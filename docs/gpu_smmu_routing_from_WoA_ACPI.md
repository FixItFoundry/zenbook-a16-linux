# GPU / SMMU routing — extracted from Windows-on-ARM ACPI (glymur / X2 Elite, SoC 8480)

Source: `acpi_dump/iort.dsl`, `dsdt.dsl`, `sdev.dsl` (WoA firmware dump, 2026-07-09).
Purpose: authoritative StreamIDs + reg bases to validate the Linux DT GPU/display bring-up.

## Headline
- GPU has a **dedicated SMMU at `0x03DA0000`** (SMMUv3, IORT Model 3).
- GPU register base = **`0x03D00000`** (len 0x100000).
- **Both match X1E80100 upstream** (`gpu@3d00000` / `adreno_smmu@3da0000`) → reuse the x1e adreno + adreno_smmu DT skeleton; do NOT emulate any Gunyah/hypervisor handshake. GPU is driven natively by Windows in the primary VM.
- There is NO per-op "Gunyah VMID" to copy. The secure owner is TrustZone/**SISP** (see SDEV below).

## Two SMMUv3 instances (IORT)
| IORT offset | Base address | Role |
|---|---|---|
| 0x030 | `0x15000000` | apps_smmu (system: GMU, USB, UFS, ADSP, SISP, etc.) |
| 0x3FC | `0x03DA0000` | **adreno_smmu** (GPU dedicated) |

## GPU0 → adreno_smmu @ 0x03DA0000 — StreamIDs
Context/render set: `0x00 0x01 0x02 0x04 0x05 0x07`
Protected/secure set: `0x80 0x81 0x83  0x1880 0x1883 0x1884 0x1885  0x1940 0x1941 0x1943 0x1944 0x1945 0x1946 0x1947 0x1948  0x19E0 0x19E1  0x1DE0 0x1DE1 0x1DE2`

DT (x1e-style), verify against these:
```
iommus = <&adreno_smmu 0 0x400>,
         <&adreno_smmu 1 0x400>;
```
GMU node:
```
iommus = <&adreno_smmu 5 0x400>;   # SID 0x05 present
```

## GMU / AVS0 → apps_smmu @ 0x15000000 — StreamIDs
`0x820  0x1800 0x1820 0x1840 0x1860 0x18A0  0x1900 0x1980 0x19A0`

## GPU0 register windows (DSDT _CRS, Memory32Fixed)
| Base | Length | Likely block |
|---|---|---|
| `0x03D00000` | 0x100000 | **GPU (kgsl-3d0)** — matches x1e gpu@3d00000 |
| `0x0AE00000` | 0x200000 | GMU / GX region (verify) |
| `0x0AA00000` | 0x100000 | gpucc candidate (verify) |
| `0x0B290000` | 0x10000  | (verify) |

## SDEV — Secure Devices table
- Namespace device `\_SB.SISP`, HID **QCOM0FC1**, class 43/4F/4D, flag "Secure access components present".
- Maps to apps_smmu @0x15000000 SID `0x00`.
- This (TrustZone/SISP), not a Gunyah VMID, is the secure-buffer owner.

## Display (DPU/MDSS)
- No translating MDSS node in IORT (framebuffer/secure path).
- DSDT has `disp_cc_mdss_core_gdsc`, `disp_cc_mdss_ahb_clk`, `disp_cc_mdss_vsync_clk`, `disp_cc_mdss_rscc_ahb_clk` → DPU present, clock-gated normally.
- Implication: display block is a clock/regulator/TLMM plumbing problem, not a hypervisor one. Prime suspect remains the over-reserved gpio-range hitting the edp regulator on TLMM pin 70 (same family as the USB pin 8/9 fix in test47).

## Conclusion
GPU SMMU base + low SIDs match x1e upstream, so routing is NOT the blocker. Focus msm-probe debugging on gpucc / GX-CX regulators / TLMM range, not on VMID/SMMU or any Gunyah emulation.
