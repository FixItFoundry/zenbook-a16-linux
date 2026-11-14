# Kernel Packages

Active kernel build recipes are organized into two maintained tracks (`stable` and `rc`), alongside the standalone Arch Linux `7.2.10` recipe (`arch-7.2.10`). Retired bringup recipes (`rc3-*`, `rc5-202610*`) live under [`../archive/kernel/`](../archive/kernel/).

| Directory | Track | Upstream Base | Patches | Replayed Source Tree | Status |
|---|---|---|---:|---|---|
| [`stable/`](stable/README.md) | **Stable Release Track** (`main`) | Linux `v7.3` (`c03c1a14507dfaf8b856c2608f9ac216021fc222`) | [157](../patches/stable/README.md) | `68c6fb5921f92299904c233333fccf4fb5093bc4` | Adds 7.3 HM1092 `.set_fmt` and PMH0101 IR emitter/BOB1 wiring on top of revision 6 (`bd1327aac6e1`, which boots with display and Wi-Fi working; stability not yet accepted). |
| [`rc/`](rc/README.md) | **RC / Upstream Development Track** (`rc`) | Linux `next-20261103` (`d6bcfc94eb4da6e089c5473970cd96727292fd97`, `v7.4-rc1`) | [113](../patches/rc/README.md) | `52ecc2153e2280fcf68b6a2d56f00804d7d27e73` | Adds PMH0101 IR emitter/BOB1 wiring on top of revision 6 (`ed1c21244abb`); source/DTB verified off the device, not installed or booted. |
| [`arch-7.2.10/`](arch-7.2.10/BUILD-AND-UPGRADE.txt) | **Arch Linux 7.2.10 Recipe** | Linux `v7.2.10` | 127 | `4d6a5f56ffa9571ec5b5f053ecbe4861c158b2b2` | Standalone `PKGBUILD` generator with side-by-side UKI and header support. |
| [`../archive/kernel/`](../archive/kernel/) | **Retired Snapshots** | `v7.3-rc3` / `v7.3-rc5` | — | Historical | Retained `rc3-20260919`, `rc5-20261002`, `rc5-20261008`, `rc5-20261013`, and `rc5-20261031` recipes. |

## Replay and Build Commands

```sh
# Stable track (Linux 7.3 final, 157 patches):
python3 kernel/stable/replay.py /path/to/linux
JOBS=4 ./kernel/stable/build.sh /path/to/linux /path/to/stable-output

# RC track (Linux 7.4-rc1 linux-next next-20261103, 113 patches):
python3 kernel/rc/replay.py /path/to/linux
JOBS=4 ./kernel/rc/build.sh /path/to/linux /path/to/rc-output

# Replay both tracks with forward and reverse index checks:
python3 scripts/ci.py --replay-only --track both --linux-git /path/to/linux
```

Each `build.sh` verifies source checksums and tree identity in a temporary Git index, creates an isolated worktree, builds `Image`, modules, `glymur-asus-zenbook-a16-ux3607oa.dtb` (verifying `qcom,keep-runtime-active;` via `dtc`), external-module headers, and distro packages (`BUILD_RPM=1` for Fedora RPMs, `BUILD_DEB=1` for Ubuntu/Debian DEBs, `STAGE_BUNDLE=1` for the portable bundle). New builds append `-a16pkgN+` so they never overwrite an installed fallback kernel.

See the [package contract](../packaging/zenbook-a16-kernel/README.md), [track policy](../docs/kernel-tracks.md), and [board firmware guide](../firmware/README.md).
