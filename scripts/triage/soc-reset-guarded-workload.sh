#!/usr/bin/env bash
# Capture low-level platform evidence around an explicitly authorized workload.
# This script does not change governors, frequency limits, ASPM, thermal trips,
# watchdogs, boot files, or services.  It refuses to start without --execute.
# It deliberately does not read the EC fan tachometer: prior EC polling during
# CPU load coincided with a hard reset on this machine.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  soc-reset-guarded-workload.sh --execute [options] -- COMMAND [ARG ...]

Options:
  --evidence-dir DIR    Persistent output directory (required; must not exist)
  --max-seconds N       Stop the workload after N seconds (default: 900)
  --sample-seconds N    Sampling interval (default: 1)
  --preflight-temp MC   Refuse to start at/above this temperature (default: 70000)
  --stop-temp MC        Stop at/above this temperature (default: 92000)
  --stop-nvme-temp MC   Stop at/above this NVMe temperature (default: 75000)
  --execute             Acknowledge that COMMAND will be run

Example (do not run without separate authorization):
  scripts/triage/soc-reset-guarded-workload.sh --execute \
    --evidence-dir /home/jcasco/Projects/zenbook-a16-linux/internal-docs/evidence/soc-reset-j4-YYYYMMDD-HHMMSS -- \
    make -C /path/to/linux O=/path/to/fresh-obj ARCH=arm64 -j4 \
      Image modules dtbs

Automatic stop conditions are: temperature threshold, new PCIe AER counter,
new kernel PCIe/thermal/lockup/SCMI-timeout message, missing cpufreq policy,
NVMe temperature threshold, timeout, or loss of AC power.

The wrapper intentionally does not poll the EC fan tachometer.  Do not add an
EC read to the workload loop; prior EC polling under CPU load coincided with a
hard reset on this machine.
EOF
}

execute=0
evidence_dir=
max_seconds=900
sample_seconds=1
preflight_temp=70000
stop_temp=92000
stop_nvme_temp=75000

while (( $# )); do
    case "$1" in
        --execute) execute=1; shift ;;
        --evidence-dir) evidence_dir=${2:?missing directory}; shift 2 ;;
        --max-seconds) max_seconds=${2:?missing seconds}; shift 2 ;;
        --sample-seconds) sample_seconds=${2:?missing seconds}; shift 2 ;;
        --preflight-temp) preflight_temp=${2:?missing temperature}; shift 2 ;;
        --stop-temp) stop_temp=${2:?missing temperature}; shift 2 ;;
        --stop-nvme-temp) stop_nvme_temp=${2:?missing temperature}; shift 2 ;;
        --) shift; break ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

