#!/bin/bash
# glymur-ov02c10-probe.sh -- probe of the front sensor (OV02C10) on glymur.
#
# REWRITTEN 2026-09-06. The 2026-08-21 version of this script tested
# cci0_i2c0, which its own header flagged as "a genuine guess ... the one
# dimension most likely to be wrong". It was wrong. Do not re-run it.
#
# Boot ONE of the two 2026-09-06 GRUB entries (submenu "Test DTBs"):
#
#   zenbook-a16-ov02c10-cci1i2c0  "OV02C10 on cci1_i2c0, no supplies"
#       Runs on the CURRENT kernel. The sensor node has no dovdd/avdd/dvdd,
#       so the regulator core substitutes dummies. This answers the bus
#       question ONLY if UEFI happened to leave the camera rails voted up
#       across the handoff -- a real possibility, since RPMh votes persist.
#
#   zenbook-a16-ov02c10-full      "OV02C10 full wiring"
#       Needs a kernel built with patches/glymur-pmh0104-camera-ldos.patch.
#       CONFIG_REGULATOR_QCOM_RPMH=y, so that is a full rebuild, not a module
#       swap. On the current kernel this entry boots fine but is inert:
#       rpmh_regulator_init_vreg() rejects the unknown ldo4/ldo7 subnodes with
#       -EINVAL, so regulators-5 never probes and the sensor defers forever.
#       (Blast radius is that node only -- the other PMICs are separate
#       platform devices and are unaffected.)
#
# i2c_qcom_cci, qcom_camss and ov02c10 are all blacklisted on both entries'
# cmdlines -- load by hand, same reasoning as the earlier probe scripts.
#
# What is grounded vs inferred, going in (full evidence table in
# docs/hardware.md):
#   - cci1_i2c0: the AeoB blob muxes {gpio=106, func=1}; PINGROUP() puts
#     msm_mux_gpio at funcs[0], so func 1 on pin 106 is cci_i2c_scl, and
#     105/106 is the cci1_i2c0 pin pair. Identical in BOTH sensors' blobs,
#     which is what makes it a shared bus. Strong.
#     FALLBACK if 0x36 does not ACK: cci1_i2c1 (TLMM 235/236, function
#     asc_cci) -- what the ASUS Zenbook A14 uses. One bit, one boot.
#   - MCLK4 @ 19.2 MHz on gpio100: literal string in the blob; gpio100 is the
#     only MCLK4-capable pin on the SoC (cam_mclk_groups[] is 96-99). Proven.
#   - reset gpio239: front-sensor-only TLMMGPIO entry. Strong, unproven. If
#     reset never releases, try function "egpio" in cam_rgb_default.
#   - 0x36: Windows CRD sensor config; matches the A14 and Yoga Slim 7x.
#   - rails LDO4_I0 1.8V / LDO7_I0 2.8V: proven from the blob. avdd and dvdd
#     share the 2.8V rail -- two LDOs is not a missing DVDD.
#
# Honest goal: does anything ACK at 0x36 on a CCI bus, and does the endpoint
# to csiphy4 resolve without error.

set -u
LOG=${1:-/var/tmp/ov02c10-probe-$(date +%m%d-%H%M).log}
exec > >(tee -a "$LOG") 2>&1
echo "=== ov02c10 probe $(date) -> $LOG"

echo "--- kernel"
uname -r

echo "--- DTB fingerprint (only this DTB has the camera@36 node)"
if [ ! -e /proc/device-tree/soc@0/cci@ac16000/i2c-bus@0/camera@36 ]; then
	echo "ABORT: wrong DTB. camera@36 is not under cci1_i2c0. Reboot and pick"
	echo "       one of the 2026-09-06 entries, NOT the superseded 2026-08-21"
	echo "       'OV02C10 sensor probe test' (that one is cci0_i2c0)."
	exit 1
fi
echo "camera@36 present under cci1_i2c0 (cci@ac16000/i2c-bus@0) - correct DTB"
if [ -e /proc/device-tree/soc@0/cci@ac16000/i2c-bus@0/camera@36/avdd-supply ]; then
	echo "variant: FULL wiring (supplies present) - needs the pmh0104-LDO kernel"
else
	echo "variant: no-supplies (dummy regulators) - runs on the current kernel"
fi

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

echo "--- raw i2c presence check on ALL CCI buses (0x36), now that clocks are live ---"
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
