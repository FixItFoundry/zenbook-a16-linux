# Current build — 2026-10-02 (RC5 promoted)

`7.3.0-rc5-ZenbookA16-20261002-rc5-integrated1+` is the promoted baseline and the
GRUB default. It has **not** been booted. Promotion is not a validation
sign-off; the RC3 baseline remains the proven-good fallback. Audio, long-duration
stability and suspend remain under investigation.

## Build identity

| Field | Value |
|---|---|
| Release | `7.3.0-rc5-ZenbookA16-20261002-rc5-integrated1+` (promoted default, unbooted) |
| Base | Linux v7.3-rc5, `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e` |
| Source tree | `a3327a6d526503774e01b3bb15841883da87a180` (28-patch series, verified) |
| Proven fallback | `7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+` on v7.3-rc3 `fd73f4a66598` |
| Package | [`../kernel/rc5-20261002/`](../kernel/rc5-20261002/README.md) |
| Series | [`../../patches/rc5-20261002/`](../../patches/rc5-20261002/README.md) |
| Board | ASUS Zenbook A16 UX3607OA, Qualcomm glymur |
| Userspace | Fedora 44 aarch64, ML4W/Hyprland with UWSM |

The RC3 package stays in place: it reproduces the kernel that was actually
booting as the known-good baseline and is the reproduction path for the
fallback entry.

### Correction to the rc4 plan

The 2026-09-30 notes targeted v7.3-rc4 (`93f51579e7df`). That was already one RC
behind when written: **v7.3-rc5** (`72d3fcf802c4`, 742 commits past rc4) is the
current release candidate and is what this baseline uses. No rc4 kernel was ever
built or installed on this machine, so the previously documented
`zenbook-a16-rc4` / `7.3.0-rc4-ZenbookA16-rc4-integrated1+` GRUB entry did not
exist. Both `v7.3-rc4` and `v7.3-rc5` tags are now present in the kernel
repository at `~/kernel-build/community-audit-20260919.git`.

## Patch audit against v7.3-rc5

All 24 RC3 patches were replayed against rc5 using a throwaway Git index.

| Outcome | Count | Detail |
|---|---|---|
| Retired, now upstream | 1 | `drm/msm/dp: skip PUSH_IDLE when the link was never enabled` — upstream as `e249a6e2a130` |
| Applied unchanged | 23 | Every other RC3 patch applies to rc5 without re-basing |
| Added | 5 | EC v3 series (4) and PMH0104 camera LDOs (1) |
| **Total in the new series** | **28** | |

Nothing in the carried stack was found obsolete or in need of rebasing by hand.
That is a source-level result only: it says nothing about rc5 hardware behaviour.

The camera LDO patch arrived as a headerless diff and was rewritten as a real
commit so the series replays with `git am`. It only adds rail descriptions; no DT
node consumes them yet, so it is inert while the baseline cmdline blacklists
`ov02c10`, `qcom_camss` and `i2c_qcom_cci`.

Config delta versus RC3 is two lines: `CONFIG_EC_ASUS_GLYMUR=m` and a retargeted
`LOCALVERSION`.

## Spontaneous reset on 2026-10-02 (corrected record)

The first version of this section blamed a failed suspend. That was wrong: it
came from `journalctl -b -1`, and this machine's journal boot list is corrupt —
`--list-boots` reports September dates while every kernel-start marker is
stamped `Sep 13 20:00:00`. Booting on `_BOOT_ID` gives the real picture. Four
boots occurred on 2026-10-02, all on `7.3.0-rc3-ZenbookA16-20260930-usb1dualport1+`:

| Boot ID | Window | Ending |
|---|---|---|
| `c0906e4b` | 08:28:24 → 08:29:56 | Orderly reboot |
| `c1016cc2f` | ~08:30 → **09:38:08** | **Silent reset** |
| `696b5d8c` | 09:38:08 → 09:39:57 | Power-key suspend, user-initiated |
| `65f750d1` | 09:40:37 → present | Current |

