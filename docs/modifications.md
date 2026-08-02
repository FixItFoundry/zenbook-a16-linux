# Modifications — every device-tree and kernel change, and why

Baseline is Konrad Dybcio's upstream A16 device tree on kernel **7.2.0-rc3** (linux-next
lineage). Everything below is what this project adds on top. For what each component *is*, see
[`hardware.md`](hardware.md).

- **Upstream baseline:** [`../upstream/dts/glymur-asus-zenbook-a16-ux3607oa.dts`](../upstream/dts/glymur-asus-zenbook-a16-ux3607oa.dts) (1271 lines)
- **Ours:** [`../dts/glymur-asus-zenbook-a16-ux3607oa-merged-gpu.dts`](../dts/glymur-asus-zenbook-a16-ux3607oa-merged-gpu.dts) (1476 lines)
- Delta: **233 changed lines**. Every local change is marked `GLYMUR-A16:` in the source.

---

## ✅ Source/DTB parity — closed 2026-08-02

Until 2026-08-02 the three fixes below existed **only inside the compiled DTB** — made by
decompile → edit → recompile and never back-ported — so building the tracked DTS produced a
machine with no cpufreq, no thermal actuation and dead HDMI.

**All three are now in the source and verified against the running machine.** The live DTB
(`/boot/glymur/glymur-a16-hdmi-nocomaux.dtb`) was pulled off `loazen` and diffed property by
property against a fresh build of `dts/glymur-asus-zenbook-a16-ux3607oa-merged-gpu.dts`:

| Property | live DTB | built from source |
|---|---|---|
| `arm,no-completion-irq` | 1 | 1 |
| `cooling-maps` nodes | 55 | **56** |
| `polling-delay-passive` | 64 | **65** |
| passive trips @ 95000 | 64 | **65** |
| `hysteresis` 1000 | 148 | **149** |
| `phy@88e1000` `clock-names` | `"aux", "ref", "usb3_pipe"` | identical |

Every zone matches the live one field for field — same trip temperature, hysteresis, polling
delay, cooling-device args and phandle.

★ **The +1 is deliberate and is an improvement.** Upstream `glymur.dtsi` contains a typo'd zone
name — `cpuillc-2-1-thermal`, with three i's. The hand-edited DTB matched on `cpullc-*` and
missed it, binding 41 zones; the source enumerates programmatically and binds **42**. It is a
real zone with a real sensor.

⚠️ **One thing deliberately NOT carried over:** the live DTB has a `ramoops@ffc00000`
reserved-memory node. It is left out because **ramoops cannot capture on this hardware** — DRAM
at that address does not survive a reset (proven with a canary across a clean reboot; the
firmware scrubs it). Re-adding it would only look like crash capture exists.

⚠️ `CLAUDE.md` still names `glymur-a16-merged-gpu-coolmaps.dtb` as the baseline. The GRUB default
actually loads **`glymur-a16-hdmi-nocomaux.dtb`** (coolmaps *plus* the `com_aux` removal).

### The DTS also did not build against upstream until this change

Two `/delete-node/` lines referenced labels that exist only in the vendor-patched tree this DTS
was originally developed on:

```dts
/delete-node/ &pmh0104_l1_thermal;    /* label does not exist upstream */
/delete-node/ &pmh0110_h0_thermal;
```

Upstream leaves those two zones unlabelled, so the deletes silently failed to resolve and left a
dangling phandle into a PMIC the DTS had just removed — a hard `dtc` error. Now deleted by path
(`&{/thermal-zones/pmh0104-l1-thermal}`), which works either way. **This is corroborating
evidence for the provenance problem** described at the end of this document.

---

## Device-tree changes

### Display / eDP — pin the PHY supply rails

```dts
&vreg_l2f_e1 { regulator-always-on; };   /* eDP vdda-phy */
&vreg_l4f_e1 { regulator-always-on; };   /* eDP vdda-pll */
```

**Why:** `qcom_edp_phy_exit()` drops these rails on teardown while the rest of the display block
still needs them, which hard-resets the SoC. This was the fix for the display-teardown crash —
the first off-survival ever achieved from a DT change alone.

