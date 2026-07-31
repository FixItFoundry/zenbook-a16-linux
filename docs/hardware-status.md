# Hardware status — what works, what doesn't, and how to test it

ASUS Zenbook A16 UX3607OA · Snapdragon X2 Elite Extreme ("glymur") · box `loazen`

**Last verified: 2026-07-31.** Every "working" claim below has a reproducible check
next to it. If a claim has no check, treat it as unverified.

Current recommended boot entry: **`Fedora Linux on ARM`** (id `fedora-linux-arm`) — the
single baseline, kernel `7.2.0-rc3-konrad1-pmskip6`, DTB
`glymur-a16-merged-gpu-scmipoll.dtb`, cmdline carrying `glymur_pci_skip=5`. It is the one
entry that has **both** the suspend workaround and the cpufreq fix.

Known-good fallbacks, newest first, all under the *Previous baselines and fallbacks*
submenu: `fedora-linux-arm-prev-suspend` (suspend, no cpufreq — also the single-variable
control for the cpufreq change) → `fedora-linux-arm-prev-plain` (neither) →
`fedora-linux-arm-noruntime` → `fedora-linux-arm-nogpu` → `fedora-linux-arm-legacy`
(7.1 vendor lineage). Never edit those in place.

Sweep re-run on the live box 2026-07-31 08:4x confirming this header: `uname -r` =
`7.2.0-rc3-konrad1`, model `ASUS Zenbook A16 (UX3607OA)`, 3 cpufreq policies with
`scaling_driver=scmi` / `governor=schedutil`, `card1` + `renderD128` with
`gen80100_sqe.fw` loaded, `typec/port0` + `port1` present, eDP `connected` with
`dp_aux_backlight`, audio card 0 registered, Wi-Fi `connected`.

---

## Working

| Thing | How to verify |
|---|---|
| **eDP panel + backlight** | `cat /sys/class/drm/card1/card1-eDP-1/status` = `connected`; `cat /sys/class/graphics/fb0/name` = `msmdrmfb`; `ls /sys/class/backlight/` = `dp_aux_backlight`. HBR3, 2880x1800@120. `msm` autoloads and binds unattended. |
| **Wi-Fi 7** | ath12k/QCC2072. Associates at boot. Needs Windows-extracted firmware + regdomain `US`. |
| **CPU frequency scaling** | ✅ **2026-07-31.** `ls /sys/devices/system/cpu/cpufreq/` = `boost policy0 policy6 policy12`; `cat .../policy0/scaling_driver` = `scmi`. Three SCMI performance domains — cpus 0-5 at 355 MHz–3.61 GHz (20 OPPs), cpus 6-11 and 12-17 at 355 MHz–4.45 GHz (21 OPPs each). Governor `schedutil`, selected by power-profiles-daemon. **Requires the `arm,no-completion-irq` DTB** — verify with `cat /proc/device-tree/firmware/scmi/arm,no-completion-irq`. Root cause and evidence: [`power-and-thermal.md`](power-and-thermal.md), [`../patches/glymur-scmi-no-completion-irq-CONFIRMED.patch`](../patches/glymur-scmi-no-completion-irq-CONFIRMED.patch). |
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
| ~~**GPU / Adreno X2 rendering**~~ | **MOVED TO WORKING 2026-07-29** — `adreno` binds, GMU firmware loads, turnip enumerates the device. Re-verified 2026-07-31: `/sys/class/drm/` has `card1` + `renderD128` and `gen80100_sqe.fw` loads. The blocker was our own stale `modprobe.blacklist=gpucc_glymur`, not a missing driver. |
| ~~**cpufreq scaling**~~ | **MOVED TO WORKING 2026-07-31** — see the Working table. |
| **Fan RPM readback** | ✅ **2026-07-31.** `/usr/local/bin/glymur-ec-read.sh rpm`. Reads the EC at `0x76` on `i2c-9` with the DSDT's `RECM` command (`0x52`, raw I2C, **no SMBus count byte**), combining `0x0603<<8 | 0x0602` exactly as `\_SB.FAN0.GCFR` does. Validated against load: 2340 RPM @ 44 C idle → 2940 RPM @ 73 C with all 18 cores busy → back to 2340. ⚠️ The old "blocked on an SSDT re-dump" claim is **retracted** — `FAN1` is external and unused; `FAN0` was in the DSDT all along. |
| **Thermal `cooling-maps`** | ⚠️ **New gap, exposed by the cpufreq fix.** The kernel now creates `cpufreq-cpu0`, `cpufreq-cpu6` and `cpufreq-cpu12` cooling devices, but **no thermal zone binds them**, so Linux has cooling *capability* and no cooling *actuation*. Verify: `for f in /sys/class/thermal/thermal_zone*/cdev*_type; do cat $f; done \| grep -c cpufreq` returns `0`. What protects the machine meanwhile: 101 critical trip points, and the EC/BIOS-autonomous fan. Writing the `cooling-maps` is the next thermal task. |
| ~~**UCSI / USB-C PD**~~ | ✅ **MOVED TO WORKING 2026-07-29** — fixed by deleting one DT property; see `usb-c-ucsi-dp-altmode.md`. Re-verified 2026-07-31: `/sys/class/typec/port0` and `port1` present, DP alt-mode negotiates on both ports, and charging is reported through `ucsi-source-psy-*`. The old `PPM init failed` symptom is gone. |
| ~~**AC / charger detection**~~ | ✅ **NOT BROKEN — retracted 2026-07-31.** It was genuinely broken on 2026-07-24, then **fixed as a side effect of the UCSI fix on 07-29**, and nobody re-checked. Verified live while plugging in: `qcom-battmgr-usb/online` = `1`, `ucsi-source-psy-…ucsi.02/online` = `1`, battery `status=Charging` with `energy_now` climbing at ~35 W, and `upower -d` reporting `on-battery: no`. **`qcom-battmgr-ac/online` = 0 is correct**: its `type` is `Mains`, a dedicated AC/barrel-jack rail this laptop does not have — it charges over USB-C PD. Do not read `qcom-battmgr-ac` and conclude "no charger". |
| **USB4 / Thunderbolt** | Three USB4 controllers exist in silicon (`gcc_usb4_{0,1,2}_gdsc`), but no host-router/NHI node in DT — and none in `hamoa.dtsi` either, so upstream has nothing to copy. Blocked behind UCSI. ⚠️ `usb usb4:` in dmesg is **USB bus 4**, a plain xHCI root hub — not USB4. |
| **Suspend / resume** | ⚠️ **WORKING on a workaround, 2026-07-30.** Lid close sleeps, lid open wakes; 3/3 cycles. Stock it hard-resets the SoC. Cause: PCI config-space access during `dpm_suspend_noirq()`; reproduces on the **upstream** A16 DT. Needs the `fedora-linux-arm-suspend` GRUB entry. Saves less power than a correct suspend — a real fix needs a firmware revision. See the Suspend section. |
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

