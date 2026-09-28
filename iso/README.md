# Zenbook A16 live images

`build-live-images.sh` assembles bootable aarch64 live media around the
promoted A16 kernel. It does not compile the kernel and it is not a disk
installer.

## Installing onto the target hard drive

The live USB boots with our custom kernel, DTB, and firmware in a temporary RAM
overlay. Distro installers (such as Fedora's Anaconda) install stock distro
packages to the target disk — they do not automatically copy custom kernels,
DTBs, or proprietary firmware to the internal drive.

To install the custom kernel and platform support onto the target disk:

1. **Boot the live USB** on the Zenbook A16.
2. **Run the distro installer** (e.g. click "Install to Hard Drive" in Anaconda)
   and complete the disk partitioning and base installation.
3. **Before rebooting**, run the bundled installation script from the live desktop:
   - Double-click the **"Install Zenbook A16 Kernel to Disk"** desktop icon, or
   - Open a terminal and run:
     ```sh
     sudo zenbook-install-to-disk
     ```
   The script installs the custom 7.3-rc3 kernel, matching A16 DTB, firmware blobs,
   power tweaks, and configures the target GRUB/BLS bootloader with the required
   kernel cmdline parameters (`clk_ignore_unused pd_ignore_unused cma=128M glymur_pci_skip=5`).
4. **Reboot** into your new, fully functional Linux installation.

*Recovery note:* If you accidentally rebooted into an unbootable disk, boot the
live USB again, mount the target root (`sudo mount /dev/nvme0n1p... /mnt`), and
run `sudo zenbook-install-to-disk /mnt`.

## Prepare the staging directory

The builder defaults to `~/glymur-images`. Copy the live bundle into it, then
add a non-host-only live initramfs and a distro base image:

```sh
export KREL='7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+'
export STAGE="$HOME/glymur-images"

mkdir -p "$STAGE"
cp -a /path/to/new-output/bundle/. "$STAGE/"
dracut --force --no-hostonly --add dmsquash-live \
  --kver "$KREL" --kmoddir "$STAGE/modules/$KREL" \
  "$STAGE/initramfs-live-$KREL.img"
```

Populate `$STAGE/firmware/` as described in
[`../firmware/README.md`](../firmware/README.md). The required layout includes:

```text
firmware/
├── ath12k/QCC2072/hw1.0/
├── qca/
└── qcom/glymur/
```

Do not flatten these directories. In particular,
`ath12k/QCC2072/hw1.0/firmware-2.bin` and
`qcom/glymur/adsp.mbn` must retain their parent directories. Build and install
the model-specific topology as
`qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin` using
[`../firmware/tplg/README.md`](../firmware/tplg/README.md).

Add the base image needed by the selected target:

| Target | Base image placed in `$STAGE` | Desktop |
|---|---|---|
| `fedora` | Fedora KDE Live aarch64 ISO | KDE Plasma |
| `ubuntu` | Ubuntu Desktop arm64 ISO | GNOME |
| `arch` | Manjaro ARM KDE `.img.xz` | KDE Plasma |

The exact filename patterns are in the target functions in
`build-live-images.sh`. The
script checks the kernel, modules, DTB, live initramfs, EFI loader, and each
required firmware file before modifying a root filesystem. Missing inputs or a
failed target now produce a nonzero exit status.

## Build and write the live image

Run one target at a time while diagnosing a build:

```sh
cd iso
sudo -E bash ./build-live-images.sh fedora
```

Results are written below `$STAGE/out-live/`. Decompress the selected `.img.gz`
and write it to a dedicated USB drive with a tool such as Fedora Media Writer,
balenaEtcher, or `dd`. Double-check the destination device before writing it.

The live root uses a RAM overlay. Changes made during a live session, including
package installation, do not by themselves become part of the installed disk.
