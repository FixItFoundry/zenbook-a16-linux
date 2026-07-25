#!/bin/bash
# edp-train-probe.sh — one script for every eDP link-training run.
#
# Works on ANY boot (test62, test63, whatever). It reports which DTB is live rather
# than assuming, sets drm.debug itself at runtime, probes the PHY return values that
# msm discards, binds msm, and summarises.
#
# Replaces test62b-phyprobe.sh + test63-run.sh.
#
# WHY drm.debug is set here and not on the cmdline: /sys/module/drm/parameters/debug is
# runtime-writable (root, 0600). No GRUB entry or DTB rebuild is needed just to get the
# DP debug trace — only the link RATE requires a DTB (link-frequencies is read from DT
# at probe, dp_link.c:1215, and has no runtime override).
#
# Usage: sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh [tag]
#   tag defaults to a timestamp; logs land in logs/edp-<tag>-*.log

TAG="${1:-$(date +%H%M)}"
L=/home/jcasco/Projects/zenbook-a16-linux/logs
T=/sys/kernel/debug/tracing
EP=/proc/device-tree/soc@0/display-subsystem@ae00000/displayport-controller@af6c000/ports/port@1/endpoint
mkdir -p $L

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
lsmod | grep -q "^msm " && { echo "msm already loaded — reboot first, this must run pre-bind"; exit 1; }

echo "### which DTB is live?"
# hexdump prints 32-bit words host-endian, so DTS 0x41dd7600 (HBR2) reads back as 0076dd41.
LF=$(hexdump -e '8/4 "%08x " "\n"' $EP/link-frequencies | tr -s ' ')
case "$LF" in
  *0076dd41*) RATE="HBR2 (5.4G) - full rate, test62-style";;
  *00bbeea0*) RATE="HBR (2.7G) capped - test63-style";;
  *)          RATE="unknown: $LF";;
esac
echo "    max link rate: $RATE"

echo "### enabling drm.debug = 0x100 (DRM_UT_DP)"
echo 0x100 > /sys/module/drm/parameters/debug
echo "    now: $(cat /sys/module/drm/parameters/debug)  (256 = 0x100)"

echo "### stopping compositor (plasmalogin, aliased display-manager)"
systemctl stop display-manager 2>/dev/null

echo "### installing probes"
# NOTE: events/kprobes/ does not exist until at least one probe is created,
# so clear/disable AFTER creating, never before.
#
# drm_dp_* live in drm_display_helper, which is NOT loaded yet at this point --
# msm pulls it in later. A bare symbol name is unresolvable and the write fails
# with EINVAL. The MOD:SYM form registers a deferred probe that arms when the
# module loads, which is what we need here.
#
# But a deferred probe CANNOT use $arg1: the kernel can't verify the probe sits at
# function entry until the module is loaded, so it rejects $arg* with
#   "$arg* can be used only on function entry or exit"   (see $T/error_log)
# $retval is exempt, which is why the r: probes worked and the p: ones did not.
# Use the raw arm64 AAPCS registers instead -- no entry check, and at offset 0
# x0/x1 ARE arg1/arg2. This is arch-specific; on x86_64 it would be %di/%si.
echo > $T/kprobe_events 2>/dev/null
add() {
  echo "$1" >> $T/kprobe_events 2>/dev/null && return
  echo "    !! probe FAILED: $1"
  # the kernel records WHY here; without this you only see a bare EINVAL
  tail -3 $T/error_log 2>/dev/null | sed 's/^/       /'
}

