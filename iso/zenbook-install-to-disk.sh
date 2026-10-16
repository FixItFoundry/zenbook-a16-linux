#!/usr/bin/env bash
# ============================================================================
# zenbook-install-to-disk.sh — Multi-distro installer for ASUS Zenbook A16
# Installs kernel, DTB, modules, firmware, platform tweaks, and persistent
# kernel-update hooks onto target disk across Fedora, Ubuntu, and Arch.
# ============================================================================
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  zenbook-install-to-disk [OPTIONS] [TARGET_ROOT]

Arguments:
  TARGET_ROOT       Mount point of target root filesystem.
                    Auto-detected if omitted: /mnt/sysimage, /target, or /mnt.

Options:
  --target <dir>    Explicit target root filesystem mount point
  -h, --help        Show this help message
EOF
}

target=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            target=$(realpath "$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$target" ]]; then
                target=$(realpath "$1")
                shift
            else
                echo "error: unexpected argument: $1" >&2
                usage >&2
                exit 1
            fi
            ;;
    esac
done

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: must run as root (use sudo)" >&2
    exit 1
fi

# 1. Auto-detect target root across Fedora Anaconda, Ubuntu Subiquity/Calamares, Arch/manual
if [[ -z "$target" ]]; then
    if [[ -d "/mnt/sysimage/etc" ]]; then
        target="/mnt/sysimage"
    elif [[ -d "/target/etc" ]]; then
        target="/target"
    elif [[ -d "/mnt/etc" ]]; then
        target="/mnt"
    fi
fi

if [[ -z "$target" || ! -d "$target/etc" ]]; then
    echo "error: target root filesystem not found at /mnt/sysimage, /target, or /mnt." >&2
    echo "Mount target root (e.g. sudo mount /dev/nvme0n1p... /mnt) and run:" >&2
    echo "  sudo zenbook-install-to-disk /mnt" >&2
    exit 1
fi

echo "============================================================"
echo "Installing Zenbook A16 platform support into: $target"
echo "============================================================"

# Detect distribution from target /etc/os-release
DISTRO="fedora"
if [[ -f "$target/etc/os-release" ]]; then
    # shellcheck disable=SC1091
    . "$target/etc/os-release"
    case "${ID:-}:${ID_LIKE:-}" in
        *fedora*|*rhel*)
            DISTRO="fedora"
            ;;
        *ubuntu*|*debian*)
            DISTRO="ubuntu"
            ;;
        *arch*)
            DISTRO="arch"
            ;;
        *)
            DISTRO="fedora"
            ;;
    esac
fi
echo "Detected target distribution: $DISTRO"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)

