# eDP Status — ASUS Zenbook A16 (UX3607OA / X2E94100 / glymur)

Machine `loazen` · Fedora 44 KDE aarch64 · kernel `7.1.0-glymur-clean+`
Booted DTB: `/boot/glymur/glymur-a16-test55.dtb` (model: `Qualcomm Technologies, Inc. Glymur CRD`)
Written 2026-07-19, from live inspection of this machine + the migrated archive.

## Where this actually stands

**The device-tree work is done.** `test57.dts` already enables the whole eDP chain and
carries the correct panel node. The remaining blocker is a *runtime* failure — eDP link
training — not a missing DT description. Do not re-derive the DT; it exists.

## Live state on the running machine (test55)

Display is on the UEFI framebuffer via `simpledrm`; the real stack never loads:

```
/sys/class/drm/card0 -> ../../devices/platform/simple-framebuffer.0/drm/card0
[drm] Initialized simpledrm 1.0.0 for simple-framebuffer.0 on minor 0
```

Current cmdline (note: `efi=noruntime` and `kvm-arm.mode=protected` are **already set**):

```
BOOT_IMAGE=/boot/vmlinuz-7.1.0-glymur-clean+ root=UUID=7db7b00f-... rw
clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime arm64.nopauth
console=tty0 ignore_loglevel modprobe.blacklist=msm rd.timeout=60 panic=10
softlockup_panic=1 kvm-arm.mode=protected systemd.mask=dev-tpm0.device ...
```

The one probe failure in the display path:

```
qcom-edp-phy faac00.phy: error -ENOENT: failed to get clocks
qcom-edp-phy faac00.phy: probe with driver qcom-edp-phy failed with error -2
[   30.691732] VREG_EDP_3P3: disabling
```

This is **expected on test55, not a new bug**: `phy@faac00` pulls two of its three
clocks (`aux`, `cfg_ahb`) from `dispcc`, and on test55 `dispcc` is `status="disabled"`.
`faac00.phy` is the only unbound platform device in the display path, and the 3.3V eDP
rail powers down 30s in because nothing claims it. Flipping to test57 resolves all of
this by construction.

## The hardware

| Item | Value |
|---|---|
| Panel | **Samsung ATNA60HR07**, `"samsung,atna60cl08"`, `"samsung,atna33xc20"` |
| Mode | 2880×1800, 60/120 Hz, 10 bpc |
| Panel enable GPIO | TLMM **18** |
| `vreg_edp_3p3` enable GPIO | TLMM **70** |
| MDSS | `display-subsystem@ae00000` — `qcom,glymur-mdss` |
| DPU | `display-controller@ae01000` — `reg-names = "mdp","vbif"`, VBIF base `0xaeb0000` |
| eDP controller | `displayport-controller@af6c000` — `qcom,glymur-dp` (`mdss_dp3`) |
| eDP PHY | `phy@faac00` — `qcom,glymur-dp-phy` (`mdss_dp3_phy`), phandle `0xf7` |
| dispcc | `clock-controller@af00000` — `qcom,glymur-dispcc`, phandle `0xae` |
| IOMMU | `iommus = <apps_smmu 0x1de0 0x2>` |

`af6c000` is the internal panel: it is the only DP controller on a dedicated PHY (the
other three at `af54000`/`af5c000`/`af64000` sit on USB3-DP combo PHYs), and the only
one with 5 clocks rather than 6 (no `stream_1_pixel`). Same layout as X1E80100 laptops.

## test55 vs test57

Verified by direct inspection of both DTS files (`dts/` in this repo):

| Node | test55-usb (daily) | **test57** |
|---|---|---|
| `clock-controller@af00000` (dispcc) | disabled | **okay** |
| `display-subsystem@ae00000` (mdss) | disabled | **okay** |
| `displayport-controller@af6c000` | okay | okay |
| `phy@faac00` | okay | okay |
| `aux-bus` + panel node | present but inert | **present and live** |

test57's eDP block, verbatim:

```dts
displayport-controller@af6c000 {
        compatible = "qcom,glymur-dp";
        clocks = <0xae 0x06 0xae 0x37 0xae 0x39 0xae 0x3e 0xae 0x3f>;
        clock-names = "core_iface", "core_aux", "ctrl_link", "ctrl_link_iface", "stream_pixel";
        phys = <0xf7>;
        phy-names = "dp";
        status = "okay";
        ...
        port@1 {
                endpoint {
                        data-lanes = <0x00 0x01 0x02 0x03>;
                        link-frequencies = <0x00 0x608f3d00 0x00 0xa0eebb00
                                            0x01 0x41dd7600 0x01 0xe2cc3100>;
                };
        };
        aux-bus {
                panel {
                        compatible = "samsung,atna60cl08", "samsung,atna33xc20";
                        enable-gpios = <0x69 0x12 0x00>;   /* tlmm gpio18 */
                        power-supply = <0xfa>;             /* vreg_edp_3p3 */
                };
        };
};
```

