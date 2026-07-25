# Hardware status — what works, what doesn't, and how to test it

ASUS Zenbook A16 UX3607OA · Snapdragon X2 Elite Extreme ("glymur") · box `loazen`

**Last verified: 2026-07-24.** Every "working" claim below has a reproducible check
next to it. If a claim has no check, treat it as unverified.

Current recommended boot entry: **`fedora-glymur-test65`**
(kernel `7.1.0-glymur-gdsc1`, DTB `glymur-a16-test65.dtb`).
Known-good fallbacks, in order: `fedora-glymur-gdsc1` → `fedora-glymur-edp1` →
`fedora-glymur-clean2`. Never edit those in place.

---

## Working

| Thing | How to verify |
|---|---|
| **eDP panel + backlight** | `cat /sys/class/drm/card1/card1-eDP-1/status` = `connected`; `cat /sys/class/graphics/fb0/name` = `msmdrmfb`; `ls /sys/class/backlight/` = `dp_aux_backlight`. HBR3, 2880x1800@120. `msm` autoloads and binds unattended. |
| **Wi-Fi 7** | ath12k/QCC2072. Associates at boot. Needs Windows-extracted firmware + regdomain `US`. |
| **Keyboard + backlight** | ASUS vendor HID handshake. Steady-on at max via userspace hidraw script — see `keyboard-and-brightness-status.md`. Not dimmable (see below). |
| **Touchpad / touchscreen / stylus** | `grep Name /proc/bus/input/devices` — `hid-over-i2c 093A:3012`, `04F3:4645`. |
| **NVMe / RTC / USB** | Root on `nvme0n1p17`. USB buses `usb1`..`usb7`. |
| **Battery reporting** | `/sys/class/power_supply/qcom-battmgr-bat/` — `energy_now`/`energy_full` valid. ⚠️ `capacity` reads **empty**, so desktop % indicators may not populate. |
| **Fan** | EC-autonomous. |
| **gpucc / GPU clock controller** | **New 2026-07-24.** `modprobe gpucc-glymur` → 25 clocks in `/sys/kernel/debug/clk`, `gpu_cc_pll0` = 1149999902 Hz. Registration only — no GPU rendering. See `gpucc-bringup.md`. |
| **Audio (with caveats)** | See the audio section below — it is real but has a boot-ordering trap and a channel-layout trap. |

---

## Not working

| Thing | State |
|---|---|
| **GPU / Adreno X2 rendering** | gpucc clock controller confirmed; GPU itself not brought up. Gap is device tree (gpu/gmu/adreno_smmu nodes), **not** drivers — a8xx + firmware are already present. Do NOT start a gpucc decompile. |
| **cpufreq scaling** | `scmi-cpufreq -110`, cores pinned at boot clock. Bandaid: `glymur-thermal-guard.service` polls every 2s and steps `scaling_max_freq`. No DT thermal zone; only trip point is 115C critical. |
| **UCSI / USB-C PD** | `ucsi_glink ... PPM init failed, stop trying`. No PD or altmode negotiation. Suspected cause of the USB-C hub/NIC issue, and a hard prerequisite for USB4. |
| **AC / charger detection** | ⚠️ **New 2026-07-24.** With the charger physically plugged in, `qcom-battmgr-ac/online` = `0` and `power_now` is negative (discharging). Likely tied to the UCSI/PD failure. Needs investigation. |
| **USB4 / Thunderbolt** | Three USB4 controllers exist in silicon (`gcc_usb4_{0,1,2}_gdsc`), but no host-router/NHI node in DT — and none in `hamoa.dtsi` either, so upstream has nothing to copy. Blocked behind UCSI. ⚠️ `usb usb4:` in dmesg is **USB bus 4**, a plain xHCI root hub — not USB4. |
| **Suspend / resume** | Untested-good. Crashed hard on 2026-07-24 with zero evidence captured. `mem_sleep` was on `deep`; now forced to `s2idle` (see below). Retest pending. |
| ~~**Lid switch**~~ | **MOVED TO WORKING 2026-07-24** — test65 added it on TLMM 92; verified `EV_SW`/`SW_LID` registered and `logind` reading it. See the lid section. |
| **Headphone jack / DP audio** | Not working. (`GLYMUR-A16 Headset Jack` input node does appear once the ADSP is up.) |
| **Dimmable keyboard backlight** | No `asus::kbd_backlight` LED; the A16 device entry lacks `QUIRK_USE_KBD_BACKLIGHT`, so Fn illum keys land nowhere. |
| **`qcom-spmi-temp-alarm`** | Not working. |

