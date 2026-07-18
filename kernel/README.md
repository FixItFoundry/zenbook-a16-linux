# Kernel

The Zenbook A16 bring-up runs on **mainline Linux v7.1** with the glymur boot-critical
drivers force-enabled. The build shipped in the images is **`7.1.0-glymur-clean+`** (v7.1 +
patches, with the experimental `msm`/display mapping reverted for stability). A fuller
`-glymur-full` build with the display experiments also exists but is less stable.

> **Do not build on 7.2 / linux-next.** A regression in the 7.2 cycle broke the working
> glymur chain. Known-good base = **v7.1**.

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
