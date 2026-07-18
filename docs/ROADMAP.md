# Roadmap & known-not-working

This is a **semi-working** bring-up of Linux on the ASUS Zenbook A16 (UX3607OA, Snapdragon
X2 Elite / `glymur` / sm8750). Lots works; several things don't yet. Contributions and expert
eyes are very welcome — see `CONTRIBUTING.md` and open an Issue/Discussion.

## Working
- Boot to desktop (systemd-boot, raw arm64 Image + DTB) on Arch/Manjaro-KDE, Ubuntu, Fedora.
- Keyboard, trackpad, touchpad, keyboard backlight (steady, via `asus-kbd-init`).
- USB-C + USB-A (incl. USB NIC), USB storage, RTC.
- Wi-Fi 7 (Qualcomm QCC2072, ath12k) — with correct firmware + a forced regdomain.
- Battery percentage + USB-PD charging (`soccp_glink` + `ps883x`).
- Audio: speakers (4.0, woofers + tweeters via AudioReach topology + WirePlumber upmix) and
  the internal DMIC. See `../LOCAL-TWEAKS.md`.

## Not working yet / help wanted

### Thermal shutdowns under load — HIGH IMPACT
The DT thermal-zones expose **only a `critical` trip (~115 °C hard shutdown) and no
`cooling-maps`**, and the fan is not Linux-controllable (see SPMI below). So under sustained
load the SoC races to 115 °C and does a protective shutdown — which presents as "random
crashes" (~every 10–20 min under a full KDE/Wayland software-render load). An interim userspace
**thermal guard** ships in the images and throttles CPU max frequency by temperature (see
`../LOCAL-TWEAKS.md` §6); it held a full 18-core load at ~70 °C with no shutdown. The real fix is
DT `cooling-maps` binding `cpufreq-cooling` to *passive* trips **plus** a working fan (SPMI).
Note: CPU frequency scaling itself **works** (`scaling_driver=scmi`; cores scale 355 MHz–4.45 GHz)
via SCMI regular messaging — only the SCMI perf *fast-channel* fails (`Failed to get FC for
protocol 13 … Using regular messaging`). The advertised perf table also tops out at **4.45 GHz** —
the X2 Elite's rated ~5 GHz boost bin isn't exposed (the boost/turbo states are normally carried
over the fast-channel, so this is likely the same FC gap). UI sluggishness is from **software
rendering (no GPU)**, not cpufreq.

### SPMI PMIC-arb — gates the fan AND the thermal alarm — HIGH IMPACT
Secondary PMICs fail to probe over SPMI (`pmic-spmi … error -5`; `pmic_arb_wait_for_done:
transaction failed`). This one bottleneck blocks **both**: (1) `qcom-spmi-temp-alarm` (the PMIC
temperature alarm never registers), and (2) the PMIC PWM (`pmh0101`/`pm8350c`) that drives the
**fan** — so `/sys/class/pwm` is empty and Linux can't spin it. Fixing the SPMI arbiter probe
should unlock the temp alarm, the fan PWM (→ a real `pwm-fan` cooling device), and proper thermal
throttling. Likely relevant in-kernel 7.x SPMI work to pull in. Tracked for post-launch.

### GPU / display acceleration
Still on software rendering (simpledrm/efifb). Adreno X2 + DPU bring-up is a separate, larger
effort (the `docs/gpu-re/` notes cover the VMID/SMMU/ACPI investigation). The eDP regulator is
likely blocked by the same over-reserved TLMM gpio-range pattern used to free the USB pins.
Unlocks DP / USB-C display **and** DisplayPort audio.

### Charging negotiation (UCSI/PD)
`ucsi_glink … PPM init failed` — the UCSI/PD power-management handshake has a firmware-response
gap. Battery % + basic charging work; full PD negotiation does not.

### Headphone jack / DisplayPort audio
Jack detect exists but there's no rx-macro/WCD9395 codec in the DT yet; DP audio backends exist
but are gated on GPU/DRM.

### Camera — not working
The webcam/IR camera is not up — no sensor driver or CCI/CSI device-tree wiring for the glymur
camera on this platform yet.

## Notes for contributors
- The kernel is pinned to **v7.1** + local patches; 7.2/linux-next broke the bring-up chain.
- `soccp_glink` is a custom (out-of-tree-origin) battery driver, now built in-tree.
- Firmware is **not** shipped here — pull it from your own device's Windows/WoA install
  (`ath12k`, `qcom/glymur`, regulatory.db). See `../LOCAL-TWEAKS.md` §1.
- This project was developed with heavy AI assistance; the maintainer is not a kernel dev by
  trade. Treat findings as field notes, verify before relying on them.
