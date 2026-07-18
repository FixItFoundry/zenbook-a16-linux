# G05 — test30 RESULT (KEYBOARD ✅) + test31 ADSP graft (battery/audio phase)

## 1. test30 outcome — the win
`hid-over-i2c 0B05:4B42 Keyboard` bound at `3-0015`, probe 0 in 147ms. Live: GICv3 617
(`88c000.i2c`) count 119+ and ticking. The IRQ off-by-one (0x248→0x249) was the entire
keyboard blocker; everything else (clock, power, pinctrl, DMA) had been correctly ruled out.
Bonus wins in the same boot: RTC alive (`rtc-pm8xxx` → rtc0; time wrong, 1970-era — offset
nit for later), all PMIC GPIO banks probed.

Boot noise (both recovered, both future fixes):
- ath12k: 3× "Timeout while waiting for regulatory update" (~9s). Fix candidate:
  `options cfg80211 ieee80211_regdom=US` in modprobe.d.
- qcom_spmi_pmic probe: 15× SPMI `transaction failed (0x3)` + 3 kernel WARNs — CRD DT
  declares PMIC peripherals (sids 0x7/0xb) the A16 lacks. DT trim candidate.

## 2. Battery/audio blocker found in minutes: NO remoteproc nodes at all
`/sys/class/remoteproc/` is empty. The 7.1 glymur.dtsi shipped only the ADSP/CDSP
reserved-mem carveouts + smp2p nodes — no remoteproc, and the 7.1 PAS driver has no glymur
compat. qcom_battmgr registers 4 blank supplies because its service runs ON the ADSP.
No ADSP = no battery data and no audio, unconditionally. This supersedes the EC question
until the ADSP is up.

## 3. The break: upstream 7.2-rc2 + sm8550 fallback compat = no kernel rebuild
`git fetch --depth 1 origin master` in ~/kernel-build/linux → glymur remoteproc landed:
`remoteproc@6800000`, compat `"qcom,glymur-adsp-pas", "qcom,sm8550-adsp-pas"`.
The 7.1 driver already binds `qcom,sm8550-adsp-pas` (pas_id 1, dtb_pas_id 0x24, dual
firmware mbn+dtb, proxy PDs lcx/lmx) — exactly why glymur ships `adsp_dtb.mbn`. So the
upstream node grafts onto our CRD DTB and binds TODAY.

## 4. test31 = test30 + ADSP node (build_test31.py)
Grafted verbatim from 7.2-rc2 except (deliberate, single-variable):
- `interconnects` omitted (optional bandwidth vote; lpass NoCs exist live if wanted later)
- `fastrpc`/compute-cb children omitted (compute offload, not battery/audio)
- CDSP not grafted (separate later test)
- `status = "okay"` + firmware-name set directly (upstream does it in the board dtsi):
  `qcom/glymur/adsp.mbn`, `qcom/glymur/adsp_dtb.mbn` — both staged (.zst, loader handles it)

Phandles resolved from the live DTB: apps_smmu (iommu@15000000, SID 0x1000), pdc
(int-ctrl@b220000, IRQ 6 edge), smp2p_adsp in/out (0,1,2,3,7 + stop state), rpmhcc
(rsc@18900000/clock-controller, CXO=0), rpmhpd (…/power-controller, LCX=4 LMX=5),
adspslpi+q6-adsp-dtb reserved-mem, aoss_qmp (power-management@c300000), glink-edge on
ipcc (mailbox@3e04000, LPASS=3, GLINK_QMP=0, remote-pid 2, label "lpass").

Verified by re-parse (node + glink-edge + kbd/0x249 intact). Synced via new `a16put.py`
(paramiko SFTP; a16.py -f chokes on big payloads), md5 match 6fedeed5…501. STAGED:
/boot/glymur + 40_custom test30→test31 + update-grub all done. **Reboot pending.**

## 5. How to read the test31 boot
1. `dmesg | grep -iE "remoteproc|adsp"` — want: fw auth OK + "6800000.remoteproc is now up".
   - Auth failure (-EACCES/SCM errors) → try OEM-signed fw: point firmware-name at
     `qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn` (dtb file TBD) in a test31b.
   - Probe defer forever → check which resource is missing (`devices_deferred`).
2. If up: `cat /sys/class/power_supply/qcom-battmgr-bat/{status,capacity,voltage_now}` +
   `upower -d`. Populated → BATTERY DONE (pmic_glink glink channel via new glink-edge).
   Still blank → battery genuinely behind ASUS EC (\_SB.ABD) → EC driver workstream, and
   the ADSP still pays for audio.
3. Watch for regressions: keyboard (3-0015), tpad, ts, wifi, usb — graft touches none.

## 6. Roadmap (Jesse, 2026-07-11): battery + device mgmt → audio → GPU
- Audio after battery: needs gpr/apr + soundcard nodes (thin upstream even in 7.2-rc2) —
  ADSP up is the prerequisite; expect a kernel bump for the full audio stack eventually.
- GPU: NO adreno node even in 7.2-rc2 master — stays deferred; kernel bump alone won't do it.
- Device-mgmt cleanups queued: cfg80211 regdom, ghost-SPMI trim, RTC offset, CDSP graft.
