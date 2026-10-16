#!/bin/bash
# Apply SCMI frequency caps from the measured Energy Model; see docs/power-and-thermal.md.
# policy0 is the efficiency cluster; policy6 and policy12 have identical performance OPPs.

set -u

CPUFREQ=/sys/devices/system/cpu/cpufreq
PROFILE="${1:-}"

log() { echo "glymur-cpu-profile: $*"; if command -v logger >/dev/null; then logger -t glymur-cpu-profile "$*" || :; fi; }

usage() {
	echo "usage: $0 {performance|balanced|powersave|reset|status}" >&2
	exit 2
}

have_policy() { [ -d "$CPUFREQ/$1" ]; }

# Write $2 to policy $1's scaling_max_freq, clamped to what the policy allows.
set_max() {
	local pol="$1" want="$2" p="$CPUFREQ/$1" ceil
	have_policy "$pol" || { log "ERROR: $pol absent"; return 1; }
	ceil=$(cat "$p/cpuinfo_max_freq") || return 1
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
	local found=0
	if [ -e "$CPUFREQ/boost" ]; then
		echo "$want" > "$CPUFREQ/boost" 2>/dev/null || { log "ERROR: global boost write failed"; return 1; }
		found=1
	fi
	for pol in policy0 policy6 policy12; do
		p="$CPUFREQ/$pol/boost"
		[ -e "$p" ] || continue
		echo "$want" > "$p" 2>/dev/null || { log "ERROR: boost write failed: $p"; return 1; }
		found=1
	done
	[ "$found" = 1 ] || { log "ERROR: no boost control found"; return 1; }
}

apply() {
	local boost="$1" e="$2" p="$3"
	set_boost "$boost" || return 1
	set_max policy0  "$e" || return 1
	set_max policy6  "$p" || return 1
	set_max policy12 "$p" || return 1
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
		set_boost 0 || exit 1
		for pol in policy0 policy6 policy12; do
			have_policy "$pol" || { log "ERROR: $pol absent"; exit 1; }
			cat "$CPUFREQ/$pol/cpuinfo_max_freq" > "$CPUFREQ/$pol/scaling_max_freq" 2>/dev/null || exit 1
		done
		log "reset: all policies back to their non-boost ceiling"
		;;

	status) status ;;
	*) usage ;;
esac
