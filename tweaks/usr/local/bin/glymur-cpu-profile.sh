#!/bin/bash
# glymur-cpu-profile.sh — apply per-cluster frequency caps for a power profile.
#
# There is no EPP on this platform. EPP is an x86 concept (intel_pstate /
# amd-pstate HWP). Here the CPU is driven by scmi-cpufreq + schedutil, and the
# equivalent levers are: per-policy scaling_max_freq, the boost switch, and the
# Energy Model that EAS already uses for placement. This script drives the first
# two; EAS handles the rest by itself.
#
# Clusters (from Konrad's DT: capacity-dmips-mhz 1024 x6, 1372 x12, three
# scmi_perf domains):
#   policy0   cpus 0-5    efficiency   355.2 MHz - 3.6096 GHz   capacity 619
#   policy6   cpus 6-11   performance  355.2 MHz - 4.4544 GHz   capacity 1024
#   policy12  cpus 12-17  performance  355.2 MHz - 4.4544 GHz   capacity 1024
#   boost bins on policy6/policy12 only: 4.5696 GHz, 4.7232 GHz
#
# NOTE policy6 and policy12 are IDENTICAL — same capacity-dmips-mhz, same OPP
# table, same boost bins. They are two perf domains, not a "performance" and a
# "prime" tier. Nothing here treats them differently, on purpose.
#
# The cap values are taken from the kernel's own Energy Model
# (/sys/kernel/debug/energy_model/cpuN/ps:*/cost), which is energy per unit of
# work and is comparable across clusters. See docs/power-and-thermal.md.

set -u

CPUFREQ=/sys/devices/system/cpu/cpufreq
PROFILE="${1:-}"

log() { echo "glymur-cpu-profile: $*"; command -v logger >/dev/null && logger -t glymur-cpu-profile "$*"; }

usage() {
	echo "usage: $0 {performance|balanced|powersave|reset|status}" >&2
	exit 2
}

have_policy() { [ -d "$CPUFREQ/$1" ]; }

# Write $2 to policy $1's scaling_max_freq, clamped to what the policy allows.
set_max() {
	local pol="$1" want="$2" p="$CPUFREQ/$1" ceil
	have_policy "$pol" || { log "WARN: $pol absent, skipping"; return 0; }
	ceil=$(cat "$p/cpuinfo_max_freq")
	# cpuinfo_max_freq already reflects whether boost is on.
	if [ "$want" -gt "$ceil" ]; then
		log "WARN: $pol requested ${want} > ceiling ${ceil}, clamping"
		want="$ceil"
	fi
	echo "$want" > "$p/scaling_max_freq" 2>/dev/null \
		|| { log "ERROR: failed writing $p/scaling_max_freq"; return 1; }
}

# Boost must be set BEFORE scaling_max_freq: enabling it raises cpuinfo_max_freq
# to the top boost bin, and a max-freq write above the current ceiling is clamped.
set_boost() {
	local want="$1" pol p
	if [ -w "$CPUFREQ/boost" ]; then
		echo "$want" > "$CPUFREQ/boost" 2>/dev/null || log "WARN: global boost write failed"
	fi
	for pol in policy0 policy6 policy12; do
		p="$CPUFREQ/$pol/boost"
		[ -w "$p" ] && { echo "$want" > "$p" 2>/dev/null || true; }
	done
}

apply() {
	local boost="$1" e="$2" p="$3"
	set_boost "$boost"
	set_max policy0  "$e"
	set_max policy6  "$p"
	set_max policy12 "$p"
	log "applied ${PROFILE}: boost=${boost} policy0<=${e} policy6/12<=${p}"
}

status() {
	local pol p
	printf "%-9s %-18s %-10s %-10s %-10s %s\n" POLICY CPUS GOV MAX CEILING BOOST
	for pol in policy0 policy6 policy12; do
		p="$CPUFREQ/$pol"
		have_policy "$pol" || continue
		printf "%-9s %-18s %-10s %-10s %-10s %s\n" \
			"$pol" "$(cat $p/related_cpus | tr ' ' ',')" \
			"$(cat $p/scaling_governor)" "$(cat $p/scaling_max_freq)" \
			"$(cat $p/cpuinfo_max_freq)" "$(cat $p/boost 2>/dev/null)"
	done
}

case "$PROFILE" in
	# Everything open. schedutil deliberately, NOT the performance governor:
	# with fast_switch active and a 30 us transition latency this reaches the
	# same peak on demand without holding every core at max while idle.
	performance) apply 1 3609600 4723200 ;;

	# Cap where the cost curve turns steep. ~81% of each cluster's top frequency
	# for ~70% of its energy-per-unit-work:
	#   policy0  2918400 -> cost 3406 vs 4723 at max
	#   policy6  3628800 -> cost 5411 vs 7779 at max
	balanced)    apply 0 2918400 3628800 ;;

	# Deep in the flat part of the curve. ~51%/44% of max cost:
	#   policy0  2073600 -> cost 2422 vs 4723
	#   policy6  2400000 -> cost 3392 vs 7779
	powersave)   apply 0 2073600 2400000 ;;

	# Hand every policy back its full non-boost ceiling.
	reset)
		set_boost 0
		for pol in policy0 policy6 policy12; do
			have_policy "$pol" || continue
			cat "$CPUFREQ/$pol/cpuinfo_max_freq" > "$CPUFREQ/$pol/scaling_max_freq" 2>/dev/null || true
		done
		log "reset: all policies back to their non-boost ceiling"
		;;

	status) status ;;
	*) usage ;;
esac
