> ## ★★★ SOLVED 2026-07-31 — fan RPM works. No SSDT was ever needed.
>
> **Read it with:** `/usr/local/bin/glymur-ec-read.sh rpm`
> (source: [`scripts/ec/glymur-ec-read.sh`](../scripts/ec/glymur-ec-read.sh))
>
> ### The two mistakes this doc used to make
>
> **1. "Blocked on an SSDT re-dump" was wrong.** `_SB.FAN1` is `External` and unresolved on
> both OSes — but **`_SB.FAN0` is fully defined in the DSDT we have had since 2026-07-09**,
> with a complete `_FST`. The original analysis stopped at `FAN1` and never checked whether
> another fan device supplied the same thing. Nothing about the SSDTs mattered.
>
> **2. The SSDTs are genuinely absent, and that is now settled** — firmware XSDT has 16
> entries and no SSDT (confirmed identically from Windows and Linux); 942 MB of UEFI image
> and 3.3 GB of Windows drivers byte-scanned, zero ACPI tables beyond EDK2 boilerplate.
> Stop re-opening it.
>
> ### The protocol
>
> ```
> Device (IC10)  _HID "QCOM0F10"  _STR "QUP_1_SE_1"  MMIO 0x00A84000   -> /dev/i2c-9
> Name (UMPC)    I2cSerialBusV2 (0x0076, ... 400000 Hz)                -> EC at 0x76
> Field (DVUM)   Connection(UMPC), Offset(0x50) ... AttribBytes(0x05), FC52
>                                                                      -> command 0x52
> ```
>
> On the wire:
>
> ```
> write:  S 0x76 W  0x52  reg_hi reg_lo len 0x00 0x00  P
> read:   S 0x76 W  0x52  Sr 0x76 R  <byte>  P
> ```
>
> ⚠️ **The trap that cost an hour.** For an *I2C* GenericSerialBus connection,
> `AttribBytes(n)` is a **raw n-byte transfer — there is no SMBus count byte.** The AML
> buffer's byte 1 holds a length (`ECR1 = 0x04`) and it is tempting to put that on the wire.
> Do not. It shifts every field by one, the EC reads a bogus register, and **every read
> returns 0xFF** — which looks exactly like "the EC is refusing us" rather than "our framing
> is off by one byte". The giveaway was that commands `0x0E` and `0x51` answered fine while
> `0x52` did not.
>
> ### Fan RPM
>
> From `\_SB.FAN0.GCFR`:
>
> ```
> RPM = (RECM(0x0603,1) << 8) | RECM(0x0602,1)
> ```
>
> `_FST` buckets it against `FOPR = {0, 0x0870, 0x0A8C, 0x14A0}` = **0 / 2160 / 2700 / 5280
> RPM**, with `GRAN = 0xC8` = 200 RPM.
>
> **Validated on hardware 2026-07-31** (BIOS `UX3607OA.312`) — the value tracks temperature,
> which is what makes it a real tachometer rather than a plausible constant:
>
> | | hottest zone | RPM |
> |---|---|---|
> | idle | 44 C | 2340–2400 |
> | all 18 cores loaded | 57 → 73 C | 2400 → **2940** |
> | 20 s after load stopped | 54 C | back to 2340 |
>
> ### EC registers the DSDT references (all read-only so far)
>
> | register | meaning |
> |---|---|
> | `0x0602` / `0x0603` | fan 0 RPM, low / high byte |
> | `0x0604` | unknown, reads 0x30–0x32 |
> | `0x0624` / `0x0625` | **NOT a fan.** Reads 1380 combined; the association with "fan 2" was a guess from register adjacency and is **withdrawn** — see below. Meaning unknown. |
> | `0x0C7C` | RECM/WECB doorbell, 0 = idle |
> | `0x0C6C`–`0x0C6F` | unknown |
> | `0x0B4A`–`0x0B53` | 10-byte block, values move with load — likely the fan curve |
>
> ### ⛔⛔ IT CRASHED THE MACHINE — 2026-07-31, read before any further EC work
>
> Polling the EC while the CPU was loaded **hard-reset the box**: froze on screen, rebooted,
> no kernel fault of any kind. Reconstruction from the persistent journal:
>
> - Crash at **11:11:52**, mid-poll, within a couple of seconds of 18 CPU-load processes
>   spawning. Last kernel message was **11:06:44** and entirely benign; after that only
>   sudo/audit lines, then the log just stops. No oops, no panic, no watchdog — the same
>   signature as the display-teardown crash that was never traced.
> - **The I2C controller was already erroring 15 minutes earlier**, at 10:58, during the
>   transaction-shape experiments:
>
>   ```
>   gpi a00000.dma-controller: Error in Transaction
>   geni_i2c a84000.i2c: DMA txn failed:3
>   geni_i2c a84000.i2c: GPI transfer failed: -5
>   ```
>
>   These correlate with the **combined write+read repeated-start** form
>   (`w6@0x76 ... r7@0x76`), which also returned 0xFF. The two-transaction form the working
>   reader uses did **not** produce them.
>
> ⇒ **Prime suspect is the GENI/GPI DMA path, not the EC.** Repeated-start transfers on
> `a84000.i2c` drive a DMA path that fails `-5` on this hardware, and hammering it appears to
> be what eventually took the SoC down.
>
> **Rules until this is understood:**
> 1. **Never use combined/repeated-start transfers** on this controller. Two separate
>    `i2ctransfer` calls only.
> 2. **Do not poll the EC under CPU load.** The one validated measurement run sampled every
>    5 s and read 2 registers; the run that crashed sampled 5 registers per row.
> 3. **Keep it to `0x0602`/`0x0603`.** The crash run also touched `0x0604`, `0x0624`,
>    `0x0625`, which we do not understand.
> 4. Watch for `geni_i2c ... GPI transfer failed` in `dmesg` — that is the early warning.
>
> ⚠️ Note this cost a hard reset **after** fan RPM was already working and committed. The
> RPM result stands; confirming fan 2 does not justify another one.
>
> ### Still not done
>
> - ~~**`FAN2` is unconfirmed.**~~ **CLOSED 2026-07-31: no second *addressable* fan zone.**
>
>   ```asl
>   Name (FNTR, 0x0705)                                  // static constant
>   FAN2._STA:  If ((\_SB.FNTR & 0x03) >= 0x02) { Return (0x0F) } Else { Return (Zero) }
>   ```
>
>   `0x0705 & 0x03` = **1**, so `_STA` returns **Zero** — the device is absent.
>
>   ⚠️ **CORRECTED: this machine physically HAS TWO FANS.** Observed directly 2026-07-31 —
>   both rotors spin up together under load. `FNTR & 0x03` is **not a rotor count**; it is
>   the number of **independently addressable fan zones**. The confirming evidence is in
>   `\_SB.CIO1._DSM`: when that field is `2` the DSDT issues a *second* `ECGE._DSM` call with
>   `MSFS[0] = 0x02`, i.e. a second fan index. On this machine only index 1 is ever sent.
>
>   ⇒ **Two rotors, ganged to one controller with one tachometer.** `FAN0` is that zone and
>   `0x0602`/`0x0603` is its tach. `FAN2` would be a second *independently controlled* fan,
>   which this chassis does not have. `FAN0` has no `_STA` at all, so it is unconditionally
>   present.
>
>   **And `FAN2` could never report RPM anyway**, on any SKU: its `_FST` is a *static*
>   `Package (0x03) {Zero, Zero, Zero}`, not a Method. Its only real function is pushing trip
>   points via `CMDP` -> `\_SB.ECGE._DSM`, a different EC gateway that never touches
>   `IC10.RECM`.
>
>   ⚠️ **`0x0624`/`0x0625` was never derived from the AML** — it was guessed from register
>   adjacency to `0x0602`/`0x0603`. The hard reset above was incurred probing a device this
>   machine does not have. **Derive registers from the AML the way `FAN0`'s were, or do not
>   touch the EC.**
> - **Nothing writes yet.** `SUFC` (set user fan curve) and `ECWM` are decoded but untried.
>   This EC owns charging — reads are safe, writes are not. Jesse's standing instruction:
>   **ask before any write.**
> - **`cooling-maps`** is still the blocker for actual thermal control; RPM readback does not
>   by itself give the kernel a fan cooling device.

