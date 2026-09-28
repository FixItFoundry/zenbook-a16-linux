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
    ath12k/QCC2072/hw1.0/Notice.txt
    ath12k/QCC2072/hw1.0/board-2.bin
    ath12k/QCC2072/hw1.0/firmware-2.bin
    qca/ornbtfw11.tlv
    qca/ornnv11.bin
    qcom/glymur/adsp.mbn
    qcom/glymur/adsp_dtb.mbn
    qcom/glymur/adspr.jsn
    qcom/glymur/adsps.jsn
    qcom/glymur/adspua.jsn
    qcom/glymur/cdsp.mbn
    qcom/glymur/cdsp_dtb.mbn
    qcom/glymur/cdspr.jsn
    qcom/glymur/gen80100_zap.mbn
    qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin
)

check_all() {
    local missing=0 file found ext
    echo "Checking $dest"
    for file in "${required[@]}"; do
        found=""
        for ext in "" ".xz" ".zst"; do
            if [[ -s "$dest/$file$ext" ]]; then
                found="$file$ext"
                break
            fi
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
        if [[ -d "$candidate/ath12k/QCC2072/hw1.0" ]]; then
            source=$candidate
            break
        fi
    done
    [[ -n "$source" ]] || {
        echo "error: no ath12k/QCC2072/hw1.0 tree found below $input" >&2
        return 1
    }

    echo "Copying from $source to $dest"
    install -d "$dest/ath12k" "$dest/qca" "$dest/qcom"
    cp -a --no-preserve=ownership "$source/ath12k/QCC2072" "$dest/ath12k/"
    for candidate in ornbtfw11.tlv ornnv11.bin; do
        cp -a --no-preserve=ownership "$source/qca/$candidate"* "$dest/qca/" 2>/dev/null || true
    done
    cp -a --no-preserve=ownership "$source/qcom/glymur" "$dest/qcom/"
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
