#!/usr/bin/env bash
# Build Fedora/Ubuntu live media with a compressed root and RAM overlay.
# p1: FAT ESP with boot artifacts; p2: ext4 GLYMURLIVE with LiveOS/squashfs.img.
# ext4 permits squashfs images larger than FAT32's 4 GiB limit.
# Supply a non-host-only dracut initramfs with dmsquash-live and the A16 DSP hook.
# Run as root: sudo -E bash build-live-images.sh [fedora|ubuntu|--all]
set -Eeuo pipefail

KREL="${KREL:-7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+}"
STAGE="${STAGE:-$HOME/glymur-images}"
OUT="${OUT:-$STAGE/out-live}"

VM="${VM:-$STAGE/vmlinuz-$KREL}"
LIVEINITRD="${LIVEINITRD:-$STAGE/initramfs-live-$KREL.img}"
DTB="${DTB:-$STAGE/$KREL.dtb}"
MODS="${MODS:-$STAGE/modules}"
FW="${FW:-$STAGE/firmware}"
SB="${SB:-$STAGE/systemd-bootaa64.efi}"
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# zstd decompresses far faster than xz, which is what matters when the root is
# read live off a stick. -Xcompression-level 15 is a good size/speed tradeoff.
COMP="${COMP:--comp zstd -Xcompression-level 15}"
LABEL=GLYMURLIVE
ST="$STAGE/LIVE-STATUS.txt"

