#!/usr/bin/env bash
# build-fedora-iso.sh — inject the glymur v7.1 kernel RPM + A16 DTB into a Fedora aarch64 ISO.
#
# Uses mkksiso (from lorax) to rebuild an official Fedora aarch64 INSTALLER ISO with a custom
# kickstart that installs our kernel and drops the DTB. mkksiso itself is arch-neutral, so it
# runs fine on x86 Fedora WSL.
#
# ┌─ IMPORTANT: base-ISO type ─────────────────────────────────────────────────────────────┐
# │ This kickstart path needs a NETINST / Everything (Anaconda installer) ISO, e.g.          │
# │   Fedora-Server-netinst-aarch64-*.iso  or  Fedora-Everything-netinst-aarch64-*.iso       │
# │ A *Live* ISO (e.g. Fedora-KDE-Desktop-Live-44-*.aarch64.iso) does NOT install via        │
# │ kickstart — its root is a squashfs. To put our kernel in a Live ISO you must unsquashfs   │
# │ the rootfs, drop in vmlinuz + /lib/modules + DTB, re-squash, and rebuild the ISO          │
# │ (same idea as the Ubuntu live-repack). If you have the KDE Live ISO, either grab a        │
# │ netinst ISO for this script, or use the live-rootfs edit approach.                        │
# └────────────────────────────────────────────────────────────────────────────────────────┘
#
#   sudo dnf install -y lorax          # provides mkksiso
#   ./build-fedora-iso.sh Fedora-Everything-netinst-aarch64-*.iso kernel-glymur-*.rpm glymur-a16-test55-usb.dtb
#
set -euo pipefail
BASE_ISO="${1:?path to official Fedora aarch64 ISO}"
KRPM="${2:?path to kernel-*.rpm built for v7.1}"
DTB="${3:?path to glymur-a16-test55-usb.dtb}"
OUT="${OUT:-fedora-glymur-a16-aarch64.iso}"
WORK="${WORK:-$PWD/fedora-build}"

command -v mkksiso >/dev/null || { echo "install lorax (dnf install lorax) for mkksiso"; exit 1; }
[ "$(uname -m)" = "aarch64" ] || echo "WARNING: not aarch64; ensure qemu-user-static + binfmt for any chroot steps."

rm -rf "$WORK"; mkdir -p "$WORK/extra"
cp "$KRPM" "$WORK/extra/"
cp "$DTB"  "$WORK/extra/glymur-a16-test55-usb.dtb"

cat > "$WORK/glymur.ks" <<'KS'
# Minimal kickstart: install our kernel + drop the A16 DTB, force efi=noruntime.
%packages
@core
grub2-efi-aa64
%end

%post --nochroot
mkdir -p /mnt/sysimage/boot/glymur
cp /run/install/repo/glymur-a16-test55-usb.dtb /mnt/sysimage/boot/glymur/ || true
%end

%post
# Install the custom kernel RPM shipped on the ISO.
rpm -Uvh --force /run/install/repo/kernel-glymur-*.rpm || dnf -y install /run/install/repo/kernel-glymur-*.rpm || true
# Mandatory cmdline for this firmware + point at the A16 DTB.
grubby --update-kernel=ALL --args="efi=noruntime" || true
echo 'GRUB_DTB=/boot/glymur/glymur-a16-test55-usb.dtb' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg || true
%end
KS

echo "== Rebuilding ISO with mkksiso =="
mkksiso --ks "$WORK/glymur.ks" \
        --add "$WORK/extra" \
        "$BASE_ISO" "$OUT"

ls -lh "$OUT"
echo "DONE. Attach '$OUT' to a GitHub Release; do not commit it. Firmware supplied on first boot."
