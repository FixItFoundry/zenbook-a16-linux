# Things tried — including the dead-ends

A curated log of approaches that were attempted and did **not** pan out, so contributors
don't burn time re-running known-bad experiments. The blow-by-blow is in
[`DTB_CHANGELOG.md`](DTB_CHANGELOG.md); this is the short "already tried, don't bother" list.

## Display / eDP

| Attempt | Result | Takeaway |
|---|---|---|
| **test58** — `x1e80100-asus-vivobook-s15` base with `mdss`/`dispcc`/`mdss_dp3` = okay | **FAILED** — did not bring up native display | Recorded as tried; revisit after the `-110` link-training root cause is understood. |
| `video=simplefb:off` (drop simplefb to "free" the panel) | Hard warm reset | Removing simplefb drops the MDSS power domain during handoff → reset. Keep simplefb alive. |
| Forced `video=eDP-1:1920x1080@60` (lower link rate via modeset) | Hard warm reset | Forcing a resolution triggers a full modeset → MDSS GDSC power-cycle → reset. Don't force `video=`. |
| **msm_gem CMA rewrite** (bypass SMMU with contiguous buffers) | Abandoned | Solved the wrong problem — SMMU translation was never the fault; buffers already map fine. The `-110` is a DP PHY / link-training issue. |
| "TrustZone XPU / secure-VMID wall" theory | Superseded / misdiagnosis | WoA ACPI (IORT/DSDT/SDEV) shows the display path is normally clock-gated with **no** secure VMID gate. The real blocker is eDP link training. |

**Still the open target:** eDP `-110` link training — DP PHY init order, panel power
sequencing (`enable-gpios` + `edp_3v3`), and AUX retry/timing. See
[`display-bringup-findings.md`](display-bringup-findings.md) and
[`edp-enable-findings.md`](edp-enable-findings.md).

## GPU

| Attempt | Result | Takeaway |
|---|---|---|
| Graft hamoa (x1e80100) GPU + GMU + IOMMU nodes into glymur DT | Immediate **SError** at ~0.3 s | Nodes probe, driver reads ID registers on an **unpowered** block → hardware exception. |
| Same graft with `clocks`/`power-domains` stripped (to compile) | Same SError | Stripping the clocks is exactly why the block is unpowered — this is the `gpucc` gap, not a fix. |
| Emulate a "Gunyah / hypervisor handshake" to unlock the GPU | Dead-end | The GPU is driven **natively** by Windows in the primary VM (`qcdxkm8480.sys` WDDM), not behind a Gunyah VMID. Nothing to emulate. |

**Root cause:** the **GPU Clock Controller (`gpucc`) for `sm8750` is missing from mainline.**
Until it exists (or a minimal shim powers the block), the Adreno node can't be safely probed.
RE'd register candidates: [`gpu-re/gpucc-clock-registers.md`](gpu-re/gpucc-clock-registers.md).

## Kernel base

| Attempt | Result | Takeaway |
|---|---|---|
| Build on **7.2 / linux-next** | Broke the working chain | A regression somewhere in the 7.2 cycle broke glymur bring-up. Stay on **v7.1**. Bisecting the 7.2 breakage is a wanted contribution. |

## Input (historical, now resolved — kept for reference)

| Attempt | Result | Takeaway |
|---|---|---|
| Keyboard at `0x3a` on `i2c@b94000` (from another laptop's map) | `-ENXIO`, nothing ACKs | Wrong bus. DSDT ground truth: keyboard = `0x15` on `i2c@88c000` (the EC bus), 400 kHz. |
| Drop EC I2C bus clock to 100 kHz to "give the EC time" | Regressed — GENI `Timeout abort_m_cmd` | Lower speed is worse; 400 kHz is correct. The real fix was restoring the keyboard's power/pinctrl bindings. |
