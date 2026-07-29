# The "konrad" parallel lineage — plan (2026-07-28)

Jesse's call: keep the working 7.1 lineage untouched, and build a **separate grouping** based
on Konrad Dybcio's upstream A16 device tree, so we can compare like-for-like without risking
what we have. Everything below is namespaced `konrad-*` and touches nothing existing.

## Why

We are on v7.1 + a vendor-decompiled DTB + an X1E-derived topology. Konrad is on ~v7.2
mainline + a hand-written DTS + (presumably) a correct glymur topology, and reports Display
and Audio working. Rather than converge one property at a time — which consumed a whole
session and produced mostly eliminations — stand his configuration up beside ours.

⚠️ **What his commit message does and does not claim.** It says "GPU, Display" and "Audio
playback (4 speakers)" work. It says **nothing** about DPMS-off, blanking or suspend. Our
display crash only occurs on panel power-down, which a bring-up validation may never
exercise. Do not assume his tree is free of the teardown crash — that is a question to test,
and if it *is* free of it, the diff becomes extremely valuable.

## Layout (nothing shared with the 7.1 tree)

| | |
|---|---|
| source | `~/kernel-build/konrad/linux-7.2/` — from `LoA Project/zenbook-native-kernel` (v7.2.0-rc3) |
| output | `~/kernel-build/konrad/out/` |
| LOCALVERSION | `-konrad1` → `7.2.0-konrad1` (never collides with `7.1.0-glymur-*`) |
| DTB | `glymur-asus-zenbook-a16-ux3607oa.dtb`, installed as `/boot/glymur/konrad-a16.dtb` |
| GRUB ids | `fedora-glymur-konrad*` |
| default entry | **unchanged** — stays `fedora-glymur-baseline` |

`LOCALVERSION` must be passed on the make command line, not in `.config` — see
[[zenbook-a16-hardware-traps]]; `.config` has `CONFIG_LOCALVERSION=""`.

## Steps

1. **Disk check first.** The 7.1 tree is ~12 G; a second tree plus output needs comparable
   room. Verify before copying.
2. Copy `zenbook-native-kernel` (7.2.0-rc3) to `~/kernel-build/konrad/linux-7.2`.
3. Seed `.config` from the running 7.1 build (`~/kernel-build/usb-out/.config`), then
   `make olddefconfig`. Verify these survive: `CONFIG_DRM_PANEL_SAMSUNG_ATNA33XC20`,
   `CONFIG_SND_SOC_QCOM*`, `CONFIG_QCOM_GDSC`, `CONFIG_COMMON_CLK_QCOM`, and the soccp/battery
   pieces.
4. Add `upstream/dts/glymur-asus-zenbook-a16-ux3607oa.dts` to that tree (it builds cleanly at
   7.2 — the ten unresolved labels that blocked it on 7.1 all exist there) and add it to the
   qcom Makefile.
5. Build kernel + modules + DTB with `make LOCALVERSION=-konrad1`.
6. `modules_install`, copy `Image` to `/boot/vmlinuz-7.2.0-konrad1`, build
   `/boot/initrd.img-7.2.0-konrad1` **with the ADSP dracut config applied** — otherwise the
   ADSP never boots and audio is a false negative (this exact trap cost us a boot on
   2026-07-27).
7. Add GRUB entry `fedora-glymur-konrad1`; leave `set default=` alone.

## Which of our 7.1 patches to carry over, and which not

| our change | carry? | why |
|---|---|---|
| gdsc genpd teardown fix | **no** | developer-workflow only (hot-swapping clock controllers); exonerated for audio but unnecessary here |
| HBR3 force on eDP | **not initially** | Konrad's DT may negotiate correctly on its own; adding it hides whether it does |
| `LINK_RATE_SET` plumbing fix | **yes if still needed** | genuine upstream fix; check whether 7.2 already carries it |
| soccp_glink (battery) | **yes** | out-of-tree-origin, needed for battery %; must be built in-tree so vermagic matches |
| hid-asus A16 keyboard | **check first** | upstream version may already be in 7.2 |
| msm bisect diagnostics | **no** | diagnostic only, explicitly not for upstream |
| phy PD_CTL probe | **no** | diagnostic only |

The point of the exercise is to see his configuration behave *as he ships it*. Add our
patches back one at a time only when something is actually missing.

