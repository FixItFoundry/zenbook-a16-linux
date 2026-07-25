# eDP: what the vendor firmware says, and what is now ruled out

**Date:** 2026-07-24 · **Box:** loazen (glymur, UX3607OA) · **Kernel:** 7.1.0-glymur-clean2
**DTB:** test62 (HBR2/5.4G) · **State:** CR passes on all 4 lanes, EQ never sets, `-110`

This supersedes the swing/drive-level theory. Read the "closed doors" section before
proposing anything — the point of this document is to stop the project re-deriving
"everything matches vendor" for a fourth time.

---

## Why this was written

The eDP project has now concluded **three separate times**, by three different routes,
that the drive-level path matches Qualcomm's own configuration:

| When | Route | Conclusion |
|---|---|---|
| 2026-07-12 | `DISPLAY-BRINGUP-FINDINGS.md` | DT eDP PHY/panel/link-rate "match CLO" |
| 2026-07-24 am | CLO source search | `phy-qcom-edp.c` byte-identical across every vendor branch |
| 2026-07-24 pm | **UEFI firmware RE** (this doc) | tables *and* register offsets identical to firmware |

Each pass was sound and each was answering a slightly different question, but the
repetition is itself the finding: **the driver's drive-level configuration is not the
bug, and no amount of further table archaeology will make it one.** What changed today
is that we now have evidence from a *binary that successfully lights this panel*, not
from another copy of the same Linux source.

---

## Artifacts

| Thing | Path |
|---|---|
| UEFI display driver | `a16dump/uefi_ext/fv0/volume-fv0/file-b4216697-.../file-4138022f-06c7-4f79-9c94-7e33b511a4e7/section1.pe` |
| Local copy | `re/DisplayDxe.pe` (741376 B, md5 in `re/`) |
| Windows display KMD | `Exported_Drivers/qcdx8480.inf_arm64_e11dd2e33e0b42d3/qcdxkm8480.sys` → `re/qcdxkm8480.sys` |
| Ghidra project | `re/ghproj` (program `DisplayDxe.pe`, already analyzed) |
| Ghidra scripts | `re/ghidra_scripts/{DumpDpAsm,DumpAt,DumpRange,DumpFxnsInit}.java` |
| Raw output | `re/ghidra-asm.log`, `re/setlanedrv.log`, `re/edpfxns.log`, `re/fxnsinit.log` |

**Ghidra note:** `/opt/ghidra_12.1.2_PUBLIC` ships **no `linux_arm_64` decompiler native**
(`Ghidra/Features/Decompiler/os/` has x86_64 and mac only), so headless decompilation
fails with "Could not find decompiler executable". The scripts above dump *disassembly*
instead, which is enough. Re-run against the already-analyzed project with:

```bash
/opt/ghidra_12.1.2_PUBLIC/support/analyzeHeadless \
  ~/Projects/zenbook-a16-linux/re/ghproj DisplayDxe \
  -process DisplayDxe.pe -noanalysis \
  -scriptPath ~/Projects/zenbook-a16-linux/re/ghidra_scripts \
  -postScript DumpAt.java 0x25850
```

`DumpAt.java` takes function addresses as arguments and will disassemble + create a
function at an address that analysis left undefined (the vtable-only ones).

---

## Map of the firmware DP stack

Functions are unnamed in the binary; these were located by their debug-print strings.

| Address | What it is |
|---|---|
| `FUN_0002009c` | `DP_LinkSetupPreemphSwing` — builds the request, calls the HAL, backs levels off on failure |
| `FUN_00024d20` | HAL dispatch: `HAL_DP_Fxns[id]` at `0xabbc8`, **stride 0x58**, SetLaneDrv at **+0x18** |
| `FUN_00024c58` | `HAL_DP_PhyFxnsInit` — requires PHY version **major=1 minor=4 step=1**, read from `base + 0x90000` |
| `FUN_00027520` | vtable installer for DP0–DP2 |
| `FUN_00025da8` | vtable installer for the **4th instance (eDP)** |
| `FUN_00025018` | `HAL_DP_1_4_1_PHY_Config` (vtable +0x00) — polls C_READY then PHY_READY |
| **`FUN_00025850`** | **eDP SetLaneDrv (vtable +0x18) — the swing/emphasis writer** |
| `0xb3988` | global holding the MMIO base pointer every register access goes through |

