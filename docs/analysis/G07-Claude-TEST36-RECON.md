# G07 — Test36 recon: the ADSP's own device tree decoded (audio + battery coordinates)

## 1. The big unlock: adsp_dtbs.elf contains SIX parseable DTBs
`firmware-staging/adsp_dtbs.elf` payload = 6 FDT blobs (extracted: `adsp_dtb_0..5.dtb` in
firmware-staging). dtb0-2 = qcom,glymur (main + audio_process-PD + qsh_process-PD overlays);
dtb3-5 = qcom,mahua (other SoC variant, ignore). dtb0 = the ADSP's full hardware map. Parse
with python fdt (Windows-side, no box needed).

## 2. BATTERY: island bus coordinates (EC@0x08 lives here)
From dtb0 `/soc`:
- **SSC_QUP_0 @ 0x7900000** (size 0x100000), qup_id 16, core 150MHz,
  `se_wrapper_base_offset 0x80000` → **SE_N base = 0x7980000 + N*0x4000** (SE_0..SE_8, SE_10).
  se_flags 0x4000020 on most SEs (i3c/ibi-capable), 0x20 on SE_4/7/10.
- **SSC pinctrl (island TLMM) @ 0x75C0000** — pin groups `ssc_qupv3_se0_*`, ssc_gpio_6..35.
- slimbus pinctrl @ 0x7760000 exists too (unused by A16? codec Q below).
- OPEN QUESTIONS for the graft: (a) which SE hosts the EC (probe 0x08 across SEs once one
  works), (b) do SSC SE IRQs route to the APSS GIC (if not: polling or ADSP-mediated only),
  (c) SE clock: island clocks are lpass-cc-fed; ADSP RUNNING keeps them on + `clk_ignore_unused`
  on cmdline — a graft may work leaning on the ADSP keeping the island alive. RISK: touching
  island resources could disturb the working ADSP — single-variable test with easy rollback.
- Driver once bus works: standard `qcom,geni-i2c` node + EC driver from the DSDT register map
  (07 changelog: BIXD@0x10110 _BIX 68B, BSTD@0x101A8, BMND/BSND strings; template
  acer-aspire1-ec).

## 3. AUDIO: architecture verdict — Windows does DSP-owned codec via ACDB
- DSDT has NO codec/soundwire/WCD/WSA devices. Windows audio = `AUDC` (ACPI0018, the
  "audio compositor" ACD device, 3 endpoints EP00-02) + everything else inside the ADSP,
  configured by **`acdb_cal.acdb` (524KB, FileRepository pkg `qcacsp_crd8480`)**. The codec/amp
  attach (soundwire vs slimbus, which amps) is encoded in the ACDB, not in any DT we have.
- Upstream Linux AudioReach expects APSS-side lpass soundwire + wcd/wsa codec drivers —
  glymur has NONE of those nodes upstream (even 7.2-rc2). Two candidate paths for Test36+:
  **(A) ACDB-led**: stage acdb_cal.acdb where tqftpserv serves it (check tqftpserv's search
  paths; X1E convention = /lib/firmware/qcom/<soc>/<oem>/...), then build a minimal
  AudioReach machine driver card using q6apm-lpass-dais codec-DMA backends and see if the DSP
  self-configures the codec path (mirrors Windows model; unknown if Linux graph setup suffices).
  **(B) X1E-style APSS codec stack**: needs glymur lpass swr/macro base addresses — NOT in
  dtb0's visible nodes (lpass audio cc candidates present: clock-controller@6bc0000/7a00000/
  7b00000/6e40000 in dtb0 /soc) — plus wcd/wsa drivers and pinctrl; big arc, may want the
  7.2-rc kernel bump first for lpass compats.
- Recommended order: try (A) first — cheap, no DT hardware invention; instrument with
  q6apm graph open (aplay on a codec-dma PCM once a card exists).

## 4. Concrete Test36 build plan (fresh session)
1. Check tqftpserv serve-path + stage acdb_cal.acdb (+ inspect ACDB header for codec names —
   strings in the .acdb may literally name WCD/WSA parts).
2. Minimal sound{} machine node (qcom audioreach card, e.g. sc8280xp/x1e machine compat with
   only codec-dma dai-links) → does a card register? → aplay probe.
3. Parallel: island i2c SE graft experiment for EC (0x7980000+N*0x4000, ssc pinctrl,
   IRQ question) — SEPARATE test DTB from audio (single-variable).
4. Keep test35 as fallback DTB.

## 5. Session context (test30→35 all in one day, 2026-07-11)
Keyboard → RTC → ADSP → audio control plane → recon complete. Tooling: a16.py/a16put.py via
shell:cmd; FileRepository.zip = canonical blob source; adsp_dtb_*.dtb extracted for study.
