#!/bin/bash
# glymur-ec-block.sh — the ASUS EC *block* command layer on the Zenbook A16.
#
# Companion to glymur-ec-read.sh. That script implements RECM (command 0x52 on
# I2C 0x76) and reads fan RPM. This one implements the layer underneath it:
# ECRB/ECWB byte access on I2C 0x5b, and the WEBC/REBC block engine on
# EC-internal device 0xC9 that carries the fan curve commands.
#
# ── STATUS ────────────────────────────────────────────────────────────────────
#
# The byte layer WORKS (verified 2026-07-31: writes to 0xC9 read back unchanged).
# The block engine DOES NOT RESPOND — 0x6F never self-clears, so REBC can never
# start. See docs/fan-ec-interface.md, section "The gate". The missing step is
# believed to be ECCW(0x02, 0x83, 1), which this script can send but does NOT
# send unless you pass `enable`, because that flag may hand fan control away
# from the EC. Read the doc before using it.
#
# ── PROTOCOL, transcribed from the Windows-on-Arm DSDT ────────────────────────
#
#   Field (DV5B, BufferAcc) { Connection(SL5B),          // I2cSerialBusV2(0x005B)
#       Offset(0x10), AccessAs(BufferAcc, AttribBytes(0x02)), FC10, 8,
#                     AccessAs(BufferAcc, AttribBytes(0x01)), FC11, 8 }
#
#   ECRB(dev,reg)      w3@0x5b 0x10 <dev> <reg>   then  w1@0x5b 0x11 / r1@0x5b
#   ECWB(dev,reg,val)  w3@0x5b 0x10 <dev> <reg>   then  w2@0x5b 0x11 <val>
#
# The OperationRegion offset IS the I2C command byte and there is NO SMBus count
# byte — the same trap that cost an hour on command 0x52. C10G is
# {status, len, dev, reg, 0, 0} and only {dev, reg} go on the wire.
#
#   device 0xC9:  0x6F control/status, 0x6E command, 0x40-0x6F data window
#                 0x80 = write pending, 0x20 = read pending, 0x40 = host done
#   device 0xC4:  0x30 doorbell, 0x31/0x32 args   (the ECCW/ECCR mailbox)
#
#   GDFC(sel) = WEBC(0x20,1,{sel}) + REBC(0x21,16)   read default curve
#   GFLB(sel) = WEBC(0x20,1,{sel}) + REBC(0x24,8)    read limits
#   SUFC(sel) = WEBC(0x20,1,{sel}) + WEBC(0x22,16,c) WRITE user curve  [NOT IMPLEMENTED]
#
#   sel = op_class | (group << 2) | index
#     GDFC 0x80 0x81 0x82 | 0x84 0x85 0x86 | 0x88 0x89 0x8A
#     GFLB 0x20           | 0x24           | 0x28
#     SUFC 0x40           | 0x44           | 0x48
#
# ── RULES (from the 2026-07-31 hard reset) ────────────────────────────────────
#
#   1. Two separate i2ctransfer calls. NEVER a 6-byte-write + 7-byte-read
#      repeated start — that form threw GPI transfer failed: -5.
#   2. Never run this under CPU load.
#   3. Watch dmesg for "GPI transfer failed" — that is the early warning.
#
# ⚠️ This EC also owns charging. Every command here except `probe` writes EC
#    registers. Ask before extending it.

set -u
BUS=9
A=0x5b
DEV_BLOCK=0xc9
DEV_MBOX=0xc4
TX=0

die() { echo "glymur-ec-block: $*" >&2; exit 1; }
command -v i2ctransfer >/dev/null || die "i2ctransfer not found (install i2c-tools)"
[ -e "/dev/i2c-$BUS" ] || die "/dev/i2c-$BUS missing"

# ── layer 1: byte access ──────────────────────────────────────────────────────

ecrb() { # dev reg -> decimal value on stdout
	TX=$((TX + 2))
	sudo -n i2ctransfer -y "$BUS" w3@$A 0x10 "$1" "$2" >/dev/null 2>&1 || return 1
	local v
	v=$(sudo -n i2ctransfer -y "$BUS" w1@$A 0x11 r1@$A 2>/dev/null) || return 1
	[ -n "$v" ] || return 1
	echo $((v))
}

