# Upstream credits

This project stands on work done by upstream Linux and Qualcomm developers bringing up the
Snapdragon X2 Elite ("Glymur") platform. Anything here that originates upstream is credited
with its author and source patch.

If you're one of the people below and want an entry corrected, removed, or reworded, open an
issue — we'll fix it immediately.

## Adopted into this tree

The [2026-09-19 RC3 integration](patches/rc3-20260919/README.md) preserves author,
review and source-link trailers in each exported patch. Its ordered commit list
is [recorded separately](patches/rc3-20260919/commits.txt); local compatibility
and experimental patches are not represented as new upstream work.

| What | Author | Patch | Status |
|---|---|---|---|
| Zenbook A16 keyboard support (I2C-HID quirks, key mapping) | **Konrad Dybcio** | `HID: asus: support the Zenbook A16 (UX3607OA) keyboard`, 2026-07-24, `20260724-topic-asus_keyboard-v1-1-a746ff8f77b2@oss.qualcomm.com` | Adopted 2026-07-27. One mapping (`0x5f`) drifted from a leftover local value; corrected 2026-07-31 to match Konrad's. |
| eDP HPD pin muxing (GPIO119 → `edp0_hot`) | **Konrad Dybcio** | `arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, 2026-07-21, `20260721-topic-a16_submission-v1-2-8ea213130d05@oss.qualcomm.com` | Idea reproduced on our DTB (separate lineage from his file). |
| eDP v8 PHY power-on sequence fix | **Bjorn Andersson** | `phy: qcom: edp: Update v8 programming sequence`, 2026-06-22, `20260622-glymur-edp-phy-v1-0-814b45089ac9@oss.qualcomm.com`, unmerged | Adopted verbatim 2026-08-19 (`patches/0014`, `0015`). Fixes the HBR3-only training bug; retires our local force-HBR3 hack. Validated on hardware — panel now trains natively at HBR2. |
| Zenbook A16 device tree (base board file) | **Konrad Dybcio**, reviewed by **Dmitry Baryshkov** and **Abel Vesa** | `arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, 2026-07-21, `20260721-topic-a16_submission-v1-2-8ea213130d05@oss.qualcomm.com`, unmerged | Adopted 2026-07-29 as the base of our merged DTS. Carried essentially intact; our deltas are additive and commented in-place. |

## Referenced, not yet adopted

| What | Author | Patch | Notes |
|---|---|---|---|
| `INT2_GDSC` on MDSS | — | posted 2026-07-20, `20260720-msm_gdsc2-v1-0-4687866d6cb0@oss.qualcomm.com` | Candidate for our display-teardown crash. |
| Glymur DP PHY PLL programming | — | posted 2026-07-21, `20260721-glymur-phy-conf-v1-1-7c8909552c5e@oss.qualcomm.com` | USB-C combo PHY, not eDP. |
| Glymur display support (MDSS/DPU/DP) | **Abel Vesa** | `drm/msm: Add display support for Glymur platform`, Sep–Oct 2025 | Already in our v7.1 tree. |
| Glymur eDP/DP PHY v8 support (base) | **Abel Vesa**, applied by **Vinod Koul** | `phy: qcom: edp: Add support for Glymur platform` (v6), Dec 2025/Jan 2026 | Already in our v7.1 tree. |
| Zenbook A14 (x1e/x1p) reference | **Alex Vinarskis** | `github.com/alexVinarskis/linux-x1e80100-zenbook-a14` | Closest working reference for eDP + suspend on this SoC family. |
| A16 DT reviews | **Dmitry Baryshkov**, **Abel Vesa** | — | Reviewed-by on Konrad's A16 series. |

## Our own contributions, for contrast

- `clk: qcom: gdsc: fix genpd teardown` — real upstream bug, `patches/glymur-gdsc-genpd-teardown-UPSTREAM.patch`.
- eDP HBR3 link-up and the `LINK_RATE_SET` plumbing fix.
- `wsa884x` pm_runtime fix (`patches/0017`).
- ADSP boot ordering, lid switch, UCSI `usb-role-switch` fix, USB-C DP alt-mode.

## Policy

1. Credit the author by name in the table above.
2. Record the patch subject and message-id.
3. State whether taken verbatim or adapted.
4. Never present adopted work as our own.

Raw patches we've adopted or are evaluating live in `upstream/patches/`, in original mbox
form with authorship headers intact.
