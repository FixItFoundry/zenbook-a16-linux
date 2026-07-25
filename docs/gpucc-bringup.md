# GPU bring-up (Adreno X2 / gpucc) — starting state, 2026-07-24

Successor project to eDP. **Read this before opening a decompiler.**

## The headline: there is almost nothing to reverse engineer

The old plan ("RE the gpucc from the Windows driver") was based on a wrong premise. The
kernel side is already written and sitting in `~/kernel-build/linux-src` — the *same* v7.1
tree the working `7.1.0-glymur-edp1` kernel was built from.

| Piece | Where | State |
|---|---|---|
| gpucc driver | `drivers/clk/qcom/gpucc-glymur.c` | 618 lines, real. Compatible `qcom,glymur-gpucc`, CX GDSC `0x9080`, regmap window `0x95e8`. Builds via `CONFIG_CLK_GLYMUR_GPUCC` (pulls in `gxclkctl-kaanapali.o`) |
| GPU driver | `drivers/gpu/drm/msm/adreno/a8xx_gpu.c` | **Already compiled into the running `msm.ko`** |
| Catalog entry | `drivers/gpu/drm/msm/adreno/a6xx_catalog.c:2113` | chipid **`0x44070001`**, `ADRENO_8XX_GEN2`, `x285_protect`, gmem 21 MB, `gmu_chipid = 0x8010100` |
| Firmware | `/lib/firmware/qcom/` | `gen80100_sqe.fw`, `gen80100_gmu.bin`, and `qcom/glymur/gen80100_zap.mbn` — all present |

`zenbook-a16-linux-public/kernel/gpucc-x2.c` is the **abandoned** RE attempt: 126 lines of
`TODO` and `/* Assumed */` offsets. It is superseded — delete it rather than extend it. It
also cites `qcpep8480.sys`, which is **not on this box** (`re/` holds only `qcdxkm8480.sys`,
the display KMD), so decompile-driven gpucc work would first require re-extracting a file
we do not have, to rebuild something that already exists.

## The real gap: device tree

No glymur device tree anywhere — not `glymur.dtsi`, not the CLO `next` tree — has `gpu@`,
`gmu@`, `gpu_cc`, or `adreno_smmu` nodes. Upstream shipped the drivers without the DT.

Template to copy: **`arch/arm64/boot/dts/qcom/hamoa.dtsi`**. That is `x1e80100.dtsi`
renamed to its SoC codename in v7.1 — which is why searching for `x1e80100.dtsi` comes up
empty. It has the full skeleton:

| Node | Line in hamoa.dtsi |
|---|---|
| `gpu: gpu@3d00000` | 4040 |
| `gpu_zap_shader: zap-shader` | 4068 |
| `gmu: gmu@3d6a000` | 4199 |
| `gpucc: clock-controller@3d90000` | 4251 |
| `adreno_smmu: iommu@3da0000` | 4262 |

`docs/gpu_smmu_routing_from_WoA_ACPI.md` independently confirms GPU base `0x03D00000` and
a dedicated adreno SMMUv3 at `0x03DA0000` from the Windows ACPI dump, with StreamID sets,
and reaches the same conclusion: reuse the x1e skeleton.

### gpucc base address — settled

**`0x3d90000`, size `0xa000`.** Identical on sm8550, sm8650 and hamoa, it is the value in
the binding's own example (`Documentation/devicetree/bindings/clock/qcom,sm8450-gpucc.yaml`),
and it fits `gpucc-glymur.c`'s `max_register = 0x95e8`. The ACPI doc's guess of
`0x0AA00000` is **wrong** — that address is in display territory.

A `clock-controller@3d90000` node has in fact been present in test62/test63 since
2026-07-20, but with the invented compatible `qcom,x2-gpucc` (from the dead RE driver) and
**no `clocks` property**, so nothing ever bound to it. It is inert in the running system.

## Test 1 (staged 2026-07-24, not yet booted): does gpu_cc probe?

Deliberately minimal — the GPU node stays `disabled`. This answers one question: is the
base address right and does the clock controller come up?

- `CONFIG_CLK_GLYMUR_GPUCC=m` — a one-line `.config` delta, nothing else moved.
  `gpucc-glymur.ko` (srcversion `F2D6E3C26866D496A277E40`, vermagic
  `7.1.0-glymur-edp1`) copied into `/lib/modules/7.1.0-glymur-edp1/`. Nothing else in
  `/lib/modules` was touched; `msm` and `phy_qcom_edp` srcversions are unchanged.
- **`test64.dtb`** = test62 plus exactly two lines:

  ```
  compatible = "qcom,glymur-gpucc";                  /* was "qcom,x2-gpucc" */
  clocks = <0x3a 0x00 0x46 0x38 0x46 0x39>;          /* new */
  ```

  `0x3a` = `qcom,glymur-rpmh-clk` (CXO — the same source dispcc uses), `0x46` = `gcc`,
  indices 56/57 = `GCC_GPU_GPLL0_CLK_SRC` / `GCC_GPU_GPLL0_DIV_CLK_SRC`. Verified by
  decompiling both DTBs and diffing: the only delta against the *actually booted*
  `glymur-a16-test62.dtb` is those two lines.
- GRUB entry **`fedora-glymur-gpucc1`**; default remains `fedora-glymur-edp1`.
  Backup at `/boot/grub/grub.cfg.bak-pre-gpucc1`.
- The entry carries **`modprobe.blacklist=gpucc_glymur` on purpose.** If the register
  window is unpowered or XPU-gated, the first read can hang the SoC — we want that at a
  known instant on a booted, SSH-able system with a synced log, not mid-boot.

Run it with:

```bash
~/Projects/zenbook-a16-linux/scripts/gpucc-probe.sh
```

It refuses to run unless the live `clock-controller@3d90000/compatible` reads
`qcom,glymur-gpucc` — the DTB fingerprint, since `/proc/cmdline` cannot identify the DTB
(see the traps list). It also re-checks the module's running-vs-disk srcversion.

**Verdict rule:** `gpu_cc` clock count in `/sys/kernel/debug/clk` greater than zero means
the base address is confirmed and gpucc binds. Zero means it did not bind.

## Known risks, not yet answered

1. **The XPU/VBIF firmware gate (G18).** MDSS got past it under pKVM; whether the GPU does
   is unknown and is the one thing that could still be a hard wall.
2. **Zap shader signing.** The zap blob loads through TrustZone; retail firmware may
   reject the linux-firmware copy.
3. `rmmod msm` still hard-freezes this box, so every GPU-side mistake costs a reboot.
