# Thermal sensor mapping — HANDOFF (2026-08-17)

Started because: while chasing the NVMe overheat-during-charging investigation
tonight, noticed `hwmon7` (nvme) logs `temp1_input not attached to any
thermal zone` at boot. Worth mapping the whole picture before proposing any
DT patch, rather than fixing just the one sensor we happened to be staring at.

## Current inventory (this boot, `7.2.0-ZenbookA16-20260817+`)

- **114** `hwmon` devices total
- **102** `thermal_zone` devices total (CPU cores, cpullc, qmx, GPU, GPUSS,
  AOSS, DDR, video, camera, PMIC rails — all wired, all with `*-thermal`
  zone types matching a hwmon of the same name). This is the work already
  landed 2026-07-31 per CHANGELOG ("41 of 41 cpu*/cpullc* zones bind").

## Orphaned hwmon devices — NOT wired to any thermal_zone

Identified by elimination: hwmon devices whose `name` does NOT correspond to
a `thermal_zone*/type`. All of these are power-supply or codec devices with
their own temperature-adjacent hwmon interface, wired for *readback* but not
for OS-level thermal *policy* (no passive trip, no critical shutdown tied to
them):

| hwmon | name | device |
|---|---|---|
| hwmon0 | `hid-...-battery-7` | HID battery (secondary/wireless peripheral?) |
| hwmon1 | `qcom_battmgr_bat` | main battery |
| hwmon2 | `qcom_battmgr_ac` | AC/charger |
| hwmon3 | `qcom_battmgr_usb` | USB power |
| hwmon4 | `qcom_battmgr_wls` | wireless charging |
| hwmon5, hwmon6 | `ucsi_source_psy_...01/02` | USB-C PD source, both ports |
| **hwmon7** | **`nvme`** | **the one that started this** — 3 temp inputs, confirmed via tonight's charging-heat investigation (Sensor 1 swung 74→91°C tracking charger plug state) |
| hwmon8–11 | `wsa884x` ×4 | **all four SoundWire speaker codecs have their own temp sensor, also unwired** — not previously noticed |

## Why this matters, concretely

Tonight's NVMe investigation found Sensor 1 swinging up to 91°C purely from
charging-adjacent heat, with nothing in the OS thermal framework watching it
— the drive is expected to self-protect via its own firmware, but nothing
here confirms that's actually configured, and nothing warns the user if it
isn't. The WSA884x finding is new and unexplored: 4 speaker codecs sitting
right next to a laptop chassis surface, also with no OS-level thermal policy.

## ★ UPDATE 2026-08-21 — cross-checked against the Windows-on-Arm ACPI/driver dump

Source: BitLocker-mounted `nvme0n1p14` (recovery-passphrase unlock via `cryptsetup
bitlkOpen`, read-only — Windows' own Fast Startup/hibernation state forced ntfs-3g to
refuse read-write regardless of the mount flags, which is the correct outcome), plus
Jesse's own extraction at `Users/jesse/Zenbook_HW_Dump/` (`SUMMARY_REPORT.txt`,
`DeviceTree/PnpDevices_Detailed.txt`, fresh `ACPI/dsdt.dat`, `Registry/*.reg`).

**Finding A — the 9 orphaned-looking ACPI temperature sensors are already fully wired.**
The dump lists exactly nine `Qualcomm Temperature Sensor Device` ACPI nodes: `QCOM0F5A`,
`QCOM0F91`, `QCOM1038`, `QCOM1039`, `QCOM103A`, `QCOM0FE7`, `QCOM0F58`, `QCOM0F59`,
`QCOM0FB5`. That count matches, field for field, `docs/hardware.md`'s "SPMI ✅ mostly"
section: **nine PMICs bind `qcom-spmi-temp-alarm`** (six on `spmi_bus0`, three on
`spmi_bus1`), each with a live `thermal_zone` (`pmcx0102-*`, `pmh0101`, `pmh0104-*`,
`pmh0110-*` — confirmed present in `/sys/class/thermal/` on this boot). Windows and Linux
are watching the same nine PMIC rails. **Nothing to wire here — already closed, just not
previously cross-checked against the Windows side.**

**Finding B — the 3 "mitigation" ACPI devices are software policy, not sensors, and
Linux already has an equivalent for two of three.** `QCOM1005` (Subsys Base Thermal
Mitigation), `QCOM0FC7` (Wlan Thermal Mitigation), `QCOM0FB8` (NSP0 CDSP SW Thermal) are
Windows-side *policy* nodes that consume the sensors above, not additional hardware.
Linux's equivalents: the `step_wise` governor + `cooling-maps` (covers Subsys/CPU) and
the already-bound `ath12k_thermal` cooling device (covers Wlan). **NSP0/CDSP (the Hexagon
NPU) has no Linux thermal mitigation because the NPU itself isn't bound yet** — that's a
real gap, but it's an NPU-bring-up gap, not a thermal-DT gap, and out of scope here.

**Finding C — answers Next-step 3 below: NVMe and the WSA884x codecs are not thermally
managed by Windows either.** Grepped the full dump (`SUMMARY_REPORT.txt`,
`PnpDevices_Detailed.txt`, `PnpDevices_All.csv`) for anything NVMe- or
codec/`884x`-adjacent to a thermal device: **zero hits.** So this is not a case of
Windows having a reference thermal-zone binding we're missing — **neither OS puts these
two devices on the OS thermal-policy bus on this hardware.** That's consistent with (but
does not prove) both self-protecting via their own firmware, and it means there is no
"known gap upstream" to point a patch at — Next-step 3 is answered, not open.

## Next steps

1. ~~Check whether Windows/other X2 Elite boards wire NVMe/codec thermal zones~~ —
   **answered 2026-08-21, Finding C: no, on neither OS.** Not a reference-design gap.
2. Pull `nvme`/`wsa884x` datasheet or driver-default trip points, if any exist, rather
   than inventing thresholds — **still open, now lower priority**: absent evidence of an
   active gap (Finding C), this is a belt-and-suspenders addition, not a fix for a
   confirmed-missing safety net.
3. If pursued, decide per-sensor whether it needs a DT `thermal-zones` entry (passive
   trip + `cooling-maps`, mirroring the existing CPU pattern — see `docs/modifications.md`
   for the exact 42-zone pattern, not "41", after the `cpuillc-2-1-thermal` typo-zone
   correction) or stays read-only.
4. Draft as a `thermal-zones` DT addition once/if trip points are grounded, not guessed.

Related: `docs/hardware.md` (Thermal ✅ and SPMI ✅ sections), `docs/modifications.md`
(cooling-maps/zone-count detail), `docs/power-and-thermal.md` (root-cause history — its
"NEXT: write cooling-maps" framing is stale, see the note added there 2026-08-21).