add 'r:phypo qcom_edp_phy_power_on    $retval'
add 'r:phyv8 qcom_edp_phy_power_on_v8 $retval'
# phyv8 = CMN_STATUS PLL-lock (BIT7).  phyrsm = resetsm C_READY (BIT0).  phypo = whole
# power_on incl the final DP_PHY_STATUS PHY_READY (BIT1) poll at phy-qcom-edp.c:1250.
# If phyv8=0 & phyrsm=0 but phypo=-110, the hang is the PHY_READY poll (lane/TX side),
# not the PLL.  If phyrsm=-110, C_READY never asserts (PLL-table side).
add 'r:phyrsm qcom_edp_phy_com_resetsm_cntrl_v8 $retval'
# link_status[6] = DPCD 0x202..0x207. x0 = const u8 *link_status, x1 = lane_count.
add 'p:eqok drm_display_helper:drm_dp_channel_eq_ok s202=+0(%x0):u8 s203=+1(%x0):u8 s204=+2(%x0):u8 s205=+3(%x0):u8 s206=+4(%x0):u8 s207=+5(%x0):u8 lanes=%x1:u32'
add 'r:eqokr drm_display_helper:drm_dp_channel_eq_ok $retval'
add 'p:crok drm_display_helper:drm_dp_clock_recovery_ok s202=+0(%x0):u8 s203=+1(%x0):u8 s204=+2(%x0):u8 lanes=%x1:u32'
# Panel power sequencing. The question these answer: is the panel ever prepared/enabled
# BEFORE msm runs link training at hpd_high, or does msm train against a panel that DRM
# has not brought up yet? The panel driver is silent in dmesg, so only a probe shows it.
# MOD:SYM form works whether or not panel_samsung_atna33xc20 is already loaded.
add 'p:panelprep panel_samsung_atna33xc20:atana33xc20_prepare'
add 'r:panelprepr panel_samsung_atna33xc20:atana33xc20_prepare $retval'
add 'p:panelen panel_samsung_atna33xc20:atana33xc20_enable'
add 'p:panelres panel_samsung_atna33xc20:atana33xc20_resume'

echo 1 > $T/events/kprobes/enable
echo 1 > $T/tracing_on
: > $T/trace

echo "### unbuffered dmesg capture"
stdbuf -o0 dmesg -w > $L/edp-$TAG-bind.log 2>&1 &
DW=$!
sleep 1

echo "### binding msm"
modprobe msm; echo "    modprobe rc=$? (139 is benign)"
# srcversion trap: prove the RUNNING phy_qcom_edp is the on-disk build, not a stale
# stock module from initramfs. run != disk means the experiment never actually ran.
echo "    phy_qcom_edp srcversion: running=$(cat /sys/module/phy_qcom_edp/srcversion 2>/dev/null) disk=$(modinfo -F srcversion phy_qcom_edp 2>/dev/null)"
# msm is blacklisted at boot and loaded here from /lib/modules, so unlike phy_qcom_edp it
# never comes from the initramfs -- but check anyway, a stale msm silently wastes the run.
echo "    msm          srcversion: running=$(cat /sys/module/msm/srcversion 2>/dev/null) disk=$(modinfo -F srcversion msm 2>/dev/null)"
sleep 12

cp $T/trace $L/edp-$TAG-phy.log
echo 0 > $T/events/kprobes/enable   # must disable BEFORE clearing, else EBUSY
echo 0 > $T/tracing_on
echo > $T/kprobe_events
kill $DW 2>/dev/null; sleep 1

