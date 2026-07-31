> ## ★★★ SOLVED 2026-07-31 — `asus::kbd_backlight` exists and dims
>
> `/sys/class/leds/asus::kbd_backlight`, `max_brightness = 3`, four levels.
> Patch: [`../patches/glymur-hid-asus-a16-7.2.patch`](../patches/glymur-hid-asus-a16-7.2.patch).
> Persistent — the initramfs was rebuilt and the srcversion inside it matches on-disk.
>
> ### ⚠️ §2.4's "candidate fix" was wrong, and §2.2's diagnosis was only half right
>
> Adding `QUIRK_USE_KBD_BACKLIGHT` **is** necessary — without it `asus_kbd_register_leds()`
> is never called. But it is **not sufficient**, and the doc's claim that it "should register
> `asus::kbd_backlight` ... at which point UPower/KDE picks up the Fn keys with no further
> work" is **false on 7.2**. Two further things were needed.
>
> **(a) hid-asus no longer registers the LED at all.** Since the LED rework there is no
> `led_classdev_register` anywhere in `hid-asus.c`. The driver registers a *listener* and
> **asus-wmi owns the class device**. On a device-tree boot there is no ACPI, so no asus-wmi,
> so `asus_hid_register_listener()` returns `-ENODEV` and no LED can ever appear. The patch
> registers a `led_classdev` in that case and drives it through the existing
> `asus_kbd_backlight_work()`.
>
> **(b) ★ A real driver bug: `asus_kbd_get_functions()` sends a short feature report.**
> It sends 6 bytes; this keyboard silently ignores feature reports shorter than the declared
> report size. The command never lands, so the follow-up `GET_REPORT` returns the *handshake
> echo* left by `asus_kbd_init()`:
>
> ```
> raw: 5a 41 53 55 53 20 54 65 63 68 2e 49
>      5a  A  S  U  S     T  e  c  h  .  I
> ```
>
> `readbuf[6]` is `0x54` — the `'T'` of "Tech" — so `kbd_func` reads `0x54`,
> `SUPPORT_KBD_BACKLIGHT` (BIT 0) is clear, and the driver decides the keyboard has no
> backlight. Padding the command to `FEATURE_KBD_REPORT_SIZE` fixes it:
>
> ```
> raw: 5a 05 20 31 00 08 01 61 c1     kbd_func=0x01
> ```
>
> **This is not A16-specific and is worth reporting upstream.**
>
> How it was isolated, in case the same shape recurs: the identical query sent from userspace
> as a **64-byte** `HIDIOCSFEATURE` returned `0x01`, while the kernel's 6-byte form returned
> the stale handshake. Timing was ruled out explicitly — `msleep` before *and* after the
> command changed nothing. Only the length mattered.
>
> ### Also enabled: `QUIRK_HID_FN_LOCK`
>
> `asus_kbd_set_fn_lock()` (`{0x5a, 0xd0, 0x4e, enabled}`) already existed in the driver and
> is toggled from `KEY_FN_ESC` in `asus_event()`, gated on `QUIRK_HID_FN_LOCK`. Our entry
> lacked the bit, so Fn+Esc did nothing. Added. **Not yet confirmed by keypress.**
>
> ### Unrelated but worth knowing: the mute/camera LEDs already exist
>
> `orange:micmute`, `orange:indicator` and `white:indicator` are **platform LEDs from the
> device tree** (`/sys/devices/platform/leds/`), nothing to do with hid-asus. All
> `max_brightness = 1`, `trigger = none`. They are present but unwired — attaching triggers
> is a userspace/DT job, not a driver one.

# Keyboard backlight & brightness controls — what works, what doesn't

**Document date:** 2026-07-24
**Machine:** ASUS Zenbook A16 UX3607OA (glymur), Fedora 44 aarch64, `7.1.0-glymur-clean2`
**Keyboard:** I2C-HID `0B05:4B42` on `i2c-3` addr `0x15`, bound to the `asus` driver

