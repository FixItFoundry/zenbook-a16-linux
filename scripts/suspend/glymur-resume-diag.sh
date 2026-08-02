#!/usr/bin/env bash
# glymur-resume-diag.sh — post-resume forensics for the Zenbook A16 (glymur).
#
# Run AFTER a resume that left devices hung. Read-only: it collects state, it
# does not poke anything. Writes one timestamped file under ~ (never /tmp —
# /tmp is wiped on reboot on this box).
#
#   bash glymur-resume-diag.sh            # collect
#   bash glymur-resume-diag.sh -q         # collect, print only the verdict
#
# The three questions it answers, in order:
#   1. Did it RESUME or did it RESET?          <- uptime -s is the only truth
#   2. What did not come back?                 <- per-subsystem live state
#   3. What does the kernel say happened?      <- the resume window in the log
#
# ⚠️ Judge by uptime -s, never by reachability. Wi-Fi takes minutes to
#    re-associate and the USB-A NIC sometimes never returns.

set -uo pipefail
OUT=~/glymur-resume-diag-$(date +%Y%m%d-%H%M%S).txt
Q=${1:-}

s() { printf '\n\n===== %s =====\n' "$*" >>"$OUT"; }
r() { printf '\n--- $ %s\n' "$*" >>"$OUT"; eval "$*" >>"$OUT" 2>&1; }

: >"$OUT"
{
  echo "glymur resume diagnostic"
  echo "collected : $(date -Is)"
  echo "host      : $(hostname)"
  echo "kernel    : $(uname -r)"
} >>"$OUT"

# ---------------------------------------------------------------- 1. reset?
s "1. RESUME OR RESET (the only question that matters first)"
r "uptime -s"
r "uptime"
r "cat /proc/uptime"
r "cat /sys/power/suspend_stats/success"
r "cat /sys/power/suspend_stats/fail"
r "cat /sys/power/suspend_stats/last_failed_dev"
r "cat /sys/power/suspend_stats/last_failed_step"
r "cat /sys/power/mem_sleep"
r "cat /proc/cmdline"
r "last -x -n 15 reboot shutdown"

# ------------------------------------------------------------- 2. what died
s "2a. NETWORK — interfaces and links"
r "ip -br addr show"
r "ip -br link show"
r "ip route"
r "ip -6 route | head -20"

s "2b. WI-FI / ath12k (PCIe — the glymur_pci_skip=5 suspect)"
r "lspci -nn"
r "lspci -vv -s \$(lspci | awk '/Network|Wireless/{print \$1; exit}') 2>/dev/null | head -40"
r "ls -la /sys/bus/pci/devices/"
r "for d in /sys/bus/pci/devices/*/; do printf '%s power/runtime_status=%s current_state=%s\n' \"\$d\" \"\$(cat \$d/power/runtime_status 2>/dev/null)\" \"\$(cat \$d/power/current_state 2>/dev/null)\"; done"
r "iw dev 2>/dev/null"
r "nmcli -t device status 2>/dev/null"
r "rfkill list"
r "lsmod | grep -E 'ath12k|mac80211|cfg80211'"

s "2c. USB — controller vs device (replug not working => controller)"
r "lsusb"
r "lsusb -t"
r "ls -la /sys/bus/usb/devices/"
r "for d in /sys/bus/usb/devices/usb*/; do printf '%s runtime_status=%s\n' \"\$d\" \"\$(cat \$d/power/runtime_status 2>/dev/null)\"; done"
r "ls /sys/bus/platform/drivers/dwc3/ 2>/dev/null"
r "ls /sys/bus/platform/drivers/xhci-hcd/ 2>/dev/null"
r "dmesg | grep -iE 'xhci|dwc3|usb .*(disconnect|new|reset)' | tail -40"

s "2d. TYPE-C / UCSI / battery — all on the one glink edge, they fail together"
r "ls /sys/class/typec/"
r "cat /sys/class/power_supply/qcom-battmgr-bat/status"
r "cat /sys/class/power_supply/qcom-battmgr-bat/energy_now"
r "cat /sys/class/power_supply/qcom-battmgr-usb/online"
r "upower -d 2>/dev/null | head -30"

