# Delta against `next-20260817`

The full 13-patch series that turns vanilla `next-20260817` into the working daily-driver kernel for the ASUS Zenbook A16 (UX3607OA).

Build name: **`7.2.0-rc6-ZenbookA16-20260817`**

| patch | area | what | upstream status |
|---|---|---|---|
| `0001` | SCMI | `arm,no-completion-irq` polling mode property | sent, upstream track |
| `0002` | DRM/eDP | make eDP 1.4 `LINK_RATE_SET` path reachable and clear `LINK_BW_SET` | sent (generic msm bug) |
| `0003` | DRM/eDP | `push_idle` guard when link was never powered on | sent (generic msm bug) |
| `0004` | DRM/eDP | **LOCAL:** force internal eDP panel to DT max rate (HBR3) | not proposable — drives above sink max; real fix in `phy-qcom-edp.c` |
| `0005` | PCI | **LOCAL:** `glymur_pci_skip` module parameter to bypass s2idle reset | not proposable — diagnostic knob in production |
| `0006` | HID | complete Zenbook keyboard feature set (backlight, N-Key, Fn lock, short report padding) | upstreamable with cleanup |
| `0007` | DTS | sync board DTS with upstream merged DTS carrying local fixups | local board reconciliation |
| `0008` | DTS | use existing `pcie4_port0_ep` label | tracks upstream rename |
| `0009` | Audio | q6apm/audioreach fast-retry on `APM_CMD_GET_SPF_STATE` (removes 5s boot lag) | local timing fix, unsent |
| `0010` | Audio | SoundWire device0 alert, clash recovery, and attach-count guard | local SoundWire enumeration fix |
| `0011` | Build | drop `localversion-next` | cosmetic / build-tree clean |
| `0012` | Security | include `asn1_decoder.h` in `trusted_tpm2.c` | genuine upstream bug fix (`CONFIG_TRUSTED_KEYS=y`) |
| `0013` | Audio | SoundWire direct reprobe for slaves held in reset during deferred probe | local SoundWire probe deferral fix |

## Diff breakdown

- **DTS reconciliation (1130 lines)**: Reconciling the A16 board file against upstream's merged DTS (`0007`) and tracking the `pcie4_port0_ep` label rename (`0008`). Carries forward local fixups (`regulator-always-on` for WCN 3.3V rail and the `wcn7850-pmu` node).
- **Functional kernel delta (~350 lines)**: The remaining 11 patches providing the actual drivers, audio timing/reprobe, display link training, keyboard quirks, and security fixes.
