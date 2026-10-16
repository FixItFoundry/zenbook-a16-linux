#!/usr/bin/env bash
# install-hooks.sh — Install persistent kernel-update hooks across Fedora, Ubuntu, and Arch.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  install-hooks.sh [--root <dir>] [--distro auto|fedora|ubuntu|arch]

Options:
  --root <dir>     Target root directory (default: /)
  --distro <name>  Target distribution: auto (default), fedora, ubuntu, or arch
  -h, --help       Show this help message
EOF
}

TARGET="/"
DISTRO="auto"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            TARGET=$(realpath "$2")
            shift 2
            ;;
        --distro)
            DISTRO="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

# 1. Detect distribution if auto
if [[ "$DISTRO" == "auto" ]]; then
    if [[ -f "$TARGET/etc/os-release" ]]; then
        # shellcheck disable=SC1091
        . "$TARGET/etc/os-release"
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
                echo "warning: unknown distro ID '$ID', falling back to fedora" >&2
                DISTRO="fedora"
                ;;
        esac
    elif [[ -d "$TARGET/etc/dracut.conf.d" || -d "$TARGET/usr/lib/dracut" ]]; then
        DISTRO="fedora"
    elif [[ -d "$TARGET/etc/initramfs-tools" ]]; then
        DISTRO="ubuntu"
    elif [[ -d "$TARGET/etc/mkinitcpio.d" || -d "$TARGET/usr/lib/initcpio" ]]; then
        DISTRO="arch"
    else
        DISTRO="fedora"
    fi
fi

echo "Installing Zenbook A16 persistent kernel-update hooks for distro: $DISTRO into $TARGET"

# 2. Always install verify-boot.py into /usr/lib/zenbook-a16/
mkdir -p "$TARGET/usr/lib/zenbook-a16" "$TARGET/usr/lib/omarchy-a16"
install -Dm755 "$REPO_ROOT/packaging/omarchy-a16-support/verify-boot.py" \
    "$TARGET/usr/lib/zenbook-a16/verify-boot.py"
ln -sf "../zenbook-a16/verify-boot.py" "$TARGET/usr/lib/omarchy-a16/verify-boot"

# Also stage hook sources for runtime script references if needed
mkdir -p "$TARGET/usr/share/zenbook-a16/hooks"
cp -a "$SCRIPT_DIR"/* "$TARGET/usr/share/zenbook-a16/hooks/" 2>/dev/null || true

# 3. Distribution-specific hooks
case "$DISTRO" in
    fedora)
        # Dracut module
        mkdir -p "$TARGET/usr/lib/dracut/modules.d/90zenbook-a16"
        install -Dm755 "$SCRIPT_DIR/fedora/90zenbook-a16/module-setup.sh" \
            "$TARGET/usr/lib/dracut/modules.d/90zenbook-a16/module-setup.sh"
        install -Dm755 "$SCRIPT_DIR/fedora/90zenbook-a16/zenbook-a16-pre-udev.sh" \
            "$TARGET/usr/lib/dracut/modules.d/90zenbook-a16/zenbook-a16-pre-udev.sh"

        # Dracut config drop-in
        mkdir -p "$TARGET/etc/dracut.conf.d"
        install -Dm644 "$SCRIPT_DIR/fedora/99-zenbook-a16.conf" \
            "$TARGET/etc/dracut.conf.d/99-zenbook-a16.conf"

        # kernel-install hook
        mkdir -p "$TARGET/etc/kernel/install.d"
        install -Dm755 "$SCRIPT_DIR/fedora/95-zenbook-a16.install" \
            "$TARGET/etc/kernel/install.d/95-zenbook-a16.install"
        ;;

    ubuntu)
        # initramfs-tools hook & premount script
        mkdir -p "$TARGET/etc/initramfs-tools/hooks" \
                 "$TARGET/etc/initramfs-tools/scripts/init-premount"
        install -Dm755 "$SCRIPT_DIR/ubuntu/initramfs-hook-zenbook-a16" \
            "$TARGET/etc/initramfs-tools/hooks/zenbook-a16"
        install -Dm755 "$SCRIPT_DIR/ubuntu/init-premount-zenbook-a16" \
            "$TARGET/etc/initramfs-tools/scripts/init-premount/zenbook-a16"

        # GRUB hook
        mkdir -p "$TARGET/etc/grub.d"
        install -Dm755 "$SCRIPT_DIR/ubuntu/09_zenbook_a16" \
            "$TARGET/etc/grub.d/09_zenbook_a16"

        # kernel postinst hook
        mkdir -p "$TARGET/etc/kernel/postinst.d"
        install -Dm755 "$SCRIPT_DIR/ubuntu/zz-zenbook-a16" \
            "$TARGET/etc/kernel/postinst.d/zz-zenbook-a16"
        ;;

    arch)
        # mkinitcpio hooks
        mkdir -p "$TARGET/usr/lib/initcpio/install" \
                 "$TARGET/usr/lib/initcpio/hooks" \
                 "$TARGET/etc/mkinitcpio.conf.d" \
                 "$TARGET/usr/share/omarchy-a16"
        install -Dm755 "$REPO_ROOT/packaging/omarchy-a16-support/initcpio-install" \
            "$TARGET/usr/lib/initcpio/install/omarchy-a16-dsp"
        install -Dm755 "$REPO_ROOT/packaging/omarchy-a16-support/initcpio-hook" \
            "$TARGET/usr/lib/initcpio/hooks/omarchy-a16-dsp"
        install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/mkinitcpio.conf" \
            "$TARGET/etc/mkinitcpio.conf.d/zz-zenbook-a16-dsp.conf"
        install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/remoteproc-blacklist.conf" \
            "$TARGET/usr/share/omarchy-a16/remoteproc-blacklist.conf"

        # libalpm pacman hooks
        mkdir -p "$TARGET/usr/share/libalpm/hooks"
        install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/60-omarchy-a16-boot-check.hook" \
            "$TARGET/usr/share/libalpm/hooks/60-omarchy-a16-pre.hook"
        install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/zz-omarchy-a16-boot-check.hook" \
            "$TARGET/usr/share/libalpm/hooks/95-omarchy-a16-post.hook"
        ;;
esac

echo "Zenbook A16 persistent kernel-update hooks installed successfully."