## What to measure on the first konrad boot

1. Does eDP light, and at what link rate (without our HBR3 force)?
2. **Does `kscreen-doctor --dpms off` still reset the SoC?** ← the big one
3. Does audio work, and specifically does `GRAPH_START` succeed?
   (`sudo dmesg | grep -aE "CMD timeout|DSP returned"`)
4. Battery %, Wi-Fi, keyboard, lid.

Any of those behaving differently is a direct, reportable data point for Konrad — and if his
tree does *not* crash on display power-down, diffing the two trees finally localises a bug we
have chased for days.

---

## What 7.2 already has vs what we must carry — CHECKED 2026-07-28

Verified against the v7.2.0-rc3 tree on the LoA drive (`zenbook-native-kernel`), before
building anything:

| item | in 7.2? | action |
|---|---|---|
| **gdsc `pm_genpd_remove()` on unregister** | **YES — already upstream** | **drop our patch's unregister half; it is not novel** |
| gdsc `gdsc_register()` **error-path** cleanup | **NO** — still `return ret` after `gdsc_init()` failure, and `of_genpd_add_provider_onecell()`'s return is still unchecked | our error-path half is still novel; candidate for a small standalone submission |
| A16 keyboard (`0x4B42`, `ZENBOOK_A16`) | **no** — Konrad's hid-asus patch is unmerged | carry it (we already run upstream's version) |
| `soccp_glink` (battery) | **no** — does not exist upstream at all | must carry, built in-tree so vermagic matches |
| Konrad's A16 DTS | no — his series is unmerged | add from `upstream/dts/` |
| `use_rate_set` / `rate_set` plumbing in `dp_panel.c` | present — needs a closer look to see whether our "actually reachable" fix is still needed | check before carrying |

### ⛔ Correction to a standing project claim

The repo and memory describe the gdsc work as *"a real upstream gdsc genpd-teardown bug
fixed and pushed"*. That is now only half true: **upstream fixed the `gdsc_unregister()` half
itself between v7.1 and v7.2**, independently of us. Our tree is not carrying a unique fix
there. Only the `gdsc_register()` error-path cleanup remains missing upstream, and it is a
leak-on-failure fix rather than a crash fix — say so plainly if we ever submit it, rather
than overselling it.

---

## BUILD LOG — 2026-07-28

**Base:** stock `v7.2-rc3` (`git clone --depth 1 --branch v7.2-rc3` from torvalds/linux,
HEAD `a13c140cc`), at `~/kernel-build/konrad/linux-7.2`, output `~/kernel-build/konrad/out`,
`LOCALVERSION=-konrad1`.

**Config:** seeded from the running 7.1 build then `make olddefconfig` (178 symbols changed,
normal for a version bump). Verified surviving: `DRM_PANEL_SAMSUNG_ATNA33XC20=m`,
`QCOM_GDSC=y`, `COMMON_CLK_QCOM=y`, the full QDSP6 stack, `DRM_MSM=m`, `HID_ASUS=m`,
`PSTORE_RAM=m`. Seed kept at `out/.config.seed-7.1`.

### ★ Stock v7.2-rc3 is NOT enough for his DTS

His DTS references labels that **rc3 does not have** — the accepted LPASS/audio DT patches
(2026-07-01 and 07-06) landed *after* the rc3 tag. Missing at rc3: `lpass_vamacro`, `swr0`,
`swr3`, `gpu`, `gmu`, plus the `WSA_CODEC_DMA_RX_0` binding. (`remoteproc_adsp`/`_cdsp` *do*
resolve at rc3 — they were missing at 7.1.)

Applying the accepted patches directly failed: `[v11,1/2] LPASS macro codecs and pinctrl`
does not apply to rc3 (written against a tree with other changes in). `[v11,2/2]` and the
audio-PD memory-region patch applied cleanly but depend on it.

**Resolution:** took `glymur.dtsi` (227 KB) from the drive's **patched** 7.2 tree
(`LoA Project/zenbook-native-kernel`, which is rc3 + those DT patches) and dropped it into
the clone, plus the two missing headers `qcom,glymur-camcc.h` and `qcom,glymur-evacc.h`.

### ⚠️ Deviations from Konrad's DTS — declare these when reporting any result

Three edits were needed because our `glymur.dtsi` still lacks two nodes:

