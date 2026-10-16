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
   The script auto-detects the target root (/mnt/sysimage, /target, or /mnt) and distro,
   copies the custom 7.3 kernel, matching A16 DTB, firmware blobs, platform tweaks,
   and installs persistent kernel-update hooks. It then generates the initramfs in chroot,
   syncs top-level Btrfs `/boot` if needed, and verifies boot integrity via `verify-boot.py`.
4. **Reboot** into your new, fully functional Linux installation.

*Recovery note:* If you accidentally rebooted into an unbootable disk, boot the
live USB again, mount the target root (`sudo mount /dev/nvme0n1p... /mnt`), and
run `sudo zenbook-install-to-disk /mnt`.

## Live Media Architecture

The live image architecture guarantees self-contained reliability:
1. **In-Squashfs Bundle Staging**: Artifacts are staged directly into the live rootfs at
   `/usr/share/zenbook-a16/bundle/` (`vmlinuz-$KREL`, `glymur-asus-zenbook-a16-ux3607oa.dtb`,
   `modules/$KREL/`, `firmware/`, `tweaks/`, and `packaging/`). This ensures `zenbook-install-to-disk`
   always has access to all required assets even if partition 1 (`LIVEESP`) is unmounted.
2. **ASUS-Signed Board Firmware**: `glymur-fetch-firmware.sh` enforces and stages the OEM ASUS-signed
   DSP binaries (`qcadsp8480.mbn`, `adsp_dtbs.elf`, `qccdsp8480.mbn`, `cdsp_dtbs.elf`) and the
   `UX3607OA-tplg.bin` audio topology required by `glymur-asus-zenbook-a16-ux3607oa.dts`.
3. **Early DSP/QRTR Initramfs Ordering**: The live image and persistent hooks load `qrtr`,
   `qcom_pd_mapper`, and `qcom_q6v5_pas` before `systemd-udevd` starts, preventing `msm_drm`
   from racing `cdsp` during device probe.
4. **Persistent Multi-Distro Hooks**:
   - **Fedora**: Dracut module `90zenbook-a16`, `/etc/dracut.conf.d/99-zenbook-a16.conf`, and `/etc/kernel/install.d/95-zenbook-a16.install`.
   - **Ubuntu**: `/etc/initramfs-tools/hooks/zenbook-a16`, `/etc/initramfs-tools/scripts/init-premount/zenbook-a16`, and `/etc/kernel/postinst.d/zz-zenbook-a16`.
   - **Arch**: `/usr/lib/initcpio/install/omarchy-a16-dsp`, `/usr/lib/initcpio/hooks/omarchy-a16-dsp`, and ALPM pre/post transaction hooks.
5. **Boot Verification Gate**: `/usr/lib/zenbook-a16/verify-boot.py` verifies kernel binaries, DTB
   `qcom,keep-runtime-active;` presence, initramfs DSP firmware, and bootloader entries before
   installation completes.

## Prepare the staging directory

The builder defaults to `~/glymur-images`. Copy the live bundle into it, then
add a non-host-only live initramfs and a distro base image:

```sh
export KREL='7.3.0-rc5-glymur-rc5-20261013'
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
├── ath12k/WCN7850/hw2.0/ (or ath12k/QCC2072/hw1.0/)
├── qca/
└── qcom/
    ├── gen80500_sqe.fw
    ├── gen80500_gmu.bin
    └── glymur/ASUSTeK/UX3607OA/
        ├── qcadsp8480.mbn
        ├── adsp_dtbs.elf
        ├── qccdsp8480.mbn
        ├── cdsp_dtbs.elf
        └── UX3607OA-tplg.bin
```

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
