# Current build — 2026-10-21

The latest validated **Omarchy candidate is `7.2.8-24-omarchy`**, with source tree `d05c4879b3789c74e2a73684683b15deb0be258b`. It completed native build, package, boot and hardware validation and is still running on the A16; the package recipes and runtime/ISO follow-ups are still awaiting submission and publication. See [Omarchy status and submission order](omarchy-status.md) for the exact scope and limits.

The Fedora soc2 baseline below and the [rc5 Qualcomm bridge](../kernel/rc5-qcom-bridge-20261018/README.md) are separate kernel tracks. Omarchy results do not establish acceptance of the bridge. The retained `kernel/arch-7.2.10/` package is an earlier backport, not the current shared Omarchy recipe.

## Fedora soc2 baseline — 2026-10-14

**`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+` is the retained Fedora baseline.** The dated observations below describe that build and boot; they do not describe the newer Omarchy candidate or the laptop’s current boot selection.

## Identity

| Field | Value |
|---|---|
| Base | Linux v7.3-rc5, `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e` |
| Source commit | `80849361fb38a8adc11dd66f1d6856260d98e01b` |
| Source tree | `e3af70b5403334c7d762fdb00b0a7cdfbb5a362c` |
| Source package | [64 patches](../patches/rc5-20261013/README.md), [config and build helper](../kernel/rc5-20261013/README.md) |
| Config SHA256 | `c41128086a5423948700342a853e26698754923827d6151951bbfdca869484c2` |
| Build compiler | GCC 15.2.0, Ubuntu `15.2.0-16ubuntu1` |
| Ordinary boot | `c847468f-0ae1-4278-82ce-8b5bf2414d0e` |
| Host | ASUS UX3607OA / glymur; Fedora 44 aarch64 |
| Root and fan | Btrfs subvolume `a16-audio-test4-20260919` (259); EC fan profile 2 |

The complete series replays to the tested tree. The prior 59 patches are unchanged;
patches 60–64 preserve the five soc2 source commits. The [October 12](build-20261012.md)
and [October 2](build-20261002.md) records remain historical.

## Validation

| Scope | Result |
|---|---|
| Ordinary boot | Release, root, DT and ordinary entry match; recovery cache flags are absent. |
| Installed artifacts | 8,487 file hashes, 233 candidate/fallback boot files and nine boot configuration files match; 201 loaded modules match their installed metadata. |
| Btrfs | Original incorrect-extent-count error absent; all five device counters zero. The affected free-space group has the expected two extents. |
| Current health | No failed units; kernel taint and sampled PCIe AER counters zero. Kernel journal unchanged between captures through 22 minutes uptime. |
| Wi-Fi and power | 20/20 gateway replies, zero loss; USB-PD online, battery reports Not charging. |
| Audio | Four SoundWire devices attached; both controllers runtime active with DT keep-active opt-ins. User accepted the retained RC3-era workaround mechanism; no fresh listening test. |
| Prior recovery boot, same binaries | Read-only 615.68 GiB scrub completed in 23 minutes with zero errors; one CPU worker for 30.02 seconds and 600 Vulkan frames passed, peaking at 45.9 C. |
| Prior physical checks | User confirmed display, keyboard and touchpad on the recovery boot, and four speakers on the first soc2 boot. USB0 previously passed SuperSpeed Ethernet and 20 gateway replies; one hub reset remains unexplained. |
| Build and source tests | Full soc2 build passed; 21 warnings, none in changed files. Eleven native source-test suites passed; these were not rerun on the ordinary boot. |

The Btrfs error predates soc2. A one-time free-space-cache rebuild cleared the
observed inconsistency across an ordinary reboot; this is not a soc2 kernel fix.
The original cause is unproven; no offline structural check or backup verification was performed.

## Remaining limits

- USB1 SuperSpeed still fails with `-71`; only a USB2 hub appears. Both-orientation carrier and sustained traffic remain unaccepted.
- Bluetooth reports missing `qca/clnbtfw10.tlv`; peer pairing and traffic remain unvalidated. This message alone does not prove total Bluetooth failure.
- Suspend/hibernate, efficient audio PM, battery life, repeated cold-boot/idle/playback checks and long-duration stability remain open. Historical resets and RPMh timeouts are unresolved.
- Physical fan response, external displays/HDMI/USB4, camera capture, microphones and other audio routes remain unaccepted.

## Boot and rollback

The tested ordinary entry is `zenbook-a16-rc5-soc2-fan2-20261014`. The saved
GRUB default remains `zenbook-a16-rc5-audiopm1-fan2-20261008`; no next boot is
armed, and previous kernels, EFI order and Windows entry are preserved.

Firmware reads boot files from the Btrfs top level while Linux mounts the audio-test4
subvolume. Verify all boot surfaces when installing; changing the running root's
`/boot` alone is insufficient. Kernel rollback does not undo filesystem metadata.

The tested command line retains `clk_ignore_unused`, `pd_ignore_unused`,
`cma=128M`, `glymur_pci_skip=5`, `selinux=0`, fan profile 2 and the
`i2c_qcom_cci,qcom_camss,ov02c10` blacklist. These are part of the tested setup.
This publication changes repository files only; it does not rebuild, install or select a boot entry.
