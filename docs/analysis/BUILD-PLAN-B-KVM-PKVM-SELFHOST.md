# Build Plan B — KVM / pKVM self-host

**Goal:** unlock the DPU using the KVM stack we already have (no Gunyah port), by getting Linux's DPU
register writes to carry a nonzero stage-2 VMID. Two tiers: a **cheap pKVM host-mode test that could
shortcut the entire project**, and a heavier full-passthrough guest fallback.

**Proven precondition (2026-07-13):** a KVM guest with *any* nonzero stage-2 VMID wrote the fatal VBIF
register successfully (readback-confirmed); bare-metal EL2 VHE host (VMID 0) resets on the same write. So
the gate is "EL1 + nonzero stage-2 VMID" vs "bare-metal EL2 host." The question this plan answers: can we
put the *normal* Linux into that permitted context cheaply?

---

## PHASE 0 — pKVM host-mode test (DO THIS FIRST — ~1 hour, could end the project)

**Idea:** In **protected KVM** (`kvm-arm.mode=protected`, nVHE), the pKVM hypervisor at EL2 runs the
**host kernel at EL1 under a host stage-2**. If that host stage-2 tags device MMIO with a nonzero VMID,
then the *ordinary* host Linux — no guest, no passthrough — would be permitted to drive the DPU directly.

**Test:**
1. Confirm the kernel supports pKVM (`CONFIG_KVM=y`, nVHE hyp; may need a rebuild with pKVM enabled — VHE
   is the current default). Verify the SoC will boot nVHE/protected.
2. Boot current test47 with `kvm-arm.mode=protected` on the cmdline (new grub entry; keep test47 default).
3. From the **host** (no guest), run the proven VBIF write to `0xaeb0160 <- 0x22222223` (reuse
   `/dev/vbifmap` + a tiny host writer, or a minimal module). Capture over netconsole.
   - **Write succeeds (no reset)** → the pKVM host carries a permitted VMID → just un-blacklist `msm`,
     apply the test48 DT delta, and the **normal host Linux drives the display**. Done, minimal effort.
   - **Still resets** → pKVM host stage-2 uses VMID 0 (or the write is still denied) → go to Phase 1.

**Why it might work:** pKVM deliberately confines the host in a stage-2 for isolation; that stage-2 is a
plausible source of a nonzero VMID on host transactions. **Why it might not:** pKVM may keep the host at
VMID 0. This is genuinely uncertain and *exactly* the kind of thing we can settle in an hour with the
harness we already built. Highest value-to-effort in the whole project — run it before committing to any
heavy build.

**Effort:** ~1 hour (worst case a kernel rebuild to enable pKVM, ~30–40 min + one boot).

---

## PHASE 1 — Full-SoC passthrough guest (fallback if Phase 0 fails)

**Idea:** a minimal host (initramfs) whose only job is to launch the *real* Linux as a KVM guest that
**owns all the hardware**, with a nonzero VMID (KVM's normal allocation already is nonzero — our control
proved VMID=1 works, so no pinning needed).

**What the guest needs:**
- All RAM as memslots; **all device MMIO** mapped into the guest stage-2 (the way we mapped the single
  VBIF page, but for the whole SoC device space).
- **GICv3 passthrough** and **all hardware interrupts** forwarded to the guest.
- The full working DT so every driver (display included) runs in-guest with its clocks/power.

**The hard part — honest:** KVM is designed for "host owns hardware, guests get a few passthrough
devices," *not* "one guest owns the entire SoC." Full-SoC MMIO passthrough is doable via many memslots,
but **forwarding every SoC interrupt** to the guest (VFIO-platform per device, or a GIC direct-injection
scheme) is heavy and against KVM's grain — you end up hand-building what Gunyah's primary-VM model does
natively. In practice this fallback can rival Plan A in effort with **less** robustness.

**Build sketch (only if pursued):**
1. Minimal host: buildroot/initramfs, KVM + VFIO-platform, a launcher VMM (kvmtool/crosvm/custom).
2. Enumerate every device's MMIO + IRQ from the DT; script the memslot + VFIO wiring.
3. Boot the real rootfs as the guest; regression-test the working platform (wifi/audio/battery/USB).
4. Un-blacklist msm + test48 DT delta → display.

**Effort:** High — comparable to Plan A but messier (IRQ forwarding is the killer). Only pursue if Phase 0
fails AND Plan A (Gunyah) is undesirable.

---

## Recommendation / decision tree
```
Phase 0 pKVM host test  ──success──▶  un-blacklist msm + test48 delta ▶ DISPLAY  (best case, ~1 hr)
        │ fails
        ▼
Plan A (Gunyah primary-VM)  ◀── preferred heavy build over Plan B Phase 1
        (Gunyah fits "one VM owns all"; KVM full-passthrough fights the tool)
```
**Do Phase 0 first.** It's an hour and might make everything else unnecessary. If it fails, prefer Plan A
(Gunyah) over Plan B Phase 1 for the real build.

## Preserving the working platform
- Phase 0: host is unchanged except run under pKVM — lowest regression risk (audio/wifi/battery keep their
  normal driver paths; only the EL2 confinement is new).
- Phase 1: guest owns all hardware so drivers are unchanged, but SCM/PSCI/IRQ now traverse KVM — same
  regression-test burden as Plan A Phase 4.

## Risks / unknowns
- **Phase 0:** whether pKVM host stage-2 carries a nonzero VMID (unknown — the test settles it). Whether
  glymur boots nVHE/protected cleanly.
- **Phase 1:** full-SoC IRQ forwarding complexity; VFIO-platform coverage for every device; stability.

## Definition of done
Phase 0: the host, under `kvm-arm.mode=protected`, drives the internal panel with a real modeset. Phase 1:
the full-passthrough guest boots the working platform and lights the panel.