ecwb() { # dev reg val
	TX=$((TX + 2))
	sudo -n i2ctransfer -y "$BUS" w3@$A 0x10 "$1" "$2" >/dev/null 2>&1 || return 1
	sudo -n i2ctransfer -y "$BUS" w2@$A 0x11 "$3" >/dev/null 2>&1 || return 1
}

# ── layer 2: the 0xC9 block engine ────────────────────────────────────────────

wait_ctrl_idle() { # -> 0 if 0x6F reached 0, 2 on timeout
	local i=40 x
	while [ $i -gt 0 ]; do
		x=$(ecrb $DEV_BLOCK 0x6f) || return 1
		[ "$x" -eq 0 ] && return 0
		i=$((i - 1))
		sleep 0.005
	done
	return 2
}

webc() { # cmd len byte...
	local cmd=$1 len=$2
	shift 2
	wait_ctrl_idle || return 2
	local i=0
	while [ $i -lt "$len" ]; do
		ecwb $DEV_BLOCK $((0x40 + i)) "$1" || return 1
		shift
		i=$((i + 1))
	done
	ecwb $DEV_BLOCK 0x6f 0x80 || return 1 # BMCR was 0, |= 0x80
	ecwb $DEV_BLOCK 0x6e "$cmd" || return 1
}

rebc() { # cmd len -> prints "0xNN 0xNN ..."
	local cmd=$1 len=$2 i b out=""
	wait_ctrl_idle || return 2
	ecwb $DEV_BLOCK 0x6f 0x20 || return 1
	ecwb $DEV_BLOCK 0x6e "$cmd" || return 1

	i=50
	while [ $i -gt 0 ]; do
		b=$(ecrb $DEV_BLOCK 0x6f) || return 1
		[ $((b & 0x80)) -eq 128 ] && break
		i=$((i - 1))
		sleep 0.005
	done
	if [ $i -eq 0 ]; then
		echo "rebc: data-ready bit never set, 0x6F=0x$(printf %02x "$b")" >&2
		b=$(ecrb $DEV_BLOCK 0x6f) && ecwb $DEV_BLOCK 0x6f $((b | 0x40)) # abort
		return 2
	fi

	i=0
	while [ $i -lt "$len" ]; do
		b=$(ecrb $DEV_BLOCK $((0x40 + i))) || return 1
		out="$out $(printf '0x%02x' "$b")"
		i=$((i + 1))
	done
	b=$(ecrb $DEV_BLOCK 0x6f) && ecwb $DEV_BLOCK 0x6f $((b | 0x40)) # ack
	echo "${out# }"
}

# ── preflight ─────────────────────────────────────────────────────────────────

preflight() {
	local load errs
	load=$(awk '{print $1}' /proc/loadavg)
	errs=$(sudo -n dmesg | grep -cE "GPI transfer failed|DMA txn failed|Error in Transaction")
	echo "preflight: load=$load  prior GPI errors=$errs"
	awk -v l="$load" 'BEGIN{exit !(l > 4.0)}' && die "load too high — rule 2, never poll the EC under CPU load"
	[ "$errs" -eq 0 ] || echo "  ⚠️ the I2C controller has already thrown errors this boot"
}

postflight() {
	local errs
	errs=$(sudo -n dmesg | grep -cE "GPI transfer failed|DMA txn failed|Error in Transaction")
	echo "postflight: $TX I2C transactions, GPI errors now $errs"
	echo "postflight: fan $(/usr/local/bin/glymur-ec-read.sh rpm 2>/dev/null || echo '(read failed)')"
}

