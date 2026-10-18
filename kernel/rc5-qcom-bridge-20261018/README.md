# Reproduce the Mainline + `qcom-next` / `qcom-topics` Bridge Kernel (`rc5-qcom-bridge-20261018`)

`7.3.0-rc5-ZenbookA16-20261018-rc5-qcom1+` pulls from the mainline Linux v7.3-rc5 release (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`), applies the [64-patch local A16 baseline](../../patches/rc5-20261013/README.md), and bridges the [41-patch `qcom-next` and `qcom-topics` series](../../patches/qcom-glymur-bridge-20261018/README.md) (105 patches total) to reproduce source tree `e9fa73cd5291272d4aef6ea409bcc13b7c5b6d5c`.

Installed systems are updated via scoped post-install hooks (`packaging/zenbook-a16-hooks/`), which automatically rebuild the early-DSP initramfs, stage the verified DTB, link audio UCM2 and WirePlumber policies on UX3607OA hardware, conditionally unmask `/dev/tpm0` when `CONFIG_TCG_QCOM` is enabled, and verify boot entries while preserving rollback kernels.

## Verify and build

From the project root, supply a Linux Git checkout or bare repository containing the base commit (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`). The output directory must not exist.

```sh
python3 kernel/rc5-qcom-bridge-20261018/verify.py /path/to/linux
sudo dnf install bc bison dtc dwarves elfutils-libelf-devel flex gcc git make \
  openssl-devel perl python3 rpm-build rsync
JOBS=4 ./kernel/rc5-qcom-bridge-20261018/build.sh /path/to/linux /path/to/new-output
```

The verifier checks SHA256 hashes and replays all 105 patches in a temporary Git index, leaving `HEAD`, the normal index, and working files untouched.

The build helper uses a separate worktree, applies both patch queues with `git am`, merges [`config`](config) with [`kernel/qcom-glymur-bridge.config`](../qcom-glymur-bridge.config), checks the source tree and release, and builds `Image`, modules, DTB, matching headers, and three RPMs (`BUILD_RPM=0 BUILD_DEB=1` builds Ubuntu/Debian packages instead).

`PACKAGE_REVISION=1` appends `-a16pkg1+` to the recorded release in place of its final `+` so packaged installations never overwrite existing baseline files. See the [package contract](../../packaging/zenbook-a16-kernel/README.md) for post-install hook behavior, boot metadata, and rollback handling.
