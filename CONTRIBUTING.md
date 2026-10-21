# Contributing

Choose the track named in [current status](docs/current-build.md). Omarchy work targets the shared package recipe and coordinated runtime/ISO PRs described in [Omarchy status](docs/omarchy-status.md). For a Fedora soc2 experiment, use Linux v7.3-rc5 plus the [64-patch series](patches/rc5-20261013/README.md) and its [recorded config and verifier](kernel/rc5-20261013/README.md).

- Make each hardware experiment a separate change with a distinct kernel release. Preserve a tested fallback and the Windows boot route.
- Build the board DTB from the replayed kernel source; historical files under `dts/` and `prebuilt/` do not define this baseline.
- Preserve patch authors, review trailers and source links. Add adopted upstream work to [UPSTREAM-CREDITS.md](UPSTREAM-CREDITS.md).
- Keep kernel-derived files under `SPDX-License-Identifier: GPL-2.0-only`. Do not commit private signing keys or proprietary firmware/driver binaries.

## Reports and validation

Include the hardware variant, kernel/source identity, DTB hash, config changes,
boot command line, boot ID and relevant kernel journal. State test duration,
power source and attached devices; remove personal information before posting.

Separate source tests, boot/enumeration, traffic/playback and physical acceptance.
A short pass does not close the [remaining hardware limits](docs/current-build.md#remaining-limits).
Keep README and changelog additions factual and brief: one or two sentences per item.