say(){ echo "[$(date '+%m-%d %H:%M:%S')] $*"; echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$ST"; }

preflight(){
  mkdir -p "$STAGE" "$OUT"
  local bad=0
  for distro in "${targets[@]}"; do
    bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$STAGE" --distro "$distro" --check || bad=1
  done
  local support_root
  support_root=$(mktemp -d) || return 1
  bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$support_root" --distro fedora || bad=1
  python3 "$REPO/packaging/omarchy-a16-support/verify-boot.py" --validate-kernel \
    --root "$support_root" --initramfs-image "$LIVEINITRD" \
    --modules-dir "$MODS/$KREL" --kernel-release "$KREL" --kernel-image "$VM" --dtb-image "$DTB" || bad=1
  rm -rf "$support_root" || bad=1
  [[ "$(uname -m)" == aarch64 ]] || { say "build on native aarch64 Linux"; bad=1; }
  [ -f "$VM" ]         || { say "MISSING kernel: $VM"; bad=1; }
  [ -f "$LIVEINITRD" ] || { say "MISSING live initramfs: $LIVEINITRD"; bad=1; }
  [ -f "$DTB" ]        || { say "MISSING dtb: $DTB"; bad=1; }
  [ -f "$SB" ]         || { say "MISSING systemd-bootaa64.efi: $SB"; bad=1; }
  [ -d "$MODS/$KREL" ] || { say "MISSING modules: $MODS/$KREL"; bad=1; }
  DEST="$FW" bash "$REPO/iso/glymur-fetch-firmware.sh" --check || bad=1
  # A host-only image can omit filesystems needed on the target; check btrfs as a canary.
  if [ -f "$LIVEINITRD" ]; then
    if command -v lsinitrd >/dev/null; then
      local ls_out; ls_out=$(lsinitrd "$LIVEINITRD") || { say "cannot read live initramfs"; bad=1; }
      grep -q 'btrfs\.ko'   <<<"$ls_out" || { say "LIVE INITRAMFS looks HOSTONLY (no btrfs.ko) -- see iso/README.md"; bad=1; }
      grep -q 'dmsquash'    <<<"$ls_out" || { say "LIVE INITRAMFS lacks dmsquash-live -- it cannot find LiveOS/squashfs.img"; bad=1; }
    else
      say "MISSING TOOL: lsinitrd -- cannot verify live initramfs"; bad=1
    fi
  fi

  for c in mksquashfs parted losetup mkfs.vfat mkfs.ext4 blkid python3 dtc fdtget mountpoint mount umount chroot; do
    command -v "$c" >/dev/null || { say "MISSING TOOL: $c"; bad=1; }
  done
  if [[ " ${targets[*]} " == *" ubuntu "* ]]; then
    for c in bsdtar unsquashfs; do
      command -v "$c" >/dev/null || { say "MISSING TOOL: $c"; bad=1; }
    done
  fi
  [ "$(id -u)" -eq 0 ] || { say "must run as root"; bad=1; }
  return $bad
}

addmods(){
  local destination="$1/lib/modules/$KREL"
  [[ ! -L "$destination" ]] || { say "module destination is a symlink: $destination"; return 1; }
  mkdir -p "$destination"
  cp -a "$MODS/$KREL/." "$destination/"
  rm -rf "$destination/build" "$destination/source"
}
addfw(){
  local root=$1
  mkdir -p "$root/lib/firmware"
  local sub
  for sub in ath12k qca qcom audio; do
    if [ -d "$FW/$sub" ]; then
      cp -a "$FW/$sub" "$root/lib/firmware/"
    fi
  done
}

stage_bundle_rootfs(){
  local rd="$1"
  local bdir="$rd/usr/share/zenbook-a16/bundle"
  mkdir -p "$bdir"
  install -m755 "$REPO/iso/glymur-fetch-firmware.sh" "$bdir/glymur-fetch-firmware.sh"
  [[ ! -L "$bdir/modules/$KREL" ]] || return 1
  [ -f "$VM" ] && cp -p "$VM" "$bdir/vmlinuz-$KREL"
  local dtb_dest="$bdir/glymur-asus-zenbook-a16-ux3607oa.dtb"
  [ -f "$DTB" ] && cp -p "$DTB" "$dtb_dest"
  ln -sf "glymur-asus-zenbook-a16-ux3607oa.dtb" "$bdir/$KREL.dtb"
  if [ -d "$MODS/$KREL" ]; then
    mkdir -p "$bdir/modules"
    mkdir -p "$bdir/modules/$KREL"
    cp -a "$MODS/$KREL/." "$bdir/modules/$KREL/"
    mkdir -p "$bdir/lib/modules"
    [[ ! -d "$bdir/lib/modules/$KREL" || -L "$bdir/lib/modules/$KREL" ]] || return 1
    ln -sfn "../../modules/$KREL" "$bdir/lib/modules/$KREL"
  fi
  mkdir -p "$bdir/usr/share/doc/linux-zenbook-a16"
  printf '%s\n' "$KREL" > "$bdir/usr/share/doc/linux-zenbook-a16/kernel-release"
  if [ -d "$FW" ]; then
    mkdir -p "$bdir/firmware"
    cp -a "$FW"/* "$bdir/firmware/"
  fi
  if [ -d "$REPO/tweaks" ]; then
    mkdir -p "$bdir/tweaks"
    cp -a "$REPO/tweaks"/* "$bdir/tweaks/"
  fi
  if [ -d "$REPO/packaging/zenbook-a16-hooks" ]; then
    mkdir -p "$bdir/packaging/zenbook-a16-hooks"
    cp -a "$REPO/packaging/zenbook-a16-hooks"/* "$bdir/packaging/zenbook-a16-hooks/"
  fi
  if [ -d "$REPO/packaging/omarchy-a16-support" ]; then
    mkdir -p "$bdir/packaging/omarchy-a16-support"
    cp -a "$REPO/packaging/omarchy-a16-support"/* "$bdir/packaging/omarchy-a16-support/"
  fi
  if [ -d "$STAGE/rpms" ]; then
    mkdir -p "$bdir/rpms"
    cp -a "$STAGE/rpms"/* "$bdir/rpms/"
  fi
  if [ -d "$STAGE/debs" ]; then
    mkdir -p "$bdir/debs"
    cp -a "$STAGE/debs"/* "$bdir/debs/"
  fi
}

add_installer(){
  local rd="$1"
  mkdir -p "$rd/usr/local/bin" "$rd/opt/zenbook-kernel" "$rd/usr/share/applications"
  cp -a "$REPO/iso/zenbook-install-to-disk.sh" "$rd/usr/local/bin/zenbook-install-to-disk"
  chmod 755 "$rd/usr/local/bin/zenbook-install-to-disk"

  if [ -d "$STAGE/rpms" ]; then
    cp -a "$STAGE/rpms/"*.rpm "$rd/opt/zenbook-kernel/"
  fi

  cat > "$rd/usr/share/applications/zenbook-install.desktop" <<'EOF'
[Desktop Entry]
Name=Install Zenbook A16 Kernel to Disk
Comment=Install custom 7.3 kernel, DTB, firmware, and hooks onto disk after distro installer
Exec=sudo /usr/local/bin/zenbook-install-to-disk
Icon=system-software-install
Terminal=true
Type=Application
Categories=System;
EOF
  chmod 644 "$rd/usr/share/applications/zenbook-install.desktop"
  for u in liveuser root; do
    if [ -d "$rd/home/$u/Desktop" ]; then
      cp -a "$rd/usr/share/applications/zenbook-install.desktop" "$rd/home/$u/Desktop/"
      chmod 755 "$rd/home/$u/Desktop/zenbook-install.desktop"
    fi
  done
}
add_power_tweaks(){
  local rd="$1" src="$REPO/tweaks"
  # Drop defaults from previously staged live rootfs trees, retaining repository experiments.
  rm -f "$rd/etc/systemd/logind.conf.d/99-glymur-suspend.conf" "$rd/usr/lib/systemd/system-sleep/glymur-resume-guard"
  install -Dm644 "$src/etc/modules-load.d/battery-baseline.conf" "$rd/etc/modules-load.d/battery-baseline.conf" || return 1
  install -Dm644 "$src/etc/tmpfiles.d/glymur-s2idle.conf" "$rd/etc/tmpfiles.d/glymur-s2idle.conf" || return 1
  install -Dm755 "$src/usr/local/bin/glymur-cpu-profile.sh" "$rd/usr/local/bin/glymur-cpu-profile.sh" || return 1
  mkdir -p "$rd/etc/tuned/profiles"
  cp -a "$src/etc/tuned/profiles/glymur-balanced" "$src/etc/tuned/profiles/glymur-performance" "$src/etc/tuned/profiles/glymur-powersave" "$rd/etc/tuned/profiles/" || return 1
  if [ -d "$src/usr/share/alsa/ucm2" ]; then
    mkdir -p "$rd/usr/share/alsa/ucm2"
    cp -a "$src/usr/share/alsa/ucm2"/* "$rd/usr/share/alsa/ucm2/"
  fi
}

check_live_tools(){
  local tool
  for tool in bash python3 dtc fdtget findmnt chroot mountpoint; do
    chroot "$1" /bin/sh -c 'command -v "$1" >/dev/null' sh "$tool" || {
      say "live rootfs requires native tool: $tool"
      return 1
    }
  done
}

# $1 = rootfs dir, $2 = output name
mklive(){
  # NB: separate `local` statements. Bash expands every word on a `local` line
  # before performing any of the assignments, so referring to $NAME on the same
  # line as NAME="$2" is an unbound variable under `set -u`.
  local RD="$1" NAME="$2"
  local SQ="$STAGE/$NAME.squashfs" IMG="$STAGE/$NAME.img"
  local SQMB IMGMB LOOP="" MNT=""
  local LIVEOPTS GLYMUROPTS POLICYOPTS
  trap 'if [[ -n "${MNT:-}" ]]; then
          mountpoint -q "$MNT" && umount "$MNT" || true
          rmdir "$MNT" 2>/dev/null || true
        fi
        [[ -z "${LOOP:-}" ]] || losetup -d "$LOOP" || true' EXIT

  # The rootfs still carries the source distro's /etc/fstab (and friends),
  # which reference partitions that do not exist on a live stick. Left in
  # place, systemd-remount-fs fails at boot ("Remount Root and Kernel File
  # Systems") because it tries to remount / per an fstab entry for a device
  # that is not there. A live root comes from the overlay, so the file should
  # be empty -- this is what distro live images ship.
  say "$NAME: neutralising fstab/crypttab/resume for live boot"
  printf '# live image: root comes from the dmsquash-live overlay\n' > "$RD/etc/fstab"
  : > "$RD/etc/crypttab"
  rm -f "$RD/etc/dracut.conf.d/"*resume*
  # a stale machine-id makes every live stick share an identity; let it regenerate
  : > "$RD/etc/machine-id"

  say "$NAME: squashing rootfs (zstd)"
  rm -f "$SQ"
  mksquashfs "$RD" "$SQ" $COMP -noappend -no-progress >/dev/null || { say "$NAME: FAIL mksquashfs"; return 1; }
  SQMB=$(( $(stat -c %s "$SQ") / 1048576 ))
  say "$NAME: squashfs = ${SQMB} MiB"

  # Size the image to its content: squashfs + ESP + slack. This is the whole
  # point -- a 14 GB image takes 14 GB of dd time no matter what is in it.
  IMGMB=$(( SQMB + 900 ))
  say "$NAME: creating ${IMGMB} MiB image (was 14336 MiB with the raw builder)"
  rm -f "$IMG"; truncate -s "${IMGMB}M" "$IMG"
  parted -s "$IMG" mklabel gpt \
      mkpart ESP fat32 1MiB 701MiB set 1 esp on \
      mkpart live ext4 701MiB 100%
  LOOP=$(losetup --find --show --partscan "$IMG") || { say "$NAME: FAIL losetup"; return 1; }
  mkfs.vfat -F32 -n LIVEESP "${LOOP}p1" >/dev/null
  mkfs.ext4 -F -L "$LABEL" "${LOOP}p2" >/dev/null

  MNT=$(mktemp -d)
  mount "${LOOP}p2" "$MNT" || { say "$NAME: FAIL mount p2"; losetup -d "$LOOP"; return 1; }
  mkdir -p "$MNT/LiveOS"
  cp "$SQ" "$MNT/LiveOS/squashfs.img"
  umount "$MNT"

  mount "${LOOP}p1" "$MNT" || { say "$NAME: FAIL mount p1"; losetup -d "$LOOP"; return 1; }
  mkdir -p "$MNT/EFI/BOOT" "$MNT/EFI/systemd" "$MNT/loader/entries" "$MNT/dtbs/glymur"
  cp "$SB" "$MNT/EFI/BOOT/BOOTAA64.EFI"
  cp "$SB" "$MNT/EFI/systemd/systemd-bootaa64.efi"
  cp "$VM"         "$MNT/vmlinuz-$KREL"
  cp "$LIVEINITRD" "$MNT/initramfs-$KREL.img"
  cp "$DTB"        "$MNT/dtbs/glymur/$KREL.dtb"
  printf 'default glymur-live.conf\ntimeout 10\n' > "$MNT/loader/loader.conf"

  # rd.live.image tells dracut's dmsquash-live to look for LiveOS/squashfs.img
  # on the labelled device; overlayfs=1 puts the writable layer in RAM so the
  # stick is never written to after boot.
  # Cmdline parity with the kernel entry that actually works on this laptop,
  # plus the live bits. ignore_loglevel and panic=10 were missing in the first
  # cut: without ignore_loglevel the kernel stops printing to tty0 at default
  # loglevel, so a failure shows nothing but the last permitted lines (systemd
  # BPF audit records), and without panic=10 a panic hangs instead of rebooting.
  LIVEOPTS="root=live:LABEL=$LABEL rd.live.image rd.live.overlay.overlayfs=1"
  POLICYOPTS=$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["cmdline"]))' "$MODS/$KREL/zenbook-a16-boot.json")
  GLYMUROPTS="rw $POLICYOPTS console=tty0 ignore_loglevel rd.timeout=60 panic=10 systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device"

  cat > "$MNT/loader/entries/glymur-live.conf" <<EOF
title      $NAME live (Zenbook A16)
version    $KREL
linux      /vmlinuz-$KREL
initrd     /initramfs-$KREL.img
devicetree /dtbs/glymur/$KREL.dtb
options    $LIVEOPTS $GLYMUROPTS
EOF

  # Second entry: drops to a dracut shell on failure instead of hanging, and
  # prints what the initramfs is doing. Pick this at the systemd-boot menu when
  # a boot dies with nothing useful on screen.
  cat > "$MNT/loader/entries/glymur-live-debug.conf" <<EOF
title      $NAME live DEBUG (dracut shell on failure)
version    $KREL
linux      /vmlinuz-$KREL
initrd     /initramfs-$KREL.img
devicetree /dtbs/glymur/$KREL.dtb
options    $LIVEOPTS $GLYMUROPTS rd.shell rd.debug systemd.log_level=debug
EOF

  sync; umount "$MNT"; losetup -d "$LOOP"; rmdir "$MNT"
  MNT=""; LOOP=""
  rm -f "$SQ"
  mv -f "$IMG" "$OUT/"
  say "$NAME: DONE -> $OUT/$NAME.img ($(du -h "$OUT/$NAME.img" | cut -f1)) -- dd writes only this much"
}

# --------------------------------------------------------------------------
build_fedora(){
  say "FEDORA live: === START ==="
  say "FEDORA: live boot media with bundled disk installer (see iso/README.md)"
  local SQD=$STAGE/fed_sqroot
  [ -d "$SQD/usr/bin" ] || { say "FEDORA: FAIL no extracted rootfs at $SQD"; return 1; }
  check_live_tools "$SQD"
  say "FEDORA: reusing extracted rootfs"
  addmods "$SQD"
  addfw "$SQD"
  add_power_tweaks "$SQD"
  bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$SQD" --distro fedora
  stage_bundle_rootfs "$SQD"
  add_installer "$SQD"
  mklive "$SQD" "fedora-glymur-kde-live"
}

build_ubuntu(){
  say "UBUNTU live: === START ==="
  local RD=$STAGE/rd_ubuntu ISO SMIN=$STAGE/u-min.squashfs SDE=$STAGE/u-de.squashfs
  ISO=$(ls "$STAGE"/ubuntu-*-desktop-arm64.iso 2>/dev/null | tail -1)
  [ -n "${ISO:-}" ] || { say "UBUNTU: FAIL no ISO"; return 1; }
  rm -f "$SMIN" "$SDE"
  for sname in minimal.standard.live.squashfs minimal.squashfs; do
    if bsdtar -tf "$ISO" "casper/$sname" >/dev/null 2>&1; then
      say "UBUNTU: extracting casper/$sname"
      bsdtar -xOf "$ISO" "casper/$sname" > "$SMIN"
      break
    fi
  done
  [ -s "$SMIN" ] || { say "UBUNTU: FAIL no minimal squashfs in $ISO"; return 1; }
  if bsdtar -tf "$ISO" casper/minimal.de.squashfs >/dev/null 2>&1; then
    bsdtar -xOf "$ISO" casper/minimal.de.squashfs > "$SDE"
  fi
  rm -rf "$RD"
  unsquashfs -f -d "$RD" "$SMIN" >/dev/null 2>&1
  [ -s "$SDE" ] && unsquashfs -f -d "$RD" "$SDE" >/dev/null 2>&1
  check_live_tools "$RD"
  addmods "$RD"
  addfw "$RD"
  add_power_tweaks "$RD"
  bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$RD" --distro ubuntu
  stage_bundle_rootfs "$RD"
  add_installer "$RD"
  mklive "$RD" "ubuntu-glymur-gnome-live"
  rm -rf "$RD" "$SMIN" "$SDE"
}

main(){
targets=()
for arg in "$@"; do
  case "$arg" in
    --fedora|fedora) targets+=(fedora) ;;
    --ubuntu|ubuntu) targets+=(ubuntu) ;;
    --arch|arch) echo "error: generic Arch/Limine installation is unsupported; use the packaged Omarchy workflow" >&2; exit 1 ;;
    --all|all)       targets=(fedora ubuntu) ;;
    *) echo "error: unknown target: $arg" >&2; exit 1 ;;
  esac
done
if [ ${#targets[@]} -eq 0 ]; then
  targets=(fedora ubuntu)
fi

mkdir -p "$STAGE" "$OUT"
echo "======== LIVE RUN $(date) targets=[${targets[*]}] ========" >> "$ST"
say "kernel=$KREL  stage=$STAGE  out=$OUT"
preflight || { say "preflight failed"; exit 1; }
status=0
for t in "${targets[@]}"; do
  # A separate shell keeps errexit active inside helpers while collecting status.
  if bash -Eeuo pipefail -c 'source "$1"; "build_$2"' bash "${BASH_SOURCE[0]}" "$t"; then
    :
  else
    say "$t: aborted"
    status=1
  fi
done
say "======== LIVE RUN DONE $(date) ========"
exit "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
