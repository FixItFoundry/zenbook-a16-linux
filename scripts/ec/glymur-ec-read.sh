#!/bin/bash
# glymur-ec-read.sh — read the ASUS embedded controller on the Zenbook A16.
#
# READ ONLY. This implements RECM, the EC *read* command. It writes a request
# (register address + length) to the EC and reads the answer back; it changes no
# EC state. Do not extend this to writes without knowing what you are doing —
# this EC also owns charging.
#
# ── The protocol, transcribed from the Windows-on-Arm DSDT ────────────────────
#
#   Device (IC10)  _HID "QCOM0F10"  _STR "QUP_1_SE_1"  MMIO 0x00A84000
#       => Linux /dev/i2c-9   (verified: /sys/bus/i2c/devices/i2c-9 -> a84000.i2c)
#   Name (UMPC) I2cSerialBusV2 (0x0076, ... 400000 Hz)      => EC at 0x76
#   Field (DVUM, BufferAcc) { Connection(UMPC), Offset(0x50),
#                             ... AccessAs(BufferAcc, AttribBytes(0x05)), FC52 }
#       => command byte 0x52, five data bytes
#
#   Method (RECM, 2):  ECR2 = reg>>8;  ECR3 = reg&0xFF;  ECR4 = len
#                      \_SB.IC10.FC52 = ECRR      (write request)
#                      ECRR = \_SB.IC10.FC52      (read answer; ECR0 must be 0)
#
# ⚠️ THE TRAP: for an *I2C* GenericSerialBus connection, AttribBytes(n) is a RAW
# n-byte transfer — there is NO SMBus count byte. Sending one (the natural
# reading of the AML buffer, whose byte 1 holds a length) shifts everything by
# one, the EC reads a bogus register, and every read comes back 0xFF. That cost
# an hour. On the wire it is simply:
#
#   write:  S 0x76 W  0x52  reg_hi reg_lo len 0x00 0x00  P
#   read:   S 0x76 W  0x52  Sr 0x76 R  <byte> P
#
# ── Fan RPM, from \_SB.FAN0.GCFR ──────────────────────────────────────────────
#
#   Local0  = (RECM(0x0603,1) << 8)
#   Local0 |=  RECM(0x0602,1)
#
# _FST then buckets that against FOPR = {0, 0x0870, 0x0A8C, 0x14A0}
# = 0 / 2160 / 2700 / 5280 RPM, with GRAN = 0xC8 = 200 RPM.
#
# Validated 2026-07-31 on BIOS UX3607OA.312: idle 2340 RPM @ 44 C; all 18 cores
# loaded -> 2940 RPM @ 73 C; back to 2340 RPM twenty seconds after the load
# stopped. The value tracks temperature, so this is the real tachometer.

set -u
BUS=9
EC=0x76
CMD=0x52

die() { echo "glymur-ec-read: $*" >&2; exit 1; }
command -v i2ctransfer >/dev/null || die "i2ctransfer not found (install i2c-tools)"
[ -e "/dev/i2c-$BUS" ] || die "/dev/i2c-$BUS missing"

# ec_read <16-bit register> -> prints one byte as 0xNN, empty on failure
ec_read() {
	local reg=$1
	local hi=$(( (reg >> 8) & 0xFF )) lo=$(( reg & 0xFF ))
	sudo i2ctransfer -y "$BUS" w6@$EC $CMD "$hi" "$lo" 0x01 0x00 0x00 >/dev/null 2>&1 || return 1
	sudo i2ctransfer -y "$BUS" w1@$EC $CMD r1@$EC 2>/dev/null
}

ec_read_dec() { local v; v=$(ec_read "$1") || return 1; [ -n "$v" ] || return 1; echo $((v)); }

fan_rpm() { # $1 = lo register, $2 = hi register
	local lo hi
	lo=$(ec_read_dec "$1") || return 1
	hi=$(ec_read_dec "$2") || return 1
	echo $(( (hi << 8) | lo ))
}

hottest() {
	local m=0 t
	for z in /sys/class/thermal/thermal_zone*/temp; do
		t=$(cat "$z" 2>/dev/null || echo 0)
		[ "$t" -gt "$m" ] && m=$t
	done
	awk -v m="$m" 'BEGIN{printf "%.1f", m/1000}'
}

# FOPR buckets, matching what _FST would report
fan_state() {
	local r=$1
	if   [ "$r" -gt 5280 ]; then echo 4
	elif [ "$r" -gt 2700 ]; then echo 3
	elif [ "$r" -gt 2160 ]; then echo 2
	else echo 1; fi
}

usage() {
	cat >&2 <<EOF
usage: $0 <command>
  rpm                 fan 0 RPM (the one _FST reports)
  rpm2                the 0x0624/0x0625 pair — probably fan 2, UNVERIFIED
  watch [n] [secs]    sample RPM + hottest zone, n times (default 10 x 3s)
  reg <hex>           read one EC register, e.g. reg 0x0602
  map                 dump every EC register the DSDT references
EOF
	exit 2
}

case "${1:-}" in
	rpm)
		r=$(fan_rpm 0x0602 0x0603) || die "EC read failed"
		echo "$r RPM (state $(fan_state "$r"))"
		;;
	rpm2)
		r=$(fan_rpm 0x0624 0x0625) || die "EC read failed"
		echo "$r  (0x0625<<8|0x0624 — believed to be fan 2, not yet confirmed)"
		;;
	watch)
		n=${2:-10}; s=${3:-3}
		for _ in $(seq 1 "$n"); do
			r=$(fan_rpm 0x0602 0x0603) || r=-1
			printf '%s  %5s RPM  state %s  hottest %s C\n' "$(date +%T)" "$r" "$(fan_state "$r")" "$(hottest)"
			sleep "$s"
		done
		;;
	reg)
		[ $# -ge 2 ] || usage
		v=$(ec_read $(( $2 ))) || die "EC read failed"
		printf '%s = %s (%d)\n' "$2" "$v" "$((v))"
		;;
	map)
		# Every register the DSDT passes to RECM. Read-only.
		printf '%-8s %-6s %s\n' REG VALUE NOTE
		for spec in \
			"0x0602 fan0 RPM low byte" \
			"0x0603 fan0 RPM high byte" \
			"0x0604 unknown (0x32 = 50 observed)" \
			"0x0624 probable fan2 low" \
			"0x0625 probable fan2 high" \
			"0x0C7C RECM/WECB doorbell — 0 = idle" \
			"0x0C6C unknown" "0x0C6D unknown" "0x0C6E unknown" "0x0C6F unknown"
		do
			reg=${spec%% *}; note=${spec#* }
			v=$(ec_read $(( reg )) ) || v="ERR"
			printf '%-8s %-6s %s\n' "$reg" "$v" "$note"
		done
		echo
		echo "0x0B4A..0x0B53 block:"
		out=""
		for reg in $(seq $((0x0B4A)) $((0x0B53))); do out="$out $(ec_read "$reg")"; done
		echo " $out"
		;;
	*) usage ;;
esac
