# Distro images for the Zenbook A16 (aarch64)

How to build **bootable desktop images** for the A16 carrying the Zenbook A16 tracking kernel
(`7.2.0-rc6-ZenbookA16-20260807`, built from linux-next) + its matching device tree. (No prebuilt
images are published — a useful one would have to bundle proprietary firmware — so you build your
own; it's mostly automated.)

## Images (build your own — none are published)

We deliberately **don't ship flashable images**: a *useful* one would have to bundle proprietary
firmware (see [`../firmware/README.md`](../firmware/README.md)). Build them yourself with the
reuse-rootfs process below — these are the distro/desktop combos validated on the A16. Once built,
flash `.img.gz` with **balenaEtcher** (reads `.img.gz` directly) or
`gunzip -c img.gz | sudo dd of=/dev/sdX bs=4M` to a **16 GB+** stick and boot the A16 from it.

| Image | Desktop | Status |
|---|---|---|
| `arch-manjaro-kde.img.gz` | Manjaro (Arch) + KDE Plasma | boots to desktop (validated on the old software-rendered build) |
| `fedora-glymur-kde.img.gz` | Fedora 44 + KDE Plasma | boots to desktop (validated on the old software-rendered build) |
| `ubuntu-glymur-gnome.img.gz` | Ubuntu + GNOME | built (reuses the Ubuntu desktop rootfs) |

⚠️ **Those ✅ marks were earned by the 7.1 images and do not transfer.** The kernel underneath
changed completely on 2026-08-08 and the images have not been re-validated on hardware yet.

Confirmed from the earlier images: keyboard + backlight, trackpad, Wi-Fi, USB (incl. USB NIC),
audio (speakers + internal DMIC), battery %. Full works/doesn't list: repo README.

### What changed on 2026-08-08

The old images shipped `modprobe.blacklist=msm` on the cmdline, so the display ran on
`simple-framebuffer` — software rendering, because at the time `msm` could not light the panel.
**That blacklist is gone.** eDP now trains at HBR3 and the Adreno X2 renders under turnip, so
these images get a real accelerated desktop. `efi=noruntime` (retired 2026-07-30),
`arm64.nopauth` and `kvm-arm.mode=protected` are also gone — none of them are in the cmdline the
laptop actually daily-drives.

The builder no longer needs an aarch64 host, and no longer hardcodes a WSL layout. It only
extracts rootfs images and copies files into them; nothing from the target rootfs is executed.
Every path is an environment variable — see the block at the top of the script.

> **Firmware is NOT redistributed.** Proprietary Qualcomm firmware (`ath12k`, `qcom/glymur`,
> `regulatory.db`) is not shipped in this repo or its Release images. Wi‑Fi/audio need you to drop
> your own into `/lib/firmware` first — pull it from your device's Windows/WoA install. See
> [`../firmware/README.md`](../firmware/README.md) and [`../LOCAL-TWEAKS.md`](../LOCAL-TWEAKS.md) §1.

## Boot cmdline
The images carry the cmdline the laptop actually daily-drives:

```
rw clk_ignore_unused pd_ignore_unused cma=128M glymur_pci_skip=5 console=tty0
ignore_loglevel rd.timeout=60 panic=10 systemd.mask=dev-tpm0.device
systemd.mask=dev-tpmrm0.device
```

`glymur_pci_skip=5` is the suspend workaround — PCI config access in `dpm_suspend_noirq` resets
the SoC. It is a local kernel knob, so it only does anything on a kernel built from this tree.

⛔ **`modprobe.blacklist=msm` and `kvm-arm.mode=protected` were removed on 2026-08-08.** The
blacklist is why the old images were software-rendered; it is no longer needed or wanted.

⚠️ `efi=noruntime` used to be listed here as mandatory. **It was retired on 2026-07-30** —
the warm-reset claim was never reproducible on a clean tree, and dropping it changes no
capability: efivars are unreachable either way, because this firmware reports EFI *variable*
services as `EFI_UNSUPPORTED` (`0x8000000000000003`). See


⚠️ **Correction (2026-07-30, later the same day):** do not treat "this firmware does not support EFI variable services" as settled. Two archived `efi_pstore` crash dumps prove variable services **worked** on this same machine and firmware under 7.1 kernels. The `EFI_UNSUPPORTED` result above is real but is specific to our 7.2-rc3 build, and the cause is **unresolved**. See [`../docs/hardware.md`](../docs/hardware.md).
[`../docs/modifications.md`](../docs/modifications.md).

## How the images are built
Instead of emulated package installs, each image **reuses a stock desktop rootfs** and swaps in
our kernel + DTB + initramfs + firmware + tweaks, then writes the boot loader entry. The builder
is `build-all-overnight.sh` (targets: `arch`, `fedora`, `ubuntu`); the firmware + tweak overlays
(`a16-fw.tar.gz`, `a16-tweaks.tar.gz` — audio route, kbd backlight, battery autoload, thermal
guard) are applied by its `addfw()` step.

Source notes:
- **Manjaro (Arch):** Arch has no aarch64 desktop ISO, so we reuse the **Manjaro ARM KDE** image —
  the cleanest path to a working Arch-family desktop. (CachyOS is x86-only; don't use it.)
- **Fedora:** Fedora 44's Live root is an **EROFS with LZMA** — note the file is still *named*
  `LiveOS/squashfs.img`, so `unsquashfs` fails on it with "can't find a valid SQUASHFS
  superblock". Use `erofs-utils`.

  ⚠️ **Corrected 2026-08-02: the old claim that x86 tooling can't read it is obsolete.**
  `erofs-utils` 1.9.2 on x86_64 Fedora 44 lists `lzma` among its decompressors and extracts it
  fine. Extracting natively on the A16 is no longer necessary.

  ⛔ **`--path=/` is REQUIRED when extracting.** Without it, `fsck.erofs --extract=DIR` silently
  writes the *packed inode* as a single ~4.6 GB file instead of a directory tree, and reports
  success. Correct form:

  ```sh
  fsck.erofs --extract=<dir> --path=/ --preserve LiveOS/squashfs.img
  ```

  Extract and repack inside `unshare -r` — `--preserve` restores root ownership, and without a
  user namespace you cannot then delete or modify the tree unprivileged.
- **Ubuntu:** the casper `minimal` + desktop squashfs layers.

## Running the builder

Stage the kernel artifacts and the distro source images in one directory (default
`~/glymur-images`), then run it as root. **Any x86_64 or aarch64 Linux host works** — the script
never executes anything out of the target rootfs.

```bash
export KREL=7.2.0-rc6-ZenbookA16-20260807
export STAGE=~/glymur-images
sudo -E bash build-all-overnight.sh arch fedora ubuntu     # or one target at a time
```

`$STAGE` must contain:

| file | from |
|---|---|
| `vmlinuz-$KREL` | `arch/arm64/boot/Image` of the build |
| `initramfs-$KREL.img` | `dracut --no-hostonly` against that kernel |
| `$KREL.dtb` | `glymur-asus-zenbook-a16-ux3607oa.dtb` of the build, renamed to match |
| `modules/$KREL/` | `make modules_install INSTALL_MOD_PATH=…` |
| `firmware/` | your own extracted blobs — `ath12k/ qca/ qcom/ audio/` (**not redistributed**) |
| the distro images | Fedora KDE Live aarch64 ISO, Ubuntu desktop arm64 ISO, Manjaro ARM KDE `.img.xz` |

The script downloads the Manjaro image itself if it is missing; the Fedora and Ubuntu ISOs you
supply. `preflight` refuses to start if anything is absent, so a missing input fails in two
seconds rather than forty minutes in.

## Boot-testing note
The kernel targets glymur, so these images **only meaningfully boot on the A16 itself**.
A generic `qemu-system-aarch64` VM would only exercise the stock distro kernel, not ours.

The per-distro scripts under `arch/`, `fedora/`, `ubuntu/` are the earlier ISO-injection approach,
kept for reference; the reuse-rootfs imager above is what produced the validated images.