Prebuilt DTB exists at
`Zenbook A16 Linux on ARM/Linux-X2-Project/boot-kit/test57.dtb`.

## Driver support is already installed

Nothing needs building:

```
/lib/modules/7.1.0-glymur-clean+/kernel/clk/qcom/dispcc-glymur.ko   "QTI DISPCC Glymur Driver"
/lib/modules/7.1.0-glymur-clean+/kernel/drivers/gpu/drm/msm/msm.ko  "MSM DRM Driver"
```

`dispcc_glymur` carries the right modalias (`of:N*T*Cqcom,glymur-dispcc`). Upstream
`msm_mdss.c` has `qcom,glymur-mdss`; `phy-qcom-edp.c` has `qcom,glymur-dp-phy`. Both
were confirmed byte-identical to master during the earlier investigation.

## History — the root cause reversed twice

**Phase 1 (07-12) — "TrustZone XPU wall."** Enabling MDSS caused a silent hard warm-reset
the instant the kernel wrote a DPU VBIF register (`off=0x160 val=0x22222223`,
`VBIF_OUT_AXI_AMEMTYPE_CONF0`). Reads worked; the write reset the box. eDP, link rate,
SMMU, interconnect, clocks, power domains all ruled out. Retail `.309` BIOS RE showed
`acvmid = 0x3C` and no runtime unlock SMC. Upstream `drm-msm-next` was byte-identical →
concluded unfixable.

**Phase 2 (07-13) — pKVM bypass.** A kretprobe on `kvm_arm_vmid_update` forcing a
nonzero stage-2 VMID let a guest perform the VBIF write **without resetting the box**,
confirmed by host readback. The gate is "EL1 guest with nonzero stage-2 VMID" vs
"bare-metal EL2 with VMID 0". `kvm-arm.mode=protected` reproduces this for the ordinary
host. Only `0x22222223` is safe — junk values hard-hang.

**Phase 3 (07-15) — the re-frame, and the current view.** IORT has no MDSS node and DSDT
shows ordinary `disp_cc_mdss_*` clock gating → **there is no SMMU StreamID wall**. The
Phase-1 resets are now attributed to (a) missing `efi=noruntime`, and (b) a forced
modeset causing an MDSS GDSC power-cycle. The verdict "retail firmware makes native
display impossible" is recorded as **wrong**.

> The real surviving symptom is eDP link training `-110` — a DP PHY / panel power
> sequencing / AUX problem.

```
*ERROR* link training #2 on phy 0 failed. ret=-110
```

**Phase 4 (2026-07-19) — link training is a red herring.** A sweep of all ~35 boot logs
on the media does not support the link-training framing:

- **eDP AUX/EDID *works*.** On test48 (netconsole-captured) msm read the panel correctly
  as Samsung ATNA60HR07, 2880×1800 @60/120, 10-bit, and discovered the backlight.
- **Link rate was already falsified.** test51 forced `video=eDP-1:1920x1080@60` and hard
  reset identically. Low link rate does not help.
- **The `-110` in `DT-TEST57-NOPKVM.log` is SCMI cpufreq**, not eDP AUX. Do not confuse
  the two — they appear in the same logs.
- **The fault is not eDP-specific at all.** A libdrm atomic-**writeback** reproducer
  (`/var/tmp/wbtest`), which exercises DPU plane-fetch → compose → writeback with no
  eDP, PHY, or panel involved, still hard-resets at `drmModeAtomicCommit`.

The evidenced failure remains the **VBIF `0x160` write** (Phase 1): read succeeds, write
silently warm-resets. Patching the driver to skip VBIF writes only relocates the reset to
the next protected register — the signature of multiple TZ/XPU-locked registers.
`DT-TEST60-pstore.log` being 0 bytes fits: the reset is below the kernel, so nothing ever
reaches pstore.

## The untried step

From `DTB_CHANGELOG.md`, update of 07-15 — planned, never executed:

> Keep `video=simplefb` at 2880×1800. msm attaches to the **already-live simplefb
> framebuffer** and never disables the CRTC → MDSS GDSC never drops → no power-cycle
> reset. The clean version = mdss on + msm loaded + pKVM + `efi=noruntime` + **no**
> `simplefb:off` + **no** forced `video=`.

