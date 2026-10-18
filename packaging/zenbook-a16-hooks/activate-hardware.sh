#!/usr/bin/env bash
# Model-gated hardware activation for ASUS Zenbook A16 (UX3607OA / Glymur).
# Activated by the post-install hook pipeline: package-owned assets live under
# /usr/share/{omarchy-a16,zenbook-a16,alsa/ucm2} and are linked into /etc only
# when running on UX3607OA hardware (or when --force is passed by the disk
# installer). Bridges Qualcomm's qcom-next / qcom-topics CONFIG_TCG_QCOM fTPM
# support by only masking dev-tpm0/dev-tpmrm0 when CONFIG_TCG_QCOM is absent.
set -Eeuo pipefail

ROOT="/"
FORCE=0
KREL=""
COMPATIBLE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 && -n "$2" ]] || { echo "error: --root requires a directory" >&2; exit 2; }
            ROOT=$(realpath "$2")
            shift 2
            ;;
        --kernel-release)
            [[ $# -ge 2 && -n "$2" ]] || { echo "error: --kernel-release requires a value" >&2; exit 2; }
            KREL="$2"
            shift 2
            ;;
        --compatible-file)
            [[ $# -ge 2 && -n "$2" ]] || { echo "error: --compatible-file requires a path" >&2; exit 2; }
            COMPATIBLE_PATH="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        *)
            echo "error: unknown option: $1" >&2
            exit 2
            ;;
    esac
done

is_zenbook_a16() {
    local compat="${COMPATIBLE_PATH:-$ROOT/sys/firmware/devicetree/base/compatible}"
    if [[ ! -r "$compat" && -r "/sys/firmware/devicetree/base/compatible" && "$ROOT" == "/" ]]; then
        compat="/sys/firmware/devicetree/base/compatible"
    fi
    [[ -r "$compat" ]] || return 1
    tr '\0' '\n' < "$compat" | grep -Fxq -e 'asus,zenbook-a16-ux3607oa' -e 'asus,ux3607oa'
}

link_config() {
    local target_rel="$1" link_rel="$2"
    local src="$ROOT/${target_rel#/}"
    local dst="$ROOT/${link_rel#/}"
    [[ -e "$src" ]] || return 0
    mkdir -p "$(dirname "$dst")"
    if ln -srfn "$src" "$dst" 2>/dev/null; then
        :
    else
        ln -sfn "/${target_rel#/}" "$dst"
    fi
}

kernel_has_qcom_tpm() {
    local cfg
    local -a configs=()
    if [[ -n "$KREL" ]]; then
        configs+=(
            "$ROOT/boot/config-$KREL"
            "$ROOT/usr/lib/modules/$KREL/build/.config"
            "$ROOT/lib/modules/$KREL/build/.config"
        )
    else
        shopt -s nullglob
        configs+=(
            "$ROOT"/boot/config-*
            "$ROOT"/usr/lib/modules/*/build/.config
            "$ROOT"/lib/modules/*/build/.config
        )
        shopt -u nullglob
    fi
    for cfg in "${configs[@]}"; do
        if [[ -f "$cfg" ]] && grep -Eq '^CONFIG_TCG_QCOM=[ym]$' "$cfg"; then
            return 0
        fi
    done
    return 1
}

if [[ "$FORCE" -ne 1 ]] && ! is_zenbook_a16; then
    exit 0
fi

# 1. Link staged WirePlumber SoundWire keep-awake policy and platform drop-ins
link_config "usr/share/omarchy-a16/51-glymur-ucm.conf" \
    "etc/wireplumber/wireplumber.conf.d/51-glymur-ucm.conf"
link_config "usr/share/zenbook-a16/battery-baseline.conf" \
    "etc/modules-load.d/battery-baseline.conf"
link_config "usr/share/zenbook-a16/glymur-s2idle.conf" \
    "etc/tmpfiles.d/glymur-s2idle.conf"

# 2. Ensure SCMI cpufreq autoload drop-in exists via post-install hook
mkdir -p "$ROOT/etc/modules-load.d"
if [[ ! -e "$ROOT/etc/modules-load.d/zenbook-a16.conf" ]]; then
    printf 'scmi-cpufreq\n' > "$ROOT/etc/modules-load.d/zenbook-a16.conf"
fi

# 3. Bridge Qualcomm fTPM (CONFIG_TCG_QCOM) vs legacy bare-metal TPM lockup mask
mkdir -p "$ROOT/etc/systemd/system"
if kernel_has_qcom_tpm; then
    for unit in dev-tpm0.device dev-tpmrm0.device; do
        if [[ -L "$ROOT/etc/systemd/system/$unit" && "$(readlink "$ROOT/etc/systemd/system/$unit")" == "/dev/null" ]]; then
            rm -f "$ROOT/etc/systemd/system/$unit"
        fi
    done
else
    ln -sfn /dev/null "$ROOT/etc/systemd/system/dev-tpm0.device"
    ln -sfn /dev/null "$ROOT/etc/systemd/system/dev-tpmrm0.device"
fi
