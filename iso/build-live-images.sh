#!/usr/bin/env bash
# ============================================================================
# LIVE images for the ASUS Zenbook A16 (glymur) — compressed root, RAM overlay.
#
# Why this exists, and why it replaces legacy raw-image builders for USB use:
#
#   A raw disk image with an uncompressed ext4 root has major drawbacks on a USB stick:
#     - `dd` writes the full 14 GB no matter how well the .gz compresses, so
#       flashing takes ~half an hour
#     - every read at runtime is uncompressed I/O straight off USB
#     - every write lands on the stick, so it wears and it is slow
#
#   This builder instead produces an image sized to its CONTENT (~3 GB), whose
#   root is a compressed squashfs mounted read-only with a tmpfs overlay on
#   top. Reads decompress from RAM cache, writes go to RAM, the stick is only
#   touched at boot.
#
# Layout produced:
#     p1  ESP  vfat   bootloader, kernel, live initramfs, DTB, loader entry
#     p2  ext4 LABEL=GLYMURLIVE   LiveOS/squashfs.img   (the compressed root)
#
#   ext4 for p2 rather than one big vfat because FAT32 caps a single file at
#   4 GB and a full desktop squashfs can exceed that.
#
# The live initramfs must carry dracut's dmsquash-live module; build it on the
# A16 (matching kernel) with:
#     dracut --force --no-hostonly --add dmsquash-live --kver "$KREL" \
#       --kmoddir "$STAGE/modules/$KREL" out.img
#
# Run as root:  sudo -E bash build-live-images.sh [--fedora] [--ubuntu] [--arch] [--all]
# ============================================================================
set -Eeuo pipefail

KREL="${KREL:-7.3.0-rc5-glymur-rc5-20261013}"
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
  [ -f "$VM" ]         || { say "MISSING kernel: $VM"; bad=1; }
  [ -f "$LIVEINITRD" ] || { say "MISSING live initramfs: $LIVEINITRD"; bad=1; }
  [ -f "$DTB" ]        || { say "MISSING dtb: $DTB"; bad=1; }
  [ -f "$SB" ]         || { say "MISSING systemd-bootaa64.efi: $SB"; bad=1; }
  [ -d "$MODS/$KREL" ] || { say "MISSING modules: $MODS/$KREL"; bad=1; }
  local firmware_file
  for firmware_file in \
    qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn \
    qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf \
    qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn \
    qcom/glymur/ASUSTeK/UX3607OA/cdsp_dtbs.elf \
    qcom/glymur/ASUSTeK/UX3607OA-tplg.bin; do
    local fw_alts=("$firmware_file")
    if [[ "$firmware_file" == *"UX3607OA-tplg.bin"* ]]; then
      fw_alts+=("qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin")
    fi
    local fw_found=0
    for cand in "${fw_alts[@]}"; do
      if [ -s "$FW/$cand" ] || [ -s "$FW/$cand.xz" ] || [ -s "$FW/$cand.zst" ]; then
        fw_found=1
        break
      fi
    done
    if [ "$fw_found" -eq 0 ]; then
      say "MISSING firmware: $FW/$firmware_file"; bad=1
    fi
  done
  # A hostonly initramfs carries only the drivers the BUILD host happened to need,
  # so an image built on an ext4 box silently fails to mount a btrfs (or xfs, or
  # LVM) root on anyone else's machine -- it boots for us and for nobody else.
  # dracut's default is hostonly=yes, so this is the easy mistake, and it is
  # invisible until a stranger writes the stick. btrfs.ko is the canary: absent
  # from a hostonly build on an ext4 host, present in any --no-hostonly build.
  # (Learned the hard way 2026-08-08: converting loazen's root ext4->btrfs left
  # its installed initramfs with the btrfs *userspace* but no btrfs.ko, which
  # would have dropped the box into a dracut emergency shell on first boot.)
  if [ -f "$LIVEINITRD" ]; then
    if command -v lsinitrd >/dev/null; then
      local ls_out; ls_out=$(lsinitrd "$LIVEINITRD" 2>/dev/null)
      grep -q 'btrfs\.ko'   <<<"$ls_out" || { say "LIVE INITRAMFS looks HOSTONLY (no btrfs.ko) -- see iso/README.md"; bad=1; }
      grep -q 'dmsquash'    <<<"$ls_out" || { say "LIVE INITRAMFS lacks dmsquash-live -- it cannot find LiveOS/squashfs.img"; bad=1; }
    else
      say "WARN: lsinitrd unavailable -- cannot verify $LIVEINITRD is generic (--no-hostonly) or carries dmsquash-live"
    fi
  fi

  for c in mksquashfs parted losetup mkfs.vfat mkfs.ext4 blkid; do
    command -v "$c" >/dev/null || { say "MISSING TOOL: $c"; bad=1; }
  done
  [ "$(id -u)" -eq 0 ] || { say "must run as root"; bad=1; }
  return $bad
}

