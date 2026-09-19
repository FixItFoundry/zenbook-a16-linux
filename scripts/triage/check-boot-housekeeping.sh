#!/usr/bin/env bash
# Read-only post-login gate. Does not start playback, restart services or recover hardware.
set -u
expected='7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+'
failures=0
check() {
    local label=$1
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$label"
    else
        printf 'FAIL: %s\n' "$label"
        failures=$((failures + 1))
    fi
}

printf 'Boot: %s\nKernel: %s\n' "$(cat /proc/sys/kernel/random/boot_id)" "$(uname -r)"
findmnt -no SOURCE,OPTIONS /
check 'RC3 baseline release' test "$(uname -r)" = "$expected"
systemd-analyze time
systemd-analyze critical-chain graphical.target
check 'system manager running' systemctl is-system-running --quiet
mixer_ran() {
    local state
    state=$(systemctl show wsa-mix-boost.service -p Result -p ActiveState \
        -p SubState -p ExecMainStatus -p ExecMainStartTimestampMonotonic) || return 1
    grep -qx 'Result=success' <<< "$state" &&
        grep -qx 'ActiveState=active' <<< "$state" &&
        grep -qx 'SubState=exited' <<< "$state" &&
        grep -qx 'ExecMainStatus=0' <<< "$state" &&
        grep -Eq '^ExecMainStartTimestampMonotonic=[1-9][0-9]*$' <<< "$state"
}
check 'mixer ran successfully this boot' mixer_ran
systemctl show wsa-mix-boost.service abrtd.service NetworkManager-wait-online.service \
    -p Id -p Result -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic \
    -p InactiveExitTimestampMonotonic -p ActiveEnterTimestampMonotonic

slave_count=0
for device in /sys/bus/soundwire/devices/sdw:*; do
    [ -f "$device/status" ] || continue
    slave_count=$((slave_count + 1))
    check "$device attached" test "$(cat "$device/status")" = Attached
done
check 'four SoundWire slaves present' test "$slave_count" -eq 4

# This must run as the logged-in user, not through sudo.
check 'user manager running without failed units' systemctl --user is-system-running --quiet
check 'managed graphical session' systemctl --user is-active --quiet graphical-session.target
check 'Hyprland compositor managed by UWSM' systemctl --user is-active --quiet wayland-wm@hyprland.desktop.service
check 'WirePlumber active' systemctl --user is-active --quiet wireplumber.service
check 'desktop portal active' systemctl --user is-active --quiet xdg-desktop-portal.service
check 'Hyprland portal active' systemctl --user is-active --quiet xdg-desktop-portal-hyprland.service
systemctl --user show xdg-desktop-portal.service xdg-desktop-portal-hyprland.service \
    -p Id -p ActiveState -p SubState
cards=$(pactl -f json list cards)
check 'local card has active HiFi profile' jq -e \
    'any(.[]; .name == "alsa_card.platform-sound" and .active_profile == "HiFi")' <<< "$cards"
sinks=$(pactl -f json list sinks)
check 'four-channel local speaker sink exists' jq -e \
    'any(.[]; .name == "alsa_output.platform-sound.HiFi__Speaker__sink" and (.channel_map | split(",") | length) == 4)' <<< "$sinks"
wpctl status

if ! kernel_log=$(journalctl -b -k --no-pager -o cat 2>&1); then
    printf 'FAIL: kernel journal could not be inspected\n%s\n' "$kernel_log"
    failures=$((failures + 1))
elif [ -z "$kernel_log" ] || [ "$kernel_log" = '-- No entries --' ]; then
    printf 'FAIL: kernel journal is empty\n'
    failures=$((failures + 1))
elif errors=$(printf '%s\n' "$kernel_log" | grep -Ei 'SWR bus clash|write overflow|Parity error detected|Failed to resume device|rcu.*stall|NOHZ.*pending'); then
    printf 'FAIL: kernel errors since boot (even if recovered)\n%s\n' "$errors"
    failures=$((failures + 1))
else
    printf 'PASS: no matching kernel audio/CPU errors since boot\n'
fi
printf 'Automated failures: %d\nPhysical four-channel output and cold-boot/idle durability still require validation.\n' "$failures"
test "$failures" -eq 0
