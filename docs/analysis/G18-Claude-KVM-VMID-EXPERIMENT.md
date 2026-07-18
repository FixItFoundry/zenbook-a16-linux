# G18 — KVM-VMID VBIF-write experiment (staged; box went offline mid-run)

**Date:** 2026-07-12 overnight. **Status:** BLOCKED then STAGED. The A16 (192.168.8.209) idle-suspended /
dropped off wifi after the boot-chain probes ("destination host unreachable"); a suspended laptop can't
be woken over wifi remotely. Harness fully staged on the Windows box (`C:\a16dump`) for a one-command run
when the A16 is back. Windows box + Desktop Commander were fine throughout.

## What this tests (the last real unknown for the display)
Does the MDSS **xPU** accept a **guest-stamped VMID `0x3C`** on a CPU MMIO write? If yes, the
Gunyah-primary-VM path (G17) is validated and worth building. If the box still hard-resets, the xPU
checks more than the bus VMID and path (a) is dead too (only unlocked/eng firmware remains).

## Confirmed hard parameters (locked this session)
- **Write target:** phys **`0xaeb0160`** = VBIF base `0xaeb0000` + `0x160` (RT VBIF AMEMTYPE_CONF0).
  Base confirmed from CLO `glymur.dtsi`: `display-controller@ae01000` reg `<0xaeb0000 0x3000>` name "vbif".
- **Write value:** `0x22222223` (the exact RMW value captured faulting on bare-metal test48/49).
- **Target VMID:** **`0x3C`** (=60) — firmware-bound to Display (DEVCFG `NAMEDNODE_Display SIDMappings=0x3C`).
- Boot topology: Linux at EL2/VHE, PSCI=smc, no resident hyp → bare-metal presents VMID 0 → xPU denies.

## Staged files (on `C:\a16dump`, push to A16 `/home/jcasco/kvm_vbif/`)
- `kvm_vbif_guest.S` — EL1/MMU-off guest: writes markers to GPA 0x0, does the VBIF write, signals done.
- `kvm_vbif_test.c` — KVM host: RAM memslot + **/dev/mem passthrough of the VBIF page** into the guest,
  runs it, reads the `0x900D` success marker.
- `kvm_vmid_pin.PATCH-NOTE.txt` — how to force KVM's VMID to `0x3C` (patch `arch/arm64/kvm/vmid.c`;
  arm64 KVM is builtin → needs a kernel rebuild + a new grub entry, default stays test47).
- `run_kvm_vbif.sh` — assemble guest + build test + arm netconsole + run + report.

## Run procedure (when A16 is up)
1. Push the 4 files to `/home/jcasco/kvm_vbif/`.
2. Apply the VMID-pin patch to `arch/arm64/kvm/vmid.c` (verify symbol names against the actual file),
   set the experiment default to `0x3C`; build `Image` + install; add grub id `dt-kvmvmid`
   (keep `dt-test47` as saved default so any reset/hang recovers to the daily driver).
3. Boot `dt-kvmvmid`; confirm `dmesg | grep VMID`.
4. `bash run_kvm_vbif.sh` with netconsole listener running on the Windows box.

## Outcomes
- **Box SURVIVES + `RESULT: SUCCESS` (marker `0x900D`)** → xPU gates on the bus VMID; a guest can satisfy
  it → **build the self-hosted Gunyah primary-VM (G17)**; display is achievable without firmware unlock.
- **Box HARD-RESETS at the write** (netconsole ends, auto-recovers to test47) → xPU checks a
  hyp-identity/secure attribute beyond the VMID → path (a) dead; only unlocked/eng firmware remains.

## Safety
Same net as all prior display tests: one-shot grub, netconsole capture, auto-recovery to test47. Worst
case is a hard hang needing a manual power-cycle (as the keep-MDSS-powered test once did) — no damage.

## Caveats (finalize on box)
- `kvm_vbif_test.c` + guest asm are **correct-by-design but UNTESTED** (box was down) — expect a little
  KVM-API/asm debugging. `/dev/mem` device mmap requires `CONFIG_STRICT_DEVMEM=n` or `iomem=relaxed`
  (prior island `/dev/mem` probes worked, so this is already satisfied).
- Confirm VMID width ≥ 6 bits (dmesg "KVM: VMID bits") — 8/16-bit both fine for `0x3C`.

---

## RESULT (2026-07-13) — DECISIVE POSITIVE: a VM can satisfy the MDSS xPU

Implemented as a helper module `vbifkvm.ko` (no kernel rebuild): (a) a **kretprobe on
`kvm_arm_vmid_update`** forcing the guest's stage-2 VMID low bits to a `force_vmid` sysfs param
(default `0x3C`); (b) `/dev/vbifmap` = `remap_pfn_range` of VBIF phys `0xaeb0000` (bypasses
`CONFIG_STRICT_DEVMEM=y`). A minimal MMU-off EL1 KVM guest (RAM memslot + VBIF passthrough memslot)
writes `0x22222223 → GPA 0xaeb0160`. Hardware VMID width = 16 bits.

**Outcome:**
- **VMID pinned `0x3C`:** the guest VBIF write **COMPLETED, the box did NOT reset**, and host readback
  `VBIF[0x160] = 0x22222223` **confirmed the write landed in hardware.** On bare-metal EL2 (VMID 0) this
  identical write hard-resets (test48/49). → **the MDSS xPU gates on the guest / EL1-stage-2 context,
  not a hyp-identity → a VM satisfies it → the Gunyah-primary-VM path (G17) is VALIDATED. Display is
  achievable on this retail unit without a firmware unlock.**
- **Control `force_vmid=1`:** also **survived** (no reset) → the gate appears to be "EL1 guest with a
  nonzero stage-2 VMID" vs "bare-metal EL2 host (VMID 0)"; the *exact* value `0x3C` may not be required,
  which relaxes/eases the path. (Confirming VMID=1's write physically lands is the next check.)

**Panel artifact (corrected per Jesse's direct observation):** the blue half-panel appeared on the
**FIRST run** — VMID `0x3C`, writing the *legit* value `0x22222223`, which **survived**. So a single
guest write to the live RT-VBIF visibly perturbed the panel (left-half = normal simplefb desktop,
right-half = blue + horizontal-scanline corruption) — **our guest VBIF write reached the real display
memory-interface** (simplefb is static, so scanout was actively rewritten). It is **reproducible and
non-fatal** with the legit value; `bash /home/jcasco/kvm_vbif/replay.sh` re-triggers it.

**Separate hard-hang:** a *later* disambiguation run wrote a **junk value `0x33333331`** into the VBIF
memtype register (not the legit `0x22222223`) — THAT hung the box (bad memtype config stalls the memory
interface), needing a manual power-cycle → auto-boot test47. Lesson: **only `0x22222223` is safe**; other
values corrupt the memory-interface config and can hard-hang.

**Meaning for the project:** before tonight the display was "firmware-gated, likely needs unlocked fw."
Now it's **"achievable by running Linux as a hypervisor guest"** — the wall is breached in principle. The
remaining work is engineering: run the real DPU/msm driver inside a guest (KVM device passthrough of the
whole MDSS island, or the Gunyah primary-VM per G17). The panel artifact suggests the scanout path is
within reach.

**Caution for next runs:** the DPU/VBIF poking can hard-hang (needs manual power-cycle). Keep test47 as
the saved grub default (auto-recover), keep runs short, and prefer read-back-with-sentinel over repeated
writes. Files: `/home/jcasco/kvm_vbif/` + `C:\a16dump\{deploy_kvm,run_exp,run_ctrl,update_gt,patch_module}.sh`.
