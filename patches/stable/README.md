# Full A16/Qualcomm stack on Linux 7.3.6

Apply the 183 files in [series](series), in order, to Linux `v7.3.6`
(`1a0388846138eda9f6eb4258ff227a223afc2f52`). They reproduce source tree
`a25b51b1ceda63f568d36f0dd4847c0787dfcfaa` (`91e3f125093798823e8c2f1945e8a859298cf266`
prior to retiring `0012` and adding `0207`–`0213`, and `c9073bc3daaf012b47e5c0631316308f4a3f3a7c` on `v7.3`).
Use the matching [config, verifier and build helper](../../kernel/stable/README.md).

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
Patch `0158` stops the eDP link training fallback from dropping below the bandwidth the panel mode needs.
Patch `0159` gives the X1E80100 lite CSIDs their own clocks, Bryan O'Donoghue's `0160` drops the
unusable CSID2, and the local `0161` replaces `0107`'s CSID0/VFE0 limit with the full X1E80100 tables.
Revision 12 drops legacy `0062` (refreshing `0120`) and adds `0162`–`0169` (Ritesh Kumar's Glymur DP PHY v8 series), `0170` (HDMI HPD pinctrl on `&mdss_dp2`), `0171`–`0197` (27 patches from Michi `@scalpel4k`'s openSUSE `kernel-qcom-laptops` stack covering firmware declarations, `fnlock_default`, `iris`, SCMI `memlat`, `SPEL`, Type-C/DP/USB3/Wi-Fi fixes), `0198` (Glymur DPU `LM_4`–`LM_7` → `DSPP_4`–`DSPP_7`), and `0199`–`0202` (`iris` suspend deadlock, driver-removal work cancel, timeout firmware reload, and firmware-reported output buffer count).
Fast-forwarding the base to `v7.3.6` drops 28 patches already merged in `7.3.1`–`7.3.6` (`0006`, `0008`, `0010`, `0015`, `0018`, `0029`–`0033`, `0037`–`0038`, `0043`, `0081`, `0122`–`0130`, `0133`–`0134`, `0137`–`0138`, `0200`), refreshes five overlapping patches (`0028`, `0078`, `0152`, `0178`, `0184`), retires `0012` (`glymur_pci_skip`), and adds `0203` (A16 DisplayPort/HDMI audio DAI links), `0204`–`0206` (Omarchy `memlat` polling disable, `cluster_cl5` s2idle-only guard, and lid-switch wakeup fix), and `0207`–`0213` (Adreno GMU platform driver and broken QCE crypto disable so `gcc`/`gpucc`/`mc_virt` reach `sync_state()`).
The [kernel recipe](../../kernel/stable/README.md) describes all groups.

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
acceptance is pending. The source retains RGB/IR wiring, PM8010/HM1092 support, the full X1E80100
CAMSS tables, channel-map clearing and experimental DMIC pin settings.
No firmware is included and no running system is changed.
