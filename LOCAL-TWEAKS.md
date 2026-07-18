# A16 local customizations (userspace) — captured from the working install

Everything below was pulled from the running A16 (`loazen`, kernel `7.1.0-glymur-clean+`)
on 2026-07-18 and is baked into every distro image by `iso/build-all.sh` via two overlays:

- `a16-fw.tar.gz`  — firmware + regdomain (kernel-facing)
- `a16-tweaks.tar.gz` — userspace (audio routing, keyboard backlight, battery autoload)

The kernel/DTB/module side (clean kernel, `soccp_glink`, `test55.dtb`) is documented elsewhere.
This file is the **userspace** manifest — the parts that make hardware actually usable after boot.

---

## 1. Firmware (a16-fw.tar.gz)

| Path | Purpose |
|---|---|
| `/lib/firmware/ath12k/QCC2072/hw1.0/{amss,m3,board,aux_ucode,regdb}.bin` | Wi‑Fi 7 (Qualcomm QCC2072). The images previously shipped `bdwlan.elf`/`wlanfw20.mbn` from staging, which the `ath12k_wifi7` driver does **not** request — it wants `amss.bin` (hence the `-2` load failure). These are the correct, uncompressed files. |
| `/lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin` | AudioReach topology. Without it the sound card can't instantiate (`snd-x1e80100 ... failed to instantiate card -2`). Derived from the x1e80100 Romulus tplg. |
| `/lib/firmware/qcom/glymur/…` (adsp/cdsp mbn, ASUSTeK subtree) | ADSP/CDSP co‑processor images. |
| `/lib/firmware/regulatory.db(.p7s)` | cfg80211 regulatory database (needed for the regdomain to apply). |

### Wi‑Fi regdomain tweak (the "early wifi tweak")
`/etc/modprobe.d/wifi-regdom.conf` and `/etc/modprobe.d/cfg80211-regdom.conf` both contain:

```
options cfg80211 ieee80211_regdom=US
```

Rationale: dmesg shows `ath12k … Timeout while waiting for regulatory update` — the card's
regulatory handshake times out. Forcing a static regdomain (US) lets the interface come up and
associate anyway. **Change `US` to your country code if not in the US.**

---

## 2. Audio userspace (a16-tweaks.tar.gz)

The tplg makes the card *exist*; these make it *play* correctly.

### 2a. ALSA UCM2 profile — `/usr/share/alsa/ucm2/Qualcomm/glymur/`
`glymur.conf`, `GLYMUR-A16.conf`, `HiFi.conf`, `SpeakerFeBe.conf`, `MicFeBe.conf`, plus
enable symlinks in `/usr/share/alsa/ucm2/conf.d/glymur/`. Gives PipeWire/ALSA a named
`GLYMUR-A16` card profile with HiFi playback + mic.

### 2b. WirePlumber — `/etc/wireplumber/wireplumber.conf.d/51-glymur-ucm.conf`
Forces the platform-sound sink to **4 channels [FL FR RL RR] with upmix** (method `psd`).
The A16 chassis is a 4.0 layout — tweeters are FL/FR, **woofers are RL/RR**. Plain stereo only
drives the tweeters (tinny, no bass); the 4‑ch upmix fires the woofers. Also disables ACP and
suspend timeout so the route survives idle.

### 2c. Route script — `/usr/local/bin/glymur-audio-route.sh` + `glymur-audio-route.service`
Oneshot at boot. Waits for the `GLYMUR` card, then sets the AudioReach FE→BE mixer path,
both WSA + WSA2 macros (RX0 woofer digital vol 81, RX1 tweeter 77, comps on), all four
WSA8845 amps (COMP/BOOST/DAC/PBR on, PA Volume 6 = max), and the VA DMIC capture path.
This is the difference between "card present" and "sound comes out."

### 2d. Saved mixer state — `/var/lib/alsa/asound.state`
alsactl restore point for the above levels.

### 2e. `/etc/modprobe.d/lpass-cap.conf.off` (DISABLED — reference only)
Blacklists the LPASS macros. Kept as `.off` (inactive) from earlier debugging; do **not**
enable unless intentionally disabling on‑SoC audio.

---

## 3. Keyboard backlight (a16-tweaks.tar.gz)

- `/usr/local/bin/asus-kbd-init.py` — finds the ASUS keyboard hidraw (VID:PID `0B05:4B42`),
  sends the `ASUS Tech.Inc.` init handshake + a backlight FEATURE report to stop the default
  breathing animation and set a steady level. Keys always worked; this is backlight only.
- `asus-kbd-init.service` — runs it once at boot.
- `/usr/lib/systemd/system-sleep/asus-kbd-init` — re‑runs it after resume (backlight resets on wake).

---

## 4. Battery / charging autoload (a16-tweaks.tar.gz)

`/etc/modules-load.d/battery-baseline.conf`:
```
soccp_glink
ps883x
```
- `soccp_glink` — custom out‑of‑tree‑origin module (now in‑tree in the clean kernel): brings up
  the SOCCP GLINK edge → `pmic_glink` → `qcom-battmgr`, which is what surfaces battery %.
- `ps883x` — Parade ps8830 USB‑C retimer (USB‑PD charging).

Both modules ship in the image (`/lib/modules/7.1.0-glymur-clean+`); this file just autoloads them.

---

## 5. NetworkManager
`/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf` → `wifi.powersave = 3`
(kept as captured; low impact).

---

## Known-not-working (unchanged by these tweaks)
- **CPU freq scaling** — `scmi-cpufreq` times out (`-110`); cores run at boot clock (a cause of
  UI slowness alongside software rendering). Firmware‑response gap, not fixable in userspace.
- **UCSI/PD PPM** — `ucsi_glink … PPM init failed`. Charging‑negotiation gap.
- **GPU/display** — still software rendering (simpledrm); GPU bring‑up is a separate task.
- **Headphone jack, DP audio** — need codec/DRM work.

## How to re-capture (if the install changes)
Re-run the pull from a working A16 (`ssh jcasco@192.168.8.209`): tar `/lib/firmware/{ath12k,qcom/glymur}`
+ regdb into `a16-fw.tar.gz`, and the files in sections 2–5 into `a16-tweaks.tar.gz`, drop both in
`~/glymur-build/`, and `iso/build-all.sh` picks them up automatically via `addfw()`.

## 6. Thermal guard (interim CPU-freq throttle) — a16-tweaks.tar.gz
`/usr/local/bin/glymur-thermal-guard.sh` + `glymur-thermal-guard.service` (enabled at boot).

**Why:** the DT thermal-zones expose only a `critical` trip (~115 C hard shutdown) with **no
`cooling-maps`**, and the fan is **not controllable from Linux** (no pwmchip / fan hwmon). Under
heavy load the SoC raced to 115 C and did a protective shutdown — which presents as "random
crashes." This userspace daemon polls the hottest thermal zone every 2 s and steps
`scaling_max_freq` down in tiers (perf 2.8 -> 2.0 -> 1.1 GHz, eff 2.2 -> 1.5 -> 0.9 GHz) as temp
climbs past ~86/94 C, releasing (debounced) below ~76 C. **Validated:** full 18-core load held
~70 C steady (93 C peak) with no shutdown; without it the machine crashed every ~10-20 min.

**Interim only.** The real fix is DT `cooling-maps` binding `cpufreq-cooling` to *passive* trips
plus wiring the fan as an active cooling device — see `docs/ROADMAP.md` (SPMI / SCMI / thermal).
