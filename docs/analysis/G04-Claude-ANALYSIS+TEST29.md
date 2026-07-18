# G04 — test28 result, myth-bust, live bus forensics, and test29 (Claude, 2026-07-11)

Follows `G03-Claude-ANALYSIS+TEST28.md`. test28 booted and **failed identically to test24/26/27**.
This session verified the failure against the boot log, the live box (i2cdetect/regulator),
the DTS, and the DSDT — overturning several standing theories and isolating the real blocker to
the **GENI transfer path on QUP_2_SE_3 (88c000)**, not the keyboard device.

## 1. test28 result (DT-TEST28.log)
Keyboard `3-0015`: early `-517` (normal deferred-probe ordering while `regulator-misc-3p3` came up —
it did, `returned 0 after 869us`), then once deps resolved i2c-hid attempted the transfer:
```
geni_i2c 88c000.i2c: Timeout abort_m_cmd      (x2, ~2s apart)
probe of 3-0015 returned 6 after 4082984 usecs   (-ENXIO, ~4.08s hang)
```
Restoring vdd/vddl/pinctrl (the G03 change) did **nothing**. Same failure as every prior attempt.

## 2. MYTH BUSTED — test24 never "ACKed + returned a zero descriptor"
The premise carried since G02 ("test24 ACKed but returned an empty HID descriptor / bcdVersion 0x0000")
is **false**. `DT-TEST24.log` shows the *identical* signature:
```
geni_i2c 88c000.i2c: Timeout abort_m_cmd (x2)
probe of 3-0015 returned 6 after 4095279 usecs
```
Verified in the DTS: test24.dts `keyboard@15` already had `vdd/vddl/pinctrl-0 = <0x6a/0x6b/0x8f>`, and
its `i2c@88c000` bus node is byte-identical to test27's. So **test28 ≡ test24 config-wise, and both fail
the same way.** Every keyboard attempt (24, 26, 27, 28) = the same no-ACK timeout, **invariant to clock,
device power, and device pinctrl.** The blocker is upstream of the i2c-hid device.

## 3. Live box forensics (test28 running)
- `sudo i2cdetect -l` → i2c-0, i2c-2, i2c-3, i2c-4 are the Geni-I2C adapters.
- `sudo i2cdetect -y -r 3` (88c000): **entire bus blank** — nothing ACKs at any address.
- `sudo i2cdetect -y -r 0` → `UU` at 0x15 (touchpad bound) + a live device at **0x33** (unclaimed; note for later).
- `sudo i2cdetect -y -r 4` → `UU` at 0x10 (touchscreen bound). Tool/method proven; only bus 3 is dead.
- `sudo i2ctransfer -y -f 3 w2@0x15 0x01 0x00 r4` → `Connection timed out` (x2).
- `gpioinfo`: lines **76 & 77 claimed** (`consumer=kernel` = the i2c controller); line 67 (IRQ) unclaimed
  (expected — HID device never probed).
- `regulator_summary`: **VREG_MISC_3P3 = on, 3300 mV** (keyboard vdd) and **vreg_l15b_e0_1p8 = on, 1800 mV**
  (vddl). **Power is confirmed ON at spec.**

**Reading:** the ~4-second hang ending in `Timeout abort_m_cmd` is NOT a fast NAK. A real "nobody home"
NAK returns immediately. A full-timeout-then-abort-timeout on **every** address = the geni-i2c driver
**never gets transfer completion** — no command on this bus ever finishes. That is why the whole bus looks
dead regardless of what's on it.

## 4. DSDT dig (acpi_dump_ubuntu/dsdt.dsl) — what Windows actually does
- `Device (ECKB)` = `_HID QTEC0001`, `_CID PNP0C50` (HID-over-I2C), `_UID 3`. `_CRS` = I2cSerialBusV2 **0x15
  on \_SB.IC20 @ 400 kHz** + `GpioInt` pin **0x2C0** on GIO0. `_DSM` fn1 → **0x01** (hid-descr-addr=1).
  `_STA`=0x0F. **No `_PS0`, no `_PR0` power resource, no GpioIo reset/enable, no wrapping power device.**
  → Windows toggles **no special enable GPIO**; the keyboard is meant to come up on bus + power + IRQ alone.
- `Device (IC20)` = `QCOM0F10`, `_STR "QUP_2_SE_3"`, **Memory32Fixed 0x0088C000** → **bus is definitively
  88c000.** Address/bus confirmed, not the CRD/DSDT-mismatch problem the touchpad had.
