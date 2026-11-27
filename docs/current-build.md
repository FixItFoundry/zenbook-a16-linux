# Current build — 2026-11-27

The A16 runs Fedora with **`7.3.0-ZenbookA16-20261022-final1-a16pkg12+`**, built
from the 201-patch stable queue (`c9073bc3daaf012b47e5c0631316308f4a3f3a7c`) on
November 27 and promoted to the default GRUB entry (`fedora`). Revision 8 remains
installed in the `Test DTBs` fallback submenu.

Compared to revision 8, revision 12 drops legacy `0062` (refreshes `0120`), adds
Ritesh Kumar's Glymur DP PHY v8 series (`0162`–`0169`), moves HDMI HPD pinctrl
to `&mdss_dp2` (`0170`), carries 27 fixes from Michi (`@scalpel4k`)'s openSUSE
`kernel-qcom-laptops` stack (`0171`–`0197`, including `MODULE_FIRMWARE`
declarations, `hid-asus` `fnlock_default`, Qualcomm `qcom-7.3` `iris` video,
SCMI `memlat`, `SPEL`, Type-C/DP/USB3/Wi-Fi fixes), links Glymur DPU mixers
`LM_4`–`LM_7` to `DSPP_4`–`DSPP_7` (`0198`), and adds four `iris` fixes
(`0199`–`0202`: suspend deadlock, removal work cancel, timeout firmware reload,
and firmware-reported output buffer count). Kconfig enables
`CONFIG_CLK_GLYMUR_VIDEOCC=m`, `CONFIG_QCOM_SCMI_GENERIC_EXT=m`,
`CONFIG_DEVFREQ_GOV_REMOTE=m`, `CONFIG_SCMI_QCOM_MEMLAT_DEVFREQ=m`,
`CONFIG_QCOM_SPEL=m`, `CONFIG_NETCONSOLE_EXTENDED_LOG=y`, and the buddy
hardlockup detector.

Validation on boot `f3bdc616` (`taint=0`, 0 failed units, 0 oops, `btrfs device
stats /` all 0, `0005:00:00.0` and `0005:01:00.0` PCIe AER 0):

- **Three displays from power-on:** `eDP-1` (2880x1800@120), `DP-1` USB-C glasses
  (1920x1080@120), and `HDMI-A-1` (1920x1080@60) came up enabled with
  `dpu_refusals=0` and `phy_poweron_err=0`; Jesse confirmed clean picture on all
  three simultaneously. Verified DPMS off/on cycles: `HDMI-A-1` 10/10 (`bad=0`),
  `DP-1` 10/10 (`bad=0`), `eDP-1` 20/20 (`bad=1`, cycle 2 channel-EQ retry
  recovered cleanly).
- **Hardware video (`iris`):** H264/HEVC/VP9 decode bit-exact with software;
  GStreamer 60x alternating decode `bad=0/60`; 5/5 forced firmware hangs
  recovered with bit-exact follow-up decodes; 20/20 FFmpeg H264 encodes
  (`short=0`, `hung=0`); clean runtime suspend afterwards (`taint=0`, no D-state
  tasks).
- **USB3, peripherals, power:** 2x128 MiB read-only check on a 64 GB USB3 drive
  through a VIA USB-C hub passed (`match=OK`, 54.9 / 88.3 MB/s, 0 real USB
  errors). Wi-Fi (0% loss), Bluetooth (20 devices), upstream `MM1`/`MM2` audio
  playback and mic capture, both cameras (20/20 frames each), Adreno X2-90, EC,
  `memlat` (DDR/LLCC devfreq), and `SPEL` (15.9 W idle / 62.3 W load) all passed.
- **Load/idle soak (24 rounds, `memlat` active, 3 displays connected):** 12
  balanced rounds (2.92/3.63 GHz, peak 91 °C CPU / 42 °C NVMe) and 12 uncapped
  boost rounds (4.72 GHz, peak 95 °C CPU / 41 °C NVMe) completed with 0 resets,
  0/0 PCIe AER, `taint=0`, and 0 Btrfs errors.

Remaining limits and open items:

- **USB-C hub resets under load:** during the 24-round soak, the VIA USB-C hub
  carrying PD pass-through (`usb 6-1`) reset 10 times strictly during load
  (2× balanced, 8× boost, 0× idle), and the glasses HID (`usb 3-1`)
  re-enumerated 3×; PD rail sag vs USB PHY margin under load is untested.
