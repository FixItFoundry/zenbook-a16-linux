# Changelog

Dated record of what changed and, where it matters, what turned out to be wrong.
Current status lives in [README.md](README.md) and
[`docs/hardware.md`](docs/hardware.md) — this file is history.

Retractions are kept rather than deleted. Several confident conclusions in this project
were later disproved by measurement, and the record of that is more useful than a tidy
one.

---

## 2026-09-16 — SoundWire audio speaker pops eliminated, multi-slave alert demotion fixed, dead stream resolved

- **Speaker pop and dead audio stream root causes identified and resolved**:
  Investigated loud pops on start/stop/seek of audio and reproducible single-sided playback
  (left channel permanently dying while right channel plays) on ASUS Zenbook A16 (`UX3607OA`):
  1. **Multi-Slave Alert Demotion**: `drivers/soundwire/qcom.c`'s `qcom_swrm_get_alert_slave_dev_num()`
     only wrote `ctrl->status[devnum] = SDW_SLAVE_ALERT` for the alerting slave, leaving sibling
     slaves (the Woofer/Tweeter pair on `swr0` or `swr3`) with 0 (`SDW_SLAVE_UNATTACHED`).
     `sdw_handle_slave_status()` observed `UNATTACHED` for the sibling and called
     `wsa884x_update_status()`, marking `hw_init = false` and setting the regmap cache-only.
     This permanently silenced that speaker channel until reboot.
     *Fix*: Call `qcom_swrm_get_device_status(ctrl)` inside `qcom_swrm_get_alert_slave_dev_num(ctrl)`
     so the full register `SWRM_MCP_SLV_STATUS` is decoded for all devices before status processing.
  2. **Destructive Reset on Bus Clash (`MASTER_CLASH_DET`) & Port Collisions**: Earlier local commits
     (`c9cb9438c4e8`, `b6b0bb267d62`) hooked `SWRM_INTERRUPT_STATUS_MASTER_CLASH_DET`, `DOUT_PORT_COLLISION`,
     and `READ_EN_RD_VALID_MISMATCH` to a hard controller reset (`SWRM_COMP_SW_RESET`).
     During live playback, transient bus clashes routinely occur; resetting the master controller
     severed clock and framing, causing loud speaker pops, parity errors on the WSA8845 amplifiers,
     and dropped streams.
     *Fix*: Restored upstream Linux kernel behavior: mask the interrupt bit and log rate-limited,
     preserving the active stream and preventing mid-playback controller resets.
  3. **Non-Destructive Command FIFO Flush**: Aligned `RD_FIFO_UNDERFLOW` and `RD_FIFO_OVERFLOW` with
     `WR_CMD_FIFO_OVERFLOW` and `CMD_ERROR` by flushing the command FIFO (`ctrl->reg_write(ctrl, SWRM_CMD_FIFO_CMD, 0x1)`)
     instead of resetting the controller.
  4. **Probe-Time Cold-Boot 3x Reset Storm on `swr0` (Left Channel)**: During probe, checking
     `ctrl->status[slave->dev_num] != SDW_SLAVE_ATTACHED` in `qcom_swrm_all_slaves_attached()`
     failed on every boot because `ctrl->status` is only populated by IRQs, not during probe.
     This triggered 3 consecutive hardware resets at boot, leaving `swr0` stuck at Dev 0.
     *Fix*: Reverted `qcom_swrm_all_slaves_attached()` to verify `!slave->dev_num`, stopping the probe reset loop.
  5. **Status Wipe on Dev 0 Attachment**: Restored `ctrl->slave_status = slave_status` tracking and removed
     spurious execution of status handlers when Dev 0 attaches before enumeration finishes.
  6. **Quad Channel Map Swap Resolved**: WirePlumber configuration `/etc/wireplumber/wireplumber.conf.d/51-glymur-ucm.conf`
     had `audio.position = [ FL RL FR RR ]`, swapping Front Right and Rear Left channels. Corrected to `[ FL FR RL RR ]`
     to match hardware ALSA PCM order, restoring correct spatial alignment across all 4 speakers.
- **Artifacts Produced**:
  - Patch: `patches/0002-soundwire-qcom-alert-status-and-recovery-fix.patch`.
  - Internal doc: `internal-docs/audio-pop-and-drop-triage-2026-09-16.md`.
  - Test kernel: `7.2.0-ZenbookA16-20260916-audiofix` built via `build-0916-audiofix.sh`,
    installed via `install-0916-audiofix.sh` with safe one-shot `next_entry` GRUB test arming.
    The known-good baseline fallback entry `zenbook-a16` (`7.2.0-ZenbookA16-20260819+`) was preserved.

---

## 2026-09-16 — Wi-Fi 7 (QCC2072) cold-boot enumeration fixed, ath12k softirq storm eliminated, crash resolved

- **Crash triage (`2026-09-16 20:29:08 EDT`)**: Resolved the system panic and journal corruption.
  The crash was preceded by `NOHZ tick-stop error: local softirq work is pending, handler #280/#80`,
  context switch spikes to 133k ctxsw/s, and core 4 pegged at ~400% CPU system time. Traced
  to `drivers/net/wireless/ath/ath12k/pci.c`: `ath12k_pci_ext_grp_napi_poll()` unconditionally
  re-enabled group IRQs even when `napi_complete_done()` returned false, causing an immediate
  interrupt loop in softirq context. Guarded with `if (napi_complete_done(napi, work_done))`.
- **Root cause of missing / intermittent Wi-Fi resolved**:
  The ASUS Zenbook A16 uses a Qualcomm QCC2072 Wi-Fi 7 package (`17cb:1112`) on PCIe controller 4
  (`pcie@1bf0000`, root port `pcie4_port0`). Three compounding issues prevented reliable boot:
  1. `drivers/pci/pwrctrl/pci-pwrctrl-pwrseq.c` lacked the `pci17cb,1112` compatible string,
     so the power sequencer never bound to the Wi-Fi PCIe device node.
  2. `arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dts` omitted `wifi@0` under
     `pcie4_port0` entirely, instead attempting an artificial `wlan-connector` graph node
     connected across both `pcie4_port0` and `uart14`. This created an OF cycle that `fw_devlink`
     broke non-deterministically.
  3. `CONFIG_POWER_SEQUENCING_QCOM_WCN` and `CONFIG_PCI_PWRCTRL_PWRSEQ` were compiled as modules (`=m`).
     Because `pcie-qcom` is built into the kernel (`=y`), it attempted PCIe link training at early
     boot (`t ~ 0.001s`) before modules could load. With `tlmm 117` (`wlan-enable-gpios`) low,
     PCIe link training failed on cold boot and the device never enumerated.
