# Reproduce the RC5 soc2 baseline

`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+` became the repository and future-testing
baseline on October 14. See the [validation record](../../docs/current-build.md) for its limits.

The [64-patch series](../../patches/rc5-20261013/README.md) reproduces source tree
`e3af70b5403334c7d762fdb00b0a7cdfbb5a362c` from Linux v7.3-rc5
`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`. `build.json` pins the identity;
`config` is the tested configuration, built with Ubuntu GCC `15.2.0-16ubuntu1`.

## Verify and build

From the project root, supply a Linux Git checkout or bare repository containing
the base commit. The output directory must not exist for a fresh build.

```sh
python3 kernel/rc5-20261013/verify.py /path/to/linux
sudo dnf install bc bison dtc dwarves elfutils-libelf-devel flex gcc git make \
  openssl-devel perl python3 rpm-build rsync
JOBS=4 ./kernel/rc5-20261013/build.sh /path/to/linux /path/to/new-output
```

After fixing a build or packaging error, reuse the same directory and environment:

```sh
JOBS=4 ./kernel/rc5-20261013/build.sh --resume /path/to/linux /path/to/new-output
```

Resume preserves `.config` and compiled objects, and verifies the source tree and
kernel release again. It refuses modified worktrees, another repository's worktree,
or incomplete patch application; those require correction or a fresh output directory.

The verifier checks hashes and replays patches in a temporary index; it leaves
HEAD, the normal index and working files intact. It may add Git objects.

The build helper uses a separate worktree, applies the series with `git am`, checks
the tree and release, then builds Image, modules, DTB, matching headers and three
Ubuntu DEBs. `BUILD_RPM=1 BUILD_DEB=0` builds Fedora packages instead. The helper has no
thermal guard.

`PACKAGE_REVISION=1` adds `-a16pkg1+` to the recorded release in place of its final
`+`. Source patches and the checked-in configuration are unchanged; the separate
release protects the installed kernel's files. Increase the revision for later
rebuilds. See the [package contract](../../packaging/zenbook-a16-kernel/README.md)
for scoped hooks, boot metadata and rollback handling.

The tested soc2 binaries were already built and booted. Publication verifies
source replay and configuration; it does not repeat the full build or RPM installation.
Toolchain, timestamps and generated signing keys can change binary hashes.

## Boot

Use matching Image/modules/DTB/initramfs and [board firmware](../../firmware/README.md).
The helper does not generate an initramfs, install the kernel or select GRUB entries.
The [boot record](../../docs/current-build.md#boot-and-rollback) retains the audiopm1
saved fallback and Windows route; older packages remain available.