- `Device (GIO0)` = `QCOM0F0C`, base **0x0F100000** (the TLMM). No keyboard-enable field.
- Interrupt cross-check is **not usable**: DSDT GSIV → DT SPI is non-uniform (a80000 = GSIV−0x20, but
  b80000 = GSIV−0x1000, yet both work). So the CRD-derived `i2c@88c000` IRQ `0x248` cannot be called wrong
  from the DSDT — the CRD's own interrupt map is authoritative and the working buses prove it.

## 5. Everything ruled out this session
| Suspect | Verdict | Evidence |
|---|---|---|
| Clock (100/400 kHz) | not it | identical fail across tests |
| Device vdd/vddl/pinctrl | not it | test24≡test28, both fail; rails confirmed ON live |
| Rail actually off | not it | regulator_summary: MISC_3P3 3300mV, l15b 1800mV, enabled |
| Wrong bus/address | not it | DSDT IC20 = 0x0088C000 = QUP_2_SE_3 |
| Bus SDA/SCL pinctrl | not it | gpio76/77 `qup2_se3` + pull-up, byte-identical to working buses; pins claimed |
| Pins reserved | not it | 67/76/77 all outside gpio-reserved-ranges |
| EC enable/reset GPIO | not it | ECKB has no `_PS0`/`_PR0`/GpioIo; GIO0 has no kbd-enable |
| Wrong IRQ number | not it | CRD map authoritative; DSDT GSIV mapping non-uniform |
| SPI/i2c node conflict | not it | spi@88c000 = disabled (same as working buses) |
| GPI-DMA controller down | not it | `800000.dma-controller returned 0` |

## 6. Isolated differentiator → the GPI-DMA transfer path
88c000 is structurally identical to the working buses in **every** static/DT respect. The only remaining
difference: it sits under a different QUP wrapper (**8c0000 / QUP_2**) and routes tx/rx through
**GPI-DMA** (`dmas = <0x4b …>` → `dma-controller@800000`, `qcom,glymur-gpi-dma`). The DMA *controller*
probes, but the i2c transfers submitted to it **never complete** (the 4 s hang). The transfer mechanism is
the one untested variable that is unique to how this bus moves bytes.

## 7. test29 — force FIFO/PIO mode (single variable)
`glymur-a16-test29.dtb` = test28 with **`dmas` + `dma-names` removed from `i2c@88c000`**. This makes
geni-i2c stop using the QUP_2 GPI-DMA path and fall back to the SE FIFO/PIO engine (its own completion
IRQ). Built via `build_test29.py` (python-fdt patch of test28.dtb); re-parse verified: i2c node has no
`dmas`, `status=okay`, `keyboard@15` intact with vdd/vddl/pinctrl. Keyboard node byte-identical to test24/28.

### Expected outcome / how to read the boot
- **Success:** `abort_m_cmd` gone; `3-0015` ACKs → keyboard binds (or reveals a genuine *next* device-level
  issue, cleanly, for the first time).
- **Still `abort_m_cmd`:** the transfer path isn't the (whole) cause → it's the **completion interrupt not
  being delivered** for QUP_2_SE_3. Disambiguate live (no rebuild): `grep 88c000 /proc/interrupts` (or the
  geni i2c IRQ), run `i2cdetect -y -r 3`, re-check — if the count doesn't tick, the SE IRQ never fires →
  next lever is the interrupt routing/number for this SE specifically.

## 8. Staging (one-shot, from the box)
Sync `glymur-a16-test29.dtb` to the A16 share, then:
```
sudo cp /mnt/app_stuff/boot-kit/out/glymur-a16-test29.dtb /boot/glymur/ \
 && sudo sed -i 's/glymur-a16-test28.dtb/glymur-a16-test29.dtb/' /etc/grub.d/40_custom \
 && sudo update-grub \
 && sudo grep -H glymur-a16-test /etc/grub.d/40_custom \
 && sudo systemctl reboot -i
```

## 9. Unchanged / still-open
Battery = ASUS-EC path (`\_SB.ABD` QCOM1045 GenericSerialBus, separate workstream). GPU absent — defer to
7.2-rc. Touchpad(b80000)/touchscreen(a80000)/fan/Wi-Fi/USB untouched. The `0x33` device on bus 0 is
unexplained (unclaimed) — note for later, not keyboard-related.
