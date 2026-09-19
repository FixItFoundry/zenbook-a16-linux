#!/usr/bin/env bash
# Persistent, low-rate evidence for the intermittent kernel lockup.
set -u
source "$(dirname -- "${BASH_SOURCE[0]}")/capture-storage.sh"

umask 077
boot_id=$(cat /proc/sys/kernel/random/boot_id)
capture_dir=/var/log/zenbook-lockup-triage/$boot_id
mkdir -p "$capture_dir" || exit 75
segment_bytes=$((8 * 1024 * 1024))
total_limit_kib=$((256 * 1024))

if [[ ! -e "$capture_dir/build.txt" ]]; then
  {
    printf 'boot_id=%s\n' "$boot_id"
    printf 'started=%s\n' "$(date -Is)"
    uname -a
    printf '\ncmdline:\n'
    cat /proc/cmdline
    printf '\nboot artifacts:\n'
    kernel_release=$(uname -r)
    for artifact in "/boot/vmlinuz-$kernel_release" "/boot/initrd.img-$kernel_release"; do
      if [[ -f "$artifact" ]]; then sha256sum "$artifact"; fi
    done
    printf '\ninstalled Wi-Fi modules:\n'
    for module in ath12k ath12k_wifi7 mhi; do
      module_path=$(modinfo -n "$module" 2>/dev/null || true)
      if [[ -n "$module_path" && -f "$module_path" ]]; then sha256sum "$module_path"; fi
    done
    printf '\nlive FDT:\n'
    if [[ -r /sys/firmware/fdt ]]; then sha256sum /sys/firmware/fdt; fi
    printf '\nPCI Wi-Fi driver:\n'
    readlink -f /sys/bus/pci/devices/0004:01:00.0/driver 2>/dev/null || true
  } > "$capture_dir/build.txt"
  sync -d "$capture_dir/build.txt"
fi

snapshot="$capture_dir/counters.log"
if [[ ! -e "$capture_dir/interrupts-initial.txt" ]]; then
  cat /proc/interrupts > "$capture_dir/interrupts-initial.txt"
  sync -d "$capture_dir/interrupts-initial.txt"
fi
while :; do
  if ! capture_budget_available /var/log/zenbook-lockup-triage "$total_limit_kib"; then
    echo 'Capture storage budget reached or unreadable; archive old boots before restarting.' >&2
    exit 75
  fi
  rotate_counters "$snapshot" "$segment_bytes" || exit 75
  {
    printf '\n=== %s boot=%s uptime=' "$(date -Is)" "$boot_id"
    cat /proc/uptime
    printf '%s\n' '[interrupts: Wi-Fi PCIe, SoundWire, Qualcomm IPC, timer, IPIs]'
    awk 'NR == 1 || /0004:01:00\.0|soundwire|ipcc|glink|arch_timer|^IPI/' /proc/interrupts
    printf '%s\n' '[softirqs]'
    cat /proc/softirqs
    printf '%s\n' '[stat]'
    # Per-IRQ totals duplicate the interrupt snapshot above; retain aggregate.
    awk '$1 == "intr" {print $1, $2; next} {print}' /proc/stat
    printf '%s\n' '[scmi-cpufreq]'
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
      [[ -d "$policy" ]] || continue
      printf '%s' "${policy##*/}"
      for field in scaling_driver scaling_governor scaling_cur_freq \
        scaling_min_freq scaling_max_freq affected_cpus related_cpus; do
        if [[ -r "$policy/$field" ]]; then
          printf ' %s=' "$field"
          value=$(< "$policy/$field")
          printf '%s ' "$value"
        fi
      done
      printf '\n'
    done
    printf 'online_cpus='
    cat /sys/devices/system/cpu/online
    printf '%s\n' '[net-dev]'
    cat /proc/net/dev
    printf '%s\n' '[wifi-link]'
    # This queries firmware statistics; it is not a passive Wi-Fi observation.
    timeout 5 iw dev wlP4p1s0 link 2>&1 || true
    printf '%s\n' '[wifi-pci-power]'
    for field in control runtime_status; do
      path="/sys/bus/pci/devices/0004:01:00.0/power/$field"
      if [[ -r "$path" ]]; then printf '%s=' "$field"; cat "$path"; fi
    done
    printf '%s\n' '[soundwire-slaves]'
    for path in /sys/bus/soundwire/devices/sdw:*/status; do
      if [[ -r "$path" ]]; then
        device_dir=${path%/status}
        printf '%s number=%s status=%s\n' "$device_dir" \
          "$(cat "$device_dir/device_number" 2>/dev/null || printf unknown)" \
          "$(cat "$path")"
      fi
    done
    printf '%s\n' '[adsp]'
    for path in /sys/class/remoteproc/remoteproc*/name; do
      if [[ -r "$path" && $(cat "$path") == adsp ]]; then
        printf '%s=' "${path%/name}"
        cat "${path%/name}/state"
      fi
    done
  } >> "$snapshot" || exit 75
  sync -d "$snapshot" || exit 75
  sleep 30
done
