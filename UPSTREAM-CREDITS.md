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
| Zenbook A16 keyboard support (I2C-HID quirks, key mapping) | **Konrad Dybcio** | `HID: asus: support the Zenbook A16 (UX3607OA) keyboard`, 2026-07-24, `20260724-topic-asus_keyboard-v1-1-a746ff8f77b2@oss.qualcomm.com` | Adopted 2026-07-27. One mapping (`0x5f`) drifted from a leftover local value; corrected 2026-07-31 to match Konrad's. Extended locally for native DT backlight ownership and feature report padding; competing EC v3 LED registration omitted to avoid duplicate link. |
| eDP HPD pin muxing (GPIO119 → `edp0_hot`) | **Konrad Dybcio** | `arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, 2026-07-21, `20260721-topic-a16_submission-v1-2-8ea213130d05@oss.qualcomm.com` | Idea reproduced on our DTB (separate lineage from his file). |
| eDP v8 PHY power-on sequence fix | **Bjorn Andersson** | `phy: qcom: edp: Update v8 programming sequence`, 2026-06-22, `20260622-glymur-edp-phy-v1-0-814b45089ac9@oss.qualcomm.com`, unmerged | Adopted verbatim 2026-08-19 (`patches/0014`, `0015`). Fixes the HBR3-only training bug; retires our local force-HBR3 hack. Validated on hardware — panel now trains natively at HBR2. |
| Zenbook A16 device tree (base board file) | **Konrad Dybcio**, reviewed by **Dmitry Baryshkov** and **Abel Vesa** | `arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, 2026-07-21, `20260721-topic-a16_submission-v1-2-8ea213130d05@oss.qualcomm.com`, unmerged | Adopted 2026-07-29 as the base of our merged DTS. Carried essentially intact; our deltas are additive and commented in-place. |
| ASUS Zenbook A16 Embedded Controller (EC) driver, dt-bindings, and board DTS | **Konrad Dybcio** | `platform: arm64: Add a driver for the EC found on ASUS Glymur machines`, 2026-09-23, `20260923-topic-asus._5Fec-v3-0-2bf3bb9da879@oss.qualcomm.com` | Promoted from test kernels 2026-09-30 (`patches/rc3-ec-v3-hid-20260923/`). Carried with local patch preserving keyboard backlight control under `hid-asus`. |

## October 14 soc2 baseline

The [64-patch export](patches/rc5-20261013/README.md) retains the first 59 patches
unchanged. Patches 60–64 preserve the local commits attributed to Local Build
and Codex; earlier upstream authorship and trailers remain intact.

## October 12 working audio baseline

The [59-patch RC5 export](patches/rc5-20261008/README.md) retains the earlier
28 patches, an aggregate local checkpoint, backports, local repairs and the
board-specific audio keep-active workaround. The following backports retain
their original authors and source trailers. They are carried in the tested
integration form; verbatim equivalence to each original posting has not been
independently established. Local compatibility changes remain visible in the
exports. Patch 29 is an aggregate checkpoint, and patches 45 and 51–59 are
local work, not new work attributed to the upstream authors below.

