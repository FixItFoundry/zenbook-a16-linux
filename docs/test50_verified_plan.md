# test50 blueprint — VERDICT: already done as test48; NOT the fix. Do not re-flash.

## Status
The blueprint (free TLMM pins 18 + 70 for the eDP panel) was **already executed as test48**:
test48 = test47 + pin18 split `(10,10)→(10,8)+(19,1)` + pin70 split `(68,8)→(68,2)+(71,5)`,
plus mdss + dispcc enabled. Recreating it as "test50" gains nothing.

## What it achieved (necessary, not sufficient)
- Panel powers and **fully detects**: EDID OK (Samsung ATNA60HR07-0 / atna60cl08), backlight found,
  modes 2880x1800@120/60. So freeing 18+70 was correct and required.
- Box still **hard-resets at the first DPU pipe-enable**, independent of link rate.

## The real wall (root-caused, HLOS-side exhausted)
- Fault = DPU **VBIF register write, offset 0x160, val 0x22222223** → silent secure warm-reset (no oops).
- Cause = **MDSS_XPU** firmware protection, confirmed by RE of the retail `.309` BIOS (UX3607OA.309)
  and the SOC-package Windows SMMU/SCM drivers: XBL Dynamic-Init grants MDSS/VBIF access only to the
  VMID it assigns to the HLOS VM. Windows inherits that VMID as the Qualcomm/Gunyah HLOS guest and
  writes VBIF by plain MMIO. Bare-metal Linux presents a non-granted VMID → the VBIF write faults.
- DEVCFG RE carved the display access-control: SMMU SIDs `0x1de0/0x1de1/0x21de4` (== our Linux DT
  `iommus=<apps_smmu 0x1de0 0x2>`) and display `acvmid = 0x3C / 0x43 / 0x42`. Routing matches; the
  VMID **grant** is what's withheld.
- All HLOS fixes tested NEGATIVE: VBIF-skip, memtype-skip, `restore_sec_cfg`(EINVAL), keep-MDSS-powered,
  VBIF-halt. No DT/driver/SCM unlock exists in the retail firmware dump.

## Cross-check from WoA ACPI (gpu2 session, this pass)
- IORT: GPU has dedicated adreno_smmu @0x03DA0000, reg @0x03D00000 — identical to x1e80100 upstream.
- Confirms the SMMU/StreamID path is correct; the blocker is the XPU/VMID grant, not routing.
- See `gpu_smmu_routing_from_WoA_ACPI.md`.

## Real next path (the project's own conclusion — and Jesse's original instinct)
Boot mainline Linux as the **Gunyah HLOS/primary VM** so it carries the XPU-permitted VMID (the way
Windows/ChromeOS get display access). Mainline has `drivers/virt/gunyah`; the work is boot-chain / VM
config, not new kernel code. Alternatives: newer/unlocked/eng firmware whose XPU Dynamic-Init grants
the bare-metal VMID; or a downstream QC BSP kernel using the hyp/TZ handoff.

(`make_test50.sh` retained only as a generic reserved-range editor; it reproduces test48, not a fix.)
