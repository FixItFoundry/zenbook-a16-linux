# Kernel

The Zenbook A16 bring-up now tracks **linux-next**. The A16 device tree is upstream as of
`next-20260803`, and a linux-next kernel plus two small local deltas boots, trains the
internal eDP panel at HBR3 and runs a graphical session.

> ⛔ **Retired 2026-08-08:** this file used to say *"Do not build on 7.2 / linux-next — a
> regression in the 7.2 cycle broke the working glymur chain. Known-good base = v7.1."*
> **That is false.** The "regression" was a silent reset caused by `msm_dp_ctrl_push_idle()`
> writing to an untrained link; it is fixed by a one-line guard, and 7.1 was never the
> cause-free base it appeared to be. Build on linux-next.

## Build naming (2026-08-08)

One name, used for the kernel release string and the DTB, so a boot can always be identified
from either half:

```
kernel release   <version>-rc<N>-ZenbookA16     e.g. 7.2.0-rc6-ZenbookA16
DTB              /boot/glymur/<same string>.dtb e.g. 7.2.0-rc6-ZenbookA16.dtb
modules          /lib/modules/<same string>/
```

Built with `LOCALVERSION=-ZenbookA16` and `CONFIG_LOCALVERSION_AUTO=n`. The `<version>-rc<N>`
half comes from the linux-next snapshot's own `Makefile`, so it moves on its own as the
merge window does. ⚠️ The release string does **not** record *which* `next-YYYYMMDD` snapshot
it came from — that goes in the GRUB entry title and the changelog entry for the build.

## Native eDP (2026-07-24)

The display patches live in the kernel fork on branch
**[`glymur-edp-hbr3`](https://github.com/FixItFoundry/linux-glymur-a16/tree/glymur-edp-hbr3)**,
not in this repo. Net delta is ~112 lines over the v7.1 snapshot:

| commit | what | upstreamable? |
|---|---|---|
| `drm/msm/dp: make the eDP 1.4 LINK_RATE_SET path actually reachable` | `rate_set`/`use_rate_set` were computed into `panel->link_info` but read from `link->link_params`, so the rate-set path was dead code | **yes** — generic `msm` bug, nothing to do with glymur |
| `drm/msm/dp: glymur: force HBR3 on the internal eDP panel` | the change that lights the panel | **no** — an unconditional constant; needs a general rule first |
| `HID: asus: support the ASUS Zenbook A16 (UX3607OA) N-Key keyboard` | device ID + hotkey mappings + a non-`asus-wmi` backlight path | probably, with cleanup |

`drivers/phy/qualcomm/phy-qcom-edp.c` is **unmodified** — every PHY change tried during
bring-up turned out to be unnecessary. Background: [`../docs/hardware.md`](../docs/hardware.md).

Build name for the display-enabled kernel is **`7.1.0-glymur-edp1`**
(`make LOCALVERSION=-glymur-edp1`); `7.1.0-glymur-clean+` remains the stable shipped
build with `msm` reverted.

## Contents
- `CONFIG_FRAGMENT.md` — the exact `scripts/config` enable-list that makes v7.1 boot on glymur.
- `patches/night_diff.patch` — accumulated working-tree delta (DTS + driver tweaks) captured from the build tree. Review before applying; some hunks are experiment scaffolding.
- `gpucc-x2.c` — a stub/scratch for the missing `sm8750` GPU clock controller (not functional; a starting point for anyone attempting `gpucc`).
- `push-fork.sh` — publishes your local working kernel tree as a standalone GitHub fork repo (run it **inside** the kernel tree, e.g. `~/glymur-build/linux`).

## Two ways to consume the kernel

### A. Reproduce from mainline v7.1 (recommended, small)
```bash
git clone --depth 1 --branch v7.1 https://github.com/torvalds/linux.git
cd linux
# apply the glymur config recipe:
#   see ../boot-kit/scripts/build-kernel-native-full.sh  (starts from a distro config)
#   or CONFIG_FRAGMENT.md for the raw scripts/config enable list
git apply ../kernel/patches/night_diff.patch   # optional, review first
make -j"$(nproc)" bindeb-pkg LOCALVERSION=-glymur-clean   # the stable shipped build
make -j"$(nproc)" dtbs
```

### B. Full fork of the working tree (exact snapshot, large)
The exact working tree lives on the build machine (Fedora WSL: `~/glymur-build`). Because a
full kernel tree is GB-scale, it is published as its **own repository**, not vendored here.
Run `push-fork.sh` from inside that tree — see the script header for usage. Link the fork
back from the main repo's README once it's up.

## Firmware note
The kernel needs Qualcomm/ASUS firmware blobs at runtime (GPU zap shader, etc.). Those are
**not** included — see [`../firmware/README.md`](../firmware/README.md).
