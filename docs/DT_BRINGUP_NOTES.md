# DT Bring-up Notes — Attempt #2 Analysis & Next Steps

Updated 2026-07-10 while the full-config kernel DT results come in.

## Attempt #2 (7.1.0-glymur-full + CRD DTB): major progress, new hang point

From the boot photo:
- **simpledrm console up at 0.36s** — display works on the DT path (that's new).
- **usbhid registered** — USB HID core alive.
- **"Freeing initrd memory: 44648K" at 0.57s** — the Ubuntu initrd unpacked fine; the full-config kernel fixed the old initramfs failure.
- `integrity: Couldn't get UEFI db/dbx` — known broken-EFI-vars noise, harmless.
- Hang occurs **after core kernel init, at the start of the driver-probe phase** — exactly where board-level DT (regulators/GPIOs) starts mattering, and where CRD≠A16 bites.

Note: the full kernel also brings a much bigger module zoo in its initrd than attempt #1's minimal kernel — the hang could come from a driver attempt #1 didn't even have. Don't assume it's the same stall.

## Tonight's diagnostic: `initcall_debug`

Add `initcall_debug` to the DT entry's linux line (press `e` in GRUB or edit `/etc/grub.d/40_custom` + `update-grub`). The kernel then logs every driver init as it starts — **the last line on screen names the hanging driver.** Photograph the last ~10 lines. That's the whole experiment.

## CRD board-level DT inventory (decompiled from glymur-crd.dtb)

These nodes describe Qualcomm's reference board, not the A16. Each hardwires GPIO numbers that mean something different (or nothing, or something dangerous) on ASUS's board:

| CRD node | What it does | GPIO (controller phandle, pin) | A16 risk |
|---|---|---|---|
| `regulator-nvme` (VREG_NVME_3P3, boot-on) | powers NVMe slot | (255, 14) — PMIC GPIO | A16 NVMe rail is EC/always-on; toggling pin 14 on the A16 PMIC does *something else* |
| `regulator-nvmesec` | 2nd NVMe slot (CRD only) | (263, 14) | A16 has no 2nd slot — disable |
| `regulator-wcn-3p3` (boot-on) | Wi-Fi module power | (105, 94) — TLMM | A16 Wi-Fi is NCM820A on PCIe, own power path |
| `regulator-wcn-0p95` | Wi-Fi core rail | chained from wcn-3p3 | same |
| `wcn7850-pmu` | **CRD's Wi-Fi chip ≠ ours** (WCN7850 vs QCC2072) | wlan-en (105,117), bt-en (105,116) | disable outright in A16 DTS |
| `regulator-edp-3p3` (boot-on) | panel power | (105, 70) — TLMM | A16 panel power likely differs; suspect for display/backlight later |
| `regulator-misc-3p3` (boot-on) | misc peripherals | (256, 6) | unknown A16 meaning |
| `gpio-keys` (Volume Up) | CRD's vol-up button | (255, 6, active-low) | A16 is a laptop — no vol-up; harmless but wrong |
| `pmic-glink` + 2× usb-c-connector | battery/USB-C via glink | — | **keep** — matches A16 (2 USB-C ports); this is the battery-status path |

Four of these are `regulator-boot-on` **with GPIO toggles the kernel performs at probe time** — prime hang/misbehavior candidates when the GPIO map is wrong.

## A16 board DTS strategy (first milestone: DT boot → shell on NVMe)

1. `glymur-asus-zenbook-a16.dts` = include `glymur.dtsi` machinery from CRD DTS, then:
   - Convert `regulator-nvme` to a plain always-on fixed regulator **without GPIO** (rail is firmware/EC-managed on a laptop).
   - Delete/disable: `regulator-nvmesec`, `regulator-wcn-*`, `wcn7850-pmu`, `gpio-keys` vol-up, `regulator-edp-3p3` (display later — simpledrm doesn't need it), `regulator-misc-3p3`.
   - Keep: CPUs, GIC, SMMU, PCIe+PHY (NVMe), GENI UART, pmic-glink.
2. Boot with `initcall_debug` still on → shell on NVMe = milestone 1.
3. Then add back one subsystem at a time: GENI I2C1/6/9 + i2c-hid (keyboard 0x15 / touchpad 0x17 / touchscreen 0x10, per 03 doc) → battery (pmic_glink) → panel/backlight → GPU → audio.

## Attempt #3 evidence (initcall_debug photo) + test DTBs

initcall_debug showed: interconnects all probe OK (**RPMh comms work**), all 18 `power-domain-cpuN` return -517 (EPROBE_DEFER — waiting on the SCMI perf provider), hang inside deferred-probe processing after the last interconnect. `/firmware/scmi` uses a mailbox+shmem transport — a non-responding mailbox peer on ASUS firmware would block exactly like this.

Test DTBs (built 2026-07-10, in `boot-kit/out/`, copy to `/boot/glymur/`, select via `e` on the DT entry):
- `glymur-a16-test1.dtb` — 5 board regulators stripped of GPIO toggles (always-on), wcn7850-pmu + gpio-keys disabled, SCMI intact.
- `glymur-a16-test2.dtb` — test1 + `/firmware/scmi` disabled (CPUs stay at boot freq).

Decode: test1 boots → GPIO regulators were the hang; only test2 boots → SCMI mailbox is the hang (upstream-worthy finding); both hang → next initcall_debug photo.

ACPI boot of 7.1.0-glymur-full: ✅ verified (uname -r confirmed) — kernel itself is good; all DT failures are now attributable to the DTB.

## ACPI ground truth (extracted from A16 DSDT, 2026-07-10) — THE method going forward

Jesse's insight: the Windows ACPI tables are the authoritative board wiring list — mine them *first*, guess from CRD *never*. First extraction pass:

**PCIe (confirms the domain-6 theory):** DSDT declares segments 0–7, but `_STA` gates them: PCI4 on `PRP4`, PCI5 on `PRP5`, and **PCI6 returns Zero in BOTH branches — hard-disabled by ASUS.** Segment 6 does not exist on this board, ever. The CRD DTB enabling `pci@1c00000` (domain 6) probes dead silicon → the hang suspect, now corroborated from two independent directions.

**USB:** only ONE dwc3-class controller in the DSDT: `USB3` = `QCOM0FEE`, UID 3 (the multiport @ 0xa400000). Validates disabling the other three dwc3 nodes (test4). `BTAT` = `QCOM0FEA` (Bluetooth attach, likely UART-BT).

**GENI I2C controllers present:** UIDs 1, 6, 9, 10 (IC10), 11 (IC11), 20 (IC20).

**Input devices (corrects the earlier I2C1/6/9 guess in the subsystem table):**
| Device | ACPI bus | Addr | IRQ (GIO0 pin, raw ACPI value) | Trigger |
|---|---|---|---|---|
| Keyboard `ECKB` | **IC20** (UID 0x14) | 0x15 | **0x02C0** | Level, ActiveLow, wake, PullUp |
| Touchpad `ECAP` | **IC11** (UID 0x0B) | 0x17 | **0x03C0** | Edge, ActiveLow, wake, PullUp |
| Touchscreen `TSC1` | (extract bus) | 0x10 | Level, ActiveLow (pin TBD) | |

Note: raw ACPI pin values (0x2C0=704, 0x3C0=960) exceed TLMM pin count — Qualcomm WoA firmware encodes tile/bank offsets in `GIO0` pin numbers. Resolving the ACPI→TLMM formula for Glymur (community solved this per-SoC for X1E) is a to-do before writing the i2c-hid board DTS nodes.

**_DSD device-properties mining (Jesse's grep, 2026-07-10):** the DSDT's ~135 `_DSD` blocks concentrate in: `AUDC` (audio composition + DSP path names: Speaker_With_DSP, HeadsetMic_With_DSP), `QSJ0`/`SH02`/`SJ01` (MIPI SoundWire/SDCA codec descriptors — port configs, control lists, entity IDs → the audio-phase wiring map), and `PRT1`/`RP1` (usb4-host-interface / usb4-port-number → USB4 port mapping). Also verified: Ubuntu-served tables identical to Windows pull (no _OSI games); MCFG declares ECAM for segs 0–7 (seg4=0x780000000 WiFi, seg5=0x7A0000000 NVMe, seg6 declared but _STA-dead); SPCR exists (firmware serial console — earlycon-by-SPCR possible, hardware UART access TBD).

**Division of labor, settled:** DSDT = board truth (what exists, pins, addresses, IRQs). CRD DTS = SoC truth (clocks, interconnects, PHY parameters, power domains — everything Windows hides inside firmware/PEP). The A16 board DTS is the intersection: CRD's SoC plumbing, DSDT's board wiring, nothing that fails both tests.

## Standing reminders
- ACPI test of 7.1.0-glymur-full (regular entry) validates the kernel itself — do before/alongside DT test.
- The stock 7.0.0-27 entry remains the safe boot; never make the DT entry default.
- Record the screen on DT boots. `journalctl --list-boots` after each attempt in case userspace was reached.
