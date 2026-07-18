# Plan: Get Native eDP Working on ASUS Zenbook A16 (Glymur / sm8750) under pKVM

## Context & Current State

- **Machine**: ASUS Zenbook A16 UX3607OA — SoC **Glymur** (`qcom,glymur`, X2 Elite Extreme). Running **pKVM** (protected VM mode). Panel: `samsung,atna60cl08` (eDP, fallback `atna33xc20`).
- **Boot kernel**: `7.1.0-glymur-full` (`v7.1-1-gab9386a9c`), built from WSL `~/glymur-build/linux` (Fedora-44 WSL).
- **Stable daily driver**: grub `dt-test47` -> `/boot/glymur/glymur-a16-test55.dtb` (mdss/dispcc **disabled**, no ps8830 nodes). Battery, USB-C data, audio all work. No crashes.
- **What we proved** (prior work): enabling `mdss`/`dispcc` in the DTB causes a **hard SoC reset** during the simplefb atomic commit at 2880x1800 — regardless of (a) pKVM on/off (test61 `kvm-arm.mode=none` still crashed), (b) display PD votes stripped (test64), (c) USB-C ps8830 retimers stripped (test65). So the crash is **not** a DTB-wiring/pKVM/retimer bug in isolation — it is triggered the instant MDSS/dispcc are enabled with the current (incomplete) DTS.

## Key Discovery from This Research

- **The kernel already has the Glymur/SM8750 display driver.** `msm_mdss.c` contains both `qcom,glymur-mdss` and `qcom,sm8750-mdss` (both `data_57k`). The `samsung,atna33xc20` panel driver is built (`panel-samsung-atna33xc20.ko`).
- **The DTS does NOT enable it.** In `glymur.dtsi`, the `mdss@ae00000` node **and** `mdss_dp3_phy` are `status = "disabled"`. There is **no `&mdss_dp3` eDP panel wiring, no `aux-bus` panel node, no `vreg_edp_3p3` regulator (tlmm 70), no `enable-gpios = <&tlmm 18>`** — all of which the upstream Glymur CRD enable provides.
- **Upstream already solved this.** LKML (2025–2026) has the exact enable we need:
  - **Abel Vesa** `arm64: dts: qcom: glymur: Enable SoC-wise display and eDP panel on CRD` — adds `glymur-crd.dts` eDP + ~466 lines to `glymur.dtsi`: `&mdss`/`&mdss_dp3`/`&mdss_dp3_phy` `okay`, `aux-bus` panel `samsung,atna60cl08`, `enable-gpios = <&tlmm 18>`, `vreg_edp_3p3` on `tlmm 70`. **This matches our A16 gpio18/gpio70 wiring almost 1:1.**
  - **Krzysztof Kozlowski** `arm64: dts: qcom: sm8750: Enable display` (v5, 2026-03) — adds MDSS/dispcc to `sm8750.dtsi` (432 lines). Glymur MDSS is "SM8750 + minor bump", so this is the sibling reference.
  - **Abel Vesa** `drm/msm: Add display support for Glymur platform` (v3, 2025-10) — the DRM driver (DPU/DP/MDSS `qcom,glymur-*`). **Already in our 7.1.0 kernel** (confirmed above).
  - **Critical gotcha (X1E/X1P eDP PHY v6 NULL-deref)**: the eDP/combo PHY `com_clk_fwd_cfg` was wired for v4 ops but NULL in v6, causing an oops/hang during eDP PHY init on Hamoa/Purwa laptops. Glymur uses the same 7nm v6 PHY. If our `dsi_phy_7nm.c` lacks the v6 `com_clk_fwd_cfg` assignment, enabling eDP PHY will **fault** — under pKVM that fault becomes the hard reset we observe. MUST verify/fix.

## Conclusion

The hard reset is almost certainly caused by **enabling MDSS/dispcc in the DTB while the eDP subsystem (PHY/regulator/gpio/panel) is not fully and correctly described**, plus possibly the **eDP PHY v6 NULL-ops bug**. The fix is to **port the upstream Glymur/CRD eDP DTS enable into our `glymur.dtsi`/board DTS and verify the eDP PHY v6 ops**, then rebuild only the DTB (and, if needed, the `msm`/PHY modules). No full kernel rebase required — our 7.1.0 already carries the Glymur DRM driver.

