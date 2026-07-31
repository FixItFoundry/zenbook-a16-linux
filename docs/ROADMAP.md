# Roadmap & known-not-working

This is a **semi-working** bring-up of Linux on the ASUS Zenbook A16 (UX3607OA, Snapdragon
X2 Elite / `glymur` / sm8750). Lots works; several things don't yet. Contributions and expert
eyes are very welcome — see `CONTRIBUTING.md` and open an Issue/Discussion.

**Last updated 2026-07-31.** Where this file and `hardware-status.md` disagree, that one wins —
it carries a reproducible check next to every claim.

## Working
- Boot to desktop (systemd-boot, raw arm64 Image + DTB) on Arch/Manjaro-KDE, Ubuntu, Fedora.
- Keyboard, trackpad, touchpad, keyboard backlight (steady, via `asus-kbd-init`).
- USB-C + USB-A (incl. USB NIC), USB storage, RTC.
- Wi-Fi 7 (Qualcomm QCC2072, ath12k) — with correct firmware + a forced regdomain.
- Battery percentage + USB-PD charging (`soccp_glink` + `ps883x`).
- Audio: speakers (4.0, woofers + tweeters via AudioReach topology + WirePlumber upmix) and
  the internal DMIC. See `../LOCAL-TWEAKS.md`.
- **Native eDP** at 2880x1800@120 over the real DPU, backlight over DP AUX (2026-07-24).
- **Adreno X2 GPU** under Mesa turnip — real 3D acceleration, not software rendering (2026-07-29).
- **Suspend / resume**, on the `glymur_pci_skip=5` workaround (2026-07-30).
- **CPU frequency scaling** (2026-07-31) — see below.

## Not working yet / help wanted

### Thermal `cooling-maps` — HIGH IMPACT, and now the top item
**CPU frequency scaling works as of 2026-07-31**: three SCMI performance domains,
`scaling_driver = scmi`, `governor = schedutil`, cpus 0-5 at 355 MHz–3.61 GHz and cpus 6-17 at
355 MHz–4.45 GHz. It had failed `-110` until then because the PDP0/CPUCP firmware answers SCMI
protocol 0x13 in shared memory but **never rings the mailbox doorbell**; the fix is one DT
property, `arm,no-completion-irq`, which makes the SCMI core poll. See `power-and-thermal.md`.

That fix also made the kernel create `cpufreq-cpu0/6/12` cooling devices on its own — **but no
thermal zone binds them yet.** So Linux has cooling *capability* and no cooling *actuation*.
The remaining work is DT `cooling-maps` tying those cooling devices to *passive* trips, plus a
working fan (see SPMI below). Until then the CPU is backstopped only by the 101 critical trip
points and the EC/BIOS-autonomous fan.

⚠️ **Two corrections to what this section used to say.** First, it recommended an interim
userspace **thermal guard** and credited it with holding an 18-core load at ~70 °C. That service
was **removed on 2026-07-31 and the claim retracted** — across 62 retained boots it logged
33,048 errors and **zero** throttle events, because it wrote to a `scaling_max_freq` that did not
exist while cpufreq was dead. Whatever stopped the thermal shutdowns is unknown. Do not
reinstall it; see `../LOCAL-TWEAKS.md` §6 and `../tweaks/retired/`.

Second, the perf table topping out at **4.45 GHz** rather than the X2 Elite's rated ~5 GHz boost
bin is still unexplained. The old guess that this is a Fast Channel gap is plausible but
untested — the FC absence (`Failed to get FC for protocol 13 … Using regular messaging`) is real
and benign, but nothing has actually confirmed it is what hides the boost bin.

Also retired: "UI sluggishness is from software rendering (no GPU)". The GPU works now.

### SPMI PMIC-arb — gates the fan AND the thermal alarm — HIGH IMPACT
Secondary PMICs fail to probe over SPMI (`pmic-spmi … error -5`; `pmic_arb_wait_for_done:
transaction failed`). This one bottleneck blocks **both**: (1) `qcom-spmi-temp-alarm` (the PMIC
temperature alarm never registers), and (2) the PMIC PWM (`pmh0101`/`pm8350c`) that drives the
**fan** — so `/sys/class/pwm` is empty and Linux can't spin it. Fixing the SPMI arbiter probe
should unlock the temp alarm, the fan PWM (→ a real `pwm-fan` cooling device), and proper thermal
throttling. Likely relevant in-kernel 7.x SPMI work to pull in. Tracked for post-launch.

### ~~GPU / display acceleration~~ — DONE, moved to Working
Both landed. Native eDP over the DPU on 2026-07-24 (trains at HBR3; the eDP PHY driver needed
no changes at all), and the Adreno X2 under Mesa turnip on 2026-07-29 — the blocker there turned
out to be our own stale `modprobe.blacklist=gpucc_glymur`, not missing driver support. USB-C
DisplayPort alt-mode works on both ports. **DisplayPort audio is still not working** and is
tracked under the headphone-jack item below.

What remains on the GPU: no zap shader (falls back to `SECVID_TRUST_CNTL`), no hwmon/power
sensor so `nvtop` reports N/A, and no sustained stress testing.

### ~~Charging negotiation (UCSI/PD)~~ — DONE, moved to Working
**UCSI works** (2026-07-29) — `/sys/class/typec/port0` and `port1` are present, and
DisplayPort alt-mode negotiates on both USB-C ports. The fix was deleting one DT property; see
`usb-c-ucsi-dp-altmode.md`. The old `ucsi_glink … PPM init failed` symptom is gone.

**AC/charger detection works too** — verified live 2026-07-31 by plugging the charger in and
watching: `qcom-battmgr-usb/online` = 1, `ucsi-source-psy-…ucsi.02/online` = 1, battery
`status=Charging` with `energy_now` climbing at ~35 W, `upower -d` → `on-battery: no`.

⚠️ **An earlier revision of this file said charger detection was still broken. That was
wrong** — true on 2026-07-24, fixed as a side effect of the UCSI work on 07-29, and never
re-checked. **`qcom-battmgr-ac/online` = 0 is correct behaviour**: its `type` is `Mains`, a
dedicated AC/barrel-jack rail this laptop does not have. It charges over USB-C PD. Reading
`qcom-battmgr-ac` and concluding "no charger" is the error.

### Headphone jack / DisplayPort audio
Jack detect exists but there's no rx-macro/WCD9395 codec in the DT yet; DP audio backends exist
but are gated on GPU/DRM.

### Camera — not working
The webcam/IR camera is not up — no sensor driver or CCI/CSI device-tree wiring for the glymur
camera on this platform yet.

## Notes for contributors
- The kernel is **v7.2-rc3** (Konrad Dybcio's upstream A16 DT lineage) + local patches. ⚠️ The
  old "pinned to v7.1; 7.2/linux-next broke the bring-up chain" note is **retired** — what
  actually broke was our vendor-derived device tree, not the kernel. v7.1 remains a supported
  fallback with its own GRUB entry.
- `soccp_glink` is a custom (out-of-tree-origin) battery driver, now built in-tree.
- Firmware is **not** shipped here — pull it from your own device's Windows/WoA install
  (`ath12k`, `qcom/glymur`, regulatory.db). See `../LOCAL-TWEAKS.md` §1.
- This project was developed with heavy AI assistance; the maintainer is not a kernel dev by
  trade. Treat findings as field notes, verify before relying on them.