⚠️ Not necessarily the *correct* fix; it is a rail-lifetime bug that plausibly belongs in the
PHY driver. Do not present it upstream as "the DTS was wrong."

### HDMI — drop one clock reference

```dts
/* phy@88e1000 (usb_2_qmpphy): remove com_aux from clocks/clock-names */
```

**Why:** `gcc_usb3_tert_phy_com_aux_clk` is stuck off — the branch never leaves halt because
there is no tertiary DWC3 controller to cast the vote a USB half would normally cast. The PHY
then fails `-EBUSY`, killing AUX, EDID and all modes.

**Legal because** `qmp_combo_clk_init()` fetches `{aux, cfg_ahb, ref, com_aux}` with
`devm_clk_bulk_get_optional()` — an absent clock returns `NULL` and is skipped. `cfg_ahb`
already proves this: it is missing from all three combo PHY nodes and nothing complains.

⚠️ A workaround, not the right fix. The DT correctly describes the PHY's clocks; the *driver*
enables `com_aux` unconditionally for an instance with no USB half. The proper fix likely
belongs in `phy-qcom-qmp-combo.c` or GCC.

### CPU frequency — one property, the whole fix

```dts
&scmi { arm,no-completion-irq; };
```

**Why:** the PDP0/CPUCP firmware answers SCMI protocol 0x13 (Performance) in shared memory but
**never rings the mailbox doorbell** for it. The same message returns `status 0` in polling mode
and hangs forever in interrupt mode; the doorbell IRQ counter never moves for 0x13. This
property makes the SCMI core poll. Documented upstream boolean, no kernel patch needed.

Measured, not guessed: 8 messages sent in IRQ mode → IRQ 156 went 9→16 (one per reply) and
**zero** for 0x13.

### Thermal — bind the cooling devices

`passive` trip at 95 °C plus `cooling-maps` on all 41 `cpu*`/`cpullc*` zones, tying them to the
`cpufreq-cpu0/6/12` cooling devices the cpufreq fix created.

⚠️ **The "no zone binds them" gap never existed for long** — the *verifier* was broken. It
counted `thermal_zone*/cdev*_type`, an attribute this kernel does not have, so it returned 0
unconditionally. Working check: [`../scripts/thermal/glymur-coolmaps-check.sh`](../scripts/thermal/glymur-coolmaps-check.sh).

### USB-C / UCSI — delete two properties

```dts
&usb_2_qmpphy {
	/delete-property/ mode-switch;
	/delete-property/ orientation-switch;
};
```

**Why:** UCSI/Type-C only enumerates with the role switch gone. With them present the PPM never
initialised (`ucsi_glink … PPM init failed`) and neither Type-C port appeared. Removing them
brought up `port0`/`port1` **and** DP alt-mode on both ports, **and** fixed AC/charger detection
as a side effect.

### Wi-Fi / Bluetooth

- Wi-Fi brought up through the `qcom,wcn7850-pmu` power-sequencing binding; `qcom_wcn` pwrseq
  asserts the rail rather than hand-rolled regulator asserts.
- Pin/GPIO ownership corrected for `tlmm 116/117`, `wcn_wlan_bt_en`.
- **WCN7850 Bluetooth serdev node added** — Konrad's tree enables the UART but does not wire the
  controller to it.

### Battery / SOCCP

`&remoteproc_soccp` is **deliberately omitted** — the SOCCP is UEFI-loaded and already running,
so the DT must not try to boot it. (The label does not exist in this lineage either.)

### GPU

`gpu@3d00000` and its SMMU set `status = "okay"`. Two DTS variants exist purely so the GPU can
be a single boot-time variable:

| file | GPU |
|---|---|
| `glymur-asus-zenbook-a16-ux3607oa-merged.dts` | disabled |
| `glymur-asus-zenbook-a16-ux3607oa-merged-gpu.dts` | **enabled — this is the baseline** |

⚠️ Requires that `gpucc_glymur` is **not** blacklisted on the cmdline.

### Smaller deltas

