# Linux 7.3 final A16/Qualcomm candidate

Local source port of the full A16 stack to **Linux v7.3 final**. This is a
candidate for the stable track, awaiting compilation, native package tests and
hardware acceptance. The existing rc5 camera candidate remains the physical
validation reference; nothing here installs or selects a kernel.

| Identity | Value |
|---|---|
| Upstream base | `v7.3`, commit `c03c1a14507dfaf8b856c2608f9ac216021fc222` |
| Ordered residual queue | [146 patches](../../patches/stable/README.md) |
| Patched source tree | `ca55d57edf4c0c2ade677f0b5336e69ab8645c3a` |
| Recorded release | `7.3.0-ZenbookA16-20261022-final1+` |
| Package revision 1 | `7.3.0-ZenbookA16-20261022-final1-a16pkg1+` |

The queue retains the 64-patch A16 baseline, 40-patch Qualcomm bridge and
10-patch camera/microphone overlay (minus three complete patches already in
7.3), plus 32 patches (`0112`–`0143`) integrating the local GDSC unwind RFC,
genpd/AudioReach/Q6DMA overlays, and reviewed LKML / `qcom-next` /
`glymur-laptops` fixes through 2026-11-03 (including Konrad Dybcio's Glymur USB3
QMP PHY settings update as `0143`). Original authors and trailers are preserved;
see [upstream credits](../../UPSTREAM-CREDITS.md).

## Verify without making commits

```sh
python3 kernel/stable/replay.py /path/to/linux-git
```

The verifier checks the manifest and applies all 146 patches in a temporary Git
index, requiring the exact source tree above. It leaves HEAD, the normal index
and working files alone. It creates Git tree/blob objects, not commits.

## Build after reviewing the port

Use the existing [native Linux build prerequisites and package contract](../../packaging/zenbook-a16-kernel/README.md).
Supply a Linux Git repository containing the pinned base and a new output path:

```sh
# Fedora RPMs and portable bundle:
JOBS=4 PACKAGE_REVISION=1 \
  ./kernel/stable/build.sh /path/to/linux-git /path/to/final-output

# Ubuntu/Debian packages instead:
JOBS=4 PACKAGE_REVISION=1 BUILD_RPM=0 BUILD_DEB=1 \
  ./kernel/stable/build.sh /path/to/linux-git /path/to/final-deb-output
```

The build helper uses an isolated worktree and `git apply --index` so both mail
patches and the raw camera diffs apply without making commits. HEAD stays on
the pinned upstream base; the staged index records the complete source tree.
The helper checks that tree, runs `olddefconfig`, requires every setting in [required.config](required.config),
checks the release, and builds Image, modules, headers and the matching A16 DTB.
Retry a failed build with `--resume` and the same environment/output directory;
changes relative to the expected staged tree and incomplete patch application
are rejected.

[config](config) is the actual compiled rc5 camera pkg3 configuration with a new
local release. It is an input for 7.3 `olddefconfig`, not a claim that Kconfig has
been resolved on the new base. The manifest's `promotion_date` supplies the
existing package version format; it does not record hardware promotion.

`camera_enabled: true` makes the shared packager omit its legacy camera
blacklist and tells boot hooks to remove those camera modules from inherited
blacklists, preserving other blocked modules. Older recipes retain their command
line and inherited blacklist behavior. DSP policy, sleep restrictions and development boot settings
are retained, including `selinux=0`; this is not a production security sign-off.

## Validation and limits

Source replay and local package/build-helper regression checks pass. The real
AudioReach helper's shrinking-channel-map self-check passes on the ported source.
Camera/DMIC source and board settings are unchanged from the rc5 pkg3 candidate.
The 4 mA/pull-down/slew-1 pin setting remains experimental while its cold-boot
and simultaneous camera/microphone recording tests are pending.

No 7.3 kernel or DTB has been compiled, installed or booted by this preparation.
Native RPM/DEB transactions, external-module headers, physical update/rollback
and hardware acceptance remain open. See the [transition checklist](../../docs/kernel-tracks.md).

## RPMh and RTC additions, November 12

Preserve a mode already applied by regulator registration. Fixed/legacy/fixed
diagnostic boots retained FAST; the legacy overwrite did not reproduce because
ENABLE was zero at inference. Host tests cover the overwrite branch. No physical
rail or audio-quality improvement is established.

Release the RTC parent wake source when the timer worker cannot read time.
The GLINK read timeout remains unresolved; this balances the wake-source lifetime.

Select RTC ops without set_time unless allow-set-time is enabled. This stops NTP
retrying unsupported writes and preserves the existing writable opt-in.
The failed GLINK v2 diagnostic driver is excluded.

Both tracks pass source replay and host checks. Hardware observations cover
only the A16; other machines using these shared drivers were not tested.
This exact combined queue
has not been compiled or booted. The successful attended sleep trials used
the diagnostic image described in [the hardware record](../../docs/hardware.md).