> ## ⚠️ These are two independent workstreams. Do not conflate them.
>
> **The keyboard was fixed first, and separately.** The `hid-asus` work landed
> **2026-07-19**; the eDP bring-up ran **2026-07-20 → 07-24**. The keyboard has never
> depended on the display in any way — different driver, different subsystem, different
> fix, earlier date.
>
> Provenance: the running `hid_asus` is srcversion `98D1C85197C7DC4A34D456F`, identical
> to the on-disk module, built **2026-07-19 23:59**, and it carries the
> `hid:b0018g*v00000B05p00004B42` alias. None of the eDP work touched it.
>
> `CLAUDE.md` currently says *"brightness (needs eDP **and** a PMIC FGBCL driver)"*.
> That line is about the **display** panel only, and it is now stale — see §4. It has
> never applied to the keyboard backlight.

Two separate things get called "brightness" on this machine:

| | Fixed | State |
|---|---|---|
| **Keyboard backlight** (illumination under the keys) | 2026-07-19, `hid-asus` + hidraw | ⚠️ on, but via a **userspace hidraw hack**. No kernel LED device, Fn keys do nothing |
| **Display brightness** (the panel) | 2026-07-24, as a side effect of eDP | ✅ working — `dp_aux_backlight`, 0–2047 |

---

## 1. The keys themselves are fine

All the relevant keycodes are advertised by the input device and map correctly. Decoded
from `/proc/bus/input/devices` (`input16`, `event10`):

| code | key | present |
|---|---|---|
| 224 | `KEY_BRIGHTNESSDOWN` | yes |
| 225 | `KEY_BRIGHTNESSUP` | yes |
| 228 | `KEY_KBDILLUMTOGGLE` | yes |
| 229 | `KEY_KBDILLUMDOWN` | yes |
| 230 | `KEY_KBDILLUMUP` | yes |
| 212 | `KEY_CAMERA` | yes |
| 148 | `KEY_PROG1` (MyASUS) | yes |

`hid-asus` binds and fixes up the descriptor:

```
asus 0018:0B05:4B42.0003: Fixing up Asus N-Key report descriptor
asus 0018:0B05:4B42.0003: input,hidraw2: I2C HID v1.00 Keyboard [hid-over-i2c 0B05:4B42] on 3-0015
```

**So nothing is wrong at the input layer.** The keys emit events. The problem is that
nothing consumes the `KBDILLUM*` ones.

---

## 2. Keyboard backlight — the actual gap (and it looks like a one-word fix)

### 2.1 There is no `asus::kbd_backlight` LED device

```bash
$ ls /sys/class/leds/
input16::capslock  input16::compose  input16::kana  input16::numlock  input16::scrolllock
input19::capslock  ...
```

Only the standard lock LEDs. No keyboard-backlight LED class device exists.

### 2.2 Why

`asus_kbd_register_leds()` is gated at `drivers/hid/hid-asus.c:1341`:

```c
/* Laptops keyboard backlight is always at 0x5a */
if (is_vendor && (drvdata->quirks & QUIRK_USE_KBD_BACKLIGHT) &&
    (asus_has_report_id(hdev, FEATURE_KBD_REPORT_ID)) &&
        (asus_kbd_register_leds(hdev)))
```

It requires **`QUIRK_USE_KBD_BACKLIGHT`** = `BIT(5)`.

Our device-ID entry (uncommitted, in `drivers/hid/hid-asus.c`) sets only
**`QUIRK_ROG_NKEY_KEYBOARD`** = `BIT(11)`:

```c
{ HID_I2C_DEVICE(USB_VENDOR_ID_ASUSTEK,
    USB_DEVICE_ID_ASUSTEK_ZENBOOK_A16_KEYBOARD),
  QUIRK_ROG_NKEY_KEYBOARD },
```

`QUIRK_ROG_NKEY_KEYBOARD` does **not** imply `QUIRK_USE_KBD_BACKLIGHT` — they are
independent bits. So `asus_kbd_register_leds()` is never called for this keyboard.

