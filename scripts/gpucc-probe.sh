#!/bin/bash
# gpucc-probe.sh — first probe of gpu_cc on glymur (test64 + gpucc-glymur.ko).
#
# Boot the "gpucc1" GRUB entry first. The module is blacklisted on that entry's
# cmdline on purpose, so we load it by hand from a fully booted system: if the
# register window at 0x3d90000 is unpowered or XPU-gated the read can hang the
# SoC, and we want that to happen at a known instant with a synced log rather
# than mid-boot.
#
# The GPU itself stays disabled. This only answers: does gpu_cc probe?

set -u
LOG=${1:-/var/tmp/gpucc-probe-$(date +%m%d-%H%M).log}
exec > >(tee -a "$LOG") 2>&1
echo "=== gpucc probe $(date) -> $LOG"

echo "--- kernel"
uname -r

echo "--- DTB fingerprint (must be qcom,glymur-gpucc, i.e. test64)"
DTB_COMPAT=$(tr -d '\0' < /proc/device-tree/soc@0/clock-controller@3d90000/compatible 2>/dev/null)
echo "gpucc node compatible = ${DTB_COMPAT:-<absent>}"
if [ "$DTB_COMPAT" != "qcom,glymur-gpucc" ]; then
	echo "ABORT: wrong DTB. /proc/cmdline cannot tell you this — the compatible can."
	echo "       Reboot and pick the 'gpucc1' entry."
	exit 1
fi

echo "--- eDP still healthy? (test64 must not regress the display)"
cat /sys/class/graphics/fb0/name
cat /sys/class/drm/card*-eDP-1/status

echo "--- module on disk"
DISK=$(modinfo -F srcversion gpucc-glymur 2>/dev/null)
echo "disk srcversion = ${DISK:-<not found>}"
[ -n "$DISK" ] || { echo "ABORT: gpucc-glymur.ko not installed"; exit 1; }

echo "--- clocks before"
BEFORE=$(ls /sys/kernel/debug/clk 2>/dev/null | grep -c '^gpu_cc' || true)
echo "gpu_cc clocks currently exposed: $BEFORE"

echo "--- syncing log before the risky call"
sync

echo "=== modprobe gpucc-glymur  (if the box dies here, that IS the result) ==="
sudo modprobe gpucc-glymur
RC=$?
echo "modprobe rc=$RC"
sync

echo "--- did it bind?"
ls -l /sys/bus/platform/drivers/gpucc-glymur/ 2>/dev/null | grep 3d90000 \
	|| echo "NOT BOUND to 3d90000.clock-controller"

echo "--- running vs disk srcversion (traps memory: verify the module that ran)"
RUN=$(cat /sys/module/gpucc_glymur/srcversion 2>/dev/null)
echo "running=${RUN:-<not loaded>}  disk=$DISK"
[ "$RUN" = "$DISK" ] || echo "WARNING: mismatch — the experiment may not have run what you built"

echo "--- gpu_cc clocks now"
ls /sys/kernel/debug/clk 2>/dev/null | grep '^gpu_cc' | head -40
AFTER=$(ls /sys/kernel/debug/clk 2>/dev/null | grep -c '^gpu_cc' || true)
echo "gpu_cc clock count: $BEFORE -> $AFTER"

echo "--- GDSC / power domains"
grep -rn . /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | grep -i "gpu" | head

echo "--- dmesg"
sudo dmesg | grep -iE "gpucc|gpu_cc|3d90000|qcom,glymur-gpucc|Oops|panic|Unhandled fault" | tail -30

echo "=== done. verdict: $AFTER gpu_cc clocks (0 = no bind, >0 = base address CONFIRMED)"
sync
