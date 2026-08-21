#!/bin/bash
# glymur-camss-probe.sh — first probe of the CAMSS core (isp@acb7000) on glymur.
#
# Boot the "Zenbook A16 CAMSS isp registration test (2026-08-21)" GRUB entry
# (submenu "Test DTBs") first. Both i2c_qcom_cci and qcom_camss are
# blacklisted on that entry's cmdline on purpose — load by hand from a fully
# booted system, same reasoning as glymur-cci-probe.sh.
#
# Unlike cci0/cci1 (address-cross-validated against our own ACPI dump), the
# isp register map/interrupts come from a 2026-08-16 WIP patch of unconfirmed
# provenance for this exact hardware. Driver source review (camss-vfe.c
# msm_vfe_subdev_init(), and the equivalent csid/csiphy init) shows probe()
# only does devm_platform_ioremap_resource_byname() + devm_request_irq() +
# devm_clk_get() — no live register read/write — the same safe shape as
# cci's already-passed test. That is inference from reading the source, not
# a guarantee; go in expecting probe() to either succeed cleanly or fail
# cleanly with a driver error, not expecting certainty.
#
# This only answers: does the isp platform device probe, and do its
# subdevices register with v4l2/media? It does NOT start any video stream —
# no sensor is wired to an endpoint yet, so there is nothing to stream from.

set -u
LOG=${1:-/var/tmp/camss-probe-$(date +%m%d-%H%M).log}
exec > >(tee -a "$LOG") 2>&1
echo "=== camss probe $(date) -> $LOG"

echo "--- kernel"
uname -r

echo "--- DTB fingerprint (only the camss-test DTB has isp status=okay)"
ISP_STATUS=$(tr -d '\0' < /proc/device-tree/soc@0/isp@acb7000/status 2>/dev/null)
echo "isp status = ${ISP_STATUS:-<absent>}"
if [ "$ISP_STATUS" != "okay" ]; then
	echo "ABORT: wrong DTB. Reboot and pick the 'Zenbook A16 CAMSS isp"
	echo "       registration test' entry, not the cci-only one or default."
	exit 1
fi

echo "--- modules on disk: srcversion/vermagic before touching anything ---"
for m in i2c-qcom-cci qcom-camss; do
	p=$(find /lib/modules/"$(uname -r)" -name "${m}.ko" 2>/dev/null | head -1)
	echo "$m: $p"
	[ -n "$p" ] && modinfo -F srcversion "$p" && modinfo -F vermagic "$p"
done

echo "--- eDP healthy before? ---"
cat /sys/class/graphics/fb0/name 2>/dev/null

echo "--- loading i2c_qcom_cci (prerequisite, already proven-good) ---"
sudo modprobe i2c_qcom_cci
echo "rc=$?"

echo "--- loading qcom_camss ---"
sudo modprobe qcom_camss
RC=$?
echo "modprobe qcom_camss rc=$RC"

echo "--- dmesg tail: look for camss probe, request_irq, ioremap, media/v4l2 registration ---"
sudo dmesg | tail -80

echo "--- did isp bind? ---"
for d in /sys/bus/platform/devices/*isp* /sys/bus/platform/devices/*acb7000*; do
	[ -e "$d" ] || continue
	printf '%s -> %s\n' "$(basename "$d")" "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)"
done

echo "--- v4l2/media devices registered? ---"
ls /dev/v4l-subdev* /dev/media* 2>/dev/null
command -v media-ctl >/dev/null 2>&1 && sudo media-ctl -p 2>&1 | head -60

echo "--- eDP healthy after? ---"
cat /sys/class/graphics/fb0/name 2>/dev/null

echo "=== done. If it hung, this log has everything up to the hang — read it before rebooting."
