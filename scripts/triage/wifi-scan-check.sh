#!/usr/bin/env bash
# One bounded scan after the failed association; restore the prior radio state.
set -uo pipefail
boot_id=$(cat /proc/sys/kernel/random/boot_id)
output="/home/jcasco/Projects/zenbook-a16-linux/internal-docs/wifi-live-trial-$boot_id/scan-retry.log"
mkdir -p "${output%/*}"
cleanup() { timeout 20 nmcli radio wifi off >>"$output" 2>&1 || true; }
trap cleanup EXIT INT TERM
printf 'start=%s route=%s\n' "$(date -Is)" "$(ip route get 1.1.1.1 | head -1)" > "$output"
timeout 30 nmcli radio wifi on >>"$output" 2>&1 || exit 1
sleep 4
timeout 30 nmcli --wait 25 device wifi rescan ifname wlP4p1s0 >>"$output" 2>&1
printf 'rescan_exit=%s time=%s\n' "$?" "$(date -Is)" >> "$output"
sleep 12
timeout 15 nmcli -f IN-USE,SSID,CHAN,FREQ,SIGNAL device wifi list ifname wlP4p1s0 --rescan no >>"$output" 2>&1
printf 'list_exit=%s time=%s\n' "$?" "$(date -Is)" >> "$output"
iw dev wlP4p1s0 link >>"$output" 2>&1
