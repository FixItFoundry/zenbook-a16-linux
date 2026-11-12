# Full A16/Qualcomm stack on Linux 7.3 final

Apply the 144 files in [series](series), in order, to Linux `v7.3`
(`c03c1a14507dfaf8b856c2608f9ac216021fc222`). They reproduce source tree
`928695840df5d59b1d481a8fa672442ae6205fa8` (`004cf498d432dba102ea3d4c9f9389446d40c1bd`
prior to patch `0143`). Use the matching
[config, verifier and build helper](../../kernel/stable/README.md).

The stack combines the 111-patch `7.3` baseline (64 A16 baseline patches, 40 Qualcomm
bridge patches, and 10 camera/microphone patches, minus three complete patches already
in `v7.3`) with 32 additional patches (`0112`–`0143`) from in-repo overlays, LKML,
`qcom-next`, and `laptops-kernel/topic/glymur-laptops`.
[port-map.json](port-map.json) maps every patch to its disposition and
records before/after tree identities for each retained patch.

Patches `0144` onward carry the additions described in the matching kernel recipe.

## Upstream equivalents

These three complete patches are already present in 7.3 final and are omitted:

| Original queue and patch | Fix |
|---|---|
| `rc5-20261013/0006` | GPU CX GDSC voting |
| `qcom-glymur-bridge-20261018/0002` | GENI source-clock selection |
| `camera-microphone-20261022/0009` | CCI halt/reset |

Two retained patches also overlap fixes in final:

- `0028` (original baseline `0029`): retain the large source snapshot except
  its WSA ear-speaker gain hunk, which final already contains.
- `0054` (original baseline `0055`): retain the DMA, SoundWire, GPU, Wi-Fi and
  error-handling changes; omit the duplicate GENI runtime-PM cleanup hunk and
  retain final's `out_pm` label.

The original patch messages, authors and trailers remain intact. Renumbering
does not imply new authorship or an upstream submission. Qualcomm provenance
remains in the [bridge record](../rc/qcom-glymur-bridge/README.md) and
camera provenance in the [overlay record](../rc/camera-microphone/README.md).
Local experiments remain local experiments.

## Acceptance

The complete queue replays without three-way fallback or skipped failures.
This is source verification only; 7.3 compilation and hardware acceptance are
pending. The source retains RGB/IR wiring, PM8010/HM1092 support, the constrained
nonsecure CAMSS path, channel-map clearing and experimental DMIC pin settings.
No firmware is included and no running system is changed.
