# Linux on the ASUS Zenbook A16 (Snapdragon X2 Elite Extreme)

Mainline-based Linux bring-up for the **ASUS Zenbook A16 (UX3607OA)** — a Windows-on-ARM
laptop built on the **Qualcomm Snapdragon X2 Elite Extreme**, SoC codename **glymur**
(`sm8750`), Adreno X2 GPU.

> **Status: mostly-working daily driver.** Most of the machine works on a hand-built
> device tree today: keyboard, trackpad, touchscreen, Wi-Fi, USB, audio,
> battery, thermals, NVMe.
>
> **2026-07-24 — native eDP now works.** The panel is driven by the real DPU
> (`fb0 = msmdrmfb`, 2880x1800@120, `dp_aux_backlight`), not the UEFI
> `simple-framebuffer`. Link training completes at **HBR3 (8.1 Gbps × 4 lanes)**; the
> long-standing `-110` failure is gone. Two bugs had to be peeled to get there and one
> of them is a generic upstream `msm` bug — write-up in
> [`docs/edp-hbr3-linkup.md`](docs/edp-hbr3-linkup.md).
>
> ## 🎉 2026-07-29 — the GPU works, and everything works *at the same time*
>
> There is now a single **merged device tree** on which the display, its power-down path,
> **Wi-Fi, battery, Type-C/DisplayPort-alt-mode, the keyboard, audio and the Adreno X2 GPU
> all work together**:
>
> ```
> GPU0:  deviceName = Adreno (TM) X2-85     driverName = turnip Mesa driver
>        [drm] Loaded GMU firmware v5.2.38   gpucc: 25 clocks
> ```
>
> Video renders on the GPU and `nvtop` shows GPU processes and memory in use. Frequency
> scaling is live (`simple_ondemand`, 310 MHz idle → 1.85 GHz across 12 OPPs).
>
> **The merged tree is built on [Konrad Dybcio](https://konradybcio.pl/)'s upstream A16
> device tree** (posted 2026-07-21, still unmerged) with our fixes layered on top — see
> [UPSTREAM-CREDITS.md](UPSTREAM-CREDITS.md).
>
> **The GPU was blocked by one of our own debugging workarounds.** A
> `modprobe.blacklist=gpucc_glymur` guard, added long ago for the very first (then-risky)
> gpucc probe, was never removed. Because `gxclkctl` runtime-resumes gpucc at probe, that
> stale token cascaded into the Adreno SMMU timing out, adreno failing `-19`, and — since
> `msm` is a component framework — the **entire DRM device** failing to bind. It presented
> as a black screen, and got "fixed" for months by disabling the GPU nodes.
>
> Remaining gaps: **USB4** (binding is an unmerged upstream RFC), **camera**, and no
> sustained GPU stress testing yet. **Suspend now works** (2026-07-30) but on a
> workaround that needs a firmware revision to become a real fix — see below.

 **I'm publishing this repo to ask for the community's help.**  I've been tinkering with
 Linux and OSX (Hackintoshes) for almost two decades, and I wanted to test out some frontier
 AI, their reasoning, limits, and compare different models.  I specifically bought one month
 of Claude MAX for Fable 5 and Opus 4.8, and I have a gemini subscription as the added Youtube
 and Google Drive (3-2-1 offsite), as well as easy integration for AI tools within the google
 ecosystem.  Aside from that, I have a swarm of hermes-agents throughout my homelab, using local
 models from old hardware, combined with some free tier cloud model use.  I acknowledge that AI
 also isn't going anywhere, so I'm learning how to...harness it for productivity and automation.
 It'll be a helpful workplace skill to have.
 

 If you know the Adreno/DPU/clock-controller stack, **your review and patches are wanted.**
 If you are an actual Kernel Engineer, I welcome you to validate this work.  It was done based
 on years of playing around, and, once again, heavily assisted by AI.  The goal here is to have
 something the community can build on.  These laptops and this SoC are not going anywhere, even
 if they're delayed by the RAMpocalypse.
 See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## ⚠️ Please read:

**This project was heavily AI-assisted, and I am not a kernel developer.** I want to be VERY
clear about this.  I'm a hobbyist who can only stomach Windows during the work week, and I
bought this laptop because I'm a firm believer in ARM as the future of mobile computing.  Even
on Windows, this laptop is GREAT.

- A large amount of the analysis, device-tree bisection, reverse-engineering, and the writeups
  in this repo were produced **with AI assistance** (and then tested on real hardware). The AI
  was wrong plenty of times along the way — see [`docs/THINGS_TRIED.md`](docs/THINGS_TRIED.md).
- **YOUR MILEAGE MAY VARY:**  These are the things that worked on my specific device.  It's stable
  90% of the time, and I'm not done working on it myself.  Register addresses, StreamIDs, and
  root-cause theories are RE'd and experimental.
- I'm publishing anyway because (1) the machine is genuinely usable today and I
  want others to be able to share that, and (2) I'd love people who *actually* know this stack
  to validate it, correct me, and push it further.

Again, if you're an expert and something here is wrong or dangerous, please open an issue — I will
take the correction gladly.  I, and I'm sure a few others, would love community support in making
this durable!

This was a fun adventure so far, and I want to keep working at it.  I learned a lot during the process,
it's really piqued my interest in diving into Kernel Engineering, and the intricacies of it.  Updates will
continue as long as there are stable breakthroughs.

---

## What works / what doesn't

**Current device tree: [`dts/glymur-asus-zenbook-a16-ux3607oa-merged.dts`](dts/glymur-asus-zenbook-a16-ux3607oa-merged.dts)**
— [Konrad Dybcio](https://konradybcio.pl/)'s upstream A16 board file plus our fixes, on
`7.2.0-rc3`. Display + power-down, Wi-Fi, battery, Type-C, keyboard, audio and the Adreno X2
GPU all together.

(`dts/test68.dts` is the previous v7.1 vendor-lineage daily driver — native eDP, lid switch,
USB-C DP alt-mode, but no GPU. `test55` was the original `simple-framebuffer` baseline.)

### Working on the device tree
- Keyboard (i2c-HID, ASUS EC) + backlight control
- Trackpad (i2c-HID)
- Touchscreen + stylus (i2c `0x10`)
- Wi-Fi — ath12k, associates, SSH reachable
- USB — dwc3 + eUSB2 redrivers (PTN3222 / SMB2370)
- **Audio — working, and the long-standing "sometimes silent after boot" bug is FIXED (2026-07-29).** 4x WSA8845 speakers + internal DMIC capture. The intermittency was never the ADSP or the topology: `glymur-audio-route.service` (system) raced `wireplumber` (user), and whichever won decided whether you had sound. Fixed with a bounded ordering guard plus re-applying the route after the sink appears — validated across four boots.
  ⚠️ 4.0 layout, woofers on RL/RR — always test with `speaker-test -c 4`; 2 channels only drives the tweeters. Full write-up and the two boot traps: [`docs/audio-adsp-boot-ordering.md`](docs/audio-adsp-boot-ordering.md).
- **Bluetooth — working (2026-07-29).** WCN7850 BT over UART14 (`hci0`, `hci_uart` + `btqca`). Konrad's tree enables the UART and wires it into the connector graph but declares no serdev child, so nothing probed a controller — there was no Bluetooth entry in `rfkill` at all. Adding a `qcom,wcn7850-bt` node under `&uart14`, consuming the `wcn7850-pmu` rails we already add for Wi-Fi, brings it up.
- **USB-C DisplayPort alt-mode — confirmed working on BOTH USB-C ports.** External monitor over either port, plus UCSI, PD negotiation, orientation detection and alt-mode discovery (`/sys/class/typec/`). See [`docs/usb-c-ucsi-dp-altmode.md`](docs/usb-c-ucsi-dp-altmode.md).
- **Lid switch** — TLMM GPIO 92, recovered from the Windows-on-ARM ACPI DSDT; `SW_LID` registers and `logind` reads it.
- **GPU — Adreno X2, working (2026-07-29).** `adreno` binds, GMU firmware v5.2.38 loads, the dedicated `adreno_smmu` comes up (SMMUv2, 25 context banks), and Mesa's **turnip** Vulkan driver enumerates the device. Video renders on it; `nvtop` shows GPU processes and memory. Frequency scaling live via devfreq (`simple_ondemand`, 310 MHz → 1.85 GHz, 12 OPPs). Requires `&gpu`/`&gmu` enabled **and** `gpucc_glymur` *not* blacklisted on the cmdline.
- **`gpucc` (GPU clock controller)** — 25 `gpu_cc` clocks, `gpu_cc_pll0` at 1.15 GHz. Present in mainline v7.1 as `drivers/clk/qcom/gpucc-glymur.c`.
- Battery / charge % — via a reverse-engineered SOCCP GLINK path -> `qcom-battmgr`
- Fan / basic cooling — EC-driven (⚠️ heavy sustained load can still hit the 115 °C trip and protectively shut down; an interim thermal-guard service mitigates it — see docs/ROADMAP.md) UPDATE 7-24-26:  This isn't really an issue after stress testing throughout the week, but something I encoutered early on, and felt it important to mention.
- NVMe — Gen4/Gen5 PHY, boots from internal SSD
- **RTC** — `/dev/rtc0` exists and counts, as of **2026-07-30**. ⚠️ This line previously
  claimed a working RTC and that was wrong: before that date `rtc-pm8xxx` deferred forever and
  there was no `/dev/rtc0` at all. Three caveats even now — it is **read-only**
  (`RTC_SET_TIME` → `ENODEV`), it has **no wake alarm** (`qcom,no-alarm`, so hibernate still
  has nothing to arm), and its counter is **free-running rather than a wall clock**, so the
  epoch offset is supplied from userspace by `glymur-rtc-restore`
  (see [`LOCAL-TWEAKS.md`](LOCAL-TWEAKS.md) §9).
- fastrpc, ADSP (audio control plane)
- **Native eDP display** — DPU-driven panel at 2880x1800@120, 30 bpp, `fb0 = msmdrmfb`, backlight over DP AUX. Needs a patched `msm` and the eDP device tree — see [`docs/edp-hbr3-linkup.md`](docs/edp-hbr3-linkup.md). Still no GPU, so there is no 3D acceleration behind it.
- Display output (fallback) — UEFI `simple-framebuffer`, no acceleration. What everything before 2026-07-24 ran on.

---

### Not working yet
- **GPU — partially characterised, not fully instrumented.** The GPU *works* (see above), but: `nvtop`/`btop` report Memory/Temp/Power as **N/A** — an integrated Adreno has no dedicated VRAM, there is no hwmon node on the GPU device, and no power sensor. The temperatures *do* exist as 14 thermal zones (`gpu-0-0` … `gpu-3-2`, `gpuss-0/1`) under `/sys/class/thermal/`, which simply is not where those tools look. **No zap shader** (falls back to `SECVID_TRUST_CNTL`). **No sustained stress testing yet.** Also: Mesa names the device "Adreno X2-85" and this build contains no X2-90 string at all, while our chipid `0x44070041` matches none of the three kernel `a8xx` catalog entries exactly — likely an unmapped SKU/revision.
- **Suspend / resume — ⚠️ works, on a workaround (2026-07-30).** Closing the lid sleeps the machine and opening it wakes it, verified over three cycles. Stock, it hard-resets the SoC with no fault of any kind. Root cause: **PCI config-space access during `dpm_suspend_noirq()` resets this SoC**, with the read (`pci_save_state()`) and write (`pci_prepare_to_sleep()`) paths *independently* lethal and driver noirq callbacks innocent — a single PCIe device performing its noirq suspend is sufficient. **This reproduces on the bare upstream A16 device tree**, so it is a platform gap rather than a defect in ours. The workaround skips both config-space accesses, which means PCI devices stay powered through suspend: it sleeps, but saves less power than a correct implementation, and **a firmware revision is needed for a real fix**. It lives on its own GRUB entry.


⚠️ **Correction (2026-07-30, later the same day):** do not treat "this firmware does not support EFI variable services" as settled. Two archived `efi_pstore` crash dumps prove variable services **worked** on this same machine and firmware under 7.1 kernels. The `EFI_UNSUPPORTED` result above is real but is specific to our 7.2-rc3 build, and the cause is **unresolved**. See [`docs/crash-evidence.md`](docs/crash-evidence.md).
- **USB4 / Thunderbolt** — no host-router/NHI node exists in any in-tree qcom device tree, and `drivers/thunderbolt` has no Qualcomm support. The binding is an unmerged upstream **RFC**. The Type-C half of the pipeline (UCSI → typec_mux → QMP PHY) now works; only the host router is missing. See [`docs/usb-c-ucsi-dp-altmode.md`](docs/usb-c-ucsi-dp-altmode.md).
- **cpufreq scaling** — `scmi-cpufreq -110`, cores pinned at boot clock; interim thermal-guard service mitigates.
- **Fn hotkeys** — Some Fn keys aren't wired, but as of 7-24 update, we just need Fn Lock, KB Brightness, Microphone Mute (just the LED on KB), Camera, and the two ASUS buttons.  Asus Buttons do map though. 
- **Camera** — no sensor driver / CCI-CSI device-tree wiring yet.
- **Dimmable keyboard backlight** — no `asus::kbd_backlight` LED; the A16 entry lacks `QUIRK_USE_KBD_BACKLIGHT`.
- **Headphone jack / DP audio**, **`qcom-spmi-temp-alarm`**.

### Known regression to be aware of
**Retired 2026-07-20.** "MDSS enabled + `msm` loaded kills Wi-Fi" no longer reproduces —
it was a load-ordering problem with `ath12k`, not a power-domain/NoC/SMMU interaction.
In the test58 log Wi-Fi associates at t+29.4 s with no `ath12k` errors while `msm` binds
at t+83.5 s. Display-enabled DTBs no longer have to be treated as diagnostic-only.

Caveat when judging this yourself: a USB Ethernet dongle (`r8153_ecm`) holds the default
route at metric 100 versus Wi-Fi's 600, so a surviving SSH session is **not** evidence
that Wi-Fi is healthy.

---

## Things tried that did NOT work (dead-ends / open failures)

A condensed list so contributors do not re-run known-bad experiments. Full detail in
[`docs/DTB_CHANGELOG.md`](docs/DTB_CHANGELOG.md) and [`docs/THINGS_TRIED.md`](docs/THINGS_TRIED.md).

- **test58 (FAILED)** — display-attack DTB (`x1e80100-asus-vivobook-s15` base + `mdss`/`dispcc`/`mdss_dp3` = okay). Did not bring up native display; recorded here as tried, to be revisited.
- **`video=simplefb:off` / forced `video=eDP-1:...` modeset** — MDSS GDSC power-cycle -> warm reset. Keep simplefb alive; do not force a resolution.
- **msm_gem CMA rewrite** — abandoned; solved the wrong problem (SMMU translation was never the fault).
- **Grafting hamoa (x1e) GPU/GMU/IOMMU nodes without `gpucc`** — immediate SError (~0.3s) from unclocked register access.
- **Gunyah/hypervisor "handshake" emulation for GPU** — dead-end; the GPU is driven natively by Windows, not behind a Gunyah VMID.
- **100 kHz I2C for the EC keyboard bus** — regressed vs 400 kHz (GENI master command timeout).
- ~~**Building on 7.2 / linux-next** — broke the working chain; stay on v7.1.~~
  **Retired 2026-07-30.** The daily driver is now **7.2.0-rc3**; see *Kernel base*.

---

## Hardware

| | |
|---|---|
| **Model** | ASUS Zenbook A16, UX3607OA |
| **SoC** | Snapdragon X2 Elite Extreme, `glymur` (`sm8750`) |
| **GPU** | Adreno X2-90 (X2-45 / X2-85 / X2-90 class), `QCOM0F36` @ `0x03D00000` |
| **Panel** | Samsung ATNA60HR07, 2880x1800, 60/120 Hz, 10bpc (eDP) |
| **Wi-Fi** | Qualcomm QCC207x (ath12k) |
| **Audio** | 4x WSA8845 smart speakers (SoundWire) + DMIC array, LPASS/AudioReach |
| **Firmware** | Retail Windows-on-ARM UEFI (locked; no engineering unlock) |

Full register/bus map: [`docs/HARDWARE_MAP.md`](docs/HARDWARE_MAP.md).

---

## Kernel base

**The daily driver is `7.2.0-rc3` (updated 2026-07-30).** Display, GPU, Wi-Fi, battery,
Type-C/DP alt-mode, keyboard, audio and — since 2026-07-30 — suspend all work on it.

> **The old "do not build on 7.2 / linux-next" warning is retired.** It read: *"A regression
> somewhere in the 7.2 cycle broke the working glymur chain."* That was an honest reading at
> the time, but it was wrong about the cause. What actually broke was our **device tree**, not
> the kernel — a vendor-derived DTB lineage that had accumulated assumptions the newer tree no
> longer matched. Rebasing onto Konrad Dybcio's upstream A16 DTS made 7.2 work, and several
> things that had been blamed on the kernel (the display teardown crash among them) turned out
> to live in that DT. Kept here rather than deleted, because "our own workaround outlived its
> evidence" is the single most repeated lesson in this project.

**v7.1 remains a supported fallback.** `7.1.0-glymur-clean+` / `7.1.0-glymur-gdsc1` still boot
and still have a GRUB entry; the 7.1 patch set is in [`kernel/`](kernel/). Use it if you want
the vendor-lineage DTB, or to reproduce anything dated before 2026-07-28.

⚠️ One caveat inherited by 7.2: **suspend needs a workaround.** Stock, s2idle hard-resets the
SoC — see *Not working yet* and `docs/hardware-status.md`. It reproduces on the upstream A16 DT,
so it is a platform gap rather than something the kernel base choice fixes.

---

## The GPU / display reverse-engineering effort

Because upstream has no Adreno X2 or DPU support for `sm8750`, the Windows-on-ARM stack was
reverse-engineered to recover the hardware ground truth:

- **ACPI dump** (IORT / DSDT / SDEV) -> authoritative SMMU StreamIDs and register bases.
  GPU sits behind a **dedicated `adreno_smmu` @ `0x03DA0000`**, register base `0x03D00000` —
  **matching x1e80100 upstream**, so routing is *not* the blocker.
  ([`gpu-smmu-routing-from-woa-acpi.md`](docs/gpu-re/gpu-smmu-routing-from-woa-acpi.md))
- **Ghidra RE of `qcdxkm8480.sys`** (Windows WDDM driver) -> GPU identity, firmware blob
  names, and candidate `gpucc` clock-controller register offsets.
  ([`gpucc-clock-registers.md`](docs/gpu-re/gpucc-clock-registers.md))
- ⛔ **"Root cause: `gpucc` is absent from mainline" — this was WRONG, twice over, and is
  retired.** `drivers/clk/qcom/gpucc-glymur.c` has been in mainline v7.1 all along (618
  lines, compatible `qcom,glymur-gpucc`), the a8xx Adreno driver was already compiled into
  our `msm.ko`, the catalog entry existed, and the firmware was already on the box. **There
  was almost nothing to reverse-engineer.** The abandoned RE stub (`gpucc-x2.c`) was 126
  lines of `TODO`s reimplementing a driver that shipped.
- ✅ **The actual blocker, found 2026-07-29: our own `modprobe.blacklist=gpucc_glymur`.**
  `gxclkctl-kaanapali` lists gpucc as a power-domain provider and runtime-resumes it at
  probe; with gpucc blacklisted that provider never appeared, the resume timed out `-110`,
  the Adreno SMMU went with it, adreno failed `-19`, and because `msm` is a *component*
  framework the whole DRM bind failed — a black screen, repeatedly "fixed" by disabling the
  GPU nodes. Dropping one stale cmdline token and enabling `&gpu`/`&gmu` brought the GPU up.
  **The lesson we would pass on: audit your own debugging workarounds as ruthlessly as you
  audit the hardware.**
- **Display — SOLVED 2026-07-24.** The "TrustZone XPU wall" theory was a misdiagnosis
  (the WoA ACPI shows the display path is normally clock-gated, with no secure VMID
  gate), and so was blaming the DP PHY. The panel was dark for three stacked reasons,
  each fully masking the next: a `dispcc` `clocks[]` indexing error in our device tree
  that orphaned the DP3 link clocks and oopsed the kernel; a generic upstream `msm` bug
  that made the eDP 1.4 `LINK_RATE_SET` path dead code; and the fact that **5.4 Gbps is
  simply not a working operating point on this panel** — it trains at **HBR3**. The eDP
  PHY driver needed no changes at all.
  ([`docs/edp-hbr3-linkup.md`](docs/edp-hbr3-linkup.md))

> These docs contain addresses, StreamIDs, and register maps **derived** from proprietary
> Qualcomm/ASUS firmware and Windows drivers. The binaries themselves are **not** redistributed
> here (see [`firmware/README.md`](firmware/README.md)). This is interoperability research.

---

## Repository layout

```
dts/            Device-tree sources (test55 = daily driver; test47/58 diagnostic)
prebuilt/       Prebuilt DTB for the daily driver
boot-kit/       Build/patch/deploy scripts + example GRUB config
kernel/         Kernel build recipe, config fragment, patches, gpucc stub, fork-push script
docs/           Full changelog, hardware map, display + GPU-RE findings, analysis logs
iso/            Reproducible aarch64 installer-ISO build scripts (Arch / Fedora / Ubuntu)
firmware/       What firmware is needed and why it is NOT included
```

---

## Building & booting (short version)

1. **Kernel** — mainline Linux **v7.2-rc3** (or **v7.1** as a fallback) + the config recipe
   and patches in [`kernel/`](kernel/).
   The recipe (`boot-kit/scripts/build-kernel-native-full.sh`) starts from a distro config and
   force-enables the glymur boot-critical drivers. See [`kernel/README.md`](kernel/README.md).
2. **Device tree** — build/patch a DTB from [`dts/`](dts/), or use
   [`prebuilt/glymur-a16-test55.dtb`](prebuilt/).
3. **Boot** — via GRUB + `dtbloader`; sample entries in
   [`boot-kit/grub.cfg.laptop.example`](boot-kit/grub.cfg.laptop.example).
   ⚠️ **`efi=noruntime` was retired on 2026-07-30 and is no longer recommended.** This
   README used to call it mandatory. That claim did not survive testing on the merged
   7.2 tree — see [`docs/DTB_CHANGELOG.md`](docs/DTB_CHANGELOG.md). Older entries and
   the archived docs still carry it; that is history, not guidance.

Distro installer ISOs: see [`iso/README.md`](iso/README.md).

---

## Credits & license

**→ [UPSTREAM-CREDITS.md](UPSTREAM-CREDITS.md) names every upstream author whose work this
tree carries, with the patch and message-id it came from.** Anything adopted from upstream is
credited there and is never presented as ours.

**The merged device tree this project now runs on is [Konrad Dybcio](https://konradybcio.pl/)'s.**
He posted upstream device-tree support for this exact laptop (UX3607OA) on 2026-07-21
(reviewed by Dmitry Baryshkov and Abel Vesa, still unmerged), along with the A16 keyboard
support we use. Our tree is his board file with our fixes layered on top: the pin map, the
regulator topology, the WCN and USB wiring, gpio-keys, and the GPU/CDSP/SOCCP nodes are his
work. His DT is also what proved our long-hunted display power-down reset was a device-tree
defect on our side rather than silicon — same kernel, same `msm`, only the DTB swapped, and
his survived where ours did not. Thank you.

glymur display and eDP PHY v8 support are **Abel Vesa**'s.

Builds on mainline Linux, the Linaro/Qualcomm `qcom-next` efforts, and the broader
Snapdragon-on-Linux community (the x1e80100 "hamoa" laptops were the reference skeleton for
much of the glymur bring-up).

Kernel-derived sources (DTS, C, patches) are **GPL-2.0-only**, matching the Linux kernel.
Documentation is provided as-is for research and interoperability. See [LICENSE](LICENSE).

**Disclaimer:** experimental, unofficial, not affiliated with or endorsed by ASUS or Qualcomm.
Running this can leave the machine unbootable until you restore a known-good boot entry.
Proceed at your own risk.
