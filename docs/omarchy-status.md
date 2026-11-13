# Omarchy A16 status — 2026-11-13

**A16 board support is in the shared `linux-omarchy` kernel.** The
[`linux-omarchy-aarch64` recipe](https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/linux-omarchy-aarch64)
is at `7.3-59` on Linux 7.3. It is one kernel for many Snapdragon and
NVIDIA N1x machines, so every shared-driver change in it runs on all of them.
The A16 firmware, audio and runtime setup packages are merged. On Omarchy,
install those packages; the Fedora/Ubuntu packages in this repository are a
separate path. Publication was last checked against the edge index on October 31,
at `7.3-7`; the hardware record below is from that date and has not been repeated
on the current revision.

## What the shared kernel carries for the A16 — checked 2026-11-13

| Omarchy patches | Purpose | Relation to this repository's `stable` queue |
|---|---|---|
| `2500`–`2502` | EC driver and board tree, QCC2072 power sequencing, EFI and battery fixes | Cut down from this repository's work in #1426. Bluetooth is described on a WCN7850 power sequencer; `stable` now uses the M.2 connector (`0154`). |
| `2330`–`2331`, `2340`–`2346` | v8 eDP PHY power-on and tuning | `stable` carries only the first two (`0002`, `0003`). |
| `2367`–`2371` | eDP 1.4 rate-set selection | `2367` is this repository's `0001` without the `LINK_BW_SET` write. `2369` covers `0148`–`0149`. `2368`, `2370` and `2371` have no equivalent here. |
| `2379`, `2385`–`2388` | M.2 Bluetooth through pwrseq, BD address | `stable` carries `2379`'s source patch as `0153` plus the QCC2072 series (`0150`–`0152`), which Omarchy does not carry. |
| `2438`, `2439` | Speaker resume on v3.1.0 SoundWire controllers, A16 volume ceiling | `stable` instead keeps the controllers runtime-active (`0058`) and carries a larger local SoundWire change (`0009`). |
| `2840` | Glymur USB3 PHY settings | Same patch as `stable` `0143`. |

Not in the shared kernel: this repository's camera stack, GLINK RTC, TPM/QTEE,
EC fan profile selection and the QCC2072 Bluetooth series. A result on one
kernel does not validate the other: confirm the actual kernel, DTB, firmware,
initramfs and command line before making a boot or feature claim.

## Hardware record — 2026-10-31

Read-only inspection on October 31 confirmed the A16 running `7.3.0-7-omarchy`, with kernel/headers `7.3-7`, audio `1-1` and firmware `1.312.4500.0-1`. ADSP and CDSP were running, SoCCP was attached, and no system units were failed. The boot uses the local `omarchy.a16.dsp-test=1` entry; this is not acceptance of a stock installed boot or a fresh LUKS unlock test. Sleep remains disabled by systemd policy.

The current boot logged 14 `gcc_usb3_tert_phy_com_aux_clk` warnings on the internal HDMI PHY path. Camera and TPM device nodes were absent. Audio capture/playback, HDMI output, Bluetooth traffic and suspend were not physically tested in this inspection. The `7.2.8-24` results below remain historical evidence from October 21.

## Merged and published upstream

