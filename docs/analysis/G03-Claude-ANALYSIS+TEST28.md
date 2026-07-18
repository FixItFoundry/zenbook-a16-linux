# G03 — Deeper dive on test27 + test28 (Claude/Fable, 2026-07-11)

Follows `G02-Claude-ANALYSIS+TEST27.md`. test27 booted; this doc reads its log, **overturns the standing "clock / EC-wake" theory**, and builds test28 from the evidence + the upstream ASUS reference DT.

## 1. What test27 actually did (DT-TEST27.log)
Boot is otherwise perfect (touchpad, touchscreen+stylus, Wi-Fi, USB, fan all bind). Keyboard result:
```
i2c_hid_of 3-0015: supply vdd not found, using dummy regulator
i2c_hid_of 3-0015: supply vddl not found, using dummy regulator
geni_i2c 88c000.i2c: Timeout abort_m_cmd      (x2)
probe of 3-0015 returned 6 after 4087848 usecs   (-ENXIO, hung ~4.1s)
```
**This is the test26 signature, not the predicted test24 one.** G02 expected that reverting 100 kHz → 400 kHz would bring back test24's "EC ACKs, returns zero descriptor." It did **not**. So the clock was never the differentiator — 400 kHz alone does not restore the ACK. Something else regressed between test24 and test26/27.

## 2. The real regression (test24.dts vs test27.dts diff)
The keyboard node in **test24** (EC ACKed) vs **test27** (bus timeout), both at 400 kHz:

| property | test24 (ACK) | test26/27 (timeout) |
|---|---|---|
| `reg` / `hid-descr-addr` | 0x15 / 0x1 | 0x15 / 0x1 |
| `interrupts-extended` | `<&tlmm 67 LEVEL_LOW>` | same |
| `clock-frequency` (bus) | 400 kHz | 400 kHz |
| **`vdd-supply`** | **`<VREG_MISC_3P3>`** (0x6a) | **removed** |
| **`vddl-supply`** | **`<vreg_l15b_e0_1p8>`** (0x6b) | **removed** |
| **`pinctrl-0`** | **`<kybd-default gpio67>`** (0x8f) | **removed** |

test26's changelog note said only "vdd stripped." In fact test26 stripped **three** bindings — `vdd-supply`, `vddl-supply`, and the keyboard's `pinctrl-0` — *and* dropped the clock. test27 reverted only the clock, leaving the three stripped. So the ACK→timeout regression tracks the **stripped power/pinctrl**, not the clock.

`abort_m_cmd` is a GENI **master-transfer** timeout — the target isn't ACKing on SDA/SCL. The most physical cause of a device that ACKed in test24 and no longer ACKs is **loss of power**:
- `vdd-supply` = **VREG_MISC_3P3**, a `regulator-fixed` **3.3 V load switch** gated by a GPIO (`gpio = <0x100 6 0>`, enable-active-high, `regulator-boot-on`, **not** `regulator-always-on`).
- When the keyboard node consumed it (test24), i2c-hid called `regulator_enable()` → load switch ON → keyboard powered → ACK.
- With no consumer (test26/27), the regulator core treats VREG_MISC_3P3 as unused and leaves/turns it **off** → keyboard controller unpowered → no ACK → `abort_m_cmd`. The "breathing" backlight is the EC alive on its own standby rail while the main 3.3 V keyboard rail is dead — exactly what you'd expect.

This also explains why lowering the clock (test26) looked "worse": at 100 kHz the same dead-bus transfer just takes longer to time out. Clock was a red herring throughout.

> Caveat worth stating: the *working* touchpad (`0-0015`) also logs "supply vdd not found, using dummy regulator" and works fine. That only means the **touchpad's** rail is left on by firmware. The keyboard's rail is behind a board-specific GPIO load switch (VREG_MISC_3P3) that firmware does **not** leave on — which is why the keyboard, uniquely, needs the DT supply. The test24-vs-test27 A/B on this exact machine is the proof, independent of the touchpad.

## 3. Web cross-check — upstream ASUS reference (X1E78100 Vivobook S15)
Mainline `x1e80100-asus-vivobook-s15.dts` (closest shipping ASUS Snapdragon laptop) wires its keyboard:
```
keyboard@3a {
    compatible = "hid-over-i2c";
    reg = <0x3a>;
    hid-descr-addr = <0x1>;
    interrupts-extended = <&tlmm 67 IRQ_TYPE_LEVEL_LOW>;   // <-- TLMM 67, LEVEL_LOW
    pinctrl-0 = <&kybd_default>;                           // gpio67, function "gpio", bias-disable
    pinctrl-names = "default";
    wakeup-source;
};
&tlmm { kybd_default: kybd-default-state { pins = "gpio67"; function = "gpio"; bias-disable; }; };
```
Two decisive confirmations:
1. **TLMM 67 + LEVEL_LOW + a `gpio67 function=gpio` pinctrl is the correct, shipping ASUS keyboard IRQ wiring.** G02 doubted TLMM 67; upstream vindicates it. (A16 addr/bus differ — DSDT says 0x15 on 88c000 — but the IRQ pin and pinctrl pattern are identical across ASUS Snapdragon boards.)
2. **Pin conflict found:** in test27.dts, `gpio67` is *also* declared in `qup-spi16-cs-state` with `function = "qup2_se0"`. Removing the keyboard's own `pinctrl-0` (which forces gpio67 to `function="gpio"`) risks leaving pin 67 muxed as a SPI chip-select instead of a GPIO IRQ. Restoring `pinctrl-0 = <kybd-default>` reclaims it — matching upstream.

