#!/bin/bash
# Verdict script for the arm,no-completion-irq test. Run right after booting
# the "SCMI poll test (cpufreq)" GRUB entry.
echo "=== booted kernel / DTB identity ==="
uname -r
tr -d "\0" < /proc/device-tree/model; echo
echo -n "arm,no-completion-irq present in booted DT: "
find -L /sys/firmware/devicetree/base -name "arm,no-completion-irq" 2>/dev/null | grep -q . && echo "YES (test DTB)" || echo "NO  (you booted the wrong entry - STOP)"
echo
echo "=== the verdict ==="
if ls /sys/devices/system/cpu/cpufreq/policy* >/dev/null 2>&1; then
  echo "*** PASS: cpufreq policies exist ***"
  ls -d /sys/devices/system/cpu/cpufreq/policy*
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo "--- $p"
    echo "  related_cpus:   $(cat $p/related_cpus 2>/dev/null)"
    echo "  cur/min/max:    $(cat $p/scaling_cur_freq 2>/dev/null) / $(cat $p/cpuinfo_min_freq 2>/dev/null) / $(cat $p/cpuinfo_max_freq 2>/dev/null)"
    echo "  governor:       $(cat $p/scaling_governor 2>/dev/null)"
    echo "  available:      $(cat $p/scaling_available_frequencies 2>/dev/null)"
  done
else
  echo "*** FAIL: /sys/devices/system/cpu/cpufreq/ still has no policies ***"
fi
echo
echo "=== scmi / cpufreq dmesg ==="
sudo dmesg | grep -iE "scmi|cpufreq|cpucp" | head -40
echo
echo "=== doorbell IRQ count (should NOT need to rise for perf now) ==="
grep -iE "cpucp|mbox" /proc/interrupts
echo
echo "=== cooling devices (cpufreq-cooling should appear on PASS) ==="
for c in /sys/class/thermal/cooling_device*; do echo "  $(cat $c/type 2>/dev/null)"; done | sort | uniq -c
