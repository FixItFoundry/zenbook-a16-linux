# Hardware components — what each one is, how it connects, and where it stands

ASUS Zenbook A16 **UX3607OA** · Qualcomm Snapdragon **X2 Elite Extreme** (`glymur`,
X2E94100, 18 cores) · working baseline `7.3.0-rc3-ZenbookA16-20260919-rc3-integrated1+`.

**Current status:** [build and validation record](current-build.md). Older sections
below retain historical measurements; they are not blanket RC3 validation.

This is the single component reference. For the exact device-tree and kernel changes behind
each "what we changed" line, see [`modifications.md`](modifications.md).

**Reading rule:** every status below is either ✅ working with a check you can run, ⚠️ working
on a workaround, or ❌ not working with the reason. If a claim has no check, treat it as
unverified.

---

## Platform and boot chain

| | |
|---|---|
| SoC | Snapdragon X2 Elite Extreme, `qcom,x2e94100`, 18 cores in 3 clusters of 6 |
| Firmware | INSYDE UEFI (retail `UX3607OA.309`) |
| Boot | GRUB → raw arm64 `Image` + separate DTB via `devicetree` |
| Root | NVMe, `/dev/nvme0n1p17` |

The DTB is **not** supplied by firmware — GRUB loads ours explicitly. This requires
`insmod fdt` emitted at top level; without it every `devicetree` line fails *silently* and the
machine boots the firmware's own DT, which looks like "my changes did nothing."

⚠️ `systemd.mask=dev-tpm*.device` is **required** on the cmdline — without it the boot stalls
~90 s probing a TPM that never answers.

❌ **EFI variable services are unavailable** on this 7.2-rc3 build (`GetVariable` returns
`EFI_UNSUPPORTED`), so `efivarfs` fails and efivars-backed pstore does not exist. Two archived
crash dumps prove variable services *did* work under 7.1 on the same firmware — the regression
is unexplained.

⛔ **ramoops can never capture on this hardware.** DRAM at `0xffc00000` does not survive a
reset — proven with a canary across a clean reboot; the firmware scrubs it. This is why every
post-crash pstore has been empty. Netconsole over the USB-A NIC is the only crash-capture route.

---

## Display — eDP panel ✅

**Chain:** `mdss_dp3` (eDP controller) → eDP PHY → Samsung ATNA33XC20-class panel,
2880x1800 @ 120 Hz, trains at **HBR3**.

Backlight is driven **over DP AUX** (DPCD `0x722`), not a PWM rail — so no PMIC backlight
driver is needed for the internal panel.

**What we changed:** pinned the eDP PHY supply rails `regulator-always-on`
(`vreg_l2f_e1` = `vdda-phy`, `vreg_l4f_e1` = `vdda-pll`). This fixed a hard SoC reset on
display teardown — `qcom_edp_phy_exit()` dropped rails the rest of the block still needed.

```sh
cat /sys/class/drm/card1/card1-eDP-1/status   # connected
ls /sys/class/backlight/                       # dp_aux_backlight
```

⛔ Do not re-derive the eDP elimination list — it is in the maintainer’s private eDP notes. In particular the old
reasoning "UEFI left `LINK_BW_SET = 0x14` so the firmware's known-good link is HBR3" is
**wrong** (`0x14` is 5.4G; HBR3 is `0x1e`). Why 8.1G works is still unexplained.

## GPU — Adreno X2 ✅

**Chain:** `gpu@3d00000` (Adreno) + `gpucc_glymur` clock controller + GMU firmware
(`gen80100_sqe.fw`), rendering through **Mesa turnip**.

**What we changed:** nothing in the driver. The blocker was our own stale
`modprobe.blacklist=gpucc_glymur` on the cmdline — `gxclkctl` runtime-resumes gpucc at probe,
and without it the Adreno SMMU times out and the entire `msm` component bind fails.

⛔ **Do not start a gpucc decompile.** The drivers are in-tree and work.

Remaining: no hwmon so `nvtop` reports N/A, and no sustained stress testing.

★ **The zap-shader gap is a missing DT node, not a missing file — corrected 2026-08-02.**
`gen80100_zap.mbn.xz` **is already installed** on this machine (`/lib/firmware/qcom/glymur/`,
from upstream `linux-firmware`, redistributable) and the driver *still* falls back:

```sh
ls /lib/firmware/qcom/glymur/gen80100_zap.mbn*   # present
journalctl -k -b | grep -i zap                   # "Zap shader not enabled - using SECVID_TRUST_CNTL instead"
```

That message is printed at `a8xx_gpu.c` only on `-ENODEV`, and `-ENODEV` is returned by
`zap_shader_load_mdt()` in `adreno_gpu.c` at exactly one place:

```c
np = of_get_available_child_by_name(dev->of_node, "zap-shader");
if (!np) { zap_available = false; return -ENODEV; }
```

There is **no `zap-shader` child node** under `gpu@3d00000` in `glymur.dtsi` or in any of our
DTS files — grep for `zap` returns nothing.

### ⛔ TESTED 2026-08-02 — the DT node works and the zap shader still cannot load

The node was added and booted (linux-next 20260731, `7.2.0-rc5-glymur-next0731`):

```
gpu_zap_shader: zap-shader {
        memory-region = <&gpu_microcode_mem>;
        firmware-name = "qcom/glymur/gen80100_zap.mbn";
};
```

Result — the `-ENODEV` fallback message disappears, so the DT half is **correct and
sufficient**. But the load then fails one step later, and **that failure takes the GPU down
with it**:

```
adreno 3d00000.gpu: error -22 initializing firmware qcom/glymur/gen80100_zap.mbn
msm_dpu ae01000.display-controller: [drm:adreno_load_gpu] *ERROR* gpu hw init failed: -22
platform 3d6c000.gmu: [drm:a6xx_gmu_set_oob] *ERROR* Timeout waiting for GMU OOB set GPU_SET
```

★ **`-22` is `-EINVAL` returned by `qcom_pas_init_image()` — i.e. by TrustZone, not by Linux.**
Sourced, not guessed:

- The message text `"error %d initializing firmware %s"` is printed in `__qcom_mdt_pas_init()`
  immediately after `qcom_pas_init_image()`. The *metadata* failure has a different string
  (`"error %d reading firmware %s metadata"`) and did **not** appear, so parsing succeeded.
- The image is structurally valid. Its three program headers decode as the metadata segment
  (`p_flags` mdt-type `0x7`), one relocatable `PT_LOAD` (`0x3fc` @ `0x1000`), and a proper
  **HASH** segment (`p_flags & QCOM_MDT_TYPE_MASK == 0x2000000`). `qcom_mdt_read_metadata()`
  scans `i = 1 .. e_phnum` for the hash, so its position at index 2 is fine.
- Size is not the problem either: `0x3fc` against the `0x2000` `gpu_microcode_mem` carveout.

⇒ The kernel builds a well-formed request and **the secure world returns the failure**
(PAS ID 13, `GPU_PAS_ID` in `a8xx_gpu.c`).

