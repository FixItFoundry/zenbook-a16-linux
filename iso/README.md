# Distro images for the Zenbook A16 (aarch64)

How to build **bootable desktop live images** for the A16 carrying the Zenbook A16 kernel + its matching device tree. (No prebuilt images are published — a useful image must bundle proprietary firmware — so you build your own).

---

## ⚠️ Important: Kernel Must Be Built First

The image creation script (`build-live-images.sh`) **does not build or compile the Linux kernel**. It packages an **already-built** kernel, initramfs, DTB, and modules into a bootable rootfs image.

Before running the image builder:
1. **Compile the kernel, DTB, and modules:** Follow the instructions in [`../kernel/rc3-20260919/README.md`](../kernel/rc3-20260919/README.md).
2. **Build the live initramfs:** On an aarch64 host with dracut:
   ```bash
   dracut --force --no-hostonly --add dmsquash-live --kver "$KREL" "$STAGE/initramfs-live-$KREL.img"
   ```
3. **Extract your device firmware:** Follow [`../firmware/README.md`](../firmware/README.md).

---

## Images

Flash the resulting `.img.gz` with **balenaEtcher** or `gunzip -c img.gz | sudo dd of=/dev/sdX bs=4M` to a USB drive (16 GB+) and boot the A16 from it.

| Target | Desktop | Base |
|---|---|---|
| `arch` | KDE Plasma | Reuses Manjaro ARM KDE rootfs |
| `fedora` | KDE Plasma | Reuses Fedora KDE Live aarch64 EROFS rootfs |
| `ubuntu` | GNOME | Reuses Ubuntu desktop arm64 casper squashfs layers |

---

## Running the Live Image Builder

The active live image builder is **`build-live-images.sh`**. It creates a compressed squashfs root with a tmpfs RAM overlay (~3 GB), significantly reducing write wear and boot latency on USB drives compared to raw disk images.

Stage your built kernel artifacts and base distro images into one directory (default `~/glymur-images`):

```bash
export KREL="7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+"
export STAGE="$HOME/glymur-images"
sudo -E bash build-live-images.sh arch fedora ubuntu     # or a single target
```

### Required Files in `$STAGE`:

| File | Source / Description |
|---|---|
| `vmlinuz-$KREL` | `arch/arm64/boot/Image` of the compiled kernel |
| `initramfs-live-$KREL.img` | `dracut --no-hostonly --add dmsquash-live ...` |
| `$KREL.dtb` | `arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb` |
| `modules/$KREL/` | Directory from `make modules_install INSTALL_MOD_PATH=...` |
| `firmware/` | Extracted blobs: `ath12k/`, `qcom/`, `audio/` (see `firmware/README.md`) |
| Distro ISOs | Fedora KDE Live aarch64 ISO, Ubuntu Desktop arm64 ISO, or Manjaro KDE `.img.xz` |

The builder's `preflight()` checks for all required inputs before starting, failing immediately if any prerequisite is missing.
