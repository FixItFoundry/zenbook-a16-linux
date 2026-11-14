# Linux 7.4 RC (`next-20261103`) Development Track (`kernel/rc`)

Upstream development and LKML validation track for the **ASUS Zenbook A16 (`UX3607OA` / `glymur`)**, rebased onto **Linux `v7.4-rc1`'s `linux-next` tag `next-20261103`** (`d6bcfc94eb4da6e089c5473970cd96727292fd97`).

| Identity | Value |
|---|---|
| Upstream `linux-next` base | `next-20261103`, commit `d6bcfc94eb4da6e089c5473970cd96727292fd97` |
| Underlying mainline RC | `v7.4-rc1`, commit `6628e7d4c6b25c8d18f1345e3a20d21829aae7e4` |
| Ordered residual queue | [113 patches](../../patches/rc/README.md) ([`port-map.json`](../../patches/rc/port-map.json)) |
| Patched source tree | `52ecc2153e2280fcf68b6a2d56f00804d7d27e73` |
| Recorded release | `7.4.0-rc1-next-20261103-zenbook-a16+` |
| Package revision 6 | `7.4.0-rc1-next-20261103-zenbook-a16-a16pkg6+` (`ed1c21244abb`, prior to `0113`) |

## Upstream Retirement & RC-Specific Adjustments

The original audit of 143 patches in [`patches/stable`](../../patches/stable/README.md) against `next-20261103` retired **45 upstreamed patches** (recorded with their non-merge upstream commit SHAs in [`patches/rc/port-map.json`](../../patches/rc/port-map.json)), adapted **14 patches** to `v7.4-rc1` / `next-20261103` API changes, and added **2 `rc`-specific patches**:

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
JOBS=4 PACKAGE_REVISION=6 \
  ./kernel/rc/build.sh /path/to/linux-git /path/to/rc-output

# Ubuntu/Debian packages instead:
JOBS=4 PACKAGE_REVISION=6 BUILD_RPM=0 BUILD_DEB=1 \
  ./kernel/rc/build.sh /path/to/linux-git /path/to/rc-deb-output
```

The retired `v7.3-rc5` layered RC recipe is archived under [`../../archive/kernel/rc5-20261031/`](../../archive/kernel/rc5-20261031/README.md).

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
The successful attended sleep trials used
the diagnostic image described in [the hardware record](../../docs/hardware.md).

## Display, wireless and camera carry-forward, November 12

Patches `0104`–`0112` (stable `0147`–`0155`) add eDP rate-set corrections, the pending QCC2072 Bluetooth and M.2 power-sequencing patches, mainline M.2 Wi-Fi/Bluetooth wiring, and RGB camera MCLK4 at 6 mA. They are the nine
changes the working revision-2 build already carried, placed after the RPMh/RTC
fixes.

Built as package revision 6 on November 12 and verified off the device; not installed or booted.
The camera clock change was checked separately on revision 1: microphone-triggered
banding disappeared at 6 mA and returned at 2 mA. That does not establish IR
capture or microphone audio quality.

## PMH0101 IR emitter, November 14

Patch `0113` (stable `0157`) defines `vreg_bob1_e0` for PMH0101 L6–L9 and PM8010 L3/L4/L7, enables ganged PMH0101 MVFLASH channels 1+4 (`ir_led`), and attaches `flash-leds` to `camera@24` (`himax,hm1092`). Stable `0156` (`hm1092` `.set_fmt`) is retired on `rc` by upstream commit `48d8b2418f55`. Cross-compiled (`hm1092.o`, `leds-qcom-flash.o`, and `glymur-asus-zenbook-a16-ux3607oa.dtb`); not yet booted on `rc`.