s "2e. REMOTEPROC — ADSP/SOCCP; 'audio broke' is usually this"
r "for d in /sys/class/remoteproc/*/; do printf '%s %s state=%s\n' \"\$d\" \"\$(cat \$d/name 2>/dev/null)\" \"\$(cat \$d/state 2>/dev/null)\"; done"

s "2f. DISPLAY / GPU"
r "for c in /sys/class/drm/card*/status; do printf '%s = %s\n' \"\$c\" \"\$(cat \$c 2>/dev/null)\"; done"
r "ls /sys/class/backlight/"

s "2g. CPUFREQ / THERMAL (did the SCMI link survive?)"
r "ls /sys/devices/system/cpu/cpufreq/"
r "for p in /sys/devices/system/cpu/cpufreq/policy*/; do printf '%s driver=%s gov=%s cur=%s\n' \"\$p\" \"\$(cat \$p/scaling_driver 2>/dev/null)\" \"\$(cat \$p/scaling_governor 2>/dev/null)\" \"\$(cat \$p/scaling_cur_freq 2>/dev/null)\"; done"
r "n=0; for z in /sys/class/thermal/thermal_zone*/cdev*; do [ -L \"\$z\" ] || continue; case \"\$(cat \$z/type 2>/dev/null)\" in cpufreq-*) n=\$((n+1));; esac; done; echo \"zones bound to a cpufreq cooling device: \$n\""

s "2h. FAILED UNITS"
r "systemctl --failed --no-pager"
r "systemctl status systemd-logind --no-pager | head -20"

# ------------------------------------------------------- 3. what the kernel says
s "3a. THE RESUME WINDOW — this boot's suspend/resume lines"
r "journalctl -b -k --no-pager | grep -inE 'PM: |suspend|resume|s2idle|Freezing|Restarting tasks|thaw' | tail -80"

s "3b. ERRORS SINCE THE LAST RESUME"
r "journalctl -b -k --no-pager -p err --since '-2 hours' | tail -60"
r "dmesg -l err,warn | tail -60"

s "3c. TIMEOUTS AND -110s (the project's signature failure)"
r "journalctl -b -k --no-pager | grep -iE 'timed out|timeout|-110|ETIMEDOUT|failed to resume|not responding' | tail -50"

s "3d. PREVIOUS BOOTS — did an earlier cycle reset the box?"
r "journalctl --list-boots --no-pager | tail -12"

s "3e. LOGIND / IDLE — what actually triggered the suspend"
r "journalctl -b -u systemd-logind --no-pager | tail -30"
r "systemctl status hypridle --no-pager 2>/dev/null | head -12"
r "loginctl show-session \$(loginctl | awk 'NR==2{print \$1}') 2>/dev/null | grep -iE 'idle|lock'"

s "3f. PSTORE (expected empty — ramoops cannot capture on this hardware)"
r "ls -la /sys/fs/pstore/ 2>/dev/null"

# ------------------------------------------------------------------- verdict
BOOTED=$(uptime -s 2>/dev/null)
SUCC=$(cat /sys/power/suspend_stats/success 2>/dev/null)
FAILN=$(cat /sys/power/suspend_stats/fail 2>/dev/null)
NICS=$(ip -br link show 2>/dev/null | grep -cE ' UP ')

{
  echo
  echo "=============================================================="
  echo "VERDICT"
  echo "=============================================================="
  echo "  boot time (uptime -s) : $BOOTED"
  echo "     ^ compare with the boot time from BEFORE the suspend."
  echo "       UNCHANGED = it resumed.  CHANGED = it RESET, different bug."
  echo "  suspend success count : $SUCC"
  echo "  suspend fail count    : $FAILN"
  echo "  interfaces UP         : $NICS"
  echo
  echo "  Replug not re-enumerating the NIC points at the xHCI HOST"
  echo "  CONTROLLER not resuming, not the device. Check section 2c."
  echo "=============================================================="
} | tee -a "$OUT"

if [ "$Q" != "-q" ]; then
  echo
  echo "Full report: $OUT  ($(wc -l <"$OUT") lines)"
  echo "Retrieve with:  scp -o HostKeyAlias=loazen jcasco@<addr>:$OUT ."
fi
