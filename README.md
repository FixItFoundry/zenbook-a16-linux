# Linux on the ASUS Zenbook A16 (`UX3607OA`)

**Packaging, kernel delivery, and upstream contributor bridge for the ASUS Zenbook A16 UX3607OA**, powered by Qualcomm Snapdragon X2 Elite Extreme (`glymur`).

![Zenbook A16 running Linux](img/screenshot_20260816_080455.png)

## Why This Repository Pivoted: Packaging Layer + Upstream Track

Qualcomm is now actively developing Snapdragon X2 (`glymur`) laptop support upstream across [`qcom-next`](https://github.com/qualcomm-linux/kernel/tree/qcom-next), [`laptops-kernel/topic/glymur-laptops`](https://github.com/linux-msm/laptops-kernel), and `linux-arm-msm` on LKML. Instead of maintaining an isolated out-of-tree fork, this repository serves as:

1. **A Distro Packaging & Update Layer**: Delivers side-by-side installable **Fedora RPMs**, **Ubuntu/Debian DEBs**, **Arch / Omarchy PKGBUILDs**, and portable bundles alongside early-DSP initramfs barriers (`dracut`, `initramfs-tools`, `mkinitcpio`), verified DTBs (`qcom,keep-runtime-active;`), ALSA UCM2 / WirePlumber audio routing, and owner-extracted board firmware.
2. **A Two-Track Kernel Bridge (`stable` & `rc`)**:
   - **`stable` ([`kernel/stable/`](kernel/stable/README.md) + [`patches/stable/`](patches/stable/README.md))**: Pinned to **Linux `v7.3` final** (`c03c1a14507dfaf8b856c2608f9ac216021fc222`) with 155 backported and local patches (`bd1327aac6e1431668eaa53f69e5867d3400b4a0`). Directly aligned with **`linux-omarchy 7.3`** so patches validated on `stable` ship to both standalone Fedora/Ubuntu users and Omarchy.
   - **`rc` ([`kernel/rc/`](kernel/rc/README.md) + [`patches/rc/`](patches/rc/README.md))**: Pinned to **Linux `v7.4-rc1` `linux-next` (`next-20261103`, `d6bcfc94eb4da6e089c5473970cd96727292fd97`)** with 112 residual patches (`ed1c21244abbeae943f39c5a4824ea05c1c613ba`) after retiring 45 upstreamed patches from the `7.3` stable queue ([`patches/rc/port-map.json`](patches/rc/port-map.json)). Used for validating LKML series (`Tested-by:` / `Reviewed-by:`), staging local contributor fixes before upstream submission, and tracking `qcom-next` / `linux-next`.

---

## Quick Start: Install, Upgrade, or Build

### 1. Build Kernel Packages (`RPM`, `DEB`, or Portable Bundle)

Supply any Linux Git repository containing the pinned base commit (`v7.3` for `stable`, `next-20261103` / `v7.4-rc1` for `rc`):

```sh
# Replay and verify both tracks in a temporary Git index (no checkout changes):
python3 scripts/ci.py --replay-only --track both --linux-git /path/to/linux.git

# Build the Linux 7.3 final Stable Track (Fedora RPMs + portable bundle):
JOBS=4 PACKAGE_REVISION=6 ./kernel/stable/build.sh /path/to/linux.git /path/to/stable-out

# Build Ubuntu/Debian DEBs instead:
JOBS=4 PACKAGE_REVISION=6 BUILD_RPM=0 BUILD_DEB=1 \
  ./kernel/stable/build.sh /path/to/linux.git /path/to/stable-deb-out

# Build the RC Development Track:
JOBS=4 PACKAGE_REVISION=6 ./kernel/rc/build.sh /path/to/linux.git /path/to/rc-out
```

If a build is interrupted, pass `--resume` before `/path/to/linux.git` to reuse the verified worktree and compiled objects. Every package revision appends `-a16pkgN+` to the kernel release so upgrades install side-by-side and never overwrite your running or rollback kernel.

### 2. Install or Upgrade on Fedora / Ubuntu

> **Development status.** Package fixtures pass, but a native `dnf`/`apt` transaction has not yet been accepted on hardware; the A16 used for testing was staged by hand. Keep a working kernel and a recovery USB. **On Omarchy, do not use these packages:** install the published `linux-omarchy` kernel and `asus-zenbook-a16-firmware` instead ([status](docs/omarchy-status.md)).

Build and install on native aarch64 Linux; the [package contract](packaging/zenbook-a16-kernel/README.md) lists the build tools. Each build emits three packages that must be installed together (`zenbook-a16-support`, the versioned kernel payload `kernel-zenbook-a16-*` / `linux-image-*`, and the tracking package `zenbook-a16-kernel`):

```sh
# 1. Check that the board firmware is present (see firmware/README.md for sources):
sudo ./iso/glymur-fetch-firmware.sh --check

# 2. Install all three packages together (Fedora):
sudo dnf install /path/to/stable-out/bundle/rpms/*.rpm

# Or on Ubuntu/Debian:
sudo apt install /path/to/stable-deb-out/bundle/debs/*.deb
```

What the install does and does not do:

- The new kernel is added beside the existing ones under its own `-a16pkgN+` release. **The boot default is not changed**; pick the new entry by hand for the first boot and keep the old one as rollback.
- A16 boot entries add development settings, including `selinux=0`, `clk_ignore_unused`, `pd_ignore_unused` and `glymur_pci_skip=5`. This is not a production security or power configuration.
- Sleep stays disabled. Nothing is signed for Secure Boot, and no package repository is published, so later updates mean building and installing a new revision.

For a fresh installation from live media, or to add the kernel-update hooks to an existing root:

```sh
# Full disk installation from live media, after the distro installer has finished:
sudo iso/zenbook-install-to-disk.sh /mnt

# Install persistent kernel-update hooks into a running root or mounted target:
sudo packaging/zenbook-a16-hooks/install-hooks.sh --root / --distro auto
sudo /usr/lib/zenbook-a16/activate-hardware
```

See the [Fedora/Ubuntu installation guide](iso/README.md), [package contract](packaging/zenbook-a16-kernel/README.md), and [Omarchy status](docs/omarchy-status.md).

---

## Repository Layout

| Path | Purpose |
|---|---|
| [`kernel/stable/`](kernel/stable/README.md) | **Stable Release Track (`v7.3` final)**: `build.sh`, `replay.py`, `build.json`, Kconfig (`config`, `required.config`), and `SHA256SUMS`. |
| [`patches/stable/`](patches/stable/README.md) | **Stable Patch Queue (155 patches)**: Ordered `git format-patch` series for `v7.3` final plus [`port-map.json`](patches/stable/port-map.json) tracking upstream equivalents. |
| [`kernel/rc/`](kernel/rc/README.md) | **RC / Upstream Development Track (`v7.4-rc1` / `next-20261103`)**: `build.sh`, `replay.py`, `build.json`, Kconfig (`config`, `required.config`), and `SHA256SUMS`. |
| [`patches/rc/`](patches/rc/README.md) | **RC Patch Queue (112 patches)**: Ordered `git format-patch` series for `next-20261103` (`d6bcfc94eb4da6e089c5473970cd96727292fd97`) plus [`port-map.json`](patches/rc/port-map.json) recording 45 retired upstream commits. |
| [`kernel/arch-7.2.10/`](kernel/arch-7.2.10/BUILD-AND-UPGRADE.txt) | **Arch Linux 7.2.10 Recipe**: Reproducible `PKGBUILD` generator with side-by-side UKI and header support. |
| [`packaging/`](packaging/zenbook-a16-kernel/README.md) | Distro packager ([`zenbook-a16-kernel/`](packaging/zenbook-a16-kernel/README.md)), persistent post-install hooks ([`zenbook-a16-hooks/`](packaging/zenbook-a16-hooks/)), and boot/initramfs verifiers ([`omarchy-a16-support/`](packaging/omarchy-a16-support/)). |
| [`iso/`](iso/README.md) | Live image builder (`build-live-images.sh`), disk installer (`zenbook-install-to-disk.sh`), and firmware presence check and copy helper (`glymur-fetch-firmware.sh`). |
| [`tweaks/`](tweaks/) | UX3607OA ALSA UCM2 profiles, WirePlumber rules, CPU frequency profiles (`glymur-cpu-profile.sh`), and suspend/resume guards. |
| [`firmware/`](firmware/README.md) | Required Qualcomm/ASUS firmware manifest and topology documentation (no proprietary blobs are stored in Git). |
| [`scripts/`](scripts/ci.py) | Hardware-free CI runner (`ci.py`), disposable KVM guest harness (`ci-vm.sh`), and runtime triage utilities (`scripts/triage/`). |
| [`archive/`](archive/README.md) | Retired bringup snapshots (`rc3-20260919`, `rc5-20261002`, `rc5-20261008`, `rc5-20261013`, `rc5-20261031`, `next-202608*`) and historical standalone patches. |

---

## Upstream Contributions & LKML Tracking

A core goal of this repository is contributing back to mainline Linux (`Author:`, `Tested-by:`, and `Reviewed-by:` on `linux-arm-msm` / LKML) and validating upstream Snapdragon X2 (`glymur`) series on real UX3607OA hardware. Full commit-level provenance is recorded in [`UPSTREAM-CREDITS.md`](UPSTREAM-CREDITS.md).

### Local Fixes in This Stack (Jesse Casco)

None of these has been posted to LKML from this repository yet. Patch numbers are `patches/stable/`.

- **eDP 1.4 link training**: `drm/msm/dp: make the eDP 1.4 LINK_RATE_SET path actually reachable` (`0001`) and three rate-set corrections (`0147`–`0149`). `linux-omarchy` carries an equivalent series prepared by Jim Martin; the two are being reconciled before anything is sent upstream.
- **GDSC error unwind (RFC draft)**: `clk: qcom: gdsc: unwind domains when registration fails` (`0112`).
- **RPMh regulator and RTC**: `regulator: qcom-rpmh: Don't overwrite the initial mode with the boot readback` (`0144`), `rtc: interface: fix wakeup source leak in rtc_timer_do_work()` (`0145`) and `rtc: qcom-glink: drop set_time when the RTC is read-only` (`0146`).
- **Audio and SoundWire**: `ASoC: wsa884x: balance pm_runtime_enable() with devm-managed disable` (`0010`), `ASoC: qdsp6: q6apm: fast-retry APM_CMD_GET_SPF_STATE` (`0011`) and the `qcom,keep-runtime-active` speaker-controller guard (`0058`).
- **A16 input and board**: `HID: asus: complete the feature set for the Zenbook I2C keyboard` (`0004`), M.2 connector wiring for Wi-Fi and Bluetooth (`0154`) and the RGB camera MCLK at 6 mA (`0155`).

Several older local patches (`0028`, `0050`–`0063`, `0104`–`0111`) are combined snapshots without a sign-off. They are local carries, not upstream candidates in their current form.

### Tracked Qualcomm & LKML Patches Carried in `stable`

- **USB3 QMP combo PHY** (*Konrad Dybcio*): `phy: qcom: qmp-combo: Update Glymur USB3 settings` (`0143`).
- **Embedded controller** (*Konrad Dybcio*): binding, `asus-glymur-ec` driver and A16 node (`0023`–`0025`).
- **AudioReach and q6apm** (*Zhangfei Gao*, *Fabian Renn-Giles*, *Mohit Sharma*, *Shawn Guo*, *Vladyslav Tymoshchuk* and others): multichannel PCM, channel-map and buffer fixes (`0114`–`0115`, `0121`–`0131`).
- **PCIe** (*Qiang Yu*, *Mrinmay Sarkar*, *Christopher Obbard*, *Krishna Chaitanya Chundru*): link-down access blocking, firmware-managed suspend, bridge-only PERST# parsing and the halting fix (`0032`, `0048`, `0049`, `0089`).
- **Sleep and hibernation** (*Abel Vesa*): PM core and GMU restore fixes (`0140`–`0142`).
- **Camera** (*Nihal Kumar Gupta*, *Oleg Keri*, *Hitesh Patel*): CAMSS, CCI and MCLK nodes plus CCI clock fixes (`0100`–`0103`, `0109`). The PM8010, HM1092 and A16 wiring patches (`0104`–`0108`) are local.
- **QCC2072 Bluetooth and M.2** (*Rahul Samana*, *Vivek Sahu*, *Krishna Chaitanya Chundru*, *Manivannan Sadhasivam*): carried as `FROMLIST` (`0150`–`0153`); not in mainline as of 2026-11-13.

---

## Hardware Status Summary

See [`docs/current-build.md`](docs/current-build.md) and [`docs/omarchy-status.md`](docs/omarchy-status.md) for per-boot hardware evidence and remaining limits:

| Subsystem | Status on `stable` / `rc` |
|---|---|
| **Boot, NVMe & Btrfs** | Verified with early-DSP (`qcadsp8480.mbn`, `qccdsp8480.mbn`) pre-root initramfs barrier (`pre-root-v1`). |
| **Built-in 3K OLED eDP Display** | Working at native 2880x1800 @ 120 Hz (`phy-qcom-edp` v8 + `drm/msm/dp` `LINK_RATE_SET` fixes). |
| **Keyboard, Backlight & Touchpad** | Working via `hid-asus` UX3607OA I2C HID feature reports and `i2c_hid_of`. |
| **Wi-Fi 7 & Bluetooth (QCC2072)** | Wi-Fi working through the mainline M.2 connector with board-specific `board-2.bin` / `firmware-2.bin`. Bluetooth uses the pending QCC2072 series and linux-firmware's `qca/orn*` files. |
| **Speakers (4x WSA884x SoundWire)** | Working with `qcom,keep-runtime-active;` DTB guard and UX3607OA topology/UCM2. |
| **Camera (OV02C10 RGB / HM1092 IR) & DMICs** | Integrated (`camera_enabled: true`, nonsecure CSID0/VFE0 path). MCLK4 at 6 mA removed microphone-triggered RGB banding in an A/B/A test; IR capture and combined acceptance are pending. |
| **USB-C / USB3 (`usb0`, `usb1`)** | `0143` updates Glymur USB3 QMP combo PHY SERDES/TX/RX/PCS tables for `usb1` `-71` SuperSpeed link training; physical port matrix acceptance in progress. |
| **Power, EC Fan & Sleep** | USB-PD online and `asus_glymur_ec` fan profile 2 active; deep S2idle/PCIe noirq suspend remains guarded (`glymur_pci_skip=5`). |

## Reference

- [Kernel Track Policy & Lifecycle](docs/kernel-tracks.md) and [Current Build Record](docs/current-build.md)
- [Kernel Packages Overview](kernel/README.md) and [Patch Queues Overview](patches/README.md)
- [Upstream Credits & Provenance](UPSTREAM-CREDITS.md) and [Changelog](CHANGELOG.md)
- [Hardware Architecture](docs/hardware.md) and [Power & Thermal Notes](docs/power-and-thermal.md)

Kernel-derived sources and patches are **GPL-2.0-only**; see [LICENSE](LICENSE). Unofficial community packaging and kernel engineering project, not endorsed by ASUS or Qualcomm.
