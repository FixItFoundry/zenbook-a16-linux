# Hardware components — what each one is, how it connects, and where it stands

ASUS Zenbook A16 **UX3607OA** · Qualcomm Snapdragon **X2 Elite Extreme** (`glymur`,
X2E94100, 18 cores) · kernel `7.2.0-rc3` (linux-next lineage) + local patches.

This is the single component reference. For the exact device-tree and kernel changes behind
each "what we changed" line, see [`modifications.md`](modifications.md).

**Reading rule:** every status below is either ✅ working with a check you can run, ⚠️ working
on a workaround, or ❌ not working with the reason. If a claim has no check, treat it as
unverified.

---

## Platform and boot chain

| | |
|---|---|
| SoC | Snapdragon X2 Elite Extreme, `qcom,x2e94100`, 18 cores in 3 clusters of 6 |
| Firmware | INSYDE UEFI (retail `UX3607OA.309`) |
| Boot | GRUB → raw arm64 `Image` + separate DTB via `devicetree` |
| Root | NVMe, `/dev/nvme0n1p17` |

The DTB is **not** supplied by firmware — GRUB loads ours explicitly. This requires
`insmod fdt` emitted at top level; without it every `devicetree` line fails *silently* and the
machine boots the firmware's own DT, which looks like "my changes did nothing."

⚠️ `systemd.mask=dev-tpm*.device` is **required** on the cmdline — without it the boot stalls
~90 s probing a TPM that never answers.

❌ **EFI variable services are unavailable** on this 7.2-rc3 build (`GetVariable` returns
`EFI_UNSUPPORTED`), so `efivarfs` fails and efivars-backed pstore does not exist. Two archived
crash dumps prove variable services *did* work under 7.1 on the same firmware — the regression
is unexplained.

⛔ **ramoops can never capture on this hardware.** DRAM at `0xffc00000` does not survive a
reset — proven with a canary across a clean reboot; the firmware scrubs it. This is why every
post-crash pstore has been empty. Netconsole over the USB-A NIC is the only crash-capture route.

---

## Display — eDP panel ✅

**Chain:** `mdss_dp3` (eDP controller) → eDP PHY → Samsung ATNA33XC20-class panel,
2880x1800 @ 120 Hz, trains at **HBR3**.

Backlight is driven **over DP AUX** (DPCD `0x722`), not a PWM rail — so no PMIC backlight
driver is needed for the internal panel.

**What we changed:** pinned the eDP PHY supply rails `regulator-always-on`
(`vreg_l2f_e1` = `vdda-phy`, `vreg_l4f_e1` = `vdda-pll`). This fixed a hard SoC reset on
display teardown — `qcom_edp_phy_exit()` dropped rails the rest of the block still needed.

```sh
cat /sys/class/drm/card1/card1-eDP-1/status   # connected
ls /sys/class/backlight/                       # dp_aux_backlight
```

⛔ Do not re-derive the eDP elimination list — it is in `internal/edp/`. In particular the old
reasoning "UEFI left `LINK_BW_SET = 0x14` so the firmware's known-good link is HBR3" is
**wrong** (`0x14` is 5.4G; HBR3 is `0x1e`). Why 8.1G works is still unexplained.

## GPU — Adreno X2 ✅

**Chain:** `gpu@3d00000` (Adreno) + `gpucc_glymur` clock controller + GMU firmware
(`gen80100_sqe.fw`), rendering through **Mesa turnip**.

**What we changed:** nothing in the driver. The blocker was our own stale
`modprobe.blacklist=gpucc_glymur` on the cmdline — `gxclkctl` runtime-resumes gpucc at probe,
and without it the Adreno SMMU times out and the entire `msm` component bind fails.

⛔ **Do not start a gpucc decompile.** The drivers are in-tree and work.

Remaining: no zap shader (falls back to `SECVID_TRUST_CNTL`), no hwmon so `nvtop` reports
N/A, and no sustained stress testing.

## HDMI — ⚠️ half working, output still black

**Chain:** `hdmi-connector` ← **Parade PS185 DP→HDMI bridge** (`parade,ps185hdm`, bound to
`simple-bridge`) ← `mdss_dp2` (`af64000.displayport-controller`) ← **`phy@88e1000`**
(`usb_2_qmpphy`, a QMP USB3+DP combo PHY).

★ **Why USB-C DP worked and HDMI did not, from one cause:** `phy@88e1000` has **no DWC3
controller behind it** — the tertiary USB instance does not exist. Both USB-C combo PHYs have a
live controller; every tertiary clock read `en=0`.

