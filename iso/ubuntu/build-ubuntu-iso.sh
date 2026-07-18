#!/usr/bin/env bash
# build-ubuntu-iso.sh — build an Ubuntu aarch64 live ISO carrying the glymur v7.1 kernel + A16 DTB.
#
# RUN ON AN aarch64 HOST (the A16 works, or an arm64 VM). Requires: live-build, debootstrap,
# xorriso, mtools, dpkg-dev. Firmware is NOT bundled (supply from your own device at first boot).
#
#   sudo apt-get install -y live-build xorriso mtools dosfstools
#   ./build-ubuntu-iso.sh /path/to/linux-image-*.deb /path/to/glymur-a16-test55-usb.dtb
#
set -euo pipefail
KDEB="${1:?path to linux-image-*_arm64.deb}"
DTB="${2:?path to glymur-a16-test55-usb.dtb}"
WORK="${WORK:-$PWD/ubuntu-build}"
SUITE="${SUITE:-noble}"      # 24.04 LTS
ARCH=arm64

command -v lb >/dev/null || { echo "install live-build (apt-get install live-build)"; exit 1; }
[ "$(uname -m)" = "aarch64" ] || echo "WARNING: not aarch64; live-build will need qemu-user-static + binfmt."

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

lb config \
  --architecture "$ARCH" \
  --distribution "$SUITE" \
  --binary-images iso-hybrid \
  --bootloader grub-efi \
  --archive-areas "main restricted universe multiverse" \
  --linux-flavours none \
  --bootappend-live "boot=live components efi=noruntime"

# Ship our kernel .deb into the live system instead of the stock flavour.
mkdir -p config/packages.chroot
cp "$KDEB" config/packages.chroot/

# Stage the DTB + a hook to register a dtbloader GRUB entry.
mkdir -p config/includes.chroot/boot/glymur
cp "$DTB" config/includes.chroot/boot/glymur/glymur-a16-test55-usb.dtb

mkdir -p config/hooks/live
cat > config/hooks/live/9000-glymur.hook.chroot <<'HOOK'
#!/bin/sh
set -e
# Point the installed kernel's GRUB at the A16 DTB with the mandatory cmdline.
cat >> /etc/default/grub <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="efi=noruntime"
GRUB_DTB="/boot/glymur/glymur-a16-test55-usb.dtb"
EOF
update-grub || true
HOOK
chmod +x config/hooks/live/9000-glymur.hook.chroot

echo "== Building (sudo) =="
sudo lb build

ls -lh *.iso
echo "DONE. Attach the .iso to a GitHub Release; do not commit it. Firmware must be supplied on first boot."
