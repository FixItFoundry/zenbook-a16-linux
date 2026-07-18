# G08 — Test37: battery workstream REFRAMED + live data read from Linux

**TL;DR:** Battery is **NOT** ADSP/fastrpc-mediated. It is a **firmware-published shared-memory
mailbox in SMEM**. The Windows driver `qcabd8480.sys` ("Qualcomm ACPI Bridge Device", binds
`ACPI\QCOM1045` = `\_SB.ABD`) finds the mailbox by scanning the **DSDT** for the ASCII tag
**`SOSI`** and reading an 8-byte physical address that follows it: **`0xFFE0AD80`** (inside
`smem@ffe00000`). It `MmMapIoSpaceEx`'s that region and services the ACPI battery serial-bus
fields out of it — no glink, no QMI, no fastrpc, no SPMI. **We reproduced the read on the Linux
box** (`memremap(0xFFE0AD80, MEMREMAP_WB)`) and the block contains the live battery serial
**`X2000098`**. Battery on Linux = a small platform driver that memremaps this SMEM block and
exposes `power_supply`, parsing the DSDT field layout. `qcom-battmgr` will never populate it
(it waits on a PMIC_GLINK channel the ASUS ADSP does not provide — see G06).

---

## 1. How we got here (the RE trail)

Roadmap after M5 (ADSP up) was battery → audio → GPU. Prior theory (test35/36, G07): battery is
"ADSP-mediated via ABD → adsprpc/fastrpc → island i2c", so test37 was pencilled as a one-property
fastrpc `qcom,non-secure-domain` tweak. **That theory is now falsified.** The evidence:

1. **`\_SB.ABD` in the DSDT is trivial** — it is *only* a GenericSerialBus operation-region
   provider, with **no `_CRS`, no `_DSM`, no I2C connection of its own**:
   ```
   Device (ABD) { _HID "QCOM1045", _CID "QCOMFFEE", _UID 0
       OperationRegion (ROP1, GenericSerialBus, 0, 0x00100000)
       Method (_REG,2){ If(Arg0==0x09){ AVBL=Arg1 } } }
   ```
   So whatever services this region is a pure software serial-bus controller.

2. **`qcabd8480.sys` strings** (53 KB KMDF driver, `Z:\b\WP\ABD\rel\11.1.4\ABD\Device.c`):
   `\Device\RESOURCE_HUB` (registers as the ACPI serial-bus region handler), `MmMapIoSpaceEx`
   / `MmUnmapIoSpace` (maps physical memory directly), `ZwQuerySystemInformation`,
   `IoGetDeviceObjectPointer`/`IoBuildDeviceIoControlRequest`/`IofCallDriver`. **Zero**
   fastrpc / adsprpc / glink / QMI / SMD / APR/GPR / SPMI strings.

3. **Disassembly (capstone, ARM64)** of the map path pinned the mechanism exactly:
   - Calls `ZwQuerySystemInformation(SystemFirmwareTableInformation)` with provider
     `'ACPI'` (0x41435049) + table `'DSDT'` (0x54445344), two-step length probe
     (expects `STATUS_BUFFER_TOO_SMALL` 0xC0000023), pool tag `'qci0'`.
   - `memchr` the returned DSDT bytes for `'S'`, then `memcmp(hit,"SOSI",4)`.
   - On match: `ldur x19,[x19,#5]` → phys base, then
     `MmMapIoSpaceEx(x0=phys, x1=0xE4 /*228*/, w2=2 /*WriteCombined*/)`.
   Full annotated call sites in `boot-kit/_abd_disasm.txt`; scripts `boot-kit/re_abd*.py`.

## 2. The address — straight out of the DSDT

Raw AML in `device-info/acpi_tables/DSDT.aml` at offset 0x14c:
```
08 53 4F 53 49 0e 80 ad e0 ff 00 00 00 00   =  Name (SOSI, 0xFFE0AD80)
   S  O  S  I  |__ QWord 0x00000000FFE0AD80
```
Driver reads 8 bytes at (tag+5) = **`0xFFE0AD80`**, size **0xE4 (228)**, cache **WriteCombined**.

Live box `/proc/device-tree/reserved-memory/` has **`smem@ffe00000`** → `0xFFE0AD80` is inside
SMEM (`0xFFE00000 + 0xAD80`). SMEM is cacheable DRAM shared with the coprocessors — **APSS
accessible, not XPU-protected** (unlike the island QUP in G07, which watchdog-hung on read).