| Component | Verified state on October 31 |
|---|---|
| Shared ARM kernel | [omarchy-pkgs #1875](https://github.com/omacom/omarchy-pkgs/pull/1875) merged as `3659b4671149c0cc458f4bd2d9d9b021c0539d13`; `linux-omarchy` and `linux-omarchy-headers` `7.3-7` are published on edge. It includes EC/board support and A16 power, cooling, RTC and microphone-rate changes. |
| Board firmware | [omarchy-pkgs #1874](https://github.com/omacom/omarchy-pkgs/pull/1874) merged; `asus-zenbook-a16-firmware` `1.312.4500.0-1` is published on edge. It extracts A16 ADSP/CDSP firmware and QCC2072 Wi-Fi board data from ASUS’s public BSP. |
| Audio | [omarchy-pkgs #1841](https://github.com/omacom/omarchy-pkgs/pull/1841) supplies `asus-zenbook-a16-audio` `1-1`, published on edge. [#1842](https://github.com/omacom/omarchy-pkgs/pull/1842) added kernel speaker fixes, and [omarchy #17039](https://github.com/omacom/omarchy/pull/17039) added board-matched installation and speaker tuning. All three are merged. |
| Early disk unlock | [omarchy #16940](https://github.com/omacom/omarchy/pull/16940) merged: generic Glymur pin-control and interconnect modules before disk unlock. |
| Live-image prerequisites | [omarchy-iso #358](https://github.com/omacom/omarchy-iso/pull/358) merged: Glymur live-image drivers and console settings. This does not by itself establish A16 installed-boot acceptance. |

Publication was checked against the [edge aarch64 package index](https://pkgs.omarchy.org/edge/aarch64/omarchy.db). The shared recipe is [`pkgbuilds/linux-omarchy-aarch64`](https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/linux-omarchy-aarch64). `edge`, `rc` and `stable` are package channels; `rc` does not mean a separate Linux release-candidate kernel. These edge results do not establish promotion to the other channels.

The packaged firmware replaces Windows/BitLocker extraction as the proposed default A16 firmware source. Its Wi-Fi `board.bin` fallback is specific to UX3607OA and must not be installed on unrelated QCC2072 machines. The pending runtime change installs this package before the shared DSP firmware guard runs and includes it on the offline package list.

## Remaining upstream work

| PR | Current state and scope |
|---|---|
| [omarchy #17083](https://github.com/omacom/omarchy/pull/17083) | Merged on November 1: A16 firmware installation, disk unlock and sleep setup. Hardware validation of a stock install on the current kernel has not been recorded here. |
| [omarchy-pkgs #1428](https://github.com/omacom/omarchy-pkgs/pull/1428) | Open: preserve mkinitcpio wrapper failures. This is independent of the A16 kernel; outstanding package/architecture validation remains separate. |

Do not submit another broad kernel or runtime bringup over these changes. Start from current upstream and isolate any remaining omission or regression. The published kernel differs from the historical local series, including Wi-Fi/USB and shared-driver changes; earlier local build or hardware results do not validate that different code. Confirm the actual kernel, DTB, firmware, initramfs and command line before making new boot or feature claims.

## Retired proposals

| PR | Disposition |
|---|---|
| [omarchy-pkgs #1426](https://github.com/omacom/omarchy-pkgs/pull/1426) | Closed unmerged; the broad kernel proposal is superseded by the current shared kernel. |
| [omarchy #13820](https://github.com/omacom/omarchy/pull/13820) | Closed: the older `7.2.8-24` support-package/DSP-ABI setup is superseded by the current runtime direction. |
| [omarchy-iso #208](https://github.com/omacom/omarchy-iso/pull/208) | Closed: the broad Windows-extraction preflight no longer matches the packaged-firmware path. Remaining live-boot work should build on merged #358. |
| [omarchy-pkgs #1427](https://github.com/omacom/omarchy-pkgs/pull/1427) | Closed from the A16 series. Generic read-only BitLocker extraction would need its own consumer and coordination with [#1795](https://github.com/omacom/omarchy-pkgs/pull/1795). |
| [omarchy-pkgs #1429](https://github.com/omacom/omarchy-pkgs/pull/1429) | Closed alongside #1427. Dislocker is no longer a prerequisite of the proposed A16 installation path. |

The private `omarchy-a16-support`/`omarchy-a16-dsp-abi=1` package sequence describes the retired proposal, not prerequisites of the new upstream packages. Migrating a machine that still carries those private boot settings requires separate review; this page does not prescribe an upgrade or change the running machine.

## Kernel tracks

| Track | Identity and role |
|---|---|
| Current upstream Omarchy | Shared `linux-omarchy`, recipe at `7.3-59` on November 13. `7.3-7` was running with the local DSP test boot settings on October 31. Stock installation and full hardware acceptance remain open. |
| Historical Omarchy candidate | `7.2.8-24-omarchy`, source tree `d05c4879b3789c74e2a73684683b15deb0be258b`; the October 21 build and hardware evidence is retained below. |
| Retained Fedora soc2 baseline | `7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+`; see the dated [Fedora acceptance record](current-build.md#fedora-soc2-baseline--2026-10-14). |
| Fedora/Ubuntu tracks | [`kernel/stable`](../kernel/stable/README.md) and [`kernel/rc`](../kernel/rc/README.md); separate from the shared kernel. Omarchy acceptance does not transfer to these builds, or the reverse. |
| Earlier Arch port | [arch-7.2.10](../kernel/arch-7.2.10/BUILD-AND-UPGRADE.txt); retained reference, not the current shared Omarchy recipe. |

## Revision 24 evidence — 2026-10-21

- Clean native A16 build; all 8,487 packaged modules checked; an external module compiled against the packaged headers. The distributed source package replayed to the tree above.
- Kernel and headers `7.2.8-24`, support `20261014-1` and firmware extractor `1-6` installed. Both generated normal/rescue UKIs matched the kernel and A16 DTB and passed 26 targeted module dry runs each.
- Physical boot `1e110042-6ff5-4f7e-b2ea-63b08dad6d8e` ran revision 24. ADSP/CDSP started before root mounted and remained running; SoCCP was attached. No failed units, deferred devices or kernel taint were recorded.
- The initramfs log was empty with early logging enabled. The previous modprobe errors and four battery uevent errors were absent. Root was writable and all five Btrfs device-error counters were zero.
- The compiled battery before/after regression, runtime board/DSP shell checks, all 25 support verifier tests and support initramfs checks passed.
- Jesse physically confirmed audio playback, keyboard, touchscreen, charger transitions and Bluetooth phone calls/audio. Built-in microphone capture was not separately confirmed.

The physical test used an enclosure-specific UAS fallback for an external root SSD after transport failures. This is a local test condition, not an A16 board default or an established fix for internal NVMe installations. That candidate contained no such quirk. Four PMIC supplier-link warnings and a codec workqueue deprecation warning remained in the recorded tests; no clean-log or long-term stability claim was made.

## Historical installation evidence and feature limits

Revision 21 was the initial installation test kernel, covering ARM UEFI live boot, generic/N1x-mode VM install/reboot checks and physical A16 installation. After debugging, the A16 moved to revision 24 and completed the build, package, boot and hardware validation recorded above.

Read-only firmware extraction was exercised with the physical Windows volume using its clear-key protector. Encrypted NTFS fixtures separately covered recovery-key entry, both unlock backends, wrong keys, cancellation and cleanup. A disposable free-space install/rollback test preserved its existing encrypted partition. These are distinct tests; they do not establish a physical encrypted factory-reset recovery test.

Camera capture and suspend were disabled and unvalidated in revision 24. The camera drivers were packaged, but revision 24 blacklisted them and its active device tree lacked CAMSS, CCI and sensor nodes. Loading modules alone cannot enable that camera. These results do not establish camera, suspend or other-board support in the new upstream package. Dislocker’s x86 build was not validated in this record.
