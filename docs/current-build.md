# Current build — 2026-09-30 (Transitioning to RC4)

RC3 is the user-selected working baseline, currently transitioning to Linux
v7.3-rc4. Audio and long-duration stability remain under investigation;
promotion is not a hardware-validation sign-off.

## Build identity

| Field | Value |
|---|---|
| Release | `7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+` (active baseline) |
| Target base | Linux v7.3-rc4, `93f51579e7df248780214094418f205253383cc5` |
| Prior base | Linux v7.3-rc3, `fd73f4a6659897191fa0d40695fe370925dd3780` |
| Integrated source (RC3) | `ecb5f3d03d5b187ef54fbba07ddc73765aa76791` |
| Active test branches | `codex/rc3-ec-v3-hid-20260923`, `codex/rc3-usbdiag2-ecv3hid1-20260923` |
| Board | ASUS Zenbook A16 UX3607OA, Qualcomm glymur |
| Userspace | Fedora 44 aarch64, ML4W/Hyprland with UWSM |

The source identity refers to the separate kernel worktree, not this repository's
HEAD. The [RC3 package](../kernel/rc3-20260919/README.md) records the 24-patch
series and configuration. Replaying on v7.3-rc3 reproduces that source tree.
The upcoming RC4 package drops the mainline DP patch, promotes EC v3, and
incorporates camera LDOs.

## Integration scope

- Mainline upgrade & retirement: Upgrading base to `v7.3-rc4`. Retiring
  `drm/msm/dp: skip PUSH_IDLE when the link was never enabled` (Patch 0007)
  because it is now upstream in mainline Linux (`e249a6e2a130`).
- Promoted EC v3 driver: Incorporating Konrad Dybcio's ASUS Embedded Controller
  v3 driver and DT node (`patches/rc3-ec-v3-hid-20260923/`), validated on
  hardware in test builds, alongside our local patch preserving HID keyboard
  backlight ownership.
- Camera PMIC LDOs: Staging PMH0104 camera LDO support
  (`patches/glymur-pmh0104-camera-ldos.patch`) to provide `ldo4` (1.8 V) and
  `ldo7` (2.8 V) rails for the OmniVision OV02C10 front sensor.
- Carried next backports: GPU CX power-domain voting, WSA compander addresses,
  LPASS clock-data initialization, USB3 votes, SoundWire address-page caching,
  and A16 microphone sample rate.
- Local compatibility: eDP 1.4 `LINK_RATE_SET` reachability, ASUS HID quirks,
  Wi-Fi/Bluetooth sequencing, APM retries, WSA runtime-PM cleanup, PCI suspend
  bypass and board settings.
- Experimental SoundWire boot attachment/recovery remains a local carry patch.

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

GRUB configuration is structured with `zenbook-a16-rc3-integrated1-20260919` as the stable working baseline and `zenbook-a16-rc4` (`7.3.0-rc4-ZenbookA16-rc4-integrated1+`) as the active integration target. Diagnostic and experimental kernels (such as EC v3 and USB tracing) remain selectable under the diagnostic submenu. Retain the proven RC3 kernel, modules, and DTB as a fallback when testing any new integration build. See [`boot-kit/`](../boot-kit/) for the cleaned-up `40_custom` and `grub.cfg` configuration templates.

For historical component details see [hardware.md](hardware.md); older success
claims do not supersede the limitations above.
