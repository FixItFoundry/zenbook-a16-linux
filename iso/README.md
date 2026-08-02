# Distro images for the Zenbook A16 (aarch64)

How to build **bootable desktop images** for the A16 carrying the glymur `7.1.0-glymur-clean+`
kernel + the `test55` device tree + tweak overlays. (No prebuilt images are published — a useful
one would have to bundle proprietary firmware — so you build your own; it's mostly automated.)

## Images (build your own — none are published)

We deliberately **don't ship flashable images**: a *useful* one would have to bundle proprietary
firmware (see [`../firmware/README.md`](../firmware/README.md)). Build them yourself with the
reuse-rootfs process below — these are the distro/desktop combos validated on the A16. Once built,
flash `.img.gz` with **balenaEtcher** (reads `.img.gz` directly) or
`gunzip -c img.gz | sudo dd of=/dev/sdX bs=4M` to a **16 GB+** stick and boot the A16 from it.

| Image | Desktop | Status |
|---|---|---|
| `arch-manjaro-kde.img.gz` | Manjaro (Arch) + KDE Plasma | **✅ boots to desktop on the A16** |
| `fedora-glymur-kde.img.gz` | Fedora 44 + KDE Plasma | **✅ boots to desktop on the A16** |
| `ubuntu-glymur-gnome.img.gz` | Ubuntu + GNOME | built (reuses the Ubuntu desktop rootfs) |

Confirmed from these images: keyboard + backlight, trackpad, Wi-Fi, USB (incl. USB NIC), audio
(speakers + internal DMIC), battery %, and the interim thermal guard. Display is
`simple-framebuffer` (software rendering — usable, not fast). Full works/doesn't list: repo README.

> **Firmware is NOT redistributed.** Proprietary Qualcomm firmware (`ath12k`, `qcom/glymur`,
> `regulatory.db`) is not shipped in this repo or its Release images. Wi‑Fi/audio need you to drop
> your own into `/lib/firmware` first — pull it from your device's Windows/WoA install. See
> [`../firmware/README.md`](../firmware/README.md) and [`../LOCAL-TWEAKS.md`](../LOCAL-TWEAKS.md) §1.

## Boot cmdline
`modprobe.blacklist=msm` and `kvm-arm.mode=protected` per the working config.

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

## Building from source (optional)
On an aarch64 host (or the A16), with the kernel artifacts + overlays staged:
```bash
sudo bash build-all-overnight.sh arch fedora ubuntu
```
Artifacts used: `vmlinuz-7.1.0-glymur-clean+`, its `lib/modules/7.1.0-glymur-clean+`,
`glymur-a16-test55.dtb`, plus `a16-fw.tar.gz` + `a16-tweaks.tar.gz`.

## Boot-testing note
The glymur kernel targets `sm8750`, so these images **only meaningfully boot on the A16 itself**.
A generic `qemu-system-aarch64` VM would only exercise the stock distro kernel, not glymur.

The per-distro scripts under `arch/`, `fedora/`, `ubuntu/` are the earlier ISO-injection approach,
kept for reference; the reuse-rootfs imager above is what produced the validated images.
