#!/bin/bash
# glymur-ov02c10-probe.sh — first probe of the front sensor (OV02C10) on glymur.
#
# Boot the "Zenbook A16 OV02C10 sensor probe test (2026-08-21)" GRUB entry
# (submenu "Test DTBs") first. i2c_qcom_cci, qcom_camss, and ov02c10 are all
# blacklisted on that entry's cmdline — load by hand, same reasoning as the
# earlier two probe scripts.
#
# What's grounded vs guessed, going in:
#   - MCLK4 @ 19.2 MHz: confirmed by literal string in the Windows driver's
#     own power-sequence binary (CAMF_RES_QRD.bin) — not a guess.
#   - CSIPHY4 (DT port@3): inference from the MCLK0/MCLK4 split + ACPI MPCS's
#     sibling-revision resources naming CSIPHY0+CSIPHY4 — reasoned, not proven.
#   - I2C address 0x36: from the Windows CRD sensor config JSON.
#   - CCI bus (cci0_i2c0): a genuine guess. No evidence found anywhere for
#     which of the 4 CCI buses this sensor is wired to. This is the one
#     dimension most likely to be wrong.
#   - Power supplies (dovdd/avdd/dvdd): deliberately OMITTED. These are real
#     fixed-voltage rails with no confirmed wiring — guessing wrong here
#     risks the sensor itself, unlike everything else tonight. Expect the
#     driver to fail cleanly around the power-on / chip-ID-read step without
#     them (a real-world Dell OV02C10 case with dummy-regulator fallback
#     failed with a clean -EREMOTEIO at exactly that step — not damage).
#
# This test's honest goal: does i2c_qcom_cci see anything answer at 0x36 on
# cci0_i2c0 at all (even a failed/incomplete probe attempt is informative),
# and does the endpoint linking to csiphy4 resolve without error.

set -u
LOG=${1:-/var/tmp/ov02c10-probe-$(date +%m%d-%H%M).log}
exec > >(tee -a "$LOG") 2>&1
echo "=== ov02c10 probe $(date) -> $LOG"

echo "--- kernel"
uname -r

echo "--- DTB fingerprint (only this DTB has the camera@36 node)"
if [ ! -e /proc/device-tree/soc@0/cci@ac15000/i2c-bus@0/camera@36 ]; then
	echo "ABORT: wrong DTB. Reboot and pick the 'Zenbook A16 OV02C10 sensor"
	echo "       probe test' entry."
	exit 1
fi
echo "camera@36 present under cci0_i2c0 - correct DTB"

echo "--- eDP healthy before? ---"
cat /sys/class/graphics/fb0/name 2>/dev/null

echo "--- loading modules by hand, in dependency order ---"
for m in i2c_qcom_cci qcom_camss ov02c10; do
	sudo modprobe "$m"
	echo "modprobe $m rc=$?"
done

echo "--- dmesg tail: look for ov02c10 probe attempt, EPROBE_DEFER, EREMOTEIO, or chip-id match ---"
sudo dmesg | tail -60

echo "--- did ov02c10 bind? (unlikely without power, but check) ---"
for d in /sys/bus/i2c/devices/*-0036 /sys/bus/i2c/devices/*0036; do
	[ -e "$d" ] || continue
	printf '%s -> %s\n' "$(basename "$d")" "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)"
done

echo "--- raw i2c presence check on cci0's buses (0x36), now that clocks are live ---"
for b in /sys/bus/i2c/devices/i2c-*; do
	n=$(cat "$b/name" 2>/dev/null)
	case "$n" in
		*[Cc][Cc][Ii]*) echo "-- $(basename "$b") ($n) --"; sudo i2cget -y "$(basename "$b" | tr -dc 0-9)" 0x36 0x00 2>&1 ;;
	esac
done

echo "--- eDP healthy after? ---"
cat /sys/class/graphics/fb0/name 2>/dev/null

echo "=== done. Read dmesg carefully either way — even a clean failure tells us"
echo "    something (EPROBE_DEFER = endpoint issue, EREMOTEIO = wrong bus/addr"
echo "    or unpowered, chip-id mismatch = right bus wrong address nearby)."
