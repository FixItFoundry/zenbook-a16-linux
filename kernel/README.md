# Kernel packages

For the current shared Omarchy `7.2.8-24` candidate, see [Omarchy status](../docs/omarchy-status.md). The packages below are this repository’s rc5 development/validation tracks and retained Arch backport; their build commands do not produce that Omarchy candidate.

The repository pulls from the mainline Linux v7.3-rc5 release (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`), with both the boot-validated **`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+`** baseline and the **`7.3.0-rc5-ZenbookA16-20261018-rc5-qcom1+`** bridge package incorporating Qualcomm's `qcom-next` and `qcom-topics` series. Installed systems are updated via scoped post-install hooks.

See the [bridge build package](rc5-qcom-bridge-20261018/README.md), [soc2 baseline package](rc5-20261013/README.md), and [validation record](../docs/current-build.md).

```sh
# Mainline release + qcom-next / qcom-topics bridge (104 patches):
python3 kernel/rc5-qcom-bridge-20261018/verify.py /path/to/linux
JOBS=4 ./kernel/rc5-qcom-bridge-20261018/build.sh /path/to/linux /path/to/new-output

# Boot-validated soc2 baseline (64 patches):
python3 kernel/rc5-20261013/verify.py /path/to/linux
JOBS=4 ./kernel/rc5-20261013/build.sh /path/to/linux /path/to/new-output-soc2
```

The helper verifies the source, applies patches in a separate worktree, and builds
Image, modules, DTB, matching headers and RPMs. New releases add `-a16pkgN+` so
they cannot overwrite the installed baseline. It does not install files or change
boot selection. See the [Fedora/Ubuntu package contract](../packaging/zenbook-a16-kernel/README.md)
for Ubuntu builds, post-install hooks, rollback behavior and validation still required.

| Package | Status |
|---|---|
| [rc5-qcom-bridge-20261018](rc5-qcom-bridge-20261018/README.md) | Mainline v7.3-rc5 release + `qcom-next`/`qcom-topics` bridge: 104 patches (64 base + 40 bridge) and merged [`qcom-glymur-bridge.config`](qcom-glymur-bridge.config), updated via post-install hooks. |
| [rc5-20261013](rc5-20261013/README.md) | Boot-validated soc2 baseline: 64 patches and exact tested config. |
| [arch-7.2.10](arch-7.2.10/BUILD-AND-UPGRADE.txt) | Arch Linux 7.2.10 stable backport: 127 patches (56 mainline 7.3-rc + 64 A16 + 7 7.2 bridges). |
| [rc5-20261008](rc5-20261008/README.md) | Retained audiopm1 package and saved boot fallback. |
| [rc5-20261002](rc5-20261002/README.md) | Earlier RC5 integrated package. |
| [rc3-20260919](rc3-20260919/README.md) | Retained RC3 fallback package. |

Use matching artifacts and [board firmware](../firmware/README.md).
Other files in this directory are historical helpers and reference fragments.
