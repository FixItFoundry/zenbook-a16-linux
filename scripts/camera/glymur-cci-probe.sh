#!/bin/bash
# glymur-cci-probe.sh — first probe of cci0/cci1 on glymur (cci-test DTB).
#
# Boot the "Zenbook A16 CCI0/CCI1 registration test (2026-08-21)" GRUB entry
# (submenu "Test DTBs") first. i2c_qcom_cci is blacklisted on that entry's
# cmdline on purpose, so we load it by hand from a fully booted system: the
# interrupt numbers (GIC_SPI 456 for cci0, 859 for cci1) are a positional
# inference from decoding the WoA ACPI CAMP._CRS byte buffer, corroborated by
# but not proven against docs/hardware.md's own account, and a wrong number
# should fail at request_irq() rather than hang — but we want that failure (or
# success) to happen at a known instant with a synced log, not mid-boot.
#
# CAMSS (the `isp` node) stays disabled. This only answers: do cci0/cci1
# probe, and does the CCI HW version register read back sane?

set -u
LOG=${1:-/var/tmp/cci-probe-$(date +%m%d-%H%M).log}
exec > >(tee -a "$LOG") 2>&1
echo "=== cci probe $(date) -> $LOG"

echo "--- kernel"
uname -r

echo "--- DTB fingerprint (only the cci-test DTB has cci0/cci1 at all)"
CCI0_STATUS=$(tr -d '\0' < /proc/device-tree/soc@0/cci@ac15000/status 2>/dev/null)
CCI1_STATUS=$(tr -d '\0' < /proc/device-tree/soc@0/cci@ac16000/status 2>/dev/null)
echo "cci0 status = ${CCI0_STATUS:-<absent>}"
echo "cci1 status = ${CCI1_STATUS:-<absent>}"
if [ "$CCI0_STATUS" != "okay" ] || [ "$CCI1_STATUS" != "okay" ]; then
	echo "ABORT: wrong DTB, or cci nodes not okay. /proc/cmdline cannot tell you"
	echo "       this — the device-tree status can. Reboot and pick the"
	echo "       'Zenbook A16 CCI0/CCI1 registration test' entry."
	exit 1
fi

echo "--- isp (CAMSS core) must still be disabled — this test is CCI-only"
tr -d '\0' < /proc/device-tree/soc@0/isp@acb7000/status 2>/dev/null || echo "<absent, fine>"

echo "--- module on disk vs what would load (srcversion check before touching anything)"
MODPATH=/lib/modules/$(uname -r)/kernel/drivers/i2c/busses/i2c-qcom-cci.ko
modinfo -F srcversion "$MODPATH"
modinfo -F vermagic "$MODPATH"

echo "--- eDP still healthy before we touch anything? (this test must not regress the display)"
cat /sys/class/graphics/fb0/name 2>/dev/null

echo "--- loading i2c_qcom_cci by hand ---"
sudo modprobe i2c_qcom_cci
RC=$?
echo "modprobe rc=$RC"

echo "--- dmesg tail, look for cci probe / request_irq / CCI HW version ---"
dmesg | tail -40

echo "--- did it bind? ---"
for d in /sys/bus/platform/devices/*cci*; do
	[ -e "$d" ] || continue
	printf '%s -> %s\n' "$(basename "$d")" "$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)"
done

echo "--- new i2c buses? (cci0_i2c0/1, cci1_i2c0/1 — should be 4 new adapters if both probed) ---"
for d in /sys/bus/i2c/devices/i2c-*; do
	n=$(cat "$d/name" 2>/dev/null)
	case "$n" in
		*[Cc][Cc][Ii]*) echo "$(basename "$d"): $n" ;;
	esac
done

echo "--- eDP still healthy after? ---"
cat /sys/class/graphics/fb0/name 2>/dev/null

echo "=== done. If it hung, this log has everything up to the hang — read it before rebooting."
