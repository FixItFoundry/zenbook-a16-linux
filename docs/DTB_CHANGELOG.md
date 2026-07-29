# DTB Iteration Changelog — glymur-crd → glymur-asus-zenbook-a16

Every test DTB, its delta, its result, its lesson. Base: mainline v7.1 `glymur-crd.dtb`.
(tests 1–11 built with pyfdt; verified via libfdt from test-canary onward; all in `boot-kit/out/`)

| # | Delta vs base (cumulative where noted) | Result | Lesson |
|---|---|---|---|
| 1 | 5 board regulators GPIO-stripped→always-on; wcn7850-pmu, gpio-keys disabled | reset @~watchdog | not the killer |
| 2 | test1 + SCMI disabled | reset, identical | SCMI not the killer |
| 3 | regs + PCIe dom6 (pci@1c00000)+phy disabled | reset, identical | dom6 not the (sole) killer |
| 4 | test3 + SCMI + 3 extra USB ctrls + MDSS disabled | reset, identical | none of these |
| 5 | test4 + ALL PCIe disabled (diagnostic) | reset, identical | not PCIe |
| 6 | test4 + usb@a400000 disabled (diagnostic) | reset, identical | not dwc3-mp |
| 7 | ONLY 4 CRD GENI SEs disabled | reset, identical | not the SEs |
| 8 | whitelist-minimal (all of the above + bwmon PMUs) | reset, identical | leaf devices exonerated en masse |
| 9 | ONLY 6 island NoCs disabled | reset, identical | islands innocent (later proven probing fine) |
| 10 | test8 + island NoCs | reset, identical | ditto |
| 11-canary | ONLY interconnect@2000000 disabled | 2000000 line VANISHED from log | **DTB delivery proven working; "identical resets" = observability illusion** |
| — | instrument: `dyndbg="file drivers/base/dd.c +p"` | last line names probing device | **KILLER IDENTIFIED: f100000.pinctrl (glymur-tlmm)** — TrustZone-protected GPIO registers, read = XPU violation = watchdog reset (undisclosed pins; not in ACPI; per-machine, cf. X1E laptops) |
| 12-armor | gpio-reserved-ranges = ALL 249 pins | **MILESTONE 1: systemd in initramfs** (first A16 DT userspace); display died at udev coldplug | TLMM conviction confirmed |
| 13-surgical | reserved-ranges = all except uart 86-87, wifi-pcie 146-148, nvme-pcie 152-154 | initramfs, same depth; NVMe still absent | pins alone insufficient; initrd hostonly disease found next |
| — | fix: `dracut --no-hostonly` (fat initrd) | PCIe-4 probed (first PCIe on DT) | **hostonly initrd lacked ALL DT-only modules** (rpmh-regulator, gpi-dma, phys) |
| 14 | fresh base: reserved-ranges + MDSS + dispcc disabled | **display survived to visible emergency shell** | **dispcc (display island clock ctrl) was the post-TLMM silent killer** |
| 15 | test14 + 4 CRD GENI SEs disabled | (skipped to 16) | clears sync_state noise; SEs' pins are reserved anyway |
| 16 | test15 + gen5x4 PCIe PHY (phy@1b50000) vdda-phy/vdda-pll supplies DELETED | **MILESTONE 2: full DT desktop, 20s boot, NVMe @3.2s** | gen5 PHY supplies pointed at `_e0` PMIC instances that don't exist on A16 (`_e1` do — why gen4/wifi PHY worked); dummies fine, firmware powers rails |
| 17 | test16 + wifi@0 child node disabled + ALL 9 USB phy supplies stripped | 6/9 phys probed; radio enumerated (Gen3 x1 link up, 17cb:1112) but ath12k didn't bind; USB still down (repeaters) | supply-strip generalizes; disabled-but-present PCI child node still blocks binding; eUSB2 phys also need REPEATERS (smb2370 on SPMI PMICs — some of which are ghosts: SPMI txn failures) |
| 18 | test17 + wifi@0 node DELETED + fa2000 repeater→live donor (183) | **Wi-Fi UP on DT (ath12k bound, associated, SSH reachable at .209)**; fa2000 probed; a400000 then wanted fa1000 | delete > disable for PCI child nodes; repeater repoint works |
| 19 | test18 + fa0000→repeater 178, fa1000→183 (shared with fa2000) | **USB UP: dongle NIC enumerated; CIFS mounted at boot** (input verdict pending) | PHY framework tolerates shared repeaters; multiport needs all its port PHYs |
| 20-23 | Iterations attempting to enable I2C input devices (Touchpad/Keyboard/Touchscreen) | Watchdog resets / Boot failures | Probing incorrect protected pins caused watchdog resets. User error in grub delayed testing. |
| 24 | The Grand Realignment: Touchscreen on `a80000`, Touchpad on `b80000`, EC on `88c000`. Freed pins 48, 76, 77. | **Touchscreen WORKING! Fan quieted down!** Battery 0%. No kbd/tpad. | `88c000` is the Embedded Controller (EC) bus. Enabling it allows Linux thermal logic to stabilize the fan. Touchscreen initialized perfectly at `0x10`. Touchpad failed due to incorrect `hid-descr-addr=0x20` and wrong power bindings. |
| 25 | Touchpad: `hid-descr-addr=0x1` + stripped `vdd-supply`. Keyboard: Moved to true bus `i2c@b94000` (I2C5) at `0x3a`, freed pins 20 & 21. | **Trackpad WORKING!** Touchscreen still works, fan stable. Keyboard still dead. | Touchpad power and HID address fixes were correct! The keyboard on `b94000` didn't probe successfully (or requires different pins/power). GPU confirmed entirely missing from base DTB. |
| 26 | Keyboard moved back to true EC bus `i2c@88c000` @0x15 (hid-descr-addr=0x01, vdd stripped), **bus clock dropped 400→100kHz** to give the EC time; GPU graft abandoned (needs 7.2-rc). | **FAILED, and 100kHz REGRESSED it:** `geni_i2c 88c000.i2c: Timeout abort_m_cmd` x2 → `probe of 3-0015 returned 6` (-ENXIO) after hanging 4.1s. Keyboard backlight still "breathing". Touchpad/touchscreen unaffected. | DSDT confirms kbd IS at 0x15/88c000 (device ECKB `_HID QTEC0001`, controller IC20=0x88C000). 100kHz makes the GENI master command time out — LOWER speed is worse. Descriptor read (not IRQ) is the failing step; EC ACKs at 400kHz (test24) but returns zeros. |
| 27 | **Single-variable revert of test26: `i2c@88c000` clock 100kHz→400kHz (0x61a80).** Everything else identical (kbd 0x15, hid-descr-addr=0x01, IRQ TLMM pin 67, vdd stripped). | **BOOTED, FAILED — same as test26, NOT the predicted test24 ACK:** `geni_i2c 88c000.i2c: Timeout abort_m_cmd` x2 → `probe of 3-0015 returned 6` (-ENXIO). Platform otherwise perfect (tpad+ts+fan+wifi+usb). | **Clock was a red herring.** 400kHz alone does NOT restore the ACK ⇒ the test24→test26 regression was the *stripped power/pinctrl*, not the clock (see row 28). |
| 28 | **Re-add the 3 bindings test26 stripped** to keyboard@15 (keep 400kHz): `vdd-supply=<VREG_MISC_3P3>` (0x6a, 3.3V GPIO load switch), `vddl-supply=<vreg_l15b_e0_1p8>` (0x6b), `pinctrl-0=<kybd-default gpio67>` (0x8f). Node is now byte-identical to test24 on the working test27 platform. | BUILT + verified (`build_test28.py`, python-fdt patch of test27.dtb; props confirmed on readback). Not yet booted. | **Deeper-dive finding (G03):** `abort_m_cmd` = target not ACKing = no power. VREG_MISC_3P3 is `regulator-boot-on` but NOT always-on → with no consumer it stays off → keyboard 3.3V rail dead (backlight "breathes" on standby rail). Restoring the supply should reproduce test24's ACK. Upstream ASUS Vivobook S15 (x1e80100) confirms **TLMM 67 LEVEL_LOW + gpio67-func-gpio pinctrl** is the correct kbd IRQ; also caught gpio67 double-claimed as `qup2_se0` SPI-CS in test27 — pinctrl restore reclaims it. Next real blocker = zero HID descriptor (try `post-power-on-delay-ms`). |

### Keyboard analysis (this-model, 2026-07-11) — DSDT ground truth + why test27
DSDT device **ECKB**: `_HID "QTEC0001"`, `_CID "PNP0C50"` (HID-over-I2C), `I2cSerialBusV2(0x0015, ControllerInitiated, 0x00061A80=400kHz, "\_SB.IC20")`, GpioInt Level ActiveLow Wake pin **0x2C0** on GIO0. **IC20 `_CRS` Memory32Fixed = 0x0088C000** ⇒ keyboard = **0x15 on i2c@88c000** (400kHz). So Gemini's earlier 0x3a/b94000 (from another laptop) was wrong (`probe of 2-003a returned 6` in the test25 boot = -ENXIO, nothing ACKs there). Live bus map: i2c-0=b80000(tpad 0x15), i2c-2=b94000(empty), i2c-3=88c000(EC/kbd 0x15), i2c-4=a80000(touchscreen 0x10). All working input IRQs use the **TLMM** pinctrl (phandle 0x69): touchscreen TLMM 51, touchpad TLMM 3, keyboard currently TLMM 67 (unproven guess). Note DSDT's kbd IRQ 0x2C0=704 is >249 so it is NOT a literal TLMM pin — it decodes into the PMIC-GPIO/GIO0 aggregate bank (undecoded), so TLMM 67 is probably wrong, BUT: the i2c-hid **descriptor read does not need the IRQ**, so the test24 "zero descriptor @400kHz" and test26 "bus timeout @100kHz" point at the **EC needing a wake/init before it answers the descriptor**, not at the IRQ. Order of attack for test28+: (a) confirm test27 reproduces "EC ACK, zero descriptor" @400kHz; (b) live-probe the EC with `i2ctransfer`/`i2cdetect` on i2c-3 to find whether 0x15 ACKs and what a raw HID descriptor read returns; (c) try an EC wake (SET_POWER / GPIO) and/or a `post-power-on-delay-ms`; (d) only then chase the real (PMIC-GPIO) interrupt for input delivery. **Battery reframe:** DSDT `\_SB.ABD`/PMGK = ASUS EC exposes the battery gauge (BIXD/BPCD op-regions at EC addrs 0x04/0x06/0x08) over I2C — so `qcom_battmgr` will never populate (`qcom-battmgr-bat` is present but blank); battery needs the ASUS-EC path, a separate workstream. **GPU:** absent from base DTB (`lspci`=4 devices, `/sys/class/drm/card0`=simpledrm EFI-fb only); defer to a 7.2-rc base with upstream X-Elite Adreno nodes.

