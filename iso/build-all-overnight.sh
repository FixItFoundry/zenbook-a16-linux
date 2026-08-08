#!/usr/bin/env bash
# ============================================================================
# Overnight builder - Arch, Fedora, Ubuntu aarch64 desktop images for the
# ASUS Zenbook A16 (UX3607OA, Snapdragon X2 Elite "glymur").
#
# Reuses each distro's stock desktop rootfs and swaps in our kernel + DTB +
# initramfs + firmware, then writes a systemd-boot entry. Each distro is
# independent (continue on failure); successes are gzipped into $OUT.
#
# Run detached:
#   setsid nohup bash build-all-overnight.sh >build-all.log 2>&1 </dev/null &
#
# ---------------------------------------------------------------------------
# 2026-08-08: rewritten for the linux-next tracking kernel.
#   - was hardcoded to a WSL layout (/mnt/c/Users/..., /home/jesse/...);
#     every path is now an overridable variable
#   - was pinned to 7.1.0-glymur-clean+ and the test55 DTB
#   - ⛔ dropped `modprobe.blacklist=msm`. The old images deliberately ran the
#     display on simple-framebuffer because msm could not light the panel.
#     It can now: eDP trains at HBR3 and the Adreno X2 renders under turnip.
#     Blacklisting msm here is what made those images software-rendered.
#   - dropped `efi=noruntime` (retired 2026-07-30) and `arm64.nopauth` /
#     `kvm-arm.mode=protected`, none of which are in the working cmdline
#   - this script does NOT need an aarch64 host. It only extracts rootfs
#     images and copies files; nothing is executed from the target rootfs.
# ============================================================================
set -u

# ---- inputs (override by exporting before running) -------------------------
KREL="${KREL:-7.2.0-rc6-ZenbookA16-20260807}"   # kernel release string
STAGE="${STAGE:-$HOME/glymur-images}"           # where the inputs live
OUT="${OUT:-$STAGE/out}"                        # where finished images land

VM="${VM:-$STAGE/vmlinuz-$KREL}"
INITRD="${INITRD:-$STAGE/initramfs-$KREL.img}"
DTB="${DTB:-$STAGE/$KREL.dtb}"                  # DTB name matches the kernel
MODS="${MODS:-$STAGE/modules}"                  # contains $MODS/$KREL/
FW="${FW:-$STAGE/firmware}"                     # ath12k/ qca/ qcom/ audio/
SIZE_GB="${SIZE_GB:-14}"

DTBNAME="$KREL.dtb"
ST="$STAGE/BUILD-STATUS.txt"

# The cmdline the A16 actually daily-drives. glymur_pci_skip=5 is the suspend
# workaround (PCI config access in dpm_suspend_noirq resets the SoC); drop it
# only if you know the kernel you staged does not need it.
CMDBASE="rw clk_ignore_unused pd_ignore_unused cma=128M glymur_pci_skip=5 console=tty0 ignore_loglevel rd.timeout=60 panic=10 systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device"