### 2.3 The knock-on effect: our own fallback is dead code

The uncommitted `asus_event()` patch adds a direct-HID path for when `asus-wmi` is
absent (which is always, on a DT boot — see §2.5). But it is guarded on:

```c
if (drvdata->kbd_backlight) {
```

and `drvdata->kbd_backlight` is only ever allocated inside `asus_kbd_register_leds()`.
Since that never runs, **`kbd_backlight` is NULL and the entire fallback block is
unreachable.** It has never executed. Any conclusion drawn from testing it is void.

### 2.4 Candidate fix — untested

```c
  QUIRK_ROG_NKEY_KEYBOARD | QUIRK_USE_KBD_BACKLIGHT },
```

If `is_vendor` and `asus_has_report_id(hdev, 0x5a)` both hold — and the userspace script
in §3 is strong evidence that report ID `0x5a` works — this should register
`asus::kbd_backlight` with `max_brightness = 3`, at which point UPower/KDE picks up the
Fn keys with no further work.

The existing `-ENODEV` early-return patch in `asus_kbd_register_leds()` is **correct and
necessary** for this to work without `asus-wmi`; it just hasn't been reachable.

> Single-variable test: change only the quirk bits, rebuild `hid_asus`, `rmmod`/`modprobe`
> (this module is safe to hot-swap — unlike `msm`), and check for
> `/sys/class/leds/asus::kbd_backlight`.

### 2.5 `asus-wmi` is not available, and that is expected

```
CONFIG_ASUS_WMI          is not set
CONFIG_ACPI_WMI=y
CONFIG_X86_PLATFORM_DEVICES=y
```

`asus_hid_event()` therefore returns `-ENODEV`, which is exactly the case the fallback
patch exists to handle. `ACPI_WMI` and `X86_PLATFORM_DEVICES` were force-enabled on ARM64
via local Kconfig edits:

```diff
 menuconfig ACPI_WMI
-	depends on ACPI && X86
+	depends on ACPI
 menuconfig X86_PLATFORM_DEVICES
-	depends on X86
+	depends on X86 || (ACPI && ARM64)
 # drivers/platform/Makefile
+obj-$(CONFIG_X86_PLATFORM_DEVICES)	+= x86/
```

⚠️ **Not upstreamable in this form** — building `drivers/platform/x86/` on ARM64 by
relaxing its dependencies is a local expedient, not a design. If the §2.4 quirk fix works,
none of this is needed for the keyboard backlight and it can be dropped entirely.

---

## 3. What actually lights the keyboard today

A userspace script over `hidraw`, run once at boot and again after resume:

- `/usr/local/bin/asus-kbd-init.py`
- `/etc/systemd/system/asus-kbd-init.service` (oneshot, `WantedBy=multi-user.target`, enabled)
- `/usr/lib/systemd/system-sleep/asus-kbd-init` (resume hook)

It finds the hidraw node for `0B05:4B42` and sends two `HIDIOCSFEATURE` reports:

```python
init = [0x5a, 0x41,0x53,0x55,0x53,0x20,0x54,0x65,0x63,0x68,0x2e,0x49,0x6e,0x63,0x2e, 0x00] + [0]*48
bl   = [0x5a, 0xba, 0xc5, 0xc4, 0x03] + [0]*59
```

The first is the ASUS vendor handshake (`"ASUS Tech.Inc."`). The second is **byte-for-byte
what `asus_kbd_backlight_set()` in `hid-asus.c` sends** — report ID `0x5a`, then
`0xba 0xc5 0xc4 <level>`, with `level = 0x03` = max (`ASUS_EV_MAX_BRIGHTNESS`).

Last run:

```
Jun 26 20:00:12 loazen asus-kbd-init.py[4281]: asus-kbd-init: sent to /dev/hidraw2
```

### Consequences of doing it this way