### The swing/emphasis tables

Six 64-byte tables. Cells are `{u16 emphasis, u16 swing}`, indexed `[v_level][p_level]`,
row stride `0x10`, column stride `0x4`.

| Address | Selected when |
|---|---|
| **`0x547e0`** | **eDP, rate > 270000, flag=0** ← our case |
| `0x54820` | eDP, rate > 270000, flag=1 |
| `0x54860` | eDP, rate ≤ 270000, flag=0 |
| `0x548a0` | eDP, rate ≤ 270000, flag=1 |
| `0x548e0` | DP, rate > 270000 |
| `0x54920` | DP, rate ≤ 270000 |

The rate threshold is the literal `0x41eb0` = **270000** (kHz), i.e. the same
HBR/HBR2 split `qcom_edp_set_voltages()` makes with `dp_opts->link_rate <= 2700`.

Decoding `0x547e0`:

```
swing: 0b 11 17 1c | 10 19 1f -- | 19 1f -- -- | 1f -- -- --
emph:  0c 15 19 1e | 0b 15 19 -- | 0e 14 -- -- | 0d -- -- --
```

**Byte-for-byte identical to our `edp_swing_hbr2_hbr3` / `edp_pre_emp_hbr2_hbr3`.**
(Firmware stores `0x0000` where Linux stores `0xff` for the invalid combos.)

### The write path

```
x8 = 0xc2000 + (dev == 4 ? 0x3000 : 0) + 0x204      ; eDP TX0 block + 4
str w10, [base + x8        ]   ; emphasis -> TX0 + 0x04
str w11, [base + x8 + 0x010]   ; swing    -> TX0 + 0x14
str w10, [base + x8 + 0x400]   ; emphasis -> TX1 + 0x04
str w11, [base + x8 + 0x410]   ; swing    -> TX1 + 0x14
```

Both values clamped to `0x1f`. **No MUX_EN bit. No latch, re-arm, or follow-up write.**
That is exactly what `qcom_edp_set_voltages()` does.

### Bonus data recovered

- **v8 SSC table** at `0x547a6`: 9 rates × 5 bytes
  `{ADJ_PER1=0x00, PER1=0x6b, PER2=0x02, STEP_SIZE1, STEP_SIZE2}`, step sizes
  `0x0192, 0x01ad, 0x01e2, 0x0192, 0x01e2, 0x01ad, 0x0218, 0x024e, 0x0192`.
- A **percent-scale knob** applied to swing and emphasis before the write
  (`[ctx+0x54]`, `[ctx+0x56]`, `(x * pct + 99) / 100`), normally 0/disabled.
- Platform config keys: `EDPVoltageSwingLevel`, `EDPPreemphasisLevel`,
  `EDPLaneVoltageLevel`, `EDPTraining`, `EDPLinkRate`, `EDPMaxLinkRate`,
  `EDPLinkRateTableMethod`, `EDPOverrideDPCDCaps/Status`, `EDPHPDActiveLow`.
  The firmware can force fixed drive levels and skip training entirely.

---

## Closed doors — do not reopen without new evidence

1. **The swing/pre-emphasis tables.** Confirmed against vendor firmware, not inferred.
2. **The register offsets `0x04`/`0x14` and the `tx1 = tx0 + 0x400` stride.** Same.
3. **A missing MUX_EN bit.** Tested on hardware (`logs/edp-muxen-*`): wrote `0x2b`/`0x3f`,
   read back `0x0b0b0b0b`/`0x1f1f1f1f` — bit 5 is not implemented. The firmware does not
   set it either.
4. **A missing latch / commit / re-arm after the write.** The firmware writes four
   registers and returns.
5. **Training pattern selection.** Panel is DPCD 1.4, `0x003=0x01` (no TPS4),
   `0x002=0xc4` (TPS3 + 4 lanes); msm picks TPS3, writes `0x102 <- 0x23`, sets
   `DP_STATE_CTRL=0x4`, and MAINLINK_READY asserts.
6. **Drive levels as the cause of the EQ failure at all.** Stock table, slammed
   `0x1f/0x1f`, and MUX_EN variants all produce a **byte-identical** sink response
   (`logs/edp-hbr2-status3` == `edp-v8swing` == `edp-test62` == `edp-muxen`).

---

## RESULT of the dump patch (`logs/edp-phywin-*`, 2026-07-24 16:38) — PHY fully exonerated