usage() {
	cat >&2 <<'EOF'
usage: glymur-ec-block.sh <command>

  probe            READ ONLY. Dump 0xC9 and 0xC4 state, no writes at all.
  limits <sel>     GFLB — select, then read the 8-byte limit block.
                   sel = 0x20 | 0x24 | 0x28
  curve <sel>      GDFC — select, then read a 16-byte default curve.
                   sel = 0x80..0x82 | 0x84..0x86 | 0x88..0x8A
  all              every limit block and every curve (~500 I2C transactions)
  enable           ⚠️ ECCW(0x02,0x83,1). Announces an OS driver to the EC. May
                   hand fan control away from the EC. ASK FIRST. See the doc.
  disable          ECCW(0x02,0x83,0) — the reverse of `enable`.

Nothing here writes a fan curve. SUFC is deliberately not implemented.
EOF
	exit 2
}

case "${1:-}" in
probe)
	echo "-- 0xC9 (block engine) --"
	for r in 0x6e 0x6f; do printf '   0xC9[%s] = 0x%02x\n' "$r" "$(ecrb $DEV_BLOCK $r)"; done
	printf '   data window 0x40..0x47:'
	for r in 0x40 0x41 0x42 0x43 0x44 0x45 0x46 0x47; do printf ' 0x%02x' "$(ecrb $DEV_BLOCK $r)"; done
	echo
	echo "-- 0xC4 (ECCW/ECCR mailbox) --"
	for r in 0x30 0x31 0x32; do printf '   0xC4[%s] = 0x%02x\n' "$r" "$(ecrb $DEV_MBOX $r)"; done
	echo "-- control: 0xC0 does not exist; 0x00 here means 'unknown selector', not 'idle' --"
	printf '   0xC0[0x30] = 0x%02x\n' "$(ecrb 0xc0 0x30)"
	echo "(no writes were made)"
	;;
limits)
	[ $# -ge 2 ] || usage
	preflight
	webc 0x20 1 "$2" || die "select failed (rc=$?)"
	r=$(rebc 0x24 8) || die "read failed (rc=$?) — see 'The gate' in docs/fan-ec-interface.md"
	echo "limits[$2] = $r"
	postflight
	;;
curve)
	[ $# -ge 2 ] || usage
	preflight
	webc 0x20 1 "$2" || die "select failed (rc=$?)"
	r=$(rebc 0x21 16) || die "read failed (rc=$?) — see 'The gate' in docs/fan-ec-interface.md"
	echo "curve[$2] = $r"
	postflight
	;;
all)
	preflight
	for sel in 0x20 0x24 0x28; do
		webc 0x20 1 $sel && r=$(rebc 0x24 8) && echo "limits[$sel] = $r" || echo "limits[$sel] = FAILED"
	done
	for sel in 0x80 0x81 0x82 0x84 0x85 0x86 0x88 0x89 0x8a; do
		webc 0x20 1 $sel && r=$(rebc 0x21 16) && echo "curve[$sel]  = $r" || echo "curve[$sel]  = FAILED"
	done
	postflight
	;;
enable | disable)
	val=1
	[ "$1" = disable ] && val=0
	cat >&2 <<EOF
⚠️  ECCW(0x02, 0x83, $val) — announces an OS driver to the EC.
    This may hand fan/thermal policy from the EC to the host. The fan is
    currently the only active thermal actuator on this machine.
    Re-run with CONFIRM=yes to proceed.
EOF
	[ "${CONFIRM:-}" = yes ] || exit 2
	preflight
	i=5
	while [ $i -gt 0 ]; do
		v=$(ecrb $DEV_MBOX 0x30) || die "mailbox read failed"
		[ "$v" -eq 0 ] && break
		i=$((i - 1))
		sleep 0.005
	done
	[ $i -gt 0 ] || die "0xC4[0x30] never idle"
	ecwb $DEV_MBOX 0x31 0x83 || die "write 0x31 failed"
	ecwb $DEV_MBOX 0x32 $val || die "write 0x32 failed"
	ecwb $DEV_MBOX 0x30 0x02 || die "doorbell failed"
	i=5
	while [ $i -gt 0 ]; do
		v=$(ecrb $DEV_MBOX 0x30) || break
		[ "$v" -eq 0 ] && break
		i=$((i - 1))
		sleep 0.005
	done
	printf 'after: 0xC4[0x30] = 0x%02x  (0x00 = accepted)\n' "$(ecrb $DEV_MBOX 0x30)"
	postflight
	;;
*) usage ;;
esac
