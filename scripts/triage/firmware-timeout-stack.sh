#!/usr/bin/env bash
# Capture CPU stacks once per boot at the first late ath12k firmware-stat timeout.
set -uo pipefail

boot_id=$(cat /proc/sys/kernel/random/boot_id)
capture_dir=/var/log/zenbook-lockup-triage/$boot_id
mkdir -p "$capture_dir"
marker="$capture_dir/firmware-timeout-stack-triggered.txt"
[[ -e "$marker" ]] && exit 0

journalctl -k -b -f -n 0 -o cat --no-pager | while IFS= read -r line; do
  if [[ "$line" == *'time out while waiting for get fw stats'* ]]; then
    printf 'time=%s\nmessage=%s\n' "$(date -Is)" "$line" > "$marker"
    sync -d "$marker"
    printf l > /proc/sysrq-trigger
    timeout 10 journalctl --sync || true
    exit 0
  fi
done