**Status: working since 2026-07-30, on a workaround.** Boot the
**"Fedora Linux on ARM (suspend capable)"** GRUB entry (the default). Close the lid to sleep,
open it to wake. `logind` also suspends on the power/suspend keys; `IdleAction` is deliberately
`ignore`, so nothing sleeps unattended.

⚠️ **The workaround is entry-specific.** On any *other* GRUB entry, closing the lid or pressing
power will **hard-reset the machine**, because the handlers are global but the kernel knob is
not. The suspend-capable entry is the default and the plain daily driver is the fallback.

### Why it needs a workaround

Stock, s2idle hard-resets the SoC — no panic, no fault, no call trace, and nothing in pstore.
`/sys/power/pm_test` localises it: `freezer` and `devices` survive, `platform` resets. Under
s2idle that difference is exactly `dpm_suspend_late()` + `dpm_suspend_noirq()`, since the
`platform_suspend_prepare*` hooks are no-ops (`s2idle_set_ops()` is x86/ACPI-only).

Narrowing further shows **a single PCIe device performing its noirq suspend is sufficient to
reset the SoC**, and that inside `pci_pm_suspend_noirq()` the fatal actions are the two
config-space accesses:

| skipped | result |
|---|---|
| `pci_prepare_to_sleep()` only | resets |
| `pci_save_state()` only | resets |
| **both** | **survives** |
| driver `suspend_noirq()` | irrelevant — innocent |

⇒ **PCI config-space access during `dpm_suspend_noirq()` resets this SoC**, read and write
paths independently lethal.

**This reproduces on the bare upstream A16 device tree**, and with the GPU disabled — so it is
a platform gap, not a defect in our DT, and not fixable by a device-tree property here. **A
real fix depends on a firmware revision.** Ruled out by test, not argument: PME wakeup arming
(already disabled by default), D3cold, any D-state change, the PCIe controller being
runtime-suspended, the GPU, and every driver with a callback in that window — individually and
combined.

The workaround is `glymur_pci_skip=5` on the kernel cmdline, from
`patches/glymur-suspend-noirq-knobs-DIAGNOSTIC.patch`. Because PCI devices then never save
state or change D-state, **they stay powered through suspend** — the laptop sleeps, but saves
less power than a correct implementation. Draw in suspend has not been measured.

### Checking it worked

⚠️ Judge by `uptime -s`, never by reachability. Wi-Fi takes minutes to re-associate after a
resume and the USB-A NIC sometimes does not come back at all, so "I cannot ssh in" looks
identical to a reset.