⚠️ **`-22` carries almost no diagnostic information — do not over-read it.**
`qcom_scm_remap_error()` maps *both* `QCOM_SCM_EINVAL_ADDR` and `QCOM_SCM_EINVAL_ARG` to
`-EINVAL`, **and returns `-EINVAL` as its default for any code it does not recognise**. Two
explanations were built on this errno and **both were then disproven by test** — they are
recorded here so nobody re-proposes them:

⛔ **Disproven #1 — "TrustZone rejects the signature, unfixable fusing."** See the control
below: TZ authenticates a sibling ASUS-signed blob on this same machine.

⛔ **The "wrong image" theory was also tested and is dead.** The zap shader is signed per
device, and the ASUS-signed blob for this exact model ships in linux-firmware and is already
installed: `qcom/glymur/ASUSTeK/UX3607OA/qcdxkmsuc8480.mbn` (same 12088 bytes and identical
segment layout as the generic image, different md5 — same payload, different signature; the
naming matches `qcdxkmsuc8280` for sc8280xp and `qcdxkmsuc8380` for x1e80100). Pointing
`firmware-name` at it **fails identically with `-22`.** There is exactly one glymur zap blob
in linux-firmware, so there is no other candidate.

★★ **The control that settles it: PAS/TrustZone authentication demonstrably WORKS here.**
The ADSP is running, loaded by `qcom_q6v5_pas` through the same
`qcom_pas_init_image()` → `qcom_pas_auth_and_reset()` path, from the same vendor directory:

```sh
cat /sys/class/remoteproc/remoteproc0/firmware
# qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn      state = running
```

⇒ Same TrustZone, same signing authority, same directory — the ADSP blob authenticates and
the GPU blob does not. **So it is neither device signing nor the image.** The difference is in
how the two callers make the call.

★ **Leading hypothesis: the metadata buffer.** On glymur, PAS metadata looks like it must come
from the TrustZone mempool:

- `glymur_soccp_resource` is the **only** descriptor in all of `qcom_q6v5_pas.c` with
  `needs_tzmem = true`.
- `qcom_q6v5_pas.c:925` sets `use_tzmem = desc->needs_tzmem || rproc->has_iommu`, and the
  glymur ADSP node has `iommus = <&apps_smmu 0x1000 0x0>` — so the one PAS client that
  demonstrably works on this box is on the **tzmem** path.
- The adreno path calls `qcom_mdt_load(..., NULL)` — **no PAS context**. With `ctx == NULL`,
  `__qcom_scm_pas_init_image2()` always uses `dma_alloc_coherent()` and *cannot* request
  tzmem. The comment on that path warns the blob must be physically contiguous, 4K-aligned
  and non-cacheable, and that a buffer already in an SHM Bridge "will fail" — the exact class
  of fault `EINVAL_ADDR` reports.

### ✅ CONFIRMED by experiment 2026-08-02 — and the obvious fix is dangerous

Forcing the tzmem path when `ctx == NULL` (a local `qcom_scm.c` hack) makes the first half
work outright:

```
qcom_scm firmware:scm: GLYMUR: pas_init_image(pas_id=13) via tzmem -> ret=0 result=0
```

`-EINVAL` gone. **glymur's TrustZone requires PAS metadata from the TZ mempool, and the msm
zap path cannot supply it.** That is a real upstream gap.

The failure then moves one step later, to authorisation:

```
adreno 3d00000.gpu: [drm:adreno_zap_shader_load] *ERROR* Unable to authorize the image
```

Same root cause, second symptom: `__qcom_scm_pas_prepare_and_auth_reset()` only calls
`qcom_tzmem_shm_bridge_create()` when `ctx->use_tzmem`, and adreno calls the plain
`qcom_pas_auth_and_reset(pasid)` with no ctx — so no SHM bridge is created over the firmware
region and TZ cannot reach the loaded segments.

⛔ **The natural fix — hand adreno a real `qcom_pas_context` and use
`qcom_mdt_pas_load()` + `qcom_pas_prepare_and_auth_reset()` — HARD-RESET THE MACHINE.** Two
boots, dead in 10–15 s, no oops, no panic, no shutdown sequence (a step-3 boot for comparison
ran 4.8 minutes). The prime suspect is `qcom_tzmem_shm_bridge_create()` being asked to bridge
`gpu_microcode_mem`, a `no-map` carveout TZ already owns — XPU-violation territory. Reverted;
do not repeat without answering that question first.

⇒ Status: **root cause identified and half-proven, no safe fix.** Worth an upstream report
(the msm zap path has no way to opt into tzmem); not worth more local boots.

⚠️ Both the "TrustZone rejects the signature" and "wrong firmware image" theories are
**disproven by test** — do not present either as established.

⛔ **Do not re-add the node without also handling the failure.** `a8xx_gpu.c` special-cases
only `-ENODEV`; every other error is propagated and **fails GPU init**, so adding the node
costs the whole GPU. Reverted the same session; `renderD128` and turnip are back.

✅ The pre-existing `SECVID_TRUST_CNTL` fallback is therefore **the correct behaviour on this
machine**, not a gap to close.

## HDMI — ⚠️ half working, output still black

**Chain:** `hdmi-connector` ← **Parade PS185 DP→HDMI bridge** (`parade,ps185hdm`, bound to
`simple-bridge`) ← `mdss_dp2` (`af64000.displayport-controller`) ← **`phy@88e1000`**
(`usb_2_qmpphy`, a QMP USB3+DP combo PHY).

★ **Why USB-C DP worked and HDMI did not, from one cause:** `phy@88e1000` has **no DWC3
controller behind it** — the tertiary USB instance does not exist. Both USB-C combo PHYs have a
live controller; every tertiary clock read `en=0`.

**What we changed:** removed the `com_aux` clock reference from `phy@88e1000`.
`gcc_usb3_tert_phy_com_aux_clk` was stuck off, so the PHY failed `-EBUSY` and there was no AUX,
no EDID, zero modes. This is legal because `qmp_combo_clk_init()` uses
`devm_clk_bulk_get_optional()` — an absent clock comes back `NULL` and is skipped.

Result: PHY inits clean, EDID **0 → 512 bytes**, modes **0 → 32**. It also removed a hard
compositor hang.

⛔ **Still black — a second, separate bug.** Nothing delivers **HPD** to `af64000`. The USB-C DP
instances get HPD pushed in by `pmic_glink_altmode → aux_hpd_bridge`; the HDMI instance has no
equivalent, so its HPD register reads 0 forever and the driver tears the mainlink down.

**Four fixes tried, all eliminated** (detail in the maintainer’s private working journal):

| approach | outcome |
|---|---|
| Move `pinctrl-0` to `&mdss_dp2` | mux applied correctly, still black — ownership is not the variable |
| Mux gpio126 → `gpio` + `hpd-gpios` | failed **and** broke USB-C DP (two variables, ambiguous) |
| Mux gpio126 → `gpio` alone | **USB-C DP never links** — `usb2_dp` is load-bearing |
| `hpd-gpios` alone, mux untouched | pin uncontendable (`.strict` pinmux); **regressed EDID 512 → 0** |

