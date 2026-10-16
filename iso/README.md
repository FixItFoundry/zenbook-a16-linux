# Zenbook A16 live images and installation

`build-live-images.sh` assembles Fedora or Ubuntu live media around the recorded
A16 kernel. `zenbook-install-to-disk.sh` installs that bundle after the distro
installer has created the target system. These scripts require native aarch64
Linux; the local regression tests do not establish hardware boot acceptance.

## Supported installation contract

- Rebuild the current bundle with `kernel/rc5-20261013/build.sh`. Its
  `lib/modules/$KREL/zenbook-a16-boot.json` records the exact kernel and DTB
  hashes, source tree, required boot settings and pre-root DSP policy.
- Existing bundles with installer-created ABI markers must be rebuilt. The
  installer and image builder cannot declare arbitrary kernels compatible.
- Use a mounted target root and its distro-generated literal `root=` command
  line, including encryption and subvolume settings. Btrfs subvolume roots
  require a separately mounted `/boot`; the historical A16 top-level boot-copy
  arrangement is rejected because its parity is not verified here.
- Generic Arch/Manjaro installation is unsupported by these hooks. Omarchy keeps
  its separate packaged kernel, UKI and transaction-ordering contract under
  `packaging/omarchy-a16-support/`.
- Experimental automatic suspend and xHCI unbinding are not installed.
  [Current hardware limits](../docs/current-build.md) still apply.

## Prepare a live image

Build the matching kernel bundle first, then stage the firmware and live initramfs:

```sh
export KREL="$(cat /path/to/new-output/bundle/usr/share/doc/linux-zenbook-a16/kernel-release)"
export STAGE="$HOME/glymur-images"
mkdir -p "$STAGE"
cp -a /path/to/new-output/bundle/. "$STAGE/"
DEST="$STAGE/firmware" iso/glymur-fetch-firmware.sh --from-linux /path/to/firmware
```

See [firmware requirements](../firmware/README.md). The source must contain the
actual A16 firmware requests; older Bluetooth filenames do not satisfy them.
Build a non-host-only live initramfs with `dmsquash-live`, matching modules and
the installed A16 DSP hook. Supply `systemd-bootaa64.efi` in `$STAGE` as well.
The builder checks inputs and required tools before modifying the live rootfs.

Place a Fedora KDE Live aarch64 ISO or Ubuntu Desktop arm64 ISO under `$STAGE`;
the target functions specify the filename patterns. Then run:

```sh
sudo -E bash iso/build-live-images.sh fedora
# or: sudo -E bash iso/build-live-images.sh ubuntu
```

Output is a compressed partitioned live disk image under `$STAGE/out-live/`.
Write it to a dedicated USB drive using a disk-image writer. It contains an
installer bundle inside the live root filesystem, independent of the mounted ESP.

## Install onto disk

1. Boot the live image and complete the distro's base installation.
2. Keep the target root and its boot/EFI filesystems mounted.
3. Run `sudo zenbook-install-to-disk /mnt/sysimage` for an Anaconda target,
   or supply the actual target mount. The desktop launcher can autodetect
   `/mnt/sysimage`, `/target` or `/mnt`.
4. Resolve any error before rebooting. Missing tools, incompatible artifacts,
   failed package installation, initramfs generation or verification stop the
   script. Existing kernel entries remain available for recovery.

For a bundle containing native packages, keep exactly the current payload,
`zenbook-a16-support` and `zenbook-a16-kernel` packages in `rpms/` or `debs/`.
The installer verifies their package identities and checks the transaction before
writing target artifacts. Fedora uses RPM; Ubuntu uses target APT with downloads
and package removals disabled. Ubuntu needs an existing empty, unmounted `/mnt`
in the target for a temporary read-only package bind. Install missing distro
dependencies before running the installer.

Native packages own the kernel, matching build headers and boot support hooks;
their maintainer scripts generate boot artifacts. Firmware and the installer's
existing platform preferences remain separate. A loose bundle uses the direct-copy
path and does not install external-module build headers. Both paths
refuse any existing artifact for the same kernel release: build a new package
revision instead of overwriting a working release.

The target needs Python, `dtc`, `fdtget`, `findmnt` and its native kernel tools.
Fedora verification uses `lsinitrd`; Ubuntu uses `unmkinitramfs` and `grub-probe`.
The installer lists missing prerequisites before writing target artifacts.

## Persistent updates

Fedora's kernel-install hook stages the matching DTB and updates generated BLS
entries. Ubuntu emits identified A16 GRUB entries with matching DTBs, including
DSP-disabled rescue entries. Both initramfs adapters reuse the same readiness
policy: exact board match, rescue flag, remoteproc readiness, root-mount guard
and device settling. Fedora runs it at pre-mount; Ubuntu at init-premount.
Neither phase is described as running before udev.

New kernel packages must supply matching build metadata. Hooks act on identified
A16 kernels; they cannot apply source patches to installed binary kernels. They
preserve the distro's root options and apply the exact build's additional boot
settings. The current development policy retains `selinux=0` and other recorded
workarounds; that is not a production security or power-management endorsement.

The verifier checks actual arm64 images, matching hashes, enabled SoundWire
keep-active properties, extracted DSP firmware and complete intended boot entries.
Passing it establishes artifact consistency, not successful boot or suspend.
The older v7.1 builders and one-time repository assembly script were retired;
their historical versions remain in Git.