addmods(){ mkdir -p "$1/lib/modules"; cp -a "$MODS/$KREL" "$1/lib/modules/" || return 1
           rm -rf "$1/lib/modules/$KREL/build" "$1/lib/modules/$KREL/source"; }
addfw(){
  local root=$1
  mkdir -p "$root/lib/firmware"
  [ -d "$FW/ath12k" ] && cp -a "$FW/ath12k" "$root/lib/firmware/"
  [ -d "$FW/qca" ] && cp -a "$FW/qca" "$root/lib/firmware/"
  [ -d "$FW/qcom" ] && cp -a "$FW/qcom" "$root/lib/firmware/"
  [ -d "$FW/audio" ] && cp -a "$FW/audio" "$root/lib/firmware/"
  if [ -s "$REPO/firmware/audioreach/UX3607OA-tplg.bin" ]; then
    install -Dm644 "$REPO/firmware/audioreach/UX3607OA-tplg.bin" \
      "$root/lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/UX3607OA-tplg.bin"
    install -Dm644 "$REPO/firmware/audioreach/UX3607OA-tplg.bin" \
      "$root/lib/firmware/qcom/glymur/ASUSTeK/UX3607OA-tplg.bin"
  fi
}

stage_bundle_rootfs(){
  local rd="$1"
  local bdir="$rd/usr/share/zenbook-a16/bundle"
  mkdir -p "$bdir"
  [ -f "$VM" ] && cp -p "$VM" "$bdir/vmlinuz-$KREL"
  local dtb_dest="$bdir/glymur-asus-zenbook-a16-ux3607oa.dtb"
  [ -f "$DTB" ] && cp -p "$DTB" "$dtb_dest"
  ln -sf "glymur-asus-zenbook-a16-ux3607oa.dtb" "$bdir/$KREL.dtb" 2>/dev/null || true
  if [ -d "$MODS/$KREL" ]; then
    mkdir -p "$bdir/modules"
    cp -a "$MODS/$KREL" "$bdir/modules/"
    mkdir -p "$bdir/lib/modules"
    ln -sfn "../../modules/$KREL" "$bdir/lib/modules/$KREL" 2>/dev/null || true
    printf '1\n' > "$bdir/modules/$KREL/omarchy-a16-dsp-abi"
    printf '1\n' > "$bdir/modules/$KREL/zenbook-a16-dsp-abi"
  fi
  mkdir -p "$bdir/usr/share/doc/linux-zenbook-a16"
  printf '%s\n' "$KREL" > "$bdir/usr/share/doc/linux-zenbook-a16/kernel-release"
  if [ -d "$FW" ]; then
    mkdir -p "$bdir/firmware"
    cp -a "$FW"/* "$bdir/firmware/" 2>/dev/null || true
  fi
  if [ -d "$REPO/tweaks" ]; then
    mkdir -p "$bdir/tweaks"
    cp -a "$REPO/tweaks"/* "$bdir/tweaks/" 2>/dev/null || true
  fi
  if [ -d "$REPO/packaging/zenbook-a16-hooks" ]; then
    mkdir -p "$bdir/packaging/zenbook-a16-hooks"
    cp -a "$REPO/packaging/zenbook-a16-hooks"/* "$bdir/packaging/zenbook-a16-hooks/" 2>/dev/null || true
  fi
  if [ -d "$REPO/packaging/omarchy-a16-support" ]; then
    mkdir -p "$bdir/packaging/omarchy-a16-support"
    cp -a "$REPO/packaging/omarchy-a16-support"/* "$bdir/packaging/omarchy-a16-support/" 2>/dev/null || true
  fi
  if [ -d "$STAGE/rpms" ]; then
    mkdir -p "$bdir/rpms"
    cp -a "$STAGE/rpms"/* "$bdir/rpms/" 2>/dev/null || true
  fi
  if [ -d "$STAGE/debs" ]; then
    mkdir -p "$bdir/debs"
    cp -a "$STAGE/debs"/* "$bdir/debs/" 2>/dev/null || true
  fi
}

add_installer(){
  local rd="$1"
  mkdir -p "$rd/usr/local/bin" "$rd/opt/zenbook-kernel" "$rd/usr/share/applications"
  cp -a "$REPO/iso/zenbook-install-to-disk.sh" "$rd/usr/local/bin/zenbook-install-to-disk"
  chmod 755 "$rd/usr/local/bin/zenbook-install-to-disk"

  if [ -d "$STAGE/rpms" ]; then
    cp -a "$STAGE/rpms/"*.rpm "$rd/opt/zenbook-kernel/" 2>/dev/null || true
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
      chmod 755 "$rd/home/$u/Desktop/zenbook-install.desktop" 2>/dev/null || true
    fi
  done
}
add_power_tweaks(){
  local rd="$1" src="$REPO/tweaks"
  install -Dm644 "$src/etc/modules-load.d/battery-baseline.conf" "$rd/etc/modules-load.d/battery-baseline.conf" || return 1
  install -Dm644 "$src/etc/tmpfiles.d/glymur-s2idle.conf" "$rd/etc/tmpfiles.d/glymur-s2idle.conf" || return 1
  install -Dm644 "$src/etc/systemd/logind.conf.d/99-glymur-suspend.conf" "$rd/etc/systemd/logind.conf.d/99-glymur-suspend.conf" || return 1
  install -Dm755 "$src/usr/lib/systemd/system-sleep/glymur-resume-guard" "$rd/usr/lib/systemd/system-sleep/glymur-resume-guard" || return 1
  install -Dm755 "$src/usr/local/bin/glymur-cpu-profile.sh" "$rd/usr/local/bin/glymur-cpu-profile.sh" || return 1
  mkdir -p "$rd/etc/tuned/profiles"
  cp -a "$src/etc/tuned/profiles/glymur-balanced" "$src/etc/tuned/profiles/glymur-performance" "$src/etc/tuned/profiles/glymur-powersave" "$rd/etc/tuned/profiles/" || return 1
  if [ -d "$src/usr/share/alsa/ucm2" ]; then
    mkdir -p "$rd/usr/share/alsa/ucm2"
    cp -a "$src/usr/share/alsa/ucm2"/* "$rd/usr/share/alsa/ucm2/" 2>/dev/null || true
  fi
}

# $1 = rootfs dir, $2 = output name
mklive(){
  # NB: separate `local` statements. Bash expands every word on a `local` line
  # before performing any of the assignments, so referring to $NAME on the same
  # line as NAME="$2" is an unbound variable under `set -u`.
  local RD="$1" NAME="$2"
  local SQ="$STAGE/$NAME.squashfs" IMG="$STAGE/$NAME.img"
  local SQMB IMGMB LOOP MNT

  # The rootfs still carries the source distro's /etc/fstab (and friends),
  # which reference partitions that do not exist on a live stick. Left in
  # place, systemd-remount-fs fails at boot ("Remount Root and Kernel File
  # Systems") because it tries to remount / per an fstab entry for a device
  # that is not there. A live root comes from the overlay, so the file should
  # be empty -- this is what distro live images ship.
  say "$NAME: neutralising fstab/crypttab/resume for live boot"
  printf '# live image: root comes from the dmsquash-live overlay\n' > "$RD/etc/fstab"
  : > "$RD/etc/crypttab" 2>/dev/null || true
  rm -f "$RD/etc/dracut.conf.d/"*resume* 2>/dev/null || true
  # a stale machine-id makes every live stick share an identity; let it regenerate
  : > "$RD/etc/machine-id" 2>/dev/null || true

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
  GLYMUROPTS="rw clk_ignore_unused pd_ignore_unused cma=128M glymur_pci_skip=5 console=tty0 ignore_loglevel rd.timeout=60 panic=10 systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device"

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
  say "FEDORA: reusing extracted rootfs"
  addmods "$SQD" || return 1
  addfw "$SQD" || return 1
  add_power_tweaks "$SQD" || return 1
  bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$SQD" --distro fedora || return 1
  stage_bundle_rootfs "$SQD" || return 1
  add_installer "$SQD" || return 1
  mklive "$SQD" "fedora-glymur-kde-live"
}

build_arch(){
  say "ARCH(Manjaro) live: === START ==="
  local RD=$STAGE/rd_arch XZ IMG2=$STAGE/manjaro-kde.img LOOP MNT
  XZ=$(ls "$STAGE"/Manjaro-ARM-kde-plasma-generic-efi-*.img.xz 2>/dev/null | tail -1)
  [ -n "${XZ:-}" ] || { say "ARCH: FAIL no Manjaro image"; return 1; }
  if [ ! -s "$IMG2" ]; then say "ARCH: decompressing"; unxz -c "$XZ" > "$IMG2" || return 1; fi
  LOOP=$(losetup --find --show --partscan "$IMG2") || return 1
  MNT=$(mktemp -d)
  mount "${LOOP}p2" "$MNT" 2>/dev/null || mount "${LOOP}p1" "$MNT" 2>/dev/null || { losetup -d "$LOOP"; return 1; }
  rm -rf "$RD"; mkdir -p "$RD"; say "ARCH: extracting rootfs"
  cp -a "$MNT"/. "$RD"/ 2>/dev/null
  umount "$MNT"; rmdir "$MNT"; losetup -d "$LOOP"
  addmods "$RD" || return 1
  addfw "$RD" || return 1
  add_power_tweaks "$RD" || return 1
  bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$RD" --distro arch || return 1
  stage_bundle_rootfs "$RD" || return 1
  add_installer "$RD" || return 1
  mklive "$RD" "arch-manjaro-kde-live"
  rm -rf "$RD"
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
      bsdtar -xOf "$ISO" "casper/$sname" > "$SMIN" 2>/dev/null || true
      break
    fi
  done
  [ -s "$SMIN" ] || { say "UBUNTU: FAIL no minimal squashfs in $ISO"; return 1; }
  bsdtar -xOf "$ISO" casper/minimal.de.squashfs > "$SDE" 2>/dev/null || true
  rm -rf "$RD"
  unsquashfs -f -d "$RD" "$SMIN" >/dev/null 2>&1 || return 1
  [ -s "$SDE" ] && unsquashfs -f -d "$RD" "$SDE" >/dev/null 2>&1
  addmods "$RD" || return 1
  addfw "$RD" || return 1
  add_power_tweaks "$RD" || return 1
  bash "$REPO/packaging/zenbook-a16-hooks/install-hooks.sh" --root "$RD" --distro ubuntu || return 1
  stage_bundle_rootfs "$RD" || return 1
  add_installer "$RD" || return 1
  mklive "$RD" "ubuntu-glymur-gnome-live"
  rm -rf "$RD" "$SMIN" "$SDE"
}

targets=()
for arg in "$@"; do
  case "$arg" in
    --fedora|fedora) targets+=(fedora) ;;
    --ubuntu|ubuntu) targets+=(ubuntu) ;;
    --arch|arch)     targets+=(arch) ;;
    --all|all)       targets=(fedora ubuntu arch) ;;
    *) say "unknown target: $arg"; exit 1 ;;
  esac
done
if [ ${#targets[@]} -eq 0 ]; then
  targets=(fedora ubuntu arch)
fi

echo "======== LIVE RUN $(date) targets=[${targets[*]}] ========" >> "$ST"
say "kernel=$KREL  stage=$STAGE  out=$OUT"
preflight || { say "preflight failed"; exit 1; }
status=0
for t in "${targets[@]}"; do
  case "$t" in
    arch)   build_arch   || { say "ARCH: aborted"; status=1; } ;;
    fedora) build_fedora || { say "FEDORA: aborted"; status=1; } ;;
    ubuntu) build_ubuntu || { say "UBUNTU: aborted"; status=1; } ;;
    *) say "unknown target: $t"; status=1 ;;
  esac
done
say "======== LIVE RUN DONE $(date) ========"
exit "$status"
