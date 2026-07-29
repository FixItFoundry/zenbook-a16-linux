# Glymur-August-1 — what to add to Konrad's DTS, and the staged tests

**The name is a target date, not a variant number.** Jesse's goal: everything merged into
one lineage by **2026-08-01** — the teardown fix, Wi-Fi, battery, hotkeys, USB-C, audio,
**and a working gpucc**.

**Written 2026-07-28, after the teardown crash was localised to the device tree.**
Companion to `docs/konrad-tree-plan.md` (how the konrad lineage was built) and the
`RESUME-HERE.md` section of the same date.

---

## The result this plan rests on

Three boots, same kernel (`7.2.0-rc3-konrad1`), same `msm` (`257777F752CF092862B1337`),
same initrd. Only the DTB differed:

| DTB | model string | teardown |
|---|---|---|
| `konrad-a16.dtb` | `ASUS Zenbook A16 (UX3607OA)` | **SURVIVED** full 60 s off + on + 30 s |
| `glymur-a16-test71.dtb` (ours) | `Qualcomm Technologies, Inc. Glymur CRD` | **DIED** — TZ fatal +1.51 s, dead before t+10 s |

Both signatures are in `/var/log/glymur-kmsg.log`. pstore empty again (8th).

⇒ **The display power-down crash is a device-tree defect on our side.** The kernel is a
controlled variable. Every "it's TrustZone / a secure watchdog / silicon" reading is
retired — those are the *mechanism* of the reset, not its cause.

⚠️ What this does **not** say: which property. The display subtree itself is
**identical** between the two trees (see below), so the cause is somewhere else in the DT.

---

## Display subtree: identical. Stop looking there.

Decompiled both DTBs and compared node by node:

| node | verdict |
|---|---|
| `display-subsystem@ae00000` (MDSS) | same compatible, clocks, resets, interconnects, power-domains |
| `display-controller@ae01000` (DPU) | same clocks/names, same 8-entry OPP table, same MMCX domain |
| `displayport-controller@af6c000` (eDP) | same 5 clocks, same names, same OPP table incl. `opp-810000000`, same `power-domains = <rpmhpd RPMHPD_MMCX>` |
| `phy@faac00` (eDP PHY) | **byte-for-byte equivalent** — same reg, same `aux`/`cfg_ahb`/`ref` clocks, same `power-domains = <rpmhpd RPMHPD_MX>` |
| `clock-controller@af00000` (dispcc) | same reg, same parents, same power-domain |
| panel | same `enable-gpios` (tlmm 18), same `power-supply`; ours has the *more specific* compatible (`samsung,atna60cl08` first) |

Only cosmetic display deltas: he leaves `displayport-controller@af64000` (DP2) enabled
where we disable it, and the HPD pinctrl phandles differ (both trees mux GPIO119 —
ours since test70).

---

## Two theories killed today before they cost a boot

1. **"His TCSR clock controller holds extra votes on ldo2/ldo4."** His
   `clock-controller@1fd5000` carries **17** `vdda-qref*`/`vdda-refgen*` supply
   properties; ours carries none. But `tcsrcc-glymur.c` at v7.2-rc3 requests **no
   regulators at all** — the properties are inert. ⚠️ **CLO's tree is different**: its
   `tcsrcc-glymur.c` has per-clock regulator tables (`glymur_tcsr_tx1_rpt0_rx0_regulators`
   etc.). So Konrad's DT is written for a driver that is not upstream yet.
2. **"His videocc/evacc/camcc hold the MMCX domain up."** He has three extra clock
   controllers we lack (`videocc@aaf0000`, `evacc@abf0000`, `camcc@ade0000`), all voting
   `RPMHPD_MMCX` + `RPMHPD_MXC` with `required-opps`. Attractive — the DPU is on MMCX and
   dies at the CRTC stage. **But `videocc-glymur.ko` is not built on either kernel**, and
   there is no `evacc-glymur.c`/`camcc-glymur.c` upstream at all. All three nodes are
   inert on the kernel where his DT survives.

Both were checked against driver source, not assumed. Do not re-propose either without
first confirming the driver claims the property.

---

## The live deltas — ranked, with what each would explain

Everything here is *driver-consumed* on v7.2-rc3, i.e. capable of changing behaviour.

### 1. ★★★ `gpio-reserved-ranges` — the biggest delta in the tree

| | ranges | pins reserved |
|---|---|---|
| ours (test71) | 16 | **~250** |
| Konrad | 5 | **12** |

Ours: `<2 1> <4 4> <10 8> <19 1> <22 10> <34 14> <49 2> <52 15> <68 2> <71 5> <78 8> <88 4>
<93 26> <120 26> <149 3> <155 94>`
His: `<4 4> <10 2> <44 4> <65 1> <90 1>`

