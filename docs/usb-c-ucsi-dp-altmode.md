# USB-C: UCSI, PD and DisplayPort alt-mode on glymur

**Status 2026-07-25: SOLVED.** UCSI works, PD is negotiated, and **DisplayPort
alt-mode over USB-C drives an external monitor** (`DP-1 connected`, 1920x1080,
`msm_dp_display_enable ... rc=0`). Fixed by deleting **one property** from the device
tree.

USB4/Thunderbolt is still **not** possible — see the last section for why, and why that
is not a device-tree problem you can solve locally.

---

---

## ★★★ PREREQUISITE, learned the hard way (2026-07-29): the SOCCP glink transport

**Everything in this document sits on top of `pmic_glink`, and on this platform
`pmic_glink`'s transport IS the SOCCP glink channel (`PMIC_RTR_SOCCP_APPS`).**

The SOCCP (SoC Companion Processor) is UEFI-loaded and already running, but **nothing in
mainline registers its GLINK-over-SMEM edge**. Without that edge there is no transport, and
**three apparently unrelated subsystems fail at once**:

| symptom | actual cause |
|---|---|
| `/sys/class/typec/` empty, `ucsi_glink` bound but **silent** (no `PPM init failed`, no success) | no transport |
| `qcom-battmgr-bat` present but `energy_now` unreadable | no transport |
| DP alt-mode never entered | no transport |

⚠️ **The silence is the tell.** The *original* UCSI bug (below) announced itself with
`PPM init failed, stop trying`. A missing transport prints **nothing at all** — `ucsi_glink`
probes, binds to `pmic_glink.ucsi.0`, and simply never completes. On 2026-07-29 this was
misdiagnosed as "the UCSI fix stopped working" and then as a `pmic_glink` device-link
failure. Both were wrong.

**Fix:** `CONFIG_QCOM_SOCCP_GLINK=m` (`drivers/soc/qcom/soccp_glink.c`) plus the DT node:

```dts
soccp_glink_edge {
        compatible = "asus,soccp-glink";

        glink-edge {
                label = "soccp";
                interrupts-extended = <&ipcc IPCC_MPROC_SOCCP
                                             IPCC_MPROC_SIGNAL_GLINK_QMP
                                             IRQ_TYPE_EDGE_RISING>;
                mboxes = <&ipcc IPCC_MPROC_SOCCP IPCC_MPROC_SIGNAL_GLINK_QMP>;
                qcom,remote-pid = <19>;
        };
};
```

Confirm it took: `dmesg | grep soccp` →
`soccp_glink soccp_glink_edge: SOCCP glink edge registered (remote-pid=19)`.

**⇒ Before debugging Type-C, battery or alt-mode, check the transport first.** Adding this
one node + driver restored Type-C *and* battery on the merged tree in a single change.

---

## The symptom

Since the very beginning of this project — long before eDP or `msm` were in the
picture — every boot logged:

```
ucsi_glink.pmic_glink_ucsi pmic_glink.ucsi.0: PPM init failed, stop trying
```

`/sys/class/typec/` was empty. No ports, no partners, no alt-modes, and therefore no
DisplayPort over USB-C.

Charging and USB-C **data** worked anyway, which is what made this easy to
misprioritise: the PMIC firmware negotiates PD autonomously, so the machine charges
and enumerates devices whether or not Linux's UCSI layer ever comes up. UCSI only buys
you the *visible* Type-C stack — port/partner state, and alt-mode control.

## The actual cause

A one-property inconsistency in our device tree.

```
ucsi.c:1665   con->usb_role_sw = fwnode_usb_role_switch_get(cap->fwnode);
              -> -EPROBE_DEFER while the referenced role switch does not exist

ucsi.c:1998   those defers are counted; past UCSI_ROLE_SWITCH_WAIT_COUNT it gives up
              -> "PPM init failed, stop trying"

dwc3/drd.c:336  if (dwc->dr_mode != USB_DR_MODE_OTG)
                        return 0;      /* no usb_role_switch is ever registered */
```

