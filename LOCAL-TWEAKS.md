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
- **Thermal shutdowns under load** — DT thermal-zones have only a `critical` trip (~115 °C) and no
  `cooling-maps`, and the fan isn't Linux-controllable (PMIC PWM blocked by the SPMI probe). Under
  load the SoC reaches 115 °C and protectively shuts down. Mitigated by the thermal guard (§6); the
  real fix needs SPMI + DT cooling-maps. (CPU freq scaling itself **works** via SCMI regular
  messaging — only the perf fast-channel fails; UI slowness is from software rendering, not cpufreq.)
- **UCSI/PD PPM** — `ucsi_glink … PPM init failed`. Charging‑negotiation gap.
- **GPU/display** — still software rendering (simpledrm); GPU bring‑up is a separate task.
- **Headphone jack, DP audio** — need codec/DRM work.

## How to re-capture (if the install changes)
Re-run the pull from a working A16 (`ssh <user>@<your-A16>`): tar `/lib/firmware/{ath12k,qcom/glymur}`
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

---

## 7. ADSP firmware in the initramfs (audio at boot) — `tweaks/etc/dracut.conf.d/`

`/etc/dracut.conf.d/99-glymur-adsp.conf`

**Why:** `qcom_q6v5_pas` ships in the initramfs and probes at ~t+1.5s, but the ADSP
firmware lives on the root filesystem, which is not mounted until ~t+2.5s.
`request_firmware()` fails `-2` and **remoteproc never retries**, so the ADSP stays
`offline` for the whole session. Because the `q6prmcc` clock provider lives *inside* the
ADSP, the lpass-lpi pinctrl never gets its `core` clock and the entire audio stack (2×
soundwire, 3× codec, the sound card) is stuck in deferred probe. Six failures, one cause.

`install_items+=` ships the firmware inside the initramfs so it is present when the
driver asks. Costs ~9 MB (49 MB → 58 MB).

**Do not "fix" this with `omit_drivers+=" qcom_q6v5_pas "`.** That also gets the ADSP up,
but delays it to t+5.3s and card registration to t+11.4s — ~0.8s before PipeWire starts.
PipeWire then hits `EINVAL` opening `hw:0,0`/`0,1`/`0,2`, WirePlumber does not retry, and
the **speakers are missing at boot while the microphone works** (`hw:0,3` opens fine).
Full analysis: `docs/audio-adsp-boot-ordering.md`.

30-second triage if audio is dead:

```sh
cat /sys/class/remoteproc/remoteproc0/state    # 'offline' + firmware present == this bug
```

### 7b. `glymur-audio-wait` — PROVISIONAL canary, not a permanent fix

`tweaks/usr/lib/systemd/user/glymur-audio-wait.service` + `tweaks/usr/local/bin/glymur-audio-wait`

Waits for the ALSA sink after WirePlumber starts and restarts WirePlumber if it never
appears. Written to paper over the `omit_drivers` regression above. With the
firmware-in-initramfs fix it should be **unnecessary** — it is kept only as a canary:

```sh
journalctl --user -b -u glymur-audio-wait
#   "sink present (attempt 1)"        -> real fix works; DELETE this unit
#   "restarting wireplumber (try N)"  -> race still happening; investigate
```

## 8. Suspend mode forced to s2idle — `tweaks/etc/tmpfiles.d/`

`/etc/tmpfiles.d/glymur-s2idle.conf` → `w /sys/power/mem_sleep - - - - s2idle`

**Why:** Snapdragon platforms do not implement S3/`deep`, but the kernel was selecting
`deep`. Note `cat /sys/power/mem_sleep` shows `[s2idle] deep` — **the brackets mark the
active mode**, so that output means s2idle is selected, not deep.

⚠️ **This does NOT make suspend work.** With s2idle correctly selected the machine still
panics and reboots on suspend; the journal ends at `PM: suspend entry (s2idle)` with
nothing after. Still unsolved.

