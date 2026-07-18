# DT Bring-up Analysis — Test 20 Failure & Test 21 Recommendation

## What `test20` attempted to do
Based on the decompiled differences between `glymur-a16-test19.dtb` and `glymur-a16-test20.dtb`, test 20 attempted to enable three I2C controllers and the touchscreen:
1. **I2C9** (`i2c@a84000`) was enabled, and a touchscreen `hid@10` was added as a child node using TLMM pin 51 (`0x33`) for its interrupt.
2. **I2C11** (`i2c@a8c000`) was enabled.
3. **I2C4** (`i2c@b90000`) was enabled.

To allow these to probe, holes were punched in the `gpio-reserved-ranges` to free up the pins these controllers use.

## The Fatal Flaw
A mathematical off-by-one error was made when calculating the new `gpio-reserved-ranges`, resulting in only **half** of each I2C pin pair being freed. 

Here is the breakdown of the new reserved ranges in `test20.dtb`:
- `<0x0 0x10>`: Reserves pins 0–15. **(Frees pin 16)**
- `<0x11 0x13>`: Reserves pins 17–35. **(Frees pin 36)**
- `<0x25 0x7>`: Reserves pins 37–43. **(Frees pin 44)**
- `<0x2D 0x6>`: Reserves pins 45–50. **(Frees pin 51 — the touchscreen interrupt)**
- `<0x34 0x22>`: Reserves pins 52–85.

By starting the next reserved blocks precisely at 17, 37, and 45, pins 16, 36, and 44 were successfully freed, but pins **17, 37, and 45 were kept reserved**. 

Looking at the `pinctrl` nodes for the I2C controllers that were enabled:
- **I2C4** requires `gpio16` (SDA) and `gpio17` (SCL).
- **I2C9** requires `gpio36` and `gpio37`.
- **I2C11** requires `gpio44` and `gpio45`.

## Why this caused the boot to fail
This mistake guarantees a failure on two fronts:

1. **The I2C buses can never initialize:** Because one pin of every SCL/SDA pair is still explicitly reserved in the device tree, the `pinctrl` driver will refuse to mux the pins. The I2C controllers will instantly fail to probe (likely returning `-EBUSY` or `-EPROBE_DEFER`).
2. **The "Silent Killer" Watchdog Reset:** As documented in the runbook (`06_TONIGHT_RUNBOOK.md`), reading a TrustZone-protected pin causes an instant XPU violation and a hard watchdog reset. Because pins 16, 36, 44, and 51 were successfully unreserved, Linux attempted to read their hardware registers during `pinctrl` initialization. If even *one* of those four pins happens to be protected by ASUS's firmware, the machine suffers the exact same hard reset experienced in tests 1–11. 

## Test 21 Implementation
To properly free the I2C pairs (16+17, 36+37, 44+45) and the interrupt (51), the `gpio-reserved-ranges` should look like this:
- `<0x0 16>` (reserves 0–15)
- `<18 18>` (reserves 18–35)
- `<38 6>` (reserves 38–43)
- `<46 5>` (reserves 46–50)
- `<52 34>` (reserves 52–85)

*(Converted to hex for the DTB: `<0x0 0x10 0x12 0x12 0x26 0x6 0x2E 0x5 0x34 0x22 ...>`)*

I will construct `glymur-a16-test21.dtb` fixing this `gpio-reserved-ranges` math so the I2C controllers can properly acquire both their pins. If Test 21 still hard-resets, it will confirm that one of these newly-freed pins is a secure TrustZone pin on the ASUS firmware.

## IMPORTANT CORRECTION: Tests 20-22 and User Error
A massive breakthrough occurred due to a user error: **Test 21 never booted**. The user accidentally booted `test19.dtb` due to a misconfiguration in `grub.cfg`. 
Tests 20, 21, and 22 **ALL** triggered fatal Watchdog Resets!

This reveals a critical piece of the puzzle: In Tests 20-22, we punched holes for pins 16, 17, 36, 37, 44, 45, and 51 (which we thought belonged to the I2C controllers). However, the ASUS Zenbook **does not use** I2C4, I2C9, or I2C11. Because these were unused, ASUS TrustZone secured those pins. When we freed them in `gpio-reserved-ranges`, Linux touched them, instantly causing the watchdog reset.

## Test 23 Implementation
The actual controllers used by the Touchscreen (I2C8), Touchpad, and Keyboard (I2C10) use pins **0, 1, 32, and 33** (with interrupts on 3, 51, and 67). 
In Test 19 (which actually booted), ALL of these pins were safely locked in a massive reserved block (`0 to 85`).

For Test 23, we will use `test19.dts` as a baseline and perform a surgical strike to free **only** the pins needed by the real devices:
- `<0x2 0x1>` (Reserves 2, frees 0 and 1)
- `<0x4 0x1C>` (Reserves 4-31, frees 3)
- `<0x22 0x11>` (Reserves 34-50, frees 32 and 33)
- `<0x34 0xF>` (Reserves 52-66, frees 51)
- `<0x44 0x12>` (Reserves 68-85, frees 67)

