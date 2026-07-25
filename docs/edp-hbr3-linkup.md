# Native eDP link-up on the ASUS Zenbook A16 (glymur) — how we got there

**Date:** 2026-07-24
**Machine:** ASUS Zenbook A16 UX3607OA, Qualcomm Snapdragon X2 Elite Extreme
("glymur", X2E94100), Fedora 44 aarch64, kernel `7.1.0-glymur-clean2`
**Panel:** Samsung/SDC **ATNA60HR07-0**, 2880×1800, eDP 1.5, 4 lanes
**Status of this document:** **confirmed and reproduced on a stock PHY driver.** The
confirmation run passed on 2026-07-24 20:28 — see [§4a](#4a-confirmation-run-passed).
The link rate alone was the fix; no drive-level change is involved and the eDP PHY
driver needs no patches at all.

---

## 1. The result

First successful native eDP link training on this machine:

```
[  414.344502] XXX setvolt: is_edp=1 rate=8100 lanes=4 v=0 p=0 -> swing=0x0b emph=0x0c
[  414.345408] link training #1 on phy 0 successful
[  414.432151] dpu_dp_aux: 0x00202 AUX -> (ret=6) 77 77 81 04 44 44
[  414.432174] link training #2 on phy 0 successful          <-- never happened before
[  414.532345] SET NEW RESOLUTION: 2880x1800@120fps
[  414.532454] pixel clock (KHz)=(709633)
[  414.532490] bpp = 30
[  414.756622] dp_video_ready
[  414.756686] mainlink READY
[  415.050836] msm_dpu ae01000.display-controller: [drm] fb0: msmdrmfb frame buffer device
```

Decoded DPCD link status, all four lanes:

| phase | `0x202` | `0x203` | ALIGN | meaning |
|---|---|---|---|---|
| CR (TPS1) | `0x11` | `0x11` | 0 | CR locked, EQ/SYM clear — as in every prior run |
| EQ retries 1–5 | `0x11` | `0x11` | 0 | the historic wall |
| **EQ final** | **`0x77`** | **`0x77`** | **1** | **CR + EQ + SYM set on L0–L3, interlane aligned** |

Negotiated link: **HBR3, 810000 (8.1 Gbps/lane), 4 lanes**, written via the legacy
selector `DPCD 0x00100 <- 0x1e`, no `0x00115` write. Stream: 2880×1800@120, 30 bpp,
709.633 MHz pixel clock, wide-bus enabled, `TU tu_size_minus1=41`.

Captured in the bring-up logs as `edp-hbr3-RESULT.log` / `edp-hbr3-bind.log` (not published here — see §5).

---

## 2. Three bugs, peeled in order

The dark panel was never one bug. Each of these fully masked the next.

### Bug 1 — dispcc `clocks[]` indexing in our DTB (kernel Oops)

`dispcc-glymur.c:25-44` resolves its parent clocks **by index** into the DT `clocks`
array. Our `test58-edp.dts` had the eDP PHY (`phy@faac00` = `mdss_dp3_phy`,
phandle `0xf7`) sitting in the **DP0** slot instead of the **DP3** slot, shifting
every DP PHY entry down one position:

```
- clocks = <0x3a 0x00 0x3b 0xf7 0x00 0xf7 0x01 0x40 0x01 ... 0x00 0x00>;   test58-edp
+ clocks = <0x3a 0x00 0x3b 0x40 0x01 ... 0x42 0x02 0xf7 0x00 0xf7 0x01 0x00>;  test62
```

`DT_DP3_PHY_PLL_LINK_CLK` therefore resolved to `phy@88e1000`, which is
`status = "disabled"` and never registers a clock provider. Chain:
`dptx3` link + pixel0 clocks **orphaned** → `best_parent_hw == NULL` →
`assigned-clock-parents` reparent fails `-EBUSY` → `clk_hw_round_rate(NULL)` at
`clk-rcg2.c:1057` → **Oops** in `msm_dp_ctrl_enable_mainlink_clocks`.

Fingerprint: `dptx0/1/2` not orphaned, only `dptx3`.

**This was our DTB's bug, not upstream's.** The fix (`dts/glymur-a16-test62-edp.dts`, exactly one
line of 7,555) restores the ordering already present in upstream `glymur.dtsi:4586`.
**Nothing to send upstream here.**

After the fix: `faac00.phy::vco_div_clk` = 1,350,000,000, `dptx3_pixel0_clk_src` =
532,224,000, `dptx3_link_clk_src` = 540,000,000. First time the pixel clock ever ran.

### Bug 2 — the eDP 1.4 `LINK_RATE_SET` path in msm is dead code (upstream)

With clocks running, training reached CR-pass / EQ-fail and stuck there. While
investigating rate selection we found a genuine, **glymur-independent upstream bug**:

`use_rate_set` is computed into `panel->link_info` (`dp_panel.c`), but every consumer
reads `link->link_params` (`dp_ctrl.c`), and:

- `msm_dp_ctrl_on_link()` (`dp_ctrl.c:2311`) only ever copied `rate` and `num_lanes`
  between the two structs;
- `msm_dp_ctrl_link_train()` (`dp_ctrl.c:1645`) builds a fresh
  `struct msm_dp_link_info link_info = {0}` and copies only `rate`, `num_lanes` and
  `capabilities`.

So `msm_dp_aux_link_configure()` **always** took the legacy `LINK_BW_SET` branch, and
`msm_dp_ctrl_link_rate_down_shift()` (`dp_ctrl.c:1487`) always saw `rate_set == 0`.

Proof from the `rateset2` run: `use_rate_set=1` is logged at caps time, yet the log
shows `0x00100 <- 0x14` written three times and **no `0x00115` write at all**.

Fix: copy `rate_set` / `use_rate_set` / `supported_rates` in `msm_dp_ctrl_on_link()`,
and the two scalars into the local `link_info` in `msm_dp_ctrl_link_train()`.

**This is upstream-reportable on its own merits.** It is also *not* what lit the
panel — see Bug 3.

### Bug 3 — 5.4 G is not a working operating point on this panel; HBR3 is

The `rateset3` run confirmed the Bug 2 fix landed correctly (`0x00100 <- 00`, then
`0x00115 <- 02`, `use_rate_set=1`, `link_rate=540000`) — **and EQ still failed
byte-identically to every previous run.** That eliminated rate *mismatch* as the
mechanism: the sink was told 8.1 G (pre-fix, by accident) and then correctly told
5.4 G, with the same failure both times.

The re-read of the firmware handoff:

- UEFI trains this panel successfully at boot and leaves behind **both**
  `LINK_BW_SET = 0x14` **and** `LINK_RATE_SET = 0x02`.
- Per eDP 1.4b, `LINK_RATE_SET` is consulted **only when `LINK_BW_SET` is 00h**.
- So the firmware's real known-good selection is the `0x14`… but `0x14` in
  `LINK_BW_SET` is 5.4 G, which we had just proven fails.

There is no reconciling read, and earlier drafts of the in-tree comment claimed one
that does not survive checking. `DP_LINK_BW_5_4` is `0x14` and `DP_LINK_BW_8_1` is
`0x1e` (`include/drm/display/drm_dp.h:583-584`), so the firmware selected **5.4 G** —
the same rate that fails for us. There is no "we read the wrong byte of the pair".

The honest statement is: the panel advertises a 5.4 G maximum in every place it is
asked, the firmware selects 5.4 G and trains successfully, **we** cannot train at
5.4 G, and 8.1 G — a rate the sink never advertises — trains first try. That is
unexplained. What made 8.1 G worth trying was simply that it was the only rate left:

- 2.7 G and 1.62 G are **dead on this PHY** — `qcom_edp_com_configure_pll_v8()`'s
  2700 and 1620 entries are byte-identical copies of the mainline **v6** table
  (`hsclk=0x3, dec_start=0x34, lock_cmp=0x07/0x07`), never re-derived for v8 silicon.
  C_READY is hard-never-ready there, proven by bumping its `readl_poll_timeout` from
  10 ms to 200 ms and watching the full 200.56 ms elapse before the same `-110`.
- 8.1 G shares one PLL entry with the proven-good 5400 case
  (`phy-qcom-edp.c:1171`, `case 5400: case 8100:`) — same VCO / lock / cal codes.
  Only `edp_phy_vco_div_cfg_v8[3]` and the post-divide differ.
- `dts/glymur-a16-test62-edp.dts` already permits it: the eDP endpoint's `link-frequencies` last
  entry is `0x1e2cc3100` = 8100000000.

Forcing `link_info->rate = 810000, rate_set = 0, use_rate_set = false` in
`msm_dp_panel_read_sink_caps()` produced the link-up above **on the first attempt**.

#### The one lead worth following: `DP_PHY_VCO_DIV`

Because 5400 and 8100 share a PLL entry, the difference between the rate that fails
and the rate that works is remarkably small. Walking
`qcom_edp_phy_power_on_v8()` for both rates, **exactly one register in the entire PHY
programming sequence differs**:

| | 5400 (fails) | 8100 (works) |
|---|---|---|
| `qcom_edp_com_configure_pll_v8()` entry | `case 5400:` | `case 8100:` — **same entry**, shared `case` label |
| `DP_PHY_VCO_DIV` | `edp_phy_vco_div_cfg_v8[2]` = **`0x02`** | `edp_phy_vco_div_cfg_v8[3]` = **`0x01`** |
| divided VCO (`pixel_freq`) | 5400000000 / 4 = **1.35 GHz** | 8100000000 / 6 = **1.35 GHz** |

Same VCO, same lock/cal codes, same swing, same lane config — one divider value apart.

That makes `edp_phy_vco_div_cfg_v8[2]` the prime suspect for the real bug. Note the
shape of the table: v4 is `{0x01, 0x01, 0x02, 0x00}` and v8 is `{0x00, 0x00, 0x02, 0x01}`.
Every v8 entry differs from v4 **except** `[2]`, the 5400 one — which is the same
"left at the old value" signature that the 2700 and 1620 entries in
`qcom_edp_com_configure_pll_v8()` carry, and those are proven broken.

This was considered and set aside earlier on the grounds that "v4 and v8 both use
`0x02` there, so it isn't stale". That reasoning is backwards — matching the older
table is the symptom, not the exoneration — and it predates the evidence that 8.1 G
works. **Worth one single-variable test** (vary `edp_phy_vco_div_cfg_v8[2]`, re-run at
5.4 G) before concluding anything, and unlike the PLL constants this is one enum-like
divider value, not a fabricated register block.

---

## 3. What was ruled out, and how

Kept here so none of it gets re-litigated. Each was closed by evidence, not reasoning
from symptoms.

| Ruled out | Method |
|---|---|
| Swing / pre-emphasis **tables** wrong | Ghidra on the UEFI `DisplayDxe`: the firmware's eDP table is byte-identical to Linux `edp_swing_hbr2_hbr3` / `edp_pre_emp_hbr2_hbr3` |
| Drive-level **write path** / TX offsets wrong | Readback in `qcom_edp_set_voltages()` echoes the written value at every `(v,p)` cell; firmware writes the same offsets (emph `TX+0x04`, swing `TX+0x14`, `TX1 = TX0+0x400`) |
| Missing `DRV_LVL_MUX_EN` (bit 5) | Wrote `0x2b`/`0x3f`, read back `0x0b`/`0x1f` — bit 5 is not implemented at these offsets on v8 |
| `tx0`/`tx1` not pointing at real TX blocks | Full PHY register-window dump: exactly 5 registers change per `set_voltages`, all in the TX blocks. The `0x0b0b0b0b` byte-replicated readback is how **every** register in this PHY reads — not an anomaly |
| "Not driving hard enough" | Slammed the requested cell to max `0x1f/0x1f` at both HBR2 and 4/2/1 lanes — EQ still failed, sink request never moved off `v=0 p=1` |
| Wrong training pattern | Panel is DPCD 1.4, `0x003=0x01` (no TPS4), `0x002=0xc4` (TPS3 + 4 lanes); msm correctly picks TPS3 (`0x102 <- 0x23`) |
| Lane mapping / `tx1`-side-only fault | All four lanes fail **symmetrically** — an asymmetric bug cannot look like this |
| PLL not locking at 5.4 G | `phyv8` (CMN_STATUS BIT7), `phyrsm` (C_READY BIT0), `phypo` (whole `power_on`) kretprobes all return `0x0` |
| eDP submode / `is_edp` false | `XXX setvolt` logs `is_edp=1`; `phy_set_mode_ext(PHY_MODE_DP, PHY_SUBMODE_EDP)` runs at `dp_display.c:773` |
| Driver diverging from vendor | Reached three times by three independent routes (DT-vs-CLO 07-12, CLO source search 07-24, UEFI RE 07-24). `phy-qcom-edp.c` is byte-identical across our build, all media kernel trees, and every CLO branch incl. `rolling_glymur_next` |
| `Unexpected DP AUX IRQ 0x01000000` | It is `BIT(24) = DP_INTR_PLL_UNLOCKED`, logged by `msm_dp_aux_isr` while `!cmd_busy`, and it fires **after** each training failure during the retry re-power. Consequence, not cause |
| SMMU faults, missing panel node, gpucc, TrustZone XPU wall | All closed earlier in bring-up |

---

## 4. Open caveats

**Do not publish this as a clean result until these are closed.**

### 4a. Confirmation run — PASSED

**Closed 2026-07-24 20:28** (`edp-hbr3-stockphy-RESULT.log`).

The run that first produced the link-up used `phy_qcom_edp` srcversion
`F83AD312C31B2AC4B10C531`, which carried two uncontrolled variables: a diagnostic
swing table with `[0][1]` slammed to `0x1f`/`0x1f` (stock: `0x11`/`0x15`), and the
C_READY `readl_poll_timeout` bumped 10 ms → 200 ms. Since the sink requested exactly
`v=0 p=1` — **the modified cell** — that run trained at maximum swing and maximum
pre-emphasis rather than stock drive.

The confirmation run restored the stock swing table (srcversion
`36C471B8B711AB40B549DED`), kept the HBR3 `msm`, and changed nothing else. It trains:

```
XXX setvolt: is_edp=1 rate=8100 lanes=4 v=0 p=1 -> swing=0x11 emph=0x15
             rb tx0: drv=0x11111111 emp=0x15151515  tx1: drv=0x11111111 emp=0x15151515
EQ-check  0x202=0x77 0x203=0x77 ALIGN=1 | L0:CR EQ SYM L1:CR EQ SYM L2:CR EQ SYM L3:CR EQ SYM
```

`0x11`/`0x15` is the stock cell, and the readback confirms it reached the TX blocks.
So **the link rate alone was the fix.** Drive levels were never part of it.

The 200 ms C_READY bump is not needed either — at 8.1 G C_READY asserts in ~1 ms,
well inside the stock 10 ms timeout:

```
phyv8 @46.249096 -> phyrsm @46.250164 = 1.07 ms
```

Both PHY diagnostics are therefore reverted; `phy-qcom-edp.c` is back to pristine v7.1
in `linux-glymur-a16` commit `daf0e0183`.

### 4b. The HBR3 change as written is not upstreamable

`link_info->rate = 810000` is a hard force in `msm_dp_panel_read_sink_caps()`. It
overrides the sink's own `SUPPORTED_LINK_RATES` and extended-cap advertisement. It
works here; it is a hack. Turning it into a patch means deciding what the general
rule is — most likely reading the firmware's `LINK_BW_SET` handoff and honouring it,
or a panel/DT quirk, not an unconditional constant.

### 4c. Not yet demonstrated

**Verified 2026-07-24:** persistence across a reboot with `msm` **not** blacklisted now
holds. `7.1.0-glymur-edp1` boots with no `modprobe.blacklist=` on the command line;
`msm` autoloads, binds, and lights the panel unattended — `fb0 = msmdrmfb`,
`card1-eDP-1` connected + enabled, `dp_aux_backlight` present, no oops or panic, and the
**stock** `phy_qcom_edp` (srcversion `D981A7A0AE1ECDA17C26A43`).
`scripts/edp-train-probe.sh` is no longer needed to bring the display up.

Still open:

- Suspend/resume.
- Whether 30 bpp is the right choice or an artifact of the HBR3 headroom
  (HBR2 ×4 = 17.28 Gbps effective vs ~15.7 Gbps needed at 8 bpc — 5.4 G was
  *sufficient* for the mode, so the mode was never the constraint).

---

## 5. Reproducing it

**Kernel:** the patches are on branch
[`glymur-edp-hbr3`](https://github.com/FixItFoundry/linux-glymur-a16/tree/glymur-edp-hbr3)
of the kernel fork. Two commits matter:

- `drm/msm/dp: make the eDP 1.4 LINK_RATE_SET path actually reachable` — Bug 2. Generic,
  not glymur-specific, and the one piece here that belongs upstream as-is.
- `drm/msm/dp: glymur: force HBR3 on the internal eDP panel` — Bug 3. A hack, see §4b.

`drivers/phy/qualcomm/phy-qcom-edp.c` is **unmodified**. Everything that was ever
patched into it during bring-up turned out to be unnecessary.

**Device tree:** [`dts/glymur-a16-test62-edp.dts`](../dts/glymur-a16-test62-edp.dts).
Relative to the previous display DTB it is a one-line change — the `dispcc` `clocks[]`
fix in §2 Bug 1.

**Cmdline:** `efi=noruntime` is mandatory (without it you get an intermittent warm reset
at fbcon commit), `kvm-arm.mode=protected` must stay **on**, and keep `cma=128M` and
`clk_ignore_unused pd_ignore_unused`. Keep the `ps8830`/`ps883x` retimers disabled —
they crash on bind under pKVM and are irrelevant to internal eDP.

The full bring-up logs, the UEFI `DisplayDxe` reverse-engineering write-up, and the
per-experiment result files live in the maintainer's working tree and are not published
here; ask if you need a specific one.
