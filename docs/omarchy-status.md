# Omarchy A16 status — 2026-10-21

**`linux-omarchy 7.2.8-24` completed native build, package, boot and hardware validation and is still running on the A16.** This records the diagnosis session’s results and Jesse’s physical confirmations. The coordinated Omarchy package and PR updates are awaiting publication.

## Kernel tracks

| Track | Identity and role |
|---|---|
| Shared Omarchy candidate | `7.2.8-24-omarchy`, source tree `d05c4879b3789c74e2a73684683b15deb0be258b`; native build, package, boot and hardware validation complete; still running on the A16. |
| Retained Fedora soc2 baseline | `7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+`; its dated acceptance record remains in [current build](current-build.md#fedora-soc2-baseline--2026-10-14). |
| Mainline/Qualcomm bridge | [rc5-qcom-bridge-20261018](../kernel/rc5-qcom-bridge-20261018/README.md); separate development track. Omarchy acceptance does not transfer to this build. |
| Earlier Arch port | [arch-7.2.10](../kernel/arch-7.2.10/BUILD-AND-UPGRADE.txt), also represented by `feature/arch-7.2.10-a16`; retained reference, not the current shared Omarchy candidate. |

The shared Omarchy recipe is [`pkgbuilds/linux-omarchy-aarch64`](https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/linux-omarchy-aarch64). At this check, `master` carries `7.2.8-23` and the package repository’s `rc` branch carries `7.2.8-20`. `rc` is a package release channel, not a second Linux release-candidate kernel. Submit the A16 package changes to `master`, then promote the prerequisites with their consumers through `edge`, `rc` and `stable`.

## Revision 24 evidence

- Clean native A16 build; all 8,487 packaged modules checked; an external module compiled against the packaged headers. The distributed source package replayed to the tree above.
- Kernel and headers `7.2.8-24`, support `20261014-1` and firmware extractor `1-6` installed. Both generated normal/rescue UKIs matched the kernel and A16 DTB and passed 26 targeted module dry runs each.
- Physical boot `1e110042-6ff5-4f7e-b2ea-63b08dad6d8e` ran revision 24. ADSP/CDSP started before root mounted and remained running; SoCCP was attached. No failed units, deferred devices or kernel taint were recorded.
- The initramfs log was empty with early logging enabled. The previous modprobe errors and four battery uevent errors were absent. Root was writable and all five Btrfs device-error counters were zero.
- The compiled battery before/after regression, runtime board/DSP shell checks, all 25 support verifier tests and support initramfs checks passed.
- Jesse physically confirmed audio playback, keyboard, touchscreen, charger transitions and Bluetooth phone calls/audio. Built-in microphone capture was not separately confirmed.

The physical test used an enclosure-specific UAS fallback for an external root SSD after transport failures. This is a local test condition, not an A16 board default or an established fix for internal NVMe installations. The candidate patches contain no such quirk. Four PMIC supplier-link warnings and the previously observed codec workqueue deprecation warning remain; no clean-log or long-term stability claim is made. Long-term stability is outside this submission’s current acceptance checklist.

## Installation evidence and feature limits

Revision 21 was the initial installation test kernel, covering ARM UEFI live boot, generic/N1x-mode VM install/reboot checks and physical A16 installation. After debugging, the A16 moved to revision 24 and completed the build, package, boot and hardware validation recorded above.

Read-only firmware extraction was exercised with the physical Windows volume using its clear-key protector. Encrypted NTFS fixtures separately covered recovery-key entry, both unlock backends, wrong keys, cancellation and cleanup. A disposable free-space install/rollback test preserved its existing encrypted partition. These are distinct tests; they do not establish a physical encrypted factory-reset recovery test.

Camera capture and suspend remain disabled and unvalidated in the Omarchy candidate. The camera drivers are packaged, but revision 24 blacklists them and its active device tree lacks CAMSS, CCI and sensor nodes. Loading modules alone cannot enable that camera. A potential camera path is being investigated separately; capture is not part of this submission’s validated scope. Other supported ARM boards still need regression coverage before promotion; Dislocker’s x86 build also needs CI coverage.

## Open PRs and submission order

| Repository | Current state and next action |
|---|---|
| [omarchy #13820](https://github.com/omacom/omarchy/pull/13820) | Open against `quattro`; published head `937b15e7eb770748b60effb8baf4356618ced7c1`. Prepared update validates the shared root command line before writes, refreshes normal/rescue command lines before each build, and removes the private firmware-package dependency. |
| [omarchy-iso #208](https://github.com/omacom/omarchy-iso/pull/208) | Open against `quattro`; published head `cc37956268c4cc75a7bbace6346c6330bed21043`. Prepared update uses the unified ARM image and stages verified owner firmware before disk writes, including read-only BitLocker access. |
| [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) | Five separate local proposals: shared ARM kernel, firmware extractor, Limine failure propagation, Dislocker, and A16 support. No A16 package PR from this maintainer was open at this check. |

Publish the kernel capability `omarchy-a16-dsp-abi=1` to edge before building the support package: package CI jobs resolve dependencies from the published repository, not another PR’s artifacts. Complete all five package prerequisites before merging their runtime and ISO consumers. Each release channel must receive those prerequisites before its consumers. Preserve the matching kernel, headers and corresponding-source package together.

The three unresolved runtime review threads concern early DSP activation, downgrade safety and package prerequisites. The prepared package dependency and capability checks address those paths; the old late-start fallback is removed. Invalid prerequisites stop setup without altering existing board configuration. This does not support forcing package dependency removal.

The factory-reset command-line inheritance finding is marked resolved on GitHub, but its code correction is still part of the local update. Do not equate that thread state or existing public CI with validation of unpublished changes. Public PR descriptions also need replacement: they still describe superseded late-DSP/platform-profile work.
