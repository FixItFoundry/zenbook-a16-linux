#!/usr/bin/env bash
# ============================================================================
# zenbook-install-to-disk.sh — Multi-distro installer for ASUS Zenbook A16
# Installs kernel, DTB, modules, firmware, platform tweaks, and persistent
# kernel-update hooks onto target disk across Fedora and Ubuntu.
# ============================================================================
set -Eeuo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

die() { echo "error: $*" >&2; exit 1; }

copy_modules() {
    local source=$1 destination=$2
    [[ -d "$source" && ! -L "$destination" ]] || die "invalid module source or symlink destination: $destination"
    mkdir -p "$destination"
    # Copy directory contents: the source can be the bundle's relative symlink.
    cp -a "$source/." "$destination/"
    rm -rf "$destination/build" "$destination/source"
}

read_target_cmdline() {
    python3 - "$target" <<'PY_CMDLINE'
from pathlib import Path
import re
import shlex
import sys
root = Path(sys.argv[1])
paths = [root / 'etc/kernel/cmdline', *sorted((root / 'boot/loader/entries').glob('*.conf')),
         root / 'boot/grub/grub.cfg']
for path in paths:
    if not path.is_file():
        continue
    for line in path.read_text().splitlines():
        if path.name == 'cmdline':
            value = line.strip()
        else:
            match = re.match(r'\s*(?:options\s+|linux(?:efi)?\s+\S+\s+)(.*)', line)
            if not match:
                continue
            value = match[1]
        tokens = shlex.split(value)
        if any(t.startswith('root=') and not t.startswith('root=live:') for t in tokens) and all(
                re.fullmatch(r'[A-Za-z0-9_.,:/=+@%\-]+', t) for t in tokens):
            print(' '.join(tokens))
            sys.exit(0)
sys.exit('error: target needs an existing literal root= command line from its distro installer')
PY_CMDLINE
}

check_boot_layout() {
    local boot_mount boot_fsroot
    boot_mount=$(findmnt -n -o TARGET --target "$target/boot")
    boot_fsroot=$(findmnt -n -o FSROOT --target "$target/boot")
    [[ "$boot_mount" == "$target" || "$boot_mount" == "$target/boot" ]] || die "mount the target root and boot filesystem before installing"
    [[ "$boot_fsroot" == / ]] || die "subvolume /boot needs a separately mounted top-level boot filesystem; boot mirroring is not verified"
}

verify_boot() {
    [[ -s "$target/usr/lib/zenbook-a16/verify-boot.py" ]] || die "boot verifier missing"
    chroot "$target" python3 /usr/lib/zenbook-a16/verify-boot.py \
        --bootloader "$bootloader_check" --kernel-release "$KREL" || die "Zenbook A16 boot verification failed"
}

check_release_destinations() {
    local path
    for path in \
        "boot/vmlinuz-$KREL" "boot/config-$KREL" "boot/dtb-$KREL" "boot/glymur/$KREL.dtb" \
        "boot/dtbs/$KREL" "boot/initramfs-$KREL.img" "boot/initrd.img-$KREL" \
        "lib/modules/$KREL" "usr/lib/modules/$KREL"; do
        [[ ! -e "$target/$path" && ! -L "$target/$path" ]] || die "release $KREL already exists at $path; build a new package revision to preserve rollback"
    done
}

