# Scoping: Gunyah-HLOS-VM path to DPU (display) access

## Goal
Get KMS/DPU display on Linux by having Linux carry the MDSS_XPU-permitted VMID (the way Windows does
as the Qualcomm-hyp HLOS guest). 3D accel (Adreno) explicitly out of scope — stays on Windows (dual-boot).

## New evidence (this session, from the WoA ACPI dump)
- **FADT `Hypervisor ID = 0x4D4F4351` = "QCOM"** → platform is designed to run the OS under a resident
  Qualcomm hypervisor (QHEE/Gunyah). GTDT exposes Non-Secure EL2 + Virtual EL2 timers.
- Corroborates the root-cause model: MDSS_XPU grants VBIF/MDSS access to the VMID XBL assigns the HLOS
  VM; Windows inherits it as the hyp guest; bare-metal Linux presents a different context → VBIF write
  at 0x160 faults → silent warm-reset. (Root-caused earlier via retail .309 BIOS RE.)

## The one diagnostic that sets the plan (run on booted test47)
```
dmesg | grep -iE "CurrentEL|started at EL|hyp mode|KVM"
```
- **"started at EL2"** (expected, x1e-class boots bare-metal EL2, KVM-capable): QCOM hyp is NOT mediating
  Linux → no guest VMID → this is why XPU rejects it. Fix = boot Linux as the hyp's HLOS guest = heavy,
  firmware/boot-chain, likely needs unlocked/eng fw or downstream QC BSP.
- **"started at EL1"**: a hyp is resident under Linux → problem narrows to presenting the right VMID →
  lighter.

## Feasibility (calibrated)
- Mechanism: SOUND. Right VMID → VBIF MMIO permitted → DPU scanout works → KMS display. Orthogonal to 3D.
- Delivery: HARD on retail fw. Mainline `drivers/virt/gunyah` is GUEST-side support — it lets Linux act
  as a Gunyah VM, but does NOT make retail firmware launch Linux as the display-owning HLOS VM. The
  retail QCOM hyp controls which VM images it starts.
- Realistic verdict: correct direction, but probably gated on the same firmware-cooperation wall as
  power/charging — unless the upstream Gunyah-on-Snapdragon-laptop bring-up matures to host mainline as
  the primary VM, or eng/unlocked firmware becomes available.

## Next actions (in order)
1. Capture the EL level (command above) — decides heavy vs light path. CHEAP, do first.
2. Check whether the QCOM hyp is resident at Linux runtime: look for a hyp/gunyah console, `hvc`,
   `/proc/device-tree` firmware nodes, or whether KVM initialized (KVM working ⇒ Linux owns EL2 ⇒ no
   resident hyp ⇒ heavy path confirmed).
3. Survey upstream state: is anyone booting mainline Linux as a Gunyah *primary/HLOS* VM on Snapdragon
   X-class laptops? (Gunyah is being upstreamed by Qualcomm; check linaro/qcom-linux + gunyah lists.)
   If a boot-chain recipe exists, this becomes tractable; if only guest-secondary-VM support exists, it
   does not unlock the HLOS display slot on its own.
4. Only if 1-3 are favorable: prototype the VM/boot-chain config. Otherwise this parks next to power as
   "firmware-gated," and test47 (simplefb + audio) remains the daily driver.

## Cross-refs
- Root cause + all HLOS-side negatives: `gpu-bringup-next` memory / DISPLAY-BRINGUP-FINDINGS.md
- SMMU/StreamID confirmation from WoA IORT: gpu_smmu_routing_from_WoA_ACPI.md
- Display VMIDs from DEVCFG RE: acvmid = 0x3C / 0x43 / 0x42; SIDs 0x1de0/0x1de1/0x21de4
