# RC / Upstream Development Patch Stack (`patches/rc`)

Apply the 103 patches in [series](series), in order, to Linux `next-20261103`
(`d6bcfc94eb4da6e089c5473970cd96727292fd97`, built on mainline `v7.4-rc1`
`6628e7d4c6b25c8d18f1345e3a20d21829aae7e4`). They reproduce source tree
`e52a4f3ca29b6348ecaf84a4f349bde8d0cc1fb7` and reverse cleanly back to base tree
`a8860acf3c1c2856062494c95d68bc2521f54d1a`. Use the matching
[config, verifier, and build helper](../../kernel/rc/README.md).

## Disposition vs. Linux 7.3 Stable (`patches/stable`)

[port-map.json](port-map.json) records the disposition of all 143 patches in
[`patches/stable`](../stable/README.md) plus two `next-20261103`-specific patches:

| Category | Count | Summary |
|---|---:|---|
| `ported` | 84 | Applied cleanly from `patches/stable/` onto `next-20261103`. |
| `adapted` | 14 | Rebased onto `v7.4-rc1` / `next-20261103` upstream API and context changes (`0011`, `0012`, `0026`, `0028`, `0054`, `0059`, `0061`, `0062`, `0063`, `0066`, `0087`, `0106`, `0114`, `0120` in `stable` numbering). |
| `dropped_merged` | 45 | Retired because equivalent or superseding commits landed in `v7.4-rc1` or `next-20261103` (each recorded with its non-merge upstream commit SHA in `port-map.json`). |
| `added_rc_only` | 2 | `0001-LOCAL-drop-localversion-next-the-build-name-carries-.patch` and `0100-Revert-drm-msm-a8xx-Enable-CLX-feature-on-Adreno-X2-.patch` (Abel Vesa's `d448c66b9e47` revert of `93b6c8d10fad` / `c2a6bcfbebce` to prevent Adreno X2-85 GMU `HFI_H2F_MSG_GX_BW_PERF_VOTE` hangs on Glymur). |

Patches `0101` onward add 3 RPMh/RTC fixes ported from stable.

## Replay Without Modifying a Checkout

```sh
python3 kernel/rc/replay.py /path/to/linux.git
python3 scripts/ci.py --replay-only --track rc --linux-git /path/to/linux.git
```

The retired `v7.3-rc5` layered stack (`base`, `qcom-glymur-bridge`, `camera-microphone`, and `glymur-usb3`) is preserved under [`../../archive/patches/rc5-20261031/`](../../archive/patches/rc5-20261031/README.md).
