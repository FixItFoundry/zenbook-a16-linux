#!/bin/bash
# test62 — verify the dispcc clocks[] dp3-slot fix, then bind msm.
# Runs standalone: Wi-Fi dies when msm binds, so everything lands on disk.
# Usage: sudo ~/Projects/zenbook-a16-linux/scripts/test62-run.sh

L=/home/jcasco/Projects/zenbook-a16-linux/logs
D=/sys/kernel/debug/clk
mkdir -p $L

echo "### stage 1: pre-bind (msm NOT loaded) — this alone proves or kills the fix"
{
  echo "== uname: $(uname -r)  uptime: $(uptime -p)"
  echo "== dispcc clocks[] (want f7 at words 15-18, i.e. the dp3 slot):"
  hexdump -e '8/4 "%08x " "\n"' /proc/device-tree/soc@0/clock-controller@af00000/clocks
  echo
  echo "== dptx3 in clk_orphan_summary  (PASS = no output here):"
  grep dptx3 $D/clk_orphan_summary || echo "  (none — dptx3 is NOT orphaned)  <<< FIX WORKED"
  echo
  echo "== dptx3 + eDP phy in clk_summary:"
  grep -E "dptx3|faac00" $D/clk_summary
} > $L/test62-prebind.log 2>&1
grep -q "FIX WORKED" $L/test62-prebind.log \
  && echo "  PASS: dptx3 no longer orphaned" \
  || { echo "  FAIL: dptx3 still orphaned — stopping before msm. See $L/test62-prebind.log"; exit 1; }

echo "### stage 2: quiesce the compositor so we get one clean modeset"
# Plasma here is plasmalogin.service, aliased as display-manager.service. NOT sddm.
systemctl stop display-manager 2>/dev/null && echo "  stopped display-manager (plasmalogin)"

echo "### stage 3: unbuffered dmesg capture"
stdbuf -o0 dmesg -w > $L/test62-msm-bind.log 2>&1 &
DW=$!
sleep 1

echo "### stage 4: bind msm  (exits 139 but loads — ignore rc)"
modprobe msm; echo "  modprobe rc=$? (139 is expected/benign)"
sleep 8

echo "### stage 5: results"
{
  echo "== the two reparents (want NO -16 / no Oops):"
  grep -E "failed to reparent|rcg didn't update|Unable to handle kernel NULL" $L/test62-msm-bind.log || echo "  (clean — no reparent failure, no Oops)"
  echo
  echo "== connectors:"
  for c in /sys/class/drm/card*-*/; do
    [ -e "$c/status" ] && echo "  $(basename $c): $(cat $c/status) enabled=$(cat $c/enabled 2>/dev/null)"
  done
  echo
  echo "== modes on eDP-1:"
  cat /sys/class/drm/card1-eDP-1/modes 2>/dev/null || echo "  (no card1-eDP-1)"
  echo
  echo "== backlight:"
  for b in /sys/class/backlight/*/; do
    echo "  $(basename $b): $(cat $b/brightness 2>/dev/null)/$(cat $b/max_brightness 2>/dev/null)"
  done
  echo
  echo "== dptx3 clocks AFTER bind (want nonzero rates):"
  grep -E "dptx3|faac00" $D/clk_summary
  echo
  echo "== link training / dp errors:"
  grep -iE "link train|mainlink|-110|EDID|dpcd" $L/test62-msm-bind.log | tail -20
} > $L/test62-RESULT.log 2>&1

sleep 2; kill $DW 2>/dev/null
echo
echo "=========== DONE. Summary: ==========="
cat $L/test62-RESULT.log
echo "======================================"
echo "Logs: $L/test62-prebind.log  test62-msm-bind.log  test62-RESULT.log"
echo "If the panel is lit, restart the desktop with: systemctl start display-manager"
