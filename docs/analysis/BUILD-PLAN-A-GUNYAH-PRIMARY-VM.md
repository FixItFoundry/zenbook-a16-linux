# Build Plan A — Boot Linux as the Gunyah primary/HLOS VM

**Goal:** run the *entire* A16 Linux at EL1 as the primary VM of Qualcomm's open-source **Gunyah**
hypervisor, so all of its drivers (DPU included) execute with a permitted stage-2 VMID → the MDSS xPU
grants the VBIF/scanout writes → real display. No firmware unlock.

**Why this and not "the DPU driver alone in a guest":** the DPU depends on dispcc clocks, GDSCs, PMIC
regulators, interconnect votes and the eDP PHY — all host-managed platform resources. Splitting just the
DPU into a guest drags all of those along. The primary-VM model avoids the split entirely: the primary VM
**owns all hardware** (the Android model), so the DPU driver has its clocks/power right there, exactly
like today's bare-metal Linux — only now at EL1 with a permitted VMID.

**Proven precondition (2026-07-13):** a KVM guest with a nonzero stage-2 VMID successfully wrote the VBIF
register that hard-resets bare-metal Linux (readback-confirmed). Any nonzero guest VMID worked. So the
mechanism is validated; this plan is "make the whole OS such a guest."

---

## Architecture
```
Today:   UEFI → GRUB → Linux (EL2, VHE, bare-metal, VMID 0)          ← DPU writes DENIED
Target:  UEFI → GRUB → Gunyah (EL2) → Resource Manager → Linux primary VM (EL1, VMID != 0)  ← DPU ALLOWED
```
Gunyah = Type-1 EL2 hypervisor (`quic/gunyah-hypervisor`) + Resource Manager (`quic/gunyah-resource-manager`,
the "root VM" that creates the primary VM and does static partitioning). Mainline Linux already ships the
**guest-side** drivers (`drivers/virt/gunyah`: message queues, RM client, vCPU, console).

## Prerequisites to collect (all already in the project)
- Physical memory map + reserved carveouts — from our working DT + `acpi_dump/` (smem, adsp, etc.).
- GICv3 distributor/redistributor bases, arch-timer, CPU topology — from the DT.
- A hyp console UART — reuse the DBG2/SPCR debug UART already identified.
- The working "everything" DTB (kbd/wifi/audio/battery/USB/ADSP) = current test47 DT.

## Build phases

### Phase 1 — Recon & environment (0.5–1 wk)
- Clone both Gunyah repos; read `docs/build.md`; build the QEMU target first to learn the flow
  (hyp + RM + C-runtime packaged into one image).
- Study the `platform/` abstraction; pick the closest supported Qualcomm SoC as the port template.
- Inventory glymur specifics (memory map, GICv3, UART, timers, SMMU, CPU cluster layout).

### Phase 2 — Port Gunyah to glymur (2–4 wk, the big rock)
- Add a `glymur` platform: RAM regions, GICv3 bases, arch-timer, hyp-console UART driver, CPU topology,
  secure/non-secure memory split.
- Configure the **primary VM**: assign most of RAM + **direct access to all devices** (primary VM is the
  HLOS, not a protected VM), and a nonzero VMID (default primary VMID is fine — our control showed any
  nonzero value is accepted).
- Build the packaged Gunyah+RM boot image.

### Phase 3 — Boot-chain integration (1–2 wk, the tricky rock)
- Get Gunyah loaded at **EL2** from our Insyde-UEFI/GRUB chain (today Linux takes EL2 itself). Approach:
  GRUB loads the Gunyah image as the "kernel"; Gunyah/RM then load the primary-VM payload = Linux `Image`
  + our test47 DTB + initramfs. (Qualcomm normally packages this via their bootloader; on Insyde UEFI we
  build a small loader/wrapper — expect iteration here.)
- Primary-VM DTB = current working DT **+** Gunyah guest nodes (gunyah-console, RM message-queue) and the
  VM's GIC/timer view.

### Phase 4 — Bring up Linux as the primary VM (1–2 wk)
- Kernel config: `CONFIG_GUNYAH` guest drivers, GICv3 in the VM, PSCI via Gunyah.
- Boot to console → rootfs. **Then the critical regression pass:** verify wifi, audio/ADSP, battery
  (SOCCP glink), USB, keyboard all still work **through Gunyah** — these use SCM/PSCI/glink/interrupts
  that now traverse EL2. Fix whatever Gunyah gates (SMC forwarding, IRQ routing, memory sharing).

### Phase 5 — Unlock display (days, once Phase 4 is solid)
- Under the primary VM (nonzero VMID), un-blacklist `msm`, apply the test48 DT delta (mdss + dispcc okay,
  pins 18/70 freed), boot. The full DPU driver init runs with permitted writes → **real display**, not the
  isolated-poke corruption we saw in the experiment.

## Preserving the working platform
The primary VM owns all hardware, so drivers are unchanged. Risk areas are the paths that now go through
EL2: **SCM/TZ** (ADSP PAS auth, battery), **PSCI** (`smc` today → Gunyah must forward), **interrupts**
(GICv3 routing to the VM), **RPMh/regulators**. Budget real debugging for these in Phase 4.

## Risks / unknowns
- **Board port** for a brand-new SoC (glymur) is the largest effort and the main risk.
- **Insyde-UEFI boot integration** — no Qualcomm bootloader to package the VM image; uncharted.
- **SCM/glink/IRQ compatibility** under Gunyah could break audio/battery until proxied correctly.
- Gunyah upstream maturity for laptop-class parts is limited (mostly Android/embedded).

## Effort & verdict
**High — ~6–10 weeks.** This is the *correct, robust, upstream-aligned* path and the primary-VM model is a
natural fit (one VM owns everything). Recommended as the real build **if** the cheap pKVM test in Plan B
does not work. Reward: a genuinely working, maintainable display path.

## Definition of done
Primary-VM Linux boots with the full working platform intact **and** `card1`/msm_dpu lights the internal
panel with a correct image (a modeset, not corruption).
