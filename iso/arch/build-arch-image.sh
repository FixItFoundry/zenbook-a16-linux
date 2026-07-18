#!/usr/bin/env bash
# build-arch-image.sh — build a UEFI-bootable Arch Linux ARM (aarch64) disk image for the A16,
# using RAW glymur kernel artifacts (no pacman packaging needed).
#
# WHY: Arch has no aarch64 ISO. Arch Linux ARM (ALARM) ships a generic aarch64 ROOTFS TARBALL.
# Its stock kernel won't boot sm8750, so we drop in the glymur v7.1 kernel + modules + DTB and
# build a fat (non-hostonly) initramfs.
#
# YOU ALREADY HAVE THE INPUTS (in the project folder):
#   - vmlinuz:  Linux-X2-Project/vmlinuz-7.1.0-glymur-full-patched   (or the root copy)
#   - modules:  Linux-X2-Project/7.1.0-glymur-full-plus-modules.zip  (contains lib/modules/<ver>)
#   - DTB:      Linux-X2-Project/boot-kit/test55-usb.dtb
#   - ALARM:    ArchLinuxARM-aarch64-latest.tar.gz  (download: see iso/README.md)
#
# RUN in Fedora WSL as root (x86 WSL is fine for assembly; qemu-user-static + binfmt is only
# needed if you want to run arch-chroot steps — this script avoids chroot where possible).
#
#   sudo ./build-arch-image.sh \
#        ArchLinuxARM-aarch64-latest.tar.gz \
#        vmlinuz-7.1.0-glymur-full-patched \
#        7.1.0-glymur-full-plus-modules.zip \
#        glymur-a16-test55-usb.dtb
#
set -euo pipefail
ALARM_TAR="${1:?path to ArchLinuxARM-aarch64-latest.tar.gz}"
VMLINUZ="${2:?path to vmlinuz-7.1.0-glymur-full-patched}"
MODULES="${3:?path to modules (a .zip containing lib/modules/<ver>, or an already-unpacked dir)}"
DTB="${4:?path to glymur-a16-test55-usb.dtb}"
IMG="${IMG:-arch-glymur-a16-aarch64.img}"
SIZE_GB="${SIZE_GB:-12}"
KVER="${KVER:-7.1.0-glymur-full}"   # module dir name under lib/modules/

[ "$(id -u)" = 0 ] || { echo "run as root (loop mounts + mkfs)"; exit 1; }
for t in parted mkfs.vfat mkfs.ext4 losetup bsdtar; do
  command -v "$t" >/dev/null || { echo "missing tool: $t (install: dosfstools e2fsprogs parted libarchive/bsdtar)"; exit 1; }
done

WORK="$(mktemp -d)"; MNT="$WORK/mnt"; mkdir -p "$MNT"
cleanup(){ set +e; umount "$MNT/boot" 2>/dev/null; umount "$MNT" 2>/dev/null; [ -n "${LOOP:-}" ] && losetup -d "$LOOP" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

echo "== 1. image + GPT (ESP + root) =="
rm -f "$IMG"; truncate -s "${SIZE_GB}G" "$IMG"
parted -s "$IMG" mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB set 1 esp on \
  mkpart root ext4 1025MiB 100%
LOOP="$(losetup --find --show --partscan "$IMG")"
mkfs.vfat -F32 -n GLYMUR_ESP "${LOOP}p1" >/dev/null
mkfs.ext4 -F -L glymur-root "${LOOP}p2" >/dev/null
mount "${LOOP}p2" "$MNT"; mkdir -p "$MNT/boot"; mount "${LOOP}p1" "$MNT/boot"

echo "== 2. unpack ALARM aarch64 rootfs =="
bsdtar -xpf "$ALARM_TAR" -C "$MNT"

echo "== 3. drop in glymur kernel + modules + DTB (raw, no pacman) =="
# systemd-boot chainloads the kernel as an EFI binary and CANNOT read a gzip-compressed
# vmlinuz. The arm64 kernel carries the EFI stub, so the *decompressed* Image is a valid EFI
# application. Decompress if needed.
mkdir -p "$MNT/boot"
if file "$VMLINUZ" | grep -qi gzip; then
  echo "   vmlinuz is gzip-compressed -> decompressing to an EFI-stub Image"
  zcat "$VMLINUZ" > "$MNT/boot/vmlinuz-glymur"
else
  cp -f "$VMLINUZ" "$MNT/boot/vmlinuz-glymur"
fi
chmod 644 "$MNT/boot/vmlinuz-glymur"
mkdir -p "$MNT/lib/modules"
# IMPORTANT: a packaged modules tree usually contains a huge kernel BUILD tree under
# <ver>/build (full source + .o objects, several GB) and sometimes <ver>/source. Those are
# only for compiling out-of-tree modules and are NOT needed at runtime — copying them blows
# past the image size. We EXCLUDE them at unpack time and prune any that slip through.
case "$MODULES" in
  *.zip) command -v unzip >/dev/null || { echo "need unzip for the modules .zip"; exit 1; }
         echo "   unzipping modules (excluding build/ and source/ kernel tree)..."
         unzip -q -o "$MODULES" -x '*/build/*' '*/source/*' -d "$WORK/mod"
         MODSRC="$(find "$WORK/mod" -type d -name "${KVER}*" -path '*modules*' -print -quit || true)"
         [ -n "$MODSRC" ] || MODSRC="$(find "$WORK/mod" -type d -name "${KVER}*" -print -quit)"
         [ -n "$MODSRC" ] || { echo "couldn't find lib/modules/${KVER}* inside $MODULES"; exit 1; }
         cp -a "$MODSRC" "$MNT/lib/modules/" ;;
  *)     command -v rsync >/dev/null \
           && rsync -a --exclude=build --exclude=source "$MODULES/" "$MNT/lib/modules/" \
           || { cp -a "$MODULES/." "$MNT/lib/modules/"; } ;;