- **Fix deployed**:
  - Added `pci17cb,1112` to `pwrseq_pwrctrl_of_match[]` in `drivers/pci/pwrctrl/pci-pwrctrl-pwrseq.c`.
  - Added user prompt to `PCI_PWRCTRL_PWRSEQ` in `drivers/pci/pwrctrl/Kconfig` and built both
    `CONFIG_POWER_SEQUENCING_QCOM_WCN=y` and `CONFIG_PCI_PWRCTRL_PWRSEQ=y` directly into the kernel.
  - Added `wifi@0` node with full PMU regulator supplies to `&pcie4_port0` and removed `wlan-connector`
    and `uart14` endpoints in `glymur-asus-zenbook-a16-ux3607oa.dts`. Synced to `dts/glymur-asus-zenbook-a16-ux3607oa-merged.dts`.
  - Patch created at `patches/0001-PCI-pwrctrl-ath12k-glymur-wifi7-qcc2072-pwrseq.patch`.
  - Internal doc written at `internal-docs/wifi-qcc2072-pwrseq-triage-2026-09-16.md`.
  - Kernel built as `7.2.0-ZenbookA16-20260916-wififix` (`build-0916-wififix.sh`), installed via
    `install-0916-wififix.sh` with a one-shot `next_entry` GRUB test arming. Default baseline
    entry `zenbook-a16` (`7.2.0-ZenbookA16-20260819+`) was preserved untouched.

---

## 2026-09-06 — camera board wiring recovered from the AeoB blobs; `cci0_i2c0` retracted

- **Method that unlocked it: decode BOTH sensors' AeoB power-sequence blobs together.**
  `CAMF_RES_QRD.bin` (front) and `CAMI_RES_QRD.bin` (aux) encode the literal Windows
  power-up/power-down sequence. A field identical in both is a *shared* resource; one that
  differs is per-sensor. That single distinction is what turns a pile of GPIO numbers into
  an unambiguous mapping. Cross-checked against `drivers/pinctrl/qcom/pinctrl-glymur.c`,
  whose per-pin function tables turn raw mux indices into names.
- **⚠️ RETRACTION: the sensor is not on `cci0_i2c0`.** The 2026-08-21 node's own comment
  called that bus "a genuine guess … the one dimension most likely to be wrong", and it
  was. The blob's `TLMMGPIO_V2` entry muxes `{gpio=0x6a=106, func=1}`; `PINGROUP()` places
  `msm_mux_gpio` at `funcs[0]`, so func 1 on pin 106 is `cci_i2c_scl`. The three
  `cci_i2c_scl`-capable pins are 102/104/106, giving bus pairs `cci0_i2c0` (101/102),
  `cci0_i2c1` (103/104), **`cci1_i2c0` (105/106)**. The entry is identical in both blobs,
  which is exactly what a shared control bus looks like.
- **Recovered, with evidence grades in `docs/hardware.md`:** MCLK4 pin **TLMM 100**
  (`cam_asc_mclk4` — the only MCLK4-capable pin; `cam_mclk_groups[]` is gpio96–99 =
  MCLK0–3); front reset **TLMM 239**; aux reset **TLMM 109**; `dovdd` = **LDO4 on PMIC
  `I_E0`** @ 1.8 V (in both blobs — shared); `avdd`+`dvdd` = **LDO7 on `I_E0`** @ 2.8 V;
  aux analog = LDO3 on `I_E0`; module boost = BUCK_BOOST1 on `B_E0` @ 3.4 V; CPAS AHB
  80 MHz. `I_E0` is `pmh0104_i_e0` — the board dts already uses the identical id
  convention (`qcom,pmic-id = "B_E0"` matches the blob string `..._B_E0` exactly).
- **"Missing DVDD" was never missing.** The blob votes only two LDOs because `avdd` and
  `dvdd` share the 2.8 V rail — the same wiring the ASUS Zenbook A14 uses.
- **⛔ New blocker found: `pmh0104` has no LDOs in the kernel.** `pmh0104_vreg_data[]` in
  `drivers/regulator/qcom-rpmh-regulator.c` declares `smps1`–`smps4` only, and the board
  dts had no `I_E0` `rpmh-regulators` node at all. Staged as
  `patches/glymur-pmh0104-camera-ldos.patch`: `ldo4` (`pmic5_nldo530`, which spans
  320000+n*8000 up to 2.0 V) and `ldo7` (`pmic5_pldo530_mvp150` — 2.8 V is out of nldo
  range and *must* be a pldo). The three `pldo530_mvp{150,300,600}` variants differ only
  in `hpm_min_load_uA`, not voltage, so the pick cannot yield a wrong voltage.
  ⚠️ `CONFIG_REGULATOR_QCOM_RPMH=y` — this is a **full kernel rebuild**, not a module swap.
- **Verified the failure mode of shipping the DT ahead of the kernel.**
  `rpmh_regulator_init_vreg()` returns `-EINVAL` on an unknown subnode and
  `rpmh_regulator_probe()` bails immediately — so on the current kernel `regulators-5`
  simply fails to probe and the sensor defers forever. Blast radius is that node only;
  the other PMICs are separate platform devices. Safe to boot, just inert.