(( execute == 1 )) || {
    printf '%s\n' 'Refusing to run a workload without --execute.' >&2
    usage >&2
    exit 64
}
[[ -n "$evidence_dir" && $# -gt 0 ]] || {
    printf '%s\n' '--evidence-dir and a command after -- are required.' >&2
    usage >&2
    exit 64
}
[[ "$evidence_dir" == /* ]] || {
    printf '%s\n' '--evidence-dir must be an absolute path.' >&2
    exit 64
}
[[ ! -e "$evidence_dir" ]] || {
    printf 'Evidence directory already exists: %s\n' "$evidence_dir" >&2
    exit 73
}
for value in "$max_seconds" "$sample_seconds" "$preflight_temp" \
    "$stop_temp" "$stop_nvme_temp"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
        printf 'Expected a positive integer, got: %s\n' "$value" >&2
        exit 64
    }
done
(( preflight_temp < stop_temp )) || {
    printf '%s\n' 'Preflight temperature must be below stop temperature.' >&2
    exit 64
}

umask 077
mkdir -p -- "$evidence_dir"
summary_log=$evidence_dir/summary.log
samples_log=$evidence_dir/samples.tsv
thermal_log=$evidence_dir/thermal.tsv
cpufreq_log=$evidence_dir/cpufreq.tsv
cooling_log=$evidence_dir/cooling.tsv
aer_log=$evidence_dir/aer.tsv
kernel_log=$evidence_dir/kernel-follow.log
build_log=$evidence_dir/workload.log
stop_file=$evidence_dir/STOP

workload_pid=
journal_pid=
stop_reason=

sync_logs() {
    local path
    for path in "$summary_log" "$samples_log" "$thermal_log" \
        "$cpufreq_log" "$cooling_log" "$aer_log" "$kernel_log" \
        "$build_log" "$stop_file"; do
        [[ -e "$path" ]] && sync -d -- "$path" 2>/dev/null || true
    done
}

stop_workload() {
    local signal
    [[ -n "$workload_pid" ]] || return 0
    kill -0 "$workload_pid" 2>/dev/null || return 0
    for signal in INT TERM KILL; do
        kill -"$signal" -- "-$workload_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 "$workload_pid" 2>/dev/null || return 0
            sleep 1
        done
    done
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    stop_workload
    if [[ -n "$journal_pid" ]]; then
        kill "$journal_pid" 2>/dev/null || true
        wait "$journal_pid" 2>/dev/null || true
    fi
    sync_logs
    exit "$status"
}
trap cleanup EXIT INT TERM HUP

max_thermal_temp() {
    local path value max=0
    for path in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "$path" ]] || continue
        value=$(<"$path")
        [[ "$value" =~ ^-?[0-9]+$ ]] || continue
        (( value > max )) && max=$value
    done
    printf '%d\n' "$max"
}

ac_online() {
    local path type online found=0
    for path in /sys/class/power_supply/*; do
        [[ -r "$path/type" && -r "$path/online" ]] || continue
        type=$(<"$path/type")
        [[ "$type" == Mains || "$type" == USB || "$type" == USB_C ]] || continue
        found=1
        online=$(<"$path/online")
        [[ "$online" == 1 ]] && return 0
    done
    (( found == 0 )) && return 0
    return 1
}

aer_total() {
    local path line value sum=0
    for path in /sys/bus/pci/devices/0005:00:00.0/aer_* \
        /sys/bus/pci/devices/0005:01:00.0/aer_*; do
        [[ -r "$path" ]] || continue
        while IFS= read -r line; do
            value=${line##* }
            [[ "$value" =~ ^[0-9]+$ ]] && sum=$((sum + value))
        done < "$path"
    done
    printf '%d\n' "$sum"
}

nvme_temp_millic() {
    local path value
    for path in /sys/class/nvme/nvme0/device/hwmon/hwmon*/temp1_input \
        /sys/class/hwmon/hwmon*/temp1_input; do
        [[ -r "$path" ]] || continue
        case "$(readlink -f "$path" 2>/dev/null)" in
            *nvme*)
                value=$(<"$path")
                [[ "$value" =~ ^[0-9]+$ ]] && { printf '%d\n' "$value"; return; }
                ;;
        esac
    done
    printf '%d\n' 0
}

policy_count() {
    local path count=0
    for path in /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq; do
        [[ -r "$path" ]] && (( count += 1 ))
    done
    printf '%d\n' "$count"
}

record_snapshot() {
    local iso=$1 elapsed=$2 max_temp=$3 nvme_temp=$4 aer=$5
    local path type value policy
    printf '%s\t%s\t%s\t%s\t%s\t' \
        "$iso" "$elapsed" "$max_temp" "$nvme_temp" "$aer" >> "$samples_log"
    tr '\n' ' ' < /proc/loadavg >> "$samples_log"
    printf '\t' >> "$samples_log"
    awk '/^(some|full)/ {printf "%s ", $0}' /proc/pressure/{cpu,memory,io} \
        >> "$samples_log" 2>/dev/null || true
    printf '\n' >> "$samples_log"

    for path in /sys/class/thermal/thermal_zone*; do
        [[ -r "$path/type" && -r "$path/temp" ]] || continue
        type=$(<"$path/type")
        value=$(<"$path/temp")
        printf '%s\t%s\t%s\t%s\n' "$iso" "${path##*/}" "$type" "$value"
    done >> "$thermal_log"

    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [[ -d "$policy" ]] || continue
        printf '%s\t%s' "$iso" "${policy##*/}" >> "$cpufreq_log"
        for path in scaling_cur_freq scaling_min_freq scaling_max_freq \
            cpuinfo_min_freq cpuinfo_max_freq scaling_driver scaling_governor; do
            if [[ -r "$policy/$path" ]]; then
                value=$(<"$policy/$path")
                printf '\t%s=%s' "$path" "$value" >> "$cpufreq_log"
            fi
        done
        printf '\n' >> "$cpufreq_log"
    done

    for path in /sys/class/thermal/cooling_device*; do
        [[ -r "$path/type" && -r "$path/cur_state" ]] || continue
        printf '%s\t%s\t%s\t%s\t%s\n' "$iso" "${path##*/}" \
            "$(<"$path/type")" "$(<"$path/cur_state")" \
            "$(<"$path/max_state")"
    done >> "$cooling_log"

    for path in /sys/bus/pci/devices/0005:00:00.0/aer_* \
        /sys/bus/pci/devices/0005:01:00.0/aer_*; do
        [[ -r "$path" ]] || continue
        while IFS= read -r value; do
            printf '%s\t%s\t%s\n' "$iso" "$path" "$value"
        done < "$path"
    done >> "$aer_log"
}

boot_id=$(< /proc/sys/kernel/random/boot_id)
start_iso=$(date -Is)
start_epoch=$(date +%s)
initial_temp=$(max_thermal_temp)
initial_aer=$(aer_total)
initial_policies=$(policy_count)
initial_nvme_temp=$(nvme_temp_millic)

{
    printf 'boot_id=%s\nstarted=%s\nuname=%s\n' "$boot_id" "$start_iso" "$(uname -a)"
    printf 'cmdline=%s\n' "$(< /proc/cmdline)"
    printf 'command='; printf '%q ' "$@"; printf '\n'
    printf 'limits=max_seconds:%s sample_seconds:%s preflight_temp:%s stop_temp:%s stop_nvme_temp:%s\n' \
        "$max_seconds" "$sample_seconds" "$preflight_temp" "$stop_temp" "$stop_nvme_temp"
    printf 'initial=max_temp:%s nvme_temp:%s aer_sum:%s policies:%s\n' \
        "$initial_temp" "$initial_nvme_temp" "$initial_aer" "$initial_policies"
} > "$summary_log"

ac_online || { printf '%s\n' 'Preflight failed: AC power is offline.' >&2; exit 75; }
(( initial_temp < preflight_temp )) || {
    printf 'Preflight failed: maximum temperature %s >= %s mC.\n' \
        "$initial_temp" "$preflight_temp" >&2
    exit 75
}
(( initial_aer == 0 )) || {
    printf 'Preflight failed: live PCIe AER counter sum is %s, expected zero.\n' \
        "$initial_aer" >&2
    exit 75
}
(( initial_policies > 0 )) || {
    printf '%s\n' 'Preflight failed: no readable cpufreq policies.' >&2
    exit 75
}
journalctl -k -n 1 --no-pager >/dev/null 2>&1 || {
    printf '%s\n' 'Preflight failed: the kernel journal is not readable.' >&2
    exit 75
}
if (( initial_nvme_temp > 0 && initial_nvme_temp >= stop_nvme_temp )); then
    printf 'Preflight failed: NVMe temperature %s >= %s mC.\n' \
        "$initial_nvme_temp" "$stop_nvme_temp" >&2
    exit 75
fi

printf 'iso\telapsed_s\tmax_temp_mc\tnvme_temp_mc\taer_sum\tload\tpsi\n' > "$samples_log"
journalctl -k -f -n 0 -o short-monotonic >> "$kernel_log" 2>&1 &
journal_pid=$!

setsid -- "$@" > "$build_log" 2>&1 &
workload_pid=$!
printf 'workload_pid=%s\n' "$workload_pid" >> "$summary_log"
sync_logs

while kill -0 "$workload_pid" 2>/dev/null; do
    now_epoch=$(date +%s)
    elapsed=$((now_epoch - start_epoch))
    iso=$(date -Is)
    max_temp=$(max_thermal_temp)
    current_nvme_temp=$(nvme_temp_millic)
    current_aer=$(aer_total)
    current_policies=$(policy_count)
    record_snapshot "$iso" "$elapsed" "$max_temp" "$current_nvme_temp" "$current_aer"

    if (( max_temp >= stop_temp )); then
        stop_reason="temperature ${max_temp}mC reached ${stop_temp}mC"
    elif (( current_nvme_temp > 0 && current_nvme_temp >= stop_nvme_temp )); then
        stop_reason="NVMe temperature ${current_nvme_temp}mC reached ${stop_nvme_temp}mC"
    elif (( current_aer > initial_aer )); then
        stop_reason="PCIe AER counter changed from ${initial_aer} to ${current_aer}"
    elif (( current_policies != initial_policies )); then
        stop_reason="cpufreq policy count changed from ${initial_policies} to ${current_policies}"
    elif ! ac_online; then
        stop_reason='AC power went offline'
    elif ! kill -0 "$journal_pid" 2>/dev/null; then
        stop_reason='kernel journal follower exited unexpectedly'
    elif (( elapsed >= max_seconds )); then
        stop_reason="timeout after ${elapsed}s"
    elif rg -q -i 'PCIe Bus Error|AER:.*(error|fatal)|Data Link Layer|BadTLP|RxErr|critical temperature|Temperature too high|HARDWARE PROTECTION|soft lockup|hard LOCKUP|RCU.*stall|SCMI.*(fault|timed out|timeout)' "$kernel_log"; then
        stop_reason='new kernel PCIe, thermal, lockup, RCU, or SCMI-timeout message'
    fi

    if [[ -n "$stop_reason" ]]; then
        printf '%s\t%s\n' "$iso" "$stop_reason" > "$stop_file"
        printf 'stop=%s\n' "$stop_reason" >> "$summary_log"
        sync_logs
        stop_workload
        break
    fi
    sync_logs
    sleep "$sample_seconds"
done

set +e
wait "$workload_pid"
workload_status=$?
set -e
printf 'workload_status=%s\nfinished=%s\n' "$workload_status" "$(date -Is)" \
    >> "$summary_log"
sync_logs

if [[ -n "$stop_reason" ]]; then
    exit 75
fi
exit "$workload_status"
