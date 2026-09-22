#!/usr/bin/env bash
# Bounded one-boot A/B workload trial. Run as the desktop user; collectors run separately.
set -uo pipefail

root=/home/jcasco/Projects/zenbook-a16-linux
trial_ap=${WIFI_TRIAL_AP:-TP-Link_37F7_5G}
baseline_seconds=${WIFI_TRIAL_BASELINE_SECONDS:-240}
wifi_seconds=${WIFI_TRIAL_ON_SECONDS:-1200}
baseline_only=${WIFI_TRIAL_BASELINE_ONLY:-0}
baseline_traffic=${WIFI_TRIAL_BASELINE_TRAFFIC:-0}
boot_id=$(cat /proc/sys/kernel/random/boot_id)
trial_dir="$root/internal-docs/wifi-live-trial-$boot_id"
mkdir -p "$trial_dir"
chmod 700 "$trial_dir"
log="$trial_dir/trial.log"
tone="$trial_dir/quiet-4ch.wav"
started=$(date -Is)

record() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$log"; }

cleaned=0
cleanup() {
  [[ $cleaned == 1 ]] && return
  cleaned=1
  record 'trial cleanup: turning Wi-Fi radio off; Ethernet remains available'
  timeout 20 nmcli radio wifi off >>"$log" 2>&1 || true
}
trap cleanup EXIT
trap 'exit 143' INT TERM

python3 - "$tone" <<'PY'
import math, struct, sys, wave
rate = 48000
with wave.open(sys.argv[1], 'wb') as out:
    out.setnchannels(4)
    out.setsampwidth(2)
    out.setframerate(rate)
    for n in range(rate):
        sample = int(800 * math.sin(2 * math.pi * 440 * n / rate))
        out.writeframesraw(struct.pack('<hhhh', sample, sample, sample, sample))
PY

record "start boot=$boot_id kernel=$(uname -r) target_ap=$trial_ap baseline_seconds=$baseline_seconds wifi_seconds=$wifi_seconds baseline_only=$baseline_only baseline_traffic=$baseline_traffic"
record "wired_route=$(ip route get 1.1.1.1 | head -1)"
record "radio=$(nmcli -g WIFI general status 2>/dev/null || nmcli radio wifi)"
record "sink=$(pactl get-default-sink 2>/dev/null || true)"
record "wifi_module=$(modinfo -F srcversion ath12k_wifi7 2>/dev/null || true)"

if ! ip route get 1.1.1.1 | grep -q 'dev enu1u3'; then
  record 'abort: Ethernet is not the default route'
  exit 1
fi
if [[ $(nmcli radio wifi) != disabled ]]; then
  record 'abort: Wi-Fi was not off at the start'
  exit 1
fi

run_phase() {
  local phase=$1 duration=$2 end loop=0
  end=$((SECONDS + duration))
  record "phase=$phase start duration_seconds=$duration"
  while (( SECONDS < end )); do
    loop=$((loop + 1))
    record "phase=$phase loop=$loop wifi_link=$(iw dev wlP4p1s0 link 2>&1 | tr '\n' ' ')"
    timeout 8 pw-play --target alsa_output.platform-sound.HiFi__Speaker__sink "$tone" >>"$log" 2>&1
    record "phase=$phase audio_exit=$?"
    timeout 18 ffmpeg -nostdin -hide_banner -loglevel error -re \
      -f lavfi -i testsrc2=size=1280x720:rate=30 -t 12 -f null - \
      >>"$log" 2>&1
    record "phase=$phase video_exit=$?"
    if [[ $phase == wifi ]]; then
      timeout 12 curl --silent --show-error --location --interface wlP4p1s0 \
        --max-time 10 --output /dev/null \
        --write-out 'wifi_http_code=%{http_code} wifi_bytes=%{size_download} wifi_seconds=%{time_total}\n' \
        'https://speed.cloudflare.com/__down?bytes=1048576' >>"$log" 2>&1
      record "phase=$phase wifi_http_exit=$?"
    elif [[ $baseline_traffic == 1 ]]; then
      timeout 12 curl --silent --show-error --location --interface enu1u3 \
        --max-time 10 --output /dev/null \
        --write-out 'wired_http_code=%{http_code} wired_bytes=%{size_download} wired_seconds=%{time_total}\n' \
        'https://speed.cloudflare.com/__down?bytes=1048576' >>"$log" 2>&1
      record "phase=$phase wired_http_exit=$?"
    fi
    if sudo -n test -e "/var/log/zenbook-lockup-triage/$boot_id/firmware-timeout-stack-triggered.txt"; then
      record 'STOP: ath12k firmware-stat timeout captured; see collector marker and journal'
      return 2
    fi
    if journalctl -k -b --since "$started" --no-pager -o cat 2>/dev/null |
        grep -Eiq 'rcu: INFO:.*stall|Kernel panic|SWR bus clash detected|time out while waiting for get fw stats'; then
      record 'STOP: RCU/panic/SoundWire-clash signature in this trial; inspect journal'
      return 3
    fi
    sleep 10
  done
  record "phase=$phase completed loops=$loop"
}

run_phase radio_off "$baseline_seconds" || exit $?
if [[ $baseline_only == 1 ]]; then
  record 'radio-off comparison complete without monitored kernel failure signatures'
  exit 0
fi
record "turning on Wi-Fi for the $trial_ap trial"
timeout 30 nmcli radio wifi on >>"$log" 2>&1 || { record 'failed to enable Wi-Fi'; exit 1; }
timeout 60 nmcli --wait 50 connection up id "$trial_ap" ifname wlP4p1s0 >>"$log" 2>&1 || {
  record "failed to associate with $trial_ap"; exit 1;
}
record "associated=$(iw dev wlP4p1s0 link | tr '\n' ' ')"
if [[ $(iw dev wlP4p1s0 link | awk '$1 == "SSID:" {print substr($0, index($0,$2))}') != "$trial_ap" ]]; then
  record "STOP: associated SSID differs from requested $trial_ap"
  exit 1
fi
record "wired_route=$(ip route get 1.1.1.1 | head -1)"
if ! ip route get 1.1.1.1 | grep -q 'dev enu1u3'; then
  record 'STOP: Ethernet lost default route'
  exit 1
fi
run_phase wifi "$wifi_seconds" || exit $?
record 'trial complete without the monitored failure signatures'
