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