Both questions below are now **answered from hardware**, and the anomaly that motivated
them is dead.

**1. The `0x0b0b0b0b` readback was never an anomaly.** *Every* register in this PHY reads
back byte-replicated: `28282828`, `1b1b1b1b`, `6b6b6b6b`, `4f4f4f4f`, `a3a3a3a3`… That is
how the block answers a 32-bit read of an 8-bit register. The only register in the whole
window with genuine per-byte variance is `pll+0x328`.

**2. The writes land exactly where intended.** Per `set_voltages` call, five registers
change and no others:

```
win+0x404 (tx0+0x004) 0x10101010 -> 0x0c0c0c0c     emphasis
win+0x414 (tx0+0x014) 0x1f1f1f1f -> 0x0b0b0b0b     swing
win+0x804 (tx1+0x004) 0x10101010 -> 0x0c0c0c0c
win+0x814 (tx1+0x014) 0x1f1f1f1f -> 0x0b0b0b0b
win+0x328 (pll+0x328) 0x27272526 -> 0x09080908     (not ours -- see below)
```

The pre-write values `0x10`/`0x1f` are exactly what `power_on` writes at `:1221-1224`, so
these *are* the TX drive registers and `tx0`/`tx1` point at the real blocks.

**3. The whole PHY is verifiably correct in silicon**, against the v8 tables:

| What | Where | Value | Expected |
|---|---|---|---|
| dec_start | `pll+0x88` | `0x4f` | v8 5400 entry ✓ |
| lock_cmp1/2 | `pll+0x80/0x84` | `0x18`/`0x15` | ✓ |
| code1/2 | `pll+0x58/0x5c` | `0x14`/`0x25` | ✓ |
| hsclk_sel | `pll+0x64` | `0x02` | ✓ |
| SSC PER1/PER2 | `pll+0xcc/0xd0` | `0x6b`/`0x02` | matches the firmware SSC table ✓ |
| TX0 vs TX1 | `+0x400` / `+0x800` | **identical** | ✓ |
| TX misc | | CLKBUF `0x0f`, DRV_LVL_OFFSET `0x10`, RESET_TSYNC `0x03`, TX_BAND `0x04`, RES_CODE `0x11`/`0x11`, BIAS_EN `0x03`, HIGHZ `0x04`, POL_INV `0x00`, LANE_MODE_1 `0x00` | all ✓ |
| DP_PHY_CFG / CFG_1 | `phy+0x10/0x14` | `0x19` / `0x0f` (4 lanes) | ✓ |
| **DP_PHY_STATUS** | `phy+0xe0` | **`0x0f`** | PHY_READY set ✓ |
| lane map | DT endpoint | `data-lanes = <0 1 2 3>` | no reversal |

**4. Question B closes too.** The firmware's SSC writes land at region `+0xc4/+0xcc/+0xd0`
and our live PLL block has `0x00/0x6b/0x02` at exactly those offsets — so the firmware's
COM block and ours are the same generation with the same offsets. glymur's COM simply grew
to `0x358` (the dump shows a duplicated mode bank at `0x1c0–0x2f0`), pushing TX from `+0x200`
out to `+0x400`. **Our DT is right.**

**5. Still unexplained, low priority:** `pll+0x328` changes on every `set_voltages` and is
the only true 32-bit/per-lane register in the block (`0x27272526`, `0x292a2b2b`,
`0x14141313`). It is probably an LDO / resistor-calibration readout disturbed by the
`com_ldo_config()` call at the top of `set_voltages` — i.e. a measurement, not a control.

**6. ASSR checked and symmetric.** `dp_ctrl.c:403` (controller `DP_CONFIGURATION_CTRL_ASSR`)
and `dp_ctrl.c:1645` (DPCD `0x10a`) are both gated on the same
`drm_dp_alternate_scrambler_reset_cap(dpcd)`, and the log shows `0x0010a AUX <- 01`. No
scrambler-seed mismatch.

### So: add the PHY to the closed list

The eDP PHY — tables, offsets, register programming, PLL, SSC, lane map, ready status — is
correct end to end and does what the vendor firmware does. **The bug is not in
`phy-qcom-edp.c` and not in the DT PHY node.** Anything that fails now fails above the PHY.

---

## Open — the two live questions

### A. Does anything we write reach a real TX register?