1. removed the `&pcie4_port0_ep { … }` override block
2. removed the `&remoteproc_soccp { … }` override block
3. removed the dangling `remote-endpoint = <&pcie4_port0_ep>;` line inside
   `wlan-connector/ports/port@0/endpoint@0`

Plus the two thermal labels his own series adds (`pmh0104_l1_thermal`,
`pmh0110_h0_thermal`), applied to the pmh dtsi files as his patch 2/3 does.

None of these touch display or audio. SoCCP battery support comes from our out-of-tree
`soccp_glink` regardless. **But the DTB is Konrad's minus those two blocks — say so if we
report results upstream.**

**DTB built successfully: 154 332 bytes.** First time his device tree has ever compiled here.

## ✅ BUILT AND STAGED — 2026-07-28 14:07

| artifact | |
|---|---|
| `/boot/vmlinuz-7.2.0-rc3-konrad1` | 62 835 200 B |
| `/boot/initrd.img-7.2.0-rc3-konrad1` | 57 795 515 B |
| `/boot/glymur/konrad-a16.dtb` | 154 332 B |
| modules in `/lib/modules/7.2.0-rc3-konrad1` | **8447 / 8447** |
| **ADSP firmware inside the initrd** | **verified present (2 matches)** |

GRUB entry `fedora-glymur-konrad1`; backup `/boot/grub/grub.cfg.bak-pre-konrad1`;
**`set default=` still `fedora-glymur-baseline`**; 32 menu entries, all 7.1 entries untouched.

Release string is `7.2.0-rc3-konrad1` (EXTRAVERSION `-rc3` is preserved), so it can never be
confused with a `7.1.0-glymur-*` build.