We will also explicitly enable `i2c@a80000` and `i2c@b80000` while keeping the unused CRD controllers disabled.

## Test 24 Implementation
Test 23 was a massive victory on the TrustZone front! The watchdog was successfully bypassed and the I2C controllers `a80000` and `b80000` successfully probed without crashing the system! 
However, the devices (Touchpad, Touchscreen, Keyboard) returned `-ENXIO` (No such device or address) and `-EINVAL`.

Analysis of the ASUS ACPI tables (`dsdt.dsl`) revealed that the Qualcomm Reference Design (CRD) device tree uses completely different I2C addresses and controller layouts than what ASUS built:
1. **Touchscreen**: Wired to address `0x10` (not `0x38`), and requires pin 48 to reset (which we left reserved in Test 23).
2. **Touchpad**: Wired to address `0x15` (not `0x2C`).
3. **Keyboard & EC (Battery/Fan)**: Wired to a totally different controller (`i2c@88c000` / I2C19) at address `0x15`. This explains the 100% fan speed and 0% battery—Linux couldn't talk to the Embedded Controller because its bus was disabled and pins were reserved!

For Test 24, we will:
1. Fix the `reg` addresses for the Touchscreen (`0x10`) and Touchpad (`0x15`).
2. Move the Keyboard out of `i2c@b80000` and into `i2c@88c000` with `reg = <0x15>`, and enable `i2c@88c000`.
3. Update `gpio-reserved-ranges` to punch holes for pin 48 (Touchscreen Reset) and pins 76 & 77 (I2C19 SDA/SCL for the EC):
   `<0x2 0x1 0x4 0x1C 0x22 0xE 0x31 0x2 0x34 0xF 0x44 0x8 0x4E 0x8>`

## Test 25 Implementation
Test 24 was another huge milestone! The Touchscreen successfully initialized at `0x10`, and the fan dropped from 100% to quiet! This proves that `88c000` is indeed the Embedded Controller bus, and simply enabling it allows Linux thermal/power logic (or the EC itself) to stabilize the fan.

However, the Touchpad and Keyboard failed:
1. **Touchpad (`b80000`)**: Failed to probe with `-ENXIO`. The issue was that we provided the wrong `hid-descr-addr` (`0x20` instead of `0x1`), and we tried to force its power through the eDP regulator (`vdd-supply = <0x6A>`). Because Linux incorrectly managed its power, the touchpad never turned on to respond to its I2C address.
2. **Keyboard**: Probed on the EC bus (`88c000`) but returned an empty HID descriptor. Upon reviewing the mainline Linux patches for similar ASUS laptops, the actual human-interface keyboard is wired to **I2C5 (`b94000`)** at address `0x3a`. The device at `0x15` on `88c000` is exclusively the Embedded Controller.

For Test 25, we will:
1. Fix the Touchpad by removing `vdd-supply`/`vddl-supply` and setting `hid-descr-addr = <0x1>`.
2. Move the Keyboard to `i2c@b94000`, remove its `vdd-supply`, and enable `b94000`.
3. Update `gpio-reserved-ranges` to punch holes for pins 20 and 21 (required by `b94000`):
   `<0x2 0x1 0x4 0x10 0x16 0xA 0x22 0xE 0x31 0x2 0x34 0xF 0x44 0x8 0x4E 0x8>`
4. Advise the user to remove `modprobe.blacklist=msm rd.driver.blacklist=msm` from `grub.cfg` so the GPU can probe.

### Analysis of Test 25 & The Keyboard Heartbeat (July 11)
**Test 25 Results:**
- **Trackpad:** FULLY FUNCTIONAL! The HID descriptor address was indeed `0x1`, and removing the power binding allowed the firmware to naturally initialize the trackpad on `i2c@b80000`.
- **Keyboard:** FAILED with `-ENXIO` on `b94000` (`i2c5`) at `0x3a`. The keyboard backlights were seen pulsing from low to medium like a "heartbeat".

**Insights & Next Steps (Test 26):**
The pulsating heartbeat is the smoking gun! Asus Embedded Controllers (ECs) default to this "breathing" backlight behavior when powered on, waiting for an OS initialization command. Because the keyboard is breathing, it means the EC is powered and running, but waiting. 
Since `b94000` returned `-ENXIO`, the keyboard is **not** a separate chip on the A16. It is, in fact, the EC itself at `0x15` on `88c000`! 
In Test 24, we saw `0x15` return a `bcdVersion (0x0000)` HID error. This typically happens with Asus ECs if the I2C clock speed is too fast (400kHz) for initial probing, or if it isn't awakened properly. For Test 26, we will restore the keyboard to `88c000` but drop the I2C speed to 100kHz to give the EC time to respond. 

Additionally, we confirmed the Adreno GPU device node (`gpu@3d00000`) is completely missing from the base device tree, which explains why removing the `msm` blacklist had no effect. Test 26 will manually inject the GPU and GMU nodes from the upstream `x1e80100.dtsi`.

**Status:** `glymur-a16-test26.dtb` is compiled and ready for deployment in `Linux-X2-Project/boot-kit/out/`.
