# Upstream credits

This project stands on work done by upstream Linux and Qualcomm developers bringing up the
Snapdragon X2 Elite ("Glymur") platform. Anything here that originates upstream is credited
with its author and source patch.

If you're one of the people below and want an entry corrected, removed, or reworded, open an
issue — we'll fix it immediately.

## Adopted into this tree

The [rc5 audio channel-map overlay](patches/audio-channel-maps-20261031/series)
backports Zhangfei Gao's [v3 multichannel helper replacement](https://lore.kernel.org/r/20261028024720.981971-1-zhangfei.gao@oss.qualcomm.com)
and the two explicit-map clears from Fabian Renn-Giles's
[stale-map fix](https://lore.kernel.org/r/20261028100708.6808-1-fabian@fielding.dev).
It adapts rc5 context and drops the superseded helper hunk from Fabian's patch.
Original authorship is retained; these are not new submissions by this project.

The [7.3 final source port](patches/stable/README.md) carries the full
155-patch A16/Qualcomm/camera/LKML stack on `v7.3` (`c03c1a14507dfaf8b856c2608f9ac216021fc222`),
omitting three complete upstream equivalents (`0001`–`0111`) and integrating 32
new fixes (`0112`–`0143`) from in-repo overlays, LKML, `qcom-next`, and
`laptops-kernel/topic/glymur-laptops` (with three context adaptations for upstream
overlap), plus the November 12 RPMh/RTC fixes (`0144`–`0146`) and nine carried-forward patches (`0147`–`0155`). Its [patch map](patches/stable/port-map.json) preserves original
provenance and authorship trailers on every patch.

## November 10, 2026 — QCC2072 and M.2 Bluetooth support

- Stable `0150` / rc `0107`: **Rahul Samana**, QCC2072 DT binding, [v2 1/6](https://lore.kernel.org/all/20260727-rb3-industrial-bt-uart-v2-1-2d100f30e202@oss.qualcomm.com/).
- Stable `0151` / rc `0108`: **Vivek Sahu**, QCC2072 UART driver support, [v2 2/6](https://lore.kernel.org/all/20260727-rb3-industrial-bt-uart-v2-2-2d100f30e202@oss.qualcomm.com/).
- Stable `0152` / rc `0109`: **Krishna Chaitanya Chundru**, QCC2072 M.2 power sequencing, [v2 3/6](https://lore.kernel.org/all/20260727-rb3-industrial-bt-uart-v2-3-2d100f30e202@oss.qualcomm.com/).
- Stable `0153` / rc `0110`: **Manivannan Sadhasivam**, M.2 Bluetooth power sequencing, [monza-wireless v7 1/8](https://lore.kernel.org/all/20261005-monza-wireless-v7-1-5a6de7662dcb@oss.qualcomm.com/), with the QCC2072 case-group context adaptation noted in the patch.

These four patches are carried as `FROMLIST`. The accompanying eDP corrections,
A16 M.2 wiring restoration and RGB camera clock-drive fix are by Jesse Casco.

## November 3, 2026 — Linux 7.3 final rebase (`0112`–`0143`)

| Patch | Author | Subject | Upstream / LKML Provenance |
|---|---|---|---|
| [`0112`](patches/stable/0112-clk-qcom-gdsc-unwind-domains-when-registration-fails.patch) | **Jesse Casco** | `[RFC PATCH] clk: qcom: gdsc: unwind domains when registration fails` | Local authored RFC (`archive/patches/standalone/glymur-gdsc-genpd-teardown-UPSTREAM.patch`), extending Herman van Hazendonk's `20260602140934.796697-4-github.com@herrie.org` |
| [`0113`](patches/stable/0113-pmdomain-core-clear-states-after-freeing-them.patch) | **Anfernee Cao** | `[PATCH] pmdomain: core: clear states after freeing them` | `179259111932.19580.13027750156272888992@gmail.com` |
| [`0114`](patches/stable/0114-ASoC-qcom-audioreach-support-multichannel-PCM-formats.patch) | **Zhangfei Gao** | `[PATCH] ASoC: qcom: audioreach: support multichannel PCM formats` | `20261028024720.981971-1-zhangfei.gao@oss.qualcomm.com` |
| [`0115`](patches/stable/0115-ASoC-qcom-qdsp6-clear-stale-channel_map-entries.patch) | **Fabian Renn-Giles** | `[PATCH] ASoC: qcom: qdsp6: clear stale channel_map entries` | `20261028100708.6808-1-fabian@fielding.dev` |
| [`0116`](patches/stable/0116-phy-qualcomm-m31-eusb2-Add-register-XCFGI_159_152-for-SE0-recovery.patch) | **Peter Chen** / **Elson Serrao** | `[PATCH v2 1/1] phy: qualcomm: m31-eusb2: Add register XCFGI_159_152 for SE0 recovery` | `20261015221849.4027591-2-quic_eserrao@quicinc.com` (Tested-by Christian Cortner on Zenbook A16 UX3607OA) |
| [`0117`](patches/stable/0117-arm64-dts-qcom-glymur-Set-snps-resume-hs-terminations-for-USB-controllers.patch) | **Peter Chen** | `[PATCH v2 1/4] arm64: dts: qcom: glymur: Set snps,resume-hs-terminations for USB controllers` | `20261015080909.2610018-2-peter.chen@oss.qualcomm.com` |
| [`0118`](patches/stable/0118-arm64-dts-qcom-glymur-Refrain-from-overclocking-the-USB2-controller.patch) | **Konrad Dybcio** | `arm64: dts: qcom: glymur: Refrain from overclocking the USB2 controller` | `20261028-topic-usb2_glymur_clk-v1-1-34f1b4c245a7@oss.qualcomm.com` (`29a70f3d2326`) |
| [`0119`](patches/stable/0119-phy-qcom-qmp-usb-Add-PM-suspend-resume-callbacks.patch) | **Prashanth K** | `FROMLIST: phy: qcom: qmp-usb: Add PM suspend/resume callbacks` | `20261022104321.306679-1-prashanth.k@oss.qualcomm.com` (`453569726aae`) |
| [`0120`](patches/stable/0120-phy-qcom-qmp-combo-Add-PM-suspend-resume-callbacks.patch) | **Prashanth K** | `FROMLIST: phy: qcom: qmp-combo: Add PM suspend/resume callbacks` | `20261022104321.306679-2-prashanth.k@oss.qualcomm.com` (`0d348e9f0a31`, context adapted) |
| [`0121`](patches/stable/0121-soc-qcom-apr-Publish-GPR-callback-before-client-probe.patch) | **Srinivas Kandagatla** | `FROMLIST: soc: qcom: apr: Publish GPR callback before client probe` | `laptops-kernel/topic/glymur-laptops` (`b75408b2f242`) |
| [`0122`](patches/stable/0122-ASoC-qcom-q6apm-Guard-callbacks-until-probe-data-is-ready.patch) | **Srinivas Kandagatla** | `FROMLIST: ASoC: qcom: q6apm: Guard callbacks until probe data is ready` | `laptops-kernel/topic/glymur-laptops` (`d023cbd2af85`) |
| [`0123`](patches/stable/0123-ASoC-qcom-q6apm-clear-g_apm-on-driver-removal.patch) | **Srinivas Kandagatla** | `ASoC: qcom: q6apm: clear g_apm on driver removal` | `laptops-kernel/topic/glymur-laptops` (`be2172758f26`) |
| [`0124`](patches/stable/0124-ASoC-qcom-q6apm-Fix-unmap-regions-response-handling.patch) | **Srinivas Kandagatla** | `ASoC: qcom: q6apm: Fix unmap regions response handling` | `laptops-kernel/topic/glymur-laptops` (`4b832a2af52e`) |
| [`0125`](patches/stable/0125-ASoC-qcom-q6apm-Clear-the-right-handle-on-pos-buffer-unmap.patch) | **Srinivas Kandagatla** | `ASoC: qcom: q6apm: Clear the right handle on pos buffer unmap` | `laptops-kernel/topic/glymur-laptops` (`43c69604271f`) |
| [`0126`](patches/stable/0126-ASoC-qcom-q6apm-Unmap-DSP-buffers-before-removing-the-topology.patch) | **Srinivas Kandagatla** | `ASoC: qcom: q6apm: Unmap DSP buffers before removing the topology` | `laptops-kernel/topic/glymur-laptops` (`a51c5dd7f7fc`) |
| [`0127`](patches/stable/0127-ASoC-qcom-q6apm-reset-the-hw-pointer-with-the-fragment-queue.patch) | **Srinivas Kandagatla** | `ASoC: qcom: q6apm: reset the hw pointer with the fragment queue` | `laptops-kernel/topic/glymur-laptops` (`0337b8129cf3`) |
| [`0128`](patches/stable/0128-ASoC-qcom-q6apm-dai-wrap-the-position-of-a-full-ring-to-0.patch) | **Srinivas Kandagatla** | `ASoC: qcom: q6apm-dai: wrap the position of a full ring to 0` | `laptops-kernel/topic/glymur-laptops` (`0ea3e0b196f8`) |
| [`0129`](patches/stable/0129-ASoC-qcom-audioreach-fix-module-cfg-blob-size-handling.patch) | **Srinivas Kandagatla** | `ASoC: qcom: audioreach: fix module cfg blob size handling` | `laptops-kernel/topic/glymur-laptops` (`e21fb64a8c47`) |
| [`0130`](patches/stable/0130-ASoC-qcom-qdsp6-q6afe-fix-clk-vote-response-type-mismatch.patch) | **Srinivas Kandagatla** | `ASoC: qcom: qdsp6: q6afe: fix clk vote response type mismatch` | `laptops-kernel/topic/glymur-laptops` (`f3c7bee984ab`) |
| [`0131`](patches/stable/0131-ASoC-qcom-sm8250-Limit-RX-digital-gain-to-0-dB.patch) | **Oleg Keri** | `ASoC: qcom: sm8250: Limit RX digital gain to 0 dB` | `20261009085811.27383-1-okerixx@gmail.com` (`55df18877473`) |
| [`0132`](patches/stable/0132-soundwire-qcom-disable-the-interrupt-before-gating-the-clock.patch) | **Oleg Keri** | `[PATCH v2] soundwire: qcom: disable the interrupt before gating the clock` | `20261009082639.22662-1-okerixx@gmail.com` (`6c067677192f`, context adapted) |
| [`0133`](patches/stable/0133-clk-qcom-Fix-camera-rivian-PLL-configuration-settings.patch) | **Jagadeesh Kona** | `clk: qcom: Fix camera rivian PLL configuration settings` | `qcom-next` (`6666c03f2346`) |
| [`0134`](patches/stable/0134-clk-qcom-gcc-glymur-Use-clk_regmap_phy_mux_ops-for-GCC-UFS-muxes.patch) | **Jagadeesh Kona** | `clk: qcom: gcc-glymur: Use clk_regmap_phy_mux_ops for GCC UFS muxes` | `qcom-next` (`20b77a88fc6f`) |
| [`0135`](patches/stable/0135-iommu-arm-smmu-Work-around-Qualcomm-SMMU-500-TLBIVAL-granule-issue.patch) | **Prakash Gupta** / **Sibi Sankar** | `WORKAROUND: iommu/arm-smmu: Work around Qualcomm SMMU-500 TLBIVAL granule issue` | `laptops-kernel/topic/glymur-laptops` (`7848b6fc30f4`) |
| [`0136`](patches/stable/0136-mmc-sdhci-msm-Remove-brownout-risk.patch) | **Konrad Dybcio** | `mmc: sdhci-msm: Remove brownout risk` | `qcom-next` (`b0a3511a02ba`) |
| [`0137`](patches/stable/0137-power-supply-qcom_battmgr-Notify-charger-supplies-of-online-changes.patch) | **Bjorn Andersson** | `power: supply: qcom_battmgr: Notify charger supplies of online changes` | `qcom-next` (`87fd20da8caa`) |
| [`0138`](patches/stable/0138-power-supply-qcom_battmgr-report-full-batteries.patch) | **Bjorn Andersson** | `power: supply: qcom_battmgr: report full batteries` | `20261008-battmgr-full-v1-1-4f5485a9c421@oss.qualcomm.com` (`6c8098e04ee4`, context adapted) |
| [`0139`](patches/stable/0139-wifi-ath12k-keep-ML-mgmt-tx-on-active-link.patch) | **Hangtian Zhu** | `FROMLIST: wifi: ath12k: keep ML mgmt tx on active link` | `20261020063719.3486519-1-hangtian.zhu@oss.qualcomm.com` (`cdf7a2675e70`) |
| [`0140`](patches/stable/0140-PM-sleep-Do-not-mark-devices-without-PM-callbacks-active-on-resume.patch) | **Abel Vesa** | `[PATCH 1/2] PM: sleep: Do not mark devices without PM callbacks active on resume` | `20261029-pm-sleep-hibernation-fixes-v1-1-a2fd76bd9066@oss.qualcomm.com` |
| [`0141`](patches/stable/0141-PM-sleep-Do-not-arm-wakeup-IRQs-for-hibernation-freeze-and-quiesce.patch) | **Abel Vesa** | `[PATCH 2/2] PM: sleep: Do not arm wakeup IRQs for hibernation freeze and quiesce` | `20261029-pm-sleep-hibernation-fixes-v1-2-a2fd76bd9066@oss.qualcomm.com` |
| [`0142`](patches/stable/0142-drm-msm-a6xx-Reset-the-GMU-state-when-restoring-from-hibernation.patch) | **Abel Vesa** | `[PATCH RFC] drm/msm/a6xx: Reset the GMU state when restoring from hibernation` | `20261030-drm-msm-a6xx-hibernation-gmu-reset-v1-1-820bc7859df5@oss.qualcomm.com` |
| [`0143`](patches/stable/0143-phy-qcom-qmp-combo-Update-Glymur-USB3-settings.patch) | **Konrad Dybcio** | `[PATCH] phy: qcom: qmp-combo: Update Glymur USB3 settings` | `76e97352-3a54-40de-8ef0-eef0ca27ca73@oss.qualcomm.com` / `20261102-topic-glymur_usb3_phy-v1-1-bf53bc466cf6@oss.qualcomm.com` (`8c9d1255de7c`) |

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
- `clk: qcom: gdsc: unwind domains when registration fails` — local review draft in `archive/patches/standalone/glymur-gdsc-genpd-teardown-UPSTREAM.patch`. Successful-unregister cleanup was already contributed upstream by Herman van Hazendonk; this draft only fixes failed registration.
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