---

## Plan

### Step 0 — Pull upstream reference patches (read-only inspect first)
- In WSL `~/glymur-build`, fetch the LKML patches to a working dir (do NOT apply yet):
  - Abel Vesa "glymur: Enable SoC-wise display and eDP panel on CRD" (latest v7) — from `lore.kernel.org`/`spinics.net`.
  - Krzysztof Kozlowski "sm8750: Enable display" (v5) — reference for MDSS/dispcc node shape.
  - Abel Vesa "drm/msm: Add display support for Glymur" — confirm already present; note any DTS-binding deps.
- Extract the DTS hunks only (the `&mdss`, `&mdss_dp3`, `&mdss_dp3_phy`, `aux-bus` panel, `vreg_edp_3p3`, `enable-gpios`).

### Step 1 — Verify eDP PHY v6 ops fix in our tree
- In WSL: inspect `drivers/gpu/drm/msm/dsi/phy/dsi_phy_7nm.c` for the **v6** ops struct (`dsi_phy_7nm_v6_*`) and confirm `com_clk_fwd_cfg` / `com_clk_fwd_cfg0` is **non-NULL** for v6 (the X1E/X1P NULL-deref fix).
- If NULL/missing -> cherry-pick the PHY v6 `com_clk_fwd_cfg` fix from upstream (`drm/msm/dsi/phy: ... fix com_clk_fwd_cfg for v6`). This requires rebuilding `msm.ko` (or just the phy module).

### Step 2 — Build the A16 eDP-enable DTS (incremental, safe)
Create a **new** DTS overlay/board file `glymur-a16-edp.dts` that:
- `#include`s our working `glymur-a16-test55` base (the stable one with battery/USB/audio).
- Enables `&mdss`, `&mdss_dp3`, `&mdss_dp3_phy` (`status = "okay"`) **using the exact node labels/addresses already in `glymur.dtsi`** (no redefinition — only `status` flips + `&mdss_dp3` port/aux-bus panel + vreg + enable-gpio).
- Adds `aux-bus` panel `compatible = "samsung,atna60cl08"` (fallback `atna33xc20`), `enable-gpios = <&tlmm 18 GPIO_ACTIVE_HIGH>`, `vreg_edp_3p3` regulator on `tlmm 70`.
- **Keeps ps8830 retimers DISABLED** (they crash on bind under pKVM — proven). USB-C SS can stay direct or use nxp redrivers as in test55.
- Compile with `dtc` in WSL; verify `ps8830` count = 0, mdss/dispcc `status=okay`, dtb size sane.

### Step 3 — Deploy to a NEW grub entry (never touch dt-test47)
- Copy compiled `glymur-a16-edp.dtb` -> `/boot/glymur/`.
- Add a NEW `dt-edp` menuentry in `/boot/grub/grub.cfg` (do NOT modify `dt-test47`; keep it default). Pattern matches existing entries.
- Keep `dt-test65` already removed.

### Step 4 — Test boot & capture
- Boot `dt-edp`. Watch for: (a) clean eDP bring-up at 2880x1800, or (b) the same hard reset.
- If hard reset persists -> the cause is the eDP PHY v6 ops (Step 1) or pKVM MMIO protection on the display block. Then: try `kvm-arm.mode=none` with the new DTS (already known to crash pre-fix, but retest post-PHY-fix); if still reset, the PHY/vreg wiring is still incomplete — diff our DTS against Kozlowski sm8750 + Vesa CRD line-by-line.
- If it boots but no panel -> check `dmesg | grep msm|dp|edp`; likely missing `aux-bus`/regulator or backlight (`backlight` node for brightness).

### Step 5 — Brightness / backlight (only after eDP works)
- Add `backlight` node (typically `&pmc8380_gpios` + pwm or `backlight` referencing the panel) once the panel is live. Blocked until Step 4 succeeds.

