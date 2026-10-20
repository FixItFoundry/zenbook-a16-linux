# Linux on the ASUS Zenbook A16

Mainline-based Linux bring-up for the **ASUS Zenbook A16 UX3607OA**, powered by
Qualcomm Snapdragon X2 Elite Extreme (`glymur`).

![Zenbook A16 running Linux](img/screenshot_20260816_080455.png)

## Mainline + `qcom-next` / `qcom-topics` Bridge — 2026-10-18

**`7.3.0-rc5-ZenbookA16-20261018-rc5-qcom1+` bridges the mainline `v7.3-rc5` release base with Qualcomm's `qcom-next` and `qcom-topics` repositories, managed and updated via post-install hooks.**

Rather than tracking daily `linux-next` churn or attempting source builds inside end-user package hooks, the repository pulls from the pinned mainline release (`v7.3-rc5`), layers the [64-patch local A16 baseline](patches/rc5-20261013/README.md) plus the [40-patch `qcom-next` / `qcom-topics` bridge series](patches/qcom-glymur-bridge-20261018/README.md) (104 patches total, reproducing tree `65fd4b07749a5d6b48f5b2dbbfc3e78681f04bf1`), and applies all initramfs, DTB, audio UCM2/WirePlumber, and hardware activation updates through scoped post-install hooks (`packaging/zenbook-a16-hooks/`).

See the [bridge build package](kernel/rc5-qcom-bridge-20261018/README.md) and [bridge Kconfig fragment](kernel/qcom-glymur-bridge.config). Hardware boot and runtime acceptance of the bridged stack remain separate from source and package verification.

## Baseline — 2026-10-14

**`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+` remains the boot-validated baseline.** This is a development baseline with limited hardware acceptance.

The [build package](kernel/rc5-20261013/README.md) contains the exact tested
config and [64 ordered patches](patches/rc5-20261013/README.md). The previous
59 patches are unchanged; five additions cover error handling, DMA, SoundWire,
Bluetooth, DP, QMP/Type-C ownership and a hibernation config fragment.

| Area | Validation and limits |
|---|---|
| Boot and storage | Ordinary soc2 boot verified; 8,487 installed hashes match. The earlier Btrfs free-space-cache error has not returned after cache rebuild. |
| Display and input | Built-in display, keyboard and touchpad confirmed on the preceding boot of the same binaries. |
| Speakers | Four channels confirmed on an earlier soc2 boot; accepted with the retained keep-active workaround. All four devices are attached now; no fresh listening test. |
| CPU and GPU | One 30-second CPU worker and 600 Vulkan frames passed on the preceding boot. Long-duration stability remains open. |
| Wi-Fi and USB0 | Wi-Fi passed 20 gateway replies on this boot; USB0 SuperSpeed Ethernet passed a short test on an earlier soc2 boot. |
| USB1 | SuperSpeed enumeration still fails with `-71`; the hub falls back to USB2. |
| Bluetooth | Missing `qca/clnbtfw10.tlv` is reported; pairing and traffic remain unvalidated. |
| Power and sleep | USB-PD supply is online; fan profile 2 is selected. Suspend, hibernate, battery life and physical fan response remain unaccepted. |
| Other hardware | Camera capture, microphones, other audio routes, external displays and USB4 remain unvalidated. Camera drivers are blacklisted. |

The [current build record](docs/current-build.md) separates current-boot checks
from retained tests. Historical resets and RPMh timeouts remain unresolved.
The saved GRUB fallback remains `zenbook-a16-rc5-audiopm1-20261008`;
previous kernels and the Windows route are retained.

## Branches & Distro Tracks

All cross-compatible kernel tracks, multi-distro installer scripts, and persistent post-install kernel hooks are synced to `main`, with dedicated working branches for concurrent development:

- **`main`**: Unified baseline carrying the mainline release + `qcom-next`/`qcom-topics` bridge (`rc5-qcom-bridge-20261018`), the validated `7.3-rc5` (`rc5-20261013`) baseline, the Arch `7.2.10` (`arch-7.2.10`) backport, cross-distro installer (`iso/`), and post-install kernel hooks (`packaging/`).
- **`feature/multi-distro-installer`**: Working branch for the mainline + `qcom-next`/`qcom-topics` bridge, kernel package builder (`RPM`/`DEB`/bundle), and persistent post-install hooks across Fedora (`aarch64`) and Ubuntu (`arm64`).
- **`feature/arch-7.2.10-a16`**: Working branch for the Arch Linux `7.2.10` kernel & support package port.

