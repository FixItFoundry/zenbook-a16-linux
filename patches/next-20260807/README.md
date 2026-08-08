# Delta against `next-20260807`

The full stack that turns a stock linux-next snapshot into the kernel this laptop
daily-drives. Generated with `git format-patch --base=next-20260807`, so each patch carries a
real `index` line and applies with `git am`.

Build name: **`7.2.0-rc6-ZenbookA16-20260807`** (see [`../../kernel/README.md`](../../kernel/README.md)).

| patch | what | upstreamable? |
|---|---|---|
| `0001` SCMI polling | the CPUCP answers protocol 0x13 but never rings the doorbell, so every perf transfer times out and `scmi-cpufreq` probes `-110`. One DT property. | **yes** — sent as a DT change |
| `0002` eDP `LINK_RATE_SET` | `rate_set`/`use_rate_set` were computed into `panel->link_info` but read from `link->link_params`, so the eDP 1.4 rate-set path was dead code. Also clears `LINK_BW_SET` first, which the spec requires and firmware leaves dirty. | ⛔ **not on its own** — see below |
| `0003` DP `push_idle` guard | `msm_dp_ctrl_push_idle()` on a controller that was never powered on times out, and the PHY is then left up. On glymur that is answered by a TrustZone force-stop and a silent SoC reset. | **yes** — this is upstream mail #1 |
| `0004` force eDP max rate | **LOCAL.** Drives the internal panel above its advertised maximum. The v8 PHY only trains at HBR3; the panel advertises HBR2 as its max, so the spec-correct choice is the one rate that cannot work. | **no** — the real fix belongs in `phy-qcom-edp.c` |
| `0005` `glymur_pci_skip` | **LOCAL.** Suspend workaround: PCI config access in `dpm_suspend_noirq` resets the SoC. `=5` skips `pci_prepare_to_sleep` and `pci_save_state`. | **no** — a diagnostic knob doing production duty |
| `0007` HID Zenbook keyboard | the device ID is already upstream; this adds the backlight, N-Key and Fn-lock quirks it is missing, plus short-feature-report padding and an `asus::kbd_backlight` for device-tree boots. | **yes** — see below |

(`0006` is a build-tree convenience that drops `localversion-next`; it is not part of the
hardware delta and is not published here.)

## ⛔ `0002` is correct and must not be sent alone

It makes the eDP 1.4 rate-set path reachable, which is a real bug fix — and on this laptop
that is exactly what breaks the display. The panel advertises HBR2 as its maximum, the v8
PHY can only train at HBR3, so honouring `LINK_RATE_SET` lands the link on the one rate
that provably cannot train: `link training #2 on phy 0 failed. ret=-110`.

It behaves here only because `0004` overrides the selected rate immediately afterwards.
Measured over 14 boots: 8 boots without it, zero link-training failures; 6 boots with it
and without `0004`, failures on every one.

Sending it by itself would regress every machine with this panel/PHY pairing. The PHY
limitation has to be understood first — that is what the eDP bug report is for.

## ⛔ Before sending any of these upstream

**None of them carry a `Signed-off-by`.** Only Jesse can certify the DCO, so it is
deliberately absent — add it below the `Assisted-by:` trailer on the patches you send.
`Assisted-by:` is required by `submitting-patches.rst`; an agent must not add
`Signed-off-by:`.

## What `next-20260807` absorbed

Tracking linux-next immediately paid for itself on `0007`. Between `next-20260803` and
`next-20260807` upstream refactored `asus_kbd_leds` into a generic `asus_worker` action queue
and took `BIT(15)`, which our quirk had used. Forward-porting it removed three things we had
been carrying:

- **the backlight level write** — upstream's new `asus_kbd_set_brightness()` already writes the
  level index rather than a PWM duty, which is what this controller wants
- **the hotkey cycling branch** — only reachable when asus-wmi is present, and unreachable there
- **all three hotkey mappings** (`0x85` camera, `0x86` MyASUS, `0x5f` programmable) — now
  upstream with identical values, including the `0x85 → KEY_CAMERA` correction, which upstream
  arrived at independently

Then the boot test found the bigger one. **`next-20260807` added this keyboard's device ID**:

```c
#define USB_DEVICE_ID_ASUSTEK_I2C_ZENBOOK_KEYBOARD	0x4b42     /* upstream, new */
#define USB_DEVICE_ID_ASUSTEK_ZENBOOK_A16_KEYBOARD	0x4B42     /* ours -- same device */
```

Upstream's entry sits earlier in `asus_devices[]`, so it matched first and ours was never
reached. Its quirk set is `I2C_KEYBOARD_QUIRKS | QUIRK_FILTER_CAMERA_COMPANION` — no
backlight, no N-Key fixup, no Fn lock. Symptom on a booted machine: `hid-asus` binds
normally and the keyboard types fine, but `asus::kbd_backlight` never appears and the
"Fixing up Asus N-Key report descriptor" message is gone.

So `0007` is now a much better patch than the one we were carrying: it adds the missing
quirks to an entry upstream already owns, rather than proposing a duplicate device ID. Our
duplicate `#define` is deleted, and `hid-ids.h` is untouched.

The part worth their attention is not A16-specific at all: `asus_kbd_register_leds()` leaves
`asus::kbd_backlight` to asus-wmi, which cannot exist on a device-tree boot. **Any ASUS
keyboard booted from DT has no backlight LED**, not just this one.
