# Full A16/Qualcomm stack on Linux 7.3 final

Apply the 157 files in [series](series), in order, to Linux `v7.3`
(`c03c1a14507dfaf8b856c2608f9ac216021fc222`). They reproduce source tree
`68c6fb5921f92299904c233333fccf4fb5093bc4` (`004cf498d432dba102ea3d4c9f9389446d40c1bd`
prior to patch `0143`). Use the matching
[config, verifier and build helper](../../kernel/stable/README.md).

The stack combines the 111-patch `7.3` baseline (64 A16 baseline patches, 40 Qualcomm
bridge patches, and 10 camera/microphone patches, minus three complete patches already
in `v7.3`) with 32 additional patches (`0112`–`0143`) from in-repo overlays, LKML,
`qcom-next`, and `laptops-kernel/topic/glymur-laptops`.
[port-map.json](port-map.json) maps every patch to its disposition and
records before/after tree identities for each retained patch.

Patches `0144`–`0146` are the November 12 RPMh/RTC fixes. Patches `0147`–`0155` add
eDP rate-set corrections, the pending QCC2072 Bluetooth and M.2 power-sequencing patches,
mainline M.2 Wi-Fi/Bluetooth wiring, and RGB camera MCLK4 at 6 mA. Patches `0156`–`0157`
wire `hm1092` `.set_fmt` on 7.3 and connect the ganged PMH0101 IR emitter and `vreg_bob1_e0` supplies.
The [kernel recipe](../../kernel/stable/README.md) describes all three groups.

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
Package revision 6 was built from this queue and boots on the A16; stability
acceptance is pending. The source retains RGB/IR wiring, PM8010/HM1092 support, the constrained
nonsecure CAMSS path, channel-map clearing and experimental DMIC pin settings.
No firmware is included and no running system is changed.
