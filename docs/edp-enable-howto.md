# Enabling native eDP on the ASUS Zenbook A16 (glymur) — required settings

Everything that has to be in place to get the internal panel to link up. This is the
reproduction recipe; **why** each piece is needed is in
[`edp-hbr3-linkup-2026-07-24.md`](edp-hbr3-linkup-2026-07-24.md).

> **Status: working, not yet baked.** The link trains and the mode sets, but the
> running driver still carries two diagnostic changes and `msm` is hand-bound rather
> than auto-loaded. See [§7 Known gaps](#7-known-gaps-before-this-is-daily-drivable)
> before relying on it.

Verified on: ASUS Zenbook A16 **UX3607OA** (Snapdragon X2 Elite Extreme, "glymur"),
Fedora 44 aarch64, kernel `7.1.0-glymur-clean2`, panel Samsung/SDC **ATNA60HR07-0**.

---

## 1. Kernel config

Built from mainline **v7.1** (do **not** use 7.2 / linux-next).

```
CONFIG_CLK_GLYMUR_DISPCC=m              # dispcc — the display clock controller
CONFIG_CLK_GLYMUR_GCC=y
CONFIG_PINCTRL_GLYMUR=y
CONFIG_DRM_MSM=m
CONFIG_DRM_MSM_DP=y
CONFIG_PHY_QCOM_EDP=m                   # the eDP PHY (QSERDES v8)
CONFIG_DRM_PANEL_SAMSUNG_ATNA33XC20=m   # panel + dp_aux_backlight
CONFIG_DRM_DISPLAY_DP_AUX_BUS=m
CONFIG_DRM_DISPLAY_HELPER=m
CONFIG_DRM_FBDEV_EMULATION=y
```

`CONFIG_CLK_GLYMUR_GPUCC` is **not** set and does not need to be — there is no
sm8750 gpucc in mainline, and `no GPU device was found` is harmless for eDP.

---

## 2. Device tree

Base: upstream `glymur.dtsi` from the v7.1 tree. Our working DTB is
[`dts/test62.dts`](../dts/test62.dts) → `/boot/glymur/glymur-a16-test62.dtb`.

Four things must be true. The first two are the ones that silently break everything.

### 2.1 `dispcc` `clocks[]` — the eDP PHY must sit in the **DP3** slot

`dispcc-glymur.c:25-44` resolves parents **by array index**. The eDP PHY
(`phy@faac00`, phandle `0xf7` here) belongs at indices **8-9**, not 2-3:

```dts
clock-controller@af00000 {
    compatible = "qcom,glymur-dispcc";
    clocks = <0x3a 0x00 0x3b            /* XO, sleep_clk */
              0x40 0x01 0x40 0x02       /* DP0 */
              0x41 0x01 0x41 0x02       /* DP1 */
              0x42 0x01 0x42 0x02       /* DP2 */
              0xf7 0x00 0xf7 0x01       /* DP3  <-- phy@faac00, the eDP PHY */
              0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00>;
};
```

Getting this wrong orphans `dptx3_link_clk_src` / `dptx3_pixel0_clk_src` and Oopses
the kernel in `msm_dp_ctrl_enable_mainlink_clocks`. **Upstream `glymur.dtsi:4586` is
already correct** — this only matters if you are hand-editing a DTB.

Verify before booting anything else:

```bash
grep dptx3 /sys/kernel/debug/clk/clk_orphan_summary   # must print nothing
```

(Expected and harmless after the fix: `dptx2` orphans instead, because
`phy@88e1000` is disabled. DP2 is an external port we don't use.)

### 2.2 `link-frequencies` must include **8100000000**

The eDP endpoint's rate cap. `msm_dp_link_link_frequencies()` (`dp_link.c:1215`)
reads element `cnt-1` as the maximum. HBR3 is the only rate this panel trains at:

```dts
endpoint {
    data-lanes = <0 1 2 3>;
    link-frequencies = /bits/ 64 <1620000000 2700000000 5400000000 8100000000>;
};
```

Do **not** truncate this to cap at 2.7 G or 5.4 G. 2.7 G and 1.62 G are dead on this
PHY (stale v6 PLL constants in the v8 table); 5.4 G passes CR but never passes EQ.

### 2.3 `dispcc` and `mdss` must be `status = "okay"`

The `clean2` / `test55` DTBs have both **disabled**. On those, `phy@faac00` probes
with `Failed to get clk index: 0 ret: -2` and no eDP is possible at all.

```bash
tr -d '\0' < /proc/device-tree/soc@0/clock-controller@af00000/status   # okay
tr -d '\0' < /proc/device-tree/soc@0/display-subsystem@ae00000/status  # okay
```

> `model` reads `"Qualcomm Technologies, Inc. Glymur CRD"` on the eDP DTB **too** —
> it is not a useful discriminator. Trust dispcc/mdss status and the gpio ranges.

### 2.4 TLMM pin 18 must be free in `gpio-reserved-ranges`

The panel's `enable-gpios = <&tlmm 18 GPIO_ACTIVE_HIGH>` is unresolvable otherwise.
Decode the `(start, count)` pairs: the reserved range must stop at 17 and resume at 19.

Panel node, for reference:

```dts
aux-bus {
    panel {
        compatible = "samsung,atna60cl08", "samsung,atna33xc20";
        enable-gpios = <&tlmm 18 GPIO_ACTIVE_HIGH>;
        power-supply = <&vreg_edp_3p3>;
        port { endpoint { remote-endpoint = <&mdss_dp3_out>; }; };
    };
};
```

---

## 3. Driver patches

Two changes to `drivers/gpu/drm/msm/dp/`. Both are in the kernel repo on branch
`glymur-edp-hbr3`.

### 3.1 eDP 1.4 rate-set plumbing (`dp_ctrl.c`) — **upstream bug, generic**

`use_rate_set` / `rate_set` are computed into `panel->link_info` but every consumer
reads `link->link_params`, and neither `msm_dp_ctrl_on_link()` nor
`msm_dp_ctrl_link_train()` copied them across. Result: `msm_dp_aux_link_configure()`
always took the legacy `LINK_BW_SET` branch and `LINK_RATE_SET` was never written.

Not glymur-specific and not what fixes this panel, but it is a real bug and should go
upstream on its own. Patch: `patches/glymur-edp-rate-set-EXPERIMENT.patch`.

### 3.2 Force HBR3 (`dp_panel.c`) — **the change that lights the panel**

In `msm_dp_panel_read_sink_caps()`, after the rate-set selection:

```c
link_info->rate = 810000;
link_info->rate_set = 0;
link_info->use_rate_set = false;
```

This overrides the panel's own `SUPPORTED_LINK_RATES` table (which tops out at
540000) and drives the legacy `LINK_BW_SET` path, writing `DPCD 0x00100 <- 0x1e`.

`rate_set = 0` keeps `msm_dp_ctrl_link_rate_down_shift()` on its legacy switch, so a
`train_1` failure falls back 810000 → 540000 rather than into the broken low-rate PLL
entries. Patch: `patches/glymur-edp-hbr3-EXPERIMENT.patch`.

> ⚠️ **This is a hack, not a patch.** An unconditional constant is not upstreamable —
> see §7.

### 3.3 Build and install — `7.1.0-glymur-edp1`

**As of 2026-07-24 this is a whole kernel, not hand-copied modules.** Everything below
about `M=` module builds is kept for reference but should not be needed again.

```bash
cd ~/kernel-build/linux-src
git checkout glymur-edp-hbr3
make O=/home/jcasco/kernel-build/usb-out olddefconfig
make -j$(nproc) O=/home/jcasco/kernel-build/usb-out LOCALVERSION=-glymur-edp1 Image modules
sudo make O=/home/jcasco/kernel-build/usb-out LOCALVERSION=-glymur-edp1 modules_install
sudo cp /home/jcasco/kernel-build/usb-out/arch/arm64/boot/Image /boot/vmlinuz-7.1.0-glymur-edp1
sudo dracut --force --kver 7.1.0-glymur-edp1 /boot/initrd.img-7.1.0-glymur-edp1
```

`LOCALVERSION` goes on the **command line**, not in `.config` — that is how
`7.1.0-glymur-clean2` was built too, and it is why neither has the `+` suffix that
`scripts/setlocalversion` otherwise appends.

**Why a separate kernel version instead of patching clean2's modules in place.** The
old arrangement had four hand-built `.ko` files sitting in clean2's module directory
with vermagic `7.1.0+` against a kernel whose vermagic is `7.1.0-glymur-clean2`. They
loaded only because `CONFIG_MODVERSIONS=y` relaxes the vermagic check to symbol CRCs.
Combined with the initramfs trap in §6 that arrangement produced two false null results
and cost two reboots. With a real versioned build, `uname -r`, `/lib/modules`, the
initramfs and git HEAD all agree, and `7.1.0-glymur-clean2` stays on disk untouched as
the fallback.

> ⚠️ **Do not `make install`.** Fedora's kernel-install hooks write BLS entries into
> `/boot/loader/entries/`, which is *not* the menu this machine boots from (§4). Copy
> the `Image` by hand and add the GRUB entry by hand.

<details>
<summary>Historical: the per-module build used during bring-up</summary>

`msm` was built in-tree with `M=` against the `O=` tree:

```bash
cd ~/kernel-build/linux-src
make -j$(nproc) O=/home/jcasco/kernel-build/usb-out M=drivers/gpu/drm/msm modules
sudo cp drivers/gpu/drm/msm/msm.ko \
        /lib/modules/7.1.0-glymur-clean2/kernel/drivers/gpu/drm/msm/msm.ko
sudo depmod -a
```

No initramfs rebuild was needed for `msm` — it was blacklisted at boot and loaded by
hand from `/lib/modules`. `phy_qcom_edp` was different: it loads from the **initramfs**
at ~1.8 s, so `cp` + `depmod` alone changed nothing. See §6.

</details>

---

## 4. Boot configuration

### 4.0 The `edp1` entry — `msm` NOT blacklisted

This is the one to use. It differs from `test62` in exactly three ways: the kernel and
initrd are `7.1.0-glymur-edp1`, and **`modprobe.blacklist=msm` is gone** so the display
comes up on its own instead of being hand-bound by a script.

```
menuentry "Fedora (glymur A16, edp1 - native eDP, msm autoloads)" --id fedora-glymur-edp1 {
    search --set=root --fs-uuid 7db7b00f-3862-4771-afee-ece1682d2970
    devicetree /boot/glymur/glymur-a16-test62.dtb
    linux /boot/vmlinuz-7.1.0-glymur-edp1 root=UUID=7db7b00f-3862-4771-afee-ece1682d2970 rw \
          clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime arm64.nopauth \
          console=tty0 ignore_loglevel rd.timeout=60 panic=10 softlockup_panic=1 \
          kvm-arm.mode=protected systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device
    initrd /boot/initrd.img-7.1.0-glymur-edp1
}
```

Same DTB as `test62` — the device tree did not change.

**This is the GRUB default as of 2026-07-24:** `set default="fedora-glymur-edp1"`, set by
`--id` rather than index so it survives entries being reordered. `set timeout=10` gives a
10-second window to pick `test55` (the known-good fallback) or `test62` (eDP with `msm`
hand-bound) by hand. Neither of those entries was modified — per the standing rule, never
edit the fallback in place. Previous menu saved as `/boot/grub/grub.cfg.bak-pre-default-edp1`.

`panic=10 softlockup_panic=1` are kept on purpose: if `msm` autoloading wedges the box,
it reboots itself in 10 s instead of needing an unplugged drain. Note that with edp1 as
the default this reboots *back into edp1*, so a hard hang still needs a manual pick at
the menu.

### 4.1 The bring-up entry (`test62`, `msm` hand-bound)

Kept as the fallback and for instrumented runs.

```
menuentry "Fedora (glymur A16, test62 - dispcc clocks[] dp3 slot fixed + pKVM)" --id fedora-glymur-test62 {
    search --set=root --fs-uuid <root-uuid>
    devicetree /boot/glymur/glymur-a16-test62.dtb
    linux /boot/vmlinuz-7.1.0-glymur-clean2 root=UUID=<root-uuid> rw \
          clk_ignore_unused pd_ignore_unused cma=128M efi=noruntime arm64.nopauth \
          console=tty0 ignore_loglevel modprobe.blacklist=msm rd.timeout=60 \
          panic=10 softlockup_panic=1 kvm-arm.mode=protected \
          systemd.mask=dev-tpm0.device systemd.mask=dev-tpmrm0.device
    initrd /boot/initrd.img-7.1.0-glymur-clean2
}
```

Load-bearing cmdline arguments:

| argument | why |
|---|---|
| ~~`efi=noruntime`~~ | **RETIRED 2026-07-30 — no longer load-bearing.** The "intermittent warm reset at fbcon commit" was never reproducible on a clean tree, and it was established in the window where this very flag was a documented confound. Dropping it changes no capability. See `docs/DTB_CHANGELOG.md` |
| `kvm-arm.mode=protected` | **pKVM must stay ON.** Dropping it was correct for test57 and wrong for test58/test62 |
| `cma=128M` | framebuffer allocation |
| `modprobe.blacklist=msm` | keeps `msm` off the boot path so it can be bound by hand under instrumentation. Not required for a working display — see §7 |
| `clk_ignore_unused pd_ignore_unused` | keeps display clocks/power domains alive through boot |

Also keep `ps8830` / `ps883x` retimers disabled — they crash on bind under pKVM and
are irrelevant to internal eDP.

---

## 5. Running it

```bash
sudo ~/Projects/zenbook-a16-linux/scripts/edp-train-probe.sh hbr3
```

The script installs the ftrace kprobes, verifies module provenance, stops the display
manager, binds `msm`, and writes `logs/edp-hbr3-{RESULT,bind,phy}.log`.

Success looks like:

```
*** LINK TRAINING FULLY SUCCEEDED ***
EQ-check  0x202=0x77 0x203=0x77 ALIGN=1 | L0:CR EQ SYM L1:CR EQ SYM L2:CR EQ SYM L3:CR EQ SYM
link_rate=810000   use_rate_set=0   0x00100 <- 1e   (no 0x00115 write)
XXX setvolt: is_edp=1 rate=8100 ...
mainlink READY
```

Confirm from sysfs:

```bash
cat /sys/class/drm/card1-eDP-1/status   # connected
cat /sys/class/graphics/fb0/name        # msmdrmfb  (NOT simplefb)
```

> The display manager here is **`plasmalogin.service`** (aliased `display-manager`),
> not sddm. `systemctl stop sddm` is a silent no-op.

---

## 6. Module provenance — verify before trusting any run

This has invalidated four separate experiments. `phy_qcom_edp` loads from the
initramfs, and the hand-written GRUB entries load **`/boot/initrd.img-<kver>`**, not
the dracut-default `/boot/initramfs-<kver>.img`.

```bash
# rebuild the file the GRUB entry actually loads
sudo dracut --force --kver 7.1.0-glymur-clean2 /boot/initrd.img-7.1.0-glymur-clean2

# verify the initramfs carries what you built
sudo lsinitrd -f usr/lib/modules/7.1.0-glymur-clean2/kernel/drivers/phy/qualcomm/phy-qcom-edp.ko \
     /boot/initrd.img-7.1.0-glymur-clean2 > /tmp/x.ko
modinfo -F srcversion /tmp/x.ko

# and verify what is actually RUNNING matches what is on disk
diff <(cat /sys/module/phy_qcom_edp/srcversion) \
     <(modinfo -F srcversion $(modinfo -n phy_qcom_edp)) && echo "module OK"
```

If those differ, whatever you just "tested" was a different driver.
`rmmod phy_qcom_edp && modprobe phy_qcom_edp` loads the on-disk one — but only
**before** `msm` binds.

⚠️ **`rmmod msm` hard-freezes this box.** Every `msm`-side change costs a reboot.

---

## 7. Known gaps before this is daily-drivable

1. ~~The running `phy_qcom_edp` is a diagnostic build.~~ **Closed 2026-07-24.** The
   confirmation run passed on the stock swing table, and `7.1.0-glymur-edp1` runs the
   pristine v7.1 PHY (srcversion `D981A7A0AE1ECDA17C26A43`). The link rate alone was the
   fix.
2. **The HBR3 change is an unconditional constant**, not a patch. Needs to become
   either a firmware-handoff read or a panel/DT quirk before it can go upstream.
3. ~~`msm` is still blacklisted and hand-bound.~~ **Closed 2026-07-24.** Booted
   `7.1.0-glymur-edp1` with no `modprobe.blacklist=`: `msm` autoloads, binds, and lights
   the panel unattended — `fb0 = msmdrmfb`, `eDP-1` connected + enabled,
   `dp_aux_backlight` present, no oops or panic.
4. **Suspend/resume untested.** ← now the top remaining gap.
5. ~~`drm.debug=0x100` and the `XXX` instrumentation are still in.~~ **Closed
   2026-07-24.** The `XXX` markers went with the PHY revert, and the `edp1` command line
   carries no `drm.debug` — which is why `link training … successful` no longer prints.
6. Brightness works (`dp_aux_backlight`, 0–2047) but full **brightness key** handling
   still wants a PMIC FGBCL driver.

---

## 8. Fallback

Never edit the known-good entry in place. `update-grub` wipes hand-written entries —
always add a new one.

| Entry | Purpose |
|---|---|
| `fedora-glymur` | test55 — known-good fallback, display off |
| `fedora-glymur-clean2` | clean2 kernel, display off — daily driver |
| `fedora-glymur-test62` | **the eDP entry** |

Revert the PHY driver entirely:

```bash
sudo cp ~/Projects/zenbook-a16-linux/patches/phy-qcom-edp.ko.orig \
        /lib/modules/$(uname -r)/kernel/drivers/phy/qualcomm/phy-qcom-edp.ko
sudo depmod -a
sudo dracut --force --kver $(uname -r) /boot/initrd.img-$(uname -r)
```

NVMe partitions **p1–p11** (Qualcomm/WoA firmware) and **p13–p16** (Windows) must
never be touched. Linux root is p17.
