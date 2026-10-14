# Kernel packages

The repository and future-testing baseline is
**`7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+`**, based on Linux v7.3-rc5.
See the [build package](rc5-20261013/README.md) and [validation record](../docs/current-build.md).

```sh
python3 kernel/rc5-20261013/verify.py /path/to/linux
JOBS=4 ./kernel/rc5-20261013/build.sh /path/to/linux /path/to/new-output
```

The helper verifies the source, applies patches in a separate worktree, and builds
Image, modules, DTB and RPMs. It does not install files or change boot selection.

| Package | Status |
|---|---|
| [rc5-20261013](rc5-20261013/README.md) | Current soc2 baseline: 64 patches and exact tested config. |
| [rc5-20261008](rc5-20261008/README.md) | Retained audiopm1 package and saved boot fallback. |
| [rc5-20261002](rc5-20261002/README.md) | Earlier RC5 integrated package. |
| [rc3-20260919](rc3-20260919/README.md) | Retained RC3 fallback package. |

Use matching artifacts and [board firmware](../firmware/README.md).
Other files in this directory are historical helpers and reference fragments.