The RC5 build finished at 09:35:43. Boot `c1016cc2f` then died at 09:38:08
during an otherwise ordinary desktop session (tailscaled up, desktop and D-Bus
running, a ChatGPT app process active). There is no orderly shutdown — the boot
goes from a normal application log line straight to nothing. No panic, oops,
`Call trace`, AER, thermal or watchdog message; `/sys/fs/pstore/` is empty. The
build was already complete, so this is not a build-time reset.

Around the time of the reset the machine was verifying the bundle manifest,
reading roughly 8,500 files including the 62 MB Image and 8,463 modules. Heavy
sequential I/O is a plausible but unproven contributor. No causal claim is made.

This adds a third unexplained silent reset to the record and is better evidence
than the earlier "high-parallelism build resets" observations, because it
happened with no build running at all. It does not support a
high-parallelism-specific explanation.

### Suspend: unresolved, not a negative result

A short power-key press in boot `696b5d8c` at 09:39:57 logged
`PM: suspend entry (s2idle)` and nothing further. That event cannot be separated
from the spontaneous reset behaviour above: because the machine demonstrably dies
silently on its own, a boot whose last message is the suspend entry is equally
consistent with a suspend failure and with an unrelated reset that happened to
land there.

The journal contains **zero resume events of any kind** across all six recorded
suspend attempts (`Sep 23` ×2, `Sep 25`, `Sep 30`, `Oct 01`, `Oct 02`). That
means either every suspend failed or resume is not being logged; the available
data cannot distinguish these.

The earlier claim that this contradicted
`/etc/systemd/logind.conf.d/99-glymur-suspend.conf` is **withdrawn**. The
knob `glymur_pci_skip=5` was on the cmdline, but with a confounded event and a
demonstrated spontaneous reset, no conclusion about the mitigation is supported.
That file's own "validated on 2 suspend/resume cycles" note remains the honest
description of the evidence.

## Validation and limitations

The RC5 Image, 8463 modules, DTB and initramfs all built and installed. The
bundle manifest verifies 8481/8481 files. The DTB contains `embedded-controller@76`
and the initramfs carries the four ADSP blobs plus the A16 AudioReach topology
required for early audio. **No boot of this kernel has occurred.** Nothing in
this build is hardware-validated.

Carried-forward RC3 limitations still stand: front-left audio silence after boot
is unresolved, repeated cold boots and microphone recording are unvalidated,
earlier NOHZ/RCU warnings and spontaneous resets have no long-duration
explanation, high-parallelism build resets remain unexplained, and Wi-Fi
regulatory warnings persist. Hibernate stays disabled.

## Boot and rollback

GRUB was restructured on 2026-10-02 from 38 entries to 10:

1. **Default** — `zenbook-a16-rc5-integrated1-20261002` (`GRUB_DEFAULT` and
   `saved_entry`). Its cmdline is deliberately identical to the RC3 baseline so
   the only variable across the promotion is the kernel.
2. **FALLBACKS** — the proven RC3 baseline, Fedora 6.19.10, the 6.19 rescue
   initramfs, and `7.1.0-glymur-clean2`. The two Fedora entries remain
   **UNVERIFIED** on this machine and carry no custom devicetree.
3. **USB1 SuperSpeed** — the 20260930 dual-port control and the 20260929 hub
   depth diagnostic it borrows its DTB from.
4. **Windows / UEFI** — always-works escape hatches.

The 24-entry "Earlier builds" archive and six superseded USB1 experiments were
removed from the menu. **No artifacts were deleted**: every retired kernel,
module tree, DTB and initramfs is still in `/boot` and `/lib/modules`. The
previous menu is preserved at
`~/kernel-build/backups/rc5-promote-20261002-094858/40_custom.bak`, and the
pre-change `40_custom`, `grubenv` copies and `/etc/default/grub` are in the same
directory.

If the new default fails to boot, select FALLBACKS → RC3 working baseline.

For historical component details see [hardware.md](hardware.md); older success
claims do not supersede the limitations above.