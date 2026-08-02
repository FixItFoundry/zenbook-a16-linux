#!/bin/bash
# glymur-usb-recover.sh — recover the USB stack after an s2idle resume on glymur.
#
# Replaces the `authorized` toggle approach, which cannot work for the fault this
# machine actually hits.
#
# THE FAULT (observed 2026-08-02):
#   xhci-hcd xhci-hcd.1.auto: WARNING: Host System Error
#   arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402 [Format=2 TF]
#
#   The controller DMA'd to an IOVA the SMMU could not translate. A Host System
#   Error is FATAL to an xHCI controller: it stops allocating device slots, so
#   every re-enumeration attempt fails with
#       usb usbN-portM: couldn't allocate usb_device
#   and no amount of replugging, `authorized` toggling, or USB-device-level
#   rebinding will help. The controller itself has to be torn down and rebuilt.
#
# WHY `authorized` CANNOT FIX IT: that attribute controls whether devices are
# permitted to attach to a hub. It never touches the controller. Re-attach is
# exactly what is already failing.
#
# Usage:
#   sudo bash glymur-usb-recover.sh            # diagnose only, change nothing
#   sudo bash glymur-usb-recover.sh --recover  # escalate until USB works
#
# ⚠️ Keyboard/touchpad on this laptop are I2C-HID and NVMe is PCIe, so cycling
#    the USB controllers does not cost you input or storage.

set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
DO=${1:-}

hr() { printf '\n=== %s ===\n' "$*"; }

# ---------------------------------------------------------------- diagnose
hr "controllers"
for x in /sys/bus/platform/devices/xhci-hcd.*; do
	[ -e "$x" ] || continue
	printf '  %-18s parent=%-14s bound=%s\n' \
		"$(basename "$x")" \
		"$(basename "$(readlink -f "$x/.." )")" \
		"$([ -e "$x/driver" ] && echo yes || echo NO)"
done

hr "root hubs (runtime=suspended on an EMPTY hub is normal, not a fault)"
for d in /sys/bus/usb/devices/usb*/; do
	printf '  %-6s runtime=%-10s control=%s\n' \
		"$(basename "$d")" \
		"$(cat "$d/power/runtime_status" 2>/dev/null)" \
		"$(cat "$d/power/control" 2>/dev/null)"
done

hr "devices attached (root hubs only == nothing enumerated)"
lsusb | grep -v "root hub" || echo "  NONE — only root hubs present"

hr "the fatal signatures"
HSE=$(dmesg | grep -c "Host System Error")
SMMU=$(dmesg | grep -c "Unhandled context fault")
ALLOC=$(dmesg | grep -c "couldn't allocate usb_device")
echo "  Host System Error      : $HSE"
echo "  SMMU context faults    : $SMMU"
echo "  couldn't allocate      : $ALLOC"
dmesg | grep -E "Host System Error|Unhandled context fault" | tail -4 | sed 's/^/    /'

if [ "$HSE" -eq 0 ] && [ "$ALLOC" -eq 0 ]; then
	echo
	echo "  No HSE and no allocation failures. This script fixes the HSE fault;"
	echo "  if USB is misbehaving it is something else. Do NOT cycle blindly."
fi

[ "$DO" = "--recover" ] || {
	echo
	echo "Diagnosis only. Re-run with --recover to act."
	exit 0
}

# ---------------------------------------------------------------- recover
# Ladder, cheapest first. Stop as soon as a device enumerates.

# true when at least one non-root-hub device is enumerated
works() { [ "$(lsusb 2>/dev/null | grep -vc 'root hub')" -gt 0 ]; }

hr "rung 3 — force runtime resume (cheap, fixes only a sleeping healthy device)"
for d in /sys/bus/usb/devices/usb*/; do echo on > "$d/power/control" 2>/dev/null; done
sleep 3
if works; then echo "  recovered at rung 3"; exit 0; fi
echo "  no change (expected if the controller is in HSE)"

hr "rung 6 — rebind the xHCI PLATFORM devices (the real fix for HSE)"
DRV=/sys/bus/platform/drivers/xhci-hcd
for x in /sys/bus/platform/devices/xhci-hcd.*; do
	[ -e "$x" ] || continue
	n=$(basename "$x")
	echo "  unbind $n"
	echo "$n" > "$DRV/unbind" 2>/dev/null || echo "    (was not bound)"
	sleep 2
	echo "  bind   $n"
	echo "$n" > "$DRV/bind" 2>/dev/null || echo "    ⛔ bind FAILED for $n"
	sleep 3
done

sleep 5
hr "result"
lsusb
for d in /sys/bus/usb/devices/usb*/; do echo auto > "$d/power/control" 2>/dev/null; done   # restore normal PM

if works; then
	echo
	echo "✅ USB devices enumerated again."
else
	echo
	echo "⛔ Still nothing. The controller did not recover from the HSE."
	echo "   Next rung is a reboot — but capture this first, it is the useful evidence:"
	echo "     dmesg | grep -E 'Host System Error|Unhandled context fault|couldn.t allocate' > ~/usb-hse.txt"
fi