# The embedded controller and fan interface — decoded from the WoA ACPI dump

*Written 2026-07-30. Everything here is either read out of the Windows-on-Arm DSDT, read
out of Qualcomm's own board DTS, or measured on loazen. Where something is a guess it says
so.*

The goal is fan control in the kernel instead of leaving it to the EC. This document is the
map of how Windows talks to that EC, and how far we got reproducing it from Linux.

**Status: the EC answers Linux on I2C.** Read-only, no DT change, no reboot. That is the
milestone the plan in `power-and-thermal.md` §4 asked for.

---

## 1. Where the EC lives

| | |
|---|---|
| ACPI device | `\_SB.IC10`, `_HID` **`QCOM0F10`**, `_UID` 10, `_STR` **`QUP_1_SE_1`** |
| Register base | `0x00A84000`, len `0x4000`, GSIV `0x182` (GIC SPI 354) |
| DT node | `i2c9: i2c@a84000` in `glymur.dtsi:1382` — `qcom,geni-i2c` |
| Live on loazen | **`/dev/i2c-9`**, `status = okay`, pinctrl `default` applied |
| Bus speed | 400 kHz (`0x00061A80` in the DSDT, `clock-frequency = <400000>` in the DTS) |

**Two I2C slaves**, and both sources agree:

