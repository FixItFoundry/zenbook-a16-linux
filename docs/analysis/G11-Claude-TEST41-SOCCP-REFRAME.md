# G11 — Test41: battery reframed AGAIN → SOCCP/OOB subsystem, not a PD, not a bad offset

**TL;DR.** Two firm advances, one big reframe, no DTB change.

1. **(A) CLOSED — qcom_battmgr is structurally impossible on this box.** The full firmware
   PDR service inventory (every `.jsn` in FileRepository.zip) hosts exactly ONE working service,
   `avs/audio` on the ADSP. **No charger/battery/PMIC/fuel-gauge service PD exists on ANY
   subsystem** (ADSP root/sensor/audio, OOB-MSS-NS, OOB-MSS-TEE, SOCCP root — all other service
   lists are empty). So battmgr's PMIC_GLINK battery request can never be answered: there is no
   charger PD firmware to answer it. Stop trying to revive battmgr. The ASUS-EC/SOSI path is the
   ONLY battery path — permanently.

2. **(NEW) The SOSI blob is populated by the SOCCP (SoC Companion Processor), which is ALIVE on
   our Linux boot but never told to start battery reporting.** This unifies G09 (SOSI dormant,
   LKUP=0, blob all-zero) and G10 (raw SMEM poke did nothing) into a single, actionable cause.

3. **G10 interpretation (ii) refined and favored over (i).** Our test40 CTLD/HSWD SMEM write did
   nothing not because the offset was wrong, but because a raw SMEM write with **no OOB→SOCCP
   enable handshake** never wakes the filler. Chasing the "correct" CTLD offset (option B) is
   lower value than performing the enable handshake.

---

## Evidence

### Firmware PDR inventory (local, FileRepository.zip `.jsn`)
- `adspua.jsn` (audio_pd, qmi_iid 74): `tms/servreg` + **`avs/audio`**  ← only real service on the SoC
- `adspr.jsn` (root_pd), `adsps.jsn` (sensor_pd): `tms/servreg` only
- `oobmssn.jsn` (oobmss-ns root_pd, iid 67): **`sr_service: []`**
- `oobmsst.jsn` (oobmss-tee root_pd, iid 160): **`sr_service: []`**
- `soccpr.jsn` (soccp root_pd, iid 186): **`sr_service: []`**
- grep `charg|batt|pmic|fg_|fuel|power_supply` across all `.jsn` → **zero hits**.

### SOCCP is present and alive under our DT boot (live box .209, test36 DTB)
- DT reserved-memory: `soccp@89300000` (0x400000, **no-map, no compatible, no driver** — just a
  carveout), `soccpdtb@892e0000`, plus OOB carveouts `oobdtboem@87d50000`, `oobdtbqc@87d30000`,
  `oobdaretag@86e10000`, `oob-secure@87170000`, `oob-nonsecure@87e00000`; noc `qcom,glymur-oobm-ss-noc`.
- DT `smp2p-soccp`: `qcom,smp2p`, remote-pid **0x13 (19)**, `master-kernel` (outbound
  `#qcom,smem-state-cells`), `slave-kernel` (inbound interrupt-controller).
- `qcom_smp2p` driver **has smp2p-soccp bound** (`/sys/bus/platform/drivers/qcom_smp2p/smp2p-soccp`).
- `/proc/interrupts` line 146 `ipcc 3014658 Edge smp2p-soccp` = **count 1** (fired). Contrast
  `smp2p-cdsp` = 0 (CDSP down). ⇒ SOCCP negotiated smp2p at least once ⇒ it is powered/reachable.
- No OS firmware image for SOCCP exists: `qcsubsys_ext_soccp8480` ships only `RSCP.bin` (1117 B
  config), `soccpr.jsn`, inf/cat — **no `.mbn`/`.elf`**. ⇒ SOCCP is UEFI/ABL-loaded and autonomous
  (that's why it's up without any Linux remoteproc, unlike ADSP which we had to PAS-load).

### The enabler is the OOB subsystem, driven from user space on Windows
- `qcOobWindowsService8480.dll` (178 KB, `WP\OobWindowsService\rel\11.1.4`, ctx
  `OOB_WINDOWS_COMMON_DEVICE_CONTEXT`) imports only Win32 file/IO/threadpool APIs ⇒ it's a thin
  user service that DeviceIoControls an **OOB kernel driver**; the actual SOCCP comms (smp2p+SMEM)
  live in that kernel driver. On Linux nothing performs this enable/registration handshake, so
  SOCCP never starts filling SOSI (LKUP stays 0, blob stays zero) — exactly what G09 measured.
- Consistent with G09's finding that `qcabd8480.sys` is a **pure polled-SMEM reader**: qcabd only
  reads the blob; the OOB stack is what makes SOCCP populate it.

---

## Battery chain (corrected model)
`OOB user service → OOB kernel driver → (smp2p-soccp doorbell + SMEM) → SOCCP → EC/PMIC gauge →
SOCCP writes SOSI@0xFFE0AD80 → qcabd8480 polls SOSI → Windows battery UI.`
Linux has: SOSI reader (a16_battery), a live smp2p-soccp channel, SOCCP alive.
Linux is missing: the **OOB enable handshake** that tells SOCCP to start writing SOSI.

## Next steps (test42), priority order
- **(1) Live enable-bit sweep — cheap, remote, single-variable, no reboot.** Kernel module that
  `qcom_smem_state_get()`s the `smp2p-soccp` master-kernel outbound state and pulses candidate
  enable bits one at a time (state is a small bitfield), re-dumping SOSI LKUP + battery buffers
  after each pulse (reuse `sosi_probe`). If any bit makes SOCCP publish LKUP>0 / non-zero buffers,
  battery is unlocked with a tiny driver. smp2p is designed for exactly this — safe.
- **(2) Ground the bit / IOCTL — bounded static RE.** Find the OOB **kernel** driver in
  FileRepository.zip (the .sys behind qcOobWindowsService; likely a qcsubsys/oob or a WMI/ACPI
  function driver) and RE its DeviceIoControl→smp2p/SMEM path to identify the exact "start battery
  telemetry" bit/sequence. Removes the guesswork from (1).
- **(3) One Windows/ACPI boot dump (G10 option C) — still the ground-truth fallback.** Dump
  `0xffe0ad80` (size ≥0x3dc) while the gauge works to see the populated blob + real `_BST`/`_BIX`
  offsets and what CTLD/HSWD hold when enabled. Now framed as confirmation, not the primary lead.

## Files
- New here: `_jsn_dump.txt` already had ADSP; this session read oob/soccp `.jsn` + oob service dll
  direct from the zip (no new extracts needed). No DTB change (test36 still flight).
- a16_battery.ko unchanged/healthy (serial X2000098, present=1).
