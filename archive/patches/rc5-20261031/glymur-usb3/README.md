# Glymur USB3 calibration candidate

Konrad Dybcio's [USB3 PHY settings update](https://lore.kernel.org/all/76e97352-3a54-40de-8ef0-eef0ca27ca73@oss.qualcomm.com/)
changes calibration values in three Glymur tables. Original authorship and
sign-off are preserved. The same patch passed full build and package checks in
the Omarchy `7.3.0-7-omarchy-a16usb1` candidate. That result does not validate
these different source queues or establish reliable USB/DP on the A16.

This opt-in overlay preserves the dated stable and rc baselines. `tracks.json`
records each baseline verifier, resulting source tree, configuration inputs and
distinct candidate release. It does not select an installed or default kernel.
Both use the retained pkg3-derived config, compared with the running Fedora
pkg3 config: only the release label differs. Configuration checksums are pinned
separately from source replay and resolved settings still need build review.

```sh
python3 scripts/ci.py --replay-only --track stable --linux-git /path/to/linux.git
python3 scripts/ci.py --replay-only --track rc --linux-git /path/to/linux.git
```

Each command checks the original queue, applies this series in a temporary Git
index, verifies the candidate tree, then checks reverse application. The normal
`scripts/ci.py --linux-git /path/to/linux.git` run includes both candidates;
`--track stable` or `--track rc` selects one independently.

For a build, export the verified candidate `source_tree` from `tracks.json` into
a new directory. Merge that track's `config_inputs` in order with the kernel's
`scripts/kconfig/merge_config.sh -m`, set `CONFIG_LOCALVERSION` to
`-ZenbookA16-20261031-usb1`, retain `LOCALVERSION=+`, and run `olddefconfig`.
Review configuration differences and build Image, modules and the A16 DTB using
the existing distro pipeline. Record the actual release, source/config/artifact
hashes and validation for each track; source replay alone is not a build pass.

The tables serve all `qcom,glymur-qmp-usb3-dp-phy` consumers, including A16,
Surface Laptop 8 and CRD. Other SoC tables and driver control flow are unchanged.
The [external A16 report](https://lists.openwall.net/linux-kernel/2026/10/27/3041)
found improved enumeration but retained sustained NIC resets. Keep this a
candidate until separately accepted on hardware, including both orientations,
USB0/USB1, DP and concurrent workloads. Preserve fallback kernels; never move a
mounted root SSD between ports. Native package transactions, boot and hardware
acceptance do not transfer from Omarchy's build or x86_64 KVM fixture tests.
