# G09 — Test39: qcabd8480 read-handler RE + SOSI mailbox is DORMANT (battery reframe #2)

**TL;DR.** Fully reverse-engineered `qcabd8480.sys` and empirically dumped the whole SOSI
SMEM object from Linux. Two decisive results:

1. **`qcabd8480` is a pure *polled shared-memory* software SPB controller.** Its ENTIRE import
   surface for I/O is `MmMapIoSpaceEx` + plain loads/stores + a DSDT scan. **No glink, QMI,
   SPMI, IPCC, fastrpc, or any hardware-signalling API.** It cannot ring a doorbell in
   hardware — every "doorbell" (CTLD/HSWD) is just a write into the SMEM window that a
   coprocessor/EC polls.

2. **The SOSI object at `0xFFE0AD80` is DORMANT on our Linux boot — all battery data is zero.**
   The 988-byte blob contains only a static header (version, serial, SOSN nonce, a small GI2C
   selector table, two empty 22-entry tables). Every battery/USB-PD buffer, and the CTLD/HSWD
   handshake words, read `0x00000000`. The mailbox has never been *enabled* (`LKUP == 0`).

**Consequence — battery reframe #2:** the ABD/SOSI SMEM path is **not** an independent shortcut
around the dead battery provider. It is **downstream** of it. On Windows the mailbox is woken by
`LKST(1)` (sets `LKUP=1`, writes the CTLD/HSWD handshake), and `LKST` is called by the driver
only when the **pmic_glink / battery subsystem signals ready**. On our DT boot that provider is
down (G06: ASUS ADSP publishes no `PMIC_GLINK` channel → `qcom-battmgr-bat` is empty, verified
again this session), so `LKST(1)` never runs, `LKUP` stays 0, and the SMEM buffers stay empty.
**Same root blocker as `qcom-battmgr` `-EAGAIN`, now unified.**

---

## 1. Driver architecture (static RE — capstone/pefile, `boot-kit/re_abd9.py`)

`qcabd8480.sys`: KMDF, 6359 instrs, imagebase 0x140000000, 65 functions (.pdata-derived).
Imports that matter: `MmMapIoSpaceEx`, `MmUnmapIoSpace`, `ZwQuerySystemInformation`, `memchr`,
`IoBuildDeviceIoControlRequest`/`IoGetDeviceObjectPointer`/`IofCallDriver` (RESOURCE_HUB client),
Wdf*, pool, `sprintf_s`/`strcpy_s`. **Nothing else** — confirms the polled-SMEM model.

### 1a. Find + map SOSI  (`func 0x1400040b0`)
```
ZwQuerySystemInformation(SystemFirmwareTableInformation, 'ACPI','DSDT')  // two-step length probe
memchr(dsdt, 'S', 0xFFD); memcmp(hit,"SOSI",4)                            // scan DSDT for the tag
x19 = *(u64*)(hit+5)                       = 0xFFE0AD80                    // phys base
r1  = MmMapIoSpaceEx(0xFFE0AD80, 0xE4=228, WriteCombined)                 // map header
count     = *(u32*)(r1+0x9c)               = 3
base_size = *(u32*)(r1+0xe0)               = 0x3d0
MmUnmapIoSpace(r1, 0xE4)
r2  = MmMapIoSpaceEx(0xFFE0AD80, base_size + 4*count = 0x3dc, WriteCombined)  // remap full blob
return r2
```
So the window is `[0xFFE0AD80 .. +0x3DC)` — **988 bytes**, same base, WriteCombined.

### 1b. Parse + cache descriptor, then UNMAP  (`func 0x1400042a0`, run once, flag @0x1400063c0)
Copies from the blob into a global descriptor struct and then **unmaps the blob**:
- serial (`strcpy_s` from `blob+0x7c`), plus version-gated u32 params from
  `blob+{0x04,0x08,0x2c,0x30,0x5c,0x60,0x6c,0x70,0x74,0x78,0xac,...}`.
- `version = *(u32*)(blob+0)` (=0x17). Feature gates at ≥0x0e, 0x10, 0x13, 0x14, 0x15.
- **table1** = `blob + *(u32*)(blob+0xa8)` (=+0xf8), `*(u32*)(blob+0xa4)` (=22) entries → memcpy.
- **table2** (ver≥0x15) = `blob + *(u32*)(blob+0xdc)` (=+0x150), 22 entries → memcpy.
- final `MmUnmapIoSpace(blob, base_size + 4*count)`.

