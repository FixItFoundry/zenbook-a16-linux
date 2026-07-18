# G06 — ★ MILESTONE 5: ADSP UP (test34) + definitive battery verdict + audio runway

## 1. test34 result: "remote processor adsp is now up"
`Booting fw image qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn, size 19851224` → up in <1s,
"Handover signaled" (proxy resources released cleanly), rproc state `running`, smp2p-adsp
IRQ live (6+). The missing artifact was **`adsp_dtbs.elf`** from Jesse's FileRepository.zip
(package `qcsubsys_ext_adsp8480`, next to the main image). Windows DSP-dtb naming: `*_dtbs.elf`.
The github-downloaded generic pair was test-key-signed → TZ -22. Full chain that got here:
IRQ 0x249 (kbd) → remoteproc graft (sm8550 fallback compat) → interconnects vote (icc
sync_state clamp) → OEM dual-firmware. Every piece was necessary.

## 2. Battery: VERDICT — not the ADSP's job on this laptop
ADSP announced channels: IPCRTR, adsp_apps, adsp_apps2, bt_cp_ctrl, fastrpcglink-apps-dsp,
glink_ssr, sleepmonglink-apps-adsp, rpmsg_ctrl. **No PMIC_GLINK channel** → ASUS's ADSP fw
hosts no battery/charger service → qcom-battmgr will stay -EAGAIN forever (its 4 supplies can
be dropped from DT later to silence upowerd). This CONFIRMS the DSDT reframe: battery gauge
is behind the ASUS EC (`\_SB.ABD`, BIXD/BPCD/BPSD op-regions). **Battery workstream = ASUS EC
driver** (kernel driver speaking to the EC over its bus, exposing power_supply). Same EC
gates the keyboard-backlight/fan policy — one driver, several wins. DSDT is the spec.

## 3. Audio: the runway is now open
`adsp_apps`/`adsp_apps2` = AudioReach **GPR** channels — the audio service IS running on the
ADSP. What Linux still needs:
1. DT: `gpr` node under the existing glink-edge (qcom,glink-channels = "adsp_apps"),
   q6apm/q6prm subnodes, lpass dais, soundcard node (upstream 7.2-rc2 glymur has thin audio —
   may need sm8550/x1e soundcard patterns + a kernel bump eventually).
2. Userspace: **pd-mapper + tqftpserv** (NOT installed; only libqrtr-glib present). The
   `adspr.jsn`/`adspua.jsn` files staged next to the fw are exactly pd-mapper's service-registry
   inputs. Audio user-PD won't start without them.
3. Topology/modules: FileRepository.zip `qcsubsys_ext_adsp8480/ADSP/*.so` (fluence, aptX, LC3
   etc.) — Windows-side AudioReach modules; Linux needs its own audioreach topology bin
   (check linux-firmware x1e pattern when glymur lands, or extract from ACDB in the zip).

## 4. Housekeeping still queued
CIFS boot-mount race (flaky — won some boots, lost this one): `x-systemd.automount` in fstab.
ath12k regdom (`options cfg80211 ieee80211_regdom=US`). Ghost-SPMI trim (sids 0x7/0xb WARNs).
RTC offset (1970). Drop battmgr supplies from pmic-glink node (cosmetic). CDSP graft when
wanted: `qccdsp8480.mbn` + `cdsp_dtbs.elf` both in the zip — same recipe as ADSP (compat
`qcom,sm8550-cdsp-pas` fallback, cx pd, cdsp carveouts).

## 5. Working-set status (post-test34)
KEYBOARD ✓ touchpad ✓ touchscreen+stylus ✓ wifi ✓ USB ✓ fan ✓ NVMe ✓ RTC ✓ **ADSP ✓** —
battery (EC driver), audio (GPR stack), GPU (needs upstream adreno node, still absent in
7.2-rc2), camera/video (fw staged in zip) remaining.