⚠️ **Crash evidence is not collectable on this box — but not for the reason stated here
before.** This used to blame mandatory `efi=noruntime`. Corrected 2026-07-30: the flag was
retired, and efivars are unreachable on this firmware with *or* without it. EFI runtime
services do come up; this INSYDE firmware simply reports the **variable** subset as
unsupported (`GetVariable` → `EFI_UNSUPPORTED`, `0x8000000000000003`), so
`fsopen("efivarfs")` fails `EOPNOTSUPP` and efivars-backed pstore was never there to be
disabled. `/sys/fs/pstore` is empty after every
panic regardless. Debugging suspend further needs `/sys/power/pm_test` stage bisection
(`CONFIG_PM_DEBUG=y`, available) or a ramoops region added to the DTB. Also worth checking
whether `CONFIG_EFIVAR_FS` is enabled at all.

## 9. RTC epoch offset — `tweaks/usr/local/bin/glymur-rtc-{save,restore}`

The glymur PMIC RTC (`pmk8850`, `rtc-pm8xxx`) is a **free-running counter, not a wall
clock**. Real time is `counter + offset`, and the firmware keeps that offset in a UEFI
variable — which is exactly what upstream's `qcom,uefi-rtc-info` property tells the driver
to go read.

We cannot read it, and the reason is specific: EFI runtime services themselves **do** come up (`Remapping and enabling EFI services.`
at boot). What this INSYDE firmware does not support is the **variable** subset:
`GetVariable` returns `EFI_UNSUPPORTED` (status `0x8000000000000003`, logged as
`integrity: Couldn't get size: 0x8000000000000003` / `MODSIGN: Couldn't get UEFI db list`).
So `efivar_is_available()` is false and `fsopen("efivarfs")` fails `EOPNOTSUPP`. Not a
kernel config gap: `CONFIG_EFIVAR_FS=y` and efivarfs is registered in `/proc/filesystems`.

**This holds with or without `efi=noruntime`** — verified 2026-07-30 by booting a variant
with the property restored and the flag dropped. With the
property set the driver returns `-EPROBE_DEFER` forever, so our device tree deletes it. The
RTC then binds, but starts at ~1970.

So we do what the firmware does. The offset is a **constant**, because the counter is
monotonic and battery-backed:

```
counter C = 4941867   now N = 1785382601   offset = N - C = 1780440734
```

- **`glymur-rtc-save`** → writes the offset to `/var/lib/glymur/rtc-offset`, but **only while
  `NTPSynchronized=yes`**, so a wrong clock can never poison it. Driven by
  `glymur-rtc-save.timer` (`OnBootSec=3min`, `OnUnitActiveSec=1h`). The timer is *not* for
  drift — there is none. It exists to capture the offset after the first NTP sync, and to
  self-heal if the RTC domain loses power and the counter restarts from zero.
- **`glymur-rtc-restore`** → early oneshot (`DefaultDependencies=no`, `After=local-fs.target`,
  `Before=sysinit.target`) that sets the clock to `counter + offset`. It **only ever moves the
  clock forward**, which makes it impossible to stomp an already-correct clock. Verified by
  running it against a good clock and watching it decline:
  `clock already at/ahead of RTC estimate -- leaving it alone`.

Install:
```
sudo install -m 0755 tweaks/usr/local/bin/glymur-rtc-{save,restore} /usr/local/bin/
sudo install -m 0644 tweaks/etc/systemd/system/glymur-rtc-{restore.service,save.service,save.timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo /usr/local/bin/glymur-rtc-save          # seed it while NTP is synced
sudo systemctl enable --now glymur-rtc-save.timer
sudo systemctl enable glymur-rtc-restore.service
```

⚠️ **This does not give you a wake alarm.** `qcom,no-alarm` is upstream's and stays, so
`/sys/class/rtc/rtc0/wakealarm` does not exist and hibernate still has nothing to arm. The
RTC also remains **read-only** — `hwclock --systohc` fails with `ENODEV`, and `rtcsync` in
`/etc/chrony.conf` will silently never succeed.

Without this tweak the machine still recovers: chronyd is configured `makestep 1.0 3`, so it
*steps* the ~1970 offset rather than slewing it. But there is a window early in boot where the
clock reads 1970 and TLS validation would fail, which is what this closes.