---

## Audio — two traps

Audio genuinely works, but it fails in two different ways that look like "audio is broken".

**Trap 1 — the ADSP firmware boot race.** Full detail in
`audio-adsp-boot-ordering.md`. Short version: `qcom_q6v5_pas` ships in the initramfs
and probes at ~t+1.56s, but its firmware lives on the root filesystem, which mounts at
~t+2.46s. `request_firmware()` fails `-2`, remoteproc never retries, and because the
`q6prmcc` clock provider lives *inside* the ADSP, the whole audio stack stays deferred.
Triage:

```sh
cat /sys/class/remoteproc/remoteproc0/state     # 'offline' + firmware present == this bug
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state   # card appears in seconds
```

Fixed persistently via `/etc/dracut.conf.d/99-glymur-adsp.conf` — **`install_items+=`
shipping the firmware in the initramfs**, so the driver finds it at t+1.5s.
Confirmed 2026-07-24 that the ADSP comes up at boot and the
`DSP returned error[1001006] 9` graph-open failure does not recur (it was an artifact of
hand-starting the ADSP ~1000s late).

⚠️ **A first attempt used `omit_drivers+=" qcom_q6v5_pas "` instead, and that was
wrong.** It fixed the ADSP but delayed it to t+5.3s, pushing card registration to
t+11.4s — ~0.8s before PipeWire starts. PipeWire then hit `EINVAL` opening hw:0,0/0,1/0,2,
WirePlumber did not retry, and **the speakers were missing at boot while the microphone
worked** (hw:0,3 opens fine). If you ever see mic-yes/speakers-no, that is this bug.
Full detail in `audio-adsp-boot-ordering.md`.

**Trap 2 — default sink lands on a network speaker.** With RAOP/AirPlay sinks on the
LAN, WirePlumber can pick one as the default because the ALSA card appears *late*
(the ADSP boots after switch-root). Symptom: audio "works" but comes out of a speaker
in another room. Fixed durably by the persisted
`default.configured.audio.sink=alsa_output.platform-sound.playback.1.0` in
`~/.local/state/wireplumber/default-nodes` — verified to survive WirePlumber restarts
with RAOP sinks present. If it ever regresses, add a WirePlumber `priority.session`
rule for the ALSA node.

**Trap 3 — 4.0 channel layout: ALWAYS test with 4 channels.** Confirmed by Jesse
2026-07-24. The card is 4-channel (`s16le 4ch 48000Hz`) and the woofers sit on
**RL/RR**, so a 2-channel test drives only the tweeters and can read as "barely working"
or "no sound". This matches the long-standing `CLAUDE.md` note; it is correct.

```sh
speaker-test -D pipewire -c 4              # correct — exercises all four drivers
speaker-test -D pipewire -c 2              # WRONG — tweeters only, misleading result
speaker-test -D pipewire -c 4 -t wav       # names each speaker aloud as it fires
```

Practical consequence: stereo content needs a 4-channel upmix to reach the woofers at
all, so "the laptop sounds thin" is expected without one — not a fault.

Also observed: `RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1`/`MultiMedia2` were `[off]`
and needed `amixer -c 0 sset "<name>" on` by hand. UCM should be doing that — if it
does not on a clean boot, that is its own bug.

Open: after a *late* hand-start of the ADSP, playback failed with
`qcom-apm ... DSP returned error[1001006] 9` (graph-open refused). Suspected artifact of
the late start. Retest from a clean boot before chasing it.

---

## Suspend

Snapdragon platforms do not implement S3/`deep`; **`s2idle` is the only viable mode**,
but the kernel was selecting `deep`:

```sh
cat /sys/power/mem_sleep      # want [s2idle], not [deep]
```

Forced via `/etc/tmpfiles.d/glymur-s2idle.conf` (`w /sys/power/mem_sleep - - - - s2idle`).
Chosen over a cmdline `mem_sleep_default=` specifically to avoid another GRUB edit.

⚠️ **Crash evidence is not currently collectable.** `efi=noruntime` is mandatory on this
box (without it you get intermittent warm resets at fbcon commit), and it disables EFI
runtime services — which is exactly why `/sys/fs/pstore` was **empty** after the
2026-07-24 crash. If suspend crashes again, expect no post-mortem unless ramoops or
netconsole is set up first.

