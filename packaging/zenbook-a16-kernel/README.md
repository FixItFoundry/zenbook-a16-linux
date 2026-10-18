# Managed A16 kernel packages

Fedora is the first native package target; Ubuntu uses the same verified payload
and boot policy. Arch uses the split kernel and support package workflow with
post-install hooks. These recipes are development drafts: package fixtures pass,
but native transactions and physical boot/rollback still need acceptance. They
do not make the RC kernel production-ready.

## Build without installing

Run from this repository on a native aarch64 Linux build machine. Supply a kernel
Git repository containing the pinned mainline base ([`rc5-qcom-bridge-20261018`](../../kernel/rc5-qcom-bridge-20261018/build.json) or [`rc5-20261013`](../../kernel/rc5-20261013/build.json)).
The output directory must not exist. The helper creates a separate source worktree.

```sh
# Fedora (mainline release + qcom-next / qcom-topics bridge):
JOBS=4 PACKAGE_REVISION=1 BUILD_RPM=1 BUILD_DEB=0 \
  ./kernel/rc5-qcom-bridge-20261018/build.sh /path/to/linux /path/to/fedora-build

# Ubuntu (mainline release + qcom-next / qcom-topics bridge):
JOBS=4 PACKAGE_REVISION=1 BUILD_RPM=0 BUILD_DEB=1 \
  ./kernel/rc5-qcom-bridge-20261018/build.sh /path/to/linux /path/to/ubuntu-build
```

Both builds require Python, `dtc`, `fdtget`, GNU coreutils and the kernel's compiler,
libelf/OpenSSL development files, bison, flex, bc, pahole, Perl and rsync.
Builds do not install packages, generate host boot entries or change the default.
`BUILD_RPM=0 BUILD_DEB=0` stages only the portable bundle. Packages go in
`bundle/rpms/` or `bundle/debs/`.

The kernel source pulls from the mainline release base (`v7.3-rc5`), applies the
local A16 series and the `qcom-next`/`qcom-topics` bridge patches, and merges
[`kernel/qcom-glymur-bridge.config`](../../kernel/qcom-glymur-bridge.config).
The new release ends in `-a16pkg1+`, replacing its original final `+`, so its modules
cannot overwrite the installed baseline. Increase `PACKAGE_REVISION` for each
new rebuild; never distribute different bytes with the same release identity.
This is a source/configuration rebuild, not a promise of byte-identical binaries.

## Package ownership and post-install hook updates

Each native build produces three packages:

| Package | Owns |
|---|---|
| `kernel-zenbook-a16-<release>` (Fedora), `linux-image-<release>` (Ubuntu) | Versioned Image, modules, build headers, config, DTB, boot metadata, and `zenbook-a16-dsp-abi = 1` capability |
| `zenbook-a16-support` | Scoped initramfs hooks, boot generation, verification, rollback helpers, staged ALSA UCM2/WirePlumber/platform configs, and `activate-hardware` post-install hook |
| `zenbook-a16-kernel` | Dependency on the exact current payload version |

Package names use the lowercase release; files retain its original spelling.
Headers live at `/usr/lib/modules/<release>/build`. Metadata there records the
source tree, release, package family/version, Image/DTB/config hashes, command line
and DSP policy. Packaging rejects missing/mismatched headers or artifacts.

A tracking-package upgrade adds a new payload package rather than replacing the
previous payload. It also updates shared support hooks and runs `activate-hardware`
in post-install to link UX3607OA audio/platform configs into `/etc` and conditionally
unmask `/dev/tpm0` and `/dev/tpmrm0` when `CONFIG_TCG_QCOM` is enabled in the kernel
config. Fedora marks payloads as install-only; Ubuntu supplies an APT never-auto-remove
rule for this family. There is no automatic kernel pruning. Manual removal refuses a
running managed kernel or the recorded rollback kernel.

Future package-manager updates require publishing each rebuilt/tested set to a
signed RPM/APT repository. No repository is configured or published here. A new
upstream source needs patch replay, conflict resolution and testing before a new
package is built. A post-install hook cannot apply these C/DTS patches to a binary
Fedora or Ubuntu kernel. Stock kernels bypass the A16 hooks.

## Boot and rollback contract

Install all three packages together only after native transaction testing. The
live installer checks package identities and dependency resolution first. Firmware
is supplied separately and must pass `glymur-fetch-firmware.sh --check`; these
packages do not replace the installer's audio/platform setup.

Before unpacking a new kernel, the package checks for release collisions and saves
the existing default in `/var/lib/zenbook-a16/rollback.json`. Fedora requires an
installed literal root command line in `/etc/kernel/cmdline`. Ubuntu derives it
from the selected installed entry when absent. Both require an existing kernel
and a resolvable boot entry; the package does not create a bootloader from scratch.
Btrfs subvolume roots require a separately mounted `/boot`. The current machine's
historical top-level boot-copy arrangement remains unsupported.

Ubuntu pins a stable version-specific GRUB ID in
`/etc/default/grub.d/99-zenbook-a16-default.cfg`; its generic newest-kernel entry
cannot serve as a rollback identity. Fedora restores its saved BLS selection.
The old default stays selected after adding a kernel, including after an initramfs
failure. If restoration fails, the transaction reports an error. Choose a new
entry manually for testing; do not reboot after an unsuccessful verification.
Changing the saved default later requires reviewing the stored rollback policy;
subsequent A16 upgrades refuse a conflicting default instead of replacing it.

Only metadata-identified A16 kernels receive DSP setup and board-specific entries.
Missing or damaged metadata on a managed release is an error. Legacy global
hooks are removed only when their hashes match the exact previously shipped
files; modified copies block migration for review. Migration also refuses to
remove the old global blacklist while an existing DSP-off rescue entry lacks
`module_blacklist=qcom_q6v5_pas`; review that entry first. New rescue entries carry
both flags. A previous kernel remains the independent rollback option.

Package transactions are not atomic across firmware, boot files and their package
database. A failed post-install can leave a new package unpacked/unconfigured;
the earlier kernel remains installed and selected. Keep its complete boot files
and an independent recovery device. Distro-managed kernels remain subject to
their distro's retention policy.

## Arch and release acceptance

Reuse the shared Arch kernel/support ABI (`zenbook-a16-dsp-abi = 1`) and Limine
post-install hook workflow described in the
[Arch support package](../omarchy-a16-support/PKGBUILD.in). The optional
[standalone Arch build](../../kernel/arch-7.2.10/BUILD-AND-UPGRADE.txt) now has
versioned payloads, headers, metadata and UKI presets. It does not claim the shared
DSP ABI. Automatic standalone Limine updates remain blocked by external global
DTB selection; explicit UKI generation/signing and verification are required.

Before publishing a stable channel, test native RPM/DEB transactions, two-version
coexistence, stock-kernel updates, failure recovery and physical boot/rollback.
Current GPU acceptance, sleep, hibernate, camera and IR limits remain in the
[hardware record](../../docs/current-build.md). The retained `selinux=0` and other
development boot settings also need a release decision.

Local fixture check: `python3 packaging/zenbook-a16-kernel/test_package.py`.