- Backlight is **steady-on at maximum**. There is no way to dim it.
- **Fn keys do nothing** — the events are emitted (§1) and land nowhere.
- State is lost on suspend, hence the resume hook.
- Requires root access to `/dev/hidraw*`.
- The script silently `exit(0)`s on any error, so failures are invisible.

The script's real value is that it **proves the protocol works** on this keyboard. That
is the evidence the §2.4 fix is likely to succeed.

---

## 4. Display brightness — newly working (panel only; unrelated to §2–3)

**This section is about the display panel, not the keyboard.** Nothing here affects or
is affected by the keyboard backlight, which was already working before any of it (§2–3).

Previously blocked: with no eDP link there was no `backlight` class device at all, which
is why `CLAUDE.md` lists brightness as needing "eDP *and* a PMIC FGBCL driver." That
requirement was always about the panel.

As of the eDP link-up (see [`edp-hbr3-linkup-2026-07-24.md`](edp-hbr3-linkup-2026-07-24.md)):

```bash
$ cat /sys/class/backlight/dp_aux_backlight/brightness   # 206
$ cat /sys/class/backlight/dp_aux_backlight/max_brightness # 2047
```

Registered by `panel_samsung_atna33xc20` via the DP AUX backlight helper, and it is
demonstrably live — the panel's brightness DPCD register is being written during normal
use:

```
dpu_dp_aux: 0x00722 AUX <- (ret=2) 02 cc
dpu_dp_aux: 0x00722 AUX <- (ret=2) 01 9a
dpu_dp_aux: 0x00722 AUX <- (ret=2) 00 ce
```

**This appears to make the PMIC FGBCL requirement moot for the internal panel** — the
panel is driven over AUX (DPCD `0x722`), not by a PWM rail. Treat that as a correction to
be validated, not yet a settled fact: it has only been observed in one session, on a
hand-bound `msm`, with the display harness running.

### Still to verify

- That `KEY_BRIGHTNESSUP/DOWN` actually drive `dp_aux_backlight` through the desktop
  (the keycodes exist and the device exists, but the two have not been observed connected).
- Brightness persistence across suspend/resume and reboot.
- Behaviour on a clean boot without `modprobe.blacklist=msm`.

---

## 5. Summary

Keyboard items (§1–3) are the **2026-07-19 `hid-asus` workstream**. Display items (§4)
are a **2026-07-24 side effect of the eDP link-up**. The two are independent.

| Item | Workstream | Status | Blocker |
|---|---|---|---|
| Keyboard keys / keycodes | kbd, 07-19 | ✅ working | — |
| Keyboard backlight, on | kbd, 07-19 | ⚠️ userspace hidraw hack, max only | no kernel LED device |
| Keyboard backlight, dimmable | kbd | ❌ | `QUIRK_USE_KBD_BACKLIGHT` missing from the device entry (§2.4) |
| Fn keyboard-illum keys | kbd | ❌ | same — nothing consumes the events |
| `asus-wmi` integration | kbd | ❌ n/a | `CONFIG_ASUS_WMI` off; DT boot has no WMI. Fallback path exists but is unreachable |
| Camera / MyASUS keys | kbd | ✅ mapped | no consumer bound |
| Display brightness | eDP, 07-24 | ✅ working | — |
| Fn brightness keys → panel | eDP | ❓ untested | needs a desktop-session check |

### Next actions, cheapest first

1. **Add `QUIRK_USE_KBD_BACKLIGHT` to the A16 device entry**, rebuild `hid_asus`,
   `rmmod`/`modprobe`, look for `/sys/class/leds/asus::kbd_backlight`. No reboot needed.
2. If that works: retire `asus-kbd-init.py`, the service and the sleep hook, and drop the
   `drivers/platform/` Kconfig edits.
3. Confirm the Fn brightness keys drive `dp_aux_backlight` in a live session.
4. Only then consider what, if anything, from the `hid-asus` work is worth sending
   upstream — a device-ID + quirk addition is a normal, easily-accepted patch; the
   ARM64 platform/x86 Kconfig relaxation is not.
