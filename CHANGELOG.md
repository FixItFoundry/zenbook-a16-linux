# Changelog

Dated record of what changed and, where it matters, what turned out to be wrong.
Current status lives in [README.md](README.md) and
[`docs/hardware.md`](docs/hardware.md) — this file is history.

Retractions are kept rather than deleted. Several confident conclusions in this project
were later disproved by measurement, and the record of that is more useful than a tidy
one.

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