The anomaly that survives everything above: a 5-bit level register returns
**`0x0b0b0b0b`** for a write of `0x0b` — the byte mirrored across all four lanes of the
word. Per-TX level registers do not behave that way. Either the block at `tx0` is not a
TX lane block, or it is a shadow/broadcast alias of one.

### B. Is the firmware's PHY sub-block layout the same as ours?

| | COM/PLL | TX0 | TX1 | DP_PHY |
|---|---|---|---|---|
| **DisplayDxe HAL** | +0x000 | **+0x200** | **+0x600** | +0xa00 |
| **`glymur.dtsi:2367` / our DTB** | +0x000 (len **0x358**) | **+0x400** | **+0x800** | +0xc00 |

The vendor DTS is authoritative for glymur and the bigger `0x358` COM block explains the
push to `0x400`. So the likeliest reading is that **the DisplayDxe I analyzed is not
glymur's** — its `+0x200/+0x600` is the older x1e80100-style map. That is not yet proven:
the binary contains no absolute base constants (`0x00faa000`, `0x0ae00000`, `0x0aec2000`
are all absent — the base arrives at runtime via `0xb3988`), and only the `uefi_ext` copy
has been looked at.

**Do not conclude our DT is wrong from this table.** Settle it first (see the RE task list).

### Update (same day) — there are TWO DisplayDxe builds, and neither self-identifies

| Build | Size | md5 | Tables |
|---|---|---|---|
| `uefi_ext` (analyzed above) → `re/DisplayDxe.pe` | 741376 | `cd96187b…` | **6**, incl. `0x547e0` matching Linux |
| `uefi309` (retail 309) → `re/DisplayDxe-309.pe` | 647168 | `dc623ec8…` | **4**, at `0x495fc`, `0x4963c`, `0x49a08`, `0x49a48` — none match Linux |

Same file GUID `4138022f-…`, different builds. This weakens the identification badly:

- **The table match never proved SoC identity.** Linux uses the *same generic* eDP
  swing/emphasis tables for x1e80100, sc8280xp and glymur — a match only says "a Qualcomm
  eDP driver", not "glymur".
- The `uefi_ext` build's addressing (`0xc2000` + dev×`0x3000`, TX at `+0x200`) **is the
  x1e80100 map** (`0xaec2000` pll / `0xaec2200` tx0 / `0xaec2600` tx1 / `0xaec2a00` phy).
  So it is probably *not* glymur's, and its `+0x200` should not be held against our DT.
- Neither binary carries its own physical map: `FUN_000424cc` just copies base pointers in
  from a caller-supplied struct (`[x0]→0xb3988`, `[x0+8]→0xb3990`, …), so the base arrives
  from a platform lib/protocol at runtime.
- The `EDP*` config keys appear **only inside DisplayDxe itself** — grep of the whole
  `a16dump` finds no config blob, so they are UEFI variables/PCDs, not a data file we can read.

Conclusion: the retail `0x495fc`/`0x4963c`/`0x49a08`/`0x49a48` tables are the interesting
ones now, but the firmware route can no longer answer question B on its own. **The live
register dump can** — that is the cheaper path and the patch is built.

---

## The dump patch

`patches/glymur-edp-phywin-dump-DIAGNOSTIC.patch` — cumulative diff vs HEAD of
`drivers/phy/qualcomm/phy-qcom-edp.c`, containing three live diagnostics: the v8 swing
table, the `XXX setvolt` readback line, and the new register-window dump. The MUX_EN
experiment has been **reverted** — it is answered.

What it does:

- **Snapshot / diff.** Reads the PHY registers before the four drive-level writes and
  prints every register whose value changed after them:
  `XXX phydiff setvolt: win+0x414 (tx0+0x014) 0x0000001f -> 0x0b0b0b0b`.
  Wherever `0x0b`/`0x1f` actually appears is the real drive-level register. If the only
  things that change are the four we wrote, the writes are landing nowhere else and
  question A narrows to "is this block a TX block at all".
- **One layout dump** after `power_on` returns, with the PHY up and lanes driving
  (`XXX phydump after-power_on ...`), all-zero lines skipped.

Safety: by default it reads **only the four ranges the DT already maps** — which the
driver reads and writes anyway, so no new risk. `dbg_full=1` additionally sweeps the gaps
between sub-blocks (`0x358–0x400`, `0x528–0x800`, `0x928–0xc00`); those are unproven on
this SoC, so it is opt-in. Note `+0x200` — the address the firmware map implies for TX0 —
is **inside the declared PLL range**, so the primary hypothesis is testable in safe mode.