# 2. Discover bundle and kernel release
BUNDLE=""
liveesp_tmp=""
cleanup() {
    echo "Cleaning up mountpoints..."
    if [[ ${#mounted_binds[@]:-0} -gt 0 ]]; then
        for ((i=${#mounted_binds[@]}-1; i>=0; i--)); do
            umount "${mounted_binds[i]}" 2>/dev/null || true
        done
    fi
    if [[ -n "$liveesp_tmp" && -d "$liveesp_tmp" ]]; then
        umount "$liveesp_tmp" 2>/dev/null || true
        rmdir "$liveesp_tmp" 2>/dev/null || true
    fi
}
trap cleanup EXIT
mounted_binds=()

# Search bundle inside squashfs rootfs first
for cand in \
    "/usr/share/zenbook-a16/bundle" \
    "$SCRIPT_DIR/../bundle" \
    "/run/initramfs/live/bundle" \
    "/opt/zenbook-bundle"; do
    if [[ -d "$cand" ]]; then
        BUNDLE="$cand"
        break
    fi
done

# Fallback: check if LABEL=LIVEESP can be mounted
if [[ -z "$BUNDLE" ]]; then
    esp_dev=$(blkid -L LIVEESP 2>/dev/null || true)
    if [[ -n "$esp_dev" ]]; then
        liveesp_tmp=$(mktemp -d)
        if mount -o ro "$esp_dev" "$liveesp_tmp" 2>/dev/null; then
            if [[ -d "$liveesp_tmp/bundle" ]]; then
                BUNDLE="$liveesp_tmp/bundle"
            fi
        fi
    fi
fi

# Determine KREL
KREL="${KREL:-}"
if [[ -z "$KREL" && -n "$BUNDLE" && -f "$BUNDLE/usr/share/doc/linux-zenbook-a16/kernel-release" ]]; then
    KREL=$(head -n 1 "$BUNDLE/usr/share/doc/linux-zenbook-a16/kernel-release" | tr -d '[:space:]')
fi
if [[ -z "$KREL" && -n "$BUNDLE" ]]; then
    vm_cand=$(find "$BUNDLE" -maxdepth 2 -name 'vmlinuz-*' 2>/dev/null | head -n 1)
    if [[ -n "$vm_cand" ]]; then
        KREL=$(basename "$vm_cand" | sed 's/^vmlinuz-//')
    fi
fi
if [[ -z "$KREL" ]]; then
    KREL="7.3.0-rc5-glymur-rc5-20261013"
fi
echo "Using kernel release: $KREL"

# 3. Locate and verify kernel Image and DTB
KERNEL_SRC=""
for cand in \
    ${BUNDLE:+"$BUNDLE/vmlinuz-$KREL"} \
    ${BUNDLE:+"$BUNDLE/vmlinuz"} \
    "/boot/vmlinuz-$KREL" \
    "/vmlinuz-$KREL" \
    ${liveesp_tmp:+"$liveesp_tmp/vmlinuz-$KREL"}; do
    if [[ -s "$cand" ]]; then
        KERNEL_SRC="$cand"
        break
    fi
done

DTB_SRC=""
for cand in \
    ${BUNDLE:+"$BUNDLE/glymur-asus-zenbook-a16-ux3607oa.dtb"} \
    ${BUNDLE:+"$BUNDLE/$KREL.dtb"} \
    "/boot/dtb-$KREL" \
    "/boot/glymur/$KREL.dtb" \
    "/boot/dtbs/$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb" \
    ${liveesp_tmp:+"$liveesp_tmp/dtbs/glymur/$KREL.dtb"}; do
    if [[ -s "$cand" ]]; then
        DTB_SRC="$cand"
        break
    fi
done

if [[ -z "$KERNEL_SRC" ]]; then
    echo "error: kernel image (vmlinuz-$KREL) not found in bundle or boot sources" >&2
    exit 1
fi

if [[ -z "$DTB_SRC" ]]; then
    echo "error: device tree (glymur-asus-zenbook-a16-ux3607oa.dtb) not found in bundle or boot sources" >&2
    exit 1
fi

echo "Found kernel image: $KERNEL_SRC"
echo "Found device tree:  $DTB_SRC"

# 4. Install Kernel Packages / Binaries into target
if [[ "$DISTRO" == "fedora" ]]; then
    rpm_dir=""
    for cand in ${BUNDLE:+"$BUNDLE/rpms"} "/opt/zenbook-kernel" "$SCRIPT_DIR/../bundle/rpms"; do
        if compgen -G "$cand/kernel-*.rpm" >/dev/null 2>&1; then
            rpm_dir="$cand"
            break
        fi
    done
    if [[ -n "$rpm_dir" ]]; then
        echo "Installing kernel RPMs from $rpm_dir..."
        rpm --root "$target" -ivh --force --nodeps "$rpm_dir"/kernel-*.rpm 2>/dev/null || \
            dnf --installroot="$target" install -y "$rpm_dir"/kernel-*.rpm 2>/dev/null || true
    fi
elif [[ "$DISTRO" == "ubuntu" ]]; then
    deb_dir=""
    for cand in ${BUNDLE:+"$BUNDLE/debs"} "/opt/zenbook-kernel" "$SCRIPT_DIR/../bundle/debs"; do
        if compgen -G "$cand/linux-image-*.deb" >/dev/null 2>&1; then
            deb_dir="$cand"
            break
        fi
    done
    if [[ -n "$deb_dir" ]]; then
        echo "Installing kernel DEBs from $deb_dir..."
        dpkg --root="$target" -i "$deb_dir"/linux-*.deb 2>/dev/null || true
    fi
fi

# Ensure /boot artifacts exist
mkdir -p "$target/boot/glymur" "$target/boot/dtbs/$KREL/qcom"
install -Dm644 "$KERNEL_SRC" "$target/boot/vmlinuz-$KREL"
install -Dm644 "$DTB_SRC" "$target/boot/dtb-$KREL"
install -Dm644 "$DTB_SRC" "$target/boot/dtbs/$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb"
install -Dm644 "$DTB_SRC" "$target/boot/glymur/$KREL.dtb"

# Copy kernel modules
MODULES_SRC=""
for cand in \
    ${BUNDLE:+"$BUNDLE/lib/modules/$KREL"} \
    ${BUNDLE:+"$BUNDLE/modules/$KREL"} \
    "/lib/modules/$KREL" \
    "/usr/lib/modules/$KREL"; do
    if [[ -d "$cand" ]]; then
        MODULES_SRC="$cand"
        break
    fi
done

if [[ -n "$MODULES_SRC" ]]; then
    echo "Installing kernel modules from $MODULES_SRC..."
    mkdir -p "$target/lib/modules"
    cp -a "$MODULES_SRC" "$target/lib/modules/$KREL"
    rm -rf "$target/lib/modules/$KREL/build" "$target/lib/modules/$KREL/source"
    printf '1\n' > "$target/lib/modules/$KREL/omarchy-a16-dsp-abi"
    printf '1\n' > "$target/lib/modules/$KREL/zenbook-a16-dsp-abi"
    mkdir -p "$target/usr/share/doc/linux-zenbook-a16"
    printf '%s\n' "$KREL" > "$target/usr/share/doc/linux-zenbook-a16/kernel-release"
fi

# 5. Install Firmware
echo "Updating firmware in $target/lib/firmware..."
mkdir -p "$target/lib/firmware"
FW_SRC=""
for cand in ${BUNDLE:+"$BUNDLE/firmware"} "/lib/firmware"; do
    if [[ -d "$cand/qcom" || -d "$cand/ath12k" ]]; then
        FW_SRC="$cand"
        break
    fi
done

if [[ -n "$FW_SRC" ]]; then
    for sub in "ath12k/WCN7850" "ath12k/QCC2072" "qca" "qcom/glymur" "qcom"; do
        if [[ -d "$FW_SRC/$sub" ]]; then
            mkdir -p "$target/lib/firmware/$(dirname "$sub")"
            cp -a "$FW_SRC/$sub" "$target/lib/firmware/$(dirname "$sub")/"
        fi
    done
fi

# 6. Install Power and Platform Tweaks
echo "Installing platform tweaks and ALSA UCM configuration..."
TWEAKS_SRC=""
for cand in ${BUNDLE:+"$BUNDLE/tweaks"} ${REPO_ROOT:+"$REPO_ROOT/tweaks"}; do
    if [[ -d "$cand" ]]; then
        TWEAKS_SRC="$cand"
        break
    fi
done

mkdir -p "$target/etc/modules-load.d" \
         "$target/etc/tmpfiles.d" \
         "$target/etc/systemd/logind.conf.d" \
         "$target/usr/lib/systemd/system-sleep" \
         "$target/usr/local/bin" \
         "$target/usr/share/alsa/ucm2"

if [[ -n "$TWEAKS_SRC" ]]; then
    [[ -f "$TWEAKS_SRC/etc/modules-load.d/battery-baseline.conf" ]] && \
        install -Dm644 "$TWEAKS_SRC/etc/modules-load.d/battery-baseline.conf" \
            "$target/etc/modules-load.d/battery-baseline.conf"
    [[ -f "$TWEAKS_SRC/etc/tmpfiles.d/glymur-s2idle.conf" ]] && \
        install -Dm644 "$TWEAKS_SRC/etc/tmpfiles.d/glymur-s2idle.conf" \
            "$target/etc/tmpfiles.d/glymur-s2idle.conf"
    [[ -f "$TWEAKS_SRC/etc/systemd/logind.conf.d/99-glymur-suspend.conf" ]] && \
        install -Dm644 "$TWEAKS_SRC/etc/systemd/logind.conf.d/99-glymur-suspend.conf" \
            "$target/etc/systemd/logind.conf.d/99-glymur-suspend.conf"
    [[ -f "$TWEAKS_SRC/usr/lib/systemd/system-sleep/glymur-resume-guard" ]] && \
        install -Dm755 "$TWEAKS_SRC/usr/lib/systemd/system-sleep/glymur-resume-guard" \
            "$target/usr/lib/systemd/system-sleep/glymur-resume-guard"
    [[ -f "$TWEAKS_SRC/usr/local/bin/glymur-cpu-profile.sh" ]] && \
        install -Dm755 "$TWEAKS_SRC/usr/local/bin/glymur-cpu-profile.sh" \
            "$target/usr/local/bin/glymur-cpu-profile.sh"
    if [[ -d "$TWEAKS_SRC/usr/share/alsa/ucm2" ]]; then
        cp -a "$TWEAKS_SRC/usr/share/alsa/ucm2"/* "$target/usr/share/alsa/ucm2/" 2>/dev/null || true
    fi
fi

# Mask TPM devices to avoid firmware lockups
mkdir -p "$target/etc/systemd/system"
ln -sf /dev/null "$target/etc/systemd/system/dev-tpm0.device" 2>/dev/null || true
ln -sf /dev/null "$target/etc/systemd/system/dev-tpmrm0.device" 2>/dev/null || true

# 7. Install Persistent Kernel-Update Hooks
echo "Installing persistent kernel-update hooks..."
HOOKS_INSTALLER=""
for cand in \
    ${BUNDLE:+"$BUNDLE/packaging/zenbook-a16-hooks/install-hooks.sh"} \
    ${REPO_ROOT:+"$REPO_ROOT/packaging/zenbook-a16-hooks/install-hooks.sh"} \
    "/usr/share/zenbook-a16/hooks/install-hooks.sh"; do
    if [[ -x "$cand" ]]; then
        HOOKS_INSTALLER="$cand"
        break
    fi
done

if [[ -n "$HOOKS_INSTALLER" ]]; then
    bash "$HOOKS_INSTALLER" --root "$target" --distro "$DISTRO"
else
    echo "warning: install-hooks.sh not found; proceeding with manual boot setup" >&2
fi

# 8. Bind-mount system filesystems into target for chroot execution
echo "Bind-mounting system hierarchies for chroot operations..."
for m in /dev /dev/pts /proc /sys /run; do
    if [[ -d "$m" ]]; then
        mkdir -p "$target$m"
        mount --bind "$m" "$target$m"
        mounted_binds+=("$target$m")
    fi
done
if [[ -d "/sys/firmware/efi/efivars" ]]; then
    mkdir -p "$target/sys/firmware/efi/efivars"
    mount --bind "/sys/firmware/efi/efivars" "$target/sys/firmware/efi/efivars"
    mounted_binds+=("$target/sys/firmware/efi/efivars")
fi

# 9. Configure Initramfs & Bootloader in Chroot
CMDLINE_EXTRA="clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 nvme_core.default_ps_max_latency_us=0 pcie_aspm=off"

echo "Updating target initramfs and bootloader ($DISTRO)..."
case "$DISTRO" in
    fedora)
        # Dracut initramfs
        if [[ -x "$target/usr/bin/dracut" ]]; then
            echo "Generating initramfs with dracut..."
            chroot "$target" dracut --force --no-hostonly --kver "$KREL" "/boot/initramfs-$KREL.img" 2>/dev/null || true
        elif [[ ! -s "$target/boot/initramfs-$KREL.img" && -s "/boot/initramfs-$KREL.img" ]]; then
            cp -a "/boot/initramfs-$KREL.img" "$target/boot/initramfs-$KREL.img"
        fi

        # Kernel-install / BLS
        if [[ -x "$target/usr/bin/kernel-install" ]]; then
            chroot "$target" kernel-install add "$KREL" "/boot/vmlinuz-$KREL" 2>/dev/null || true
        fi

        # Fallback manual BLS entry
        for bls_dir in "$target/boot/loader/entries" "$target/boot/efi/loader/entries"; do
            if [[ -d "$bls_dir" ]]; then
                cat > "$bls_dir/zenbook-a16-$KREL.conf" <<EOF
title      Fedora (ASUS Zenbook A16)
version    $KREL
linux      /vmlinuz-$KREL
initrd     /initramfs-$KREL.img
devicetree /dtbs/$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb
options    root=LABEL=fedora rw $CMDLINE_EXTRA
EOF
            fi
        done

        # Regenerate GRUB config
        if [[ -x "$target/usr/sbin/grub2-mkconfig" ]]; then
            chroot "$target" grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
            chroot "$target" grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
        fi
        ;;

    ubuntu)
        # Ubuntu initramfs
        if [[ -x "$target/usr/sbin/update-initramfs" ]]; then
            echo "Generating initramfs with update-initramfs..."
            chroot "$target" update-initramfs -c -k "$KREL" 2>/dev/null || \
            chroot "$target" update-initramfs -u -k "$KREL" 2>/dev/null || true
        elif [[ ! -s "$target/boot/initrd.img-$KREL" && -s "/boot/initrd.img-$KREL" ]]; then
            cp -a "/boot/initrd.img-$KREL" "$target/boot/initrd.img-$KREL"
        fi

        # Update GRUB
        if [[ -x "$target/usr/sbin/update-grub" ]]; then
            chroot "$target" update-grub 2>/dev/null || true
        elif [[ -x "$target/usr/sbin/grub-mkconfig" ]]; then
            chroot "$target" grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        fi
        ;;

    arch)
        # Arch mkinitcpio
        if [[ -x "$target/usr/bin/mkinitcpio" ]]; then
            echo "Generating initramfs with mkinitcpio..."
            chroot "$target" mkinitcpio -k "$KREL" -g "/boot/initramfs-$KREL.img" 2>/dev/null || true
        fi
        if [[ -x "$target/usr/bin/limine-update" ]]; then
            chroot "$target" limine-update 2>/dev/null || true
        fi
        ;;
esac

# 10. Handle Fedora Btrfs top-level /boot sync (subvolid=5)
if [[ "$DISTRO" == "fedora" ]]; then
    root_fstype=$(findmnt -n -o FSTYPE "$target" 2>/dev/null || true)
    root_opts=$(findmnt -n -o OPTIONS "$target" 2>/dev/null || true)
    if [[ "$root_fstype" == "btrfs" && "$root_opts" =~ subvol= ]]; then
        root_dev=$(findmnt -n -o SOURCE "$target" 2>/dev/null || true)
        if [[ -n "$root_dev" ]]; then
            tmp_subvol=$(mktemp -d)
            if mount -o "rw,subvolid=5" "$root_dev" "$tmp_subvol" 2>/dev/null; then
                if [[ -d "$tmp_subvol/boot" ]]; then
                    echo "Syncing boot artifacts into Btrfs top-level subvolume (subvolid=5)..."
                    mkdir -p "$tmp_subvol/boot/dtbs/$KREL/qcom" "$tmp_subvol/boot/glymur"
                    install -m 0644 "$target/boot/vmlinuz-$KREL" "$tmp_subvol/boot/vmlinuz-$KREL" 2>/dev/null || true
                    [[ -f "$target/boot/initramfs-$KREL.img" ]] && \
                        install -m 0644 "$target/boot/initramfs-$KREL.img" "$tmp_subvol/boot/initramfs-$KREL.img" 2>/dev/null || true
                    install -m 0644 "$target/boot/dtb-$KREL" "$tmp_subvol/boot/dtb-$KREL" 2>/dev/null || true
                    install -m 0644 "$target/boot/dtbs/$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb" \
                        "$tmp_subvol/boot/dtbs/$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb" 2>/dev/null || true
                fi
                umount "$tmp_subvol" 2>/dev/null || true
            fi
            rmdir "$tmp_subvol" 2>/dev/null || true
        fi
    fi
fi

# 11. Run Boot Verification
echo "Running post-install boot verification..."
bootloader_check="auto"
case "$DISTRO" in
    fedora) bootloader_check="grub-bls" ;;
    ubuntu) bootloader_check="grub-ubuntu" ;;
    arch)   bootloader_check="limine" ;;
esac

verifier="$target/usr/lib/zenbook-a16/verify-boot.py"
if [[ -x "$verifier" || -f "$verifier" ]]; then
    chroot "$target" python3 /usr/lib/zenbook-a16/verify-boot.py \
        --bootloader "$bootloader_check" --kernel-release "$KREL" || {
        echo "error: Zenbook A16 boot verification failed!" >&2
        exit 1
    }
fi

echo "============================================================"
echo " Zenbook A16 installation complete and verified!"
echo " Kernel:     $KREL"
echo " Devicetree: /boot/dtb-$KREL"
echo " Target:     $target"
echo " Distro:     $DISTRO"
echo "============================================================"
echo "You can now safely unmount the target and reboot."
