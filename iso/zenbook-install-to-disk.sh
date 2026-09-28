#!/usr/bin/env bash
# ============================================================================
# zenbook-install-to-disk.sh — Install custom 7.3-rc3 kernel, DTB, firmware,
# and bootloader entry onto the target hard drive.
#
# Use cases:
#   1. In live session after Anaconda / distro installer finishes:
#        sudo zenbook-install-to-disk
#
#   2. Offline/recovery with target mounted:
#        sudo zenbook-install-to-disk /mnt
# ============================================================================
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  zenbook-install-to-disk [TARGET_ROOT]

Arguments:
  TARGET_ROOT    Mount point of target root filesystem.
                 Defaults to /mnt/sysimage (Anaconda target) or /mnt.
EOF
}

[[ ${1:-} != "-h" && ${1:-} != "--help" ]] || { usage; exit 0; }

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: must run as root (use sudo)" >&2
    exit 1
fi

target=""
if [[ $# -ge 1 ]]; then
    target=$(realpath "$1")
elif [[ -d "/mnt/sysimage/etc" ]]; then
    target="/mnt/sysimage"
elif [[ -d "/mnt/etc" ]]; then
    target="/mnt"
fi

if [[ -z "$target" || ! -d "$target/etc" ]]; then
    echo "error: target root filesystem not found at /mnt/sysimage or /mnt." >&2
    echo "Mount target root (e.g. sudo mount /dev/nvme0n1p... /mnt) and run:" >&2
    echo "  sudo zenbook-install-to-disk /mnt" >&2
    exit 1
fi

echo "Installing Zenbook A16 platform support into: $target"

KREL="${KREL:-7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "")

# 1. Install Kernel Packages / Binaries
rpm_dir=""
for candidate in \
    "/opt/zenbook-kernel" \
    "$SCRIPT_DIR/../bundle/rpms" \
    "$HOME/glymur-images/rpms" \
    "/var/opt/zenbook-kernel"; do
    if compgen -G "$candidate/kernel-*.rpm" >/dev/null 2>&1; then
        rpm_dir="$candidate"
        break
    fi
done

if [[ -n "$rpm_dir" ]]; then
    echo "Installing kernel RPMs from $rpm_dir..."
    rpm --root "$target" -ivh --force --nodeps "$rpm_dir"/kernel-*.rpm 2>/dev/null || \
        dnf --installroot="$target" install -y "$rpm_dir"/kernel-*.rpm 2>/dev/null || true
fi

# Ensure kernel Image and DTB exist in $target/boot
mkdir -p "$target/boot/glymur"

if [[ ! -s "$target/boot/vmlinuz-$KREL" ]]; then
    for candidate_vm in \
        "/boot/vmlinuz-$KREL" \
        "/vmlinuz-$KREL" \
        "/run/initramfs/live/vmlinuz-$KREL"; do
        if [[ -s "$candidate_vm" ]]; then
            echo "Copying kernel image from $candidate_vm..."
            install -Dm644 "$candidate_vm" "$target/boot/vmlinuz-$KREL"
            break
        fi
    done
fi

for candidate_dtb in \
    "/boot/glymur/$KREL.dtb" \
    "/boot/dtb-$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb" \
    "/dtbs/glymur/$KREL.dtb" \
    "/run/initramfs/live/dtbs/glymur/$KREL.dtb" \
    "$target/lib/modules/$KREL/dtb/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb"; do
    if [[ -s "$candidate_dtb" ]]; then
        echo "Installing A16 DTB from $candidate_dtb..."
        install -Dm644 "$candidate_dtb" "$target/boot/glymur/$KREL.dtb"
        break
    fi
done

if [[ ! -d "$target/lib/modules/$KREL" && -d "/lib/modules/$KREL" ]]; then
    echo "Copying kernel modules from live environment..."
    mkdir -p "$target/lib/modules"
    cp -a "/lib/modules/$KREL" "$target/lib/modules/"
fi

# 2. Install Firmware
echo "Updating firmware in $target/lib/firmware..."
mkdir -p "$target/lib/firmware"
for fw_sub in "ath12k/QCC2072" "qca" "qcom/glymur"; do
    if [[ -d "/lib/firmware/$fw_sub" ]]; then
        mkdir -p "$target/lib/firmware/$(dirname "$fw_sub")"
        cp -a "/lib/firmware/$fw_sub" "$target/lib/firmware/$(dirname "$fw_sub")/"
    fi
done

# 3. Install Power and Stability Tweaks
echo "Installing platform tweaks and power settings..."
mkdir -p "$target/etc/modules-load.d" \
         "$target/etc/tmpfiles.d" \
         "$target/etc/systemd/logind.conf.d" \
         "$target/usr/lib/systemd/system-sleep" \
         "$target/usr/local/bin"

if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT/tweaks" ]]; then
    install -Dm644 "$REPO_ROOT/tweaks/etc/modules-load.d/battery-baseline.conf" \
        "$target/etc/modules-load.d/battery-baseline.conf" 2>/dev/null || true
    install -Dm644 "$REPO_ROOT/tweaks/etc/tmpfiles.d/glymur-s2idle.conf" \
        "$target/etc/tmpfiles.d/glymur-s2idle.conf" 2>/dev/null || true
    install -Dm644 "$REPO_ROOT/tweaks/etc/systemd/logind.conf.d/99-glymur-suspend.conf" \
        "$target/etc/systemd/logind.conf.d/99-glymur-suspend.conf" 2>/dev/null || true
    install -Dm755 "$REPO_ROOT/tweaks/usr/lib/systemd/system-sleep/glymur-resume-guard" \
        "$target/usr/lib/systemd/system-sleep/glymur-resume-guard" 2>/dev/null || true
    install -Dm755 "$REPO_ROOT/tweaks/usr/local/bin/glymur-cpu-profile.sh" \
        "$target/usr/local/bin/glymur-cpu-profile.sh" 2>/dev/null || true
fi

# Mask TPM devices to avoid firmware lockups
mkdir -p "$target/etc/systemd/system"
ln -sf /dev/null "$target/etc/systemd/system/dev-tpm0.device" 2>/dev/null || true
ln -sf /dev/null "$target/etc/systemd/system/dev-tpmrm0.device" 2>/dev/null || true

# 4. Initramfs
if [[ ! -s "$target/boot/initramfs-$KREL.img" ]]; then
    if [[ -s "/boot/initramfs-$KREL.img" ]]; then
        echo "Copying initramfs from live environment..."
        cp -a "/boot/initramfs-$KREL.img" "$target/boot/initramfs-$KREL.img"
    elif [[ -x "$target/usr/bin/dracut" ]]; then
        echo "Generating initramfs with dracut..."
        chroot "$target" dracut --force --no-hostonly --kver "$KREL" "/boot/initramfs-$KREL.img" 2>/dev/null || true
    fi
fi

# 5. Bootloader Configuration
echo "Configuring bootloader..."
CMDLINE_EXTRA="rw clk_ignore_unused pd_ignore_unused cma=128M glymur_pci_skip=5 console=tty0 ignore_loglevel rd.timeout=60 panic=10 systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device selinux=0 modprobe.blacklist=i2c_qcom_cci,qcom_camss,ov02c10"

root_uuid=""
if command -v blkid >/dev/null 2>&1; then
    target_dev=$(findmnt -n -o SOURCE "$target" 2>/dev/null || true)
    if [[ -n "$target_dev" ]]; then
        root_uuid=$(blkid -s UUID -o value "$target_dev" 2>/dev/null || true)
    fi
fi

root_spec="root=LABEL=fedora"
if [[ -n "$root_uuid" ]]; then
    root_spec="root=UUID=$root_uuid"
fi

if [[ -d "$target/etc/grub.d" ]]; then
    echo "Creating GRUB menu entry in $target/etc/grub.d/40_zenbook_a16..."
    cat > "$target/etc/grub.d/40_zenbook_a16" <<EOF
#!/bin/sh
exec tail -n +3 \$0
# ASUS Zenbook A16 7.3-rc3 custom kernel entry
insmod part_gpt
insmod ext2
insmod btrfs
insmod fat
insmod fdt

menuentry "Fedora (ASUS Zenbook A16 7.3-rc3)" --id zenbook-a16-custom {
    devicetree /boot/glymur/$KREL.dtb
    linux /boot/vmlinuz-$KREL $root_spec $CMDLINE_EXTRA
    if [ -f /boot/initramfs-$KREL.img ]; then
        initrd /boot/initramfs-$KREL.img
    fi
}
EOF
    chmod 755 "$target/etc/grub.d/40_zenbook_a16"

    if [[ -x "$target/usr/sbin/grub2-mkconfig" ]]; then
        echo "Running grub2-mkconfig in target..."
        chroot "$target" grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
        chroot "$target" grub2-set-default zenbook-a16-custom 2>/dev/null || true
    fi
fi

for bls_dir in "$target/boot/loader/entries" "$target/boot/efi/loader/entries"; do
    if [[ -d "$bls_dir" ]]; then
        echo "Creating BLS entry in $bls_dir..."
        cat > "$bls_dir/zenbook-a16-$KREL.conf" <<EOF
title      ASUS Zenbook A16 (7.3-rc3)
version    $KREL
linux      /vmlinuz-$KREL
initrd     /initramfs-$KREL.img
devicetree /dtbs/glymur/$KREL.dtb
options    $root_spec $CMDLINE_EXTRA
EOF
    fi
done

cat <<EOF

============================================================
 Installation complete!
 Kernel:     $KREL
 Devicetree: /boot/glymur/$KREL.dtb
 Target:     $target
============================================================
You can now safely unmount the target and reboot your laptop.
EOF
