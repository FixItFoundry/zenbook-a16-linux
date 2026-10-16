#!/usr/bin/env bash
# Check or copy the firmware layout used by the promoted Zenbook A16 kernel.
set -Eeuo pipefail

dest=${DEST:-/lib/firmware}

usage() {
    cat <<'EOF'
Usage:
  glymur-fetch-firmware.sh --check
  glymur-fetch-firmware.sh --from-linux PATH

--check verifies DEST (default: /lib/firmware).
--from-linux copies from PATH, PATH/lib/firmware, or PATH/usr/lib/firmware.

Current Glymur firmware is available from upstream linux-firmware. This script
preserves its directory layout; it does not guess Linux filenames from Windows
driver files. See firmware/README.md for the tested upstream tag.
EOF
}

required=(
    ath12k/WCN7850/hw2.0/board-2.bin
    ath12k/WCN7850/hw2.0/firmware-2.bin
    qca/hmtbtfw20.tlv
    qca/hmtbtnv20.bin
    qcom/gen80500_sqe.fw
    qcom/gen80500_gmu.bin
    qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn
    qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf
    qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn
    qcom/glymur/ASUSTeK/UX3607OA/cdsp_dtbs.elf
    qcom/glymur/ASUSTeK/UX3607OA-tplg.bin
)

check_all() {
    local missing=0 file found ext
    echo "Checking $dest"
    for file in "${required[@]}"; do
        found=""
        local check_targets=("$file")
        if [[ "$file" == *"UX3607OA-tplg.bin" ]]; then
            check_targets+=("qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin")
        fi
        for target in "${check_targets[@]}"; do
            for ext in "" ".xz" ".zst"; do
                if [[ -s "$dest/$target$ext" ]]; then
                    found="$target$ext"
                    break 2
                fi
            done
        done
        if [[ -n "$found" ]]; then
            printf '  OK       %s\n' "$found"
        else
            printf '  MISSING  %s\n' "$file"
            missing=$((missing + 1))
        fi
    done
    if (( missing )); then
        echo "Incomplete: $missing required file(s) are missing." >&2
        return 1
    fi
    echo "Complete: all required files are present."
}

copy_from_linux() {
    local input=$1 source= candidate
    [[ -d "$input" ]] || { echo "error: no such directory: $input" >&2; return 1; }

    for candidate in "$input" "$input/lib/firmware" "$input/usr/lib/firmware"; do
        if [[ -d "$candidate/ath12k" || -d "$candidate/qcom" ]]; then
            source=$candidate
            break
        fi
    done
    [[ -n "$source" ]] || {
        echo "error: no firmware tree found below $input" >&2
        return 1
    }

    echo "Copying from $source to $dest"
    install -d "$dest/ath12k" "$dest/qca" "$dest/qcom"

    # Wi-Fi
    if [[ -d "$source/ath12k/WCN7850" ]]; then
        cp -a --no-preserve=ownership "$source/ath12k/WCN7850" "$dest/ath12k/"
    fi
    if [[ -d "$source/ath12k/QCC2072" ]]; then
        cp -a --no-preserve=ownership "$source/ath12k/QCC2072" "$dest/ath12k/"
    fi

    # Bluetooth
    for candidate in hmtbtfw20.tlv hmtbtnv20.bin ornbtfw11.tlv ornnv11.bin; do
        cp -a --no-preserve=ownership "$source/qca/$candidate"* "$dest/qca/" 2>/dev/null || true
    done

    # GPU
    for candidate in gen80500_sqe.fw gen80500_gmu.bin gen80100_zap.mbn; do
        cp -a --no-preserve=ownership "$source/qcom/$candidate"* "$dest/qcom/" 2>/dev/null || true
    done

    # Glymur / ASUS platform firmware
    if [[ -d "$source/qcom/glymur" ]]; then
        cp -a --no-preserve=ownership "$source/qcom/glymur" "$dest/qcom/"
    fi

    # Copy firmware/audioreach/UX3607OA-tplg.bin from repo if present
    local repo_root
    repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || true)
    if [[ -n "$repo_root" && -s "$repo_root/firmware/audioreach/UX3607OA-tplg.bin" ]]; then
        install -Dm644 "$repo_root/firmware/audioreach/UX3607OA-tplg.bin" \
            "$dest/qcom/glymur/ASUSTeK/UX3607OA/UX3607OA-tplg.bin"
        install -Dm644 "$repo_root/firmware/audioreach/UX3607OA-tplg.bin" \
            "$dest/qcom/glymur/ASUSTeK/UX3607OA-tplg.bin"
    fi

    check_all
}

case ${1:---check} in
    --check)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        check_all
        ;;
    --from-linux)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        copy_from_linux "$2"
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