discover_kernel_packages() {
    package_files=()
    support_package=""; payload_package=""; meta_package=""
    local directory extension payload_name file name normalized_release
    normalized_release=$(printf '%s' "$KREL" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9+.-]/-/g')
    case "$DISTRO" in
        fedora)
            directory="$BUNDLE/rpms"; extension=rpm
            payload_name="kernel-zenbook-a16-$normalized_release"
            ;;
        ubuntu)
            directory="$BUNDLE/debs"; extension=deb
            payload_name="linux-image-$normalized_release"
            ;;
    esac
    [[ -d "$directory" ]] || return 0
    shopt -s nullglob
    package_files=("$directory"/*."$extension")
    shopt -u nullglob
    [[ ${#package_files[@]} -eq 3 ]] || die "bundle $directory must contain exactly the current kernel, support and meta packages"
    if [[ "$DISTRO" == fedora ]]; then
        command -v rpm >/dev/null || die "live environment requires rpm for bundled packages"
    else
        command -v dpkg-deb >/dev/null || die "live environment requires dpkg-deb for bundled packages"
    fi
    for file in "${package_files[@]}"; do
        if [[ "$DISTRO" == fedora ]]; then
            name=$(rpm -qp --queryformat '%{NAME}\n' "$file")
        else
            name=$(dpkg-deb --field "$file" Package)
        fi
        case "$name" in
            zenbook-a16-support) [[ -z "$support_package" ]] || die "duplicate support package"; support_package="$file" ;;
            zenbook-a16-kernel) [[ -z "$meta_package" ]] || die "duplicate kernel meta package"; meta_package="$file" ;;
            "$payload_name") [[ -z "$payload_package" ]] || die "duplicate kernel payload package"; payload_package="$file" ;;
            *) die "unexpected package $name in $directory" ;;
        esac
    done
    [[ -n "$support_package" && -n "$payload_package" && -n "$meta_package" ]] || die "incomplete kernel package set"
    package_files=("$support_package" "$payload_package" "$meta_package")
}

bind_package_directory() {
    [[ -d "$target/mnt" && ! -L "$target/mnt" ]] || die "target needs an empty /mnt directory for package staging"
    if mountpoint -q "$target/mnt"; then
        die "target /mnt is already mounted; unmount it before installing"
    fi
    [[ -z "$(find "$target/mnt" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "target /mnt must be empty for package staging"
    mount --bind "$BUNDLE/debs" "$target/mnt"
    mounted_binds+=("$target/mnt")
    mount -o remount,bind,ro "$target/mnt"
    target_package_files=()
    local file
    for file in "${package_files[@]}"; do
        target_package_files+=("/mnt/$(basename "$file")")
    done
}

check_package_transaction() {
    [[ ${#package_files[@]} -gt 0 ]] || return 0
    if [[ "$DISTRO" == fedora ]]; then
        rpm --root "$target" -Uvh --test "${package_files[@]}"
    else
        bind_package_directory
        chroot "$target" apt-get --simulate --no-download --no-remove install "${target_package_files[@]}"
    fi
}

install_kernel_packages() {
    [[ ${#package_files[@]} -gt 0 ]] || return 0
    if [[ "$DISTRO" == fedora ]]; then
        rpm --root "$target" -Uvh "${package_files[@]}"
    else
        chroot "$target" apt-get -y --no-download --no-remove install "${target_package_files[@]}"
    fi
}

configure_boot() {
echo "Updating target initramfs and bootloader ($DISTRO)..."
chroot "$target" depmod -a "$KREL"
case "$DISTRO" in
    fedora)
        chroot "$target" dracut --force --no-hostonly --kver "$KREL" "/boot/initramfs-$KREL.img"
        chroot "$target" kernel-install add "$KREL" "/boot/vmlinuz-$KREL"
        # Keep distro-generated root options; the hook supplies the A16 DTB and flags.
        chroot "$target" /etc/kernel/install.d/95-zenbook-a16.install add "$KREL" "" "/boot/vmlinuz-$KREL"
        chroot "$target" grub2-mkconfig -o /boot/grub2/grub.cfg
        ;;
    ubuntu)
        initramfs_mode=-c
        [[ ! -e "$target/boot/initrd.img-$KREL" ]] || initramfs_mode=-u
        chroot "$target" update-initramfs "$initramfs_mode" -k "$KREL"
        chroot "$target" /etc/kernel/postinst.d/zz-zenbook-a16 "$KREL" "/boot/vmlinuz-$KREL"
        ;;
esac

}

main() {
target=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            [[ $# -ge 2 ]] || die "--target requires a directory"
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
DISTRO=""
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
            die "unsupported target distribution: ${ID:-unknown}"
            ;;
    esac
fi
[[ -n "$DISTRO" ]] || die "target /etc/os-release is required"
[[ "$DISTRO" != arch ]] || die "generic Arch installation has no verified Limine/UKI contract; use the packaged Omarchy workflow"
[[ "$target" != / ]] || die "refusing to install into the live root"
mountpoint -q "$target" || die "target must be a mounted root filesystem"
echo "Detected target distribution: $DISTRO"

REPO_ROOT=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || true)

# 2. Discover bundle and kernel release
BUNDLE=""
liveesp_tmp=""
cleanup() {
    echo "Cleaning up mountpoints..."
    if [[ ${#mounted_binds[@]} -gt 0 ]]; then
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
[[ -n "$BUNDLE" ]] || die "installer bundle is required"
[[ -n "$KREL" && "$KREL" != */* && "$KREL" != . && "$KREL" != .. ]] || die "missing or invalid kernel release"
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

# Resolve every required input and native tool before changing the target.
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

[[ -n "$MODULES_SRC" ]] || die "matching kernel modules are required"
[[ ! -L "$target/lib/modules/$KREL" ]] || die "target module directory must not be a symlink"
HOOKS_INSTALLER="$BUNDLE/packaging/zenbook-a16-hooks/install-hooks.sh"
[[ -x "$HOOKS_INSTALLER" && -s "$BUNDLE/packaging/omarchy-a16-support/verify-boot.py" ]] || die "complete persistent hooks and verifier are required in bundle"
bash "$HOOKS_INSTALLER" --root "$target" --distro "$DISTRO" --check
[[ "$(uname -m)" == aarch64 ]] || die "run this installer on native aarch64 Linux"
for tool in python3 dtc fdtget findmnt mountpoint chroot; do
    command -v "$tool" >/dev/null || die "live environment requires tool: $tool"
done
python3 "$BUNDLE/packaging/omarchy-a16-support/verify-boot.py" --validate-kernel \
    --modules-dir "$MODULES_SRC" --kernel-release "$KREL" --kernel-image "$KERNEL_SRC" --dtb-image "$DTB_SRC"
