#!/bin/bash
# glymur-coolmaps-check.sh - verify CPU thermal cooling-maps are bound AND actuate.
#
# ⛔ THE ORIGINAL VERSION OF THIS SCRIPT WAS BROKEN AND INVENTED A BUG.
# It counted /sys/class/thermal/thermal_zone*/cdev*_type. That attribute does
# NOT exist on this kernel - a bound zone has cdev0 (a symlink), cdev0_trip_point
# and cdev0_weight, and no cdev0_type. So it returned 0 whether the maps were
# bound or not, and that zero became the "no thermal zone binds them" gap that
# sat in the project notes and the README. Rewritten 2026-07-31.
set -u
echo "=== booted DTB carries cpu cooling-maps? ==="
echo -n "  cooling-maps nodes in live DT: "
ls -d /proc/device-tree/thermal-zones/*/cooling-maps 2>/dev/null | wc -l
echo "  (55 = coolmaps DTB, 14 = scmipoll/GPU-only)"

echo "=== zones bound to a cpufreq cooling device ==="
n=0
for z in /sys/class/thermal/thermal_zone*; do
	[ -e "$z/cdev0" ] || continue
	case "$(cat "$(readlink -f "$z/cdev0")/type" 2>/dev/null)" in
	cpufreq-*) n=$((n + 1)) ;;
	esac
done
echo "  $n   (want 41)"
[ "$n" -eq 41 ] && echo "  PASS" || echo "  FAIL - are you on the coolmaps DTB?"

echo "=== example binding ==="
for z in /sys/class/thermal/thermal_zone*; do
	[ "$(cat "$z/type" 2>/dev/null)" = "cpu-0-0-0-thermal" ] || continue
	echo "  $z ($(cat "$z/type")) policy=$(cat "$z/policy")"
	for tp in "$z"/trip_point_*_type; do
		echo "    $(basename "$tp"): $(cat "$tp") @ $(cat "${tp%_type}_temp")"
	done
	echo "    cdev0 -> $(cat "$(readlink -f "$z/cdev0")/type") trip=$(cat "$z/cdev0_trip_point")"
done

echo "=== actuation (emulated - no load needed) ==="
echo "  ⛔ NEVER emulate >= the critical trip (115000): the thermal core calls"
echo "     hw_protection_shutdown and powers the machine off instantly."
Z=""
for z in /sys/class/thermal/thermal_zone*; do
	[ "$(cat "$z/type" 2>/dev/null)" = "cpu-0-0-0-thermal" ] && Z="$z" && break
done
if [ -n "$Z" ] && [ -w "$Z/emul_temp" -o "$(id -u)" = 0 ]; then
	CD=/sys/class/thermal/cooling_device0
	for T in 96000 104000 112000; do
		sudo -n sh -c "echo $T > $Z/emul_temp" 2>/dev/null || { echo "  (needs root)"; break; }
		sleep 2
		echo "    emul=$T -> cur_state=$(cat $CD/cur_state)"
	done
	sudo -n sh -c "echo 0 > $Z/emul_temp" 2>/dev/null
	sleep 2
	echo "    restored -> cur_state=$(cat $CD/cur_state) temp=$(cat $Z/temp)"
else
	echo "  (skipped - run as root to exercise it)"
fi