```sh
uptime -s                              # unchanged across a cycle = it resumed, not reset
cat /sys/power/suspend_stats/success   # increments on each successful cycle
journalctl -u systemd-logind | tail    # "Lid closed." -> "Suspending..." -> "Operation 'suspend' finished."
```

### Mode selection

Snapdragon platforms do not implement S3/`deep`; **`s2idle` is the only viable mode**,
but the kernel was selecting `deep`:

```sh
cat /sys/power/mem_sleep      # want [s2idle], not [deep]
```

Forced via `/etc/tmpfiles.d/glymur-s2idle.conf` (`w /sys/power/mem_sleep - - - - s2idle`).
Chosen over a cmdline `mem_sleep_default=` specifically to avoid another GRUB edit.

⚠️ **Crash evidence is not currently collectable — but the reason above was wrong.**
This section used to blame mandatory `efi=noruntime`. Corrected 2026-07-30: that flag was
retired, and efivars are unreachable with or without it. EFI runtime services themselves **do** come up (`Remapping and enabling EFI services.`
at boot). What this INSYDE firmware does not support is the **variable** subset:
`GetVariable` returns `EFI_UNSUPPORTED` (status `0x8000000000000003`, logged as


⚠️ **Correction (2026-07-30, later the same day):** do not treat "this firmware does not support EFI variable services" as settled. Two archived `efi_pstore` crash dumps prove variable services **worked** on this same machine and firmware under 7.1 kernels. The `EFI_UNSUPPORTED` result above is real but is specific to our 7.2-rc3 build, and the cause is **unresolved**. See [`docs/crash-evidence.md`](docs/crash-evidence.md).
`integrity: Couldn't get size: 0x8000000000000003` / `MODSIGN: Couldn't get UEFI db list`).
So `efivar_is_available()` is false and `fsopen("efivarfs")` fails `EOPNOTSUPP`. Not a
kernel config gap: `CONFIG_EFIVAR_FS=y` and efivarfs is registered in `/proc/filesystems`.
So efivars-backed pstore was never available in the first place, which is why `/sys/fs/pstore` was empty after the 2026-07-24 crash. If suspend
crashes again, expect no post-mortem unless ramoops or netconsole is set up first — and
check whether `CONFIG_EFIVAR_FS` is even enabled in our kernel config.

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

⚠️ `logind` has `HandleLidSwitch=suspend` (set 2026-07-30 in
`tweaks/etc/systemd/logind.conf.d/99-glymur-suspend.conf`), so closing the lid **will** suspend.
That is safe on the suspend-capable entry and **will hard-reset the machine on any other**.

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

---

## test66 — REGRESSION, do not boot (2026-07-25)

test66 freed TLMM 94 (`regulator-wcn-3p3`) and 246 (`regulator-wwan`) on top of
test65. **It broke Wi-Fi and audio.** Boot test65 instead.

**Why it broke.** Freeing those two pins let the regulators probe, which unblocked
the devices waiting on them — and those devices then reached for pins that are
*still* reserved:

```
glymur-tlmm: error -EINVAL: pin-150 (1c00000.pci)
qcom-pcie 1c00000.pci: error -EINVAL: Error applying setting, reverse things back
glymur-tlmm: error -EINVAL: pin-116 (wcn7850-pmu)
pwrseq-qcom_wcn wcn7850-pmu: error -EINVAL: Error applying setting, reverse things back
```

Before test66 those devices sat in **deferred probe, which is harmless**. After, they
probe and *fail*, leaving the WCN power sequencer half-configured — Wi-Fi then dies
with endless `Timeout while waiting for regulatory update`. Audio also degraded
further: a second DSP timeout appeared, `CMD timeout for [1001002]`
(`APM_CMD_GRAPH_START`), after the card registered — which is why the usual
off/on toggle did not recover it.

**Lesson: deferred is better than broken.** Do not free a reserved pin unless every
pin its dependent chain needs is freed in the same change.

The complete set a working test67 would need (traced from the DTS):

| device | pins |
|---|---|
| `regulator-wcn-3p3` / `regulator-wcn-0p95` | 94 |
| `regulator-wwan` | 246 |
| `wcn7850-pmu` | 116 (bt-enable), 117 (wlan-enable) |
| `1c00000.pci` | 150 |

i.e. 94, 116, 117, 150, 246 — and even then it may expose a further layer.
**Judged not worth it:** Wi-Fi already works on test65 *because* these sit deferred.
The only gains would be a WWAN slot and silencing a cosmetic `gcc sync_state()`
message.

### Why "just move the ADSP later" does not fix the audio race

Measured, not assumed: the `omit_drivers` build booted the ADSP at **5.3s** instead
of 1.41s, and the card still registered at **10.359s** vs **10.36s**. Card
registration is gated by DSP readiness (~10s), not by ADSP driver load time.
Delaying the ADSP can only make it later.