Against the current machine the delta is small: this box already boots with
`efi=noruntime` and `kvm-arm.mode=protected`. What changes is only:

1. DTB `glymur-a16-test55.dtb` → `test57.dtb`
2. Drop `modprobe.blacklist=msm`
3. Add **nothing** else — no `video=`, no `simplefb:off`

### What the logs can and cannot tell you (checked 2026-07-19)

**Every one of the ~35 boot logs on the media was captured with `modprobe.blacklist=msm`.**
There is no logged boot in which msm actually bound. `DT-TEST57-NOPKVM.log` is the
*control* — test57's DTB with the eDP nodes present and no driver touching them — not
the experiment. It shows a clean boot: `dispcc-glymur ... sync_state() pending due to
ae00000.display-subsystem` (dispcc binds fine, waiting for the consumer that never
arrives), then `VREG_EDP_3P3: disabling`.

**No SMMU fault exists anywhere.** A strict sweep for `Unhandled context fault`,
`context fault`, `fsr=`, `fsynr=`, `cbfrsynra`, `C_BAD_STREAMID` across every log returns
zero hits. Both SMMUs probe healthy in every boot. This is corroborated independently:
buffers *do* map at commit, and the retail BIOS DEVCFG maps display StreamIDs to
`OutputBase 0x1DE0`, matching the DT's `iommus = <apps_smmu 0x1de0 0x2>`. One real
detail worth carrying: `arm-smmu 15000000.iommu: preserved 0 boot mappings` — whatever
mapping XBL held for BOOTFB is gone before Linux runs.

**What test57 + msm loaded actually does** (from `07_DTB_CHANGELOG.md`, confirmed two
nights running) is *not* a hard reset:

> Console shows garbled/overlapping lines (msm/DPU probing clobbers the fbcon over the
> simplefb framebuffer), screen goes BLACK, then the boot chime plays (so it reaches
> userspace — it is NOT a hard reset). Result: no display + no WiFi. Box unreachable
> over SSH.

So mdss-enabled + msm **blacklisted** = fine; mdss-enabled + msm **loaded** = black
screen and dead Wi-Fi. That is a different failure from test48's reset.

**Confound:** `efi=noruntime` was missing from the test55/56/57/58/59 boots — only
`7-17-26TEST55.log` carries it. The changelog notes many past "display crashes" were
likely that, not the XPU wall. The current daily boot does have it.

**The missing capture.** No netconsole or serial log of *mdss enabled + msm loaded*
exists. The changelog lists it as the open action item. Because that boot kills Wi-Fi,
netconsole over Wi-Fi cannot survive it — plan for USB-ethernet or serial.

**The videos are not eDP tests.** All nine `VID*.mp4` on the media date 07-09 → 07-11,
predating the 07-12 display work. Frame extraction + OCR across all nine returns zero
hits for `dpu`/`mdss`/`vbif`/`link train`/`dispcc`/`msm_dp`. They document the TLMM
watchdog-reset era and Ubuntu-era black-screen boots.

## Traps — read before booting anything

- **MDSS enabled + msm loaded ⇒ Wi-Fi dies.** Confirmed across two nights. A runtime
  interaction, not a DT diff. Expect to lose network on a successful display boot.
- **Every `dt-*` cmdline MUST carry `efi=noruntime`**, or you get intermittent warm
  reset at fbcon commit.
- **Keep ps8830/ps883x retimers disabled** — they crash on bind under pKVM. Irrelevant
  to internal eDP.
- **Do not re-free TLMM pins 18/70** — already freed in test48. test59 was a no-op;
  test61 (freeing gpio 12/13/18) crashed and was deleted.
- **`update-grub` wipes hand-edited entries.** Add a *new* entry; never modify the
  known-good one.
- **Do not build on 7.2/linux-next** — pin v7.1.
- Known-good fallback to preserve: kernel `7.1.0-glymur-clean+`, DTB
  `glymur-a16-test55.dtb`, `modprobe.blacklist=msm`.

## After eDP comes up

Brightness is a **separate problem**. The backlight is a PMIC device
(`\_SB.BCL1` / `QCOM0F77` / FGBCL, `qcfgbcl8480.inf`) — PMIC-driven, not GPIO PWM — and
needs its own Linux driver. `/sys/class/backlight/` is currently empty. Do not expect
brightness control to arrive with the panel.

## Correction to an earlier draft

An earlier version of this file, written from live machine state before the archive was
read, concluded that no panel node had ever been attempted and proposed writing one.
That was wrong: `test57.dts` has had a complete, correct panel node since 07-14. The
remaining work is link training, not DT authoring.