**Expected on this boot:** no battery percentage (`soccp_glink` is not upstream) and no ASUS
hotkeys (Konrad's hid-asus patch is unmerged). The keyboard still works as generic HID.
That is by design — see the carry-over table above.

### Test order (why display before audio)

1. Does eDP light, and at what link rate, **without** our HBR3 force?
2. **`kscreen-doctor --dpms off`** — does the SoC still hard-reset?
3. Audio: `sudo dmesg | grep -aE "CMD timeout|DSP returned"`.

Audio still has a live non-kernel explanation (the X1E-derived topology, never yet varied),
whereas the display crash has survived every elimination. So his tree is worth more to us as
a display experiment first.

⚠️ Do not leave that boot idle before running step 2 — a self-blank would confound exactly
the measurement being taken. The stay-awake user service starts there too, but the point is
to trigger the teardown deliberately, not accidentally.

## ★★★ FIRST konrad1 BOOT (2026-07-28) — it booted fine; the panel just never lit

Reported as "failed to boot, nothing". It did **not** fail — journald shows boot `-1` ran
`7.2.0-rc3-konrad1` all the way to a **Plasma session**. There was simply no display, so
nothing appeared. (Same trap as test72 earlier: headless ≠ dead. Check
`journalctl --list-boots` before concluding a kernel does not boot.)

### Root cause of the black screen: the GPU takes the display down with it

```
msm_dpu ae01000.display-controller: bound af54000.displayport-controller
msm_dpu ae01000.display-controller: bound af5c000.displayport-controller
msm_dpu ae01000.display-controller: bound af6c000.displayport-controller   <- eDP, bound OK
msm_dpu ae01000.display-controller: bound af64000.displayport-controller
msm_dpu ae01000.display-controller: failed to load adreno gpu
msm_dpu ae01000.display-controller: failed to bind 3d00000.gpu (a3xx_ops): -19
msm_dpu ae01000.display-controller: adev bind failed: -19
```

with, upstream of it:

```
adreno 3d00000.gpu: deferred probe timeout, ignoring dependency
arm-smmu 3da0000.iommu: probe with driver arm-smmu failed with error -110
gxclkctl-kaanapali 3d64000.clock-controller: probe ... error -110
```

**All four DP controllers bound.** Konrad's display wiring is fine. What killed it is that his
DTS enables `&gpu`/`&gmu` — which ours never has — and adreno cannot probe here because its
SMMU and GX clock controller time out. `msm` is a *component* framework, so one failed
component fails the whole master bind: no DRM device, `fb0` stays on the UEFI
`simple-framebuffer`, panel dark.

**Fix applied:** `&gpu` and `&gmu` set to `status = "disabled"` in our copy of his DTS; DTB
rebuilt (154 340 B) and reinstalled over `/boot/glymur/konrad-a16.dtb`, so the existing
`fedora-glymur-konrad1` entry picks it up with no menu change.

### ★ Second finding: the sound card proves the topology-filename mechanism

```
snd-x1e80100 sound: probe with driver snd-x1e80100 failed with error -2
```

`-ENOENT`. His `model = "GLYMUR-ASUS-Zenbook-A16-UX3607OA"`, so
`audioreach_tplg_init()` requests `qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin`,
which does not exist here. This is direct confirmation of the
`qcom/<driver_name>/<card name>-tplg.bin` derivation, and it gives us a clean lever: **the
topology in use is selected purely by the DT `model` string.**

For now our existing 29 KB topology was copied to that filename so the card can probe at all
(a control, matching 7.1 behaviour). Swapping in `firmware/tplg/GLYMUR-CRD.tplg` under that
name is then a one-file, one-variable test of the topology hypothesis.

### Next boot of konrad1 — what to look for

1. Does the panel light now that the GPU is out of the way?
2. If yes: `kscreen-doctor --dpms off` — **does the SoC still hard-reset?**
3. Audio: does the card probe, and does `GRAPH_START` still time out?

Note the GPU being disabled is a deviation from Konrad's tree; add it to the declared list
alongside the two removed override blocks.

## ★★★ SECOND konrad1 BOOT (2026-07-28) — the GPU fix worked, and it exposed three real gaps

With `&gpu`/`&gmu` disabled the machine **boots completely**: `Startup finished in 16.000s`,
`Reached target graphical.target`, full Plasma Wayland session. The 7.2 kernel is not the
problem — Jesse's long-standing "I could never boot 7.2" was almost certainly this same
picture: a healthy system with no display and no network, therefore invisible.

### 1. ★ msm now binds — and eDP link training FAILS at Konrad's default rates

```
msm_dpu ae01000.display-controller: bound af54000 / af5c000 / af6c000 / af64000
[drm] Initialized msm 1.13.0 for ae01000.display-controller on minor 1
msm_dpu ae01000.display-controller: no GPU device was found
panel_samsung_atna33xc20 loaded
[drm:msm_dp_ctrl_link_train_1_2] *ERROR* link training #2 on phy 0 failed. ret=-110
[drm:msm_dp_ctrl_setup_main_link]  *ERROR* link training on sink failed. ret=-110   (repeating)
```

The DRM device comes up, the correct Samsung OLED panel driver loads, and then **link
training fails with `-110`** — the exact wall this project hit for days before discovering
that the panel only trains at **HBR3 (810000)**.

**This tree deliberately omitted our HBR3 force**, precisely to find out whether Konrad's
device tree negotiates correctly on its own. **It does not.**

⇒ **Our HBR3 finding is not a local hack — it is required on this hardware, and upstream's
A16 device tree does not address it.** That is a reportable result: his series claims
"Display" works, and on a retail UX3607OA with v7.2-rc3 the internal panel does not train.
Possible explanations to check before asserting anything upstream: a different panel SKU, a
newer msm than rc3, or the path simply never being exercised.

### 2. Wi-Fi dies because the WCN rail is switched off

```
VREG_WCN_3P3: disabling
/wlan-connector: Fixed dependency cycle(s) with /soc@0/geniqup@ac0000/serial@a98000
```

The 3.3 V WCN regulator is disabled, so the Wi-Fi card has no power — that is why the box was
unreachable. Our own DTB keeps this rail up (the pin stays reserved / the regulator stays on).

### 3. CDSP firmware is absent

```
remoteproc1: Direct firmware load for qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn failed: -2
```

His DTS enables `&remoteproc_cdsp`; we only ever extracted the **ADSP** firmware
(`qcadsp8480.mbn`). Noisy but not fatal.

### What this means for the project

**None of our out-of-tree work is optional.** Upstream's device tree alone yields a machine
with no panel, no Wi-Fi and a missing co-processor image. The HBR3 force in particular is
load-bearing, and it is the piece most worth telling upstream about.

**Deviations from Konrad's DTS now stand at four** (declare all of them in any report):
`&pcie4_port0_ep` block removed, `&remoteproc_soccp` block removed, the dangling
`remote-endpoint` line removed, and **`&gpu`/`&gmu` disabled**.