- **Two DTBs staged**, both built clean from `wt-baseline-combined`, both verified by
  decompile to place `camera@36` under `cci@ac16000/i2c-bus@0`:
  - `…-ov02c10-cci1i2c0.dtb` — corrected bus/pins, **no supplies** (dummy regulators).
    Runs on the current kernel; answers the bus question *if* UEFI left the rails voted up
    across the handoff, which RPMh vote persistence makes plausible.
  - `…-ov02c10-full.dtb` — full wiring incl. `regulators-5`. Needs the LDO kernel.
  GRUB entries `zenbook-a16-ov02c10-cci1i2c0` and `zenbook-a16-ov02c10-full` added under
  "Test DTBs". **Default is untouched** (`zenbook-a16`). `grub.cfg` backed up to
  `grub-backups/grub.cfg.bak-pre-camera-20260906`, `40_custom` to
  `40_custom.bak-pre-camera-20260906`; `40_custom` re-synced and confirmed by a
  `grub2-mkconfig` dry-run diffing **identical** to the live `grub.cfg`, so a future
  regeneration will not silently delete these entries (the 2026-08-23 trap).
- **`README.md` camera bullet was badly stale** — it still claimed CAMSS has no support for
  this SoC generation and that the sensor was unidentified, both untrue since 2026-08-21.
  Rewritten.
- **Nothing in the latest rc helps.** `v7.3-rc1` is the newest tag and `zenbook-next-0831`
  is `next-20260831` on top of it. Last commit to `drivers/media/platform/qcom/camss/`
  anywhere is 2026-06-04 (a macro rename); last `ov02c10.c` commit is 2025-12-08. No
  `qcom,glymur-camss` compatible exists, and no upstream DT carries a camss node for
  x1e80100 either. Rebasing gains the camera nothing.

---

## 2026-08-23 — GRUB loadenv error fixed, Wi-Fi/GPIO regression ruled out, CCI baseline promoted

- **GRUB `load_env` error on every boot, fixed.** `/boot/grub/grubenv` carried a stale
  `env_block=512+1` variable (Fedora's raw-block BLS environment feature). `GRUB_ENABLE_BLSCFG=false`
  here and root is btrfs on `nvme0n1p17` with no `bios_grub`/reserved area backing that block
  range, so the unconditional `00_header` boilerplate (`if [ "${env_block}" ]; then ... load_env
  -f "(${root})512+1"; fi`) tried to load a nonexistent raw environment block every boot. Cleared
  with `grub2-editenv /boot/grub/grubenv unset env_block`; `saved_entry`/`boot_success` etc. are
  untouched. Reversible with `grub2-editenv /boot/grub/grubenv set env_block=512+1`.
- **Wi-Fi "baseline has no Wi-Fi" — not a GPIO regression.** Decompiled and diffed the baseline
  DTB (`7.2.0-ZenbookA16-20260819+.dtb`) against the CCI-camera test DTBs: the diff is purely
  additive (`camss@acb7000`, `cci@ac15000` nodes) plus phandle renumbering. `wcn7850-pmu`
  (`wlan-enable-gpios`/`bt-enable-gpios`) and `gpio-reserved-ranges` are byte-identical across
  baseline and all three camera test DTBs. The camera GPIO work did not touch Wi-Fi's pins.
  Not independently reproduced live on the plain baseline entry this session (was booted on
  `ov02c10-test` throughout, where Wi-Fi is confirmed working) — if it recurs, it isn't the DT.
- **Baseline promoted to the CCI-test DTB.** `zenbook-a16` (id, default) now boots
  `7.2.0-ZenbookA16-20260819-cci-test.dtb`'s content (CCI0/CCI1 registration, `i2c_qcom_cci`
  blacklisted so nothing autoprobes) instead of the pre-camera DTB. Old baseline preserved as
  `7.2.0-ZenbookA16-20260819-precamera.dtb`, reachable via Test DTBs → "prev baseline: 20260819,
  pre-camera" (`prev-20260819-precamera`). Edited `/boot/grub/grub.cfg` directly (backed up to
  `grub.cfg.bak-pre-cci-promote-20260823`) rather than regenerating via `grub2-mkconfig`, since
  `/etc/grub.d/40_custom` has drifted out of sync — it's missing the `ov02c10-test`/`camss-test`/
  `cci-test` entries entirely, which live only as hand-edits in `grub.cfg`. Regenerating would
  have silently deleted them.