Reserving a pin means Linux may not touch it — every consumer whose pinctrl needs one
fails to probe. This already explains, on our tree: `regulator-wcn-3p3` and
`regulator-wwan` failing `-EINVAL` (pins 94 and 246 are both inside our ranges), and why
test66 broke Wi-Fi when it freed them — freeing the pin lets Linux *own* the rail and
then switch it off.

Whether it explains the teardown is unknown, but it is the single largest behavioural
difference and it is one property to move.

### 2. ★★★ eDP PHY rail voltages — and what CLO's vendor tree does with them

| rail | ours | Konrad | **CLO (vendor)** |
|---|---|---|---|
| ldo2 `vdda-phy` | **0.831 V** fixed (`vreg_l2f_e1_0p83`) | 0.88 V fixed | **`vreg_l2f_e1_0p83`** — same as ours |
| ldo4 `vdda-pll` | **1.08 – 1.32 V range** (`vreg_l4f_e1_1p08`) | 1.2 V fixed | **`vreg_l4f_e1_1p08`** — same as ours |

Same PMIC (F_E1) everywhere. **Our values are vendor-correct; Konrad's are the outlier.**
(`clo-glymur/arch/arm64/boot/dts/qcom/glymur-crd.dts`, `&mdss_dp3_phy`.)

★★★ **But the vendor gives that rail other consumers.** In CLO's `mahua-crd.dts` — a
sibling board — the TCSR refgen supplies are wired to the *same ldo2 the eDP PHY uses*:

```dts
vdda-qrefrpt0-0p9-supply = <&vreg_l2f_e1_0p83>;
vdda-qrefrpt1-0p9-supply = <&vreg_l2f_e1_0p83>;
vdda-qrefrx0-0p9-supply  = <&vreg_l2f_e1_0p83>;   /* … six of them */
```

and CLO's `tcsrcc-glymur.c` **claims them** (per-clock regulator tables). So on the vendor
stack ldo2/ldo4 always carry votes from the TCSR block, and
`regulator_bulk_disable()` inside `qcom_edp_phy_exit()` is physically a **no-op**.
Upstream has neither the supply properties on a probing driver nor the driver support, so
our eDP PHY is the **sole consumer** and the rail genuinely powers off.

**⇒ Testable with one property and no kernel build: `regulator-always-on` on ldo2 + ldo4.**
If the rail can never drop, the teardown cannot cut it. This is the top experiment.

### 3. ★★ Peripheral enable/disable swaps

| node | ours | Konrad |
|---|---|---|
| `pci@1c00000` | okay | **disabled** |
| `phy@1c06000` (PCIe PHY) | okay | **disabled** |
| `phy@88e1000` | **disabled** | okay |
| `phy@fa0000` | okay | **disabled** |
| `i2c@a84000`, `i2c@a88000`, `i2c@a94000` | disabled | okay |
| `serial@a98000` | disabled | okay |
| `displayport-controller@af64000` | disabled | okay |

Ours enables a PCIe controller and PHY that never successfully probe (their regulators
fail on reserved pins). A half-probed PCIe/PHY holding partial resources is exactly the
kind of thing that changes what happens when a neighbouring block powers down — and the
eDP PHY at `0xfaac00` physically **lives in the peripheral PHY region**, next to
`usb_mp_qmpphy0@fa3000` / `usb_mp_qmpphy1@fa5000`, not in the MDSS block.

### 4. ★ Memory reservations

All 21 `reserved-memory` regions are **identical in address and size**. Deltas: ours adds
`ramoops@94000000`; his adds `adsp-rpc-remote-heap` (8 MB `shared-dma-pool`, `reusable`)
wired into the ADSP remoteproc node, plus `linux,cma`.

---

## What we have that his tree lacks — the port-back list

33 node names exist in ours and not his. Sorted by what they buy:

| ours | value | DT-only? | notes |
|---|---|---|---|
| `wcn7850-pmu` + `regulator-wcn-0p95` + `bluetooth` | ★★★ **Wi-Fi + BT** | yes | he uses a `wlan-connector` + PCIe-endpoint graph instead; ours is the PMU approach that works today |
| `soccp_glink_edge` | ★★★ **battery %** | **no** | also needs the out-of-tree `soccp_glink` module built in-tree for 7.2 |
| `thermal_zones` | ★★ thermal | yes | his has `cooling-maps`/`map0` under a differently-named node — verify before porting |
| `ramoops@94000000` | ★★ crash capture | yes | free, and we want it on every experimental DTB |
| `regulator-wwan` + `wwan-reg-en-state` | ★ WWAN | yes | not populated on this machine |
| `redriver@47` | ★ USB-C | yes | his is `redriver@4f` — different I2C address, check which port |
| `key-volume-up` | ★ | yes | trivial |
| `lid-switch` | — | yes | **redundant** — he has `switch-lid` + `hall-int-n-state` |
| `edp-3v3-regulator`/`regulator-edp-3p3` | — | yes | **redundant** — he has `regulator-edp` + `edp-pwr-en-state` |
| `pmic@7`, `spmi@c48000`, `bob1/2`, `ldo0/5`, `smps9` | ? | yes | a whole extra PMIC bank our vendor DTB carries; unexamined |

