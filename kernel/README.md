# Kernel

The Zenbook A16 bring-up tracks **linux-next** and Linux v7.3-rc snapshots; the current base is v7.3-rc5. The A16 device tree is upstream, and a kernel combining the baseline with backports and hardware fixes boots, trains the internal eDP panel, and runs a graphical desktop session.

---

## Current Promoted Baseline (RC5)

The working audio baseline is **`7.3.0-rc5-ZenbookA16-20261008-rc5-audiopm1+`**
on Linux **v7.3-rc5** (`72d3fcf802c4`). Native boot/artifact checks, all four
physical speaker channels and a short guarded CPU/Vulkan screen passed on
October 12. Audio controller autosuspend is disabled by an explicit board
opt-in; full platform stability, battery and suspend remain open.

The exact tested source, configuration and 59-patch series are in
**[kernel/rc5-20261008/README.md](rc5-20261008/README.md)**.
See the [current build record](../docs/current-build.md) for evidence and limits.
The saved boot default and old fallback packages remain intact.

### Quick build

From the project root, give the build helper a Linux Git repository containing
the recorded base commit and a new output path. A bare repository works as well
as a checkout:

```bash
JOBS=4 ./kernel/rc5-20261008/build.sh /path/to/linux /path/to/new-output
```

It verifies and applies the exact patch series in an isolated worktree, checks
the resulting source identity, and builds the Image, modules, DTB, and an
installable RPM. See the RC5 README above for dependencies, outputs, manual
steps, and the distinction between live-USB files and an installed kernel.

---

## Kernel Contents

- `rc5-20261008/` — Current audio baseline: build metadata, exact config, verifier and SHA256 checksums.
- `rc5-20261002/` — Retained prior RC5 integrated package and saved boot default.
- `rc3-20260919/` — The previous build package, reproducing the proven fallback kernel.
- `CONFIG_FRAGMENT.md` — Reference config fragment for earlier v7.1 builds.
- `gpucc-x2.c` — Reference stub for the sm8750 GPU clock controller.
- `soccp_glink.c` — Legacy standalone loader (now integrated natively).
- `push-fork.sh` — Script to publish a standalone kernel fork repository.

---

## Firmware note

The kernel needs matching ADSP, CDSP, GPU, Wi-Fi, Bluetooth, and audio-topology
files at runtime. Most are now redistributable through upstream linux-firmware;
see [`../firmware/README.md`](../firmware/README.md) for the exact paths and the
model-specific topology build.