- **`/etc/grub.d/40_custom` reconciled with `grub.cfg`.** Extracted the live custom section
  (between grub2-mkconfig's own `### BEGIN/END /etc/grub.d/40_custom ###` markers) back into
  `/etc/grub.d/40_custom`, so it now regenerates byte-identical to the hand-edited `grub.cfg`.
  ⚠️ Trap hit and fixed during this: a `cp`-made backup of the old `40_custom` left inside
  `/etc/grub.d/` inherited the executable bit and got picked up by `grub2-mkconfig` as its own
  script, duplicating the entire menu — caught via a dry-run (`grub2-mkconfig -o <scratch file>`,
  diffed before touching anything live) before it hit `/boot/grub/grub.cfg`. Backups belong
  outside `/etc/grub.d/`; `/home/jcasco/grub-backups/` is the existing convention for that.
  Then ran `grub2-mkconfig -o /boot/grub/grub.cfg` for real (backed up to
  `grub-backups/grub.cfg.bak-pre-real-mkconfig-20260823`): the only change was `set default=`
  reverting from the session's manual `zenbook-a16-ov02c10-test` override back to
  `GRUB_DEFAULT=zenbook-a16` (now the CCI-promoted baseline) — done deliberately, at Jesse's
  choice, not a side effect.

---

## 2026-08-21 — Windows-partition cross-check: thermal doc reconciliation, camera sensor IDs

- **Repo sync**: pulled 2 commits from the workstation (`ff91ad5` eDP v8 PHY power-on
  sequencing fix retiring the HBR3-force hack + wsa884x `pm_runtime` fix, `012bddf`
  UPSTREAM-CREDITS.md trim) that hadn't reached `origin/main` or `loazen` yet. Fast-forward,
  no conflicts.
- **New method: mounting the BitLocker-encrypted Windows partition (`nvme0n1p14`) read-only**
  for driver/ACPI archaeology, via `cryptsetup bitlkOpen` (native BitLocker support in
  `cryptsetup` 2.8+, no `dislocker` needed) + `ntfs-3g`. The BitLocker header reports a
  volume size larger than the partition (~950 GiB vs. the actual 929 GiB) — a stale FVE
  metadata field left over from whatever shrank the partition to make room for the Fedora
  install; NTFS's own on-disk geometry matches the real partition exactly, so this is
  cosmetic, not corruption. `ntfs-3g` independently refused read-write on its own (Windows
  Fast Startup left the volume hibernated/dirty) regardless of the mount flags requested —
  worth knowing that safety net exists and fires correctly.
- **Camera — sensor identity resolved.** `docs/hardware.md` originally marked the sensors
  blocked on driver-store extraction. Cross-referencing board-specific extension packages
  in `setupapi.dev.log` against generic reference-design packages resolved both parts:
  - **Front/main sensor**: OmniVision **OV02C10** (2 MP), staged via `qccamfrontsensor_extension8480.inf` (`com.qti.sensormodule.ov02c10.{bin,json}`).
  - **Aux/IR sensor (Windows Hello)**: SK Hynix **HM1092**, staged via `qccamauxsensor_extension8480.inf` (`com.qti.sensormodule.hm1092.{bin,json}`).
  - *(Retraction)* An initial read of generic `.sys` probe strings suggested Azurewave/OV9234 and OV08X/IMX688 candidates; these were reference-design fallbacks, not the board-populated sensors.
  - `CAMP` MMIO/IRQ resources in the Windows dump match the existing DSDT extraction.
- **Thermal — reconciled stale docs, cross-checked against Windows, no new gap found.**
  `docs/power-and-thermal.md` still framed `cooling-maps` as "★ NEXT" though they landed
  2026-07-31/08-02 (`docs/hardware.md`/`docs/modifications.md` already had this right) —
  added a stale-status note and struck the item. Cross-checked the Windows ACPI thermal
  device inventory (`SUMMARY_REPORT.txt`) against Linux: the 9 `Qualcomm Temperature Sensor
  Device` nodes map 1:1 to the 9 SPMI PMIC `temp-alarm` zones already bound; the 3
  "mitigation" nodes are software policy with a Linux equivalent for 2 of 3 (CPU governor +
  `cooling-maps`, `ath12k_thermal`) and no equivalent for the third (NSP0/CDSP, an NPU
  bring-up gap, out of scope here). Grepped the full Windows device dump for NVMe/WSA884x
  thermal entries and found none — **neither OS puts those two devices on the OS
  thermal-policy bus on this hardware**, so `docs/thermal-sensor-mapping-HANDOFF.md`'s open
  question ("is this a known gap upstream too?") is answered: not a reference-design gap,
  just unmanaged on both OSes. Full detail and update history in that file.

---

## 2026-08-17 — Rebase on `next-20260817`, SoundWire deferred probe resolution, trusted TPM2 fix

- **Baseline rebase to `next-20260817`**:
  - Reconciled A16 DTS with upstream merged DTS (1130 lines), carrying local fixups (`regulator-always-on` for WCN 3.3V, `wcn7850-pmu` node, path-based thermal zone cleanup).
  - Maintained 11-patch functional kernel delta (<350 lines): SCMI polling, eDP rate-set reachability, push_idle guard, local HBR3/PCI skip workarounds, HID Zenbook keyboard feature completion, audio q6apm fast-retry, SoundWire auto-enumeration/reprobe, and trusted TPM2 include.
- **SoundWire & Audio bring-up**:
  - Isolated root cause for unattached SoundWire slaves: probe deferrals on dependent resources (e.g. `reset-gpios` through LPASS TLMM) leave slaves un-enumerated if the deferred probe queue isn't re-triggered promptly. Added direct `device_reprobe()` on unattached slaves during controller probe.
  - Added device 0 alert auto-enumeration trigger and bus clash recovery.
  - Added EasyEffects systemd service hook to guarantee clean 4-channel linking on startup.
- **Security / Keys**:
  - Fixed missing `<linux/asn1_decoder.h>` include in `security/keys/trusted-keys/trusted_tpm2.c` for `CONFIG_TRUSTED_KEYS=y`.

---

## 2026-08-16 — Audio UCM2 & routing stabilized, Bluetooth verified, GRUB menu cleaned

- **Audio routing & Quad WSA8845 speaker resolution**:
  - Restored upstream shared `reset-gpios` (`gpio12` Left, `gpio13` Right) and removed conflicting `output-low` pinctrl that clamped speaker amplifiers in reset during boot and triggered startup SoundWire bus clashes.
  - Standardized kernel sound card driver ([`sound/soc/qcom/x1e80100.c`](file:///home/jcasco/kernel-build/zenbook-next/sound/soc/qcom/x1e80100.c)) 4-channel slot mapping to standard quad layout: `[FL FR LB RB]` (WooferLeft, WooferRight, TweeterLeft, TweeterRight), matching PipeWire quad layout `[FL FR RL RR]`.
  - Configured WirePlumber with standard quad mapping and automatic stereo upmixing, ensuring EasyEffects and standard stereo clients route cleanly to both Left and Right speaker pairs simultaneously.
- **Bluetooth**: WCN7850 Bluetooth controller verified on `hci0` over UART14 via native power sequencing.
- **GRUB Bootloader hierarchy**: Reorganized `/etc/grub.d/40_custom` and `/etc/default/grub` to establish clean top-level menu hierarchy (Fedora ARM baseline default, Windows Boot Manager chainloader, UEFI Firmware Settings, and Test DTBs submenu). Configured persistent `saved_entry=zenbook-a16` across both `/boot/grub/grubenv` and `/boot/grub2/grubenv` to survive `grubby` reapplications and reboots.

---

## 2026-08-15 — external report: DPMS-on wake reset is a separate, upstream-fixed cause

GitHub issue #2 (142spp) reports a hard SoC reset on **DPMS on** (display wake),
distinct from the PHY-regulator teardown reset we fixed on the disable/modeset path.
With the panel and DPTX/DPU cleanly suspended, requesting DPMS on reset the machine —
no panic, no pstore, reproducible with `kscreen-doctor --dpms off` then `on`.

Root cause: `dpu_core_perf_crtc_update()` computes a zero aggregate DPU core clock
rate when the CRTC goes offline and passes it to `dev_pm_opp_set_rate()`, which resets
the SoC. Upstream fixed it in `next-20260807` with a guard in
`drivers/gpu/drm/msm/disp/dpu1/dpu_core_perf.c`:

    /* If we're going offline, PM callbacks will disable the clocks instead */
    if (!clk_rate)
        return 0;

Donggeun Lee backported just that hunk and got 13 consecutive clean DPMS off→on cycles.

This is a **second, independent** reset path: our `PUSH_IDLE` guard (2026-08-07) covers
the disable/modeset path; the upstream `dpu_core_perf` guard covers the enable/wake
path. Our `next-20260807` baseline already carries both, so the daily driver is covered.

---

## 2026-08-07 — the display comes up on current linux-next, and the silent reset is solved

**Two bugs, both found by measurement on hardware, and the machine now boots a working
display on `next-20260803` (7.2-rc6).** Before today, no unmodified upstream kernel had ever
lit this panel.

**1. The silent SoC reset was the DP disable path, not the compositor.** Every failing boot
died 1.9–4.3 s after the Wayland session started, which made the compositor look guilty for
weeks. It was not. When eDP link training fails, `msm_dp_display_atomic_enable()` returns
early leaving `->power_on` false, but `msm_dp_display_atomic_disable()` writes
`DP_STATE_CTRL_PUSH_IDLE` anyway — the one step of the teardown that is not gated on that
flag. On this SoC TrustZone answers it by force-stopping the SOCCP and ADSP, and the machine
resets silently ~50 ms later with no oops and no panic. The compositor was simply the first
thing that performed a modeset; `echo 1 > /sys/class/graphics/fb0/blank` reproduces it with
no compositor, no GPU and no login. A one-line guard fixes it, verified by repair.

**2. The eDP PHY on this SoC trains only at HBR3.** Forcing each rate in turn on otherwise
identical kernels: RBR and HBR fail clock recovery outright, HBR2 completes clock recovery
and never completes equalization, and 8.1 Gbps trains on the first attempt every time. The
panel advertises **HBR2 as its maximum**, so a correct kernel selects the one rate that
cannot work and the screen stays black. `phy-qcom-edp.c` is byte-identical at
`next-20260713` and `next-20260803`, so this is long-standing, not a regression. Reported
upstream; our local override is deliberately **not** proposed, because it drives the link
above the sink's advertised maximum.

### ⛔ Retracted

- **"The toolchain is the variable."** A long detour concluded that kernels built with the
  cross compiler reset and natively built ones did not. False. The "surviving" native build
  never brought `msm` up at all — no `card1`, no `eDP-1`, no `Initialized msm` — so it never
  performed a modeset and never reset. It was running on the UEFI framebuffer. Nothing about
  the compiler resets this SoC.
- **"No pure upstream kernel has ever booted this laptop"** and **"the working kernel cannot
  be reproduced, so decompile it."** Both rested on the same bad reading. The working kernel
  was never special; it simply forced HBR3.
- **"It is an rc3 → rc6 regression."** Tested directly: an rc6 kernel built with the rc3
  `drivers/gpu/drm/msm/dp` directory fails identically. The DP rework is exonerated.

### Method note that cost the most time

`grep -c "link training"` returning 0 is **not** evidence that training succeeded — it is
also what you get when the display driver never binds. Confirm the connector exists first.
Likewise, a kernel log from a boot that reset at ~23 s is missing its early lines, because
journald had not flushed them; several boots were scored on absent evidence. Kernel messages
captured over netconsole were what finally settled it.

## 2026-08-04 (evening) — a first upstreamable patch, and two conclusions withdrawn

**The project has a patch worth sending.** `arm,no-completion-irq;` on the `scmi` node —
one line, `git format-patch` format, building clean against `next-20260803` and running on
the machine, with all three cpufreq policies scaling. ⚠️ Earlier the same day these notes
said that property was not upstream. Wrong: it is documented in `arm,scmi.yaml` and read by
`drivers/firmware/arm_scmi/driver.c`. Upstream simply does not set it on glymur, so no driver
or binding change is needed.

**The silent reset runs on a fixed timer.** Three unrelated configurations died at 27, 26 and
26 seconds past first contact. That is a timeout, not a race, and it redirects the search
from init ordering to timers, watchdogs and handshake deadlines.

**Eliminated by single-variable boot test, each against a pure upstream control:** the camera
clock controller, `.use_rpm` on `gcc_glymur_desc`, `qcom,pdc-ranges`, the whole local patch
set, QSEECOM, and the SoCCP remoteproc. QSEECOM had looked compelling — it was allowlisted
for this exact laptop inside the regression window — and it made no difference.

**Five other tests produced no information at all, and are recorded as void rather than
negative.** A reset repoint that swapped a reset out instead of adding one; a dwc3 test where
probe ordering released the clocks before the path under test ran; a ramoops attempt against
a kernel built without the console backend; a module that loaded but could not be shown to
have attached; and a watchdog field that is only populated on other platforms. Each looked
like an answer. ⇒ Two rules came out of it: **prove the variable actually moved** before
scoring an elimination, and **treat a suspiciously fast reboot as a failed probe, not a
death**.

**`com_aux` is not a DP-only bug.** Reading the clock controller directly during a failing
boot eliminated the remaining structural suspects — the USB4 DP0 reset is already deasserted
and untouched by the driver, the power domain is byte-identical to a working instance, and
the parent clock source is shared with a clock that enables fine. With the tertiary USB
controller enabled, the **USB half of the same PHY also fails**. So `phy@88e1000` is
non-functional for both USB3 and DisplayPort, and the report drafted around `com_aux` needs
rebuilding on that basis.

**The eDP link-rate explanation is downgraded to conditional.** Decoding the panel's own
DisplayID gives 2880x1800 at a 709.632 MHz pixel clock, with the EDID declaring 10 bits per
colour. At 8 bpc that fits HBR2 with 1.4 % to spare; at 10 bpc it needs 21.3 Gbps and cannot
fit HBR2 at all. If the driver programs 10 bpc then 8.1 Gbps is *required and correct*, not
"an accident of the rate-set bug" as recorded here previously — and Konrad's board file lists
8.1 deliberately. The bit depth has not been measured, so the earlier explanation stands only
until it is. ⚠️ Both panel modes share one pixel clock, so dropping to 60 Hz would not reduce
the bandwidth requirement.

**A SoCCP claim was made and withdrawn the same night.** These notes briefly said upstream
asks Linux to load a processor that cannot be loaded, because the DT enables a SoCCP
remoteproc while its firmware image exists nowhere — not in linux-firmware, not in our
staging, not in the Windows driver package. That was wrong, and the mistake was reading the
device tree without reading the driver: the resource is marked early-boot, which puts the
remote processor into a detached state and returns before the firmware is ever requested.
Upstream *attaches* to the bootloader-started SoCCP rather than loading it — the same model
this project arrived at independently, implemented properly. ★ The correction inverts the
open question: if upstream attaches, its glink edge should come up too, which would make our
out-of-tree registrar **redundant rather than required** on `next-20260731+`. Untested.

**Why no crash dump has ever been captured.** The kernel was built without the pstore console
backend, and the ramoops node carries no console area — so ramoops only ever wrote on panic
or oops, and a reset with no panic never reaches that path. Every empty pstore recorded on
this project is evidence about the configuration, not about the crash. A kernel with the
console backend enabled is built and staged.

**Still open.** No post-mortem yet. Untested suspects: the rpmhpd retention change, the
tcsrcc rewrite, the new wakeup-source nodes, and the TrustZone changes that do affect the
ADSP, which does load on this machine. ⚠️ And an unfilled control: **a pure upstream
`next-20260713` has never been booted.** The stable rc3 is our own tree, so the comparison
behind the regression report moves two variables at once. The within-tree comparison still
holds, but that control should be run before the report goes out.

## 2026-08-04 — the A16 board file is upstream

Checked our tree against **linux-next `next-20260803`** (7.2-rc6). Upstream drift since the
base of our running kernel (`next-20260713`) is 7,173 files, +351,640 / −87,373.

**Konrad Dybcio's ASUS Zenbook A16 device tree has been merged** —
`e8fbbca94db7 arm64: dts: qcom: glymur: Add Asus Zenbook A16 (UX3607OA)`, reviewed by Abel
Vesa and Dmitry Baryshkov, applied by Bjorn Andersson, with the binding alongside it. Both
prerequisites that had blocked it (`remoteproc_soccp`, `pcie4_port0_ep`) landed by
`next-20260731`, so it builds standalone. The note in these docs that his series was
unmerged was true on 2026-08-02 and is not true now.

**One of our patches turned out to be his, and is now upstream.** The thermal-zone label
additions in `pmh0104-glymur.dtsi` / `pmh0110-glymur.dtsi` are byte-identical to what his
commit carries — same before/after blob hashes. They dropped out of our delta on rebase.

Our patch set rebased onto `next-20260803` cleanly apart from two conflicts: `dp_ctrl.c`
(upstream refactored `msm_dp_ctrl_on_link()` to take `panel` as a parameter; our rate-set
copy was re-spelled, semantics unchanged) and `localversion-next` (kept deleted). The delta
is now 11 files, 4,210 lines.

Over 40 glymur commits landed in this window, including a PDC IRQ mapping fix, USB
controllers marked wakeup-capable, the SoCCP DT node, and the camera clock controller — two
of which were on our own suspect list for an unrelated instability.

**A zap-shader lead reopened, cautiously.** `c22000637636 remoteproc: qcom: pas: add
needs_tzmem flag to trigger shmbridge creation` is new in `next-20260803` and was *not*
present when we tested and closed the zap shader on 2026-08-02. Its rationale — SHM bridge
creation being required to protect remoteproc metadata, previously gated on an `iommu`
property — matches the shape of our `-EINVAL` from `qcom_pas_init_image()`. ⚠️ But it
touches remoteproc only; the GPU zap path goes through `qcom_mdt_load()`, and
`mdt_loader.c` is unchanged. So this is not a fix — it is evidence the mechanism we blamed
is real, and grounds for one retest rather than a reopening.

## 2026-08-02 — verification pass against upstream, and two suspend bugs root-caused

**Repo audit vs upstream.** Four long-standing claims in these docs were checked against
the actual kernel tree and the linux-firmware archive, and were wrong:

| Claimed | Actual |
|---|---|
| No firmware for this machine is redistributable | `linux-firmware` ships glymur ath12k (QCC2072), QCA Bluetooth, ADSP/CDSP, `gen80100_zap.mbn` and CRD audio topology |
| `camcc-glymur.c` does not exist | It exists, builds, and `glymur.dtsi` already has the node |
| No zap shader exists | `gen80100_zap.mbn` is upstream; it was simply not installed |
| SPMI needs work pulled in | Driver match, binding and both bus nodes are all upstream |

Confirmed still true: USB4's host-router binding is an unmerged RFC, and CAMSS has no
support for this SoC generation.

**Camera — first real step.** `camcc` probes for the first time: 94 `cam_cc` clocks,
driver bound to `ade0000.clock-controller`. No code was needed — only
`CONFIG_CLK_GLYMUR_CAMCC=y`. CAMSS remains a driver port, not a device-tree job.

**HDMI — half solved.** Removing `com_aux` from `phy@88e1000` makes the DP PHY
initialise: EDID 0 → 512 bytes, modes 0 → 32, and it removes a compositor hang. The
output is still black because nothing delivers HPD to `af64000`. Konrad Dybcio's
unmodified upstream DTS reproduces the PHY failure identically on this unit, which makes
this a driver issue rather than a device-tree one.

**Suspend — the two resume failures are now characterised.** Both are mitigated, neither
is fixed:

- **xHCI.** Controllers suspend with the HS-PHY not in L2, leaving a stale ring; on
  resume the controller DMAs into an address the SMMU cannot translate and xHCI latches a
  fatal Host System Error. Duration-independent. Attached devices eliminated — two
  controllers with nothing attached fail identically.
- **ath12k.** MHI reaches the device but never reloads AMSS. Duration-sensitive: a 2m25s
  sleep passes, 12 minutes and beyond fail. `remove` + `rescan` recovers it 3/3; a driver
  rebind does not.

Rejected as causes: `glymur_pci_skip=5`, USB autosuspend policy, attached devices,
`d3cold_allowed=0`, and the ath12k regulatory-update timeout.

**GPU zap shader — closed as not fixable from Linux.** The DT node is correct and does
remove the `-ENODEV` fallback, but `qcom_pas_init_image()` then returns `-EINVAL`:
TrustZone rejects the upstream-signed image. Worse, `a8xx_gpu.c` tolerates only
`-ENODEV`, so adding the node costs the entire GPU (`gpu hw init failed: -22`). The
`SECVID_TRUST_CNTL` fallback is correct on this machine.

**Corrections.** Dimmable keyboard backlight works (`asus::kbd_backlight`,
`max_brightness=3`) — the A16 `hid-asus` entry does carry `QUIRK_USE_KBD_BACKLIGHT`.
`qcom-spmi-temp-alarm` is bound on nine PMICs with nine live thermal zones; SPMI was
never the reason the fan PWM is missing, and that cause is now unidentified.

**Docs consolidated** from 65 files into a component reference plus this changelog.

## 2026-07-31 — CPU frequency scaling, fan RPM, thermal actuation

**cpufreq works.** `scmi-cpufreq` had failed `-110` since the start and the cores ran
pinned at boot clock. Root cause: the PDP0/CPUCP firmware answers SCMI protocol 0x13
(Performance) in shared memory but never rings the mailbox doorbell for it, so every perf
transfer waited on an interrupt that never came. Proven by sending the identical message
both ways — `status 0` in polling mode, hangs forever in interrupt mode, with the doorbell
IRQ counter not moving.

The fix is one device-tree property, `arm,no-completion-irq` on the `scmi` node. No kernel
patch. Result: three SCMI performance domains, 355 MHz to 3.61/4.45 GHz,
`scaling_driver = scmi`, `schedutil` under power-profiles-daemon.

**Thermal `cooling-maps` were never broken.** This was listed as an open gap — *"the
cooling devices exist but no zone actuates them."* That was an artefact of a broken check:
both this repo and the on-box verifier counted
`/sys/class/thermal/thermal_zone*/cdev*_type`, an attribute this kernel does not have, so
the check returned 0 whether the maps were bound or not. Measured properly: 41 of 41
`cpu*`/`cpullc*` zones bind `cpufreq-cpu0/6/12`, plus 14 GPU zones on
`devfreq-3d00000.gpu`, with actuation confirmed across the 95 °C passive trip.

⛔ Never write `emul_temp` at or above the critical trip (115000) — the thermal core calls
`hw_protection_shutdown` and powers the machine off on the spot.

This was the **fourth** time this project's own tooling, not the hardware, produced a
false negative — after `modprobe.blacklist=gpucc_glymur`, `efi=noruntime`, and the thermal
guard. The rule that came out of it: *before believing a negative, prove the instrument can
report a positive.*

**Fan RPM readback** via the EC on i2c-9. **Keyboard backlight and Fn keys** working.
`glymur-thermal-guard` **retired** — it never fired once across 62 retained boots, because
it wrote to a `scaling_max_freq` that did not exist while cpufreq was dead.

**Boot-argument audit.** Retired `softlockup_panic=1`, `arm64.nopauth` and
`kvm-arm.mode=protected`. `/boot/grub/grub.cfg` became a generated file with
`/etc/grub.d/40_custom` as its source.

## 2026-07-30 — suspend, RTC, and the move to 7.2

**Suspend works**, on a workaround. Stock, s2idle hard-resets the SoC with no fault of any
kind. Root cause: **PCI config-space access during `dpm_suspend_noirq()` resets this SoC**,
with the read (`pci_save_state()`) and write (`pci_prepare_to_sleep()`) paths independently
lethal and driver noirq callbacks innocent — one PCIe device performing its noirq suspend
is sufficient. This reproduces on the bare upstream A16 device tree, so it is a platform
gap, not a defect in ours. The workaround (`glymur_pci_skip=5`) skips both accesses, which
leaves PCI devices powered through suspend: it sleeps, but saves less power than a correct
implementation, and a firmware revision is needed for a real fix.

**RTC.** `/dev/rtc0` exists and counts. `qcom,uefi-rtc-info` made `rtc-pm8xxx` defer
forever on this build; dropping the property makes it bind. It is read-only, has no wake
alarm, and its counter is free-running rather than a wall clock, so the epoch offset is
supplied from userspace.

**`efi=noruntime` retired.** ⚠️ Do not treat "this firmware does not support EFI variable
services" as settled — two archived `efi_pstore` crash dumps prove variable services
*worked* on this same machine and firmware under 7.1 kernels. The `EFI_UNSUPPORTED` result
is real but specific to the 7.2-rc3 build, and the cause is unresolved.

**The "do not build on 7.2 / linux-next" warning was retired.** It read: *"a regression
somewhere in the 7.2 cycle broke the working glymur chain."* Honest at the time, wrong
about the cause. What actually broke was **our device tree** — a vendor-derived DTB lineage
carrying assumptions the newer tree no longer matched. Rebasing onto Konrad Dybcio's
upstream A16 DTS made 7.2 work, and several things blamed on the kernel turned out to live
in that DT.

## 2026-07-29 — the GPU works, and everything works at the same time

A single merged device tree on which display, its power-down path, Wi-Fi, battery,
Type-C/DP alt-mode, keyboard, audio and the Adreno X2 GPU all work together.

```
GPU0:  deviceName = Adreno (TM) X2-85     driverName = turnip Mesa driver
       [drm] Loaded GMU firmware v5.2.38   gpucc: 25 clocks
```

**The GPU was blocked by one of our own debugging workarounds.** A
`modprobe.blacklist=gpucc_glymur` guard, added long before for the first (then-risky) gpucc
probe, was never removed. Because `gxclkctl` runtime-resumes gpucc at probe, that stale
token cascaded into the Adreno SMMU timing out, adreno failing `-19`, and — since `msm` is
a component framework — the entire DRM device failing to bind. It presented as a black
screen and was "fixed" for months by disabling the GPU nodes.

Two earlier root causes were retired at the same time: *"gpucc is absent from mainline"* was
wrong twice over — `drivers/clk/qcom/gpucc-glymur.c` had been in mainline v7.1 all along,
the a8xx Adreno driver was already compiled into our `msm.ko`, and the firmware was already
on the box. There was almost nothing to reverse-engineer.

**The lesson: audit your own debugging workarounds as ruthlessly as you audit the
hardware.**

Also this day: **audio intermittency fixed** — never the ADSP or the topology, but
`glymur-audio-route.service` racing `wireplumber`; **Bluetooth** brought up by adding a
`qcom,wcn7850-bt` serdev node under `&uart14`; **UCSI + DP alt-mode confirmed on both
USB-C ports**, fixed by deleting one DT property (`usb-role-switch` on host-mode dwc3).

## 2026-07-16 → 2026-07-28 — DTB iteration arc (test64–test72) and supporting findings

**DTB changes, one variable per boot:**
- test64: gpucc probe (baseline for gpucc1/gdsc1).
- test65: lid switch on TLMM 92 (from the WoA DSDT); frees pin 92.
- test66: freed TLMM 94 + 246 (wcn-3p3, wwan) — **regression, never boot it:** unblocked `wcn7850-pmu` and `1c00000.pci`, which then failed on pins 116/150 (still reserved) → Wi-Fi dead, audio worse.
- test67: `dr_mode="otg"` — no-op (`CONFIG_USB_DWC3_HOST=y` forces host).
- test68: deleted `usb-role-switch` from `usb@a600000` — first UCSI/Type-C bring-up; `/sys/class/typec/` populates, PD negotiates, USB-C DP alt-mode on both ports.
- test69: `ramoops@94000000` reserved-memory node for crash capture (address cross-checked against `/proc/iomem`).
- test70: eDP HPD — frees pin 119, muxes `edp0_hot` on `&mdss_dp3`; matches upstream; did not fix the teardown crash.
- test71: dropped `VA DMIC2/3` from `audio-routing` (upstream routes two); correct per upstream; no audio change.
- test72: test71 + `modprobe.blacklist=msm` — control boot; audio still fails ⇒ msm exonerated.

**gdsc genpd teardown:** `gdsc_init()` calls `pm_genpd_init()` but nothing called `pm_genpd_remove()`, so `rmmod` of a qcom clock controller left the global `gpd_list` pointing into freed memory (list corruption on next `modprobe`). Upstream fixed the `gdsc_unregister()` half between v7.1 and v7.2; only the `gdsc_register()` error-path cleanup remains outstanding upstream (leak-on-failure, not a crash). Measured innocent of the audio regression (45 genpd domains, zero errors on both kernels).

**Audio root cause (2026-07-28):** the DSP failures (`CMD timeout [1001021]` GET_SPF_STATE, `[1001002]` GRAPH_START, `DSP returned error[1001006]` APM_CMD_SET_CFG) were deterministic across every kernel/DTB and unaffected by msm, the topology, or the kernel — because `tqftpserv` was missing. The in-kernel `qcom_pd_mapper` replaced `pd-mapper`, but `tqftpserv` has no kernel equivalent: it answers the DSP's file requests over QRTR. Fix: `dnf install tqftpserv` + `systemctl enable --now tqftpserv`. (The `glymur-audio-route.service` / wireplumber race noted on 2026-07-29 is a separate, milder intermittency; the missing daemon was the hard failure.)

**Audio topology provenance:** the in-tree topology descends from the X1E80100-Romulus (Microsoft Surface) topology, hand-modified, and matches no public board file. (2026-07-18 shipped it from the public BSD-3 `linux-msm/audioreach-topology` source — same lineage.)

**Display teardown crash (still open):** eDP power-down hard-resets the SoC; trigger isolated to `qcom_edp_phy_exit()` (both clk-disable and regulator-disable halves independently lethal); no Linux fault captured (pstore empty; reset is external). **EDL/download mode closed:** the SoC reset and self-POSTed rather than entering EDL, so download mode is fused off on retail hardware.

## 2026-07-24 — native eDP

The panel is driven by the real DPU (`fb0 = msmdrmfb`, 2880x1800@120,
`dp_aux_backlight`), not the UEFI `simple-framebuffer`. Link training completes at **HBR3
(8.1 Gbps × 4 lanes)** and the long-standing `-110` failure is gone.

The panel was dark for three stacked reasons, each fully masking the next:

1. A `dispcc` `clocks[]` indexing error in our device tree that orphaned the DP3 link
   clocks and oopsed the kernel.
2. A generic upstream `msm` bug that made the eDP 1.4 `LINK_RATE_SET` path dead code.
3. **5.4 Gbps is simply not a working operating point on this panel** — it trains at HBR3.

The eDP PHY driver needed no changes at all. The earlier "TrustZone XPU wall" theory was a
misdiagnosis, and so was blaming the DP PHY.

⚠️ Still unexplained: the panel advertises 5.4 Gbps as its maximum everywhere it is asked,
and the UEFI firmware trains it at 5.4 Gbps — but Linux cannot, at any drive level or lane
count. 8.1 Gbps, a rate the panel never advertises, trains first try.

**Lid switch** added the same day — TLMM GPIO 92, recovered from the Windows-on-ARM ACPI
DSDT.

## Earlier

- **2026-07-20** — the "MDSS enabled + `msm` loaded kills Wi-Fi" regression was retired; it
  was a load-ordering problem with `ath12k`, not a power-domain/NoC/SMMU interaction.
- **2026-07-19** — keyboard and keyboard backlight brought up via the ASUS vendor HID
  handshake. Independent of the display work.
- **2026-07-18** — audio topology shipped from public BSD-3 source
  (`linux-msm/audioreach-topology`).
