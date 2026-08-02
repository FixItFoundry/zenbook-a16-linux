#!/bin/bash
# glymur-fetch-firmware.sh — populate /lib/firmware on a glymur (Zenbook A16) image
# from firmware the USER already owns, on their own device.
#
# WHY THIS EXISTS
#   The Qualcomm/ASUS blobs this laptop needs are proprietary and cannot be
#   legally redistributed, so no image in this project ships them. That is what
#   makes an image publishable at all. This script closes the gap on first boot
#   by copying firmware off something the user already has.
#
# TWO SOURCES, easiest first:
#   1. An existing Linux install on this machine that already works.
#   2. The device's own Windows / WoA installation (the driver store).
#
# ⛔ This copies files from YOUR device to YOUR device. Do not redistribute what
#    it produces.
#
#   sudo ./glymur-fetch-firmware.sh --from-linux /mnt/oldroot
#   sudo ./glymur-fetch-firmware.sh --from-windows /mnt/windows
#   sudo ./glymur-fetch-firmware.sh --check          # what is present/missing

set -uo pipefail
DEST=${DEST:-/lib/firmware}

# What the drivers on this build actually request.
WANT_ATH12K="amss.bin m3.bin board.bin regdb.bin aux_ucode.bin"
ATH_DIR="ath12k/QCC2072/hw1.0"

ok=0; miss=0
chk() { # path label
	if [ -s "$DEST/$1" ]; then printf '  ✅ %-52s %s\n' "$1" "$(du -h "$DEST/$1" | cut -f1)"; ok=$((ok+1))
	else printf '  ❌ %-52s MISSING  (%s)\n' "$1" "$2"; miss=$((miss+1)); fi
}

check_all() {
	echo "=== Wi-Fi (ath12k / QCC2072) ==="
	for f in $WANT_ATH12K; do chk "$ATH_DIR/$f" "Wi-Fi will not work"; done
	echo "=== Audio / ADSP ==="
	chk "qcom/glymur/adsp.mbn" "no audio"
	chk "qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn" "no audio"
	chk "qcom/glymur/GLYMUR-A16-tplg.bin" "no audio routing — THIS ONE IS OPEN SOURCE, build from firmware/tplg/"
	echo "=== Regulatory (usually from your distro's linux-firmware) ==="
	chk "regulatory.db" "Wi-Fi regdomain"
	echo
	echo "  present: $ok   missing: $miss"
	[ "$miss" -eq 0 ] && echo "  ✅ complete" || echo "  ⚠️  incomplete — see firmware/README.md"
}

copy_from_linux() {
	SRC=$1
	[ -d "$SRC" ] || { echo "no such directory: $SRC"; exit 1; }
	for sub in "lib/firmware" "usr/lib/firmware" ""; do
		[ -d "$SRC/$sub/ath12k" ] && { FW="$SRC/$sub"; break; }
	done
	[ -n "${FW:-}" ] || { echo "⛔ no ath12k tree found under $SRC — is that a Linux root?"; exit 1; }
	echo "source: $FW"
	for d in ath12k qcom/glymur; do
		[ -d "$FW/$d" ] || { echo "  ⚠️  $d not present at source, skipping"; continue; }
		mkdir -p "$DEST/$(dirname "$d")"
		cp -a --no-preserve=ownership "$FW/$d" "$DEST/$(dirname "$d")/" && echo "  copied $d"
	done
	[ -f "$FW/regulatory.db" ] && cp -a "$FW/regulatory.db"* "$DEST/" && echo "  copied regulatory.db"
	echo; check_all
}

copy_from_windows() {
	SRC=$1
	REPO="$SRC/Windows/System32/DriverStore/FileRepository"
	[ -d "$REPO" ] || { echo "⛔ not a Windows root (no $REPO)"; exit 1; }
	echo "Scanning the driver store. This is READ-ONLY — nothing is written to Windows."
	echo
	echo "⚠️  The Windows filenames do NOT match the Linux ones. This step cannot be"
	echo "    fully automated safely, so it REPORTS candidates and you place them."
	echo "    Match by role and size; see firmware/README.md."
	echo
	echo "=== candidate Qualcomm firmware blobs found ==="
	find "$REPO" -iname "*.mbn" -o -iname "amss*" -o -iname "m3.bin" -o -iname "board*.bin" 2>/dev/null \
		| head -40 | while read -r f; do printf '  %10s  %s\n' "$(du -h "$f" | cut -f1)" "${f#$REPO/}"; done
	echo
	echo "Place them as:"
	echo "  $DEST/$ATH_DIR/{amss.bin,m3.bin,board.bin,regdb.bin,aux_ucode.bin}"
	echo "  $DEST/qcom/glymur/adsp.mbn"
	echo "  $DEST/qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn"
	echo
	echo "Then re-run:  $0 --check"
}

case "${1:---check}" in
	--check)        check_all ;;
	--from-linux)   [ $# -ge 2 ] || { echo "usage: $0 --from-linux <path-to-linux-root>"; exit 1; }
	                [ "$(id -u)" = 0 ] || { echo "needs root"; exit 1; }; copy_from_linux "$2" ;;
	--from-windows) [ $# -ge 2 ] || { echo "usage: $0 --from-windows <path-to-windows-root>"; exit 1; }
	                copy_from_windows "$2" ;;
	*) sed -n '2,24p' "$0"; exit 1 ;;
esac
