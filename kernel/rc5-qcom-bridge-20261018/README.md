# Reproduce the Mainline + `qcom-next` / `qcom-topics` Bridge Kernel (`rc5-qcom-bridge-20261018`)

`7.3.0-rc5-ZenbookA16-20261018-rc5-qcom1+` pulls from the mainline Linux v7.3-rc5 release (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`), applies the [64-patch local A16 baseline](../../patches/rc5-20261013/README.md), and bridges the [40-patch `qcom-next` and `qcom-topics` series](../../patches/qcom-glymur-bridge-20261018/README.md) (104 patches total) to reproduce source tree `65fd4b07749a5d6b48f5b2dbbfc3e78681f04bf1`.

Installed systems are updated via scoped post-install hooks (`packaging/zenbook-a16-hooks/`), which automatically rebuild the early-DSP initramfs, stage the verified DTB, link audio UCM2 and WirePlumber policies on UX3607OA hardware, conditionally unmask `/dev/tpm0` when `CONFIG_TCG_QCOM` is enabled, and verify boot entries while preserving rollback kernels.

## Verify and build

From the project root, supply a Linux Git checkout or bare repository containing the base commit (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`). The output directory must not exist for a fresh build.

```sh
python3 kernel/rc5-qcom-bridge-20261018/verify.py /path/to/linux
sudo dnf install bc bison dtc dwarves elfutils-libelf-devel flex gcc git make \
  openssl-devel perl python3 rpm-build rsync
JOBS=4 ./kernel/rc5-qcom-bridge-20261018/build.sh /path/to/linux /path/to/new-output
```

After fixing a build or packaging error, reuse the same directory and environment:

```sh
JOBS=4 ./kernel/rc5-qcom-bridge-20261018/build.sh --resume /path/to/linux /path/to/new-output
```

Resume preserves `.config` and compiled objects, and verifies the source tree and
kernel release again. It refuses modified worktrees, another repository's worktree,
or incomplete patch application; those require correction or a fresh output directory.

The verifier checks SHA256 hashes and replays all 104 patches in a temporary Git index, leaving `HEAD`, the normal index, and working files untouched.

The build helper uses a separate worktree, applies both patch queues with `git am`, merges [`config`](config) with [`kernel/qcom-glymur-bridge.config`](../qcom-glymur-bridge.config), checks the source tree and release, and builds `Image`, modules, DTB, matching headers, and Ubuntu/Debian DEBs (`BUILD_RPM=1 BUILD_DEB=0` builds Fedora RPMs instead).

`PACKAGE_REVISION=1` appends `-a16pkg1+` to the recorded release in place of its final `+` so packaged installations never overwrite existing baseline files. See the [package contract](../../packaging/zenbook-a16-kernel/README.md) for post-install hook behavior, boot metadata, and rollback handling.
