# G13 — TEST43: Audio bring-up (LPASS macro graft) + safe one-shot boot harness

Date: 2026-07-11. Session goal (Jesse, unattended): "get audio routed, then GPU."
Result: **Audio control plane confirmed fully up; LPASS codec/soundwire subtree is the
remaining work and is a multi-session hardware task. test38 (LPASS-macro graft) attempted
via a bulletproof one-shot boot harness — it booted to userspace then panic-rebooted
(fault not captured, no pstore), auto-recovered to test37. Box left CLEAN + HEALTHY on
test37 DT (now the default). GPU NOT attempted (gated on audio, per plan).**

## 1. Baseline (test37, current boot DTB) — audio is further along than G06 implied
- ADSP up (`remoteproc0: adsp running`). Battery still works (upower 79.6%, "Not charging").
- **GPR control plane LIVE**: `gprsvc:service:2:1` (q6apm) + `2:2` (q6prm) on the adsp_apps
  glink channel. Kernel audio stack loaded + bound: snd_q6apm, q6apm_dai, q6apm_lpass_dais,
  q6prm, q6prm_clocks, snd_q6dsp_common, apr (GPR bus), snd_soc_core.
- **test37 DT already contains** the full `gpr` subtree: `service@1` q6apm (with `dais`
  q6apm-dais + `bedais` q6apm-lpass-dais) and `service@2` q6prm (with `clock-controller`
  q6prm-lpass-clocks, #clock-cells=2). i.e. the FE/DSP path is present.
- Userspace: `pd-mapper` + `tqftpserv` running (systemd, since boot). in-kernel qcom_pd_mapper
  + pdr_interface loaded. `qrtr-ns` binary MISSING but not needed (in-kernel PD mapper covers it).
- **Missing for a real card**: NO top-level `sound` node, NO LPASS macros (va/wsa/rx/tx),
  NO SoundWire controllers, NO codecs (wcd/wsa). `aplay -l` = no soundcards. That subtree
  is what remains.

## 2. Ground truth gathered (all SAFE, no box risk)
- Kernel tree `/home/jcasco/kernel-build/linux` is RECENT: has `glymur.dtsi`, `glymur-crd.dts`,
  and full x1e80100 + x1p42100 board files incl. **`x1e80100-asus-zenbook-a14.dts`** (the A16's
  sibling). Sound machine driver `sound/soc/qcom/x1e80100.c` **already supports
  `qcom,glymur-sndcard`** (glymur data). So glymur audio is partially mainlined.
- **glymur.dtsi has NO LPASS audio hardware** — only the lpass NOCs (interconnect@7400000/
  7420000/7e40000). No macros, no swr, no codecs, no sndcard. The `#sound-dai-cells` in
  glymur.dtsi are just the (disabled) DisplayPort audio DAIs.
- x1e80100 (hamoa.dtsi) LPASS map (reference): wsa2macro@6aa0000, swr3@6ab0000,
  rxmacro@6ac0000, swr1@6ad0000, txmacro@6ae0000, wsamacro@6b00000, swr0@6b10000,
  lpass_audiocc@**6b6c000**, swr2@6d30000, vamacro@6d44000, lpass_tlmm@6e80000. Macros clock
  from `&q6prmcc <ID> 1` (q6prm-lpass-clocks) + `&lpass_vamacro` fsgen. SoundWire resets from
  `&lpass_audiocc LPASS_AUDIO_SWR_*_CGCR`.
- **glymur LPASS clock controllers (from ADSP's own DT, adsp_dtb_*.dtb — glymur-authoritative):**
  `lpass_aon_cc@1f40000`, `lpass_audio_cc@`**`6bc0000`**, `lpass_lpmla_cc@6e40000`
  (all `qcom,*-glymur` compatibles — NO Linux driver for these yet).
  => glymur's lpass_audio_cc (0x6bc0000) is at a DIFFERENT address than x1e80100's
  lpass_audiocc (0x6b6c000). This is the RED FLAG: glymur relocated part of the LPASS map,
  so x1e80100 macro/swr addresses are NOT guaranteed on glymur, and the SoundWire reset
  provider (lpass_audiocc) has no glymur Linux driver.
- ADSP dtb does NOT expose the macro/swr nodes (DSP owns them via the CCs), so glymur's
  macro/swr register addresses are not directly readable from it. Need a glymur BSP dtsi
  or on-hardware discovery.
- LPASS clock IDs (numeric, for editing compiled DTBs): WSA2=68, WSA=66, RX=64, TX=57,
  HW_MACRO_VOTE=102, HW_DCODEC_VOTE=103, COUPLE_NO attribute cell = **1** (0x1, not 0).
- ASUS Vivobook S15 DTS (local, older) has NO audio subtree — not a usable reference. The
  in-tree `x1e80100-asus-zenbook-a14.dts` DOES (wcd9385 + wsa + macros + `qcom,x1e80100-sndcard`,
  model "X1E80100-ASUS-Zenbook-A14") — best structural template when addresses are known.

## 3. test38 experiment — single-variable: "are glymur LPASS macros at x1e80100 addresses?"
- Built **test38 = test37 + only the 5 LPASS macros** (va@6d44000, wsa@6b00000, wsa2@6aa0000,
  rx@6ac0000, tx@6ae0000), each with `clocks=<&q6prmcc ID 1>...<&lpass_vamacro>`. Labeled the
  q6prm clock-controller `q6prmcc:`. NO soundwire, NO codecs, NO sndcard (macros need only the
  already-live q6prm clocks — lowest-risk probe). Built on box: decompile test37.dtb → edit
  dts → `dtc` (rc=0, clean). Artifact: `/boot/glymur/glymur-a16-test38.dtb` (+ NAS + build
  recipe `boot-kit/out/build_test38_macros.txt`).
- **Result: inconclusive-but-negative.** test38 booted to early userspace (ADSP up, GPR svcs,
  wifi, apparmor) then the machine rebooted — panic=10 fired (fault occurred after journald's
  last flush; RTC is clockless so nothing persisted; no pstore/ramoops configured). Zero
  LPASS-macro probe lines were captured. Auto-recovered to test37 via the one-shot fallback.
  Most likely cause: wrong glymur macro reg address and/or a macro clock op stalling
  (consistent with the CC-address relocation above). Cannot refine without the panic log.

## 4. Safe one-shot boot harness (important reusable infra) — and a platform gotcha
- **This platform has NO hardware watchdog** (`watchdog: Hard watchdog permanently disabled;
  NMI not fully supported`). So a hard hang does NOT auto-recover. Plan accordingly.
- grub was `GRUB_DEFAULT=0` = the auto-generated **ACPI** 'Ubuntu' entry (no devicetree line);
  the test37 DT boot only came from a 40_custom entry. An unattended plain reboot would NOT
  reliably return to DT. Both ACPI and DT boots are SSH-reachable (recoverable), but fixed now.
- New harness (in place): `GRUB_DEFAULT=saved`, `GRUB_TIMEOUT=5`. 40_custom rewritten with two
  id'd entries: **`dt-test37`** (WORKING baseline, permanent saved default) and **`dt-test38`**
  (audio macros, `+panic=10 softlockup_panic=1` so any hang auto-panics → reboots → saved
  test37). One-shot via `grub-reboot dt-test38`.
- **GOTCHA that cost two cycles:** the grub 00_header `initrdfail` recovery block runs BEFORE
  the `next_entry` block and overwrites `next_entry` with `prev_entry` when `initrdfail=1`.
  Custom DT entries don't manage initrdfail, so a stale `initrdfail=1` silently defeated the
  one-shot (booted saved default instead). FIX: `grub-editenv /boot/grub/grubenv unset
  initrdfail; unset prev_entry` immediately before `grub-reboot`. After that the one-shot fired.
- Net: the box now DEFAULTS to test37 DT (better than before). Backups: `/etc/default/grub
  .pretest38`, `/etc/grub.d/40_custom.pretest38` (chmod -x it if you re-run update-grub to
  avoid a dup entry). `40_custom.bak.test36` made non-exec.

## 5. Recommended next steps (audio)
1. **Capture the fault** on the next test38 boot with **netconsole** (stream kernel log over
   UDP to the Windows box during boot) OR configure **ramoops/pstore** (reserve a mem region +
   ramoops node) so the panic survives the reboot. Without this, further blind attempts are
   low-yield. (Serial console is not available.)
2. **Get glymur's real LPASS macro/swr addresses**: from a glymur BSP/vendor dtsi if obtainable,
   or from linux-next when glymur audio lands, or by reading the LPASS region on-hardware
   (careful — verify not XPU-protected first). Do NOT assume x1e80100 addresses (CC already moved).
3. A glymur **lpass_audio_cc** Linux clock driver (or a DT reset workaround) is needed before
   SoundWire (swr resets = `&lpass_audiocc *_CGCR`). Macros themselves need only q6prm clocks.
4. Once macros probe cleanly: add swr0/swr1/swr2 + wcd9385 + wsa88xx (model on
   `x1e80100-asus-zenbook-a14.dts`) + a `qcom,glymur-sndcard` node with the va/wcd/wsa
   dai-links. Codec/amp GPIOs + which speakers on which swr bus need on-hardware confirmation.
5. Topology bin: AudioReach needs a glymur topology (check linux-firmware x1e pattern / extract
   from ACDB `firmware-staging/audio/acdb_cal.acdb`).

## 6. GPU — NOT attempted (correct per plan)
Gated on "after all is working" (Jesse) and deferred across all prior notes: no adreno node in
the base DTB or even 7.2-rc2 master; a manual `gpu@3d00000` graft needs ~a dozen
gpucc/rpmhpd/smmu phandles and is panic-prone. Given no hardware watchdog + unattended, a GPU
graft was too risky this session. Revisit after audio and likely after a kernel bump to a base
with upstream X-Elite/glymur adreno nodes.

## 7. Working-set status (unchanged, verified healthy post-experiment)
KEYBOARD OK, touchpad, touchscreen, wifi (.209), USB, fan, NVMe, RTC(clockless), ADSP up,
BATTERY 79.6% — all intact. Audio control plane up; audio card = remaining. Boot DTB default
now = test37 (dt-test37). test38 entry present but not default.
