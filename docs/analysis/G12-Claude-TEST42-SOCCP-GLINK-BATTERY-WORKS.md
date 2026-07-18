# G12 — Test42: BATTERY WORKS. SOCCP GLINK edge → qcom_battmgr live. (MILESTONE 6)

**TL;DR.** Battery is up on the A16 via the standard upstream `qcom_battmgr`/`pmic_glink`
path. The test41 "battmgr is impossible" conclusion was overturned by RE: the charger service
is **PMIC-GLINK hosted on the SOCCP** (channel `PMIC_RTR_SOCCP_APPS`), and Linux simply had no
SOCCP glink edge. Standing one up (inert DT node + a tiny out-of-tree registrar module) made the
SOCCP open its channels and `qcom-battmgr-bat` populate with real data.

**Live result (test37 DTB + soccp_glink.ko):**
- rpmsg channels appeared: `PMIC_RTR_SOCCP_APPS`, `PMIC_LOGS_SOCCP_APPS`, `IPCRTR` (platform edge).
- `pmic_glink` bound to `PMIC_RTR_SOCCP_APPS` (`qcom_pmic_glink_rpmsg`).
- `qcom-battmgr-bat`: present=1, status=Not charging, **voltage_now=12.661 V**, temp=30.7 C,
  technology=Li-ion, model_name=340758, manufacturer=AS3GZHg3KB, cycle_count=14, power_now=0.
- `qcom-battmgr-usb` online=1. **upower: 79.56 %, 55.76 / 70.088 Wh, energy-full-design 70.016 Wh.**
- New `glink-smem` IRQ (ipcc 3014656) actively firing (~1142 in seconds) = SOCCP↔APPS live.
- Benign: `ucsi_glink ... PPM init failed, stop trying` (USB-C UCSI over SOCCP; unrelated to battery).

---

## Why this works (the corrected model)
- test41 found no charger **PD** in the servreg/PDR `.jsn` lists — true, but the charger service
  isn't a PD; it's a **glink channel**. `qcpmicglink8480.sys` strings: `PMIC_RTR_SOCCP_APPS`,
  `PMIC_LOGS_SOCCP_APPS`, `\Callback\pmicGlinkSMEMUpdatedCB`, `soccp` → PMIC-GLINK lives on the
  **SOCCP**, and it also updates SMEM (that's what fed the SOSI/qcabd path on Windows).
- The kernel already supports it: `pmic_glink.c` has `pmic_glink_soccp_data` and matches channel
  `PMIC_RTR_SOCCP_APPS` (line 285); our `pmic-glink` node (`qcom,glymur-pmic-glink`) already uses
  the soccp data. The ONLY missing piece was a **SOCCP glink edge** — no driver in this tree calls
  `qcom_glink_smem_register()` for the SOCCP (remoteproc/ has no soccp support).
- SOCCP is UEFI-loaded and already running (smp2p-soccp negotiated), so no remoteproc/PAS is
  needed. `qcom_glink_smem_register(parent, node)` is exported and stands up the SMEM glink
  transport for a host-pid from a DT node alone.

## What was built
1. **DT (test37 = test36 + one inert root node):**
   ```
   soccp_glink_edge {
       compatible = "asus,soccp-glink";
       glink-edge {
           label = "soccp";
           qcom,remote-pid = <0x13>;              /* SOCCP host pid 19 */
           mboxes = <0x39 0x2e 0x00>;             /* &ipcc, client 46, glink signal 0 */
           interrupts-extended = <0x39 0x2e 0x00 0x01>;
       };
   };
   ```
   IPCC = mailbox@3e04000 (phandle 0x39). SOCCP IPCC client 0x2e(46) from smp2p-soccp; glink
   signal 0 (smp2p uses signal 2). Node is inert unless the module binds it (boot-safe).
2. **Out-of-tree module `soccp_glink.ko`** (`boot-kit/soccp-glink/soccp_glink.c`): platform driver
   matching `asus,soccp-glink`; on probe calls `qcom_glink_smem_register(dev, of "glink-edge")`.
   depends: qcom_glink_smem. Reversible (rmmod unregisters).

## Persistence (installed on box)
- `/lib/modules/7.1.0-glymur-full/extra/soccp_glink.ko` + `depmod -a`.
- `/etc/modules-load.d/soccp_glink.conf` = `soccp_glink` → auto-loads late in userspace (cannot
  block boot). Boot DTB repointed to `glymur-a16-test37.dtb` (40_custom backed up to
  `.bak.test36`). Artifacts also in `/mnt/app_stuff/boot-kit/out/` and project `boot-kit/soccp-glink/`.
- `a16-battery` (the SOSI/ABD reader hack) is now obsolete — battmgr is the real path.

## Upstreaming
- The clean upstream fix is a proper **SOCCP remoteproc driver** (manages power/SSR + registers the
  glink edge). Our module is the minimal working proof + interim: it registers only the edge and
  relies on the firmware-run SOCCP. Good basis for a linux-arm-msm post: "Glymur SOCCP glink edge +
  pmic_glink battery". DT node + channel name are the key facts.

## Next (test43 candidates)
- Make `capacity` populate (upower % works via energy; raw `capacity` attr empty — check battmgr
  request set for the SOCCP variant).
- UCSI PPM over SOCCP (USB-C alt-mode/PD status) — the `PPM init failed` path.
- Fold the node into a proper soccp remoteproc for SSR/upstream.
- Then AUDIO (gpr/q6apm + userspace) per G06, then GPU.