---

## Lid switch (new in test65)

Until test65 there was **no lid switch of any kind** — `gpio-keys` declared only
`key-volume-up`, and `logind` reported `LidClosed=false` permanently despite
`HandleLidSwitch=suspend`.

The pin was recovered from the WoA ACPI dump
(`~/Documents/asus-fn-keys-fix/acpi-ref/dsdt.dsl`). `Device (LID0)` / `_HID PNP0C0D`
does not own a GPIO directly; it reads `\_SB.GIO0.LIDR`, which is a 1-bit field on
GpioIo pin `0x005C` of `GIO0` (`QCOM0F0C`, base `0x0F100000` = TLMM):

**Lid = TLMM GPIO 92, active-low** (AML: `LIDB == Zero` → "Lid closing action is set",
so 0 = closed).

Cross-check that validates the decode: the two adjacent fields in the same block are
`G098` on pin `0x0062` (98) and `G120` on pin `0x0078` (120) — the names encode the
decimal pin numbers and both match.

Pin 92 sat inside `gpio-reserved-ranges` block `88..145`. test65 splits it into
`88..91` + `93..145`, freeing **only** pin 92, and adds:

```dts
lid-switch {
    label = "Lid Switch";
    gpios = <&tlmm 92 GPIO_ACTIVE_LOW>;   /* raw: <0x69 0x5c 0x01> */
    linux,input-type = <0x05>;            /* EV_SW  */
    linux,code = <0x00>;                  /* SW_LID */
    debounce-interval = <0x0f>;
    wakeup-source;
};
```

⚠️ Freeing reserved TLMM pins is the operation that killed test61 (which freed
12/13/18). test65 frees exactly one. Argument that 92 is safer: Windows reads it from
the **non-secure** OS via `GeneralPurposeIo` on the same TLMM, so it is unlikely to be
TrustZone-owned. Still a real risk — if test65 fails to boot, the pin free is the cause
(the `gpio-keys` addition can only fail a probe, not kill early boot).

⚠️ Phandle trap: `key-volume-up` uses phandle `0xff`, which is `gpio@8800`
(`qcom,pmh0101-gpio`) — a **PMIC** GPIO controller, not the TLMM. The TLMM is phandle
`0x69` (`pinctrl@f100000`, `qcom,glymur-tlmm`). Do not copy the volume-key phandle.

**VERIFIED WORKING 2026-07-24** — test65 booted first try, freeing TLMM 92 caused no
crash, and the switch registered.

⚠️ **Do NOT verify with `grep -i lid /proc/bus/input/devices` — it always returns
nothing, even when the lid works.** `gpio-keys` creates a *single* input device named
`gpio-keys` holding every key and switch; "Lid Switch" is a per-key label that never
appears in that file. Correct check — read the capability bits:

```sh
awk '/Name="gpio-keys"/{p=1} p' /proc/bus/input/devices | head -10
#   B: EV=23   -> 0x23 = EV_SYN|EV_KEY|EV_SW   (EV_SW = the lid)
#   B: SW=1    -> bit 0 = SW_LID               <- this line existing IS the proof

busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager LidClosed              # flips when you close it
sudo evtest /dev/input/event2                             # watch live SW_LID events
```

(Also beware parsing those `B:` lines with `awk '{print $3}'` — the field is `$2`,
e.g. `B: EV=23`. That mistake reports "no switch" on a perfectly working lid.)

⚠️ `logind` has `HandleLidSwitch=suspend`. The moment the switch exists, closing the
lid **will** suspend. If suspend is not yet known-good, set `HandleLidSwitch=ignore`
while testing, or verify suspend first.

---

## test65 boot checklist

```sh
uname -r                                        # 7.1.0-glymur-gdsc1
cat /proc/device-tree/soc@0/clock-controller@3d90000/compatible   # qcom,glymur-gpucc
cat /sys/class/remoteproc/remoteproc0/state     # running  <- initramfs fix worked
cat /proc/asound/cards                          # GLYMUR-A16
sudo cat /sys/kernel/debug/devices_deferred     # no audio entries
awk '/Name="gpio-keys"/{p=1} p' /proc/bus/input/devices | grep "^B: SW="   # SW=1 -> lid OK
cat /sys/power/mem_sleep                        # [s2idle]  <- BRACKETS mark the ACTIVE mode
cat /sys/class/drm/card1/card1-eDP-1/status     # connected
```
