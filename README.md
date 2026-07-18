# Linux on the ASUS Zenbook A16 (Snapdragon X2 Elite Extreme)

Mainline-based Linux bring-up for the **ASUS Zenbook A16 (UX3607OA)** — a Windows-on-ARM
laptop built on the **Qualcomm Snapdragon X2 Elite Extreme**, SoC codename **glymur**
(`sm8750`), Adreno X2 GPU.

> **Status: mostly-working daily driver.** Most of the machine works on a hand-built
> device tree today: keyboard, trackpad, touchscreen, Wi-Fi, USB, audio,
> battery, thermals, NVMe. The two big gaps are **native display (eDP)** and the
> **GPU** — both blocked on Qualcomm kernel support for this SoC that does not exist
> upstream yet. The machine is usable now via the UEFI `simple-framebuffer`.

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

**Current daily-driver device tree: `dts/glymur-a16-test55.dts` (build "test55").**
MDSS disabled, display via `simple-framebuffer`.

### Working on the device tree
- Keyboard (i2c-HID, ASUS EC) + backlight control
- Trackpad (i2c-HID)
- Touchscreen + stylus (i2c `0x10`)
- Wi-Fi — ath12k, associates, SSH reachable
- USB — dwc3 + eUSB2 redrivers (PTN3222 / SMB2370)
- Audio — 4x WSA8845 speakers (confirmed audible) + internal DMIC capture; ALSA/UCM profile
- Battery / charge % — via a reverse-engineered SOCCP GLINK path -> `qcom-battmgr`
- Fan / basic cooling — EC-driven (⚠️ heavy sustained load can still hit the 115 °C trip and protectively shut down; an interim thermal-guard service mitigates it — see docs/ROADMAP.md)
- NVMe — Gen4/Gen5 PHY, boots from internal SSD
- RTC, fastrpc, ADSP (audio control plane)
- Display output — UEFI `simple-framebuffer` (no acceleration).  Watching videos isn't super enjoyable, still a WIP.  simplefb works for now to the best of its ability (yay 18 cores).

---

### Not working yet
- **Native eDP display** — `msm`/DPU binds, reads EDID, then eDP **link training times out (`-110`)**. Top open problem. See [`docs/display-bringup-findings.md`](docs/display-bringup-findings.md).
- **GPU (Adreno X2)** — no `gpu@3d00000` / `gpucc` support for `sm8750` in mainline. Full RE writeup in [`docs/gpu-re/`](docs/gpu-re/).
- **Fn hotkeys** — Fn brightness/media keys aren't wired (brightness itself works in Settings).
- **Camera** — no sensor driver / CCI-CSI device-tree wiring yet.

### Known regression to be aware of
Any device tree with **MDSS enabled + `msm` loaded** currently **kills Wi-Fi** at boot
(garbled console -> black screen, box unreachable). Root cause unconfirmed; likely a shared
power-domain / NoC / SMMU interaction between display bring-up and PCIe/ath12k.
Treat every display-enabled DTB as **diagnostic-only** — do not make it the default boot.

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
- **Building on 7.2 / linux-next** — broke the working chain; stay on v7.1.

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

Bring-up is done against **mainline Linux v7.1**. The build shipped in the images is
**`7.1.0-glymur-clean+`** (v7.1 + patches, with the experimental `msm`/display mapping reverted
for stability).

> **Do not build on 7.2 / linux-next.** A regression somewhere in the 7.2 cycle broke
> the working glymur chain.  At least that's what I think, I started with 7.0.0, then updated
> to 7.1.0 from CodeLinaro, and then tried linux-next 7.2.  The known-good base is **v7.1** plus
> the patches in [`kernel/`](kernel/). See [`kernel/README.md`](kernel/README.md).

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
- **Root cause identified:** the **GPU Clock Controller (`gpucc`)** for `sm8750` is absent
  from mainline. Without it Linux cannot power the GPU block, so any grafted Adreno/GMU node
  triggers an immediate SError.
  ([`gpu-investigation-summary.md`](docs/gpu-re/gpu-investigation-summary.md))
- **Display re-framing (2026-07-15):** the earlier "TrustZone XPU wall" theory was a
  misdiagnosis. The WoA ACPI shows the display path is **normally clock-gated with no secure
  VMID gate**. The real, surviving blocker is the eDP **`-110` link-training** failure
  (DP PHY / panel power sequencing / AUX), not firmware.

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

1. **Kernel** — mainline Linux **v7.1** + the config recipe and patches in [`kernel/`](kernel/).
   The recipe (`boot-kit/scripts/build-kernel-native-full.sh`) starts from a distro config and
   force-enables the glymur boot-critical drivers. See [`kernel/README.md`](kernel/README.md).
2. **Device tree** — build/patch a DTB from [`dts/`](dts/), or use
   [`prebuilt/glymur-a16-test55.dtb`](prebuilt/).
3. **Boot** — via GRUB + `dtbloader`; sample entries in
   [`boot-kit/grub.cfg.laptop.example`](boot-kit/grub.cfg.laptop.example).
   **Every glymur boot cmdline must include `efi=noruntime`** (a missing one causes an
   intermittent early-boot warm reset on this firmware).

Distro installer ISOs: see [`iso/README.md`](iso/README.md).

---

## Credits & license

Builds on mainline Linux, the Linaro/Qualcomm `qcom-next` efforts, and the broader
Snapdragon-on-Linux community (the x1e80100 "hamoa" laptops were the reference skeleton for
much of the glymur bring-up).

Kernel-derived sources (DTS, C, patches) are **GPL-2.0-only**, matching the Linux kernel.
Documentation is provided as-is for research and interoperability. See [LICENSE](LICENSE).

**Disclaimer:** experimental, unofficial, not affiliated with or endorsed by ASUS or Qualcomm.
Running this can leave the machine unbootable until you restore a known-good boot entry.
Proceed at your own risk.