## 3. Live read from Linux — PROOF (test37)

`/dev/mem` gave a clean **SIGBUS** (region is `no-map` reserved) — safe, not a watchdog reset.
A tiny out-of-tree module using `memremap(0xffe0ad80, 228, MEMREMAP_WB)` + `print_hex_dump`
(`~/sosi_dump/` on the box) read it successfully:

```
SOSI: 00000000: 17 00 00 00 96 02 00 00 00 00 02 00 00 00 00 00
SOSI: 00000030: 01 00 00 00 28 00 00 00 00 00 01 00 00 00 00 00
SOSI: 00000040: 01 00 00 00 5c 00 01 00 00 00 02 00 5d 00 01 00
SOSI: 00000050: 00 00 02 00 62 00 01 00 01 00 02 00 01 00 00 00
SOSI: 00000060: 8a 2d cc 71 09 00 00 00 38 03 00 00 a1 00 00 00
SOSI: 00000070: 0a 00 00 00 19 00 00 00 6e 04 00 00 58 32 30 30
SOSI: 00000080: 30 30 39 38 00 ...                    X 2 0 0
                                                      0 0 9 8   <- battery serial "X2000098"
```
The ASCII **`X2000098`** at +0x7c is the battery serial → this SMEM block IS the live battery
mailbox. Other little-endian u32s present: 0x296=662, 0x2f3=755, 0x338=824, 0x46e=1134,
0x380=896, 0x3d0=976 (candidate voltages mV / capacities mAh — to be decoded against _BIX/_BST).

## 4. The ACPI field layout (what the bytes mean)

DSDT `Field (\_SB.ABD.ROP1 ...)` at SPB **address 0x08** (`\_SB.PMGK` scope) defines the
serial-bus register offsets the bridge answers. Key entries (offset → field, size):
```
0x10100 BPRD  4     battery present / _STA-ish
0x10110 BIXD  0x44  _BIX (battery info extended, 68 bytes)
0x10160 BPCD  0x10  battery power config
0x10178 BPSD  0x14  battery power state
0x101A8 BSTD  0x10  _BST (state, present-rate, remaining-cap, voltage)
0x10200 BMND  0x80  manufacturer name (128)
0x10280 BSND  0x80  serial number (128)   <-- "X2000098"
0x20100+ UVED/UCCD/UMID/UIXD/UMOD/UOXD/UPCD  USB-PD source/sink blocks
0x100 CTLD 4  / 0x180 HSWD 4  (control / handshake doorbell words)
```
These 0x10100+ values are SPB "register" selectors, not offsets into the 228-byte region1.
Region1 is a **descriptor/index** (note the `{0x1005c, .., 0x1005d, .., 0x10062}` entries at
region1 +0x44..+0x58) plus some inline data (serial at +0x7c). The bridge's **second**
`MmMapIoSpaceEx` maps a **region2** whose base/size come from fields inside region1
(`*(r1+0x9c)`, `*(r1+0xe0)`), holding the larger _BIX/_BST/mfr payloads. Decoding region1's
descriptor format + region2 is the driver-writing step (test38+).

## 5. Linux path forward (battery)

**Approach:** a small platform/ACPI driver (model: `drivers/power/supply/*` + the
`acer-aspire1-ec` style) that:
1. Locates the SOSI region — either hardcode `0xFFE0AD80` (from DSDT), or better, look up
   `Name(SOSI)` / scan the DSDT like Windows does, so it's portable across firmware revisions.
2. `memremap`s region1 (and region2 via the in-region pointer), maps SPB register offsets
   (BSTD/BIXD/BSND/BMND) → `POWER_SUPPLY_PROP_*`, exposes `power_supply` "BAT0".
3. Poll (there are CTLD@0x100 / HSWD@0x180 doorbell words — check whether a write is needed to
   trigger a refresh, or whether the EC updates the block autonomously; start read-only/poll).

**Why not qcom-battmgr:** confirmed in G06 — ASUS ADSP announces no `PMIC_GLINK` channel, so
`qcom-battmgr-bat` stays `-EAGAIN` forever. The SOSI/SMEM path is independent and is how Windows
actually does it.