| Author | Exported patch subject | Source message ID |
|---|---|---|
| Akhil P Oommen | [drm/msm/a6xx: Fix secondary rail vote in ARC votes](patches/rc5-20261008/0030-drm-msm-a6xx-Fix-secondary-rail-vote-in-ARC-votes.patch) | `20260923-hawi-gpu-v1-2-0c3c79a1a470@oss.qualcomm.com` |
| Akhil P Oommen | [drm/msm/a6xx: Fix RPMH dependency votes](patches/rc5-20261008/0031-drm-msm-a6xx-Fix-RPMH-dependency-votes.patch) | `20260923-hawi-gpu-v1-3-0c3c79a1a470@oss.qualcomm.com` |
| Akhil P Oommen | [drm/msm/a6xx: Honor perfmode_bw threshold on A8x](patches/rc5-20261008/0032-drm-msm-a6xx-Honor-perfmode_bw-threshold-on-A8x.patch) | `20260923-hawi-gpu-v1-1-0c3c79a1a470@oss.qualcomm.com` |
| Christopher Obbard | [PCI: qcom: Only check bridge nodes for PERST# GPIOs](patches/rc5-20261008/0033-PCI-qcom-Only-check-bridge-nodes-for-PERST-GPIOs.patch) | `20260829-wip-obbardc-drivers-pcie-qcom-rb3gen2-usb-fix-v1-1-337821131a99@oss.qualcomm.com` |
| Baochen Qiang | [wifi: ath12k: signal regd update completion when reg event is dropped](patches/rc5-20261008/0034-wifi-ath12k-signal-regd-update-completion-when-reg-event-is-dropped.patch) | `20260729-ath12k-regd-wait-timeout-v1-1-504aa6e7e93c@oss.qualcomm.com` |
| Baochen Qiang | [wifi: ath12k: use per-radio ab in ath12k_mac_hw_register()](patches/rc5-20261008/0035-wifi-ath12k-use-per-radio-ab-in-ath12k_mac_hw_register.patch) | `20260729-ath12k-regd-wait-timeout-v1-2-504aa6e7e93c@oss.qualcomm.com` |
| Baochen Qiang | [wifi: ath12k: protect new_alpha2 access with base_lock](patches/rc5-20261008/0036-wifi-ath12k-protect-new_alpha2-access-with-base_lock.patch) | `20260729-ath12k-regd-wait-timeout-v1-3-504aa6e7e93c@oss.qualcomm.com` |
| Baochen Qiang | [wifi: ath12k: skip setting country code during registration when unchanged](patches/rc5-20261008/0037-wifi-ath12k-skip-setting-country-code-during-registration-when-unchanged.patch) | `20260729-ath12k-regd-wait-timeout-v1-4-504aa6e7e93c@oss.qualcomm.com` |
| Aaradhana Sahu | [wifi: ath12k: Free allocated CE IRQs on request_irq() failure](patches/rc5-20261008/0038-wifi-ath12k-Free-allocated-CE-IRQs-on-request_irq-failure.patch) | `20260819110215.2485514-2-aaradhana.sahu@oss.qualcomm.com` |
| Aaradhana Sahu | [wifi: ath12k: Free allocated external IRQs on request_irq() failure](patches/rc5-20261008/0039-wifi-ath12k-Free-allocated-external-IRQs-on-request_irq-failure.patch) | `20260819110215.2485514-3-aaradhana.sahu@oss.qualcomm.com` |
| Linkai Gong | [wifi: ath12k: clear dangling channel pointers on error paths](patches/rc5-20261008/0040-wifi-ath12k-clear-dangling-channel-pointers-on-error-paths.patch) | `20260811020523.387433-1-gonglinkai@kylinos.cn` |
| Baochen Qiang | [wifi: ath12k: use per-device max QMI chunk size](patches/rc5-20261008/0041-wifi-ath12k-use-per-device-max-QMI-chunk-size.patch) | `20260730-ath12k-align-qmi-memory-v1-1-0fef98dda614@oss.qualcomm.com` |
| Baochen Qiang | [wifi: ath12k: clear chunk paddr and size in ath12k_qmi_free_target_mem_chunk()](patches/rc5-20261008/0042-wifi-ath12k-clear-chunk-paddr-and-size-in-ath12k_qmi_free_target_mem_chunk.patch) | `20260730-ath12k-align-qmi-memory-v1-2-0fef98dda614@oss.qualcomm.com` |
| Baochen Qiang | [wifi: ath12k: align QMI target memory to 64 KB](patches/rc5-20261008/0043-wifi-ath12k-align-QMI-target-memory-to-64-KB.patch) | `20260730-ath12k-align-qmi-memory-v1-3-0fef98dda614@oss.qualcomm.com` |
| Konrad Dybcio | [soc: qcom: pmic_glink: Avoid losing early rpmsg probe](patches/rc5-20261008/0044-soc-qcom-pmic_glink-Avoid-losing-early-rpmsg-probe.patch) | `20260720-topic-pmic_glink_defer-v1-1-94c0f233f2f7@oss.qualcomm.com` |
| Akhil P Oommen | [drm/msm/a6xx: Factor out RPMh arc-vote helpers](patches/rc5-20261008/0046-drm-msm-a6xx-Factor-out-RPMh-arc-vote-helpers.patch) | `20260923-hawi-gpu-v1-4-0c3c79a1a470@oss.qualcomm.com` |
| Akhil P Oommen | [drm/msm/a6xx: Add BX rail support to GMU dependency votes](patches/rc5-20261008/0047-drm-msm-a6xx-Add-BX-rail-support-to-GMU-dependency-votes.patch) | `20260923-hawi-gpu-v1-5-0c3c79a1a470@oss.qualcomm.com` |
| Akhil P Oommen | [drm/msm/a6xx: Clamp MX dependency vote](patches/rc5-20261008/0048-drm-msm-a6xx-Clamp-MX-dependency-vote.patch) | `20260923-hawi-gpu-v1-6-0c3c79a1a470@oss.qualcomm.com` |
| Qiang Yu | [PCI: qcom: Block accesses to downstream devices on link down](patches/rc5-20261008/0049-PCI-qcom-Block-accesses-to-downstream-devices-on-link-down.patch) | `20260819-ecam_blocker-v2-1-e7a8fdc1c5cb@oss.qualcomm.com` |
| Mrinmay Sarkar | [PCI: qcom: Skip system suspend/resume for firmware-managed PCIe](patches/rc5-20261008/0050-PCI-qcom-Skip-system-suspend-resume-for-firmware-managed-PCIe.patch) | `20260831-skip_suspend-v1-1-ba2d877e22b1@oss.qualcomm.com` |

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

- `drm/msm/dp: skip PUSH_IDLE when the link was never enabled` — merged upstream into mainline Linux (commit `e249a6e2a130c08bb4d8b0a55cbe29754307e5c9`), included in Linux 7.3 and backported to 6.18.54 / 7.2.8. Retired from out-of-tree patch queue on v7.3-rc4 upgrade.
- `clk: qcom: gdsc: fix genpd teardown` — real upstream bug, `patches/glymur-gdsc-genpd-teardown-UPSTREAM.patch`.
- eDP link training running natively at HBR2 (retiring the forced-HBR3 hack) and the `LINK_RATE_SET` plumbing fix; ongoing LKML discussion carries our Tested-by flag.
- Zenbook keyboard standalone backlight and feature completion in `hid-asus` (`QUIRK_USE_KBD_BACKLIGHT`, `QUIRK_PAD_FEATURE_REPORTS`, `QUIRK_FN_LOCK_DEFAULT_OFF`), plus deduplication omitting the competing EC v3 backlight registration.
- `wsa884x` pm_runtime fix (`patches/0017`).
- ADSP boot ordering, lid switch, UCSI `usb-role-switch` fix, USB-C DP alt-mode.

## Policy

1. Credit the author by name in the table above.
2. Record the patch subject and message-id.
3. State whether taken verbatim or adapted.
4. Never present adopted work as our own.

Raw patches we've adopted or are evaluating live in `upstream/patches/`, in original mbox
form with authorship headers intact.
