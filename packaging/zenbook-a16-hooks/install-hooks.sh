#!/usr/bin/env bash
# Install persistent Fedora/Ubuntu hooks; Omarchy uses its packaged support contract.
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  install-hooks.sh [--root <dir>] [--distro auto|fedora|ubuntu|arch] [--check]

Options:
  --root <dir>     Target root directory (default: /)
  --distro <name>  Target distribution: auto (default), fedora, ubuntu, or arch
  --check         Validate hook sources without installing
  -h, --help       Show this help message
EOF
}

TARGET="/"
DISTRO="auto"
CHECK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 && -n $2 ]] || { echo "error: --root requires a directory" >&2; exit 1; }
            TARGET=$(realpath "$2")
            shift 2
            ;;
        --distro)
            [[ $# -ge 2 && -n $2 ]] || { echo "error: --distro requires a value" >&2; exit 1; }
            DISTRO="$2"
            shift 2
            ;;
        --check)
            CHECK=1
            shift
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
                echo "error: unsupported distro ID ${ID:-unknown}" >&2
                exit 1
                ;;
        esac
    elif [[ -d "$TARGET/etc/dracut.conf.d" || -d "$TARGET/usr/lib/dracut" ]]; then
        DISTRO="fedora"
    elif [[ -d "$TARGET/etc/initramfs-tools" ]]; then
        DISTRO="ubuntu"
    elif [[ -d "$TARGET/etc/mkinitcpio.d" || -d "$TARGET/usr/lib/initcpio" ]]; then
        DISTRO="arch"
    else
        echo "error: cannot identify target distribution" >&2
        exit 1
    fi
fi

case "$DISTRO" in
    fedora|ubuntu) ;;
    arch) echo 'error: generic Arch hooks are unsupported; use the Omarchy support package with its kernel metadata, pkgbase and UKI hook ordering' >&2; exit 1 ;;
    *) echo "error: unsupported distro: $DISTRO" >&2; exit 1 ;;
esac

required=(
    "$SCRIPT_DIR/boot-artifacts.py"
    "$REPO_ROOT/packaging/omarchy-a16-support/verify-boot.py"
    "$REPO_ROOT/packaging/omarchy-a16-support/initcpio-hook"
    "$REPO_ROOT/packaging/omarchy-a16-support/remoteproc-blacklist.conf"
)
if [[ $DISTRO == fedora ]]; then
    required+=("$SCRIPT_DIR/fedora/90zenbook-a16/module-setup.sh"
        "$SCRIPT_DIR/fedora/90zenbook-a16/zenbook-a16-pre-udev.sh"
        "$SCRIPT_DIR/fedora/95-zenbook-a16.install" "$SCRIPT_DIR/fedora/99-zenbook-a16.conf")
else
    required+=("$SCRIPT_DIR/ubuntu/09_zenbook_a16" "$SCRIPT_DIR/ubuntu/zz-zenbook-a16"
        "$SCRIPT_DIR/ubuntu/init-premount-zenbook-a16" "$SCRIPT_DIR/ubuntu/initramfs-hook-zenbook-a16")
fi
for source in "${required[@]}"; do
    [[ -s $source ]] || { echo "error: missing hook source: $source" >&2; exit 1; }
done
[[ $CHECK == 0 ]] || exit 0

echo "Installing Zenbook A16 persistent kernel-update hooks for distro: $DISTRO into $TARGET"

# 2. Always install verify-boot.py into /usr/lib/zenbook-a16/
mkdir -p "$TARGET/usr/lib/zenbook-a16"
install -Dm755 "$REPO_ROOT/packaging/omarchy-a16-support/verify-boot.py" \
    "$TARGET/usr/lib/zenbook-a16/verify-boot.py"
install -Dm755 "$SCRIPT_DIR/boot-artifacts.py" "$TARGET/usr/lib/zenbook-a16/boot-artifacts.py"
install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/initcpio-hook" "$TARGET/usr/lib/zenbook-a16/dsp-policy.sh"
install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/remoteproc-blacklist.conf" "$TARGET/usr/share/omarchy-a16/remoteproc-blacklist.conf"
install -Dm644 "$REPO_ROOT/packaging/omarchy-a16-support/remoteproc-blacklist.conf" "$TARGET/etc/modprobe.d/zenbook-a16-remoteproc.conf"

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


esac

echo "Zenbook A16 persistent kernel-update hooks installed successfully."
