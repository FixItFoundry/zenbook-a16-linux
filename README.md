# Linux on the ASUS Zenbook A16

Mainline-based Linux bring-up for the **ASUS Zenbook A16 UX3607OA**, powered by
Qualcomm Snapdragon X2 Elite Extreme (`glymur`).

![Zenbook A16 running Linux](img/screenshot_20260816_080455.png)

## Current status — 2026-10-12

**The RC5 audio test kernel is now the working bring-up baseline:**
`7.3.0-rc5-ZenbookA16-20261008-rc5-audiopm1+` (Linux `v7.3-rc5`).

The current build boots into a graphical desktop, and all four physical
speaker channels have been confirmed working. USB0 hub Ethernet and USB-PD
charging were verified, and a short CPU/Vulkan test passed on AC power.

Audio currently relies on a board-specific workaround that keeps both
SoundWire speaker controllers active. Repeated cold-boot and idle/playback
checks, the workaround's battery cost, suspend/resume and long-duration
stability remain open. Historical spontaneous resets and RPMh timeouts are
still unresolved, so this is a working development baseline with limited
validation.

The repository now includes the exact build configuration and complete
59-patch stack. Source replay reproduces the tested tree, and all 8,469
recorded installed payload hashes match. See the [current build
record](docs/current-build.md) for evidence and limits.

| Area | Current position |
|---|---|
| Speakers | All four physical channels confirmed working. Both controllers remain active; repeated boot/idle checks and efficient audio power management remain open. |
| Display and GPU | Internal desktop and a 600-frame Vulkan test passed. External displays and repeated GPU runtime resume remain unvalidated. |
| CPU and cooling | A guarded 95-second CPU/Vulkan test passed on AC, peaking at 50.5 °C with no new kernel messages or monitored PCIe errors. Sustained stability and physical fan response remain open. |
| Battery and charging | USB-PD power and battery charging verified. Battery drain and AC/battery transitions remain unvalidated. |
| USB0 | SuperSpeed network hub and Ethernet verified with a short gateway traffic test. Sustained traffic and idle/resume remain open. |
| USB1 | Hub enumeration has failed in earlier testing. Both cable orientations, stable carrier/traffic and idle/resume still need validation. |
| Wi-Fi | Device available; sustained traffic, reconnect and recovery on this kernel remain unvalidated. |
| Bluetooth | The current boot reports missing `qca/hmtbtfw11.tlv`; pairing and traffic remain unvalidated. |
| Embedded Controller | EC v3 and HID keyboard-backlight ownership retained; the accepted boot uses fan profile 2. |
| Microphones and other audio | Recording, headset/jack, Bluetooth audio and DP audio remain unvalidated on this build. |
| Suspend/hibernate | Unresolved; no successful system-sleep acceptance for this baseline. |
| Camera | Camera/CSI changes are included in the source stack, but camera drivers are blacklisted in the accepted boot. Capture remains unvalidated. |
| HDMI and USB4 | Not validated as working on this baseline. |

This promotion updates the repository baseline. The saved GRUB default remains
`zenbook-a16-rc5-integrated1-20261002`; the current kernel uses the existing
audiopm1 test entry. Previous kernels and the Windows boot route are retained.

### Retained EC integration

Konrad Dybcio's ASUS Zenbook A16 EC v3 series and the local change preserving
keyboard-backlight ownership under the ASUS HID driver remain in the current
stack as patches 24–27. Their earlier daily-use validation is recorded in the
[EC integration notes](patches/rc3-ec-v3-hid-20260923/README.md);
current-kernel acceptance limits are listed above.

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
