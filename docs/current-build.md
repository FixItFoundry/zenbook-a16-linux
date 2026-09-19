# Current build — 2026-09-19

RC3 is the user-selected working baseline. Audio and long-duration stability
remain under investigation; promotion is not a hardware-validation sign-off.

## Build identity

| Field | Value |
|---|---|
| Release | `7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+` |
| Upstream base | Linux v7.3-rc3, `fd73f4a6659897191fa0d40695fe370925dd3780` |
| Integrated source | `ecb5f3d03d5b187ef54fbba07ddc73765aa76791` |
| Local kernel branch | `codex/rc3-integrated-20260919` |
| Board | ASUS Zenbook A16 UX3607OA, Qualcomm glymur |
| Userspace | Fedora 44 aarch64, ML4W/Hyprland with UWSM |

The source identity refers to the separate kernel worktree, not this repository's
HEAD. The [RC3 package](../kernel/rc3-20260919/README.md) now includes all 24
integration patches, the exact installed config, hashes and a verifier. Replaying
the series on v7.3-rc3 reproduces the original source tree exactly. This does not
promise byte-identical signed binaries. Do not substitute an August patch series
or older prebuilt DTB.

## Integration scope

- Selected next backports: GPU CX power-domain voting, DP PUSH_IDLE guard,
  WSA compander addresses, LPASS clock-data initialization, USB3 votes,
  SoundWire address-page caching and A16 microphone sample rate.
- Local compatibility: eDP programming, ASUS HID, Wi-Fi/Bluetooth sequencing,
  APM retries, WSA runtime-PM cleanup, PCI suspend bypass and board settings.
- Experimental SoundWire boot attachment/recovery remains a local carry patch,
  not a proven generic fix or submission-ready series.
- Camera changes remain separate. The staged CDSP firmware initramfs experiment
  is not selected in the baseline.

## Validation and limitations

The complete Image/modules/DTB build passed. Installed artifacts were checked
against the build manifest, and RC3 has booted on hardware. Boot housekeeping
reduced measured startup from 50.8 s to 15.6 s; mixer initialization dropped
from about 40 s to 25 ms. These are host measurements, not general benchmarks.

Native UCM restores HiFi, but one boot had physically silent front-left output.
Cycling the audio device restored output without restarting PipeWire or
WirePlumber. A collector also recorded a temporary left-amplifier detachment
without a bus-clash journal message. The cause and its relationship to the
manual toggle are unresolved. Repeated cold boots, all four physical channels,
microphone recording and idle recovery still need validation.

Earlier kernels showed NOHZ/RCU warnings and spontaneous resets. Their absence
in a short RC3 observation is not long-duration stability proof. High-parallelism
build resets remain unexplained. Suspend remains workaround-dependent and
unvalidated on RC3; hibernation is disabled. Wi-Fi regulatory and firmware-load
warnings remain. Bluetooth's active controller uses the original-firmware
fallback when its optional patch file is absent.

The old systemd audio-route/wait helpers were retired in August in favor of UCM;
they have not been reinstated. EasyEffects is removed. The obsolete standalone
SOCCP module-load entry was removed; native remoteproc attachment is in use.

Diagnostic efficiency fixes are separate from the unchanged RC3 kernel: capture
startup cleanup, bounded counter storage, reduced redundant sampling and stricter
boot-service checks. The updated persistent collector is installed as root-owned
scripts and running; the bounded audio capture is updated but not automatically
started. See [diagnostic usage and tests](../scripts/triage/README.md).

## Boot and rollback

GRUB defaults to `zenbook-a16-rc3-integrated1-20260919`. The existing test3 and
older audiofix entries remain available, with unchanged boot artifacts. The
camera entry is separate; obsolete menu entries were archived without deleting
their kernels, DTBs, initramfs files or root snapshots.

The promotion changes the selected default, not the kernel release or filesystem
layout. Its generated menu passed syntax/diff checks; booting the new default
selection remains a separate check. Keep a fallback while testing any new change.

For historical component details see [hardware.md](hardware.md); older success
claims do not supersede the limitations above.