say(){ echo "[$(date '+%m-%d %H:%M:%S')] $*"; echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$ST"; }

need(){ for c in "$@"; do command -v "$c" >/dev/null || { say "MISSING TOOL: $c"; return 1; }; done; }

preflight(){
  mkdir -p "$STAGE" "$OUT"
  local bad=0
  [ -f "$VM" ]      || { say "MISSING kernel image: $VM"; bad=1; }
  [ -f "$INITRD" ]  || { say "MISSING initramfs: $INITRD"; bad=1; }
  [ -f "$DTB" ]     || { say "MISSING dtb: $DTB"; bad=1; }
  [ -d "$MODS/$KREL" ] || { say "MISSING modules: $MODS/$KREL"; bad=1; }
  [ -d "$FW" ]      || say "WARN no firmware dir ($FW) - Wi-Fi and audio will not work in the image"
  need parted losetup mkfs.vfat mkfs.ext4 blkid pigz || bad=1
  [ "$(id -u)" -eq 0 ] || { say "must run as root (loop devices, mounts)"; bad=1; }
  return $bad
}

# ---- generic: build a bootable .img from a prepared rootfs dir ----
# $1 = rootfs dir   $2 = image path   $3 = distro label
mkimg(){
  local RD="$1" IMG="$2" NAME="$3" LOOP MNT RUUID
  say "$NAME: creating image $IMG (${SIZE_GB}G)"
  rm -f "$IMG"; truncate -s "${SIZE_GB}G" "$IMG"
  parted -s "$IMG" mklabel gpt mkpart ESP fat32 1MiB 1025MiB set 1 esp on mkpart root ext4 1025MiB 100%
  LOOP=$(losetup --find --show --partscan "$IMG")
  mkfs.vfat -F32 -n ESP "${LOOP}p1" >/dev/null
  mkfs.ext4 -F -L "${NAME}root" "${LOOP}p2" >/dev/null
  MNT=$(mktemp -d)
  mount "${LOOP}p2" "$MNT"; mkdir -p "$MNT/boot"; mount "${LOOP}p1" "$MNT/boot"
  say "$NAME: copying rootfs into image"
  cp -a "$RD"/. "$MNT"/
  # the ESP is mounted at /boot; wipe any distro boot files the rootfs shipped
  rm -rf "$MNT/boot"/* 2>/dev/null || true
  mkdir -p "$MNT/boot"
  cp -f "$VM" "$MNT/boot/vmlinuz-$KREL"
  install -Dm644 "$DTB" "$MNT/boot/dtbs/glymur/$DTBNAME"
  cp -f "$INITRD" "$MNT/boot/initramfs-$KREL.img"
  RUUID=$(blkid -s UUID -o value "${LOOP}p2")
  mkdir -p "$MNT/boot/loader/entries"
  printf 'default glymur.conf\ntimeout 3\n' > "$MNT/boot/loader/loader.conf"
  cat > "$MNT/boot/loader/entries/glymur.conf" <<EOF
title      $NAME (Zenbook A16)
version    $KREL
linux      /vmlinuz-$KREL
initrd     /initramfs-$KREL.img
devicetree /dtbs/glymur/$DTBNAME
options    root=UUID=$RUUID $CMDBASE
EOF
  # systemd-boot EFI stub: prefer the rootfs's own, else a staged one
  local SB="$MNT/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
  [ -f "$SB" ] || SB="$STAGE/systemd-bootaa64.efi"
  if [ -f "$SB" ]; then
    mkdir -p "$MNT/boot/EFI/BOOT" "$MNT/boot/EFI/systemd"
    cp "$SB" "$MNT/boot/EFI/systemd/systemd-bootaa64.efi"
    cp "$SB" "$MNT/boot/EFI/BOOT/BOOTAA64.EFI"
  else
    say "$NAME: WARN no systemd-bootaa64.efi available (may not boot)"
  fi
  # fresh fstab so it matches this image's UUIDs
  printf '# Zenbook A16 image\nUUID=%s / ext4 rw,relatime 0 1\n' "$RUUID" > "$MNT/etc/fstab"
  printf 'UUID=%s /boot vfat rw,relatime 0 2\n' "$(blkid -s UUID -o value "${LOOP}p1")" >> "$MNT/etc/fstab"
  sync
  umount "$MNT/boot" "$MNT" 2>/dev/null
  losetup -d "$LOOP" 2>/dev/null
  rmdir "$MNT" 2>/dev/null
  say "$NAME: image built; compressing"
  pigz -f "$IMG"
  mv -f "$IMG.gz" "$OUT/" && say "$NAME: DONE -> $OUT/$(basename "$IMG").gz ($(du -h "$OUT/$(basename "$IMG").gz"|cut -f1))"
}

# ---- firmware into a rootfs dir ----
# Not redistributable - this copies YOUR extracted blobs. See ../firmware/README.md.
addfw(){
  local RD="$1"
  [ -d "$FW" ] || return 0
  mkdir -p "$RD/lib/firmware"
  cp -a "$FW"/ath12k "$FW"/qca "$FW"/qcom "$FW"/audio "$RD/lib/firmware/" 2>/dev/null
  cp -a "$FW"/adsp_dtb* "$RD/lib/firmware/" 2>/dev/null
  return 0
}

# ---- modules into a rootfs dir ----
addmods(){
  local RD="$1"
  mkdir -p "$RD/lib/modules"
  cp -a "$MODS/$KREL" "$RD/lib/modules/" || return 1
  rm -rf "$RD/lib/modules/$KREL/build" "$RD/lib/modules/$KREL/source"
}

# =========================== ARCH (Manjaro-KDE reuse) ===========================
# Arch has no aarch64 desktop ISO, so reuse Manjaro ARM's prebuilt KDE rootfs.
build_arch(){
  say "ARCH(Manjaro-KDE): === START ==="
  local RD=$STAGE/rd_arch XZ IMG2=$STAGE/manjaro-kde.img URL LOOP MNT
  XZ=$(ls "$STAGE"/Manjaro-ARM-kde-plasma-generic-efi-*.img.xz 2>/dev/null | tail -1)
  if [ -f "$IMG2" ] && [ "$(stat -c %s "$IMG2" 2>/dev/null || echo 0)" -gt 2000000000 ]; then
    say "ARCH: reusing already-decompressed $IMG2"
  else
    if [ -z "${XZ:-}" ] || [ ! -s "$XZ" ]; then
      URL=$(curl -fsSL https://api.github.com/repos/manjaro-arm/generic-efi-images/releases 2>/dev/null | grep -oE 'https[^"]*kde-plasma[^"]*\.img\.xz' | sort | tail -1)
      [ -n "$URL" ] || { say "ARCH: FAIL could not find Manjaro KDE url"; return 1; }
      XZ="$STAGE/$(basename "$URL")"
      say "ARCH: downloading $URL"
      curl -fL -C - -o "$XZ" "$URL" || { say "ARCH: FAIL download manjaro"; return 1; }
    fi
    say "ARCH: decompressing $XZ"
    rm -f "$IMG2"; unxz -c "$XZ" > "$IMG2" || { say "ARCH: FAIL unxz"; return 1; }
  fi
  LOOP=$(losetup --find --show --partscan "$IMG2") || { say "ARCH: FAIL losetup"; return 1; }
  MNT=$(mktemp -d)
  # root partition is the last/largest; try p2 then p1
  mount "${LOOP}p2" "$MNT" 2>/dev/null || mount "${LOOP}p1" "$MNT" 2>/dev/null || { say "ARCH: FAIL mount manjaro root"; losetup -d "$LOOP"; return 1; }
  rm -rf "$RD"; mkdir -p "$RD"
  say "ARCH: extracting Manjaro KDE rootfs"
  cp -a "$MNT"/. "$RD"/ 2>/dev/null
  umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null
  [ -d "$RD/usr/bin" ] || { say "ARCH: FAIL manjaro rootfs looks empty"; rm -rf "$RD"; return 1; }
  addmods "$RD" || { say "ARCH: FAIL staging modules"; return 1; }
  addfw "$RD"
  mkimg "$RD" "$STAGE/arch-manjaro-kde.img" "arch-manjaro"
  rm -rf "$RD" "$IMG2"
  say "ARCH(Manjaro-KDE): === END ==="
}

# =========================== FEDORA (KDE Live reuse) ===========================
build_fedora(){
  say "FEDORA(KDE-Live reuse): === START ==="
  local RD=$STAGE/rd_fedora ISO EROFS=$STAGE/fed.erofs SQD=$STAGE/fed_sqroot MNT2 RIMG
  ISO=$(ls "$STAGE"/Fedora-KDE-Desktop-Live-*.aarch64.iso 2>/dev/null | tail -1)
  [ -n "${ISO:-}" ] && [ -f "$ISO" ] || { say "FEDORA: FAIL no Fedora KDE aarch64 ISO in $STAGE"; return 1; }
  need bsdtar fsck.erofs || return 1
  say "FEDORA: extracting LiveOS/squashfs.img from $(basename "$ISO")"
  # NOTE: the file is *named* squashfs.img but Fedora 44 ships EROFS+LZMA in it.
  bsdtar -xOf "$ISO" LiveOS/squashfs.img > "$EROFS" 2>/dev/null && [ -s "$EROFS" ] || { say "FEDORA: FAIL extract erofs"; return 1; }
  rm -rf "$SQD"; mkdir -p "$SQD"
  say "FEDORA: fsck.erofs extract"
  # ⛔ --path=/ is REQUIRED. Without it fsck.erofs writes the packed inode as a
  # single ~4.6G file instead of a directory tree, and still reports success.
  fsck.erofs --extract="$SQD" --path=/ --preserve "$EROFS" >/dev/null 2>&1 || { say "FEDORA: FAIL fsck.erofs"; return 1; }
  RIMG=$(find "$SQD" -name 'rootfs.img' | head -1)
  [ -n "$RIMG" ] || { say "FEDORA: FAIL no rootfs.img inside erofs"; return 1; }
  MNT2=$(mktemp -d)
  mount -o loop,ro "$RIMG" "$MNT2" || { say "FEDORA: FAIL mount rootfs.img"; return 1; }
  rm -rf "$RD"; mkdir -p "$RD"
  say "FEDORA: copying KDE rootfs"
  cp -a "$MNT2"/. "$RD"/ 2>/dev/null
  umount "$MNT2" 2>/dev/null; rmdir "$MNT2" 2>/dev/null
  [ -d "$RD/usr/bin" ] || { say "FEDORA: FAIL rootfs empty"; rm -rf "$RD" "$SQD" "$EROFS"; return 1; }
  addmods "$RD" || { say "FEDORA: FAIL staging modules"; return 1; }
  addfw "$RD"
  mkimg "$RD" "$STAGE/fedora-glymur-kde.img" "fedora"
  rm -rf "$RD" "$SQD" "$EROFS"
  say "FEDORA(KDE-Live reuse): === END ==="
}

# =========================== UBUNTU (desktop Live reuse) ===========================
build_ubuntu(){
  say "UBUNTU(desktop-Live reuse): === START ==="
  local RD=$STAGE/rd_ubuntu ISO SMIN=$STAGE/u-min.squashfs SDE=$STAGE/u-de.squashfs
  ISO=$(ls "$STAGE"/ubuntu-*-desktop-arm64.iso 2>/dev/null | tail -1)
  [ -n "${ISO:-}" ] && [ -f "$ISO" ] || { say "UBUNTU: FAIL no ubuntu desktop arm64 ISO in $STAGE"; return 1; }
  need bsdtar unsquashfs || return 1
  say "UBUNTU: extracting casper squashfs layers from $(basename "$ISO")"
  bsdtar -xOf "$ISO" casper/minimal.squashfs > "$SMIN" 2>/dev/null && [ -s "$SMIN" ] || { say "UBUNTU: FAIL extract minimal.squashfs"; return 1; }
  bsdtar -xOf "$ISO" casper/minimal.de.squashfs > "$SDE" 2>/dev/null && [ -s "$SDE" ] || say "UBUNTU: WARN no desktop layer (base only)"
  rm -rf "$RD"
  unsquashfs -f -d "$RD" "$SMIN" >/dev/null 2>&1 || { say "UBUNTU: FAIL unsquashfs minimal"; return 1; }
  [ -s "$SDE" ] && { say "UBUNTU: overlaying desktop (GNOME) layer"; unsquashfs -f -d "$RD" "$SDE" >/dev/null 2>&1; }
  [ -d "$RD/usr/bin" ] || { say "UBUNTU: FAIL rootfs empty"; rm -rf "$RD" "$SMIN" "$SDE"; return 1; }
  addmods "$RD" || { say "UBUNTU: FAIL staging modules"; return 1; }
  addfw "$RD"
  mkimg "$RD" "$STAGE/ubuntu-glymur-gnome.img" "ubuntu"
  rm -rf "$RD" "$SMIN" "$SDE"
  say "UBUNTU(desktop-Live reuse): === END ==="
}

# ---- run selected targets (default all) ----
echo "======== RUN $(date) targets=[${*:-arch fedora ubuntu}] ========" >> "$ST"
say "kernel=$KREL  stage=$STAGE  out=$OUT"
preflight || { say "preflight failed - nothing built"; exit 1; }
for t in ${*:-arch fedora ubuntu}; do
  case "$t" in
    arch)   build_arch   || say "ARCH: aborted" ;;
    fedora) build_fedora || say "FEDORA: aborted" ;;
    ubuntu) build_ubuntu || say "UBUNTU: aborted" ;;
    *) say "unknown target: $t" ;;
  esac
done
say "======== RUN DONE $(date) ========"
