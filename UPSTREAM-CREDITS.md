# Upstream credits

This project stands on work done by the upstream Linux and Qualcomm developers who brought
up the Snapdragon X2 Elite ("Glymur") platform. **Anything in this tree that originates
upstream is credited here, with its author and the patch it came from.** Where we carry a
patch before it is merged, we carry it unmodified and attributed; where we changed it, that
is stated explicitly.

If you are one of the people below and would like an entry corrected, removed, or worded
differently, please open an issue — we will fix it immediately.

## Adopted into this tree

| What | Author | Upstream patch | Status here |
|---|---|---|---|
| **ASUS Zenbook A16 (UX3607OA) keyboard support** — I2C-HID `0B05:4B42`, vendor usages 0x85 → `KEY_CAMERA`, 0x86 → `KEY_PROG1`, 0x5f → `KEY_PROG2`, and `QUIRK_FILTER_CAMERA_COMPANION` for the camera-toggle companion byte that otherwise dims the panel | **Konrad Dybcio** \<konrad.dybcio@oss.qualcomm.com\> | `HID: asus: support the Zenbook A16 (UX3607OA) keyboard`, 2026-07-24, msg-id `20260724-topic-asus_keyboard-v1-1-a746ff8f77b2@oss.qualcomm.com` | **Adopted verbatim**, 2026-07-27. It replaced our own earlier hand-rolled mapping, which was wrong — we had 0x85 as `KEY_KBDILLUMTOGGLE` and it never worked on the hardware. Konrad's mapping is confirmed correct on this machine. |
| **eDP HPD pin muxing** — GPIO119 → `edp0_hot` on `&mdss_dp3` | **Konrad Dybcio** | `arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, 2026-07-21, msg-id `20260721-topic-a16_submission-v1-2-8ea213130d05@oss.qualcomm.com` | **Idea adopted** in our `test70` DTB. Our device tree is a separate, vendor-derived lineage, so we could not take his file directly; we reproduced this one property on ours. |

| **The ASUS Zenbook A16 (UX3607OA) device tree itself** — the entire board DTS our merged tree is built on: `gpio-reserved-ranges`, regulators, the WCN/`pcie-m2-e-connector` wiring, gpio-keys/lid, `&gpu`/`&gmu`/`&remoteproc_cdsp`/`&remoteproc_soccp` enablement, USB/PHY and display plumbing | **Konrad Dybcio** \<konrad.dybcio@oss.qualcomm.com\> | `arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, 2026-07-21, msg-id `20260721-topic-a16_submission-v1-2-8ea213130d05@oss.qualcomm.com` (reviewed by **Dmitry Baryshkov** and **Abel Vesa**), **still unmerged** | **Adopted as the base of our merged tree**, 2026-07-29, as `glymur-asus-zenbook-a16-ux3607oa-merged.dts`. His file is carried essentially intact; our deltas are additive and each is commented in-place: Wi-Fi via `qcom,wcn7850-pmu` instead of the `pcie-m2-e-connector`+pwrseq path (which does not bind on 7.2-rc3), `regulator-always-on` on the WCN and eDP PHY rails, the UCSI `usb-role-switch` deletion, an inline `pcie4_port0_ep` (the label does not exist in 7.2-rc3 `glymur.dtsi`), and a `soccp_glink_edge` node. **The structure, the pin map and the board knowledge are his.** |

## Referenced, not yet adopted

| What | Author | Upstream patch | Notes |
|---|---|---|---|
| **`INT2_GDSC` on MDSS** — Glymur's MDSS has two power domains, `CORE_GDSC` and `CORE_INT2_GDSC` (the latter powering the VIG2/VIG3/DMA5/DMA6 SSPP blocks); the MDSS driver only ever attached one | Series posted 2026-07-20, msg-id base `20260720-msm_gdsc2-v1-0-4687866d6cb0@oss.qualcomm.com` — `dt-bindings: display: msm: Allow two MDSS power domains` / `drm/msm/mdss: Enable INT2_GDSC alongside CORE_GDSC` / `arm64: dts: qcom: Add INT2_GDSC to MDSS on Kaanapali and Glymur` | Under evaluation as a candidate for our display-teardown crash. |
| **Glymur DP PHY PLL programming** | posted 2026-07-21, msg-id `20260721-glymur-phy-conf-v1-1-7c8909552c5e@oss.qualcomm.com` | `phy: qualcomm: qmp-combo: update DP PHY PLL programming on Glymur` — the USB-C combo PHY, not the eDP PHY, but same platform. |
| **Glymur display support** (MDSS / DPU / DP driver + bindings) | **Abel Vesa** \<abel.vesa@oss.qualcomm.com\> | `drm/msm: Add display support for Glymur platform`, Sept–Oct 2025 | The basis for everything we do on the display. Already in our v7.1 tree. |
| **Glymur eDP/DP PHY v8 support** | **Abel Vesa**, applied by **Vinod Koul** | `phy: qcom: edp: Add support for Glymur platform` (v6), Dec 2025 / Jan 2026 | Already in our v7.1 tree; `qcom,glymur-dp-phy`. |
| **ASUS Zenbook A14 (x1e/x1p) support** | **Alex Vinarskis** \<alex.vinarskis@gmail.com\> | merged ~6.15/6.18; out-of-tree work at `github.com/alexVinarskis/linux-x1e80100-zenbook-a14` | Our closest working reference for a functioning eDP + suspend path on this SoC family. |
| Reviews on the A16 device tree | **Dmitry Baryshkov**, **Abel Vesa** | — | Reviewed-by on Konrad's A16 series. |

## Our own contributions, for contrast

Kept separate so the provenance stays clean:

- **`clk: qcom: gdsc: fix genpd teardown`** — a real upstream bug: `gdsc_init()` calls
  `pm_genpd_init()` but nothing called `pm_genpd_remove()`, so unloading any Qualcomm clock
  controller left the global `gpd_list` pointing into freed module memory. Fixed plus two
  error paths. Pushed to `linux-glymur-a16@glymur-edp-hbr3`; patch in
  `patches/glymur-gdsc-genpd-teardown-UPSTREAM.patch`.
- **eDP HBR3 link-up** and the `LINK_RATE_SET` plumbing fix beside it.
- ADSP firmware boot ordering, lid switch (TLMM 92 from the WoA DSDT), the UCSI
  `usb-role-switch` fix, USB-C DisplayPort alt-mode.

## Policy

When we merge upstream work into this tree we:

1. credit the author by name and email in the table above,
2. record the patch subject and message-id so the original is findable,
3. state whether we took it verbatim or adapted it, and
4. never present adopted work as our own in the README, commit messages, or any upstream
   posting.

Raw copies of the patches we have adopted or are evaluating live in `upstream/patches/`,
kept in their original mbox form with authorship headers intact.
