# Kernel

The Zenbook A16 bring-up tracks **linux-next** and Linux v7.3-rc snapshots; the current base is v7.3-rc5. The A16 device tree is upstream, and a kernel combining the baseline with backports and hardware fixes boots, trains the internal eDP panel, and runs a graphical desktop session.

---

## Current Promoted Baseline (RC5)

The promoted baseline is **`7.3.0-rc5-ZenbookA16-20261002-rc5-integrated1+`** on Linux **v7.3-rc5** (`72d3fcf802c4`). It is installed and is the GRUB default, but has not been booted. The daily-use kernel with boots behind it is still the RC3 baseline below.

RC5 retires our out-of-tree DP `PUSH_IDLE` guard (merged into mainline 7.3 as `e249a6e2a130`), carries the ASUS EC v3 driver series from Konrad Dybcio ([`patches/rc3-ec-v3-hid-20260923/`](../patches/rc3-ec-v3-hid-20260923/README.md)), and stages PMH0104 camera LDOs for OV02C10 camera bring-up. All 23 retained RC3 patches applied to rc5 unchanged.

Complete reproduction instructions, exact `.config`, checksums, and patch series are documented in:
👉 **[kernel/rc5-20261002/README.md](rc5-20261002/README.md)**

### Quick build

From the project root, give the build helper a Linux Git repository containing
the recorded base commit and a new output path. A bare repository works as well
as a checkout:

```bash
JOBS=8 ./kernel/rc5-20261002/build.sh /path/to/linux /path/to/new-output
```

It verifies and applies the exact patch series in an isolated worktree, checks
the resulting source identity, and builds the Image, modules, DTB, and an
installable RPM. See the RC5 README above for dependencies, outputs, manual
steps, and the distinction between live-USB files and an installed kernel.

---

## Kernel Contents

- `rc5-20261002/` — The current build package: build metadata, exact kernel config, verification script, and SHA256 checksums.
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