esac
KREAL="$(basename "$(find "$MNT/lib/modules" -maxdepth 1 -mindepth 1 -type d -name "${KVER}*" | head -1)")"
# prune the build/source trees (symlinks or real dirs) in case any slipped through
rm -rf "$MNT/lib/modules/$KREAL/build" "$MNT/lib/modules/$KREAL/source"
echo "   installed modules: $KREAL ($(du -sh "$MNT/lib/modules/$KREAL" 2>/dev/null | cut -f1))"
mkdir -p "$MNT/boot/dtbs/glymur"
install -Dm644 "$DTB" "$MNT/boot/dtbs/glymur/glymur-a16-test55-usb.dtb"

echo "== 4. initramfs =="
# BEST PATH (recommended): reuse a known-good fat initramfs via  INITRD=/path.
# The A16's own /boot/initrd.img-7.1.0-glymur-full is kernel-matched, hardware-proven, and
# distro-agnostic (it mounts root=UUID and switch_roots), so it boots the Arch rootfs fine.
# This sidesteps fragile mkinitcpio-under-emulation entirely.
if [ -n "${INITRD:-}" ] && [ -f "$INITRD" ]; then
  echo "  using prebuilt initramfs: $INITRD"
  cp "$INITRD" "$MNT/boot/initramfs-glymur.img"
  echo "  initramfs: OK ($(du -h "$MNT/boot/initramfs-glymur.img" | cut -f1))"