---

## Risks / Watch-items
- **pKVM may still block display MMIO** even with correct DTS. Mitigation: `kvm-arm.mode=none` test post-PHY-fix; if it works only without pKVM, that's a firmware/pKVM limitation, not a DTB bug.
- **Wireless-kill under display+msm**: unconfirmed; test WiFi after eDP bring-up.
- **ps8830/ps883x bind crash**: keep retimers disabled in the eDP DTS; they are irrelevant to internal eDP.
- **Do not touch `dt-test47` or `glymur-a16-test55.dtb`** — they are the known-good fallback.

## Files
- Source DTS: `~/glymur-build/linux/arch/arm64/boot/dts/qcom/glymur.dtsi` (mdss@4159 disabled, dp3_phy@2366 disabled), `glymur-crd.dts` (reference enable).
- Build inputs: `~/glymur-build/test55-patched.dts`, `patch_dt_full.py`.
- Deploy: `/boot/glymur/glymur-a16-edp.dtb` (new), `/boot/grub/grub.cfg` (new entry only).
- Driver: `~/glymur-build/linux/drivers/gpu/drm/msm/msm_mdss.c` (has glymur/sm8750), `dsi/phy/dsi_phy_7nm.c` (v6 ops check), `panel/panel-samsung-atna33xc20.ko` (built).

## Verification
- `dtc` compiles with exit 0; `ps8830` count 0; mdss/dispcc `okay`.
- Boot `dt-edp` -> either clean 2880x1800 eDP, or reproduce reset (then iterate on PHY v6 ops / vreg / gpio).
- Confirm `dt-test47` still boots unchanged (sanity fallback).

---

## Step 0 / Step 1 RESULTS (research + verification done)

**The hard reset is NOT a DTB/driver gap. Everything upstream provides already exists in our 7.1.0 tree.**

### What was gathered (in `~/glymur-build/lkml-display/`)
- `glymur-crd.dts` (upstream CRD eDP enable, 321 lines) — reference for panel/vreg/pinctrl.
- `glymur.dtsi`, `sm8750.dtsi` (torvalds master) — for diffing.
- `glymur-crd.dtsi` (OUR tree, Jul 14) — defines all PMIC regulators + pinctrl (this is what our flattened base already includes).
- `phy-qcom-edp.c` (torvalds master) — for driver diff.

### Verified present in our tree (no changes needed)
1. **Glymur DRM driver**: `msm_mdss.c` has `qcom,glymur-mdss` AND `qcom,sm8750-mdss` -> `data_57k`.
2. **Glymur eDP PHY driver**: `phy-qcom-edp.c` has `qcom,glymur-dp-phy` -> `glymur_phy_cfg`. **Byte-identical to torvalds master** (same line numbers 1084/1485).
3. **Full eDP DTS wiring already in our base** (`test55-patched.dts`):
   - `mdss@ae00000` = `disabled` (this is the only switch).
   - `mdss_dp3` (`displayport-controller@af6c000`) = `okay`, with `aux-bus` panel `samsung,atna60cl08`,`atna33xc20`.
   - `mdss_dp3_phy` (`qcom,glymur-dp-phy` @1918) has `vdda-phy-supply` + `vdda-pll-supply` (resolve to `vreg_l2f_e1_0p83`/`vreg_l4f_e1_1p08`).
   - `vreg_edp_3p3` regulator (gpio70), `edp-bl-en` (gpio18) pinctrl, `edp_3v3` regulator all present.
   - All PMIC regulators (`vreg_l2f_e1_0p83`, etc.) defined via `glymur-crd.dtsi` content.
4. **`glymur.dtsi` diff vs torvalds master**: only `#cooling-cells` + newer clock bindings (`gpucc`/`videocc`/`kaanapali-gxclkctl`) differ. **Display subtree is identical** (0 display-relevant diff lines; only 2 new `status="disabled"` in master).

### Conclusion
Enabling `&mdss` (as test65 did) is the only action, and it hard-resets the SoC. Since:
- the DTB is complete,
- the drivers match upstream master,
- it crashes under BOTH pKVM (`kvm-arm.mode=none`, test61) and stock,
- it is independent of retimers (test65 stripped ps8830) and PD votes (test64),

