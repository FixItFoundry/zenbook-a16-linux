# RC5 integration — 2026-10-02

These 28 ordered patches reproduce the source of the RC5 integrated build
`7.3.0-rc5-ZenbookA16-20261002-rc5-integrated1+`. Apply only to Linux
**v7.3-rc5** (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`).
`series` defines order; `commits.txt` records the original integration commits.
Author and provenance trailers are retained from the source worktrees.

See [build instructions](../../kernel/rc5-20261002/README.md) and
[current validation limits](../../docs/current-build.md).

## Relationship to the RC3 series

This is the RC3 stack rebased onto rc5, minus one retired patch, plus EC v3 and
the PMH0104 camera LDOs. Patch numbering changed; identify patches by their
`Subject:` trailer, not their position.

| Change | Detail |
|---|---|
| Base | v7.3-rc3 `fd73f4a66598` → v7.3-rc5 `72d3fcf802c4` (742 commits past rc4) |
| Retired | `drm/msm/dp: skip PUSH_IDLE when the link was never enabled` — merged upstream in 7.3 as `e249a6e2a130`, so it is now dropped rather than carried |
| Added | EC v3 series, patches 24–27, from [`rc3-ec-v3-hid-20260923/`](../rc3-ec-v3-hid-20260923/) |
| Added | PMH0104 camera LDOs, patch 28, converted from the raw diff in [`glymur-pmh0104-camera-ldos.patch`](../glymur-pmh0104-camera-ldos.patch) |
| Unchanged | The remaining 23 RC3 patches apply to rc5 without modification |

Every patch was checked against rc5 by applying the whole ordered series to a
throwaway Git index. One patch was retired as already upstream; none needed
re-basing, rebasing-by-hand or was found obsolete. That is a source-level
result only — it says nothing about hardware behaviour on the rc5 base.

## Notes

Patch 28 was rewritten from a headerless diff into a real commit so the series
can be replayed with `git am` like the rest. It adds only rail descriptions to
`pmh0104_vreg_data`; no DT node consumes them yet, so it is inert on a
baseline that blacklists `ov02c10`, `qcom_camss` and `i2c_qcom_cci`.

Patches 24–27 need `CONFIG_EC_ASUS_GLYMUR=m`, which this package's `config`
sets. The driver is a module, so the DT node added by patch 26 only takes
effect once that module is present.

This is an integration snapshot, not an upstream submission series. In
particular, patch 10 carries experimental SoundWire recovery, patch 13 bypasses
PCI suspend behavior, and patches 17–23 preserve board compatibility. Their
inclusion does not establish correctness or upstream readiness. The OV02C10
camera DT wiring and the separate CDSP initramfs experiment are excluded.

The manifest verifies source-tree equality, not byte-identical binaries:
compiler versions, generated signing keys and build timestamps affect outputs.