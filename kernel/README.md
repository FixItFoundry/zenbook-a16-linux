# Kernel Packages

Active kernel build recipes are organized into two maintained tracks (`stable` and `rc`), alongside the standalone Arch Linux `7.2.10` recipe (`arch-7.2.10`). Retired bringup recipes (`rc3-*`, `rc5-202610*`) live under [`../archive/kernel/`](../archive/kernel/).

| Directory | Track | Upstream Base | Patches | Replayed Source Tree | Status |
|---|---|---|---:|---|---|
| [`stable/`](stable/README.md) | **Stable Release Track** (`main`) | Linux `v7.3.6` (`1a0388846138eda9f6eb4258ff227a223afc2f52`) | [183](../patches/stable/README.md) | `a25b51b1ceda63f568d36f0dd4847c0787dfcfaa` | Feature-complete maintenance baseline (`pkg14`, promoted default): 3 displays, HDMI/DP audio, Iris HW video, RGB/IR cameras, Wi-Fi/BT, `memlat`/SPEL, and full `APSS + CXSD + AOSD + DDR` `s2idle` deep sleep without `clk_ignore_unused`/`pd_ignore_unused`/`glymur_pci_skip=5`. |
| [`rc/`](rc/README.md) | **RC / Upstream Development Track** (`rc`) | Linux `next-20261103` (`d6bcfc94eb4da6e089c5473970cd96727292fd97`, `v7.4-rc1`) | [114](../patches/rc/README.md) | `ae9780ba94c73237250a58ecc44fca2485813f8a` | Adds PMH0101 IR emitter/BOB1 wiring and the eDP link fallback fix on top of revision 6 (`ed1c21244abb`); source/DTB verified off the device, not installed or booted. |
| [`arch-7.2.10/`](arch-7.2.10/BUILD-AND-UPGRADE.txt) | **Arch Linux 7.2.10 Recipe** | Linux `v7.2.10` | 127 | `4d6a5f56ffa9571ec5b5f053ecbe4861c158b2b2` | Standalone `PKGBUILD` generator with side-by-side UKI and header support. |
| [`../archive/kernel/`](../archive/kernel/) | **Retired Snapshots** | `v7.3-rc3` / `v7.3-rc5` | — | Historical | Retained `rc3-20260919`, `rc5-20261002`, `rc5-20261008`, `rc5-20261013`, and `rc5-20261031` recipes. |

## Replay and Build Commands

```sh
# Stable track (Linux 7.3.6, 183 patches):
python3 kernel/stable/replay.py /path/to/linux
JOBS=4 PACKAGE_REVISION=14 ./kernel/stable/build.sh /path/to/linux /path/to/stable-output

# RC track (Linux 7.4-rc1 linux-next next-20261103, 114 patches):
python3 kernel/rc/replay.py /path/to/linux
JOBS=4 ./kernel/rc/build.sh /path/to/linux /path/to/rc-output

# Replay both tracks with forward and reverse index checks:
python3 scripts/ci.py --replay-only --track both --linux-git /path/to/linux
```

Each `build.sh` verifies source checksums and tree identity in a temporary Git index, creates an isolated worktree, builds `Image`, modules, `glymur-asus-zenbook-a16-ux3607oa.dtb` (verifying `qcom,keep-runtime-active;` via `dtc`), external-module headers, and distro packages (`BUILD_RPM=1` for Fedora RPMs, `BUILD_DEB=1` for Ubuntu/Debian DEBs, `STAGE_BUNDLE=1` for the portable bundle). New builds append `-a16pkgN+` so they never overwrite an installed fallback kernel.

See the [package contract](../packaging/zenbook-a16-kernel/README.md), [track policy](../docs/kernel-tracks.md), and [board firmware guide](../firmware/README.md).
