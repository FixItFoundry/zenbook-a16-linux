# G10 — Test40: battery enable experiment + provider diagnosis

**TL;DR.** Both Linux-visible battery paths are alive as *drivers* but blocked at the *firmware
service* level, and the obvious shortcut is falsified:

1. **pmic_glink + qcom_battmgr are UP** (aux devices `pmic_glink.power-supply.0`, `.ucsi.0`,
   `.altmode.0` created; `qcom-battmgr-bat/ac/usb/wls` registered) — but the ASUS firmware
   **returns no battery data** (all properties empty; `upowerd: no valid voltage value ...
   assuming 10V`). This is the DSDT's "pmicglink down" condition (`LKUP==0`).
2. **The SMEM enable-write is FALSIFIED.** Writing the DSDT `LKST(1)` handshake
   (`CTL0=1 -> blob+0x100`, `HSW0=4 -> blob+0x180`) into the SOSI blob did **not** wake the
   coprocessor: 44 s later every battery buffer is still zero. (The module's "RESPONDED"
   print was a self-inflicted false positive — the crc delta `0x705` == exactly our own two
   writes: `1*(0x100+1) + 4*(0x180+1)`.) Words restored to 0 afterwards; SMEM back to baseline.

**Conclusion:** live battery is blocked at the ASUS/Qualcomm battery *firmware service*, not at
any Linux driver we can write. Both OS-visible paths — qcom_battmgr (glink/QMI) and the ABD/SOSI
SMEM filler — are downstream of that service, which is not responding on this device under our
DT boot. This unifies G06 (battmgr -EAGAIN) and G09 (SOSI dormant) into one root cause.

---

## 1. Provider diagnosis (on-box, `boot-kit/a16dump/recon40.sh`, `journal40.sh`)
- `remoteproc0 = adsp : running`. glink edge up: `adsp_apps`, `IPCRTR`, `rpmsg_ctrl`,
  `fastrpcglink-apps-dsp`, GPR svc `2:1`/`2:2` all probe 0. So the ADSP glink transport works.
- `pmic-glink` probe 0; `qcom_battmgr` probe 0; `pmic_glink.power-supply.0` probe 0. Drivers fine.
- `qcom-battmgr-bat` attributes ALL empty (`present=`, `voltage_now=`, `status=` …),
  `waiting_for_supplier=0`. upowerd falls back to "assuming 10V". => battmgr's opening request
  over PMIC_GLINK gets no battery response from firmware. No timeout/error is even logged — the
  firmware simply never answers the battmgr QMI channel.
- Non-fatal: two USB `Failed to create device link (0x180) with supplier a600000.usb/a800000.usb`
  for pmic-glink connectors (altmode/DP-HPD wiring; unrelated to battery data).

## 2. Enable experiment (on-box, `boot-kit/a16dump/sosi_enable.c`)
Mapped `0xffe0ad80` (988 B, plain DRAM — safe, no XPU/watchdog), wrote `1 -> +0x100`,
`4 -> +0x180` (the AML `CTLD=CTLT`/`HSWD=HSWT` essence), polled 6 s + re-checked at +44 s.
Result: **no change** anywhere except the two written words themselves; data area (0xf8..0x3dc),
both 22-entry tables, and all battery selectors remain 0x0. `sosi_restore.c` zeroed them again.

Two interpretations remain, not yet distinguished:
- **(i)** Linear offset is wrong — real CTLD/HSWD physical slot differs (selector map is
  non-linear; our write landed in unused table slots `T1[2]`/`T2[12]`). 
- **(ii)** The SOSI filler (a coprocessor/EC) is gated on the same firmware battery service
  that isn't answering — a pure SMEM poke can't wake it.
Convergent evidence (both glink AND SMEM paths dead) favors (ii), but (i) isn't ruled out.

## 3. Next steps (test41), priority order
- **(C) One Windows/ACPI boot snapshot — highest information, Jesse action.** Boot Windows (or an
  ACPI Linux boot), then dump the SAME region `0xffe0ad80` (size 0x3dc, or larger) while the
  battery gauge works. This directly reveals (a) whether the blob is populated when the service
  is alive, (b) the *real* offsets of live `_BST`/`_BIX` data, and (c) what CTLD/HSWD hold when
  enabled — resolving (i) vs (ii) at a stroke. Reuse `boot-kit/a16dump/sosi_probe.c` logic.
- **(B) Finish RE of the SPB IOCTL handler** (set in DeviceAdd `func 0x140008000`; the WMI
  publisher `0x140001ce8` is NOT it) to recover the true selector->offset map, then retry the
  enable-write at the correct CTLD offset. Bounded static-RE task; rules out (i).
- **(A) Chase the firmware battery service** — why the ADSP/PMIC glink QMI battmgr channel gets
  no response (PDR service list `adspua.jsn` in FileRepository.zip; is a battery PD even hosted?).
  Deepest, but it's the true root cause and would light up battmgr *and* SOSI together.

## 4. Files
- New on box: `~/sosi_enable/`, `~/sosi_restore/` (+ existing `~/sosi_probe/`, `~/a16_battery/`).
- New here: `boot-kit/a16dump/{recon40,journal40,run_enable,run_restore}.sh`,
  `boot-kit/a16dump/{sosi_enable,sosi_restore}.c`, `boot-kit/re_abd10.py` (callers/func passes).
- No DTB change (test36 still flight). a16_battery.ko unchanged/healthy (serial X2000098).