(Upstream Vivobook has no `vdd-supply` on its keyboard because *its* board leaves the rail on. The A16 is a different board — X2 Elite/Glymur — whose DSDT gates the rail via VREG_MISC_3P3. Follow the A16's own evidence, not Vivobook's rail choice.)

## 4. lshw digest (lshwbus.log / lshw.log)
Confirms current live state only — no new bus surprises. Inputs enumerated: `hid-over-i2c 04F3:4645` (touchscreen/stylus, multiple event nodes), `hid-over-i2c 093A:3012 Touchpad/Mouse`, `pmic_pwrkey`, `pmic_resin`, `gpio-keys`, and the external `ASUSTeK ROG OMNI RECEIVER` (USB). **No internal keyboard node** — consistent with the failed 3-0015 probe. PCI = 4 devices (2 bridges, WLAN, NVMe); display = `simpledrmdrmfb` (EFI-fb). Nothing in lshw contradicts the DSDT bus map (i2c-3 = 88c000 = EC/keyboard).

## 5. test28 — the build (single, evidence-driven change set)
**test28 = test27 + re-add the three bindings test26 stripped**, keeping 400 kHz. Net effect: the keyboard node is now byte-for-byte the test24 node, but on the fully-working test26/27 platform.
```
keyboard@15 {
    compatible = "hid-over-i2c";
    reg = <0x15>;
    hid-descr-addr = <0x1>;
    interrupts-extended = <0x69 0x43 0x08>;   // TLMM 67, LEVEL_LOW
    vdd-supply  = <0x6a>;   // VREG_MISC_3P3  (3.3V GPIO load switch)   <-- restored
    vddl-supply = <0x6b>;   // vreg_l15b_e0_1p8 (1.8V LDO)              <-- restored
    pinctrl-0   = <0x8f>;   // kybd-default-state (gpio67 func gpio)    <-- restored
    pinctrl-names = "default";
    wakeup-source;
};
```
Built at `boot-kit/out/glymur-a16-test28.dtb` (via `build_test28.py`, python-fdt surgical patch of test27.dtb; phandles 0x6a/0x6b/0x8f verified still resolving in test27's tree). Bus stays `clock-frequency=0x61a80` (400 kHz), `status=okay`.

### Expected outcome / how to read the boot
- **Success-ish (most likely):** `abort_m_cmd` timeout **gone**; `3-0015` probes far enough to ACK. Then either the keyboard binds, or we're back at test24's "EC ACKs but returns a **zero HID descriptor**" — which is the *real* remaining blocker and is now cleanly isolated (power solved, IRQ correct).
- **If still -517 (EPROBE_DEFER)** on 3-0015: VREG_MISC_3P3's enable-GPIO controller (phandle 0x100) isn't up — check `cat /sys/kernel/debug/devices_deferred` and dmesg for that regulator/gpio.
- **If still `abort_m_cmd`:** power was not the (whole) cause — pivot to an EC wake sequence.

### If test28 reproduces "ACK + zero descriptor" → test29 levers (in order)
1. `post-power-on-delay-ms` on keyboard@15 (e.g. 100–500 ms) — EC may need settle time after the 3.3 V rail comes up before the HID descriptor is valid. (Standard i2c-hid property; low-risk, single-variable.)
2. Live-probe on the box: `i2cdetect -y -r 3`; raw descriptor read `i2ctransfer -y 3 w2@0x15 0x01 0x00 r4` and compare to the zero return.
3. i2c-hid SET_POWER / reset handshake timing; consider `hid-descr-addr` re-confirm from ECKB `_DSM`.
4. Only after the descriptor reads non-zero, revisit the IRQ for event delivery (TLMM 67 is already correct per upstream).

## 6. Staging (one-shot, run from the box)
The DC-side copy is written; sync it to the A16's SMB share, then stage. On the A16:
```
sudo cp /mnt/app_stuff/boot-kit/out/glymur-a16-test28.dtb /boot/glymur/ \
 && sudo sed -i 's/glymur-a16-test27.dtb/glymur-a16-test28.dtb/' /etc/grub.d/40_custom \
 && sudo update-grub \
 && sudo grep -H glymur-a16-test /etc/grub.d/40_custom \
 && sudo systemctl reboot -i
```
(If `boot-kit/out` on the A16 share is the *separate* copy, first copy `glymur-a16-test28.dtb` into `//192.168.8.10/App Stuff/boot-kit/out` so both sides match.)

## 7. Unchanged / still-open (context)
Battery = ASUS-EC path (`\_SB.ABD`/PMGK op-regions), not pmic_glink — separate workstream. GPU absent from base DTB — defer to 7.2-rc with upstream X-Elite Adreno nodes. Touchpad/touchscreen/fan/Wi-Fi/USB untouched by test28.

## Sources
- Mainline ASUS Vivobook S15 DT: [patchew v3 2/2](https://patchew.org/linux/20240630-asus-vivobook-s15-v3-0-bce7ca4d9683@gmail.com/20240630-asus-vivobook-s15-v3-2-bce7ca4d9683@gmail.com/)
- HID-over-I2C DT binding (vdd-supply, post-power-on-delay): [kernel.org](https://www.kernel.org/doc/Documentation/devicetree/bindings/input/hid-over-i2c.txt)
- i2c-hid regulator support: [patchwork briannorris](https://patchwork.kernel.org/project/linux-input/patch/1480638670-111492-1-git-send-email-briannorris@chromium.org/)
