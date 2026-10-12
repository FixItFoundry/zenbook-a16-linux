# Linux on the ASUS Zenbook A16

Mainline-based Linux bring-up for the **ASUS Zenbook A16 UX3607OA**, powered by
Qualcomm Snapdragon X2 Elite Extreme (`glymur`).

![Zenbook A16 running Linux](img/screenshot_20260816_080455.png)

## Current status — 2026-10-12

**Working audio bringup baseline:
`7.3.0-rc5-ZenbookA16-20261008-rc5-audiopm1+` (Linux `v7.3-rc5`).**

This kernel is booted, its installed artifacts match, and the user confirmed
all four physical speaker channels. A guarded CPU/Vulkan screen passed on AC.
Both speaker controllers stay runtime active through a local workaround;
efficient audio power management, suspend and long-duration stability remain
open. The [current build record](docs/current-build.md) contains the precise
evidence and limits. The saved GRUB default and fallback kernels are retained.

| Area | Current position |
|---|---|
| Display and GPU | Internal graphical session and 600-frame Vulkan screen passed; repeated runtime resume and external display remain open. |
| CPU and thermal | Short guarded workload passed: peak 50.5 C, no new kernel messages or monitored AER errors. Historical spontaneous resets and RPMh timeouts remain unresolved. |
| Embedded Controller | EC v3 and HID keyboard-backlight ownership retained; this boot uses fan profile 2. Sustained cooling and physical fan acceptance remain open. |
| Wi-Fi | Device available; sustained current-kernel traffic, reconnect and recovery remain unvalidated. |
| Bluetooth | Current boot reports missing `qca/hmtbtfw11.tlv`; pairing and traffic are unvalidated. |
| Battery and charging | USB-PD online and battery charging verified. Battery drain and power transitions remain open. |
| Speakers | All four channels physically confirmed. Both SoundWire controllers are kept active; cold-boot/idle repetition and efficient runtime PM remain open. |
| Microphones and other audio | Recording, headset/jack and Bluetooth audio remain unvalidated on this build. |
| USB | USB0 hub Ethernet passed a short traffic check. USB1 both-orientation carrier/traffic and idle/resume remain open. |
| Suspend/hibernate | Unresolved; no successful system-sleep acceptance in this promotion. |
| Camera | Camera/CSI source is included for exact reproduction, but camera drivers are blacklisted in the accepted boot. Capture remains unvalidated. |
| HDMI, USB4 and DP audio | Not accepted by this promotion; see the hardware reference. |

### EC v3 promotion

The ASUS Zenbook A16 EC v3 series from Konrad Dybcio, paired with our local
patch leaving keyboard-backlight ownership with the ASUS HID driver
([`patches/rc3-ec-v3-hid-20260923/`](patches/rc3-ec-v3-hid-20260923/README.md)),
has been validated in daily use on the test kernels (`usbdiag2ecv3hid1+`, `usb1hubdiag1+`)
and is promoted into the baseline stack, in `patches/rc5-20261002/` as patches 24-27.

## Start here

- [Current build and validation limits](docs/current-build.md)
- [Hardware reference](docs/hardware.md)
- [Changes and historical corrections](CHANGELOG.md)
- [Kernel and device-tree modifications](docs/modifications.md)
- [Upstream credits](UPSTREAM-CREDITS.md)
- [Contributing](CONTRIBUTING.md)

The current-build record takes precedence over older success claims in component
notes. Historical results describe their original kernel, not a retest of the current baseline.

## Next priorities

1. Repeat four-speaker cold-boot and idle/playback acceptance, then investigate efficient audio runtime PM as a separate controlled change.
2. Continue guarded CPU/GPU, RPMh and cooling validation on AC and battery with durable fault capture.
3. Validate runtime/system resume and USB1 orientations while preserving known boot and rollback routes.
4. Continue camera bring-up separately from this audio baseline.

## Building and booting

The [RC5 build package](kernel/rc5-20261008/README.md) contains the exact config,
an ordered 59-patch series, checksums and a source-tree replay verifier.
[The build record](docs/current-build.md) covers integration and validation.
The [RC3 package](kernel/rc3-20260919/README.md) reproduces the proven fallback
kernel. The older [`next-20260817` series](patches/next-20260817/), merged DTS
snapshots and prebuilt DTBs are historical references, not substitutes.

Use matching kernel, modules, DTB and initramfs artifacts. Include the board's
ADSP firmware and audio topology in the initramfs. Most required blobs are now
in upstream linux-firmware; see [firmware guidance](firmware/README.md).

The tested GRUB setup loads an explicit DTB and requires top-level `insmod fdt`.
Audit the live boot path, back up its source configuration outside `/etc/grub.d/`,
and review a generated configuration diff before installing it. Retain a
known-good fallback and use a distinct release for each hardware experiment.

[Live-image tooling](iso/README.md) is a separate track; it is not validation
of the current laptop baseline.

## AI assistance

**This project is AI-assisted, and I am not a kernel developer.** AI helps with
analysis, device-tree work and documentation; hardware tests determine whether
a change works. Incorrect conclusions are retained with corrections in the
project history. Reviews and reproducible bug reports are welcome.

## Repository layout

| Directory | Contents |
|---|---|
| `dts/`, `prebuilt/` | Board sources and historical DTB snapshots |
| `kernel/`, `patches/` | Build guidance, backports and local experiments |
| `boot-kit/` | Boot tooling and example configurations |
| `tweaks/` | Userspace configuration; retired workarounds are kept separately |
| `scripts/` | Hardware checks and diagnostic tools |
| `docs/` | Component reference and build status |
| `iso/` | Live-image assembly tooling |
| `firmware/` | Firmware requirements and extraction guidance |

Patch filenames alone do not establish upstream readiness or hardware validation.

## Credits and license

See [UPSTREAM-CREDITS.md](UPSTREAM-CREDITS.md) for authorship and provenance.

Kernel-derived sources are **GPL-2.0-only**; see [LICENSE](LICENSE).
This is unofficial interoperability research, not endorsed by ASUS or Qualcomm.
Experimental kernels and device trees can make the machine unbootable; keep a
recovery path.
