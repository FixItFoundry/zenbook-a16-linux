# Current build — 2026-10-12

**Working audio bringup baseline:
`7.3.0-rc5-ZenbookA16-20261008-rc5-audiopm1+`.** The user confirmed all four
physical speaker channels on October 12. Boot/artifact checks and a short
CPU/Vulkan regression screen passed. This promotion records a working audio
configuration with controller autosuspend disabled; full platform reliability
and efficient power management remain unvalidated.

## Identity and source

| Field | Value |
|---|---|
| Base | Linux v7.3-rc5, `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e` |
| Source tree | `14fd463c06510c760dde22ef215fcbd0bff9a898` |
| Series | [59 ordered patches](../patches/rc5-20261008/README.md) |
| Config and build helper | [rc5-20261008](../kernel/rc5-20261008/README.md) |
| Built | October 8, native Fedora GCC 16.2.1; Image/modules/DTB build exited 0 |
| Accepted boot | `7c99de3a-7ba3-4e75-9309-03e77e8ea121` |
| Board and userspace | ASUS UX3607OA / glymur; Fedora 44 aarch64, Hyprland |
| Active root | Btrfs `a16-audio-test4-20260919`, subvolume 259 |
| EC setting | `asus_glymur_ec.fan_profile=2`, confirmed in sysfs |

The series includes the unchanged 28-patch October 2 stack, its later source
snapshot, backports and repair1 changes, then the exact audiopm1 delta. Complete
replay reproduces the tested source tree. The captured config and compiler are
recorded rather than assuming equivalence to the earlier Ubuntu-built kernel.
No full rebuild or new RPM installation was performed during this promotion.
The [October 2 record](build-20261002.md) is retained as history.

## Acceptance on October 12

| Gate | Evidence and limit |
|---|---|
| Installed artifacts | All 8,469 recorded payload hashes match; five candidate boot files also match on the firmware-visible boot surface. Live release/root/DT/profile were checked separately. |
| Four speakers | User explicitly confirmed all four channels. Four individually labelled clips each exited 0; four-channel ALSA PCM and one-to-one FL/FR/RL/RR graph links were captured. All four SoundWire slaves stayed attached. Channel indices alone do not establish physical location. |
| Audio policy | Both live DT opt-ins present; both controllers `on`, active and runtime forbidden. Suspended counters remain zero. This establishes keep-active playback, not successful controller runtime suspend/resume. |
| Power and USB0 | USB-PD supply online and battery Charging. USB0 hub enumerated at SuperSpeed; r8152 Ethernet was the active default route. Five interface-bound gateway replies passed with zero loss. This is a short USB0 check. |
| CPU/GPU regression | Guarded 95-second window: 20 s idle, one CPU worker for 30 s, idle, 600 Vulkan frames, cooldown. Exit 0; 80 passive samples; peak temperature 50.5 C, NVMe 29.85 C, segment-5 AER sum 0. No new kernel messages in the monitored window. |
| GPU idle evidence | GPU/GMU cumulative suspended counters increased by about 19.7 s over the broader observation interval. This is not a controlled repeated runtime-resume or recovery test. |
| Rollback | 627 saved fallback hashes match; main/custom GRUB syntax passes; Windows entry and EFI order remain present. |

Raw captures and listener acceptance remain in the private October 12 validation
record. The initial workload attempt correctly refused to start while AC was
offline; the successful run used a separate evidence directory after power was
verified. Earlier October 8 postboot receipts are historical, not evidence for
this boot. Journal capture used the explicit boot ID because RTC chronology can
be misleading.

## Remaining limits

The audio workaround invokes `pm_runtime_forbid()` only with the board-specific
DT opt-in. It does not establish the detach cause, recover a detached slave,
or measure battery cost. The retained SoundWire recovery repairs are distinct
from this autosuspend prevention policy. Repeated cold boots and physical
idle-to-playback checks remain necessary before claiming durable audio recovery.

Historical abrupt resets and missing RPMh acknowledgments remain unexplained.
Host fault checks found unresolved SoundWire resume and USB QMP error-path
failures; clean short native workloads do not close those findings. Controlled
runtime/system resume, sustained load, physical fan response, battery drain and
AC/battery transitions remain open.

USB1 both-orientation carrier/traffic, external display, microphones, other
audio routes, current Bluetooth pairing/traffic and camera capture are not
accepted by this promotion. This boot reports missing Bluetooth
`qca/hmtbtfw11.tlv` and CDSP firmware, plus early dependency/routing messages;
later GPU firmware initialization succeeds. Camera drivers remain blacklisted.

## Boot and rollback

This is a repository baseline promotion. The saved GRUB default remains
`zenbook-a16-rc5-integrated1-20261002`; use the existing audiopm1 test entry to
boot the new baseline. Both old RC5 and RC3 reproduction packages are retained.
No boot files, kernel payload, runtime policy, EFI BootOrder or Windows route
were changed during promotion, and no reboot or suspend was requested.

This host's firmware reads GRUB and boot artifacts from the Btrfs top level,
while the kernel mounts the audio-test4 root. Merely updating the running
root's `/boot` does not update the complete boot path. Read-back verified all
three text GRUB environments and the raw one-shot block at partition byte
offset 262144 (`env_block=512+1`): no next entry was armed. EFI had no BootNext.
Any later boot selection change must preserve those mirrors and fallback
routes together.

The accepted command line still includes `clk_ignore_unused`,
`pd_ignore_unused`, `cma=128M`, `glymur_pci_skip=5`, `selinux=0`, and the
`i2c_qcom_cci,qcom_camss,ov02c10` blacklist. These restrictions are part of the
tested configuration, not evidence of normal low-power or security behavior.
Use matching Image/modules/DTB/initramfs and early audio firmware for any rebuild.