**What we changed:** removed the `com_aux` clock reference from `phy@88e1000`.
`gcc_usb3_tert_phy_com_aux_clk` was stuck off, so the PHY failed `-EBUSY` and there was no AUX,
no EDID, zero modes. This is legal because `qmp_combo_clk_init()` uses
`devm_clk_bulk_get_optional()` — an absent clock comes back `NULL` and is skipped.

Result: PHY inits clean, EDID **0 → 512 bytes**, modes **0 → 32**. It also removed a hard
compositor hang.

⛔ **Still black — a second, separate bug.** Nothing delivers **HPD** to `af64000`. The USB-C DP
instances get HPD pushed in by `pmic_glink_altmode → aux_hpd_bridge`; the HDMI instance has no
equivalent, so its HPD register reads 0 forever and the driver tears the mainlink down.

**Four fixes tried, all eliminated** (detail in `DTB_CHANGELOG-internal.md`):

| approach | outcome |
|---|---|
| Move `pinctrl-0` to `&mdss_dp2` | mux applied correctly, still black — ownership is not the variable |
| Mux gpio126 → `gpio` + `hpd-gpios` | failed **and** broke USB-C DP (two variables, ambiguous) |
| Mux gpio126 → `gpio` alone | **USB-C DP never links** — `usb2_dp` is load-bearing |
| `hpd-gpios` alone, mux untouched | pin uncontendable (`.strict` pinmux); **regressed EDID 512 → 0** |

★★ **The open contradiction, fully sourced — this is the question for upstream.** The WoA DSDT
registers TLMM 126 as a GPIO interrupt (`GIO0._AEI`) whose `_EVT` does
`Notify(\_SB.GPU0, 0xD1)` — GPU0 being the display subsystem at MMIO `0x0AE00000`. So *firmware
delivers HDMI HPD as a GPIO interrupt into MDSS.* Yet in Linux, putting that pin in GPIO mode
kills DisplayPort alt-mode on the USB-C ports. Both halves are solid and they conflict. This
needs SoC routing knowledge and should not be inferred further from this end.

⚠️ `/sys/class/drm/card1-HDMI-A-1/status` is **not** evidence of a cable here.

## USB-C, UCSI and DP alt-mode ✅

**Chain:** `pmic_glink` → `ucsi_glink` (PPM) → `typec_mux` → QMP combo PHYs (`fd5000`,
`fde000`) → DP alt-mode; SBU orientation handled in the PHY.

**What we changed:** deleted one DT property. `mode-switch`/`orientation-switch` on the wrong
node stopped the PPM initialising at all.

```sh
ls /sys/class/typec/          # port0 port1
```

## USB4 / Thunderbolt ❌

Three USB4 controllers exist in silicon (`gcc_usb4_{0,1,2}_gdsc`) but **no host-router/NHI node
exists in any in-tree Qualcomm device tree** — upstream has nothing to copy. The binding is an
unmerged **RFC** (Konrad Dybcio, 2025-09-16). The Type-C half of the pipeline works; only the
host router is missing. Nothing to do locally.

⚠️ `usb usb4:` in dmesg is **USB bus 4**, a plain xHCI root hub. Not USB4.

## Wi-Fi and Bluetooth ✅

Wi-Fi 7, Qualcomm **QCC2072** via `ath12k`, on PCIe. Bluetooth is **WCN7850** on a serdev UART.

Needs firmware extracted from the device's own Windows install, plus a forced regdomain (`US`).
Firmware is deliberately **not** shipped in this repo.

**What we changed:** added the WCN7850 Bluetooth serdev node; brought Wi-Fi up through the
`qcom,wcn7850-pmu` power-sequencing binding rather than hand-rolled regulator asserts.

⚠️ Wi-Fi takes up to ~5 minutes to re-associate after resume. "I cannot ssh in" is not evidence
of a crash — judge by `uptime -s`.

## Audio ✅ (with two traps)

**Chain:** ADSP (`remoteproc0`, UEFI-loaded) → AudioReach topology → **4× WSA8845 speaker amps
on SoundWire** + internal DMIC. Speakers are a **4.0 layout** (woofers RL/RR, tweeters FL/FR).

**Two things that both look like "audio is broken":**
1. **ADSP firmware boot race** — check `remoteproc0` state *first*, before suspecting a lost
   patch. This is the usual cause.
