# Linux 7.4 RC (`next-20261103`) Development Track (`kernel/rc`)

Upstream development and LKML validation track for the **ASUS Zenbook A16 (`UX3607OA` / `glymur`)**, rebased onto **Linux `v7.4-rc1`'s `linux-next` tag `next-20261103`** (`d6bcfc94eb4da6e089c5473970cd96727292fd97`).

| Identity | Value |
|---|---|
| Upstream `linux-next` base | `next-20261103`, commit `d6bcfc94eb4da6e089c5473970cd96727292fd97` |
| Underlying mainline RC | `v7.4-rc1`, commit `6628e7d4c6b25c8d18f1345e3a20d21829aae7e4` |
| Ordered residual queue | [101 patches](../../patches/rc/README.md) ([`port-map.json`](../../patches/rc/port-map.json)) |
| Patched source tree | `2b1378a830da64996ce87b1941a9d0cb592239be` |
| Recorded release | `7.4.0-rc1-next-20261103-zenbook-a16+` |
| Package revision 1 | `7.4.0-rc1-next-20261103-zenbook-a16-a16pkg1+` |

## Upstream Retirement & RC-Specific Adjustments

Auditing all 143 patches in [`patches/stable`](../../patches/stable/README.md) against `next-20261103` retired **45 upstreamed patches** (recorded with their non-merge upstream commit SHAs in [`patches/rc/port-map.json`](../../patches/rc/port-map.json)), adapted **12 patches** to `v7.4-rc1` / `next-20261103` API changes, and added **2 `rc`-specific patches**:

1. `0001-LOCAL-drop-localversion-next-the-build-name-carries-.patch`: Removes the root `localversion-next` file so `CONFIG_LOCALVERSION="-next-20261103-zenbook-a16"` controls `UTS_RELEASE` cleanly without duplicating `-next-20261103`.
2. `0100-Revert-drm-msm-a8xx-Enable-CLX-feature-on-Adreno-X2-.patch`: Applies Abel Vesa's revert (`d448c66b9e47` from `laptops-kernel/topic/glymur-laptops`) of `93b6c8d10fad` / `c2a6bcfbebce` (`drm/msm/a8xx: Enable CLX feature on Adreno X2-85`), preventing GMU `HFI_H2F_MSG_GX_BW_PERF_VOTE` timeouts on Glymur laptops.

## Verify Without Modifying a Checkout

```sh
python3 kernel/rc/replay.py /path/to/linux-git
python3 scripts/ci.py --replay-only --track rc --linux-git /path/to/linux-git
```

## Build Packages

```sh
# Fedora RPMs and portable bundle:
JOBS=4 PACKAGE_REVISION=1 \
  ./kernel/rc/build.sh /path/to/linux-git /path/to/rc-output

# Ubuntu/Debian packages instead:
JOBS=4 PACKAGE_REVISION=1 BUILD_RPM=0 BUILD_DEB=1 \
  ./kernel/rc/build.sh /path/to/linux-git /path/to/rc-deb-output
```

The retired `v7.3-rc5` layered RC recipe is archived under [`../../archive/kernel/rc5-20261031/`](../../archive/kernel/rc5-20261031/README.md).

## RPMh and RTC additions, November 12

Preserve a mode already applied by regulator registration. Fixed/legacy/fixed
diagnostic boots retained FAST; the legacy overwrite did not reproduce because
ENABLE was zero at inference. Host tests cover the overwrite branch. No physical
rail or audio-quality improvement is established.

Both tracks pass source replay and host checks. Hardware observations cover
only the A16; other machines using these shared drivers were not tested.
This exact combined queue
has not been compiled or booted. The successful attended sleep trials used
the diagnostic image described in [the hardware record](../../docs/hardware.md).