TARGET_CMDLINE=$(read_target_cmdline)
required_tools=(sh bash python3 dtc fdtget findmnt depmod udevadm modprobe tr grep sleep)
case "$DISTRO" in
    fedora) required_tools+=(dracut lsinitrd kernel-install grub2-mkconfig) ;;
    ubuntu) required_tools+=(update-initramfs unmkinitramfs update-grub grub-probe apt-get) ;;
esac
for tool in "${required_tools[@]}"; do
    chroot "$target" /bin/sh -c 'command -v "$1" >/dev/null' sh "$tool" || die "target requires native tool: $tool"
done
check_boot_layout

# 5. Install Firmware
FW_SRC=""
for cand in ${BUNDLE:+"$BUNDLE/firmware"} "/lib/firmware"; do
    if [[ -d "$cand/qcom" || -d "$cand/ath12k" ]]; then
        FW_SRC="$cand"
        break
    fi
done

[[ -n "$FW_SRC" ]] || die "A16 firmware is required"
[[ -s "$BUNDLE/glymur-fetch-firmware.sh" ]] || die "bundle firmware checker is required; rebuild the bundle"
DEST="$FW_SRC" bash "$BUNDLE/glymur-fetch-firmware.sh" --check

# Native package headers and dependency checks must pass before any target writes.
check_release_destinations
discover_kernel_packages
check_package_transaction

if [[ ${#package_files[@]} -eq 0 ]]; then
# Ensure /boot artifacts exist
mkdir -p "$target/boot/glymur" "$target/boot/dtbs/$KREL/qcom"
install -Dm644 "$KERNEL_SRC" "$target/boot/vmlinuz-$KREL"
install -Dm644 "$DTB_SRC" "$target/boot/dtb-$KREL"
install -Dm644 "$DTB_SRC" "$target/boot/dtbs/$KREL/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb"
install -Dm644 "$DTB_SRC" "$target/boot/glymur/$KREL.dtb"

echo "Installing kernel modules from $MODULES_SRC..."
copy_modules "$MODULES_SRC" "$target/lib/modules/$KREL"
mkdir -p "$target/usr/share/doc/linux-zenbook-a16"
printf '%s\n' "$KREL" > "$target/usr/share/doc/linux-zenbook-a16/kernel-release"

fi

# 5. Install Firmware
echo "Updating firmware in $target/lib/firmware..."
mkdir -p "$target/lib/firmware"
if [[ -n "$FW_SRC" ]]; then
    for sub in "ath12k/QCC2072" "qca" "qcom"; do
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
         "$target/usr/local/bin" \
         "$target/usr/share/alsa/ucm2"

if [[ -n "$TWEAKS_SRC" ]]; then
    [[ -f "$TWEAKS_SRC/etc/modules-load.d/battery-baseline.conf" ]] && \
        install -Dm644 "$TWEAKS_SRC/etc/modules-load.d/battery-baseline.conf" \
            "$target/etc/modules-load.d/battery-baseline.conf"
    [[ -f "$TWEAKS_SRC/etc/tmpfiles.d/glymur-s2idle.conf" ]] && \
        install -Dm644 "$TWEAKS_SRC/etc/tmpfiles.d/glymur-s2idle.conf" \
            "$target/etc/tmpfiles.d/glymur-s2idle.conf"
    [[ -f "$TWEAKS_SRC/usr/local/bin/glymur-cpu-profile.sh" ]] && \
        install -Dm755 "$TWEAKS_SRC/usr/local/bin/glymur-cpu-profile.sh" \
            "$target/usr/local/bin/glymur-cpu-profile.sh"
    if [[ -d "$TWEAKS_SRC/usr/share/alsa/ucm2" ]]; then
        cp -a "$TWEAKS_SRC/usr/share/alsa/ucm2"/* "$target/usr/share/alsa/ucm2/"
    fi
fi

# Mask TPM devices to avoid firmware lockups
mkdir -p "$target/etc/systemd/system"
ln -sf /dev/null "$target/etc/systemd/system/dev-tpm0.device"
ln -sf /dev/null "$target/etc/systemd/system/dev-tpmrm0.device"

# 7. Install Persistent Kernel-Update Hooks
echo "Installing persistent kernel-update hooks..."
if [[ ${#package_files[@]} -eq 0 ]]; then
    bash "$HOOKS_INSTALLER" --root "$target" --distro "$DISTRO"
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

mkdir -p "$target/etc/kernel"
printf '%s\n' "$TARGET_CMDLINE" > "$target/etc/kernel/cmdline"
install_kernel_packages

# Native package scripts own boot generation for their payload.
if [[ ${#package_files[@]} -eq 0 ]]; then
    configure_boot
fi

# 11. Run Boot Verification
echo "Running post-install boot verification..."
bootloader_check="auto"
case "$DISTRO" in
    fedora) bootloader_check="grub-bls" ;;
    ubuntu) bootloader_check="grub-ubuntu" ;;
esac

verify_boot

echo "============================================================"
echo " Zenbook A16 installation complete; boot artifacts verified."
echo " Kernel:     $KREL"
echo " Devicetree: /boot/dtb-$KREL"
echo " Target:     $target"
echo " Distro:     $DISTRO"
echo "============================================================"
echo "Unmount the target before rebooting. Hardware boot and suspend validation remain separate."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