Our DT had:

| node | `dr_mode` | `usb-role-switch` |
|---|---|---|
| `usb@a600000` | `host` | **yes** |
| `usb@a800000` | `host` | no |

So `a600000` **advertised a role switch that dwc3 would never create**, because dwc3
only registers one in OTG mode. UCSI waited for it forever. `/sys/class/usb_role/` was
empty, confirming this was never a timing/retry problem — the switch simply did not
exist.

That `host` + `usb-role-switch` combination appears on **no board in-tree**. Of the 19
x1e boards in v7.1, 18 use `dr_mode = "host"` with no role switch, and the one that
declares `usb-role-switch` (`x1e001de-devkit.dts`) pairs it with `dr_mode = "otg"`.

## The fix (test68)

Delete one line from `usb@a600000`:

```dts
-			usb-role-switch;
 			status = "okay";
 			dr_mode = "host";
```

Now neither controller advertises a role switch, `fwnode_usb_role_switch_get()` returns
NULL instead of `-EPROBE_DEFER`, and `ucsi_init()` proceeds.

### The wrong fix, and why it could not work (test67)

The tempting alternative is to make the DT *honest* the other way — keep
`usb-role-switch` and set `dr_mode = "otg"` on both controllers so dwc3 really does
register a switch. That was test67. **It cannot work on this kernel:**

```
dwc3-qcom a600000.usb: Configuration mismatch. dr_mode forced to host
dwc3-qcom a800000.usb: Configuration mismatch. dr_mode forced to host
```

The build has `CONFIG_USB_DWC3=y` with `CONFIG_USB_DWC3_HOST=y` — dual-role is not
compiled in, so `dr_mode = "otg"` is silently overridden back to host. test67 is
therefore functionally identical to doing nothing.

Making that route work would need a kernel rebuild with `CONFIG_USB_DWC3_DUAL_ROLE=y`
**and** `CONFIG_USB_GADGET=y` (a modular gadget cannot serve a built-in dwc3). That is
only worth doing if you want **device-mode** USB-C (using the laptop as a USB
peripheral). It is **not** needed for UCSI, PD, or DisplayPort alt-mode.

## Result

```sh
$ ls /sys/class/typec/
port0  port0-partner  port1

$ sudo dmesg | grep -c "PPM init failed"
0

$ for m in /sys/class/typec/port*/port*.*; do
      echo "$m svid=$(cat $m/svid) active=$(cat $m/active)"; done
port0.0  svid=8087  active=yes      # Thunderbolt/USB4 SVID
port0.1  svid=ff01  active=yes      # DisplayPort alt-mode
port1.0  svid=8087  active=yes
port1.1  svid=ff01  active=yes

$ cat /sys/class/drm/card1/card1-DP-1/status
connected
```

Orientation detection works too (`/sys/class/typec/port0/orientation` = `reverse`), and
PD is live (`port0-partner/supports_usb_power_delivery` = `yes`).

## ★ Observed real-world effect (Jesse, 2026-07-29): USB-C went from intermittent to clean

Worth recording because it is **not** obvious from the sysfs-only view of this fix:

- **Before UCSI was linked up, the USB-C ports were intermittent** — devices dropping and
  re-enumerating, the USB-C hub NIC unreliable on one port (see the deferred
  "USB-C NIC hub" workstream).
- **After the fix the ports are clean**, dwc3 is stable, **and DisplayPort output over
  USB-C works.**

So the UCSI/role-switch fix is not merely cosmetic "now Linux can see the Type-C stack" — it
is what made USB-C **reliable** on this machine and what unlocked display-out. Treat any
future regression in USB-C *stability* as a possible UCSI/`pmic_glink` transport regression,
not only as a dwc3 or cable problem.

⚠️ The **USB-A** Ethernet adapter has never been affected by any of this and is the reliable
rescue route when Wi-Fi is down (`ssh -o HostKeyAlias=loazen jcasco@192.168.8.158`).

