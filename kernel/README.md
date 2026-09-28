# Kernel

The Zenbook A16 bring-up tracks **linux-next** and Linux v7.3-rc snapshots. The A16 device tree is upstream, and a kernel combining the baseline with backports and hardware fixes boots, trains the internal eDP panel, and runs a graphical desktop session.

---

## Current Promoted Baseline (RC3)

The active daily-use kernel baseline is **`7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+`**.

Complete reproduction instructions, exact `.config`, checksums, and patch series are documented in:
👉 **[kernel/rc3-20260919/README.md](rc3-20260919/README.md)**

### Quick build

From the project root, give the build helper a Linux Git checkout containing
the recorded base commit and a new output path:

```bash
JOBS=4 ./kernel/rc3-20260919/build.sh /path/to/linux /path/to/new-output
```

It verifies and applies the exact patch series in an isolated worktree, checks
the resulting source identity, and builds the Image, modules, DTB, and an
installable RPM. See the RC3 README above for dependencies, outputs, manual
steps, and the distinction between live-USB files and an installed kernel.

---

## Kernel Contents

- `rc3-20260919/` — The complete build package: build metadata, exact kernel config, verification script, and SHA256 checksums.
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