```dts
/* glymur-asus-zenbook-a16-ux3607oa.dts:668 — Qualcomm's own board file */
&i2c9 {
	clock-frequency = <400000>;
	status = "okay";

	/* EC subdevice @ 0x5b */
	/* EC @ 0x76 */
};
```

```asl
Name (UMPC, ResourceTemplate () { I2cSerialBusV2 (0x0076, ..., AddressingMode7Bit, "\\_SB.IC10", ...) })
Name (SL5B, ResourceTemplate () { I2cSerialBusV2 (0x005B, ..., AddressingMode7Bit, "\\_SB.IC10", ...) })
```

### ✅ Both answer on the live machine

```
# i2cget -y 9 0x76 0x00  -> 0x00      EC (UMPC)
# i2cget -y 9 0x5b 0x00  -> 0xff      EC subdevice (SL5B)
```

Nothing is bound to `i2c-9` and the node has no DT children, so there is no driver conflict
to work around — the bus is simply free.

⚠️ **Correction worth recording.** The constants `0xC4` and `0xC9` that appear all over
`ECRB`/`ECWB` are **not** I2C addresses (and are not `0x62`/`0x64` shifted). Probing those
addresses NAKs. They are *EC-internal device selectors* passed inside the payload — the I2C
address is fixed by the ACPI `Connection()`, i.e. 0x5b or 0x76.

---

## 2. The classic ACPI EC is a decoy

There is a `Device (EC0)` with `_HID = PNP0C09`, but:

```asl
Method (_STA, 0, NotSerialized) { Return (Zero) }
```

`_STA` returns zero — **the standard embedded-controller device is disabled**, and it
declares no `EmbeddedControl` operation region at all. Every one of its methods goes through
`\_SB.IC10.WEBC` / `\_SB.IC10.REBC` instead. So there is no port-mapped EC to drive and
`drivers/acpi/ec.c`-style thinking does not apply. This is an I2C EC wearing an ACPI hat.

---

## 3. The wire protocol

Built from `OperationRegion (DV5B, GenericSerialBus, ...)` and the `C10G`/`C10R` buffers.

`C10G` is a 6-byte GSB buffer — `{status, length, data0..data3}` = `G010, G110, G210, G310,
G410, G510`. `C10R` is 3 bytes, `{C10S, length, C10D}`, initialised `{0x00, 0x01, 0x00}`.

### Byte read — `ECRB(dev, reg)`

```
G010 = 0        /* status  */
G110 = 2        /* length  */
G210 = dev      /* EC-internal device selector: 0xC4 or 0xC9 */
G310 = reg
FC10 = C10G     /* -> slave 0x5b, command 0x10, write 2 data bytes {dev, reg} */
C10R = FC11     /* <- slave 0x5b, command 0x11, read 1 data byte             */
if (C10S == 0) return C10D
```

### Byte write — `ECWB(dev, reg, val)`

Same shape: set up `C10G`, `FC10 = C10G`, then `C10S = 0`, `C10D = val`, `FC11 = C10R`.
Guarded by `if (AVBL && ECRD == One)` and the `\_SB.MUT0` mutex (5 s timeout).

⚠️ Every access is serialised on `\_SB.MUT0`. There are also `ECMX` and **`FANL`** (a fan
lock) mutexes. Any Linux driver must not interleave transactions.

### Block layer — `WEBC(cmd, len, buf)` / `REBC(cmd, len)`

Built on top of `ECRB`/`ECWB` against **EC-internal device `0xC9`**:

- status/control register **`0x6F`**, data window **`0x40`–`0x6F`**, command register **`0x6E`**
- `WEBC`: poll `0x6F` until clear → write `len` bytes to `0x40+i` → set bit `0x80` in `0x6F`
  → write `cmd` to `0x6E`
- `REBC`: write `0x20` to `0x6F` → write `cmd` to `0x6E` → poll until bit `0x80` set → read back
- Both give up after a bounded retry count and set bit `0x40` in `0x6F` on timeout

Device `0xC4` uses a different, simpler mailbox at registers `0x30`/`0x31`/`0x32`.

