# G02 — Analysis & test27 (Claude/Opus, 2026-07-11)

Companion to Gemini's `G01-Gemini3.1-ANALYSIS+TESTS.md`. Covers the live-box probe after test26, the DSDT keyboard ground truth, and the test27 build.

## Live state after test26 (SSH probe, running glymur-a16-test26.dtb, 7.1.0-glymur-full)
- **Working:** touchscreen + stylus (Elan 04F3:4645 @0x10 on a80000/i2c-4), touchpad (Pixart 093A:3012 @0x15 on b80000/i2c-0), Wi-Fi (ath12k), USB, fan quiet.
- **Dead:** internal keyboard; battery (`qcom-battmgr-bat` present but every field blank).
- **Only keyboard the kernel sees** = external USB ROG Omni Receiver dongle.
- **Live i2c bus map:** i2c-0 = b80000 (touchpad 0x15) · i2c-2 = b94000 (empty) · i2c-3 = 88c000 (EC/keyboard 0x15) · i2c-4 = a80000 (touchscreen 0x10).

## test26 result (booted, no functional loss)
Keyboard is now correctly targeted at `3-0015` (0x15 on 88c000), but the boot log shows a **regression** vs test24:
```
i2c_hid_of 3-0015: supply vdd/vddl not found, using dummy regulator
geni_i2c 88c000.i2c: Timeout abort_m_cmd        (t=2.5s)
geni_i2c 88c000.i2c: Timeout abort_m_cmd        (t=4.6s)
probe of 3-0015 returned 6 after 4096385 usecs  (-ENXIO, after hanging 4.1s)
```
In test24 (400kHz) the EC *answered* at 0x15 but returned a zero HID descriptor (bcdVersion 0x0000). In test26 (100kHz) the I2C master command now **times out** — dropping the clock made it worse, not better. lspci still shows only 4 devices (no Adreno); `/sys/class/drm/card0` is simpledrm (EFI-fb).

## DSDT ground truth for the keyboard (the decisive find)
The A16's own ACPI DSDT defines the keyboard explicitly (this beats guesses from other laptops):
- Device **ECKB**: `_HID "QTEC0001"`, `_CID "PNP0C50"` (HID-over-I2C)
- `I2cSerialBusV2(0x0015, ControllerInitiated, 0x00061A80 = 400 kHz, "\_SB.IC20")`
- `GpioInt(Level, ActiveLow, ...Wake...)` pin **0x2C0** on `\_SB.GIO0`
- Controller **IC20** `_CRS` = `Memory32Fixed(0x0088C000)` → **IC20 = the 88c000 bus**

So the internal keyboard is **0x15 on i2c@88c000 at 400 kHz** — exactly where test26 puts it. Gemini's earlier test25 location (0x3a on b94000, taken from a different ASUS laptop) is wrong: that boot logged `probe of 2-003a returned 6` (-ENXIO, nothing ACKs at 0x3a).

Sibling devices for reference: touchpad **ECAP** (`QTEC0003`, 0x17 on IC11 = a88000, IRQ 0x3C0); the *working* touchpad is empirically on b80000/0x15 (CRD wiring Gemini kept), i.e. the empirical map ≠ the ASUS ACPI map — do not disturb what already works.

## Why test27 = revert to 400 kHz (single variable)
All working input IRQs use the **TLMM** pinctrl (phandle 0x69): touchscreen TLMM 51, touchpad TLMM 3. The keyboard currently uses TLMM 67 (an unproven guess). But the DSDT keyboard IRQ 0x2C0 (=704) is above the 249-pin TLMM range, so it is really a PMIC-GPIO in the undecoded GIO0 aggregate — TLMM 67 is probably wrong.

Key point: the i2c-hid **HID-descriptor read is a plain register read and does not require the interrupt**. So the failing step in test24/test26 (getting the descriptor) is not an IRQ problem — it's the **EC not answering the descriptor until it is woken/initialised**. The IRQ only matters later, for delivering keypress events.

test27 therefore changes exactly one thing from test26: **`i2c@88c000` clock 100 kHz → 400 kHz (0x186a0 → 0x61a80)**. Everything else identical. This restores the test24 "EC responds" baseline, now stacked on the fully-working test26 platform. Verified in the compiled DTB; keyboard node still `reg=0x15`, `hid-descr-addr=0x01`, `wakeup-source`.

## Next steps (test28+), in order
1. Boot test27, confirm it reproduces "EC ACKs at 0x15, zero descriptor" at 400 kHz (i.e. the timeout is gone).
2. Install `i2c-tools` and live-probe i2c-3: `i2cdetect -y -r 3` (does 0x15 ACK?), then a raw HID descriptor read with `i2ctransfer` to see what the EC returns before any wake.
3. Try to wake the EC before/at probe: a `post-power-on-delay-ms`, an i2c-hid SET_POWER sequence, or a GPIO/EC wake. The "breathing" backlight = EC powered, waiting for an OS init it never receives.
4. Only after the descriptor reads correctly, chase the real interrupt (decode GIO0 pin 0x2C0 → the PMIC-GPIO controller/line) so key events are delivered.

## Battery (separate workstream)
DSDT `\_SB.ABD` / `PMGK` is the ASUS EC; it exposes the battery gauge (BIXD/BPCD/BPSD op-regions at EC I2C addresses 0x04/0x06/0x08). On the A16 the battery lives behind the ASUS EC over I2C, **not** pmic_glink — so `qcom_battmgr` will never populate. Needs an ASUS-EC access path; do not chase it through pmic_glink.

## GPU (deferred, agreed)
`gpu@3d00000` is absent from the base DTB and hand-grafting it needs a dozen gpucc/rpmhpd/smmu phandles (panic-prone). Correct path is a newer base kernel (7.2-rc) with upstream X-Elite Adreno nodes.

## Artifacts
- `boot-kit/out/glymur-a16-test27.dtb` and `boot-kit/out/test27.dts` (also staged at `/boot/glymur/` on the A16).
- grub "DT EXPERIMENT" entry (40_custom) repointed to test27 and `update-grub` run — ready to boot.