2. **The 4.0 layout** — a 2-channel test only drives the tweeters. Needs a 4-channel upmix
   (WirePlumber) or the woofers stay silent.

❌ **Headphone jack** — jack detect exists, but there is no rx-macro/WCD9395 codec node in the
DT yet. ❌ **DisplayPort audio** — backends exist but are not wired up.

## Battery, charging and USB-PD ✅

**Chain:** `soccp_glink` (custom battery driver, now built in-tree) + `qcom-battmgr` +
`ps883x` PD controller. Battery, Type-C/UCSI and DP alt-mode **all hang off one glink edge** and
fail *silently together* — if several of them break at once, check the transport first.

**What we changed:** the SOCCP is UEFI-loaded and already running, so the DT must not try to
boot it; `&remoteproc_soccp` is deliberately omitted.

⚠️ **`qcom-battmgr-ac/online = 0` is CORRECT.** Its `type` is `Mains` — a barrel-jack rail this
laptop does not have. It charges over USB-C PD. Read `qcom-battmgr-usb/online` instead.
⚠️ Battery `capacity` reads **empty**; only `energy_now`/`energy_full` are valid.

## Input ✅

Keyboard is I2C-HID `0B05:4B42` behind an **ASUS vendor HID handshake**. Touchpad, touchscreen
and stylus are I2C-HID. Lid switch is **TLMM GPIO 92**, active-low, recovered from the WoA DSDT
(requires freeing pin 92 from `gpio-reserved-ranges`).

**What we changed:** a `hid-asus` patch mapping the vendor usages — `0x85 → KEY_CAMERA`,
`0x86 → KEY_PROG1`, `0x5f → KEY_PROG2`, plus `QUIRK_FILTER_CAMERA_COMPANION` for a companion
byte that otherwise dims the panel. Mapping is Konrad Dybcio's; see `UPSTREAM-CREDITS.md`.

Keyboard backlight works **steady-on at max** via a userspace hidraw script. ❌ It is **not
dimmable** — the A16 device entry lacks `QUIRK_USE_KBD_BACKLIGHT`, so there is no
`asus::kbd_backlight` LED and the Fn illumination keys land nowhere. This is a one-line fix
nobody has made.

## CPU frequency scaling ✅

**Chain:** SCMI over a shared-memory mailbox to the PDP0/CPUCP firmware → `scmi-cpufreq` →
three performance domains.

```
policy0   cpus 0-5    355 MHz - 3.61 GHz   20 OPPs
policy6   cpus 6-11   355 MHz - 4.45 GHz   21 OPPs
policy12  cpus 12-17  355 MHz - 4.45 GHz   21 OPPs
```

**What we changed — one DT property.** `scmi-cpufreq` had probed `-110` (`-ETIMEDOUT`) for the
project's entire life. Root cause, measured with SCMI RAW: **the firmware answers protocol 0x13
(Performance) in shared memory but never rings the mailbox doorbell for it.** The doorbell IRQ
counter does not move for 0x13 at all. Fix: `arm,no-completion-irq` on the `scmi` node, which
makes the SCMI core poll instead of waiting.

⛔ **Two log lines look like failures and are not:** `Failed to query supported version for
protocol 0x13` (the firmware does not implement `0x13/0x0`; the kernel falls back) and
`Failed to get FC for protocol 13` (Fast Channels are optional).

⚠️ **Unexplained:** the table tops out at 4.45 GHz, not the X2 Elite's rated ~5 GHz boost bin.
The Fast-Channel theory is plausible and **untested** — do not repeat it as cause.

## Thermal ✅

41 `cpu*`/`cpullc*` zones bind the `cpufreq-cpu0/6/12` cooling devices; actuation confirmed by
stepping `emul_temp` across the 95 °C passive trip and watching `cur_state` go 0→1→2→3.

⛔ **`emul_temp` ≥ the critical trip (115000) POWERS THE MACHINE OFF** immediately — the thermal
core calls `hw_protection_shutdown`. Test at 96000 and always restore 0.

⛔ **Do not reinstall `glymur-thermal-guard`.** That userspace service was removed 2026-07-31.
Across 62 retained boots it logged 33,048 errors and **zero** throttle events — it wrote to a
`scaling_max_freq` that did not exist while cpufreq was dead. The claim that it held an 18-core
load at ~70 °C is **retracted**; whatever stopped the thermal shutdowns was never isolated.

## Fan and the Embedded Controller ⚠️ read-only