---

## 4. The fan commands

From `Device (EC0)`, expressed as `WEBC`/`REBC` command bytes. Command **`0x20`** is
always sent first with a 1-byte argument — a fan selector/index.

| Method | Sequence | Meaning (inferred from name and shape) |
|---|---|---|
| `GDFC(idx)` | `WEBC(0x20, 1, {idx})` then `REBC(0x21, 0x10)` | **Get default fan curve** — 16 bytes |
| `SUFC(a,b,c,d,idx)` | `WEBC(0x20, 1, {idx})` then `WEBC(0x22, 0x10, buf)` | **Set user fan curve** — 4 dwords packed little-endian into 16 bytes |
| `GFLB(idx)` | `WEBC(0x20, 1, {idx})` then `REBC(0x24, 0x08)` | **Get fan limits/bounds** — 8 bytes |

So: `0x20` select, `0x21` read default curve, `0x22` write user curve, `0x24` read limits.
A 16-byte curve is consistent with 8 (temperature, duty) points.

There are also two `_DSM` UUIDs on `IC10`, the second of which looks fan-specific:

- `DSME` = `62617bb4-a257-415d-ad2c-0f6bd849278a`, functions `EF01`–`EF08`
- `DSMF` = `5792aa21-7727-443f-8ca2-e6b3be94b6b1`, functions `FF01`–`FF13` ← next to `FANL`

---

## 5. ⚠️ The gap: no RPM reader yet

The fan *speed* object is declared but not defined in what we have:

```asl
External (_SB_.FAN1, UnknownObj)
External (_SB_.FAN1._FST, UnknownObj)   /* _FST = fan status: control, speed */
External (_SB_.FAN1._STA, UnknownObj)
External (_SB_.FAN1.GRAN, IntObj)
```

`External` means `FAN1` lives in an **SSDT**, and **neither `acpi_dump/` nor
`acpi_dump_ubuntu/` contains any SSDT** — both hold only DSDT plus the static tables. So the
method that actually reports RPM was never captured.

★ **Action: re-dump ACPI from Windows including SSDTs.** That yields `_FST` and with it the
exact command byte for fan speed. Until then we have the curve interface but no readback,
and readback is what the plan wants first.

---

## 6. Suggested order of work

1. ★ **Re-dump the WoA ACPI tables with SSDTs** and pull `\_SB.FAN1._FST`. Cheapest path to
   a real RPM number, and it closes the one gap in this document.
2. **Exercise `REBC` read-only from userspace on `/dev/i2c-9`** — implement the §3 read
   sequence with `i2ctransfer` or a small script and issue `GDFC`: select a fan with
   `0x20`, then read 16 bytes with `0x21`. A plausible-looking curve is proof the protocol
   decode is right, and it *reads* the EC rather than steering it.
   ⚠️ Note this is no longer pure reading — `REBC` writes the command and status registers
   to request data, even though it changes no fan setting. Worth being deliberate about.
3. **Only then** consider `SUFC`. Writing a curve steers the thermal hardware.
4. Once RPM readback works, wrap it as a proper driver: an `i2c` child of `i2c9` at `0x76`
   exposing `hwmon` (`fan1_input`, and `pwm1` if we get that far).

⚠️ **Risk asymmetry, restated.** This EC also owns charging and power sequencing. Reads are
cheap and safe; writes are not. Read a lot before writing anything.

---

## Appendix — commands used

```sh
# which bus is IC10 / a84000?
for d in /sys/bus/i2c/devices/i2c-*; do
    echo "$(basename $d) <- $(readlink -f $d | sed 's|/i2c-[0-9]*$||' | xargs basename)"
done | sort -V                          # -> i2c-9 <- a84000.i2c

# is anything already bound, and is the node live?
ls /sys/bus/i2c/devices/ | grep '^9-'   # -> nothing
tr -d '\0' < /sys/firmware/devicetree/base/soc@0/geniqup@ac0000/i2c@a84000/status

# does the EC answer?  (read-only)
i2cget -y 9 0x76 0x00
i2cget -y 9 0x5b 0x00

# mining the dump
D='/run/media/jcasco/LoA Project/Zenbook A16 Linux on ARM/acpi_dump/dsdt.dsl'
grep -n 'I2cSerialBusV2\|Method (ECRB\|Method (WEBC\|PNP0C09\|FAN1' "$D"
```

⚠️ `find /proc/device-tree -name …` silently finds nothing — it is a symlink and `find`
does not follow it. Use `/sys/firmware/devicetree/base` or `find -L`.