```bash
# build (module only)
cd ~/kernel-build/linux-src
make O=~/kernel-build/usb-out M=drivers/phy/qualcomm modules -j$(nproc)
sudo cp drivers/phy/qualcomm/phy-qcom-edp.ko \
        /lib/modules/7.1.0-glymur-clean2/kernel/drivers/phy/qualcomm/
sudo depmod -a 7.1.0-glymur-clean2

# swap it in -- the initramfs still serves the OLD module on every boot
sudo rmmod phy_qcom_edp && sudo modprobe phy_qcom_edp
diff <(cat /sys/module/phy_qcom_edp/srcversion) <(modinfo -F srcversion phy_qcom_edp) \
  && echo "running == disk"

# run (test62 DTB, msm not yet loaded)
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh phywin
# widen to the gaps only if the safe pass is inconclusive:
# sudo modprobe phy_qcom_edp dbg_full=1
```

Module params: `dbg_full` (bool, default 0), `dbg_reports` (int, default 3 — how many
set_voltages diffs to print).

---

## RE task list — Ghidra GUI on the Surface

Goal: settle question B, and check whether a *different* binary carries a glymur-layout
eDP PHY HAL. In priority order.

### 1. Find who writes the MMIO base global

This single answer settles B.

- Open `DisplayDxe.pe`, `G` → `0xb3988`.
- Right-click → **References → Show References to Address**.
- Find the write (a `str x?, [.., #0x988]`), open its function, and read where the value
  came from — a UEFI protocol, a PCD, or a platform table.
- **Report back: the physical address, or the name of the protocol/variable it comes from.**

If the base + `0xc5000` lands on `0x00faa000`, the firmware map *is* glymur's and our DT
tx0/tx1 are wrong. If it lands on `0x0aec5000` (or anything else), this DXE is for the
older part and question B closes as a red herring.

### 2. Check the other firmware tree for a second DisplayDxe

There are two extractions: `a16dump/uefi309` and `a16dump/uefi_ext`. Only `uefi_ext` was
analyzed.

- Look for file GUID **`4138022f-06c7-4f79-9c94-7e33b511a4e7`** under `uefi309`.
- If found and its md5 differs from `re/DisplayDxe.pe`, import it and go to the SetLaneDrv
  equivalent (find the string `DP_LinkSetupPreemphSwing`, follow the vtable, or just
  search for the table bytes below).
- **Report back: does its TX constant read `add x8,x8,#0x204` (TX0 at +0x200) or
  `#0x404` (TX0 at +0x400)?** That is the whole question in one instruction.

### 3. Anchor by table bytes in any binary

The fastest way to find this data in a binary you have not mapped yet — works in
`qcdxkm8480.sys` too:

- **Search → Memory → Hex**, search string:
  `0c 00 0b 00 15 00 11 00 19 00 17 00 1e 00 1c 00`
  (row 0 of the eDP HBR2/HBR3 table: emph/swing interleaved u16).
- Fallback anchors: `6b 02` for the SSC block, or the ASCII strings
  `DP_LinkSetupPreemphSwing`, `HAL_DP_1_4_1_PHY_Config`, `HAL_DP_PhyFxnsInit`.
- On a hit: **References → Show References to Address** on the table start gives you the
  selector function; from there the `str` instructions give the offsets.

### 4. Nice-to-have

- The PHY version check in `HAL_DP_PhyFxnsInit` reads `base + 0x90000` and requires
  `major=1, minor=4, step=1`. If you can find what glymur's PHY actually reports there,
  it tells us directly whether this DXE would even bind on this silicon.
- `qcdxkm8480.sys` (Windows KMD) — the 8-bit table scan found nothing, but it was only
  scanned for the *8-bit triangular* form. Re-scan with the u16-interleaved pattern in
  step 3; if the Windows driver has its own copy with a glymur layout, its offsets settle
  B independently.

Names/values to keep handy while probing: table row-0 bytes above · stride `0x58` for the
HAL vtable · SetLaneDrv at vtable `+0x18` · rate threshold literal `0x41eb0` · TX offsets
`0x04` (emph) / `0x14` (swing) / `0x400` (TX1 stride).