**Chain:** EC on **`/dev/i2c-9` at address `0x76`**, subdevice `0x5b`. RPM is read with the
DSDT's `RECM` command (`0x52`, raw I2C, **no SMBus count byte**), combining
`0x0603 << 8 | 0x0602` exactly as `\_SB.FAN0.GCFR` does.

Validated against load: 2340 RPM @ 44 °C idle → 2940 RPM @ 73 °C on 18 busy cores → back down.

The fan is otherwise **EC/BIOS-autonomous** — Linux does not drive it.

⛔ **Nothing writes to this EC.** The block protocol (ECRB/ECWB on `0x5b`, WEBC/REBC on `0xC9`,
fan-curve selectors) is fully decoded and `SUFC` is **deliberately not implemented**. This EC
also owns **charging**. Ask before any write.

⚠️ The old "blocked on an SSDT re-dump" premise was **wrong** — `FAN1` is external and unused;
`FAN0` was in the DSDT the whole time.

## SPMI / secondary PMICs ❌ — one bottleneck, two features

Secondary PMICs fail to probe over SPMI (`pmic-spmi … error -5`,
`pmic_arb_wait_for_done: transaction failed`). This single failure blocks **both**:

1. `qcom-spmi-temp-alarm` — the PMIC temperature alarm never registers, and
2. the PMIC PWM (`pmh0101`/`pm8350c`) that drives the **fan** — so `/sys/class/pwm` is empty
   and Linux can never spin it as a proper `pwm-fan` cooling device.

Fixing the SPMI arbiter probe unlocks both. There is likely relevant in-kernel 7.x SPMI work to
pull in.

## Suspend / resume ⚠️ works on a workaround

**Root cause, isolated 2026-07-30: PCI config-space access during `dpm_suspend_noirq()`
hard-resets the SoC.** Both paths inside `pci_pm_suspend_noirq()` are *independently* lethal —
`pci_save_state()` (reads) and `pci_prepare_to_sleep()` (write/D-state). Driver `noirq`
callbacks are innocent. **Any single PCIe device** doing its noirq suspend is sufficient.

⛔ **It is not our device tree.** The bare upstream A16 DT crashes identically, same kernel and
cmdline, DTB the only variable. Suspend is simply not working on glymur upstream; a real fix
likely needs a firmware revision.

**Workaround:** `glymur_pci_skip=5` on the cmdline (skip both config-space paths). Because PCI
devices then never save state or change D-state, **they stay powered through suspend** — it
sleeps, but saves less power than a correct implementation. **Suspend draw has never been
measured.**

⚠️ Snapdragon does not implement S3/`deep`; `s2idle` is the only viable mode and is forced via
`/etc/tmpfiles.d/glymur-s2idle.conf`. Hibernate is masked deliberately — no RTC wake alarm
(`qcom,no-alarm`).
⚠️ **Wake with the lid.** `HandlePowerKey=poweroff` turns a wake attempt into a fake failure.

Ruled out by test, not argument: PME wakeup arming, D3cold, any D-state change, the PCIe
controller being runtime-suspended, the GPU, and `bam_dma`/`pcie-qcom`/`geni_i2c`/`qcom-ipcc`/
genpd power-off/`simple-pm-bus` — individually **and all five combined**.

## Storage, RTC ✅

NVMe root on PCIe. RTC is the PMIC RTC — enabled, but **read-only**; `qcom,uefi-rtc-info` is
deliberately removed from the DT.

## Camera ❌ — not started, and expensive

There is **no `camcc-glymur.c`** (only `camcc-kaanapali.c`, the sibling SoC), and
`drivers/media/platform/qcom/camss/` has **zero** support for this SoC generation — the same is
true on X1 Elite. Bringing it up means a camera clock-controller driver, CAMSS for a new
generation, CCI/CSI wiring, and a sensor driver. Scope this in months, not days.

---

## Status at a glance

| Component | State |
|---|---|
| eDP panel + backlight, GPU, Wi-Fi/BT, audio (speakers + DMIC), battery/PD, input, NVMe, RTC, cpufreq, thermal | ✅ working |
| Fan | ✅ RPM readback only — no control |
| Suspend | ⚠️ works on `glymur_pci_skip=5`; long-sleep stability unmeasured |
| HDMI | ⚠️ PHY fixed, EDID + 32 modes — output still black (HPD) |
| Headphone jack, DP audio, dimmable kbd backlight, `qcom-spmi-temp-alarm` | ❌ known cause, unfixed |
| USB4, camera | ❌ blocked upstream / not started |
