# Contributing / How you can help

This is a solo, self-taught bring-up of Linux on the ASUS Zenbook A16 (Snapdragon X2
Elite Extreme, `glymur` / `sm8750`). It has gotten a long way by trial, bisection, and
reverse-engineering the Windows drivers — but the two hardest pieces (native display and
GPU) really need people who know the Qualcomm DRM / clock / SMMU stack.

**If you have that expertise, the project needs two things: validation and patches.**

## 1. Validation — sanity-check what's here

I'd especially value a second opinion on:

- **The eDP `-110` link-training failure** (`docs/display-bringup-findings.md`,
  `docs/edp-enable-findings.md`). `msm`/DPU binds, reads the Samsung ATNA60HR07 EDID,
  then link training times out. Is this a DP PHY init-order problem, a panel
  power-sequencing/AUX timing issue, or something in the simplefb handoff? The current
  best theory is that it is **not** a firmware/VMID wall (see the 2026-07-15 re-framing).
- **The `gpucc` gap** (`docs/gpu-re/`). The GPU clock controller for `sm8750` is missing
  from mainline; the RE'd register candidates are in `docs/gpu-re/gpucc-clock-registers.md`.
  Is a minimal `gpucc` shim enough to power the block, or is this blocked until Qualcomm
  upstreams it?
- **The MDSS-enabled + `msm`-loaded Wi-Fi regression.** Enabling the display driver kills
  ath12k/PCIe at boot. Shared power domain? NoC vote? SMMU context? This is the biggest
  mystery blocking a display-capable daily driver.
- **The SPMI PMIC-arb probe failure — gates cooling.** Secondary PMICs fail to probe over SPMI
  (`pmic-spmi … error -5`; `pmic_arb_wait_for_done: transaction failed`), which blocks **both**
  `qcom-spmi-temp-alarm` and the PMIC PWM (`pmh0101` / `pm8350c`) that drives the **fan** — so
  `/sys/class/pwm` stays empty. With no DT `cooling-maps` and no Linux fan control, the SoC hits
  its 115 °C `critical` trip and protectively shuts down under load (an interim userspace
  freq-throttle guard mitigates it). Fixing the SPMI arbiter probe likely unlocks the temp alarm,
  the fan, and real thermal throttling in one shot. See `docs/ROADMAP.md`. (Distinct from the eDP
  `-110`; this one is `-5`.)

## 2. Patches

- Please target **mainline Linux v7.1** — the known-good base. **7.2 / linux-next broke
  the chain** (a regression in the 7.2 cycle), so PRs against newer trees can't be tested
  against the working build yet. Bisecting *what* broke in 7.2 would itself be a huge help.
- DTS changes: reference `dts/glymur-a16-test55.dts` (the daily driver). Diagnostic
  display DTBs (`test47`, `test58`) are separate.
- Keep kernel-derived files `SPDX-License-Identifier: GPL-2.0-only`.

## Reporting

Open an issue with: your exact hardware (`UX3607OA` variant), kernel + DTB build, the boot
cmdline, and a `dmesg` (netconsole/serial preferred for crashes — see
`docs/analysis/` for the netconsole capture setup). Please note whether you reproduced on
`test55` (daily) or a diagnostic DTB.

## What this project is NOT

- Not affiliated with ASUS or Qualcomm.
- Not redistributing proprietary firmware or decompiled Windows drivers — only the
  *findings* derived from them (addresses, StreamIDs, register maps). See `firmware/README.md`.

Thank you — even a "you're wrong about X, here's why" is valuable.