B=$L/edp-$TAG-bind.log
{
  echo "===== RUN: $TAG   rate: $RATE ====="
  echo
  echo "===== VERDICT ====="
  # #1 = clock recovery, #2 = channel equalization. #2 only runs if #1 passed.
  if   grep -q "link training #1 on phy 0 failed" $B; then
    echo "  CLOCK RECOVERY (#1) FAILED - link never got off the ground."
    echo "  Check phypo below: -110 there means PHY_READY never asserted and"
    echo "  clk_set_rate was skipped (phy-qcom-edp.c:1202), which explains #1."
  elif grep -q "link training #2 on phy 0 failed" $B; then
    echo "  CR (#1) passed, EQUALIZATION (#2) FAILED."
    echo "  NB: drive levels are NOT the suspect -- proven inert (writes land, tables"
    echo "  match vendor firmware, every value tried gives a byte-identical ladder)."
  elif grep -q "link training #2 on phy 0 successful" $B; then
    echo "  *** LINK TRAINING FULLY SUCCEEDED ***"
  else
    echo "  (no link_train result found - check $B)"
  fi
  echo
  echo "===== phy returns  (0x0 = ok, 0xffffff92 = -110) ====="
  echo "  phyv8 = CMN_STATUS PLL-lock BIT7 | phyrsm = resetsm C_READY BIT0 | phypo = whole power_on incl PHY_READY BIT1"
  grep -E "phypo|phyv8|phyrsm" $L/edp-$TAG-phy.log | head -12
  echo
  echo "===== sink caps ====="
  grep -iE "max_lanes|max_link_rate|SUPPORTED_LINK_RATES|link_rate=|link_rate_set|lane_count" $B | head -12
  echo
  echo "===== RATE SELECTION (rate-set vs legacy LINK_BW_SET) ====="
  echo "  NB: the 'rate:' in the RUN header above is the dtsi link-frequencies CAP,"
  echo "  not the negotiated rate. The negotiated rate is the rate= in 'XXX setvolt'."
  echo "  BASE dpcd 0x001 = 0x00, but the EXTENDED block (0x2200, taken because"
  echo "  0x00e bit7 is set) says 0x14 -- that is what dpcd[] holds."
  echo "  rateset3 proved the rate-set path works (0x100 <- 00, 0x115 <- 02) and that"
  echo "  EQ still fails at 5.4G, so rate MISMATCH is not the failure mode."
  echo "  Since hbr3 we take the firmware's own selection instead: UEFI leaves"
  echo "  LINK_BW_SET = 0x14, and per eDP 1.4b LINK_RATE_SET only applies when"
  echo "  LINK_BW_SET is 00h -- so the known-good link is HBR3, not the rate table."
  echo "  WANT: use_rate_set=0, link_rate=810000, 0x00100 <- 14, no 0x00115 write,"
  echo "        and 'XXX setvolt ... rate=8100'."
  grep -iE "use_rate_set|link_rate_set|stale link_bw_set|using LINK_RATE_SET|0x00115 AUX|0x00100 AUX" $B | head -12
  echo
  echo "===== PANEL SEQUENCING vs TRAINING (does prepare happen first?) ====="
  grep -E " panelprep:| panelprepr:| panelen:| panelres:" $L/edp-$TAG-phy.log | head -10 \
    || echo "  (no panel probes fired -- the panel was never prepared/enabled during this run)"
  echo
  echo "===== LINK STATUS decoded — WHY eq fails ====="
  echo "  per lane: CR=clock recovery  EQ=channel eq  SYM=symbol locked (all 3 needed)"
  echo "  a fully-good status byte is 0x77 (both lanes); ALIGN must be 1"
  grep -E " eqok:| crok:" $L/edp-$TAG-phy.log | head -24 | awk '
  {
    which = ($0 ~ / crok:/) ? "CR-check" : "EQ-check"
    s202=""; s203=""; s204=""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^s202=/) { sub("s202=","",$i); s202=strtonum($i) }
      if ($i ~ /^s203=/) { sub("s203=","",$i); s203=strtonum($i) }
      if ($i ~ /^s204=/) { sub("s204=","",$i); s204=strtonum($i) }
    }
    printf "  %-9s 0x202=0x%02x 0x203=0x%02x ALIGN=%d |", which, s202, s203, s204%2
    split("", L)
    L[0]=s202%16; L[1]=int(s202/16)%16; L[2]=s203%16; L[3]=int(s203/16)%16
    for (n=0; n<4; n++) {
      printf " L%d:%s%s%s", n, (L[n]%2?"CR ":"cr "), (int(L[n]/2)%2?"EQ ":"eq "), (int(L[n]/4)%2?"SYM":"sym")
    }
    print ""
  }'
  echo "  (UPPERCASE = bit set/good, lowercase = bit clear/failing)"
  echo
  echo "===== requested drive levels (does the sink ever stop asking?) ====="
  grep -iE "adjust_levels|update_phy_vx_px|rate_down_shift|XXX setvolt" $B | head -40
  echo
  echo "===== errors ====="
  grep -iE "\*ERROR\*" $B | head -20
  echo
  echo "===== connector ====="
  for c in /sys/class/drm/card*-eDP*/; do
    [ -e "$c/status" ] && echo "  $(basename $c): $(cat $c/status) enabled=$(cat $c/enabled) modes=$(tr '\n' ' ' < $c/modes)"
  done
} > $L/edp-$TAG-RESULT.log 2>&1

cat $L/edp-$TAG-RESULT.log
echo
echo "Logs: $L/edp-$TAG-RESULT.log  edp-$TAG-bind.log  edp-$TAG-phy.log"
echo "Restore desktop: systemctl start display-manager"