- **Stability not accepted:** 24 clean rounds do not resolve the historical
  unexplained silent resets (~1 in 52 rounds on revision 8), nor an intermittent
  `0005:00:00.0` NVMe PCIe AER storm observed once on revision 11 (did not
  reproduce on revision 12's build, validation, or soak).
- **Not yet tested on revision 12:** physical cable hotplug/unplug cycles, 4K60,
  suspend/resume, native `dnf`/`apt` transactions, and Ubuntu DEB installation.

| Track | Patches | Replayed source tree | Package release | State |
|---|---:|---|---|---|
| stable | 201 | `c9073bc3daaf012b47e5c0631316308f4a3f3a7c` | `7.3.0-ZenbookA16-20261022-final1-a16pkg12+` | Built, installed, default |
| rc | 114 | `ae9780ba94c73237250a58ecc44fca2485813f8a` | `7.4.0-rc1-next-20261103-zenbook-a16-a16pkg6+` | Built, staged in `Test DTBs` |

## Revision 8 — 2026-11-21

The A16 ran Fedora with **`7.3.0-ZenbookA16-20261022-final1-a16pkg8+`**, built
from the 161-patch stable queue on November 21. It added the X1E80100 lite CSID
fixes (`0159`–`0160`) and the full Glymur CAMSS tables (`0161`) to revision 7.
Revision 8 remains installed in `Test DTBs` as the fallback entry.

On the first boot of revision 8, the display (2880x1800 at 120 Hz), Wi-Fi,
Bluetooth and playback came up with no failed units and an untainted kernel.
The camera graph has CSIDs 0–3 and VFEs 0–3. The HM1092 IR sensor streamed
8 frames through each of the four CSID/VFE pairs and the OV02C10 RGB sensor
through LITE1, `cam` captured from both cameras, and IR frame brightness
followed the emitter (0/80/255/0: 26.7/34.3/44.2/28.3 mean). In 20 Hyprland
DPMS off/on cycles, 3 trainings failed channel equalisation and recovered; the
panel ended at 2880x1800 at 120 Hz. The unexplained resets seen on revisions 6
and 7 are not resolved, so stability is not accepted.

Revision 5 was built without the nine display, Bluetooth, M.2 and camera patches
and is superseded. Native `dnf`/`apt` transactions, sleep and RTC behaviour are
not accepted. Hardware-free CI does not establish native ARM64 installation.
The dated records below retain their original identities and limits.

## Revision 7 — 2026-11-15

The A16 runs Fedora with **`7.3.0-ZenbookA16-20261022-final1-a16pkg7+`**, built
from the 158-patch stable queue and staged by hand on November 14. It adds the
HM1092 `.set_fmt`, PMH0101 IR emitter and eDP link fallback patches
(`0156`–`0158`) to revision 6. Revision 6 remains installed as the fallback entry.

On the first boot of revision 7, the display (2880x1800 at 120 Hz), Wi-Fi,
Bluetooth and speakers came up with no failed units and an untainted kernel.
`cam` captured RGB frames, and IR frame brightness followed the emitter
(0/80/255/0: 27.9/33.1/37.4/25.8 mean). In 100 Hyprland DPMS off/on cycles, all
112 stream starts trained at 4 lanes; 12 cycles retried after a channel
equalisation failure (11 once, 1 twice). The unexplained resets seen on
revision 6 are not resolved, so stability is not accepted.

## Historical running build — 2026-10-31

The A16 was running **`7.3.0-7-omarchy`** with the local DSP test boot entry.
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

- **`stable` (`7.3.0-ZenbookA16-20261022-final1+`)**: Replays 155 patches to `bd1327aac6e1431668eaa53f69e5867d3400b4a0`. Built as package revision 6 on November 12. It boots on the A16 with the display and Wi-Fi working; an unexplained reset between two boots is unresolved, so stability is not accepted.
- **`rc` (`7.4.0-rc1-next-20261103-zenbook-a16+`)**: Replays 112 patches to `ed1c21244abbeae943f39c5a4824ea05c1c613ba` on next-20261103. Built as package revision 6 on November 12 and verified off the device; not installed or booted.
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
- Bluetooth pairing and traffic remain unvalidated on revision 6. Builds before the November 12 queues reported missing `qca/clnbtfw10.tlv` and ran on ROM firmware.
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
