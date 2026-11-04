# Current build — 2026-10-31

The A16 is running **`7.3.0-7-omarchy`** with the local DSP test boot entry.
Read-only inspection confirmed running ADSP/CDSP, attached SoCCP and no failed
system units. The internal HDMI PHY still logs clock-enable failures; camera
and TPM device nodes are absent. This does not establish stock-install,
LUKS-unlock or full hardware acceptance. See [Omarchy status](omarchy-status.md).

## Current rc5 review overlays — 2026-10-31

The current development build starts with the rc5 camera/microphone tree
`622916bf1849749a5aa3cdbccf5179de4423ae76`, not the 7.3-final port.
The review build applies the [GDSC failed-registration RFC](../archive/patches/standalone/glymur-gdsc-genpd-teardown-UPSTREAM.patch),
then the two AudioReach/Q6DMA channel-map patches (now integrated into [`patches/stable/0114`–`0115`](../patches/stable/series)).
These are local review overlays; the dated build recipes and source queues retain
their original identities. The combined source tree is
`71c7dcd30f6560a4deb98e2dc889927b7b21efe3`.

**GDSC promotion is blocked by same-object reprobe.** The real-kernel QEMU
failure matrix reports 36 errors on the baseline and zero on the patched
52-trial run. Reusing the same domains after successful unregister triggers
kobject initialization warnings on both versions. Retrying after the patched
failed-registration cleanup also triggers those warnings and returned
`-EEXIST` in the observed run. The cleanup fixes the registration leak, but
this does not establish a durable retry path. No physical A16 test was run.

The audio backports reuse `q6dsp_map_channels()` and clear unused explicit TX/RX
map entries. The helper supports 1–6 and 8 channels, maps mono to front-center,
and rejects 7 channels. The rc5 UCM still matches its own MultiMedia2/4 topology
and PCM devices 1/3. Omarchy's Glymur CRD topology uses MultiMedia1/2 and PCM
devices 0/1, so its UCM routing cannot be copied onto this rc5 topology.
The four-channel capture workaround remains until the new kernel passes
physical capture and playback checks. See [upstream credits](../UPSTREAM-CREDITS.md)
for the two audio authors and backport scope.

## Transition targets — 2026-11-03

Stable targets Linux 7.3 final ([`kernel/stable`](../kernel/stable/README.md)); the `rc` development track ([`kernel/rc`](../kernel/rc/README.md)) targets **Linux `v7.4-rc1` `linux-next` (`next-20261103`, `d6bcfc94eb4da6e089c5473970cd96727292fd97`)**.

- **`stable` (`7.3.0-ZenbookA16-20261022-final1+`)**: Replays 143 patches to `11f818cf609ff60e6f826f47e757f939b5442adc` (`004cf498d432dba102ea3d4c9f9389446d40c1bd` prior to patch `0143`) and has completed full ARM64 `Image` + modules + DTB + Fedora `aarch64` RPM compilation and KVM CI validation; physical boot acceptance on the laptop is next.
- **`rc` (`7.4.0-rc1-next-20261103-zenbook-a16+`)**: Rebased onto `next-20261103` (`d6bcfc94eb4da6e089c5473970cd96727292fd97` on `v7.4-rc1` `6628e7d4c6b25c8d18f1345e3a20d21829aae7e4`), retiring 45 upstreamed patches ([`patches/rc/port-map.json`](../patches/rc/port-map.json)), adapting 14 patches, and adding `localversion-next` removal plus Abel Vesa's Adreno X2-85 CLX revert (`d448c66b9e47`) to produce a 100-patch queue (`f5c8bd36414eae4cea1cd2c0bf51de2ccf3b5caa`). Forward/reverse replay, ARM64 `Image`/`Image.gz`/modules/DTB (`qcom,keep-runtime-active;` and `snps,resume-hs-terminations;`), portable bundle, Fedora `aarch64` RPMs, and disposable KVM guest package lifecycle checks are verified on `.19`.
- The retired `v7.3-rc5` layered RC recipe (`7.3.0-rc5-ZenbookA16-20261022-a16pkg3+` / `20261031-usb1+`) is archived under [`archive/kernel/rc5-20261031/`](../archive/kernel/rc5-20261031/README.md) and [`archive/patches/rc5-20261031/`](../archive/patches/rc5-20261031/README.md).
The [track policy](kernel-tracks.md) records the two-track packaging architecture and release checks.
The dated Omarchy and Fedora records below retain their separate acceptance scopes.

## Historical Omarchy candidate — 2026-10-21

The **`7.2.8-24-omarchy` candidate**, source tree `d05c4879b3789c74e2a73684683b15deb0be258b`, completed the dated build, package, boot and hardware checks recorded in [Omarchy status](omarchy-status.md#revision-24-evidence--2026-10-21). These results do not validate the different source and boot settings in the current `7.3-7` package.

The Fedora soc2 baseline below and the [rc Qualcomm bridge](../kernel/rc/README.md) are separate kernel tracks. Omarchy results do not establish acceptance of the bridge. The retained `kernel/arch-7.2.10/` package is an earlier backport, not the current shared Omarchy recipe.

## Fedora soc2 baseline — 2026-10-14

**`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+` is the retained Fedora baseline.** The dated observations below describe that build and boot; they do not describe the newer Omarchy candidate or the laptop’s current boot selection.

## Identity

| Field | Value |
|---|---|
| Base | Linux v7.3-rc5, `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e` |
| Source commit | `80849361fb38a8adc11dd66f1d6856260d98e01b` |
| Source tree | `e3af70b5403334c7d762fdb00b0a7cdfbb5a362c` |
| Source package | [64 patches](../patches/rc/base/README.md), [config and build helper](../archive/kernel/rc5-20261013/README.md) |
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
This historical publication did not rebuild, install or select a boot entry.
The 2026-10-31 review builds above are separate artifacts.
