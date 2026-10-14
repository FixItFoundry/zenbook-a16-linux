# Reproduce the working RC5 audio baseline

`7.3.0-rc5-ZenbookA16-20261008-rc5-audiopm1+` was built on October 8 and
promoted to the repository's working audio bringup baseline on October 12.
Four physical speaker channels were confirmed by the user on the tested boot.
The [October 12 build record](../../docs/build-20261012.md) defines the acceptance
limits: this includes a local workaround that keeps both speaker controllers
runtime active. Efficient audio power management and platform stability remain
open.

`build.json` records Linux v7.3-rc5 as the base and source tree
`14fd463c06510c760dde22ef215fcbd0bff9a898` after the complete
[59-patch series](../../patches/rc5-20261008/README.md). `config` is the exact
configuration from the successful native build, using Fedora GCC
`16.2.1 20260819 (Red Hat 16.2.1-2)`. This is a source/configuration reproduction
package; toolchain, timestamps and packaging can change binary hashes. It
contains no firmware binaries or private signing keys.

## Verify

From the project root, pass a Linux Git checkout or bare repository containing
base commit `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`:

```sh
python3 kernel/rc5-20261008/verify.py /path/to/linux
```

The verifier checks the shipped checksums and replays every patch into a
temporary index, then compares the exact source tree. It leaves HEAD, the normal
index and working files intact; reconstructed Git objects may be stored in the
supplied repository. The October 12 replay passed.

## Build

On Fedora, install the normal build dependencies:

```sh
sudo dnf install bc bison dwarves elfutils-libelf-devel flex gcc git make \
  openssl-devel perl python3 rpm-build rsync
JOBS=4 ./kernel/rc5-20261008/build.sh /path/to/linux /path/to/new-output
```

The helper follows the existing dated-package workflow: verify, create a
separate worktree, apply the series with `git am`, check its tree, regenerate
the supplied config, check the release, then build Image, modules, DTB and RPMs.
The output directory must be new. `BUILD_RPM=0` produces only the loose-file
bundle. Four jobs match the guarded native build's concurrency, but this helper
itself does not implement the private thermal/fault guard.

The installed October 8 Image/modules/DTB were already built successfully and
their installed payload was verified on October 12. This export was replayed
and its helper checked; a new full compilation or RPM installation was not
performed during promotion.

## Boot and rollback

Use matching Image, modules, board DTB and initramfs, including the board ADSP
firmware and topology. The helper does not create an initramfs, install the
kernel or select a GRUB entry. See [firmware guidance](../../firmware/README.md)
and the [October 12 boot record](../../docs/build-20261012.md#boot-and-rollback).

Keep the old [RC5 integrated package](../rc5-20261002/README.md) and
[RC3 fallback package](../rc3-20260919/README.md). Repository promotion does not
change the saved boot default or EFI order. Continue to use the existing
distinct audiopm1 entry for this kernel until boot selection is deliberately
changed.