★★ **The open contradiction, fully sourced — this is the question for upstream.** The WoA DSDT
registers TLMM 126 as a GPIO interrupt (`GIO0._AEI`) whose `_EVT` does
`Notify(\_SB.GPU0, 0xD1)` — GPU0 being the display subsystem at MMIO `0x0AE00000`. So *firmware
delivers HDMI HPD as a GPIO interrupt into MDSS.* Yet in Linux, putting that pin in GPIO mode
kills DisplayPort alt-mode on the USB-C ports. Both halves are solid and they conflict. This
needs SoC routing knowledge and should not be inferred further from this end.

⚠️ `/sys/class/drm/card1-HDMI-A-1/status` is **not** evidence of a cable here.

## USB-C, UCSI and DP alt-mode ✅

**Chain:** `pmic_glink` → `ucsi_glink` (PPM) → `typec_mux` → QMP combo PHYs (`fd5000`,
`fde000`) → DP alt-mode; SBU orientation handled in the PHY.

**What we changed:** deleted one DT property. `mode-switch`/`orientation-switch` on the wrong
node stopped the PPM initialising at all.

```sh
ls /sys/class/typec/          # port0 port1
```

## USB4 / Thunderbolt ❌

Three USB4 controllers exist in silicon (`gcc_usb4_{0,1,2}_gdsc`) but **no host-router/NHI node
exists in any in-tree Qualcomm device tree** — upstream has nothing to copy. The binding is an
unmerged **RFC** (Konrad Dybcio, 2025-09-16). The Type-C half of the pipeline works; only the
host router is missing. Nothing to do locally.

⚠️ `usb usb4:` in dmesg is **USB bus 4**, a plain xHCI root hub. Not USB4.

## Wi-Fi and Bluetooth ✅

Wi-Fi 7, Qualcomm **QCC2072** via `ath12k`, on PCIe. Bluetooth is **WCN7850** on a serdev UART.

Needs firmware extracted from the device's own Windows install, plus a forced regdomain (`US`).
Firmware is deliberately **not** shipped in this repo.

**What we changed:** added the WCN7850 Bluetooth serdev node; brought Wi-Fi up through the
`qcom,wcn7850-pmu` power-sequencing binding rather than hand-rolled regulator asserts.

⚠️ Wi-Fi takes up to ~5 minutes to re-associate after resume. "I cannot ssh in" is not evidence
of a crash — judge by `uptime -s`.

## Audio ⚠️ — usable, startup and recovery unresolved

**Chain:** ADSP (identify by remoteproc `name`, not numeric index) → AudioReach topology → **4× WSA8845 speaker amps
on SoundWire** + internal DMIC.

Native ALSA UCM2 provides the HiFi speaker/microphone routes. WirePlumber exposes
four speaker channels `[FL FR RL RR]`; EasyEffects is removed. The retired
systemd route/wait helpers remain disabled.

The RC3 baseline carries experimental SoundWire attachment/recovery changes.
Front-left silence occurred after boot and recovered after a manual device
cycle. A separate collector observed temporary left-amplifier detachment even
without a kernel bus-clash message. Neither sink presence nor attachment proves
audible output. Earlier claims that single-sided playback and pops were fully
resolved are superseded; cold-boot and idle/playback validation remain open.

❌ **Headphone jack** — jack detect exists, but there is no rx-macro/WCD9395 codec node in the
DT yet. ❌ **DisplayPort audio** — backends exist but are not wired up.

## Battery, charging and USB-PD ✅

**Current chain:** native SOCCP remoteproc attachment + `qcom-battmgr` +
`ps883x` PD controller. Battery, Type-C/UCSI and DP alt-mode **all hang off one glink edge** and
fail *silently together* — if several of them break at once, check the transport first.

The RC3 board configuration uses attachment to the already-running SOCCP.
The old standalone `soccp_glink` module-load entry is retired.

⚠️ **`qcom-battmgr-ac/online = 0` is CORRECT.** Its `type` is `Mains` — a barrel-jack rail this
laptop does not have. It charges over USB-C PD. Read `qcom-battmgr-usb/online` instead.
⚠️ Battery `capacity` **does not exist** as an attribute (the old wording "reads empty" implied
a present-but-blank file). `qcom-battmgr-bat` exposes both `energy_*` and `charge_*`; use
either pair. Verify with `ls /sys/class/power_supply/qcom-battmgr-bat/`.

⚠️ That node also exposes `charge_control_start_threshold` / `charge_control_end_threshold`.
Writing them reaches the EC, which owns charging — **covered by the "ask first" rule below.**

## Input ✅

Keyboard is I2C-HID `0B05:4B42` behind an **ASUS vendor HID handshake**. Touchpad, touchscreen
and stylus are I2C-HID. Lid switch is **TLMM GPIO 92**, active-low, recovered from the WoA DSDT
(requires freeing pin 92 from `gpio-reserved-ranges`).

**What we changed:** a `hid-asus` patch mapping the vendor usages — `0x85 → KEY_CAMERA`,
`0x86 → KEY_PROG1`, `0x5f → KEY_PROG2`, plus `QUIRK_FILTER_CAMERA_COMPANION` for a companion
byte that otherwise dims the panel. Mapping is Konrad Dybcio's; see `UPSTREAM-CREDITS.md`.

✅ **Keyboard backlight is dimmable — corrected 2026-08-02.** The old entry here said the A16
device entry lacked `QUIRK_USE_KBD_BACKLIGHT` and that this was "a one-line fix nobody has
made". It **has** been made and it is live in the running kernel:

```sh
cat /sys/class/leds/asus::kbd_backlight/max_brightness   # 3
cat /sys/class/leds/asus::kbd_backlight/brightness       # 0-3, writable
```

The A16 entry in our `hid-asus.c` carries `QUIRK_ROG_NKEY_KEYBOARD | QUIRK_USE_KBD_BACKLIGHT |
QUIRK_HID_FN_LOCK | QUIRK_PAD_FEATURE_REPORTS | QUIRK_FN_LOCK_DEFAULT_OFF`. The userspace
hidraw script it replaced is no longer the mechanism. ⚠️ Send the level **index** (0–3), not a
PWM duty value.

## CPU frequency scaling ✅

**Chain:** SCMI over a shared-memory mailbox to the PDP0/CPUCP firmware → `scmi-cpufreq` →
three performance domains.

```
policy0   cpus 0-5    355 MHz - 3.61 GHz   20 OPPs
policy6   cpus 6-11   355 MHz - 4.45 GHz   21 OPPs
policy12  cpus 12-17  355 MHz - 4.45 GHz   21 OPPs
```

**What we changed — one DT property.** `scmi-cpufreq` had probed `-110` (`-ETIMEDOUT`) for the
project's entire life. Root cause, measured with SCMI RAW: **the firmware answers protocol 0x13
(Performance) in shared memory but never rings the mailbox doorbell for it.** The doorbell IRQ
counter does not move for 0x13 at all. Fix: `arm,no-completion-irq` on the `scmi` node, which
makes the SCMI core poll instead of waiting.