### The USB/UCSI fix — ★★★ and it is **not** in his tree

`docs/usb-c-ucsi-dp-altmode.md`: UCSI never worked until test68 deleted **one property**,
`usb-role-switch`, from `usb@a600000`. dwc3 only registers a role switch in OTG mode, so
in host mode the property makes `fwnode_usb_role_switch_get()` return `-EPROBE_DEFER`
forever → `PPM init failed, stop trying` → no Type-C, no PD, **no DisplayPort alt-mode**.

**Konrad's DT has `usb-role-switch` on BOTH `usb@a600000` and `usb@a800000`**, and his
`glymur.dtsi` sets `dr_mode = "host"` on both (lines 4804, 4877). That is exactly the
combination we proved broken.

⚠️ Unverified on 7.2: the konrad boot log shows **zero** `PPM init failed` lines. Either
the capture is partial, or `ucsi.c` changed between 7.1 and 7.2. **Check
`/sys/class/typec/` on a konrad boot before assuming the fix is still needed** — and if
UCSI does work there with the property present, that is a 7.2 improvement worth knowing
about.

### What his tree has that we should take

- `hdmi-bridge` + `hdmi-connector` — HDMI over USB-C, never wired on our side
- `leds` — keyboard mic/camera LEDs, `privacy-led`
- `switch-lid` + `hall-int-n-state` — his lid handling
- `adsp-rpc-remote-heap`, `linux,cma`
- the coresight tree (`tpdm@*`, `tpda@*`, `funnel@*`, `stm@*`) — debug only, ignore
- `remoteproc@32300000` (CDSP) — needs `qccdsp8480.mbn`, which we have never extracted

---

## Staged tests

Two tracks. **Track A breaks his tree deliberately** — start from the config that
survives and add our deltas one at a time until it crashes. The one that crashes is the
bug, and it is the upstream report.

All Track A entries: same kernel `7.2.0-rc3-konrad1`, same initrd, **DTB is the only
variable**. Fire with `~/glymur-konrad-teardown.sh`, read `/var/log/glymur-kmsg.log`.

### ✅ ALL FIVE ARE BUILT, INSTALLED AND IN GRUB (2026-07-28)

Each DTB was decompiled after building and diffed against its parent — the printed delta
is exactly the intended property and nothing else. `set default=` is parked on
`fedora-glymur-baseline` (Wi-Fi + audio), `timeout=10`, 32 → 37 entries, backup
`/boot/grub/grub.cfg.bak-pre-aug1`. Sources and build artifacts: `~/dtdiff/build/` on loazen.

**Start here — the one that tests the rail theory on the kernel you daily-drive:**

| entry | kernel | DTB | change | if it SURVIVES |
|---|---|---|---|---|
| **`fedora-glymur-test73`** | **7.1 gdsc1** | `glymur-a16-test73.dtb` | test71 + `regulator-always-on` on ldo2 **and** ldo4 | ★★★ the crash is the eDP rail genuinely powering off — and this is the fix, on our own kernel, with no rebuild |

Then the localisation set — all on the konrad kernel, DTB the only variable:

| entry | DTB | change from `konrad-a16.dtb` | if it DIES |
|---|---|---|---|
| `fedora-glymur-aug1-pinres` | `aug1-pinres.dtb` | our full 16-range `gpio-reserved-ranges` | pin reservations are the cause |
| `fedora-glymur-aug1-ldo` | `aug1-ldo.dtb` | ldo2 → 0.831 V, ldo4 → 1.08–1.32 V range | the PHY rail voltages are the cause |
| `fedora-glymur-aug1-pci` | `aug1-pci.dtb` | enable `pci@1c00000` + `phy@1c06000`, disable `phy@88e1000` | a half-probed neighbour in the PHY region is the cause |
| `fedora-glymur-aug1-alwayson` | `aug1-alwayson.dtb` | his DT + `regulator-always-on` on both rails | (control — should still survive; proves the property is harmless) |

If all three localisation entries survive, the cause is in the remainder of the delta and
the next cut is coarser: take his tlmm/pmic/soc wholesale and graft our vendor nodes in
halves.

**How to run each one:** pick it at the GRUB menu, confirm the panel lit, then

