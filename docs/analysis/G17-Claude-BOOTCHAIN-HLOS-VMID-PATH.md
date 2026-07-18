# G17 — Boot-chain / HLOS-VMID path to the display (investigation + plan)

**Date:** 2026-07-12 (overnight). **Goal:** get MDSS/DPU (KMS display) by making Linux's bus
transactions carry the display's firmware-granted VMID. 3D/Adreno stays on Windows (dual-boot).

## Topology — definitively established
Live probe (`bc_probe.sh`) + firmware facts:
- Linux boot chain: **XBL → TF-A (EL3/TZ) → UEFI (Insyde H2O) → GRUB → Linux at EL2 (VHE host).**
- PSCI conduit = **`smc`** (calls go straight to EL3); **no `/sys/hypervisor`**, no gunyah/hyp DT nodes,
  KVM/VHE initialised. ⇒ **No hypervisor is resident above Linux — Linux owns EL2.**
- Under Windows, the FADT advertises **Hypervisor ID = "QCOM"** ⇒ the Windows path loads a Qualcomm
  hypervisor (Gunyah/QHEE) and runs Windows at EL1 as the HLOS VM.
- The hyp binary and the xPU permission bits live in packed NHLOS/TZ boot blobs — **not statically
  extractable** (confirmed again this pass; UEFI FV only contains an "HLOS" debug-policy string).

## Why the display faults (mechanism)
Per Qualcomm's Access-Control docs (80-70014-11) + our DEVCFG carve (`dtb_dump.txt`):
- MDSS/VBIF registers sit behind an **xPU** (slave-side gate). A **VMIDMT** stamps each bus transaction
  with a **VMID**. The firmware binds **Display** access-control to **VMID `0x3C`**
  (`NAMEDNODE_Display … SIDMappings = 0x3C`; `vmidmt` / `acvmid` ac_config blocks).
- Windows (EL1 HLOS guest) carries the hyp-assigned VMID `0x3C` → xPU permits its plain-MMIO VBIF writes.
- Bare-metal EL2 VHE Linux applies no stage-2 VMID to its own accesses → transactions carry VMID 0 →
  xPU denies the VBIF write (`VBIF+0x160`) → silent warm-reset. (Matches every capture.)

## The key realization — this is not hopeless
The xPU grant targets a **VMID value (`0x3C`)** set by XBL early; it does **not** care *which*
hypervisor stamps it. **We own EL2.** So if we run our own thin EL2 hypervisor and run Linux as a guest
whose stage-2 VMID = `0x3C`, Linux's MDSS MMIO carries `0x3C` and the xPU should permit it —
**no firmware unlock required.**

## Path (a), self-hosted — made concrete
Boot **Gunyah** (Qualcomm's open-source Type-1 EL2 hypervisor: `quic/gunyah-hypervisor` +
`quic/gunyah-resource-manager`) as our EL2 hypervisor; its Resource Manager creates the **primary/HLOS
VM = our Linux**, pinned to **VMID `0x3C`** and owning **all** platform hardware (the primary VM owns
everything — the Android model — so no device/clock split is needed). Chainload Gunyah at EL2 from the
existing chain (feasible: Linux currently takes EL2 itself). Linux then runs at EL1 with VMID `0x3C` →
MDSS xPU grants VBIF access → display works.
- Mainline already has Gunyah **guest** drivers (`drivers/virt/gunyah`); Gunyah + RM build standalone and
  package into one boot image (VHE EL2 by default).
- **Cost:** port Gunyah/RM to glymur (memory map, GIC, SMMU), force primary-VM VMID = `0x3C`, assign all
  devices to the primary VM, wire into GRUB/UEFI. Multi-week.
- **Risk:** regressing the working platform (audio/ADSP/wifi/battery/USB) since every device re-routes
  through Gunyah assignment.

## Decisive CHEAP experiment FIRST (gate the big port)
Prove the single unknown before porting anything: **does the MDSS xPU accept a guest-stamped VMID `0x3C`
on a CPU MMIO write?** We already have EL2 + KVM.
1. Patch the KVM VMID allocator to **pin one guest's VMID = `0x3C`**.
2. Create a **minimal guest** (no OS) whose stage-2 maps just the **VBIF register page**; execute the one
   faulting write `VBIF+0x160 ← 0x22222223`, captured over netconsole.
- **Write succeeds in-guest** → the xPU gates on the bus VMID and a guest can satisfy it → the full
  Gunyah-primary-VM build is validated and worth doing.
- **Write still resets** → the xPU checks more than the bus VMID (a hyp-identity/secure attribute XBL
  bound to the *real* hyp) → path (a) is also dead; only unlocked/eng firmware remains.
- **Effort:** days (VMID pin + tiny guest + MMIO stage-2 map + boot/capture), not weeks. Same
  auto-recovery-to-test47 safety net.

## Recommendation
Run the KVM-VMID VBIF-write experiment next session — it is the cheapest test of the entire hypothesis
and the last real unknown for the display. Everything else HLOS-side is proven correct (DT, clocks,
power, SMMU/StreamIDs, interconnect, and — as of tonight — the upstream driver itself is byte-identical).
Only if the experiment passes is the multi-week self-hosted-Gunyah primary-VM build justified.

## State / artifacts
- `bc_probe.sh` → PSCI=smc, EL2/VHE, no resident hyp. `dtb_dump.txt` → Display↔`0x3C` binding.
- Box untouched: `test47` daily, stock `msm.ko`, no build/reboot. drm-msm-next scratch clone at
  `/home/jcasco/msmnext` (2.0G, removable). Cross-refs: `DISPLAY-BRINGUP-FINDINGS.md`,
  `07_DTB_CHANGELOG.md`, `../gunyah_dpu_path_scope.md`.