the reset is triggered at the **hardware/firmware/runtime** level the instant MDSS/dispcc clocks+resets are enabled — NOT by missing DTS content. Likely causes, in order:
1. A fault in the baked-in 7.1 Glymur display driver on enable (Abel Vesa's series iterated v3->v7 through 2025-26; our 7.1 may predate fixes).
2. Firmware/pKVM not granting the MDSS power/clock/reset vote -> synchronous abort on register touch -> SoC reset.
3. Board power sequencing the DTB describes but the hardware can't deliver.

### Corrected next steps (supersedes old Step 2 "add missing wiring")
- **Step 1b (REQUIRED first)**: Capture the *actual* fault instead of the opaque hard reset. Build/use a kernel with `earlycon`, `ARM64_PANIC_ON_*` off, and `msm`/`phy` debug, OR attach a serial/UART to read the synchronous abort that precedes the reset. Without the real error, DTB iteration is blind (we already proved DTB completeness).
- **Step 2 (minimal DTB)**: just flip `&mdss` (and `&dispcc` if separate) to `okay` in a NEW `glymur-a16-edp.dts` based on `test55-patched.dts` — no need to add panel/vreg/pinctrl (already there). Keep ps8830 disabled. New grub entry `dt-edp`, never touch `dt-test47`.
- **Step 3 (if fault captured)**: if it's a driver bug, cherry-pick the later Glymur display fixes from torvalds/master into `~/glymur-build/linux` and rebuild `msm.ko` + `phy-qcom-edp.ko`. If it's a firmware/MMIO grant issue, the path is firmware/pKVM (may be unfixable from DTB).
- Backlight/brightness stays blocked until eDP is live.

### Files (updated)
- Reference: `~/glymur-build/lkml-display/{glymur-crd.dts,glymur.dtsi,sm8750.dtsi,glymur-crd.dtsi,edp_master.c}`.
- Base build input: `~/glymur-build/test55-patched.dts` (flattened; already eDP-complete except `mdss` disabled), `patch_dt_full.py`.
- Deploy: `/boot/glymur/glymur-a16-edp.dtb` (new), `/boot/grub/grub.cfg` (new entry only).
- Drivers verified: `linux/drivers/gpu/drm/msm/msm_mdss.c`, `linux/drivers/phy/qualcomm/phy-qcom-edp.c` (glymur support present & current).

---

## Windows ACPI / .inf ANALYSIS (from the box's Win11 partition)

Sources in project dir: `acpi_dump/` (DSDT.dsl + raw .dat), `Exported_Drivers/` (ASUS + Qualcomm .inf), `SOCPackage_forWebSite_Qualcomm_Z_V1.300.8800.0_49531/`.

### Display ACPI devices (from DSDT.dsl)
- **`\_SB.QCOM0F36`** (line 82126) = the **MDSS/GFX** device. `GHID`, memory `0x0AE00000` (len 0x200000) + `0x03D00000`, `0x0B290000`, `0x0AA00000`, `0x15200000` — **exactly matches** our DTB `mdss@ae00000` split into mdss/dp/phy. Interrupts 0x73/0x1E1/0x1E0/0x3C8..3C5/0x14C/0x150/0x14D/0xCE/0x303.
- **`\_SB.QCOM0FF5`** (line 82330) = the **eDP/DP controller** — describes the SAME MDSS register space (it's the ACPI "display" face of the same HW).
- **Both** have `_DEP` → `\ _SB.TREE` (clock tree), `\ _SB.SCM0` (secure/trustzone SCM), `\ _SB.RPEN`, `\ _SB.PILC`, `\ _SB.IMM0`, `\ _SB.PEP0`. **This means enabling display requires secure-world clock/power coordination.**
- **`\_SB.BCL1`** (`QCOM0F77`, line 2012) = **backlight control device**, `_DEP` → `\ _SB.PMIC`. The Windows driver `qcfgbcl8480.inf` installs `FGBCL` for `ACPI\QCOM0F77` — a **PMIC-based backlight** (Fine-Grain Battery Current Limit / PMIC WLED), NOT a simple GPIO PWM. So brightness is PMIC-driven and gated behind the PMIC, independent of the eDP enable.

### Clock-reference dependency (confirms DTB completeness)
- DSDT lists `tcsr_edp_clkref_en` as a display clock dependency (lines 7239/7554/7878).
- Our `test55-patched.dts` dp3_phy (`qcom,glymur-dp-phy`) **does** carry it: `clocks = <0xae 0x37 0xae 0x06 0x2a 0x00>` where `0x2a 0x00` = tcsr phandle + `TCSR_EDP_CLKREF_EN`. (Earlier "0 hits" was a false negative — flattened DTB uses phandles, not the symbol string.) So the EDP ref clock IS wired. No gap.

### Windows display driver IDs (from `qcdxext_crd8480.inf`)
- Display extension matches `ACPI\VEN_QCOM&DEV_0F36&SUBSYS_xxxx1043` and `DEV_0FF5&SUBSYS_xxxx1043` — **1043 = ASUS**. Subsystem IDs seen: `16841043`, `16D41043`, `16941043`, `36691043` → our **ASUS Zenbook A16** family. The CRD-generic panel cfg overrides section is empty; actual panel/EDID lives in `qcdxkmext8480_CRD.bin`.
- `qcdx8480.inf` = the **Display adapter** (Qualcomm "qcdx11/12" = Adreno/Glymur WDDM). `qchwnled8480.inf` = HWNLED (likely chassis LED, not panel backlight).

### What this ADDS to the conclusion
- The ACPI firmware models display enable as requiring **`\_SB.TREE` (clock tree) + `\_SB.SCM0` (trustzone SCM) coordination**. Under pKVM the guest kernel may not be permitted to perform these secure clock/power votes → the MDSS enable touches a register the hypervisor/secure-world rejects → **synchronous abort → SoC hard reset**. This is consistent with: crash under BOTH pKVM and `kvm-arm.mode=none` (the block is gated by secure firmware, not just the pKVM shim), and independent of DTB content (already complete).
- **Backlight is a separate PMIC device (`QCOM0F77`/FGBCL)** — it will need its own Linux driver (`qcom,fg-bcl` or similar) but is NOT the cause of the reset.

### Refined likely cause (ordered)
1. **Secure-world / firmware not granting the MDSS clock+power+reset vote** under this boot (pKVM or not) → sync abort → reset. (Strongest, given ACPI `_DEP` on TREE/SCM0 + crash in both VM modes.)
2. A latent bug in the baked-in 7.1 Glymur display driver on enable (upstream iterated v3→v7 through 2025-26).
3. Board power sequencing the DTB describes but HW can't deliver.

### Next step (unchanged, now better justified)
- **Step 1b: capture the real fault.** Need early serial/UART or a debug kernel (`earlycon`, `msm`/`phy`/`clk` debug, panic-on-oops ON, `ARM64_PANIC_ON_UNDEFINED` etc.) to read the synchronous abort that precedes the reset. Without it we're blind. Then either (a) cherry-pick later Glymur display fixes into `~/glymur-build/linux`, or (b) conclude it's a firmware/secure-gate limitation.
- For backlight later: pursue the `QCOM0F77` PMIC FGBCL driver (`qcom,fg-bcl` / `qcom,pmic-bcl`), separate from eDP enable.

### Files (added)
- `acpi_dump/dsdt.dsl` + `*.dat` (ACPI tables from Win11 partition).
- `Exported_Drivers/qcdx8480.inf` (display adapter), `qcdxext_crd8480.inf` (panel/ext, ASUS SUBSYS IDs), `qcfgbcl8480.inf` (backlight `QCOM0F77`/FGBCL), `qchwnled8480.inf`.
- `SOCPackage_forWebSite_Qualcomm_Z_V1.300.8800.0_49531/` (Qualcomm BSP + BIOS + `qcdxkmext8480_CRD.bin` panel config).