## Why this works without a retimer

Reference x1e boards (e.g. `x1e80100-microsoft-romulus.dtsi`) route the connector's
SuperSpeed and SBU lines through a **retimer**:

```dts
port@1 { ... remote-endpoint = <&retimer_ss0_ss_out>; };
port@2 { ... remote-endpoint = <&retimer_ss0_con_sbu_out>; };
```

Others use a discrete GPIO SBU mux (`onnn,fsusb42`, `gpio-sbu-mux`) on `port@2`.

Our DT has **no retimer and no `port@2`** — only `port@0` (HS) and `port@1` (SS,
straight to the QMP combo PHY). That turns out to be fine, because the QMP combo PHY
registers its own Type-C mux *and* orientation switch:

```
/sys/class/typec_mux/: fd5000.phy-mux fd5000.phy-switch fde000.phy-mux fde000.phy-switch
```

Those handle orientation and DP lane routing, so alt-mode works without the discrete
parts. Worth knowing before anyone "fixes" the missing `port@2` — it is not missing in
a way that matters here.

## The signal chain, end to end

```
USB-C cable
  -> PMIC firmware negotiates PD          (works even with UCSI down: charging, data)
  -> pmic_glink  (QMI transport to the PMIC firmware)
       -> ucsi_glink   -> UCSI core  -> /sys/class/typec/portN  + alt-mode discovery
       -> pmic_glink_altmode           -> DP alt-mode entry (SVID ff01)
            -> typec_mux / typec_switch on the QMP combo PHY (fd5000/fde000)
                 -> QMP PHY switches lanes to DP mode
            -> aux_hpd_bridge          -> HPD event into DRM
                 -> msm DP controller (af54000 / af5c000 / af6c000)
                      -> DRM connector DP-1 / DP-2 -> monitor lights up
```

Everything above the QMP PHY was already present and working; the only broken link was
UCSI never initialising, which starved the whole chain of alt-mode events.

## USB4 / Thunderbolt — still blocked, and not on us

The SVID `8087` alt-mode being active is **not** USB4. That is the Thunderbolt SVID
being advertised at the Type-C layer; actual USB4 needs a **host router** (NHI).

- No USB4 host-router / NHI node exists in **any** in-tree qcom device tree (v7.1).
  Every `usb4` grep hit is a false positive: `onnn,fsusb42` (an SBU mux part) and
  `qcom,sc8280xp-qmp-usb43dp-phy` (the USB3+DP combo PHY).
- `drivers/thunderbolt/` has **no** Qualcomm support.
- The binding is an **RFC that has not landed**: *"[PATCH RFC] dt-bindings:
  thunderbolt: Add Qualcomm USB4 Host Router"*, Konrad Dybcio, 2025-09-16.
  Review feedback asks for it to be split into platform-generic and Qualcomm-specific
  parts (for reuse on e.g. Apple Silicon).

The RFC describes exactly the pipeline observed here: UCSI → `typec_mux` altmode
notifications → QMPPHY (Qualcomm's USB4/TBT3/USB3/DP mode-switchable PHY) → USB4 Host
Router. **We now have the first three.** The missing piece is the host router binding
and driver, which does not exist upstream.

**Do not hand-write DT nodes against the unmerged RFC.** Half a pipeline against a
moving binding is how you get a regression that is hard to attribute.

Sources: <https://lkml.org/lkml/2025/9/16/1490>,
<https://lists.openwall.net/linux-kernel/2025/09/18/257>

## Verify it yourself

```sh
ls /sys/class/typec/                                  # port0, port0-partner, port1
sudo dmesg | grep -c "PPM init failed"                # 0
cat /sys/class/typec/port0/orientation                # normal | reverse
# plug a USB-C display or dock into either port:
cat /sys/class/drm/card1/card1-DP-*/status            # one should read 'connected'
sudo dmesg | grep msm_dp_display_enable               # rc=0
```