```bash
systemctl --user is-active glymur-stayawake     # guard first
~/glymur-konrad-teardown.sh
sudo grep -a "GLYMUR-KONRAD" /var/log/glymur-kmsg.log | tail -15
```

**Track B — features, on top of whichever Track A base is still crash-free.** These are
for the daily driver, not for localisation:

| step | change | needs a build? |
|---|---|---|
| B1 | PCIe endpoint node under `pcie4_port0` (restores the `wlan-connector` graph) **or** port our `wcn7850-pmu` block | no |
| B2 | delete `usb-role-switch` from both `usb@a*` nodes | no |
| B3 | add `ramoops@94000000` | no |
| B4 | add `soccp_glink_edge` + build `soccp_glink` for 7.2 | **yes** |
| B5 | apply Konrad's hid-asus patch for the A16 keyboard | **yes** |

Every Track B step is re-tested with the teardown script, because any of them can
reintroduce the crash — that is the whole point of the ordering.

## Rules for this lineage

- One variable per DTB. Never two.
- Every DTB gets its own GRUB entry; `set default=` stays on a known-good entry.
- Decompile-and-diff every built DTB against its parent to prove only the intended
  property moved. (This caught two mistakes in the test69/70 lineage.)
- Keep `ramoops` in any DTB used for a crash test.
- After each crash, read `/var/log/glymur-kmsg.log` — **never** netconsole, which dies
  with the ADSP.

---

## ★★★ GPU — the blocker is a stale cmdline token, not the driver

Konrad's DTS is the first tree we have run that carries `&gpu`, `&gmu`, the GPU SMMU and
the GX clock controller. On his first boot all four failed:

```
gxclkctl-kaanapali 3d64000.clock-controller: probe ... error -110
arm-smmu 3da0000.iommu:              probe with driver arm-smmu failed with error -110
adreno 3d00000.gpu:                  deferred probe timeout, ignoring dependency
msm_dpu ae01000.display-controller:  failed to bind 3d00000.gpu (a3xx_ops): -19
                                     adev bind failed: -19          <- takes the whole display down
```

**Why.** His `clock-controller@3d64000` declares

```dts
power-domains = <&rpmhpd 3>, <&rpmhpd 20>, <&gpucc 0>;   /* phandle 0xcf = clock-controller@3d90000,
                                                            compatible "qcom,glymur-gpucc" */
```

`gxclkctl-kaanapali.c` is a 78-line GDSC provider with `use_rpm = true`, so `qcom_cc_probe()`
runtime-resumes those domains at probe. **Every GRUB entry we have carries
`modprobe.blacklist=gpucc_glymur`** — so the third provider never appears, the resume times
out `-110`, the GPU SMMU goes with it, adreno defers then fails `-19`, and because `msm` is a
component framework the *entire* DRM bind fails. That is the black screen from konrad1's
first boot, and we "fixed" it then by disabling `&gpu`/`&gmu`.

**The blacklist is stale caution.** `docs/gpucc-bringup.md` put it there deliberately for the
*first ever* gpucc probe — "if the register window is unpowered or XPU-gated, the first read
can hang the SoC — we want that at a known instant on a booted, SSH-able system." That
experiment has since **passed**: gpucc binds on hardware, 25 clocks, `gpu_cc_pll0` at
1149999902 Hz. The risk it guarded against is retired.

### ⏭️ `fedora-glymur-aug1-gpu` — staged 2026-07-28

konrad kernel + initrd, DTB `aug1-gpu.dtb` = `konrad-a16.dtb` with `gpu@3d00000` and
`gmu@3d6c000` flipped back to `okay` (verified: 5-line delta, two `status` properties),
and a cmdline with **`gpucc_glymur` dropped from `modprobe.blacklist`**. Backup
`/boot/grub/grub.cfg.bak-pre-aug1gpu`.

Two variables, deliberately — the GPU nodes and their clock provider are inseparable; there
is no useful test of one without the other.

**Reading it:**
- `gxclkctl` probes, SMMU probes, adreno binds, panel lights ⇒ **GPU bring-up is unblocked**,
  and the remaining questions are the zap shader and rendering.
- `gxclkctl` still `-110` ⇒ the missing vote is one of the two `&rpmhpd` domains (indices 3
  and 20), not gpucc — check which rpmhpd those are and whether anything else votes them.
- ⚠️ **If the GPU still fails, the whole DRM bind fails and the boot is headless again.**
  That is recoverable — pick another entry at the menu (`timeout=10`) — but do not mistake it
  for "the kernel does not boot". Check `journalctl --list-boots` first.

Known remaining GPU risks, unchanged from `docs/gpucc-bringup.md`: the XPU/VBIF firmware gate,
and whether retail TrustZone accepts the linux-firmware zap shader.
