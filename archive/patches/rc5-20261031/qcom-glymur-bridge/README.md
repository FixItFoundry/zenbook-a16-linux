# Mainline + `qcom-next` / `qcom-topics` Bridge Series (`2026-10-18`)

This directory contains the 40-patch sequential bridge series (`0001`–`0040`) layered on top of the mainline `v7.3-rc5` release base (`patches/rc5-20261013`, 64 patches; 104 patches total), verified to apply cleanly (`git apply --cached` / `git am`) and managed on target systems via scoped post-install hooks.

## Architecture: Mainline Release + `qcom-next` / `qcom-topics` Bridge + Post-Install Hooks

Rather than tracking daily `linux-next` churn or attempting source builds inside end-user package hooks, the repository pulls from a pinned mainline release candidate (`v7.3-rc5` / `v7.3-rc7`), bridges the hardware-enabling commits from Qualcomm's `qcom-next` and `qcom-topics` branches, and updates installed systems through scoped post-install hooks (`packaging/zenbook-a16-hooks/`):

1. **Mainline Release Base (`v7.3-rc5` $\rightarrow$ `v7.3-rc7`)**:
   - Provides core Snapdragon X2 (`glymur`) SoC bring-up (`pinctrl-glymur`, `gcc-glymur`, `tcsrcc-glymur`, `dispcc-glymur`, `gpucc-glymur`, `icc-glymur`).
   - Combined with the 64-patch local A16 baseline (`patches/rc5-20261013/`).
2. **`qcom-next` & `qcom-topics` Bridge (`patches/qcom-glymur-bridge-20261018/`)**:
   - Pulls 38 Glymur patches from Qualcomm's `qcom-next` and `qcom-topics` branches plus 2 local bridge fixes (`soundwire-qcom` deferred codec probing and `i2c-qcom-geni` 32 MHz source clock selection). The ordered `series` file is authoritative.
   - Configured via [`kernel/qcom-glymur-bridge.config`](../../kernel/qcom-glymur-bridge.config).
3. **Scoped Post-Install Hook Updates (`packaging/zenbook-a16-hooks/` & `packaging/zenbook-a16-kernel/`)**:
   - Pre-built kernel packages (`kernel-zenbook-a16-*` on Fedora, `linux-image-*` on Ubuntu) declare the audited DSP ABI capability (`zenbook-a16-dsp-abi = 1`).
   - Post-install hooks (`95-zenbook-a16.install`, `zz-zenbook-a16`, `activate-hardware`) automatically rebuild the early-DSP initramfs with ASUS-signed ADSP/CDSP firmware and `qcom-topics` bridge modules, stage the verified DTB, link audio UCM2 and WirePlumber policies on UX3607OA hardware, conditionally unmask `/dev/tpm0` when `CONFIG_TCG_QCOM` is enabled, and verify boot entries while preserving rollback kernels.

## Reference repositories

- [Mainline Linux](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/)
- [Qualcomm kernel](https://github.com/qualcomm-linux/kernel) and [topic branches](https://github.com/qualcomm-linux/kernel-topics)
- [Qualcomm kernel configuration](https://github.com/qualcomm-linux/kernel-config)
- [Qualcomm Debian image tooling](https://github.com/qualcomm-linux/qcom-deb-images)

Use the base commit in [`build.json`](../../kernel/rc5-qcom-bridge-20261018/build.json)
and the shipped patch series to reproduce this snapshot; moving branch tips and
local checkout paths do not identify its source.

## 4-Way Diff Summary (`v7.3-rc5` vs `v7.3-rc7` vs `linux-next` vs `qcom-topics`)

1. **`v7.3-rc5` $\rightarrow$ `v7.3-rc7` (Mainline RC)**:
   - 12 files changed (`+76 / -64` lines) on Glymur/A16 paths.
   - `drivers/clk/qcom/gpucc-glymur.c` marks `gpu_cc_cx_gdsc` as `PWRSTS_OFF_ON | FLAG_VOTABLE` (upstreamed equivalent of `patches/rc5-20261013/0006`).
   - `drivers/usb/typec/ucsi/{ucsi.c,ucsi_glink.c,displayport.c}` adds workqueue drain before `ucsi_destroy()`, `reg` property lookup, and DP altmode bounds checks.
   - `sound/soc/codecs/lpass-wsa-macro.c` and `sound/soc/qcom/lpass-cpu.c` fix Ear speaker gain restore and Quad I2S DAI index.
2. **`v7.3-rc7` $\rightarrow$ `linux-next` (`next-20261016`)**:
   - 56 files changed (`+8,126 / -652` lines) on core Glymur/A16 paths (235 files, `+20,710 / -3,620` across all Qcom/A16 paths).
   - **Local A16 patches already merged in `linux-next`**:
     - `0007` & `0008`: `lpass-wsa-macro.c` v2.5 Compander1 CTL3/CTL7 registers + `clk_init_data = {}` + `regcache_sort_defaults()`.
     - `0014`: `trusted_tpm2.c` `#include <linux/asn1_decoder.h>`.
     - `0015`: `drivers/soundwire/qcom.c` `SCP_ADDRPAGE1/2` per-slave cache + invalidation on re-attach.
     - `0016`: `glymur-asus-zenbook-a16-ux3607oa.dts` `qcom,dmic-sample-rate = <2400000>;` and removal of invalid `qcom,uefi-rtc-info`.
     - `0033`–`0043`: `pcie-qcom.c` bridge-only PERST# GPIO check and the 10-patch `ath12k` QMI/IRQ/regd cleanup series.
   - **New Glymur features in `linux-next`**:
     - Standalone MIPI CSI-2 D-PHY driver (`phy-qcom-mipi-csi2-{core,3ph-dphy}.c`) + `camss` Glymur `vfe-680`/`csid-680`/`csiphy-2.3.0`.
     - `phy-qcom-qmp-pcie-multiphy.c` Gen5x8 bifurcation (`v6_40`) + `glymur.dtsi` `pcie3a`/`pcie3b` shared PHY wiring.
     - `gcc-glymur.c` UFS symbol clock `clk_regmap_phy_mux_ops` and `phy-qcom-eusb2-repeater.c` `spmi_subdevice` refactor.

## Patch Series Contents (`series`)

- **Local A16 Bridge Fixes (`0001`–`0002`)**:
  - `0001-soundwire-qcom-allow-deferred-codec-probes.patch`: Keeps an initialized SoundWire bus registered when boot enumeration times out while codec reset suppliers are still deferred. Completion is logged only when all slaves are online; hardware initialization and DAI registration failures retain their cleanup paths.
  - `0002-i2c-qcom-geni-restore-source-clock-selection.patch`: Restores source-clock frequency table selection in `i2c-qcom-geni.c` on Glymur (`32 MHz` SE clock).
- **Qualcomm bridge patches (`0003`–`0040`)**: USB/power, LPASS, PMIC GLINK RTC, display, CDSP, video, Wi-Fi, PCIe, thermal, TEE/TPM and camera enablement. The [ordered series](series) records the actual filenames and order; each patch retains its available provenance.