**Only ONE `MmMapIoSpaceEx` call-site exists in the whole driver** (both maps in 1a). The blob is
read once and unmapped; ACPI field reads (selectors 0x10100…) are served from the cached copy.
The big 0x140004ae8 function (13 KB, contains the WDF request dispatch / selector→offset translate)
was **not** fully decoded this session — it is the remaining static-RE target if we ever need the
exact small-selector (CTLD/HSWD) physical placement (see §4).

## 2. SOSI blob — decoded header (empirical dump, `boot-kit/a16dump/sosi_probe.c`)
`ver=0x17  cnt=3  base_size=0x3d0  size=0x3dc`
```
+0x00 u32 version      = 0x17
+0x04 u32              = 0x296
+0x08 u32              = 0x20000
+0x2c u32              = 0x2f3
+0x30 u32              = 1
+0x44 .. small selector mini-table: {0x5c,1,2},{0x5d,1,2},{0x62,1,2}  (GI2C-side, not battery)
+0x60 u32              = 0x71cc2d8a  ) SOSN nonce = 0x46e71cc2d8a  (matches DSDT global)
+0x78 u32              = 0x46e       )
+0x7c ascii            = "X2000098"  (battery serial)
+0x9c u32 count        = 3
+0xa4 u32 t1_count     = 22 (0x16)
+0xa8 u32 t1_off       = 0xf8
+0xdc u32 t2_off       = 0x150   (ver>=0x15)
+0xe0 u32 base_size    = 0x3d0
+0x338 u32             = 0x1005c   (a selector id, in the data area)
```
**Everything from 0xf8 to 0x3dc is 0x00** except `T1[17]=1` and `blob+0x338=0x1005c`. CTLD(sel
0x100), HSWD(sel 0x180) and every battery buffer (BPRD/BIXD/BSTD/BMND/BSND) read all-zero — both
as linear offsets and (for 0x10100+) they fall outside the 988-byte window entirely. **The
selector→offset scheme is NOT linear, and there is no live data resident.**

## 3. Enable/handshake path (DSDT, read-only ground truth)
`\_SB.PMGK.LKST(Arg0)` and `\_SB.UCSI._STA` both do, gated on `LKUP > 0`:
```
\_SB.PMGK.CTL0 = 1 ; \_SB.PMGK.CTLD = \_SB.PMGK.CTLT     // write 1 to selector 0x100
\_SB.PMGK.HSW0 = 4 ; \_SB.PMGK.HSWD = \_SB.PMGK.HSWT     // write 4 to selector 0x180
```
`LKST` is **not** called from AML — it is invoked by the driver on a battery-subsystem-up event.
`CMBD._STA`, `UCSI._STA` all print/branch "pmicglink down" when `LKUP == 0`. Battery `_BST`/`_BIX`
are plain field reads (`BSTT = BSTD`); the driver services them from SMEM once the mailbox is live.

## 4. Where this leaves the battery workstream (for test40)
The SMEM path only yields data once the provider wakes it. Three ways forward, in priority order:

- **(A) Revive the real provider (recommended).** Battery ultimately needs the pmic_glink /
  battery-manager path the ADSP is supposed to host. This is the same fight as `qcom-battmgr`
  `-EAGAIN` (G06). If that comes up, `LKUP` gets set and BOTH battmgr *and* SOSI populate.
- **(B) Test whether an OS-side SMEM handshake wakes an autonomous EC.** Since `qcabd8480`'s only
  power is writing SMEM, IF Windows battery works purely by that, then writing the CTLD/HSWD
  handshake from Linux *might* wake the EC without glink. **Blocked on grounding:** we do not yet
  know the physical SMEM offset that selector 0x100 (CTLD) maps to — small-selector translation
  lives in the un-decoded 0x140004ae8 handler. Do NOT blind-write a firmware mailbox. Finish
  RE of that function first, then a single-variable enable-write test is well-grounded.
- **(C) One-time ACPI-boot capture.** Boot Windows/ACPI once with the mailbox live and snapshot
  the populated blob + the patched RMTB/RFMB pointers, to learn the selector→offset map directly.

## 5. Files / provenance
- RE tooling (new): `boot-kit/re_abd9.py` (`info|map|after|xref|func|funcs` passes).
- Empirical probe (new): `boot-kit/a16dump/sosi_probe.c` + `run_probe.sh` (`~/sosi_probe` on box).
- DSDT: `acpi-decompiled/dsdt.dsl` — ABD region @1425, PMGK battery Field @2618, LKST @2331,
  UCSI._STA @104107, CMBD (PNP0C0A) @2938.
- Driver: `boot-kit/a16-battery-driver/a16_battery.c` (serial-only, honest; size now header-derived).
- Prior: G08 (test37/38 reframe). test36 remains the flight DTB — **no DTB change in test39.**