**Next concrete experiments (test38):**
- Re-read region1 twice a few seconds apart while on battery vs charging → identify which u32s
  are live status (current/voltage/state) vs static (design capacity).
- Follow `*(r1+0x9c)`/`*(r1+0xe0)` to region2, dump it, find the 68-byte _BIX and 128-byte
  mfr string ("ASUSTeK"?) to lock the layout.
- Draft the power_supply platform driver; validate capacity/voltage against Windows readings.

## 6. Files / provenance
- Windows driver: `FileRepository.zip` → `qcabd8480.inf_arm64_.../qcabd8480.sys` (+ .inf).
- RE scripts + disasm dump: `boot-kit/re_abd*.py`, `boot-kit/_abd_disasm.txt`, `boot-kit/_sosi.txt`.
- Box module: `~/sosi_dump/` (memremap dump; returns -EAGAIN so it never stays loaded).
- DSDT: `device-info/acpi_tables/DSDT.aml` (raw) + `acpi-decompiled/dsdt.dsl` (field map ~line 2618).
- No DTB change this session — test36 remains the flight DTB (fastrpc `non-secure-domain` tweak
  is **shelved**: it was for the disproven ADSP-mediated theory; revisit only if a *compute*
  offload use-case needs `/dev/fastrpc-adsp`).


---

# ADDENDUM — Test38 (2026-07-11): SOSI decoded + first power_supply node

**SOSI @0xFFE0AD80 is a static DESCRIPTOR blob, not the raw telemetry.** Dumped the full 988
bytes (region2 = same base, larger size) three times over 15s — byte-identical. It holds the
serial `X2000098` (@+0x7c), the nonce `SOSN` (0x46e71cc2d8a, also a top-of-DSDT global), a set
of sub-section offsets (824/896/976/988 — structural, these were the "candidate mV/mAh" values
in §3; they are NOT battery readings), and a 9-entry register-descriptor table for low/GI2C-side
selectors (0x1005c/0x1005d/0x10062/0x10061/0x10060). It contains no manufacturer string, so it
is not the `_BIX` payload.

**DSDT shared-memory globals** (raw AML scan, `boot-kit/_tags.txt`): `SOSI=0xffe0ad80`,
`SOSN=0x46e71cc2d8a`, `SHMA=0x82000000`, plus a mailbox pointer group
`RMTB/RMTX/RFMB/RFMS/RFAB/RFAS` that is **UEFI-patched at boot** (static DSDT shows placeholders
0xAAAAAAAA/0xBBBBBBBB/…). Those patched pointers live only in the **ACPI** boot path; our Linux
is **DT-booted**, so `/sys/firmware/acpi/tables/DSDT` does not exist and we cannot read them here.

**The on-demand protocol** is visible in the DSDT battery methods: `_BST` is just
`BSTT = \_SB.PMGK.BSTD` — one GenericSerialBus read of selector **0x101A8** yields the fresh
16-byte status (BST0..3 = state / present-rate / remaining-cap / voltage); `qcabd8480` performs
the SMEM request internally on that read. Because selector 0x101A8 is far beyond the 988-byte
SOSI map and is absent from the blob's directory, **live `_BST`/`_BIX` require the SMEM
request-ring/doorbell** (control words `CTLD@0x100`, `HSWD@0x180`). Reverse-engineering that
handler is **test39**.

**Deliverable — first Linux power_supply node for the A16 battery.**
`boot-kit/a16-battery-driver/a16_battery.c` (memremap SOSI + `platform_device` +
`power_supply_register`) loads clean and creates `/sys/class/power_supply/a16-battery`:
`present=1`, `technology=Li-ion`, `serial_number=X2000098`, `type=Battery`. Capacity/voltage
are intentionally omitted (not faked) until the doorbell fetch lands.

**Test39 plan:** disassemble `qcabd8480`'s RESOURCE_HUB / `EXECUTE_SEQUENCE` read handler to
recover how it turns an SPB read of selector 0x101A8 into a request into the SMEM ring (likely
keyed by the SOSN nonce, within/near the SOSI region — the RMTB group is ACPI-only and off the
table for DT). Implement that handshake in `a16_battery.c` → real % / voltage / design capacity.
Fallback if the ring proves ACPI-pointer-dependent: revisit whether an ACPI-boot variant can
expose the patched RMTB pointers for a one-time layout capture.