⛔ **Two log lines look like failures and are not:** `Failed to query supported version for
protocol 0x13` (the firmware does not implement `0x13/0x0`; the kernel falls back) and
`Failed to get FC for protocol 13` (Fast Channels are optional).

⚠️ **Unexplained:** the table tops out at 4.45 GHz, not the X2 Elite's rated ~5 GHz boost bin.
The Fast-Channel theory is plausible and **untested** — do not repeat it as cause.

## Thermal ✅

42 `cpu*`/`cpullc*` zones bind the `cpufreq-cpu0/6/12` cooling devices; actuation confirmed by
stepping `emul_temp` across the 95 °C passive trip and watching `cur_state` go 0→1→2→3.

⛔ **`emul_temp` ≥ the critical trip (115000) POWERS THE MACHINE OFF** immediately — the thermal
core calls `hw_protection_shutdown`. Test at 96000 and always restore 0.

⛔ **Do not reinstall `glymur-thermal-guard`.** That userspace service was removed 2026-07-31.
Across 62 retained boots it logged 33,048 errors and **zero** throttle events — it wrote to a
`scaling_max_freq` that did not exist while cpufreq was dead. The claim that it held an 18-core
load at ~70 °C is **retracted**; whatever stopped the thermal shutdowns was never isolated.

## Fan and the Embedded Controller ⚠️ read-only

**Chain:** EC on **`/dev/i2c-9` at address `0x76`**, subdevice `0x5b`. RPM is read with the
DSDT's `RECM` command (`0x52`, raw I2C, **no SMBus count byte**), combining
`0x0603 << 8 | 0x0602` exactly as `\_SB.FAN0.GCFR` does.

Validated against load: 2340 RPM @ 44 °C idle → 2940 RPM @ 73 °C on 18 busy cores → back down.

The fan is otherwise **EC/BIOS-autonomous** — Linux does not drive it.

⛔ **Nothing writes to this EC.** The block protocol (ECRB/ECWB on `0x5b`, WEBC/REBC on `0xC9`,
fan-curve selectors) is fully decoded and `SUFC` is **deliberately not implemented**. This EC
also owns **charging**. Ask before any write.

⚠️ The old "blocked on an SSDT re-dump" premise was **wrong** — `FAN1` is external and unused;
`FAN0` was in the DSDT the whole time.

## SPMI / secondary PMICs ✅ — all three buses clean

⚠️ **Rewritten 2026-08-02, corrected again 2026-08-21. Two claims in this section's history
were both wrong.** The original version said secondary PMICs fail to probe, that this blocks
`qcom-spmi-temp-alarm`, and that the same failure blocks the fan PWM — all wrong, corrected
2026-08-02. The 2026-08-02 rewrite then said one device (`2-0b`/bus2) fails with `-5` — **also
now stale, see below.** Measured on the running machine (`7.2.0-ZenbookA16-20260819+`), **SPMI
is clean on all three buses** and `qcom-spmi-temp-alarm` is bound and reporting.

Upstream support is complete in linux-next 20260713 — driver, binding and **three** bus nodes:

```
drivers/spmi/spmi-pmic-arb.c:2165   { .compatible = "qcom,glymur-spmi-pmic-arb" }
Documentation/devicetree/bindings/spmi/qcom,glymur-spmi-pmic-arb.yaml
glymur.dtsi:5564/5579/5594          spmi_bus0 @c426000, spmi_bus1 @c437000, spmi_bus2 @c448000
```

**What actually enumerates** — 12 PMIC devices across all three buses (**not 13**; the
2026-08-02 count included `2-0b`, which no longer probes at all now that it's `disabled` — see
below):

```sh
ls /sys/bus/spmi/devices/
# 0-00 0-01 0-02 0-03 0-05 0-08 0-09   1-02 1-03 1-05   2-09 2-0a
```

✅ **`qcom-spmi-temp-alarm` registers on nine PMICs** — six on bus0, three on bus1 — and each
one produces a live thermal zone:

```sh
for d in /sys/bus/platform/devices/*temp-alarm*; do
  printf '%s -> %s\n' "$(basename $d)" "$(basename $(readlink $d/driver))"
done
# c426000.spmi:pmic@{1,2,3,5,8,9}:temp-alarm@a00 -> spmi-temp-alarm
# c437000.spmi:pmic@{2,3,5}:temp-alarm@a00       -> spmi-temp-alarm

grep -H . /sys/class/thermal/thermal_zone*/type | grep -E 'pmh|pmcx'
# pmcx0102-c0/-c1/-d0/-d1, pmh0101, pmh0104-i0/-j0, pmh0110-f0/-f1
```

✅ **RESOLVED 2026-08-21 — `2-0b` was never a bug to fix; it's a genuinely unpopulated third
eUSB2 repeater, and upstream already ships it disabled.** `journalctl -k -b` on this boot has
zero SPMI/PMIC errors of any kind — the `-5` error seen in older logs (from 2026-08-02) does
not reproduce on the current `next-20260817`-based DTB.

