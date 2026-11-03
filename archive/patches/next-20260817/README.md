# Delta against `next-20260817`

The 17-patch series, plus the local SOCCP GLINK integration below, that turns vanilla
`next-20260817` into the working daily-driver kernel for the ASUS Zenbook A16 (UX3607OA).

Build name: **`7.2.0-ZenbookA16-20260819`**. `CONFIG_QCOM_CPUCP_MBOX=y` (was `=m`) is also
required — a build-config change, not a source patch, so it isn't a numbered file here. Apply
`../glymur-soccp-glink-7.2-hooks.patch` and enable `CONFIG_QCOM_SOCCP_GLINK=m` as documented in
`../../kernel/CONFIG_FRAGMENT.md`; this provides the working battery/PD/DP-altmode transport.

| patch | area | what | upstream status |
|---|---|---|---|
| `0001` | SCMI | `arm,no-completion-irq` polling mode property | local; public submission needs confirmation |
| `0002` | DRM/eDP | make eDP 1.4 `LINK_RATE_SET` path reachable and clear `LINK_BW_SET` | local; do not send independently before the PHY fix lands |
| `0003` | DRM/eDP | `push_idle` guard when link was never powered on | sent (generic msm bug) |
| `0004` | DRM/eDP | ⛔ **RETIRED 2026-08-19** — LOCAL: force internal eDP panel to DT max rate (HBR3) | superseded by `0014`+`0015`, the real PHY fix; reverted by `0016` |
| `0005` | PCI | **LOCAL:** `glymur_pci_skip` module parameter to bypass s2idle reset | not proposable — diagnostic knob in production |
| `0006` | HID | complete Zenbook keyboard feature set (backlight, N-Key, Fn lock, short report padding) | upstreamable with cleanup |
| `0007` | DTS | sync board DTS with upstream merged DTS carrying local fixups | local board reconciliation |
| `0008` | DTS | use existing `pcie4_port0_ep` label | tracks upstream rename |
| `0009` | Audio | q6apm/audioreach fast-retry on `APM_CMD_GET_SPF_STATE` (removes 5s boot lag) | local timing fix, unsent |
| `0010` | Audio | SoundWire device0 alert, clash recovery, and attach-count guard | local SoundWire enumeration fix — ⚠️ the "clash recovery" here is the code whose actual effectiveness is now in question, see `0017`/handoff |
| `0011` | Build | drop `localversion-next` | cosmetic / build-tree clean |
| `0012` | Security | include `asn1_decoder.h` in `trusted_tpm2.c` | genuine upstream bug fix (`CONFIG_TRUSTED_KEYS=y`) |
| `0013` | Audio | SoundWire direct reprobe for slaves held in reset during deferred probe | local SoundWire probe deferral fix — the trigger for `0017` |
| `0014` | DRM/PHY | **UPSTREAM (Bjorn Andersson):** split eDP PHY power-on sequencing by version | unmerged, posted 2026-06-22, see `UPSTREAM-CREDITS.md` |
| `0015` | DRM/PHY | **UPSTREAM (Bjorn Andersson):** update v8 power-on programming sequence | unmerged, posted 2026-06-22 — **this is the real HBR2/HBR/RBR fix**, validated on hardware 2026-08-19 |
| `0016` | DRM/eDP | Revert `0004` now that `0014`+`0015` fix the real problem | local, retires the HBR3-force hack |
| `0017` | Audio | **LOCAL:** `wsa884x` — balance `pm_runtime_enable()` with a `devm`-managed disable | local fix for the `Unbalanced pm_runtime_enable!` bug that `0013`'s `device_reprobe()` exposes; unsent |

## Diff breakdown

- **DTS reconciliation (1130 lines)**: Reconciling the A16 board file against upstream's merged DTS (`0007`) and tracking the `pcie4_port0_ep` label rename (`0008`). Carries forward local fixups (`regulator-always-on` for WCN 3.3V rail and the `wcn7850-pmu` node).
- **Functional kernel delta (~350 lines through 0013)**: drivers, audio timing/reprobe, display link training, keyboard quirks, and security fixes.
- **2026-08-19 delta (`0014`-`0017`)**: the real eDP v8 PHY fix (upstream, unmerged) replacing the local HBR3-force hack, plus the `wsa884x` pm_runtime fix uncovered by testing `0013` under load. The detailed validation record is private; the audio bus-clash issue remains open.