else
  echo "  no INITRD= supplied -> building with mkinitcpio under emulation"
  BINFMT_OK=0; [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] && BINFMT_OK=1
  # Portable (all-modules) initramfs: DROP 'autodetect' (it trims modules to the emulated build
  # host) and force qcom boot-critical + USB/NVMe storage modules. NOTE: mkinitcpio has NO
  # '--no-hostonly' flag (that's dracut); omitting autodetect is the mkinitcpio equivalent.
  sed -i -E 's/^HOOKS=.*/HOOKS=(base udev modconf block keyboard filesystems fsck)/' "$MNT/etc/mkinitcpio.conf" || true
  sed -i -E 's/^MODULES=.*/MODULES=(nvme nvme_core phy_qcom_qmp_pcie pcie_qcom i2c_qcom_geni qcom_pdc xhci_hcd xhci_pci usb_storage ext4)/' "$MNT/etc/mkinitcpio.conf" || true

  # Build to the ext4 ROOT (always host-visible), then copy onto the ESP. Under systemd-nspawn
  # the ESP submount at /boot is NOT visible in the container, so writing straight to /boot would
  # land on the wrong filesystem — build to / then copy.
  run_mkinitcpio(){
    if command -v arch-chroot >/dev/null 2>&1; then arch-chroot "$MNT" mkinitcpio -k "$KREAL" -g /glymur-initramfs.img; return $?; fi
    if command -v systemd-nspawn >/dev/null 2>&1; then systemd-nspawn --quiet -D "$MNT" mkinitcpio -k "$KREAL" -g /glymur-initramfs.img; return $?; fi
    for m in proc sys dev; do mount --bind "/$m" "$MNT/$m"; done
    chroot "$MNT" mkinitcpio -k "$KREAL" -g /glymur-initramfs.img; local rc=$?
    for m in dev sys proc; do umount "$MNT/$m" 2>/dev/null; done
    return $rc
  }
  if [ "$BINFMT_OK" = 1 ] && run_mkinitcpio && [ -s "$MNT/glymur-initramfs.img" ]; then
    cp "$MNT/glymur-initramfs.img" "$MNT/boot/initramfs-glymur.img"; rm -f "$MNT/glymur-initramfs.img"
    echo "  initramfs: OK ($(du -h "$MNT/boot/initramfs-glymur.img" | cut -f1))"
  else
    echo "  !! initramfs NOT built (no binfmt, or mkinitcpio failed under emulation)."
    echo "  !! Recommended: re-run with a prebuilt one from the A16:"
    echo "  !!   scp jcasco@loazen:/boot/initrd.img-7.1.0-glymur-full /mnt/c/Users/jesse/Downloads/"
    echo "  !!   INITRD=/mnt/c/Users/jesse/Downloads/initrd.img-7.1.0-glymur-full  <re-run build>"
  fi
fi

echo "== 5. bootloader: systemd-boot + mandatory cmdline =="
ROOT_UUID="$(blkid -s UUID -o value "${LOOP}p2")"
mkdir -p "$MNT/boot/loader/entries"
cat > "$MNT/boot/loader/loader.conf" <<EOF
default glymur.conf
timeout 3
EOF
# DTB must be a systemd-boot 'devicetree' KEY (not a kernel arg). Cmdline mirrors the A16's
# known-good GRUB entry for test55-usb (mdss off, msm blacklisted, simplefb, pKVM).
cat > "$MNT/boot/loader/entries/glymur.conf" <<EOF
title      Arch Linux ARM (glymur A16 / test55-usb)
linux      /vmlinuz-glymur
initrd     /initramfs-glymur.img
devicetree /dtbs/glymur/glymur-a16-test55-usb.dtb
options    root=UUID=$ROOT_UUID rw clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime arm64.nopauth console=tty0 ignore_loglevel modprobe.blacklist=msm rd.timeout=60 panic=10 softlockup_panic=1 kvm-arm.mode=protected
EOF
# Install the systemd-boot EFI binary if available (else install bootctl on the A16 later).
if [ -f "$MNT/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" ]; then
  mkdir -p "$MNT/boot/EFI/BOOT" "$MNT/boot/EFI/systemd"
  cp "$MNT/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$MNT/boot/EFI/systemd/systemd-bootaa64.efi"
  cp "$MNT/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$MNT/boot/EFI/BOOT/BOOTAA64.EFI"
else
  echo "!! systemd-boot EFI stub not found in rootfs; run 'bootctl install' on the A16 first boot."
fi

echo "== 6. minimal first-boot sanity (root pw, fstab) =="
printf 'UUID=%s / ext4 rw,relatime 0 1\n' "$ROOT_UUID" >> "$MNT/etc/fstab"
printf 'UUID=%s /boot vfat rw,relatime 0 2\n' "$(blkid -s UUID -o value "${LOOP}p1")" >> "$MNT/etc/fstab"
# ALARM default user is alarm/alarm, root/root. Change on first boot.

sync
echo
echo "DONE -> $IMG"
echo "Write to USB:  sudo dd if=$IMG of=/dev/sdX bs=4M status=progress conv=fsync"
echo "Then boot the A16 from that USB. Firmware (Wi-Fi/audio/etc.) must be present under"
echo "/lib/firmware/qcom/glymur/ — copy from your own device (see firmware/README.md)."
echo
echo "If mkinitcpio couldn't run here, generate the initramfs on the A16:"
echo "  mkinitcpio -k $KREAL -g /boot/initramfs-glymur.img --no-hostonly"