`smb2370.dtsi` (Qualcomm's own file) declares **three** SMB2370 eUSB2-repeater instances on
bus2 — `pmic@9`/`smb2370_j_e2`, `pmic@a`/`smb2370_k_e2`, `pmic@b`/`smb2370_l_e2` — but this
board only has two USB-C ports, so only `j` and `k` are ever referenced by a `phys =` property
(on `usb_0_qmpphy`/`usb_1_qmpphy`, in both our merged DTS and upstream). `pmic@b`/`l` is a
spare instance for a third port this board doesn't populate, and **`smb2370.dtsi` ships it
`status = "disabled"` upstream** — confirmed live: `.../pmic@b/status` reads `disabled`, so the
kernel never attempts to probe it. The 2026-08-02 `-5` was measured against an older DTB
revision that predated that `status` line; it was never a live-hardware problem, and there is
nothing to fix. `2-09` and `2-0a` (the two real, wired repeaters) both bind `pmic-spmi`
cleanly, each with a `phy@fd00`.

⚠️ **The fan PWM is still missing, but SPMI is not the reason.** `/sys/class/pwm` is empty
while temp-alarm works on the same bus, so "one bottleneck, two features" was a false
coupling. Whatever gates the PMIC PWM has not been identified; do not repeat the SPMI
explanation for it.

## Suspend / resume ⚠️ works on a workaround

**Root cause, isolated 2026-07-30: PCI config-space access during `dpm_suspend_noirq()`
hard-resets the SoC.** Both paths inside `pci_pm_suspend_noirq()` are *independently* lethal —
`pci_save_state()` (reads) and `pci_prepare_to_sleep()` (write/D-state). Driver `noirq`
callbacks are innocent. **Any single PCIe device** doing its noirq suspend is sufficient.

⛔ **It is not our device tree.** The bare upstream A16 DT crashes identically, same kernel and
cmdline, DTB the only variable. Suspend is simply not working on glymur upstream; a real fix
likely needs a firmware revision.

**Workaround:** `glymur_pci_skip=5` on the cmdline (skip both config-space paths). Because PCI
devices then never save state or change D-state, **they stay powered through suspend** — it
sleeps, but saves less power than a correct implementation. **Suspend draw has never been
measured.**

⚠️ This kernel advertises `deep`, but only `s2idle` is tested and is forced via
`/etc/tmpfiles.d/glymur-s2idle.conf`. Hibernate is deliberately masked as untested; the missing
RTC wake alarm (`qcom,no-alarm`) prevents scheduled wake but does not itself prevent resuming a
hibernation image after a normal boot.
⚠️ **Wake with the lid.** `HandlePowerKey=poweroff` turns a wake attempt into a fake failure.

### ★ Two devices do not survive resume (root-caused 2026-08-02)

A ~35 minute s2idle cycle **resumed correctly** — `uptime -s` unchanged, `success=1 fail=0`,
and ADSP, USB-C, battmgr, NVMe and the display all came back. **Two drivers did not.** These are
device bugs on a working suspend core, not the SoC-reset bug.

**1. ath12k — the device firmware does not reload.**

```
mhi mhi0: Power on setup success          <- the bus is FINE
mhi mhi0: MHI did not load AMSS, ret:-5   <- the firmware is not
ath12k: failed to power up hif during resume: -110
```

MHI reaches the device successfully; the device never boots AMSS back to SBL/Mission mode, so
everything downstream times out. The `-110`s are consequences. Recovery — **verified working**,
and note that driver unbind/rebind does *not* work, because only re-enumeration redoes the
firmware download:

```sh
echo 1 | sudo tee /sys/bus/pci/devices/0004:01:00.0/remove
echo 1 | sudo tee /sys/bus/pci/rescan
```

⛔ **The `Timeout while waiting for regulatory update` is NOT the cause.** Eliminated three ways
on 2026-08-02: it appears in a *failing* cycle, in a *passing* cycle, and **not at all** in a
third failing cycle — and it fires at probe time on a freshly recovered, healthy device (16
occurrences in one boot). It is chronic noise on this box. Do not spend time on it.

★ **Duration-sensitive, unlike the USB bug.** Three cycles on one boot:

| sleep | ath12k | USB |
|---|---|---|
| 2m25s | ✅ firmware loaded normally | ❌ failed |
| 12m51s | ❌ `MHI did not load AMSS, ret:-5` | — (sleep hook active, survived) |
| ~35min | ❌ same | ❌ failed |

⇒ **The threshold sits between 2m25s and 12m51s and is unmeasured.** Intermittency is still not
ruled out — each duration has only one sample.

⛔ **`d3cold_allowed=0` is NOT the fix — tested 2026-08-02 over an 18m44s cycle.** Set on both
the endpoint and the bridge, it did not prevent the failure; it moved it *earlier* in the MHI
state machine:

| | d3cold allowed | d3cold blocked |
|---|---|---|
| MHI stage reached | `Wait for device to enter SBL or Mission mode` | — |
| failure | `MHI did not load AMSS, ret:-5` | `Device failed to enter MHI Ready` |

MHI boots reset → READY → PBL/SBL → AMSS, so blocking D3cold made the device fail one stage
sooner. ★ It is still informative: **changing the setting changed the failure mode, which proves
D3cold entry was really happening.** Blocking it leaves the device half-alive rather than
cleanly powered off, which is worse, not better. The device's power state across suspend is
genuinely the variable — the fix is not simply "forbid the low-power state".

⚠️ **Trap:** `remove` + `rescan` re-enumerates the device and **resets its sysfs attributes to
defaults**, so any per-device experiment (`d3cold_allowed`, ASPM, `power/control`) is silently
undone by the recovery path. Use a udev rule if a setting must persist.

`remove` + `rescan` has now recovered it **three times out of three**, firmware reloading
normally each time (`chip_id 0x21`, `fw_version 0x100581de`).

**2. xHCI — controllers suspend with their PHYs not in L2.**

The fault is at suspend *entry*, not resume:

```
usb usb1-port1: device 1-1 not suspended yet
dwc3-qcom a400000.usb: port-1 HS-PHY not in L2       (all three controllers)
```

On resume the controller DMAs into a stale ring → `arm-smmu 15000000.iommu: Unhandled context
fault: fsr=0x402 [Format=2 TF]` → `xhci-hcd: WARNING: Host System Error`. An HSE is **fatal**:
the controller stops allocating slots, so every attempt then fails `couldn't allocate
usb_device`. That is why replug, `authorized` toggling and USB-device rebinding all do nothing —
they operate above the controller.

⛔ **The SMMU is not globally broken across suspend.** Exactly two context faults, both from
xHCI SIDs. `apps_smmu` also serves the GPU, GMU, both PCIe root complexes, fastrpc and the audio
DAIs, and none of them faulted. The "SMMU context lost on resume" theory is eliminated by
measurement.

✅ **Recovery CONFIRMED 2026-08-02** — rebinding the controller clears the HSE and everything
re-enumerates (hubs, card reader, RTL8153). Rebind the *controller*, not the devices:
[`../scripts/suspend/glymur-usb-recover.sh`](../scripts/suspend/glymur-usb-recover.sh).
So the HSE is **not** a hardware-latched dead end — no DWC3-level reset is required.

### ★ Attached devices are NOT the cause — eliminated by topology, 2026-08-02

The obvious theory is that devices which fail to suspend hold their ports awake. **The
controller topology refutes it outright, with no test required:**

```
xhci-hcd.1.auto → a400000.usb → usb1, usb2 → 4 devices (2 hubs, NIC, card reader)
xhci-hcd.2.auto → a600000.usb → usb3, usb4 → 0 devices
xhci-hcd.3.auto → a800000.usb → usb5, usb6 → 0 devices
```

And the warnings, every cycle:

```
dwc3-qcom a400000.usb: port-1 HS-PHY not in L2     <- has devices
dwc3-qcom a400000.usb: port-2 HS-PHY not in L2     <- has devices
dwc3-qcom a600000.usb: port-1 HS-PHY not in L2     <- EMPTY
dwc3-qcom a800000.usb: port-1 HS-PHY not in L2     <- EMPTY
```

⇒ **Two controllers with nothing attached fail identically to the populated one.** The fault is
in the dwc3-qcom suspend path itself, not in USB device suspend ordering. This also means an
"unplug everything and retry" test is unnecessary — it cannot distinguish anything.

⛔ **Why the PHY never reaches L2 is still UNKNOWN.** Two theories tested and rejected.

*Tested and rejected 2026-08-02:* that the leaf devices sitting at `power/control = on`
(autosuspend disabled) kept the ports busy. A udev rule flipping every USB device to
`control=auto` was installed and verified applied — and the next suspend produced **4× `not in
L2`, an HSE on both `xhci-hcd.1.auto` and `.3.auto`, and 7 more allocation failures.** No
improvement at all.

⚠️ The reasoning error: `power/control` governs *runtime* autosuspend. System suspend calls the
suspend callbacks regardless, so the setting was never the blocker. Also observed — the r8152
holds a runtime-PM reference while its link is up, so it reads `active` even at `control=auto`.
The rule is harmless (no link drops seen) but it is **not a fix**; keep it only if you want the
power saving.

Next place to look is the dwc3-qcom suspend path itself, not USB power policy.

★ **The USB bug is duration-independent.** It reproduced fully on a **2m25s** sleep. Any framing
of the form "long sleeps fail, short ones are fine" does not apply to USB.

### ⚠️ The workaround works — but nothing is fixed

**Be precise about what this buys.** The controllers still fail on every single resume. The
hook does not prevent the fault; it destroys and rebuilds the thing the fault corrupts, so the
damage never becomes visible. "Survives suspend" is the wrong description — the correct one is
"dies on every resume and is automatically resurrected". The same is true of the ath12k half.

Verified 2026-08-02:

Tear the controllers down *before* sleeping rather than recover after, applying the proven
rebind proactively:
[`../tweaks/usr/lib/systemd/system-sleep/glymur-usb-suspend-guard`](../tweaks/usr/lib/systemd/system-sleep/glymur-usb-suspend-guard).

First real cycle with it installed (12m51s sleep):

```
pre:  unbound xhci-hcd.1/2/3.auto
post: rebound xhci-hcd.1/2/3.auto
post: 4 non-root-hub USB device(s) enumerated
post: Host System Error count this boot = 3
```

| counter | before | after | delta |
|---|---|---|---|
| `not in L2` | 8 | 12 | +4 — still happens, root cause untouched |
| **`Host System Error`** | 3 | **3** | **+0** |
| **`couldn't allocate usb_device`** | 14 | **14** | **+0** |

The PHY still fails to reach L2, but with the controllers unbound there is no live ring to DMA
into, so no SMMU fault and no HSE. USB survived a suspend for the first time that day.

⚠️ This is a **workaround**. The dwc3-qcom suspend path still puts the PHY down wrong; the hook
just removes the thing that gets corrupted by it.

### Resume timing — measured, and it is NOT device timeouts

A slow-feeling wake is easy to blame on the `-110`s. The monotonic clock says otherwise:

```
[ 6947.741] PM: suspend entry (s2idle)
[ 7065.068] dwc3-qcom: HS-PHY not in L2       <- resume begins
[ 7065.070] mhi: MHI did not enter READY state
[ 7065.071] ath12k: failed to power up hif -110
[ 7065.073] PM: suspend exit
```

**The entire kernel resume takes 13 milliseconds.** Those `-110`s return immediately; they are
not 10-second timeouts stacking up.

| stage | elapsed |
|---|---|
| kernel resume, all warnings and failures | **13 ms** |
| this hook (3 controller rebinds + ath12k re-enumerate) | **~14 s** |
| `System returned from sleep` → `user.slice thawed` | ~14 s |

⚠️ **That 13 ms covers the device-resume portion only, and does NOT account for the whole wake.**
A wake keypress was observed to precede `PM: suspend exit` by **~2m54s** — that much latency
between the input and the kernel resuming. There is also a 117-second gap inside
the *entry* path that is unexplained:

```
[ 6947.741] PM: suspend entry (s2idle)
[ 6947.792] Filesystems sync: 0.051 seconds
[ 7065.030] Freezing user space processes     <- 117 s later
[ 7065.073] PM: suspend exit                  <- everything after fits in 43 ms
```

★ **Strong candidate: wakeup-lock churn is stopping s2idle from actually sleeping.**

```
0-0015 (touchpad)   active=55,556   total_ms=3
qcom-battmgr-bat    active= 8,886   total_ms=156,666    <- 156 SECONDS held
19-0015 (keyboard)  active= 4,761   total_ms=0
```

An active wakeup source forces s2idle to wake and re-enter immediately. 156 s of held wakeup
time lines up closely with the 117 s of unaccounted monotonic time, and would mean the machine
thrashes in and out of sleep rather than resting — which also finally explains the long-standing
"suspend saves less power than it should" note that was never measured.

⛔ **NOT PROVEN.** The churn is measured; that it *causes* the slow wake is not. One-line test:

```sh
echo disabled | sudo tee /sys/class/power_supply/qcom-battmgr-bat/device/power/wakeup
```

If the monotonic gap collapses on the next cycle, that is the mechanism.

### A third problem: suspend ENTRY stalls, variably

The printk clock does **not** advance during s2idle — confirmed on a 2m35s sleep that consumed
2 ms of kernel-clock time between `Suspending console(s)` and `Restarting tasks: Done`. So every
monotonic gap in these logs is **real awake CPU time**, and wake-side latency is structurally
invisible to it.

With that established, the `Filesystems sync` → `Freezing user space processes` gap is genuine
awake time inside the **entry** path, and it varies enormously:

| cycle | sleep | sync → freeze |
|---|---|---|
| 4 | 18m44s | **117 s** |
| 5 | 2m35s | **4.8 s** |

That window is the PM notifier chain plus `suspend_freeze_processes()`. Something blocking it
for 117 seconds is a real defect, distinct from both device bugs above.

⚠️ **It is not the whole explanation for a slow wake.** 117 s from an 11:46:10 entry puts freeze
roughly 14 minutes before the keypress that preceded the resume. Wake-side latency
remains unaccounted and cannot be measured from printk timestamps; it needs an external clock.

⏭️ Next step is characterization, not a fix: `echo 1 > /sys/power/pm_debug_messages` for
per-phase timing on the next long cycle.

★ **Wake latency scales with sleep duration**, like the ath12k failure and unlike the USB one:
a 2m35s sleep woke instantly; an 18m44s sleep took ~3 minutes.

⛔ **Eliminated:** "the keyboard is not armed as a wakeup source". `19-0015`
(`hid-over-i2c 0B05:4B42`) is `wakeup=enabled` with 4,761 recorded wakeup events. The keypress
registers. Also eliminated: that the `-110`s are timeouts burning minutes — they return in
microseconds.

⛔ **`/usr/lib/systemd/system-sleep/` runs EVERY executable in it**, exactly like
`/etc/grub.d/`. `asus-kbd-init.retired-2026-07-31` was still `+x` and erroring on every suspend
(4 times in one boot) long after being "retired". Fixed with `chmod -x` on 2026-08-02.
Renaming a hook does not disable it.

Audit it with one command — if it stops earning its place, delete it:

```sh
journalctl -t glymur-usb-guard
```

⛔ **Prefer either of those to a reactive watchdog.** The failure is fatal and latched, so a
watchdog can only ever act after USB is already dead — and if USB is your only network path, you
may not be able to reach the box to run it. Whatever you install, make it *log every action*:
this project already shipped one bandaid that ran for 62 boots, logged 33,048 errors, never
fired once, and was credited with a fix it could not have made.

⚠️ **`glymur_pci_skip=5` is NOT the cause of either.** That hypothesis was reasoned from the
patch source, predicted the symptom, and is still wrong — `MHI Power on setup success` proves
config space was intact, and the NVMe on the other root complex resumed fine under the same
flag. Recorded because it was convincing and false.

⚠️ **"Long sleeps fail, short ones are fine" is not established.** Both bugs may be
duration-independent. A 2-minute control cycle has not been run.

Full per-cycle evidence is kept in the maintainer’s private notes and is not published; the
findings above are the complete public record.

Ruled out by test, not argument: PME wakeup arming, D3cold, any D-state change, the PCIe
controller being runtime-suspended, the GPU, and `bam_dma`/`pcie-qcom`/`geni_i2c`/`qcom-ipcc`/
genpd power-off/`simple-pm-bus` — individually **and all five combined**.

## Storage, RTC ✅

NVMe root on PCIe. RTC is the PMIC RTC — enabled, but **read-only**; `qcom,uefi-rtc-info` is
deliberately removed from the DT.

## Camera ⏳ — sensors identified, CAMSS core & CCI probed on hardware, board wiring recovered

### Clock controller (`camcc-glymur`)

`drivers/clk/qcom/camcc-glymur.c` is upstream. Enabled via `CONFIG_CLK_GLYMUR_CAMCC=y`:
- Enumerates 94 `cam_cc_*` clocks.
- Binds to platform device `ade0000.clock-controller`.

### Sensor identities (from Windows driver store)

Extracted via `setupapi.dev.log` and registry configuration (`HKLM\...\Device Parameters`):
- **Front sensor**: OmniVision **OV02C10** (2 MP) — `qccamfrontsensor_extension8480.inf`. Driver `drivers/media/i2c/ov02c10.c` already in-tree (2 lanes, 400 MHz link freq, 1928x1092).
- **Aux / IR sensor**: SK Hynix **HM1092** — `qccamauxsensor_extension8480.inf`. **No Linux driver exists.** Windows Hello IR is out of scope; it does not block the webcam.

### ★ Board wiring — recovered 2026-09-06 from the AeoB power-sequence binaries

Method: the Windows driver store ships Qualcomm `AeoB` resource blobs that encode the
literal power-up/power-down sequence. Decoding **both** sensors' blobs together
(`CAMF_RES_QRD.bin` front, `CAMI_RES_QRD.bin` aux) is what makes the pins unambiguous —
a field that is *identical* in both is a shared resource, one that differs is per-sensor.
Cross-checked against `drivers/pinctrl/qcom/pinctrl-glymur.c`, whose per-pin function
tables turn the raw mux indices into names.

| Resource | Value | Evidence |
|---|---|---|
| MCLK (front) | `cam_cc_mclk4_clk` @ 19.2 MHz | literal string + `0x0124f800` in AeoB — **proven** |
| MCLK4 pin | **TLMM 100**, function `cam_asc_mclk4` | `cam_mclk_groups[]` is gpio96–99 = MCLK0–3 only; gpio100 is the *sole* MCLK4-capable pin — **proven by elimination** |
| CCI SCL pin | **TLMM 106**, function index 1 = `cci_i2c_scl` | AeoB `TLMMGPIO_V2 {gpio=0x6a, func=1}`, identical in both sensors; `PINGROUP()` puts `msm_mux_gpio` at index 0 so f1 = `cci_i2c_scl` — **proven** |
| CCI SDA pin | TLMM 105, `cci_i2c_sda` | pin-pair partner of 106 — inferred |
| ⇒ **CCI bus** | **`cci1_i2c0`** | 105/106 is the third of three TLMM `cci_i2c_*` pin pairs: 101/102 = `cci0_i2c0`, 103/104 = `cci0_i2c1`, 105/106 = `cci1_i2c0` — **strong** |
| Front reset | **TLMM 239** (egpio) | AeoB plain `TLMMGPIO` with `EGPIO_DISABLE`/`EGPIO_ENABLE`, front blob only. `PINGROUP()` carries `egpio_enable`/`egpio_present`, `ngpios = 251` — **strong** |
| Aux reset | TLMM 109 | same field in the aux blob only — strong |
| `dovdd` | **LDO4 on PMIC `I_E0`** @ 1.8 V | `PPP_RESOURCE_ID_LDO4_I0`, `0x001b7740`; present in **both** blobs ⇒ shared I/O rail — **proven** |
| `avdd` + `dvdd` | **LDO7 on `I_E0`** @ 2.8 V | `PPP_RESOURCE_ID_LDO7_I0`, `0x002ab980`, front only — **proven** |
| aux analog | LDO3 on `I_E0` | `PPP_RESOURCE_ID_LDO3_I0`, aux only — proven |
| module boost | BUCK_BOOST1 on `B_E0` @ 3.4 V | `0x0033e140`, both blobs — proven |
| CPAS AHB | 80 MHz (`0x04c4b400`) | AeoB — proven |
| privacy LED | TLMM 111 | already upstream in the board dts as `cam_indicator_en` |
| CSIPHY rails | `vreg_l2c_e0` (0.88 V), `vreg_l4c_e0` (1.2 V) | verified against the board dts — already correct in our staged `isp` node |

**`I_E0` is `pmh0104_i_e0`** (`pmic@8`, `compatible = "qcom,pmh0104"`). The board dts
already uses the identical id convention — `qcom,pmic-id = "B_E0"` matches the AeoB
string `..._B_E0` exactly.

**There is no separate DVDD rail, and that is not a gap.** The sequence votes only two
LDOs because `avdd` and `dvdd` share the 2.8 V rail — the same arrangement the ASUS
Zenbook A14 uses.

#### ⚠️ Retraction: the `cci0_i2c0` placement was wrong

`scripts/camera/glymur-ov02c10-probe.sh` correctly flagged its own CCI bus as "a genuine
guess … the one dimension most likely to be wrong". It was. The AeoB mux entry names
TLMM 106, which is `cci1_i2c0`. **The staged `camera@36` node under `cci0_i2c0` is
superseded** — do not re-run that test.

⚠️ Note this also **diverges from the ASUS Zenbook A14**, which puts its OV02C10 on
`cci1_i2c1`. Our own board's AeoB blob outranks the sibling-board analogy, so `cci1_i2c0`
is the primary hypothesis and `cci1_i2c1` the fallback. On glymur `cci1_i2c1` is not even
a `cci_i2c_*` pin pair — it is TLMM 235/236 under function `asc_cci` (the Always-Sensing
Camera path), which is a different bus, so the two hypotheses are cleanly separable.

### ✅ CCI0 / CCI1 — PASSED on hardware (2026-08-21)

CCI register addresses and GIC SPI interrupts from ACPI `CAMP._CRS` and device trees:
- **`cci0`**: `0x0ac15000 len 0x1000`, `interrupts = <GIC_SPI 456 IRQ_TYPE_EDGE_RISING>`
- **`cci1`**: `0x0ac16000 len 0x1000`, `interrupts = <GIC_SPI 859 IRQ_TYPE_EDGE_RISING>`
- **Power domain**: `&camcc CAM_CC_TITAN_TOP_GDSC`
- **Clocks**: `CAM_CC_CAMNOC_AXI_RT_CLK`, `CAM_CC_CPAS_AHB_CLK`, `CAM_CC_CCI_0_CLK` / `CAM_CC_CCI_1_CLK`

**Hardware validation:** Both `ac15000.cci` and `ac16000.cci` probe cleanly with `i2c-qcom-cci`. Four I2C adapters (`i2c-24`..`i2c-27`) instantiate representing `cci0_i2c0`, `cci0_i2c1`, `cci1_i2c0`, `cci1_i2c1`. No IRQ errors; eDP unaffected. Probe script: [`scripts/camera/glymur-cci-probe.sh`](../scripts/camera/glymur-cci-probe.sh).

### ✅ CAMSS (`isp@acb7000`) — PASSED on hardware (2026-08-21)

- **Node**: `isp@acb7000` with `qcom,glymur-camss` / `qcom,x1e80100-camss` resource layout (17 register windows, 13 interrupts, CSIPHY/CSID/VFE blocks).
- **Supplies**: `vdd-csiphy-0p8-supply = <&vreg_l2c_e0>`, `vdd-csiphy-1p2-supply = <&vreg_l4c_e0>`.

**Hardware validation:** `acb7000.isp` probes cleanly under `qcom-camss`. Instantiates a full V4L2/media graph: 4 CSIPHY subdevs (`msm_csiphy0..2,4`), 5 CSIDs (`msm_csid0..4`), VFEs, 28 `/dev/v4l-subdev*` nodes, and `/dev/media0` with default pad formats (`UYVY8_1X16/1920x1080`). Probe script: [`scripts/camera/glymur-camss-probe.sh`](../scripts/camera/glymur-camss-probe.sh).

⚠️ `port@3` is **array index 3 in `csiphy_res_x1e80100[]`, which is hardware CSIPHY4** —
`camss.c` indexes `camss->csiphy[]` by array position, not by the `.id` field. It is not
a typo for `port@4`.

### ⛔ Blocker — `pmh0104` has no LDOs in the kernel

`pmh0104_vreg_data[]` in `drivers/regulator/qcom-rpmh-regulator.c` declares **only
`smps1`–`smps4`**, and the board dts has no `I_E0` `rpmh-regulators` node at all. So
`LDO4_I0` / `LDO7_I0` cannot be requested today, and any sensor node naming them will sit
in deferred probe forever.

Fix staged as [`patches/glymur-pmh0104-camera-ldos.patch`](../patches/glymur-pmh0104-camera-ldos.patch):
adds `ldo4` (`pmic5_nldo530`) and `ldo7` (`pmic5_pldo530_mvp150`) plus the `I_E0` DT node.
`pmic5_nldo530` tops out at **2.0 V** (`320000 + 210*8000`), so the 2.8 V LDO7 **must** be
a PLDO — `pmic5_pldo530_*` covers 1.504–3.544 V. The three `pldo530_mvp{150,300,600}`
variants differ only in `hpm_min_load_uA` (auto-mode threshold), not in voltage, so
picking `mvp150` cannot produce a wrong voltage; the exact part variant is unconfirmed.

⚠️ `CONFIG_REGULATOR_QCOM_RPMH=y` — built in. This needs a **full kernel rebuild**, not a
module swap.

### Still unknown

1. **CCI bus** — `cci1_i2c0` is strongly evidenced but unproven on hardware. `cci1_i2c1` is the fallback. One bit, one boot.
2. **Slave address `0x36`** — from the Windows CRD sensor config; matches the A14 and the Lenovo Yoga Slim 7x. Near-certain.
3. **Streaming ≠ probing.** The A14 project reports X1E camera as stable but "requires the Bryan/Linaro tree for full functionality". Whether mainline `qcom-camss` streams unaided is untested here.
4. **Userspace.** OV02C10 emits raw Bayer and there is no CamX, so a usable webcam needs libcamera softISP + the PipeWire libcamera plugin. `libcamera-0.7.1` and `pipewire-1.6.8` are installed; `libcamera-tools` (qcam) is **not** — install it for testing.

### Summary of camera scope

1. ~~**camcc probing**~~ — ✅ **DONE 2026-08-02.** 94 clocks, driver bound (`camcc-glymur`).
2. ~~**Sensor identities**~~ — ✅ **DONE 2026-08-21.** OV02C10 (front) and HM1092 (aux).
3. ~~**CCI0 / CCI1**~~ — ✅ **PASSED 2026-08-21.** `i2c-qcom-cci` bound, 4 I2C adapters (`i2c-24`..`27`).
4. ~~**CAMSS core (`isp`)**~~ — ✅ **PASSED 2026-08-21.** `qcom-camss` bound, 28 V4L2 subdevs + `/dev/media0`.
5. ~~**Board wiring (rails, GPIOs, CCI bus)**~~ — ✅ **RECOVERED 2026-09-06** from AeoB + pinctrl cross-check.
6. **Sensor integration & streaming** — ⏳ needs the `pmh0104` LDO patch (kernel rebuild) + the corrected `camera@36` node, then a chip-ID read, then streaming.

### Nothing in the latest rc helps

`v7.3-rc1` is the newest tag and `kernel-build/zenbook-next-0831` is `next-20260831` on
top of it — the tree is already current. Last commit to
`drivers/media/platform/qcom/camss/` anywhere is **2026-06-04** (a macro rename); last
`ov02c10.c` commit is **2025-12-08**. There is no `qcom,glymur-camss` compatible and no
upstream device tree carries a camss node for x1e80100 either. **Rebasing gains nothing
for the camera.**

---

## Status at a glance

| Component | State |
|---|---|
| eDP panel + backlight, GPU, Wi-Fi/BT, audio (speakers + DMIC), battery/PD, input, NVMe, RTC, cpufreq, thermal | ✅ working |
| Keyboard backlight | ✅ dimmable, `asus::kbd_backlight` 0–3 *(corrected 2026-08-02)* |
| `qcom-spmi-temp-alarm` | ✅ bound on 9 PMICs, 9 thermal zones *(corrected 2026-08-02)* |
| SPMI | ✅ all three buses clean, 12 PMICs bound (`2-0b` disabled upstream) |
| Fan | ✅ RPM readback only — no control; PWM absent, cause unidentified |
| Suspend | ⚠️ works on `glymur_pci_skip=5`; long-sleep stability unmeasured |
| HDMI | ⚠️ PHY fixed, EDID + 32 modes — output still black (HPD) |
| GPU zap shader | ❌ **tested 2026-08-02** — DT node works, TrustZone rejects the image (`-EINVAL`); adding the node costs the GPU. `SECVID_TRUST_CNTL` fallback is correct here |
| Headphone jack, DP audio | ❌ known cause (missing DT node), unfixed |
| USB4 | ❌ blocked upstream — binding is an unmerged RFC |
| Camera | ⏳ camcc, CCI (i2c-24..27), and CAMSS (28 v4l-subdevs) verified on hardware; board wiring recovered 2026-09-06 (OV02C10 on `cci1_i2c0`, MCLK4/TLMM100, reset TLMM239, LDO4/LDO7 on `I_E0`). Blocked on the `pmh0104` LDO patch |
