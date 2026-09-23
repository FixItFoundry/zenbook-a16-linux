# Kernel

The Zenbook A16 bring-up tracks **linux-next** and Linux v7.3-rc snapshots. The A16 device tree is upstream, and a kernel combining the baseline with backports and hardware fixes boots, trains the internal eDP panel, and runs a graphical desktop session.

---

## Current Promoted Baseline (RC3)

The active daily-use kernel baseline is **`7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+`**.

Complete reproduction instructions, exact `.config`, checksums, and patch series are documented in:
👉 **[kernel/rc3-20260919/README.md](rc3-20260919/README.md)**

### Quick Build Steps:

1. Clone or navigate to a Linux kernel checkout containing base commit `fd73f4a6659897191fa0d40695fe370925dd3780`.
2. Apply the 24-patch series from `patches/rc3-20260919/series`:
   ```bash
   git switch --detach fd73f4a6659897191fa0d40695fe370925dd3780
   while IFS= read -r patch; do
       git am "$REPO/patches/rc3-20260919/$patch"
   done < "$REPO/patches/rc3-20260919/series"
   ```
3. Copy the verified build configuration:
   ```bash
   cp "$REPO/kernel/rc3-20260919/config" "$BUILD_DIR/.config"
   make O="$BUILD_DIR" LOCALVERSION=+ olddefconfig
   make O="$BUILD_DIR" LOCALVERSION=+ -j"$(nproc)" Image modules dtbs
   ```

Verification script:
```bash
python3 kernel/rc3-20260919/verify.py /path/to/linux
```

---

## Kernel Contents

- `rc3-20260919/` — The complete build package: build metadata, exact kernel config, verification script, and SHA256 checksums.
- `CONFIG_FRAGMENT.md` — Reference config fragment for earlier v7.1 builds.
- `gpucc-x2.c` — Reference stub for the sm8750 GPU clock controller.
- `soccp_glink.c` — Legacy standalone loader (now integrated natively).
- `push-fork.sh` — Script to publish a standalone kernel fork repository.

---

## Firmware Note

The kernel requires Qualcomm/ASUS proprietary firmware blobs at runtime (ADSP, CDSP, GPU zap shader, Wi-Fi 7). These are **not** redistributed in this repository; see [`../firmware/README.md`](../firmware/README.md) for extraction instructions.