## Build and test

Verify and build the mainline release + `qcom-next`/`qcom-topics` bridge package (or the `rc5-20261013` baseline) as a separately versioned package:

```sh
# Mainline release + qcom-next / qcom-topics bridge (104 patches):
python3 kernel/rc5-qcom-bridge-20261018/verify.py /path/to/linux
JOBS=4 ./kernel/rc5-qcom-bridge-20261018/build.sh /path/to/linux /path/to/new-output

# Validated soc2 baseline (64 patches):
python3 kernel/rc5-20261013/verify.py /path/to/linux
JOBS=4 ./kernel/rc5-20261013/build.sh /path/to/linux /path/to/new-output-soc2
```

After a build failure, repeat the same command with `--resume` before the Linux
repository path to reuse its clean, fully patched source and compiled objects.

Build options are configured via environment variables:

- `BUILD_RPM=1`: Build Fedora kernel, support and tracking RPMs (default: 1).
- `BUILD_DEB=1`: Build Ubuntu kernel, support and tracking DEBs (default: 0).
- `PACKAGE_REVISION=1`: Give each rebuild a distinct release and package version.
- `STAGE_BUNDLE=1`: Stage portable distro-agnostic bundle at `$OUTPUT_DIR/bundle/` containing `vmlinuz-$KREL`, `glymur-asus-zenbook-a16-ux3607oa.dtb`, `lib/modules/$KREL/`, per-kernel boot hashes/policy, and release metadata (default: 1).

The build script automatically validates the compiled DTB against the required `qcom,keep-runtime-active;` safety property via `dtc`, aborting the build if missing.
See the [package contract and build commands](packaging/zenbook-a16-kernel/README.md).
Native package transactions and physical boot/rollback still need acceptance.

## Installation & Persistent Post-Install Hooks

To install the kernel, DTB, firmware, platform tweaks, and persistent post-install hooks onto a target system:

```sh
# Install persistent hooks and staged support configs into a mounted target or running root:
sudo packaging/zenbook-a16-hooks/install-hooks.sh --root / --distro auto

# Activate model-gated UX3607OA hardware configs and conditional fTPM rules:
sudo /usr/lib/zenbook-a16/activate-hardware

# Or run the end-to-end disk installer from live media:
sudo iso/zenbook-install-to-disk.sh /mnt
```

The post-install hooks support build-identified Fedora and Ubuntu kernels bridged
from the mainline release and `qcom-next`/`qcom-topics`. They skip stock distro
kernels and stop on invalid A16 metadata or boot-entry errors; they do not
compile C/DTS patches against binary distro kernels. Experimental suspend is not
enabled by installation. Btrfs subvolume roots need a separate `/boot`.

Fedora uses a dracut pre-mount readiness barrier and versioned BLS entries.
Ubuntu uses an init-premount barrier and explicit A16 GRUB entries. Both reuse
the same DSP policy, include the `qcom-next`/`qcom-topics` bridge modules when
present, run `activate-hardware` during post-install to link UX3607OA audio/platform
configs and unmask `/dev/tpm0` when `CONFIG_TCG_QCOM` is enabled, and preserve
rescue and rollback entries.

See [installation requirements and limitations](iso/README.md) before building
or installing. Hardware boot, update/rollback and sleep acceptance remain separate
from the software checks.

## Reference

- [Hardware](docs/hardware.md) and [historical modifications](docs/modifications.md)
- [Changelog](CHANGELOG.md) and [documentation index](docs/README.md)
- [Kernel packages](kernel/README.md) and [upstream credits](UPSTREAM-CREDITS.md)

This project is AI-assisted; the maintainer is not a kernel developer. Hardware
tests determine acceptance, and corrections remain in the project history.
Kernel-derived sources are **GPL-2.0-only**; see [LICENSE](LICENSE).
This is unofficial research, not endorsed by ASUS or Qualcomm.
