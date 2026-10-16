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

Checks the known firmware requests of the current A16 baseline. A successful
check does not establish Bluetooth pairing or firmware redistribution rights.
See firmware/README.md for board-specific sources and remaining limits.
EOF
}

required=(
    ath12k/QCC2072/hw1.0/board-2.bin
    ath12k/QCC2072/hw1.0/firmware-2.bin
    qca/clnbtfw10.tlv
    qcom/gen80500_sqe.fw
    qcom/gen80500_gmu.bin
    qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn
    qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf
    qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn
    qcom/glymur/ASUSTeK/UX3607OA/cdsp_dtbs.elf
    qcom/glymur/ASUSTeK/UX3607OA-tplg.bin
)

check_all() {
    local missing=0 file found ext target
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
    echo "Complete: all known required files are present; hardware acceptance remains separate."
}

copy_from_linux() {
    local input=$1 source='' candidate
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
    if [[ -d "$source/ath12k/QCC2072" ]]; then
        cp -a --no-preserve=ownership "$source/ath12k/QCC2072" "$dest/ath12k/"
    fi

    # Bluetooth
    # Preserve board-specific NVM filenames; the missing rampatch alone does not identify them.
    if [[ -d "$source/qca" ]]; then
        cp -a --no-preserve=ownership "$source/qca/." "$dest/qca/"
    fi

    # GPU
    for candidate in gen80500_sqe.fw gen80500_gmu.bin gen80100_zap.mbn; do
        cp -a --no-preserve=ownership "$source/qcom/$candidate"* "$dest/qcom/" 2>/dev/null || true
    done

    # Glymur / ASUS platform firmware
    if [[ -d "$source/qcom/glymur" ]]; then
        cp -a --no-preserve=ownership "$source/qcom/glymur" "$dest/qcom/"
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
