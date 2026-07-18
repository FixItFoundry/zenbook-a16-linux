#!/bin/bash
# glymur A16 userspace thermal guard (v2): step-wise CPU freq throttle by hottest thermal zone.
# INTERIM safety net until DT thermal cooling-maps + fan control land (critical trip=115C hard shutdown).
# Steps DOWN fast when hot, releases SLOWLY (debounced) when cool -> holds steady, avoids flapping.
set -u
POL=/sys/devices/system/cpu/cpufreq
declare -A FULL
for p in "$POL"/policy*; do FULL["$p"]=$(cat "$p/cpuinfo_max_freq"); done
PERF=( full 2822400 1996800 1132800 )   # level 0..3 caps (perf clusters, kHz)
EFF=(  full 2208000 1516800 902400 )    # level 0..3 caps (eff cluster policy0)
apply(){ local lvl=$1 p c; for p in "$POL"/policy*; do
  if [ "$p" = "$POL/policy0" ]; then c=${EFF[$lvl]}; else c=${PERF[$lvl]}; fi
  [ "$c" = full ] && c=${FULL[$p]}
  echo "$c" > "$p/scaling_max_freq" 2>/dev/null || true
done; }
hot(){ local m=0 t z; for z in /sys/class/thermal/thermal_zone*/temp; do t=$(cat "$z" 2>/dev/null||echo 0); [ "$t" -gt "$m" ]&&m="$t"; done; echo $((m/1000)); }
lvl=0; plvl=0; cool=0; apply 0
while :; do
  T=$(hot)
  if   [ "$T" -ge 94 ]; then [ "$lvl" -lt 3 ] && lvl=$((lvl+1)); cool=0
  elif [ "$T" -ge 86 ]; then [ "$lvl" -lt 2 ] && lvl=$((lvl+1)); cool=0
  elif [ "$T" -le 76 ]; then cool=$((cool+1)); if [ "$cool" -ge 4 ] && [ "$lvl" -gt 0 ]; then lvl=$((lvl-1)); cool=0; fi
  else cool=0; fi
  apply "$lvl"
  if [ "$lvl" != "$plvl" ]; then logger -t glymur-thermal-guard "T=${T}C level ${plvl}->${lvl}"; plvl=$lvl; fi
  sleep 2
done
