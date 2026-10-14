# Linux on the ASUS Zenbook A16

Mainline-based Linux bring-up for the **ASUS Zenbook A16 UX3607OA**, powered by
Qualcomm Snapdragon X2 Elite Extreme (`glymur`).

![Zenbook A16 running Linux](img/screenshot_20260816_080455.png)

## Baseline — 2026-10-14

**`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+` is the repository and future-testing
baseline.** This is a development baseline with limited hardware acceptance.

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
The saved GRUB fallback remains `zenbook-a16-rc5-audiopm1-fan2-20261008`;
previous kernels and the Windows route are retained.

## Build and test

```sh
python3 kernel/rc5-20261013/verify.py /path/to/linux
JOBS=4 ./kernel/rc5-20261013/build.sh /path/to/linux /path/to/new-output
```

Use matching Image, modules, DTB and initramfs, including board ADSP firmware
and audio topology. See [build instructions](kernel/rc5-20261013/README.md),
[firmware requirements](firmware/README.md) and [contribution guidance](CONTRIBUTING.md).

The tested GRUB setup loads an explicit DTB and needs top-level `insmod fdt`.
Preserve a bootable fallback; old DTS/DTB snapshots and [live-image tooling](iso/README.md)
are separate from the current package.

## Reference

- [Hardware](docs/hardware.md) and [historical modifications](docs/modifications.md)
- [Changelog](CHANGELOG.md) and [documentation index](docs/README.md)
- [Kernel packages](kernel/README.md) and [upstream credits](UPSTREAM-CREDITS.md)

This project is AI-assisted; the maintainer is not a kernel developer. Hardware
tests determine acceptance, and corrections remain in the project history.
Kernel-derived sources are **GPL-2.0-only**; see [LICENSE](LICENSE).
This is unofficial research, not endorsed by ASUS or Qualcomm.