| Change | Why |
|---|---|
| `qcom,uefi-rtc-info` **removed** | RTC comes up as read-only PMIC RTC instead |
| `/delete-node/ &pmh0104_l1_thermal`, `&pmh0110_h0_thermal` | secondary-PMIC thermal zones whose PMICs never probe (see SPMI) |
| `pcie4_port0_ep` referenced by path | 7.2-rc3 `glymur.dtsi` has no such label |
| Lid switch on TLMM 92, active-low | recovered from the WoA DSDT; needs pin 92 freed from `gpio-reserved-ranges` |

---

## Kernel patches

Seven patches are tracked. Diagnostic scaffolding that produced findings but is not needed to
run the machine lives in `internal/patches-diagnostic/` (untracked).

| Patch | What it does | Status |
|---|---|---|
| [`glymur-scmi-no-completion-irq-CONFIRMED.patch`](../patches/glymur-scmi-no-completion-irq-CONFIRMED.patch) | The cpufreq fix, as a patch form of the DT property | ✅ boot-tested, passed |
| [`glymur-suspend-noirq-knobs-DIAGNOSTIC.patch`](../patches/glymur-suspend-noirq-knobs-DIAGNOSTIC.patch) | Adds `glymur_pci_skip` / `glymur_pm_skip*` cmdline knobs | ⚠️ **PRODUCTION DEPENDENCY — see below** |
| [`glymur-hid-asus-a16-7.2.patch`](../patches/glymur-hid-asus-a16-7.2.patch) | Zenbook A16 keyboard: vendor usage map + `QUIRK_FILTER_CAMERA_COMPANION` | ✅ in daily use |
| [`glymur-soccp-glink-7.2-hooks.patch`](../patches/glymur-soccp-glink-7.2-hooks.patch) | Hooks for the custom `soccp_glink` battery driver on 7.2 | ✅ in daily use |
| [`glymur-edp-rate-set-UPSTREAM.patch`](../patches/glymur-edp-rate-set-UPSTREAM.patch) | eDP `LINK_RATE_SET` handling | 🔼 upstream candidate |
| [`glymur-edp1-net.patch`](../patches/glymur-edp1-net.patch) | Per eDP 1.4b, `LINK_BW_SET` must be cleared before `LINK_RATE_SET` is written | 🔼 upstream candidate |
| [`glymur-gdsc-genpd-teardown-UPSTREAM.patch`](../patches/glymur-gdsc-genpd-teardown-UPSTREAM.patch) | GDSC/genpd teardown ordering | 🔼 upstream candidate |

### ⛔ The DIAGNOSTIC label on the suspend patch is a trap

`glymur-suspend-noirq-knobs-DIAGNOSTIC.patch` is named as scaffolding but it provides
`glymur_pci_skip`, and **the daily-driver GRUB entry boots with `glymur_pci_skip=5`.** Without
this patch the machine hard-resets on lid close. It is a production dependency wearing a
diagnostic name. Do not archive it on the strength of the filename.

---

## Non-kernel local configuration

These live under `tweaks/` and are hardware-specific enough to be worth keeping; see
[`../LOCAL-TWEAKS.md`](../LOCAL-TWEAKS.md).

- `/etc/tmpfiles.d/glymur-s2idle.conf` — forces `mem_sleep` to `s2idle` (Snapdragon has no S3)
- `asus-kbd-init` — the userspace hidraw handshake that turns the keyboard backlight on
- tuned profiles, udev rules for LEDs, ALSA UCM2 for the 4.0 speaker layout

---

## Upstreaming status

Nothing here has been submitted. Two things block it:

1. **Provenance.** The kernel tree the DTS was developed against carries a `glymur.dtsi`
   introduced by a commit labelled *"Add linux-next specific files"*, and its delta includes
   vendor GPU OPP/ACD constants (`qcom,opp-acd-level = <0x88295ffd>`) that the stated reason
   does not account for. Until `glymur.dtsi` is reconstructed as upstream + specific citable
   patches, no change here can be honestly attributed.
2. **The source/DTB gap** at the top of this file.

Credit for adopted upstream work is tracked in [`../UPSTREAM-CREDITS.md`](../UPSTREAM-CREDITS.md)
and must be updated in the same change that adopts something.