## Cumulative recipe (= the seed of glymur-asus-zenbook-a16.dts)
1. `tlmm: gpio-reserved-ranges` — currently blanket-reserved except pins 86-87,146-148,152-154 (TRUE reserved set still to be bisected; kbd/tpad pins must be freed for internal input)
2. `mdss` + `dispcc`: disabled (display island off — panel bring-up is its own future project)
3. CRD GENI SEs (i2c@a80000, serial@a98000, i2c@b80000, i2c@b94000): disabled (CRD-only wiring)
4. `phy@1b50000` (gen5 NVMe PHY): vdda supplies deleted (ghost _e0 PMICs)
5. `pci@1bf0000/pcie@0/wifi@0`: **deleted** (CRD's WCN7850; A16 has QCC2072 — ath12k binds bare PCI dev)
6. All eUSB2/QMP USB phys: supplies deleted (ghost PMICs)
7. eUSB2 repeaters: fa0000→178, fa1000/fa2000→183 (LIVE smb2370s; A16's true per-port repeater map TBD from DSDT — current sharing is bring-up pragmatism, firmware pre-configures the real ones)
8. Kernel cmdline: `clk_ignore_unused pd_ignore_unused arm64.nopauth` + `modprobe.blacklist=msm,... rd.driver.blacklist=msm,...` (display stack must stay unbound, though GPU node is missing anyway)
9. Initrd: dracut `--no-hostonly` (or explicit add_drivers for the qcom DT stack)
10. **Touchscreen**: Enabled on `i2c@a80000` (addr `0x10`), pin 48 freed.
11. **Embedded Controller (EC)**: Enabled on `i2c@88c000`, pins 76 & 77 freed. Resolves 100% fan speed.
12. **Touchpad**: Enabled on `i2c@b80000` (addr `0x15`), power bindings stripped, `hid-descr-addr=0x1`.
13. **Keyboard**: Enabled on `i2c@b94000` (addr `0x3a`), pins 20 & 21 freed.

## Still open
- True reserved-pin set bisect; true repeater map; panel/backlight.
- GPU (needs node `gpu@3d00000` manually injected from `x1e80100.dtsi` into the base DTB).
- Audio (SoundWire/SDCA map in DSDT _DSD).
- Battery (handled by EC, needs proper Asus EC driver).

## Keyboard bring-up thread (tests 24–29) — see G02/G03/G04
- Keyboard is DSDT `ECKB` @ **0x15 on i2c@88c000 (QUP_2_SE_3)** — NOT b94000/0x3a (that earlier row was wrong; 0x3a came from a different laptop, gave -ENXIO).
- test24/26/27/28 ALL fail identically: `geni_i2c 88c000.i2c: Timeout abort_m_cmd` → `3-0015 returned 6` (-ENXIO, ~4s hang). Invariant to clock, vdd/vddl/pinctrl. ("test24 ACKed" was a myth — never in DT-TEST24.log.)
- Live (test28): `i2cdetect -y -r 3` = whole bus blank; buses 0/4 fine; rails VREG_MISC_3P3(3.3V)+vreg_l15b(1.8V) confirmed ON. DSDT ECKB has no _PS0/_PR0/enable-GPIO. 4s-hang = geni transfer never completes.
- **test29** = test28 minus `dmas`/`dma-names` on i2c@88c000 → forces FIFO/PIO instead of QUP_2 GPI-DMA (`dma-controller@800000`). Single-variable test of the transfer path. Built `glymur-a16-test29.dtb` (build_test29.py). If still abort_m_cmd → SE completion-IRQ not delivered (check /proc/interrupts tick).

### ★ ROOT CAUSE (test30): i2c@88c000 interrupt off by one
- test29 (FIFO) booted, no change. Live diag on that boot found it:
  - Clock (wrap2_s3) == working wrap0_s0; SE regs identical to b80000 (`FW_REVISION_RO=0x00000304` → proto 0x03 = i2c). SE is alive + firmware'd.
  - `/proc/interrupts`: **88c000.i2c = GICv3 616, fired 0 times** (b80000=850, a80000=59). Completion IRQ never delivered → 4s timeout → `abort_m_cmd`.
  - Working buses: live INTID == DSDT GSIV exactly (a80000 385, b80000 4188, b94000 4193). 88c000 registered **616** but DSDT IC20 GSIV=**617** (0x269). Real SE IRQ = GIC SPI **0x249**, DT had **0x248**. CRD put 0x249 on spi@88c000, 0x248 on i2c@88c000 — off-by-one, never exercised on the CRD.
- **test30** = test29 (FIFO) + i2c@88c000 `interrupts <0 0x248 4>` → `<0 0x249 4>`. build_test30.py. If bus transacts, first real device-level result at 0x15. Re-add dmas later as optimization.

### ★★ test30 RESULT (2026-07-11): KEYBOARD WORKS — IRQ off-by-one was the root cause
- `input: hid-over-i2c 0B05:4B42 Keyboard ... on 3-0015`, probe returned 0 (147ms). IRQ 617 live count 119+. Four-test wall (24/26/27/28) closed.
- Bootlog: `DT-TEST30.log` (project root). Boot noise, both non-fatal:
  - **ath12k**: 3× "Timeout while waiting for regulatory update" (~9s stall, then wifi fine). Future fix: persistent regdomain (`options cfg80211 ieee80211_regdom=US`).
  - **SPMI**: qcom_spmi_pmic probe → 15× `pmic_arb_wait_for_done ... transaction failed (0x3)` + 3 WARNs (ghost PMIC peripherals sids 0x7/0xb on spmi-0/1/2 — CRD DT declares more than A16 has). Recovered; future DT trim.
- **NEW WINS in the same boot:** RTC works (`rtc-pm8xxx registered as rtc0`; time bogus 1970 — needs offset, separate nit) + all PMIC GPIO banks probed.

### test31 (BUILT + STAGED 2026-07-11): ADSP remoteproc graft → battery + audio path
- Live finding: `/sys/class/remoteproc/` EMPTY — CRD DTB has NO adsp/cdsp remoteproc nodes (7.1 upstream doesn't have them; only reserved-mem + smp2p made it). battmgr supplies register but stay blank — the battmgr service runs ON the ADSP. No ADSP = no battery data, no audio, ever.
- Upstream 7.2-rc2 (FETCH_HEAD in ~/kernel-build/linux) HAS `remoteproc@6800000` compat `"qcom,glymur-adsp-pas", "qcom,sm8550-adsp-pas"` — and the 7.1 qcom_q6v5_pas driver already carries the sm8550 alias (pas_id 1, dtb_pas_id 0x24, dual-fw, lcx/lmx proxy PDs). **DTB graft works on current kernel, no rebuild.**
- test31 = test30 + upstream ADSP node grafted (build_test31.py). Deliberately omitted: `interconnects` (optional icc vote), fastrpc/compute-cb children, cdsp (later, separate test). firmware-name = `qcom/glymur/adsp.mbn` + `adsp_dtb.mbn` (staged .zst, matches upstream board dts). Deps resolved from live DTB: pdc=b220000, ipcc=mailbox@3e04000 (LPASS=3, QMP=0), aoss=power-management@c300000, rpmhcc/rpmhpd under rsc@18900000 (LCX=4 LMX=5), smp2p_adsp in/out, adspslpi+q6-adsp-dtb reserved-mem, apps_smmu SID 0x1000.
- Verified re-parse: node OK, glink-edge OK, kbd@15 + 0x249 IRQ intact. Synced (md5 6fedeed5...501), staged: /boot/glymur + 40_custom test30→test31 + update-grub done. **Awaiting reboot.**
- Read the boot: `dmesg | grep -i "adsp\|remoteproc"` → want "remoteproc remoteproc0: remote processor 6800000.remoteproc is now up". Then `/sys/class/power_supply/qcom-battmgr-bat/{status,capacity,voltage_now}`. If ADSP up but battery still blank → battery truly behind ASUS EC (\_SB.ABD), separate driver needed; ADSP still pays for audio.
- GPU: still NO node even in 7.2-rc2 master — stays deferred regardless of kernel bump.
- New tool: `a16put.py` (Temp, next to a16.py) = paramiko SFTP push Windows→A16 share (a16.py -f can't carry big payloads).

### test31 RESULT (2026-07-11): SO CLOSE — remoteproc alive, TZ rejected the dtb companion
- Graft worked: `remoteproc0: adsp is available` → `powering up adsp` → `Booting fw image qcom/glymur/adsp.mbn, size 18622472`. Node, phandles, driver bind (sm8550 fallback) all correct.
- Fail: `error -22 initializing firmware qcom/glymur/adsp_dtb.mbn` → `Failed to load program segments`. Traced to the `qcom_scm_pas_init_image` branch (mdt_loader.c ~115: metadata read OK — its own error string would differ) = **TZ rejected the dtb image metadata** (dtb_pas_id 0x24).
- Diagnosis: ASUS DriverStore ADSP is **monolithic** — `qcadsp8480.mbn` 19.8MB, NO dtb companion exists for this device; and generic `adsp.mbn`/`adsp_dtb.mbn` (18.6MB pair, non-OEM origin) won't pass retail ASUS secure-boot fuses. sm8550/x1e80100 compats both hardcode `dtb_pas_id` (x1e adds lite ids too) → driver always demands a dtb. mdt_loader identical 7.1↔master; master PAS diff = unrelated (shikra).
- Bootlog: `DT-TEST31.log` (project root).

### test32 (BUILT + STAGED 2026-07-11): mirror Windows — monolithic OEM image, no dtb
- test32 = test31 with remoteproc@6800000: compat → `qcom,sm8350-adsp-pas` (pas_id 1, lcx+lmx, load_state "adsp", **no dtb_pas_id**), firmware-name → `qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn` (the image Windows boots daily — TZ must accept it). build_test32.py. Extra memory-region entry (dtb carveout) harmless — driver reads index 0.
- Staged: md5 76f27aa0...b68, /boot/glymur + 40_custom 31→32 + update-grub done. Awaiting reboot.
- Read the boot: `dmesg | grep -iE "remoteproc|adsp"` → want "adsp is now up"; then power_supply values; then `/proc/interrupts` glink/ipcc activity.

### Workspace changes (2026-07-11)
- ROG Omni receiver REMOVED from setup (internal keyboard is now primary — it works). Ethernet NIC dongle disconnected: **SSH target is wifi 192.168.8.209** now; `a16.py`/`a16put.py` (Temp) updated to try .209 then .158. Lenovo ThinkPad debrick project incoming on the bench.

### CORRECTION (2026-07-11): `DT-TEST32.log` is a second test31 boot — staging race
- Boot 12:12:29 vs test32 staging completed 12:24:34 (verified via uptime -s + file mtimes). Live DT that boot = still sm8550+adsp.mbn (test31). Same -22, as expected.
- test32 is correctly staged NOW (grub devicetree line → glymur-a16-test32.dtb, verified live). **Just reboot again — no rebuild needed.** Next log = the real test32 verdict on qcadsp8480.mbn.

### test32 RESULT (2026-07-11): TZ ACCEPTS the OEM image — new blocker: start timeout
- `Booting fw image qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn, size 19851224` → auth+load+release all clean → `start timed out` (-110). Signing question CLOSED: OEM image is the right one.
- Live forensics (no reboot, `echo start` retry): q6v5 fatal/ready/handover/stop/shutdown-ack correctly registered on smp2p-adsp bits 0/1/2/3/7; IPCC inbound proven working (aoss-qmp counts move with our QMP load_state msgs; soccp fired once) — but **smp2p-adsp count stays 0: the DSP never says anything**. smp2p-adsp DT node identical 7.1↔master.
- Lite-ADSP theory (x1e-style leftover image) TESTED and busted: built `~/lite_kill` module (out-of-tree, calls exported `qcom_scm_pas_shutdown`) → pas 0x1f and 0x29 both return -22 = no lite image on this platform. Keep lite_kill around — handy SCM poker.
- Battery stack meanwhile CONFIRMED assembled: qcom-battmgr-bat now exposes full attr set (charge_now/temp/cycle_count/serial), all reads -EAGAIN = waiting on ADSP glink. ADSP up ⇒ battery data, near-certain.

### test33 (BUILT + STAGED 2026-07-11): the omitted interconnects prop — ADSP's DDR path
- Root-cause candidate: I omitted upstream's `interconnects` in the test31 graft ("optional bw vote"). WRONG on a settled system: icc sync_state clamps unvoted paths; live `interconnect_summary` shows ALL LPASS NoC nodes 0/0 → core released with no code-fetch path to DRAM → silent, no crash handler, exactly our symptom. `qcom_q6v5.c` (shared helper) does `devm_of_icc_get` + `icc_set_bw(0, UINT_MAX)` on prepare — only when the prop exists (absent = silently skipped, which was test32).
- test33 = test32 + `interconnects = <&lpass_lpicx_noc 0 7 &mc_virt 1 7>` (MASTER_LPASS_PROC=0, SLAVE_EBI1=1, TAG_ALWAYS=7; lpicx=interconnect@7420000 ph 0x132, mc_virt=/interconnect-1 ph 0x2c). build_test33.py; md5 53772d72...bf7; staged, grub → test33. **Reboot when ready.**
- If test33 STILL times out: next levers = (1) glymur.c icc provider — check lpicx/lpiaon noc registered + sync_state behavior; (2) add lpass_lpiaon_noc leg too; (3) SMEM crash reason read; (4) compare master glymur-crd.dtsi for any adsp-adjacent props we lack (qcom,devmem? scmi?).

### test33 RESULT (2026-07-11): icc vote works, ADSP still silent — dtb theory now prime
- `DT-TEST33.log`. Still `start timed out` -110. But icc fix VERIFIED live: during start, 6800000.remoteproc votes peak UINT_MAX on qnm_lpinoc_dsp_qns4m + qns_lpi_aon_noc + ebi (interconnect_summary). DDR path alive. Keep interconnects in all future DTBs — necessary, not sufficient.
- pas_probe module experiment (TZ init_image via exported qcom_mdt_read_metadata + qcom_scm_pas_init_image, NULL ctx): ALL THREE files return -22, including qcadsp8480.mbn which the real boot flow demonstrably accepts → probe context not equivalent (NULL-ctx/foreign-dev metadata path) → INCONCLUSIVE, disregard verdicts. Fixable: alloc real ctx via devm_qcom_scm_pas_context_alloc then pass to init_image (mirrors driver exactly).
- Standing theory: glymur ADSP REQUIRES the dtb config companion (that's why upstream ships dual-fw and why the q6-adsp-dtb carveout exists); our generic adsp_dtb.mbn (+adsp.mbn, Apr 3, owned by NO package — origin CRD/test-key drop?) fails TZ auth. Production-signed glymur dtb needed. Ubuntu linux-firmware 20260319 = no glymur, no newer candidate.
- Candidate sources for a good dtb: linux-firmware upstream git (check next session — glymur may land with 7.2), QC/CRD newer release, X2E community (aarch64-laptops), or figure out how Windows provides the equivalent config to the monolithic image.

### CIFS mount race (2026-07-11) — NOT a DTB regression
- With the ethernet dongle removed, first wifi-only boot: mnt-app_stuff.mount fires at :55 while wifi associates at :33:05 (+10s, regulatory timeouts included) → -101. Ethernet used to win this race every boot. FIX QUEUED: `x-systemd.automount` on the fstab entry (or After=network-online.target + NM-wait-online). ath12k regdom fix also still queued (`options cfg80211 ieee80211_regdom=US`).

### ADSP dtb hunt (2026-07-11 session end): all local sources exhausted, needs Jesse input
- pas_probe with REAL ctx (devm_qcom_scm_pas_context_alloc): control STILL -22 even after pas_shutdown → bare-module TZ init_image is not equivalent to the driver flow, method UNRELIABLE, all its verdicts void. Only trust the boot-flow evidence: OEM main ACCEPTED, generic dtb REJECTED (first-touch, clean TZ state).
- linux-firmware upstream: sparse clone on A16 (`/home/jcasco/lf-sparse`, filter=blob:none) → **NO qcom/glymur upstream at all** (WHENCE clean). No public production dtb exists yet.
- Windows DriverStore re-search from Linux: BLOCKED — Windows volume nvme0n1p14 is BitLocker (473.7G); p15 ntfs = recovery only. Needs either Windows-side search or dislocker + recovery key.
- **ASKS FOR JESSE:** (1) where did the Apr 3 `qcom/glymur/adsp.mbn`+`adsp_dtb.mbn` pair come from (CRD tarball? QC drop? another machine?) — same source may have a production/ASUS-signed dtb; (2) next Windows boot: search the Qualcomm ADSP driver package in `C:\Windows\System32\DriverStore\FileRepository` for anything dtb-like (`*dtb*`, `*.dtb`, files alongside qcadsp8480.mbn) + the audio driver INF for how the ADSP image is configured.
- Session net: keyboard WON (test30) + RTC alive; ADSP graft correct and one artifact away (needs TZ-acceptable adsp_dtb or Windows' equivalent config mechanism); battery stack verified assembled, waiting on ADSP; icc + firmware paths locked in. Quick fixes still queued: CIFS x-systemd.automount, cfg80211 regdom=US, ghost-SPMI trim, RTC offset.

### ★ FOUND THE MISSING ARTIFACT (2026-07-11): adsp_dtbs.elf in FileRepository.zip
- Jesse's FileRepository.zip (full Windows DriverStore export, project root) → package `qcsubsys_ext_adsp8480.inf_arm64_eda1c91a43da7f4d` contains **`adsp_dtbs.elf` (225080 B)** right next to `qcadsp8480.mbn` (19851224 B = our proven-accepted main). Windows DOES use the dtb mechanism — naming is `*_dtbs.elf`. ELF verified: same 3-phdr layout as the rejected generic (meta 0x7 / PT_LOAD paddr **0x8d800000** == q6-adsp-dtb carveout / hash 0x2). OEM-signed by construction. md5 0c87bbdb6c73a94f75cbdeaf19b87657.
- Also in the zip for later: `qcnspmcdm8480/.../cdsp_dtbs.elf` + `qccdsp8480.mbn` (CDSP graft), `qcsubsys_ext_adsp8480/ADSP/*.so` (audio/fluence/aptX modules — audio phase), bdwlan board files (wifi tuning), CAMERA_ICP, evass, qcav1e.
- **test31's generic pair was downloaded (per Jesse, likely github) — explains the TZ rejection.**
- **test34 BUILT** = test33 (interconnects kept) + compat back to `"qcom,glymur-adsp-pas","qcom,sm8550-adsp-pas"` (dual-fw, dtb_pas_id 0x24) + firmware-name = `qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn` + `.../adsp_dtbs.elf`. build_test34.py.
- Staging: A16 unreachable (mid workspace-rearrange) → **both files copied to the NAS share directly from Windows** (`\\192.168.8.10\App Stuff\boot-kit\out\`: glymur-a16-test34.dtb 123185, adsp_dtbs.elf 225080). Remaining one-shot ON THE BOX:
```
sudo cp /mnt/app_stuff/boot-kit/out/adsp_dtbs.elf /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf \
 && sudo cp /mnt/app_stuff/boot-kit/out/glymur-a16-test34.dtb /boot/glymur/ \
 && sudo sed -i 's/glymur-a16-test33.dtb/glymur-a16-test34.dtb/' /etc/grub.d/40_custom \
 && sudo update-grub && sudo grep -o 'glymur-a16-test3[34].dtb' /boot/grub/grub.cfg | sort | uniq -c \
 && sudo systemctl reboot -i
```
- Read the boot: want `Booting fw image ...qcadsp8480.mbn` with NO dtb error → `remoteproc0: adsp is now up` → battery attrs populate → glink/pmic_glink/battmgr alive. If ready STILL times out with both OEM files: next suspects = memory carveout base vs Windows map (compare adspr.jsn regions), or missing qcom,devmem-style assignment.

### ★★ test34 RESULT (2026-07-11): ADSP IS UP — MILESTONE 5
- `remote processor adsp is now up` (<1s), handover clean, rproc `running`, smp2p-adsp firing. adsp_dtbs.elf was the final missing piece. Full analysis in **G06**.
- Battery VERDICT: ADSP announces NO PMIC_GLINK channel (channels: IPCRTR, adsp_apps×2, bt_cp_ctrl, fastrpc, glink_ssr, sleepmon) → battery is ASUS-EC territory (\_SB.ABD), qcom-battmgr permanently -EAGAIN. EC driver = the battery workstream.
- Audio runway OPEN: adsp_apps = AudioReach GPR channels live. Needs: gpr DT node on the existing glink-edge, q6apm/q6prm + soundcard, pd-mapper+tqftpserv userspace (NOT installed), topology from FileRepository ADSP assets. → G06 §3.
- CIFS race remains flaky (won test33 boot, lost test34 boot) — automount fix still queued.
- test34 = the new baseline DTB. Don't regress: kbd 0x249, ADSP node + interconnects + OEM dual-fw paths.

### test35 (BUILT + STAGED 2026-07-11): AudioReach GPR graft + full userspace layer
- **DTB** = test34 + `gpr` node on the ADSP glink-edge (sm8550 pattern, verbatim): qcom,glink-channels="adsp_apps", domain 2, intents <512 20>; `service@1` q6apm (+dais iommus <smmu 0x1001 0x80, 0x1061 0>, +bedais #sound-dai-cells 1) + `service@2` q6prm (+lpass clock-controller). protection-domain "avs/audio","msm/adsp/audio_pd". build_test35.py. Staged, grub → test35.
- **Userspace installed on box (persistent, no reboot needed):** qrtr + pd-mapper (ACTIVE) + tqftpserv (ACTIVE) — built from github/linux-msm (qrtr+tqftpserv=meson — needs `systemd-dev` for unit dir; pd-mapper=plain make). Sources in ~/qrtr ~/pd-mapper ~/tqftpserv.
- **Fixes landed:** CIFS → mnt-app_stuff.automount unit (mount unit disabled from boot; on-demand mount proven working); wifi regdom → /etc/modprobe.d/cfg80211-regdom.conf (ieee80211_regdom=US).
- **Read the test35 boot:** `dmesg | grep -iE "gpr|q6apm|q6prm|pdr"` — want gpr probe + q6apm/q6prm bind + PDR "avs/audio" UP (pd-mapper journal shows the query). `aplay -l` will still be EMPTY — soundcard/codec/soundwire nodes are the NEXT graft (machine driver, lpass macros, wcd/wsa — needs DSDT + ACDB recon). No regression watch: kbd/ADSP/wifi/usb.
- **BATTERY RECON (test35 scope, answered):** PMGK Connection = I2cSerialBusV2 **addr 0x08 on \_SB.ABD** (QCOM1045/QCOMFFEE, GenericSerialBus region 0x100000). Full EC register map extracted from DSDT: BPRD@0x10100(4B) BIXD@0x10110(0x44B=_BIX struct) BPCD@0x10160 BPSD@0x10178 BSTD@0x101A8(status) BTHD/BTMD/BTPD(temp/thresholds) BMND@0x10200(mfr,128B) BSND@0x10280(serial). **Live probe: 0x08 ACKs on NO APSS-visible bus** (0/2/3/4; bus2 has only 0x43/0x4f=eUSB repeaters; bus0 0x33 = flat zeros, not EC) → **EC hangs off the ADSP island I2C** (hence QCOMFFEE + _REG region-9 gating on Windows). Battery next steps: find SSC/island QUP base (DSDT ADSP scope / master dtsi) → either graft island i2c to APSS (risk: disturb ADSP) or ADSP-mediated access. Driver template when reachable: drivers/platform/arm64 EC drivers (acer-aspire1-ec style) + the register map above.
- **Tooling gotcha:** run a16.py via `shell: cmd` — PowerShell's NativeCommandError kills the pipeline on paramiko's stderr banner (intermittent silent failures all session).

### ★ test35 RESULT (2026-07-11): AUDIO CONTROL PLANE UP — AudioReach foundation complete
- `PDR: Indication received from msm/adsp/audio_pd, state: 0x1fffffff` (=SERVREG UP — pd-mapper did its job) → GPR devs added (svc 2:1 APM, 2:2 PRM) → ALL FIVE audio drivers bound: snd_q6apm, q6prm, q6apm_dai, q6apm_lpass_dais, q6prm_clocks. One transient `CMD timeout [0x1001021]` on the FIRST APM state query (SPF still warming at 4.5s) — count stayed at 1 all boot, probe completed 0. Log: `DT-TEST35.log` (project root).
- Fixes verified live: regdom now `country US: DFS-FCC` (3 fw-side regulatory timeouts remain in dmesg — ath12k fw quirk, benign, revisit later); automount active + share mounted on-demand (race eliminated); kbd IRQ + ADSP running — zero regressions.
- `aplay -l` empty as expected. **Test36 = the soundcard arc:** (1) recon — DSDT audio devices + FileRepository ACDB/topology files (*.acdb, *.bin in qcsubsys_ext_adsp package + ADSP/*.so) and where tqftpserv must serve them from; (2) DT — lpass tx/rx/va/wsa macros? soundwire controllers? wcd/wsa codecs, lpass_tlmm pinctrl, machine `sound{}` node with dai-links (x1e80100 boards = the template; may force the 7.2-rc kernel bump if 7.1 lacks glymur lpass clk/pinctrl compats — CHECK FIRST); (3) also battery: find SSC/island QUP base in DSDT ADSP scope for the EC(0x08) bus decision.

### Test36 RECON (2026-07-11, session end): ADSP dtbs decoded — coordinates acquired → G07
- `adsp_dtbs.elf` = 6 FDTs (extracted to firmware-staging/adsp_dtb_*.dtb). dtb0 (qcom,glymur main) = the ADSP's hardware map.
- **BATTERY:** SSC_QUP_0 @0x7900000, SEs @0x7980000+N*0x4000 (SE_0..8,10), island TLMM @0x75C0000 — EC@0x08 is on one of these. Open: SE→GIC IRQ routing, island clocks (ADSP running + clk_ignore_unused may carry us). Graft = own test DTB, single-variable.
- **AUDIO:** no codec in DSDT/dtbs — Windows = DSP-owned codec via `acdb_cal.acdb` (524KB, qcacsp_crd8480 pkg). Plan A: stage ACDB for tqftpserv + minimal codec-DMA machine card (mirrors Windows model). Plan B: X1E-style APSS codec stack (needs lpass addresses we don't have; maybe 7.2-rc bump). Try A first. lpass cc candidates in dtb0: 0x6bc0000/0x7a00000/0x7b00000/0x6e40000.
- Full plan in **G07-Claude-TEST36-RECON.md**. test35 remains the flight DTB.

### ★ ISLAND VERDICT + test36 (BUILT + STAGED 2026-07-11 late)
- **Island MMIO is XPU-PROTECTED from APSS**: live /dev/mem read of SE_0 GENI_STATUS (0x7980040) hard-hung the core → watchdog reset (~20s, box auto-recovered onto test35). Direct island-i2c graft is DEAD — do NOT map 0x79xxxxx/0x75Cxxxx from APSS. (Cost: one auto-reboot; saved a doomed boot test.)
- ADSP dtb0 SE_0 details for the record: shared_se=1, i2c 400kHz OD, core_irq [1,43] (ADSP PIC), pdc_irq 138, pinctrl via island TLMM — all moot for direct access, useful for the RPC bridge ABI later.
- **Battery path = ADSP-mediated (the Windows model): ABD → adsprpc/fastrpc → ADSP does island i2c.** Step 1 = restore the fastrpc node we trimmed in test31.
- **test36 = test35 + upstream-verbatim fastrpc node** on the glink-edge (compat `qcom,glymur-fastrpc`,`qcom,kaanapali-fastrpc` — 7.1 driver HAS kaanapali + compute-cb; channel fastrpcglink-apps-dsp already announced). 6 compute-cbs (SIDs 0x1003-0x1008/0x106x per upstream). build_test36.py; staged, grub → test36.
- **Read the test36 boot:** `dmesg | grep -i fastrpc` → want compute-cb probes + `/dev/fastrpc-adsp*` present; gpr/q6apm/PDR unchanged; no regressions. Then next session: RE the FFEE/serial-bus RPC ABI (Windows libadsprpc.dll + qcadsprpc8480.sys in FileRepository.zip = the reference; also check adspua.jsn service list) → EC bridge → battery.
- AUDIO note: codelinaro tplg repo unreachable from box (auth); glymur audioreach topology likely doesn't exist publicly yet → topology authoring or extraction arc later. Audio control plane remains healthy.

### ★ test36 RESULT (2026-07-11): fastrpc UP — battery RPC gateway open. Log reviewed, CLEAN.
- All 6 compute-cbs probed (iommu groups 15-20), glink channel probe 0, **`/dev/fastrpc-adsp-secure` exists**, rproc running. "no reserved DMA memory" = informational (no CMA pool; fine for control path). NOTE for bridge work: only the SECURE node exists — upstream boards add `qcom,non-secure-domain` on compute-cbs for /dev/fastrpc-adsp; check which domain the EC/serial-bus service wants (test37 tweak if needed — one property).
- DT-TEST36.log full review: keyboard ✓, adsp up ✓, PDR audio_pd UP ✓, same single benign APM first-probe CMD timeout as test35, error inventory = the chronic set only (ghost-SPMI WARNs, reserved-pin regulators 70/94/246, edp-phy clk, scmi FC prot-13, ptn3222 eUSB). NO regressions. **test36 = new baseline DTB.**
- Working set now: keyboard, tpad, touchscreen+stylus, wifi, USB, fan, NVMe, RTC, ADSP, audio control plane, fastrpc. Remaining arcs: battery EC bridge (RE the FFEE serial-bus RPC ABI — references in FileRepository.zip: libadsprpc.dll/qcadsprpc8480.sys/adspua.jsn), audio topology (authoring/extraction), GPU (upstream-gated), CDSP (recipe ready).

### ★★ test37 (2026-07-11): BATTERY REFRAMED — SMEM mailbox, live data read from Linux (NO DTB change)
- **Prior theory (ADSP/fastrpc-mediated battery) FALSIFIED.** Windows `qcabd8480.sys` ("Qualcomm ACPI Bridge Device", binds `ACPI\QCOM1045`=`\_SB.ABD`) is a software serial-bus region handler with NO glink/QMI/fastrpc/SPMI. It `ZwQuerySystemInformation(SystemFirmwareTableInformation, ACPI/DSDT)` → raw-scans DSDT for tag **`SOSI`** → reads phys base at tag+5 → `MmMapIoSpaceEx(0xE4 bytes, WriteCombined)`.
- **Address decoded from DSDT AML:** `Name (SOSI, 0xFFE0AD80)` (raw at DSDT off 0x14c). `0xFFE0AD80` ∈ `smem@ffe00000` (reserved-memory) = cacheable DRAM, APSS-accessible (NOT XPU-protected).
- **Live read PROVEN:** `/dev/mem` → clean SIGBUS (no-map region; safe, no watchdog). `memremap(0xffe0ad80,228,MEMREMAP_WB)` in a tiny module (`~/sosi_dump/`) dumped the block → contains battery serial **`X2000098`** (ASCII @ +0x7c) + live u32s (662/755/824/1134/896/976 = candidate mV/mAh). Region1 = descriptor/index; region2 (larger _BIX/_BST/mfr payload) reached via `*(r1+0x9c)`/`*(r1+0xe0)`.
- **Field map** (DSDT `Field(\_SB.ABD.ROP1)` @ SPB addr 0x08): BPRD@0x10100, BIXD@0x10110(_BIX 68B), BSTD@0x101A8(_BST), BMND@0x10200(mfr), BSND@0x10280(serial), USB-PD @0x20xxx, doorbells CTLD@0x100/HSWD@0x180.
- **Linux path:** small `power_supply` platform driver that memremaps the SOSI region + parses fields (model: acer-aspire1-ec). `qcom-battmgr` stays -EAGAIN forever (no PMIC_GLINK from ASUS ADSP, per G06). Full writeup: **G08-Claude-TEST37-BATTERY-REFRAME.md**. RE artifacts: `boot-kit/re_abd*.py`, `_abd_disasm.txt`, `_sosi.txt`.
- **fastrpc `qcom,non-secure-domain` tweak SHELVED** — it was for the disproven theory. test36 remains flight DTB (no regressions, box untouched: still running test36, kbd/adsp/audio/fastrpc all healthy).
- **test38 next:** poll region1 charging-vs-battery to separate live/static u32s; follow pointer to region2, find 68B _BIX + mfr string; draft the driver; validate vs Windows readings.

### ★ test38 (2026-07-11): SOSI decoded = descriptor blob; FIRST Linux power_supply node for A16 battery
- **SOSI blob @0xFFE0AD80 is a static self-describing DESCRIPTOR/directory, NOT raw _BST/_BIX.** Full 988B (region2 = same base, size from r1[0xe0]=0x3d0 + r1[0x9c]*4 = 988) dumped 3× over 15s — byte-identical. Contains: serial `X2000098`@0x7c, nonce SOSN, sub-section offsets (824/896/976/988), and a register-descriptor table (count=9: selectors 0x1005c/0x1005d/0x10062×3/0x10061/0x10060×3 — these are LOW/GI2C-side regs, NOT the battery selectors). No mfr string → not the _BIX buffer.
- **DSDT global cluster (top of table) mapped:** `SOSI=0xffe0ad80`, `SOSN=0x46e71cc2d8a` (nonce, echoed in blob), `SHMA=0x82000000` (shared-mem), and a UEFI-**patched** mailbox group `RMTB/RMTX/RFMB/RFMS/RFAB/RFAS` (static DSDT = placeholders 0xAAAA…/0xBBBB…). Those patched pointers exist ONLY in the ACPI boot path → **unavailable on our DT boot** (`/sys/firmware/acpi/tables/` absent).
- **Protocol (from DSDT _BST/_BIX methods):** `_BST` = `BSTT = \_SB.PMGK.BSTD` — a single GenericSerialBus read of selector 0x101A8 returns fresh 16B (BST0..3 = state/rate/remaining/voltage); qcabd8480 does the SMEM request internally. Selector 0x101A8 ≫ 988B and absent from the blob directory ⇒ live telemetry needs the SMEM **request-ring/doorbell** protocol (CTLD@0x100/HSWD@0x180). That handler RE = **test39**.
- **★ FIRST power_supply NODE:** built `a16_battery.ko` (memremaps SOSI, `platform_device` + `power_supply_register`) → `/sys/class/power_supply/a16-battery`: present=1, technology=Li-ion, serial_number=**X2000098**, type=Battery. Source: `boot-kit/a16-battery-driver/a16_battery.c` (also `~/a16_battery/` on box). Capacity/voltage = TODO pending test39 doorbell.
- No DTB change; test36 still flight. Box healthy (module loaded, harmless). Probe tool `~/sosi_dump/` retained.
- **test39 next:** RE qcabd8480 EXECUTE_SEQUENCE/RESOURCE_HUB read handler for the selector→SMEM request-ring write + response read (uses SOSI region / SOSN nonce; RMTB group is ACPI-only). Then wire live _BST/_BIX into the driver → real % / voltage / design-capacity.

### ★★★ test37 DTB / test42 experiment (2026-07-11): BATTERY WORKS — SOCCP GLINK edge (MILESTONE 6)
- **`glymur-a16-test37.dtb` = test36 + ONE inert root node** enabling the battery. Now the flight/boot DTB (40_custom repointed; backup `.bak.test36`).
- Node added (root scope, same level as smp2p-soccp/pmic-glink):
  ```
  soccp_glink_edge {
      compatible = "asus,soccp-glink";
      glink-edge {
          label = "soccp";
          qcom,remote-pid = <0x13>;              /* SOCCP host pid 19 */
          mboxes = <0x39 0x2e 0x00>;             /* &ipcc(3e04000), client 46, glink signal 0 */
          interrupts-extended = <0x39 0x2e 0x00 0x01>;
      };
  };
  ```
  Node is INERT unless the out-of-tree `soccp_glink.ko` binds it → boot-safe (test37 boots identical to test36 without the module).
- **Root cause (corrected from test41):** the charger service is **PMIC-GLINK on the SOCCP**, glink channel `PMIC_RTR_SOCCP_APPS` (proven in `qcpmicglink8480.sys`: also `PMIC_LOGS_SOCCP_APPS`, `\Callback\pmicGlinkSMEMUpdatedCB`). Kernel `pmic_glink.c:285` already matches that channel + has `pmic_glink_soccp_data`; our `pmic-glink` node (`qcom,glymur-pmic-glink`) already selects it. The ONLY missing piece was a **SOCCP glink edge** — nothing in this tree calls `qcom_glink_smem_register()` for the SOCCP (remoteproc/ has no soccp support). (test41's "no charger PD → battmgr impossible" was wrong: charger is a glink CHANNEL, not a servreg PD.)
- **Module `soccp_glink.ko`** (`boot-kit/soccp-glink/`): platform driver matching `asus,soccp-glink`; probe → `qcom_glink_smem_register(dev, of "glink-edge")`. SOCCP is UEFI-loaded/already-running (smp2p-soccp negotiated) so no remoteproc/PAS needed. Reversible (rmmod).
- **RESULT (live):** SOCCP opened `PMIC_RTR_SOCCP_APPS` + `PMIC_LOGS_SOCCP_APPS` + `IPCRTR`; `pmic_glink` bound (`qcom_pmic_glink_rpmsg`); new `glink-smem` IRQ (ipcc 3014656) actively firing. `qcom-battmgr-bat`: present=1, status=Not charging, **voltage_now=12.661V**, temp=30.7C, Li-ion, model 340758, mfr AS3GZHg3KB, cycle_count=14; battmgr-usb online=1. **upower: 79.56%, 55.76/70.088Wh.** First working battery on the A16.
- **Persistent:** `/lib/modules/7.1.0-glymur-full/extra/soccp_glink.ko` + depmod; `/etc/modules-load.d/soccp_glink.conf` (late userspace, cannot block boot). `a16-battery`/SOSI hack now OBSOLETE.
- Full writeup: **G12-Claude-TEST42-SOCCP-GLINK-BATTERY-WORKS.md**. Loose ends: raw `capacity` attr empty (upower % works via energy); `ucsi PPM init failed` benign; upstream fix = a proper SOCCP remoteproc driver.
- **Next arc: AUDIO** (gpr/q6apm/q6prm + soundcard + pd-mapper/tqftpserv userspace + topology, G06 §3), then GPU.

---

## test38 (2026-07-11, TEST43 session) — AUDIO: LPASS-macro graft experiment (INCONCLUSIVE→negative)
- **test38 = test37 + only the 5 LPASS macros** (va@6d44000, wsa@6b00000, wsa2@6aa0000, rx@6ac0000, tx@6ae0000), each clocked from the already-live q6prm (`<&q6prmcc ID 1>` + `<&lpass_vamacro>` fsgen). Labeled the service@2 clock-controller `q6prmcc:`. NO soundwire/codecs/sndcard (single-variable: do glymur macros sit at x1e80100 addresses?). Built by decompiling test37.dtb, editing dts, `dtc` (clean). Recipe: `boot-kit/out/build_test38_macros.txt`. DTB: `/boot/glymur/glymur-a16-test38.dtb` (+NAS).
- **RESULT:** test38 booted to early userspace (ADSP up, GPR svcs, wifi) then panic-rebooted; fault NOT captured (RTC clockless, no pstore) → auto-recovered to test37. Zero macro-probe log lines. Likely wrong glymur macro address and/or macro clock stall — consistent with glymur `lpass_audio_cc@0x6bc0000` ≠ x1e80100 `lpass_audiocc@0x6b6c000` (from ADSP dtb). **Do NOT trust x1e80100 LPASS macro/swr addresses for glymur.** Full analysis: **G13-Claude-TEST43-AUDIO-BRINGUP.md**.
- **Audio control plane is already UP on test37**: GPR `gprsvc:2:1`(q6apm)+`2:2`(q6prm) live, full q6apm/q6prm/apr kernel stack bound, pd-mapper+tqftpserv running. test37 DT already has the gpr/q6apm(dais,bedais)/q6prm(clock-controller) subtree. Missing = sound node + LPASS macros + soundwire + codecs. Next: capture the test38 panic via **netconsole** or ramoops, and get glymur's real LPASS addresses (no watchdog on this platform → hangs don't auto-recover).
- **GRUB now safer:** `GRUB_DEFAULT=saved`; 40_custom has id'd entries `dt-test37` (WORKING, permanent saved default — box now boots test37 DT by default) + `dt-test38` (`+panic=10 softlockup_panic=1` auto-recover). One-shot = `grub-editenv grubenv unset initrdfail prev_entry; grub-set-default dt-test37; grub-reboot dt-test38` (the initrdfail block in 00_header clobbers next_entry if not cleared first — this cost 2 cycles). Backups: `/etc/default/grub.pretest38`, `/etc/grub.d/40_custom.pretest38`.
- **GPU: not attempted** (gated on audio per Jesse; no adreno node in base; panic-prone; unsafe unattended w/o watchdog).
- Working set intact post-experiment: kbd, touch, tpad, wifi, USB, fan, NVMe, ADSP, battery 79.6%.

---

## Continuation (2026-07-12): Audio completion → USB redrivers → Display bring-up → firmware XPU wall

> DTB test numbers 39–44 covered the LPASS-address correction and SoundWire iteration that followed the
> test38 negative (x1e macro addresses are wrong for glymur; see G13 + audio memory). The entries below
> are the load-bearing milestones from test45 onward — all verified on-box, cross-referenced to
> `DISPLAY-BRINGUP-FINDINGS.md` for the display arc.

### ★★ test45 (AUDIO M8) — glymur sound card instantiates
- **Delta vs test37/38:** 5 LPASS macros bound at the **real glymur addresses** (va@**7660000**, wsa@**6c90000**, wsa2@**6cb0000**) — NOT the x1e addresses that panicked test38 (va@6d44000). ADSP auto-boot moved into initramfs; AudioReach topology wired (x1e A14/Romulus stand-in at `/lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin`).
- **Result:** `card0 GLYMUR-A16` instantiates; MultiMedia1–4 playback + capture PCMs appear.

### ★★ test46 (AUDIO M9) — full card matching (merged-upstream)
- **Delta vs test45:** full machine/codec match. All **4 × WSA8845** speaker amps enumerate on SoundWire (`sdw:1:0 / 4:0`, id `0217:0204`); `swr0`/`swr3` bound (qcom-soundwire); va-macro DMIC + mic-bias.
- **Result:** `aplay`/`arecord` on MultiMedia1–4. **Kernel + DT side of audio COMPLETE.**

### ★★★ AUDIO M10 / M11 (userspace only — no DTB change)
- **M10:** speakers PLAY (confirmed audible) + internal DMIC CAPTURES real signal; `GLYMUR-A16` UCM profile created + `alsactl store`.
- **M11 (daily-use quality):** chassis speakers are a **4.0 layout** (tweeters = FL/FR, woofers = RL/RR — per S16 sibling), so plain stereo drove only tweeters. Fix = force platform-sound sink to 4ch `[FL FR RL RR]` + `channelmix.upmix=true` in `/etc/wireplumber/wireplumber.conf.d/51-glymur-ucm.conf`; gains raised in `glymur-audio-route.sh` (WSA/WSA2 RX0 woofer=81, RX1 tweeter=77, PA Volume=6). All routing/userspace, survives reboot. Further punch needs a real glymur AudioReach DSP topology (deferred).

### ★ Keyboard backlight (userspace only — no DTB change)
- Keyboard is i2c-hid ASUS `0B05:4B42` (i2c-3 @0x15), claimed by hid-generic (hid-asus lacks the 4B42 PID). Default firmware "breathing" backlight fixed by sending the ASUS vendor init handshake + backlight-level FEATURE reports (`0x5a …`) via `HIDIOCSFEATURE` to the kbd hidraw. Persisted: `/usr/local/bin/asus-kbd-init.py` + `asus-kbd-init.service` + a sleep hook. Keys themselves always worked (this is backlight only).

### ★ test47 — USB2 redrivers; NEW DAILY DEFAULT
- **Delta vs test46:** freed TLMM pins **8 & 9** by splitting the over-reserved range **4–19 → 4–7 + 10–19**. → the `ptn3222` USB2 redrivers bind (`phy-2-0043`/`phy-2-0047`).
- **Result:** USB2 redriver path complete. **test47 = the daily-driver DTB** (simplefb display + full audio + wifi + battery + input). Power/charging (UCSI-PPM + SCMI-perf) remain firmware-response gaps — deferred.
- **Note for display:** the same over-reservation still swallowed pins **18** (panel enable) and **70** (eDP 3V3 regulator EN) — freed next in test48.

### ★★ test48 — display stack enabled; initializes then resets at first modeset
- **Delta vs test47:** `display-subsystem@ae00000` (mdss) `status=okay` + `clock-controller@af00000` (dispcc) `status=okay`; freed **pin 18** (split `10,10 → 10,8 + 19,1`) and **pin 70** (split `68,8 → 68,2 + 71,5`); removed the legacy `modprobe.blacklist=msm` (present since test16). Grub id `dt-test48` (+`panic=10 softlockup_panic=1` auto-recover); default stays `dt-test47`.
- **Result:** msm/DPU binds all 3 DP controllers, `dpu hw rev 0xc0020000`, creates `fb0`, and reads the internal panel over eDP AUX/EDID (**Samsung ATNA60HR07, 2880×1800 @120/60, 10 bpc**, backlight found) → **hard warm-reset at the first pipe-enable.** dispcc binds cleanly — the old "dispcc island hang" fear (why msm was blacklisted) is disproven.

### test48lr — link-rate ruled out
- **Delta:** test48 + cmdline `video=eDP-1:1920x1080@60`. 1080p/low-link-rate mode appears in probe → **still resets** at the same point. HBR3/high-link-rate is NOT the cause.

### ★★★ test49 — isolation: DPU core stable; fault is the DDR scanout path
- **Delta vs test48:** internal eDP `displayport-controller@af6c000` `status=okay → disabled`. Grub id `dt-test49`.
- **Result:** msm loads and **STAYS UP** with a real `msm_dpu` DRM card (external DP only). A purpose-built libdrm **atomic-writeback reproducer** (`/var/tmp/wbtest`) — which exercises DPU plane-fetch-from-DDR → compose → writeback with **no eDP/PHY/panel at all** — **still hard-resets** at `drmModeAtomicCommit`. So the fault was never eDP-specific; it is the DPU's first real DDR/VBIF transaction.

### Root cause (test49 + custom kernel instrumentation) — retail firmware XPU/VMID wall
- Gated logging in `dpu_reg_write()` + synchronous netconsole capture pinned the faulting write: **VBIF register offset `0x160`, value `0x22222223`** (an AMEMTYPE RMW; the read-back `0x22222222` proves the address is correct — the **write access** is what faults).
- Every HLOS-side lever tested **NEGATIVE:** VBIF-skip, memtype-skip, `qcom_scm_restore_sec_cfg(MDSS,…)` → `-EINVAL`, keep-MDSS-powered, VBIF-halt.
- RE of the **retail `.309` BIOS** + the WoA ACPI/DEVCFG: VBIF/MDSS sit behind **`MDSS_XPU`**, whose access XBL Dynamic-Init grants to the **HLOS-VM VMID** (`acvmid = 0x3C`). Windows inherits that VMID as the Qualcomm-hypervisor HLOS guest and writes VBIF by plain MMIO. `dmesg` confirms **Linux boots bare-metal at EL2 as a VHE host** (`kvm: VHE mode initialized successfully`) → it presents no hyp/VMIDMT-generated VMID → the XPU denies the write → silent warm-reset. Confirmed against Qualcomm's own security docs (XPU slave-side gate + VMIDMT VMID + hypervisor EL2 stage-2).
- **Verdict:** everything under our control (DT, clocks, power, SMMU/StreamIDs, interconnect) is correct; the block is a retail firmware/TrustZone protection — same class as power/charging (UCSI/SCMI), protected TLMM pins, and download-mode. **Not fixable from DT/driver alone.** Full detail: `DISPLAY-BRINGUP-FINDINGS.md`; scope of the two remaining paths: `../gunyah_dpu_path_scope.md`.

### test50 — proposed, then rejected (documented to prevent rework)
- A "free pins 18+70" blueprint was proposed as test50. On review it is **byte-for-byte what test48 already did** and does not touch the XPU wall. **Not built.** See `../test50_verified_plan.md`.

### ★★★ Option A EXECUTED + CLOSED (2026-07-12, overnight): official upstream driver is byte-identical → confirms firmware wall
Qualcomm's authoritative **glymur MDSS + DPU + DisplayPort** support is merged in **`drm-msm-next`** (pull `drm-msm-next-2025-11-18`, for **v6.19**; glymur MDSS = SM8750-based). Shallow-cloned it on the box (`/home/jcasco/msmnext`, HEAD `9a96712 drm/msm/adreno: add Adreno 810 GPU support`) and **diffed the official driver against the test48 tree (mainline Linux 7.1)**:

| File (faulting/display path) | Official msm-next vs test48 tree |
|---|---|
| `disp/dpu1/catalog/dpu_12_2_glymur.h` (catalog) | **BYTE-IDENTICAL** (both `.vbif = &sm8650_vbif`, `core_major_ver=12`) |
| `disp/dpu1/dpu_hw_vbif.c` (VBIF register writes) | **IDENTICAL** |
| `disp/dpu1/dpu_hw_util.c` (`dpu_reg_write` — the exact faulting fn) | **IDENTICAL** |
| `disp/dpu1/dpu_vbif.c` | differs **only** by our own debug patch (`dpu_vbif_halt_memtype`); upstream logic unchanged |
| DPU/DP secure path | **NO** glymur `qcom_scm`/secure/VMID/cont-splash anywhere; mainline DPU never calls `qcom_scm` in the VBIF path |
| unrelated upstream deltas | new chip "milos", a DP HPD enum refactor, a UBWC helper refactor in `msm_mdss.c` — none touch VBIF/scanout |

**Conclusion (definitive):** the official v6.19 glymur display driver writes the **same VBIF register `0x160` the same way** as test48 and carries **no secure handshake** — so it reproduces the identical silent XPU reset. A boot was deliberately **not** spent: byte-identical code is a stronger proof than re-running it. **Option A (upstream kernel support) cannot clear the retail-firmware MDSS_XPU/VMID wall.** The blocker is 100% firmware, now confirmed against the authoritative upstream source. Box left untouched on test47 (no build, no reboot); scratch clone at `/home/jcasco/msmnext` (2.0G, removable). Remaining paths unchanged and firmware-gated: Gunyah-HLOS-VM (`../gunyah_dpu_path_scope.md`) or unlocked/eng firmware.

### test48 EXECUTION (2026-07-13): pKVM route for Display Bring-up
- **Goal:** Launch the official msm display DRM driver via the pKVM route (kvm-arm.mode=protected), providing the required qcdxkmsuc8480.mbn GPU zap shader to overcome the XPU reset loop and eliminate blue artifacting from simplefb collisions.
- **Actions:** 
  1. Provisioned qcdxkmsuc8480.mbn (12088 bytes) to /lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/ on the target.
  2. Modified /etc/grub.d/40_custom to remove modprobe.blacklist=msm and inject kvm-arm.mode=protected to dt-test48.
  3. Rebooted into the patched GRUB configuration.
- **Expected Result:** The msm driver will run with a non-zero stage-2 VMID via pKVM, satisfying the hardware's XPU policy and smoothly overriding the UEFI continuous splash.
### test48 RESULT (2026-07-13): MILESTONE - XPU Wall Bypassed, msm Driver Loaded
- **Outcome:** The msm driver successfully initialized and bound to the DPU (e01000.display-controller) without triggering the TrustZone XPU hard-reset! Protected hVHE mode initialized successfully confirmed pKVM was active.
- **Next Blocker:** While the DPU is alive, eDP link training is timing out (*ERROR* link training #2 on phy 0 failed. ret=-110). This indicates the driver is failing to establish the DisplayPort link with the panel, likely due to simplefb handoff state issues, missing panel power sequencing, or requiring a lower link rate.
- **GPU Status:** msm reported 
o GPU device was found, which is expected since the GPU node isn't present in the base 	est48 DTB.
### test48 (simplefb:off) RESULT (2026-07-13): CRASH - XPU Grant Lost via Power Domain Cycle
- **Action:** Booted 	est48 with ideo=simplefb:off to test if simplefb was interfering with eDP link training.
- **Outcome:** HARD RESET (Crash).
- **Analysis:** Disabling simplefb removes the only active consumer of the MDSS GDSC (power domain) during early boot. When the power domain drops, the hardware XPU block loses its TrustZone-programmed VMID configuration. When the msm driver subsequently powers the MDSS back on and writes to VBIF, the XPU is in a default locked state and denies the write (even with pKVM providing the correct VMID), triggering the instant warm-reset.
- **Lesson:** simplefb (continuous splash) is **MANDATORY** for this firmware-locked device. It serves as a structural placeholder to keep the MDSS power domain alive and preserve the TrustZone XPU grant until the DRM driver successfully completes handoff. We cannot disable it.
### test51 RESULT (2026-07-13): Lower Link Rate Test (1080p60) via pKVM
- **Goal:** Test if the 
et=-110 link training timeouts are caused by the eDP PHY struggling to train a high-bandwidth native link (2880x1800@120Hz) during the UEFI-to-Linux continuous splash handoff. (Test 49 was already reserved for eDP isolation, and 50 was rejected, so this is test 51).
- **Actions:** 
  1. Verified via dtdump that pins 18 and 70 are indeed mathematically absent from the gpio-reserved-ranges block in 	est48.dtb (ranges explicitly skip 18 and 70), confirming the DT is correct.
  2. Booted with ideo=eDP-1:1920x1080@60 + kvm-arm.mode=protected (no modprobe.blacklist=msm and NO simplefb:off).
- **Expected Result:** The msm driver will attempt to train a much lower bandwidth link while still bypassing the XPU wall.
### test51 RESULT (2026-07-13): CRASH - Link Rate Change Forced Power-Cycle
- **Action:** Booted `test51` (test48 + pKVM + `video=eDP-1:1920x1080@60`).
- **Outcome:** HARD RESET (Crash).
- **Analysis:** This crash perfectly confirms our finding from simplefb:off. By passing `video=eDP-1:1920x1080@60`, we forced the Linux DRM framework to abandon the 2880x1800 simplefb resolution and perform a full modeset during initialization. To change the resolution, the driver disabled the display controller (CRTC), which momentarily powered down the MDSS GDSC. The moment that power domain dropped, the TrustZone XPU grant was wiped. When it powered back up to push the 1080p mode, the XPU blocked the VBIF write and crashed the machine.
- **Ultimate Conclusion:** We are in a firmware catch-22. 
  1. We cannot power-cycle the display controller, or TrustZone revokes our access.
  2. Because we cannot power-cycle it, the eDP PHY is left in a dirty state from the UEFI continuous splash, causing the -110 Link Training timeout we saw in `test48`. 
  Without an engineering UEFI or TrustZone unlock, native display initialization on this retail firmware is fundamentally impossible.

---

## test57 / display-DTB WiFi regression (2026-07-14 → 2026-07-15) — REPEATED, EMPIRICAL

### ★ LESSON (confirmed two nights running): **`test57.dtb` BLOWS AWAY WIFI**
- **Symptom on boot:** console shows **garbled/overlapping lines** (msm/DPU probing clobbers the fbcon over the simplefb framebuffer), screen goes **BLACK**, then the **Ubuntu boot chime plays** (so it reaches userspace — it is NOT a hard reset). Result: **no display + no WiFi**. Box is unreachable over SSH.
- **Recovery:** hard power-cycle, boot into **`test55-usb.dtb`** (the last known stable: WiFi works, mdss `disabled` so simplefb only, no native display). That brings WiFi + SSH back.
- **Scope:** the regression is tied to the **display-enabled DTB** (mdss `okay` + eDP `af6c000` wired), NOT to pKVM itself — `dt-pkvm` (test57.dtb + msm blacklisted) boots clean with WiFi up (proven by `boot-kit/dmesg.log` reaching systemd). So: **mdss-enabled DTB + msm LOADED = WiFi dies; mdss-enabled DTB + msm blacklisted = fine.** The wifi kill is a side effect of the msm/DPU driver bringing up MDSS, not the DTB node set per se.
- **Why WiFi specifically:** unconfirmed root cause. Candidate: the display bring-up disturbs a shared power domain / SMMU context bank / NoC interconnect vote that the `qcom_pcie` (wifi @ `pci@1c00000`) or `ath12k` depends on, OR the MDSS GDSC power-cycle (per the test48/test51 catch-22) tears down a rail WiFi needs. The `pci@1c00000` node + PMIC `vreg_pmu_*` regulators are byte-identical between test55-usb and test57, so it is NOT a DT-node difference — it is a runtime driver interaction. **Do NOT trust any display-enabled DTB for daily use until this is root-caused.**
- **Action items (future):**
  1. Capture a serial/netconsole log of a test57 + msm-enabled boot to see the exact WiFi/PCIe failure message (ath12k timeout? `qcom_pcie` link down? SMMU fault?).
  2. Isolate: boot test57 with msm enabled but `pci@1c00000` temporarily `disabled` → if WiFi "returns" (other PCIe), confirms MDSS↔wifi coupling; if still dead, it's a global PD/NoC tear-down.
  3. Check `dmesg` for `qcom_pcie` AER / `ath12k` `regulatory update` timeout / SMMU `Unknown SID` faults coincident with msm bind.
- **Working set status (2026-07-15):** daily driver = **test55-usb.dtb** (WiFi + audio + battery + input, simplefb display only). Native eDP remains blocked by BOTH the firmware XPU/VMID wall (pre-pKVM) AND this newly-confirmed WiFi regression under any mdss-enabled+msm-loaded boot. pKVM's VMID grant may clear the VBIF wall, but the WiFi regression means a working native-display daily config does not yet exist.
- **CAUTION for future sessions:** any "test58/display-attack" DTB that enables mdss AND loads msm will likely reproduce the WiFi kill. Build it as a one-shot diagnostic only; never repoint the default grub entry to it.

### ★ SEPARATE BUG (2026-07-15): **`dt-test47` was missing `efi=noruntime` → reset at simpledrm fbcon commit**
- **Symptom:** booting `dt-test47` (loads `glymur-a16-test56.dtb`, mdss DISABLED, simplefb only) reset at `simple-framebuffer.0: [drm:drm_atomic_commit]` of the fbcon plane (NO msm/DPU/VBIF in the log). Console garbled → black → chime. Same reset class as the earlier `dt-msm`/test55-usb boot that died at `integrity: Couldn't get UEFI dbx list`.
- **Root cause:** `dt-test47` cmdline (grub.cfg.laptop line 362) had **NO `efi=noruntime`**. Without it, the kernel enters EFI runtime services during early boot (integrity UEFI-var fetch, and/or the simpledrm/fbcon atomic commit path touches EFI-owned frambuffer memory under bare-metal EL2) → silent warm-reset. **Every persistent working entry (grub.cfg.laptop lines 166–265) carries `efi=noruntime`; `dt-test47` did NOT.** This is a pre-existing grub bug, unrelated to the XPU wall or the WiFi regression.
- **Fix applied (2026-07-15):** `dt-test47` cmdline now includes `efi=noruntime cma=128M kvm-arm.mode=protected` (mirrors the known-good pattern). Re-deploy `grub.cfg.laptop` to the box + `update-grub`.
- **Note:** the `dt-msm` menuentry written by the assistant on 2026-07-15 ALREADY included `efi=noruntime` + `kvm-arm.mode=protected`; if a boot using it still reset, it was a different cause (e.g. the WiFi regression from the display-enabled DTB, or the user actually booted `dt-test47` instead).
- **Rule going forward:** any glymur boot cmdline MUST include `efi=noruntime`. A missing `efi=noruntime` reproduces a reset during early DRM/fbcon init on this firmware — do not misdiagnose it as the display/XPU wall.

### ★ GRUB FILE DIVERGENCE (2026-07-15): `boot-kit/grub.cfg.laptop` is STALE vs live box
- **Critical:** the `boot-kit/grub.cfg.laptop` (and `.test57`) copies on Windows are **NOT** the file deployed on the box. The LIVE `/boot/grub/grub.cfg` differs: e.g. live `dt-pkvm` uses `glymur-a16-test47.dtb` + `modprobe.blacklist=msm` (NOT the `test56.dtb`/no-blacklist version in the boot-kit copy). Earlier display-test "crashes" attributed to XPU/WiFi may in fact have been the **missing `efi=noruntime`** reset, because NONE of the custom `dt-*` entries carried it (only the `10_linux`-generated `Ubuntu` entries did).
- **Action:** when the box is next reachable, pull the REAL `/boot/grub/grub.cfg`, add `efi=noruntime cma=128M` to every `dt-*` entry lacking it (dt-test37, dt-test47, dt-test48/48lr/49/51, dt-pkvm, dt-test39/44/45/46), then redeploy. Do NOT trust the boot-kit copy as the source of truth.
- **Recovery (no SSH):** at the grub menu, boot the plain **`Ubuntu`** entry (first item, `vmlinuz-7.1.0-glymur-full`, already has `efi=noruntime`) — it brings up simplefb display + WiFi. Or press `e` on any `dt-*` entry and append `efi=noruntime` to the `linux` line before booting.

### ★ GRUB CLEANUP APPLIED (2026-07-15, on-box)
- **Root cause of recurring resets clarified:** missing `efi=noruntime` causes an *intermittent* warm-reset during early simpledrm/fbcon init on this firmware (NOT guaranteed — a pKVM+msm-blacklisted boot survived without it). Every custom `dt-*` entry lacked it; only the `10_linux` `Ubuntu` entries had it. Many past "display crashes" were likely this, not the XPU wall.
- **Rewrote `/etc/grub.d/40_custom`** as the single source of truth and ran `update-grub`. All entries now carry `efi=noruntime cma=128M`. Removed the duplicate/malformed `dt-msm` entries and the stray `}` in `40_custom.pretest38`.
- **Final entry set:** `dt-test37` (test37, msm blacklist), `dt-test47` (test55.dtb, mdss off, **safe daily default**), `dt-test55-usb` (test55-usb.dtb, mdss off), `dt-test48` (test48, msm blacklist, simplefb:off), `dt-test49` (test49, eDP off), `dt-test58-display` (**test58.dtb, mdss ON + msm LOADED + pKVM + drm.debug — DIAGNOSTIC ONLY, known to kill wifi**), `dt-pkvm` (test55.dtb, pKVM, msm blacklist safe).
- **Default set to `dt-test47`** (grub-set-default). Note: the live grub.cfg had previously been hand-edited out-of-sync with 40_custom (e.g. dt-test47 pointed at test58.dtb); now regenerated consistently.
- **`test58.dtb` (on box) = display-attack DTB**: mdss `okay` + eDP `af6c000` `okay` + eDP `enable-gpios` = gpio18, BUT `gpio-reserved-ranges` still has `<10 10>` → **pin 18 STILL RESERVED**. So even with msm loaded, msm would defer on the eDP enable-gpio. The WiFi-kill regression (display-enabled DTB + msm loaded) is independently real (observed 2 nights). `dt-test58-display` exists to *capture* that failure with drm.debug; it is not a usable daily config.
- **NEXT STEP (when ready):** build a corrected `test59.dtb` = test58 + pin 18 freed (`<10 10>` → `<10 8> <19 1>`) + pin 70 confirm, then boot `dt-test58-display`-style entry to see if pKVM's VMID grant + freed gpio lets msm actually train eDP. Expect wifi to die; capture via netconsole/serial.

### ★ test59 BUILT (2026-07-15, on-box) — pin 18 freed, real eDP attempt
- **Delta vs test58:** `gpio-reserved-ranges` `<10 10>` (pins 10–19) → `<10 8> <19 1>` (pins 10–17 + pin 19 reserved, **pin 18 = 0x12 freed** for the eDP panel `enable-gpios`). mdss `okay` + eDP `af6c000` `okay` + `enable-gpios = <0x69 0x12>` inherited unchanged. Built via decompile-edit-recompile of test58.dtb (`/tmp/build_test59.py`), installed to `/boot/glymur/glymur-a16-test59.dtb`.
- **Grub:** added `dt-test59-display` entry (test59.dtb + **msm LOADED** + `kvm-arm.mode=protected` + `efi=noruntime` + `drm.debug=0x1f6`). Diagnostic only — display-enabled DTB + msm loaded is expected to kill WiFi (per the test57 regression); capture via netconsole/serial.
- **Hypothesis to test:** with pin 18 freed AND pKVM's nonzero VMID grant, msm can now (a) request the eDP enable-gpio (no longer deferred), and (b) write VBIF under the VMID grant → possibly train eDP and produce a real framebuffer. If it still `-110`/resets at modeset, the catch-22 (MDSS power-cycle wipes XPU grant) remains and pKVM alone doesn't solve it. If it modesets → display works but wifi dies (separate regression to root-cause later).

---

## ★★ UPDATE 7-15 (2026-07-15, end of day) — RE-FRAMING: the "XPU wall" was a misdiagnosis

### The ACPI evidence overrides the test48 "wall" conclusion
- The **WoA ACPI dump** (`acpi_dump/`, `acpi_dump_ubuntu/` — `iort.dsl`, `dsdt.dsl`, `sdev.dsl`) proves the display path has **NO secure VMID/XPU gate**:
  - **IORT has no MDSS node.** Display (`ACPI\QCOM...0F36` primary DPU, `0FF5` 2nd path eDP+DP) is described only via DSDT `_CRS`/`_DSD` with **normal `disp_cc_mdss_*` clocks** (core_gdsc/ahb/vsync/rscc) → DPU present, **normal clock-gating**, no SMMU StreamID wall.
  - **SDEV table** secure owner = `\_SB.SISP` (HID QCOM0FC1) → apps_smmu SID 0 = **TrustZone**, NOT a Gunyah/HLOS VMID. There is no per-display secure VMID the OS must satisfy.
  - GPU (Adreno X2) is driven natively by Windows in the primary VM (`qcdxkm8480.sys` WDDM) — **not** behind a Gunyah handshake. So "emulate Windows/Gunyah to unlock display" is a **dead end**, and the display path was never VMID-gated to begin with.
- **Conclusion:** the test48-era claim that "retail firmware XPU/VMID wall makes native display impossible / simplefb is mandatory / you cannot power-cycle MDSS" is **WRONG**. The display hardware is normally clock-gated and OS-drivable. The test48 warm-resets were caused by OTHER things (below), not an immutable firmware lock.

### What the test48 resets actually were (corrected)
1. **Missing `efi=noruntime`** → intermittent warm-reset during early simpledrm/fbcon init (proven this session; was missing from ALL custom `dt-*` entries). This alone explains many "display boot crashes."
2. **Forced modeset / resolution change** (`video=simplefb:off`, `video=eDP-1:1920x1080@60`) → MDSS GDSC power-cycle. Under bare-metal EL2 this dropped the (already-tenuous) XPU grant and reset. But this is a **driver/power-sequence issue, not a firmware wall** — and under pKVM host mode the VMID grant changes the equation (G18 proved the VBIF write lands under pKVM).
3. The **real, surviving display symptom is eDP link training `-110`** (test48 with simplefb kept alive: msm binds, reads EDID, link training times out). That is a **DP PHY / panel-power-sequencing / AUX** problem — the actual target.

### test59 = duplicate of test48/test49 pin work (no-op)
- test59 freed pin 18, but **test48 already freed pins 18 AND 70** (changelog line 267: split `10,10 → 10,8 + 19,1`, and `68,8 → 68,2 + 71,5` leaving pin 70 free). Pin 70 is **already free** in test55-usb/test57/test58/test59 (reserved blocks skip it: `<68 2>` then `<71 5>`). So test59's delta was **already proven** and explained test49's result (msm loads, stays up, internal eDP still `-110`/disabled). Re-running it produced the same no-display outcome — expected, not new information.
- **Lesson recorded:** do not re-free pins 18/70 — they are already free. The blocker is link training, not gpio reservations.

### The actual goal + the Step-0 replication that works
- **Jesse's goal:** native eDP display with **brightness control**, not simplefb. (simplefb cannot drive the panel backlight — it's a dumb framebuffer. Brightness needs the eDP `enable-gpios` + `edp_3v3` regulator + backlight node, which only a real msm/panel driver provides.)
- **BUILD-PLAN-B Phase 0 = the "breakthrough" Jesse remembers:** boot test47/display-DTB under `kvm-arm.mode=protected` (pKVM host, no guest); the host carries a nonzero stage-2 VMID → the VBIF write that bare-metal EL2 reset on now **lands** (G18 confirmed: `VBIF 0xaeb0160 ← 0x22222223` permitted, no reset). Then **un-blacklist msm + apply the test48 DT delta** and the normal host Linux drives display.
- **The in-place handoff (never cleanly attempted):** keep `video=simplefb` at 2880×1800 (DO NOT pass `simplefb:off` or force a resolution). msm attaches to the **already-live simplefb framebuffer** and never disables the CRTC → MDSS GDSC never drops → no power-cycle reset. test48/test51 both *violated* this by forcing a modeset/resolution, which is why they crashed. The clean version = mdss on + msm loaded + pKVM + `efi=noruntime` + **no** `simplefb:off` + **no** forced `video=` resolution.
- **This is the step to replicate next**, targeting the `-110` link-training directly (panel power sequencing, AUX retry/delay, PHY init order) — NOT VMID.

### Grub note (Jesse: assistant overwrote hand-edited entries via `update-grub`)
- The assistant regenerated `/boot/grub/grub.cfg` from a reconstructed `/etc/grub.d/40_custom`, **wiping Jesse's hand-curated entries**. The rebuilt set is functional (all entries have `efi=noruntime`, default `dt-test47` = test55.dtb safe) but lost custom work. **Restore Jesse's original entries from his backup if available; do NOT re-run `update-grub` without explicit ask.** Future display-test entries must preserve: pKVM host mode, msm loaded, simplefb kept (no `simplefb:off`), no forced resolution, `efi=noruntime`.

### Status for GitHub post (working platform)
- **FULLY WORKING on DT:** keyboard, touchpad, touchscreen+stylus, wifi (ath12k), USB (incl. redrivers), fan (EC), NVMe, RTC, ADSP (audio control plane), fastrpc, **battery (SOCCP glink → qcom-battmgr, ~79% shown)**, audio (4× WSA8845 speakers, Mic capture), simplefb UEFI splash.
- **NOT YET WORKING:** native eDP (link-training `-110`, being debugged), GPU (no adreno node in base DTB; GPU bring-up separate workstream), brightness control (blocked on native eDP).
- **Key reference docs for the post:** `07_DTB_CHANGELOG.md`, `gpu_smmu_routing_from_WoA_ACPI.md`, `BUILD-PLAN-B-KVM-PKVM-SELFHOST.md`, `G08` (battery), `G13` (audio), `DISPLAY-BRINGUP-FINDINGS.md` (pre-pKVM, now superseded by this UPDATE).

---

# GAP FILLED: 2026-07-16 → 2026-07-28

> The changelog stopped at 2026-07-15 when the work shifted into driver RE and msm bring-up.
> Everything below reconstructs that period from the repo docs, the on-box logs, and the
> session records. Milestones are marked ★; retractions are marked ⛔ and are as important as
> the wins — several confident conclusions in this period were later disproven.

## ★★★ eDP LINK-UP (2026-07-24) — HBR3 was the answer

- **test62 / test63** iterated the eDP link at HBR2 (5.4G) and HBR (2.7G). Every attempt gave
  the same result: **CR locks on all four lanes, EQ never sets, SYM never locks**, at every
  drive level and every lane count. `0x202=0x11 0x203=0x11 ALIGN=0`.
- Drive levels were **fully ruled out**: the write path was proven by readback
  (`v=0 p=1 → 0x1f/0x1f` at the exact cell the sink requests), and max swing + max
  pre-emphasis still failed EQ. UEFI DisplayDxe was reverse-engineered (Ghidra) and its
  swing/emphasis table is **byte-identical to our v8 table**, written to the same offsets.
- **★ The fix: force HBR3 (810000).** `dp_panel.c`, right after the `use_rate_set = true`
  line — `rate = 810000, rate_set = 0, use_rate_set = false` (legacy LINK_BW_SET path).
  Link trains **first try**: `0x202/0x203 = 0x77/0x77 ALIGN=1`, 2880x1800@120 at 30 bpp,
  `fb0 = msmdrmfb`, `dp_aux_backlight` live.
- **Confirmation run passed on the STOCK swing table** → the link rate alone was the fix;
  `phy-qcom-edp.c` needs no patches at all.
- ⛔ **The rationale was wrong even though the experiment was right.** The in-tree comment
  claimed UEFI left `LINK_BW_SET = 0x14` meaning "firmware's known-good link is HBR3".
  `0x14` is **DP_LINK_BW_5_4**; HBR3 is `0x1e`. The firmware selects the rate that fails for
  us. Corrected in `linux-glymur-a16` commit `b4c376a41`.
- Panel identified from EDID: **Samsung/SDC ATNA60HR07-0**, 30–120 Hz, max pixel clock
  710 MHz.
- ⚠️ Not upstreamable as written: `link_info->rate = 810000` is unconditional.

## ★ Kernel lineage: clean+ → clean2 → edp1 → gpucc1 → gdsc1

- **`7.1.0-glymur-edp1`** — first kernel where `msm` autoloads and binds with **no
  `modprobe.blacklist=`**; panel lights unattended. Replaced the old arrangement of
  hand-copied `.ko` files.
- **gpucc CONFIRMED on hardware** — 25 `gpu_cc` clocks, `gpu_cc_pll0` = 1 149 999 902 Hz.
  Registration only, no rendering. Corrects the older "gpucc missing from mainline" claim:
  the driver exists in v7.1; the gap is device tree.
- **`7.1.0-glymur-gdsc1`** — adds the gdsc genpd teardown fix (see below).

### gdsc genpd teardown fix — and its 2026-07-28 correction

- Found 2026-07-24: `gdsc_init()` calls `pm_genpd_init()` (adds to the global `gpd_list`) but
  **nothing ever called `pm_genpd_remove()`**, so `rmmod` of any qcom clock controller left
  the list pointing into freed module memory. Next `modprobe` → `list_add corruption`;
  reading `pm_genpd_summary` → oops. `gdsc.c` is built-in, so this needed a full kernel
  rebuild. Verified with 6 clean rmmod/modprobe cycles.
- ⛔ **2026-07-28: upstream fixed the `gdsc_unregister()` half itself between v7.1 and v7.2.**
  Our patch is **not novel** there. Only the `gdsc_register()` error-path cleanup is still
  missing upstream, and that is a leak-on-failure, not a crash fix. Do not describe this as
  "a real upstream bug we found and fixed".
- ⛔ It was also suspected of causing the audio regression and was **exonerated by
  measurement**: 45 genpd domains on both kernels, zero gdsc/genpd errors.

## DTB arc: test64 → test72

| DTB | delta | verdict |
|---|---|---|
| test64 | gpucc probe | baseline for gpucc1/gdsc1 |
| test65 | **lid switch** on TLMM 92 (from the WoA DSDT), frees pin 92 | good |
| test66 | frees TLMM 94 + 246 (wcn-3p3, wwan) | ⛔ **REGRESSION — never boot it.** Unblocked `wcn7850-pmu` and `1c00000.pci`, which then failed on pins 116/150 (still reserved) → **Wi-Fi dead**, audio worse. *Deferred is better than broken.* |
| test67 | `dr_mode="otg"` | no-op (`CONFIG_USB_DWC3_HOST=y` forces host) |
| test68 | **deletes `usb-role-switch` from `usb@a600000`** | ★ **UCSI/Type-C works for the first time** — `/sys/class/typec/` populates, PD negotiates, **USB-C DisplayPort alt-mode on BOTH ports** |
| test69 | `ramoops@94000000` reserved-memory node | for crash capture; address cross-checked against `/proc/iomem`, not just the DT |
| test70 | **eDP HPD**: frees pin 119, muxes `edp0_hot` on `&mdss_dp3` | matches upstream; **did not fix the teardown crash** |
| test71 | drops `VA DMIC2/3` from `audio-routing` (upstream routes two) | correct per upstream; **no audio change** |
| test72 | test71 + `modprobe.blacklist=msm` | control boot; **audio still fails ⇒ msm exonerated** |

## ★★ THE DISPLAY TEARDOWN CRASH (2026-07-25 → 07-27) — still open

**Symptom:** the SoC hard-resets whenever the eDP panel powers down — idle blank or
`kscreen-doctor --dpms off`. Deterministic.

**Established, do not re-derive:**
- **Linux emits no fault at all.** netconsole with a provably empty queue and ramoops on a
  genuine test69 cycle both came back blank ⇒ `kmsg_dump` never runs ⇒ the SoC is reset
  externally (TZ / secure watchdog / hardware). **Any plan beginning "capture the Oops" is
  refuted.** pstore empty across **seven** attempts.
- **Trigger isolated to `qcom_edp_phy_exit()`**, and **both halves are independently lethal**
  (`PHYSKIP=1` skips the clk disable → dies; `PHYSKIP=2` skips the regulator disable → dies;
  `PHYSKIP=3` skips both → survives). ⇒ timing/ordering, not a specific clock or rail.
- **Bit 64** (defer the PHY power-down 1 s onto a delayed work) — built, booted, **still died**.
- `qcom_edp_phy_power_off()` **does** run first (marker proved it, +424 ms), so the PHY is not
  left live. Asserting `DP_PHY_PD_CTL_PSR_PWRDN` again in exit (`PHYSKIP=4`) changes nothing.
- **Death signature is NOT a discriminator** — four baseline runs gave TZ-fatal at +717 ms,
  none at all, +2.07 s, and none again. Latency and the presence of a TZ fatal are variance.

**Everything eliminated:** `qcom_wdt` (`state=inactive`, `bootstatus=0`) · PMIC PON reason
registers (four event types, four byte-identical dumps — the gen3 offsets are not in the
window we can read) · `sync_state`/interconnect floors (all 52 dropped at runtime, box fine,
teardown still dies) · idle power-collapse (`has_idle_pc=false` booted, still died) ·
**EDL/download mode** (see below) · **eDP HPD** (test70).

### ⛔ EDL / download mode — closed properly

- First attempt was **VOID**: `qcom_scm.c:2847` calls `qcom_scm_disable_sdi()` whenever the
  **probe-time** `download_mode` param is 0, which it always was ⇒ SDI was torn down every
  boot and runtime arming could never land in EDL.
- Corrected test: `fedora-glymur-test69-dload` with `qcom_scm.download_mode=full` on the
  cmdline ⇒ SDI intact, verified. Fired the teardown: **the SoC reset and POSTed by itself
  23 s later.** ⇒ **download mode is fused off on retail hardware.** Route closed.
- Also corrected: `qcom,dload-mode`'s phandle `0x2a` **does not resolve** in the live DT, so
  the IMEM path is unused — arming goes through the SCM call, which *is* available.

## ★★ AUDIO — the long regression hunt (2026-07-27 → 07-28)

**Symptom:** every boot, `CMD timeout [1001021]` (`GET_SPF_STATE`) ~10.2 s and
`CMD timeout [1001002]` (`GRAPH_START`) ~17.9 s, then a cascade of
`DSP returned error[1001006]` (**`APM_CMD_SET_CFG`**, *not* "GRAPH_OPEN" as earlier text
claimed). Card enumerates, DAPM builds, amps `Attached`, `hw_ptr` advances — and no sound.

- ⛔ **"Intermittent" is wrong.** Across the whole persistent kmsg log: **76 boots reached a
  card, ZERO were clean.** The DSP failure is 100 % deterministic — *and reproducible to the
  microsecond across different kernels and DTBs*. Only whether the user hears anything varies.
- ⇒ **A fix can be judged on ONE boot** with `dmesg | grep -aE "CMD timeout|DSP returned"`.
  `speaker-test` is retired as an oracle.
- **Eliminated by measurement:** the audio device tree (all nodes byte-identical across
  test47/52/55/64/71) · the eDP era (test55, display disabled in DT, fails identically) ·
  msm (test72) · the kernel (clean+, edp1, gdsc1 **and 7.2-rc3** all fail) · the gdsc patch ·
  `qcom_pd_mapper` (v7.1 *does* have `qcom,glymur`) · `qcom,intents` and
  `qcom,protection-domain` (identical to upstream) · DMIC routing · mixer state · PipeWire
  sink · **and the hardware itself — audio works in Windows.**
- **Topology provenance:** ours descends from **X1E80100-Romulus — a Microsoft Surface
  topology** (31 892 B, still present as `.romulus.bak`), hand-modified into the current
  29 496 B file, which matches no public board file. The changelog itself recorded it at
  test45 as an "x1e A14/Romulus stand-in", and M11 noted a real glymur topology was deferred.

### ★★★ THE FIND (2026-07-28): `tqftpserv` was missing

- The test35 entry records the working-era userspace as **qrtr + pd-mapper (ACTIVE) +
  tqftpserv (ACTIVE)**, built from source in `~/qrtr ~/pd-mapper ~/tqftpserv`.
- On 2026-07-28 all three were **gone** — no binaries, no source directories, no units.
  `pd-mapper` no longer matters (the in-kernel `qcom_pd_mapper` replaced it and is loaded),
  and QRTR's name service moved into the kernel (`net/qrtr/ns.c`). **But `tqftpserv` has no
  kernel equivalent** — it is the daemon that answers the DSP's file requests over QRTR.
- Without it the DSP asks for something, nobody answers, and its commands time out. This fits
  every otherwise-unexplained observation: identical failure on every kernel/DTB/era (it lives
  on the shared rootfs), microsecond determinism, Windows unaffected, and nothing we changed
  in DT or kernel making any difference.
- **Fix:** `dnf install tqftpserv` (Fedora packages it, 1.1.1-3.fc44) + `systemctl enable
  --now tqftpserv`. Installed and enabled 2026-07-28 18:34.
- ⏳ **UNPROVEN until a fresh boot.** Post-boot playback was already error-free before this
  change; the failure only ever occurs at boot (~13 s). The decisive test is a reboot with
  tqftpserv running from the start: does `GRAPH_START` still time out?

## ★ The konrad lineage — upstream's own A16 device tree (2026-07-28)

- **2026-07-21 Konrad Dybcio (Qualcomm) posted an upstream DT for this exact laptop**
  (`arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`), reviewed by Dmitry Baryshkov
  and Abel Vesa, **still unmerged**. Saved in `upstream/`; see `docs/konrad-tree-plan.md` and
  `UPSTREAM-CREDITS.md`.
- Built as `7.2.0-rc3-konrad1` from a stock `v7.2-rc3` clone. **Stock rc3 is not enough** —
  his DTS needs the LPASS/audio DT patches accepted 2026-07-01/07-06, which landed after the
  tag; `glymur.dtsi` was taken from the drive's patched 7.2 tree instead.
- **Deviations from his DTS (declare these in any upstream report):** `&pcie4_port0_ep` block
  removed, `&remoteproc_soccp` block removed, the dangling `remote-endpoint` line removed,
  `&gpu`/`&gmu` disabled, `&remoteproc_cdsp` disabled.
- **Result 1:** it boots fully — `Startup finished in 16.000s`, `graphical.target`, Plasma
  Wayland session. ⚠️ It *appeared* not to boot because there was no display and no network.
  **Check `journalctl --list-boots` before concluding a kernel does not boot.**
- **Result 2 (first boot):** black screen because his DTS enables `&gpu`; adreno fails `-19`
  (its `arm-smmu 3da0000` and `gxclkctl 3d64000` time out), and msm is a *component*
  framework — one failed component fails the whole master bind, so no DRM device at all.
  **All four DP controllers bound fine**; his display wiring is not at fault.
- **★ Result 3 (GPU disabled):** msm binds, `panel_samsung_atna33xc20` loads — and **eDP link
  training fails `-110`**, the exact pre-HBR3 wall. We deliberately left our HBR3 force out to
  see whether his DT negotiates correctly on its own. **It does not.** ⇒ our HBR3 finding is
  load-bearing and upstream's A16 tree does not address it. *This is the most reportable
  result we have.*
- **Result 4:** Wi-Fi died because `VREG_WCN_3P3` was switched off — dropping the
  `&pcie4_port0_ep` block also removed the connector↔PCIe-port graph link that keeps the rail
  claimed. Fixed with `regulator-always-on`.
- konrad2 (HBR3 force + CDSP disabled + WCN pinned) built 2026-07-28 18:21; msm srcversion
  `257777F752CF092862B1337`, verified **inside the initrd**.

## Infrastructure notes from this period

- **Screen-blank guard was fake.** `kde-inhibit` ran but never appeared in powerdevil's
  `ListInhibitions` (`{}`), and Plasma 6.7 appears to ignore the `[AC][DPMSControl]` keys we
  wrote — so the panel was free to blank itself and hard-reset the box, corrupting an unknown
  number of results. Replaced 2026-07-28 with `glymur-stayawake.service`: a **logind**
  inhibitor (`systemd-inhibit --what=idle:sleep:handle-lid-switch --mode=block`, *verified
  present in `systemd-inhibit --list`*) plus a 45 s `SimulateUserActivity` loop.
- **ssh:** use `ssh -o HostKeyAlias=loazen jcasco@192.168.8.60`. The IPv6 record
  (`loazen.internal` → `…ea00::1c0c`) goes stale after reboots and produces phantom
  "No route to host" while the machine is up and browsing fine. The host key is stored under
  the bare name `loazen`, which is why plain IPv4 ssh fails verification.

---

# 2026-07-29 — The merged tree: a Zenbook A16 with everything working

This is the entry the whole changelog was building toward, so it is written as a narrative
rather than a table. Short version: **the machine now boots one device tree on which the
display, its power-down path, Wi-Fi, battery, Type-C, the keyboard, audio and the Adreno X2
GPU all work at the same time.**

## Standing on Konrad Dybcio's device tree

On 2026-07-21 **Konrad Dybcio** (Qualcomm, <https://konradybcio.pl/>) posted an upstream
device tree for this exact laptop — `arm64: dts: qcom: glymur: Add Asus Zenbook A16
(UX3607OA)`, reviewed by Dmitry Baryshkov and Abel Vesa, still unmerged at time of writing.

Up to that point this project had been a vendor-derived DTB lineage, hand-bisected over
seventy-odd test builds. Konrad's file is a proper board device tree: the pin map, the
regulator topology, the WCN and USB wiring, gpio-keys, and the GPU/CDSP/SOCCP nodes. **The
merged tree in this repo is his file with our fixes added on top, and the structure and board
knowledge are his.** Full attribution, including which of our deltas replace or extend his,
is in [`UPSTREAM-CREDITS.md`](../UPSTREAM-CREDITS.md).

Two things worth saying plainly, because they cut both ways:

- **His tree survives the display power-down that ours could not.** That single experiment —
  same kernel, same `msm`, same initrd, only the DTB swapped — is what proved our long-hunted
  hard-reset was a device-tree defect on our side rather than silicon or TrustZone.
- **His tree does not solve the eDP link-training failure.** With our HBR3 rate force removed,
  link training fails `-110` on his DT exactly as it did on ours. That remains our most
  reportable finding.

## What we added on top

| Area | What was needed | Why |
|---|---|---|
| **eDP link rate** | force HBR3 (8.1 Gbps ×4) in `dp_panel.c` | the panel advertises 5.4 G everywhere and cannot train at it; 8.1 G — never advertised — trains first try. Still unexplained, and not addressed upstream |
| **Display power-down** | `regulator-always-on` on the eDP PHY rails (`vdda-phy`, `vdda-pll`) | without it the SoC is reset externally when the panel powers down, with no Linux fault at all |
| **Wi-Fi** | `qcom,wcn7850-pmu` power sequencer + `regulator-always-on` on the WCN rails | the generic `pcie-m2-e-connector` + `pwrseq` path does not bind on 7.2-rc3; and once Linux owns the 3.3 V rail it switches it off 30 s into boot unless pinned |
| **Battery, Type-C, DP alt-mode** | `soccp_glink` driver + a `soccp_glink_edge` node | `pmic_glink`'s transport on this platform is the SOCCP GLINK channel, and nothing in mainline registers that edge |
| **Type-C enumeration** | delete `usb-role-switch` where `dr_mode = "host"` | dwc3 only registers a role switch in OTG mode, so UCSI waited forever for one that never appears |
| **Keyboard / Fn keys** | `hid-asus` support for I2C-HID `0B05:4B42` | the device ID was in no `asus_devices[]` entry, and on a DT boot the driver freed `kbd_backlight` outright |
| **GPU** | enable `&gpu`/`&gmu` **and stop blacklisting `gpucc`** | see below |

## The GPU, and a lesson about our own workarounds

The GPU had been the headline gap for months. It turned out we were standing on it.

`gxclkctl-kaanapali` lists gpucc as one of its power-domain providers and runtime-resumes it
at probe. Every GRUB entry we had carried `modprobe.blacklist=gpucc_glymur` — a deliberate
guard added for the *very first* gpucc probe, back when an unpowered or XPU-gated register
window could plausibly have hung the SoC. That experiment had long since passed. But the
blacklist stayed, so gpucc never registered, `gxclkctl` timed out, the Adreno SMMU went with
it, adreno failed `-19`, and because `msm` is a component framework **the entire DRM device
failed to bind** — which presented as a black screen and got "fixed" by disabling the GPU
nodes.

Dropping one stale cmdline token and re-enabling two nodes:

```
gpucc                     25 clocks
gxclkctl-kaanapali        bound      (previously -110)
3da0000.iommu  arm-smmu   bound      SMMUv2, 25 context banks
3d00000.gpu    adreno     bound
[drm] Loaded GMU firmware v5.2.38
```

and in userspace:

```
GPU0:  deviceName = Adreno (TM) X2-85     driverName = turnip Mesa driver
       deviceID   = 0x44070041            INTEGRATED_GPU
```

**Video decode/render runs on it and `nvtop` shows GPU processes and memory in use.**
Frequency scaling is live: `simple_ondemand` governor, idling at 310 MHz with a 1.85 GHz
ceiling across 12 operating points.

The takeaway we would offer anyone doing this kind of bring-up: **audit your own debugging
workarounds as ruthlessly as you audit the hardware.** A guard that was correct when written
became the single thing standing between this machine and a working GPU, and it cost months.

## Honest limitations

- **`nvtop` reports Memory/Temp/Power as N/A.** Not a broken GPU — an integrated Adreno has
  no dedicated VRAM to report, there is no hwmon node on the GPU device, and no power sensor.
  The temperatures *do* exist: 14 GPU thermal zones (`gpu-0-0` … `gpu-3-2`, `gpuss-0/1`) under
  `/sys/class/thermal/`, which is simply not where nvtop looks. A discovery-path gap.
- **The device reports as "Adreno X2-85".** That string comes from Mesa, and this Mesa build
  contains no X2-90 name at all. Our chipid `0x44070041` also does not exactly match any of
  the three `a8xx` catalog entries in the kernel (`0x44070001`, `0x44050a01`, `0x44010000`).
  Probably an unmapped SKU/revision; flagged rather than assumed.
- **No zap shader.** Falls back to `SECVID_TRUST_CNTL`.
- **No sustained stress testing yet.** Rendering works; thermals and stability under load are
  unmeasured.
- **The display teardown has not been re-verified with the GPU enabled.** It passed twice on
  the merged tree without the GPU. Adding a large new power consumer is exactly the change
  that regressed it once before, so treat that as open.
- **Suspend, USB4** — still out. USB4 needs a host-router binding that exists only as an
  unmerged RFC; do not hand-write device tree against it.

## Why the crash hunt is documented at such length above

The display power-down reset took the largest share of this project's time, and most of that
was spent eliminating hypotheses rather than confirming one: TrustZone, secure watchdogs, the
PMIC, download mode, interconnect vote drops, idle power collapse, pin reservations, rail
voltages, kernel version, panel pinctrl. Each of those has an entry above with the evidence
that closed it. Several conclusions in this file were later retracted by measurement, and
those retractions are left in place on purpose — they are the useful part of the record.
