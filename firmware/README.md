# Firmware — what's needed and why it's NOT in this repo

The glymur platform needs proprietary Qualcomm/ASUS firmware at runtime. **None of it is
redistributed here** — it is copyrighted by Qualcomm/ASUS and cannot be legally re-hosted.
This repo only contains *findings derived from* those blobs (addresses, StreamIDs, register
maps) for interoperability research.

## Where the firmware comes from

The firmware ships with the device's Windows installation. On a stock Windows-on-ARM Zenbook
A16 it lives under the Windows driver store (`C:\Windows\System32\DriverStore\FileRepository\`)
and the Qualcomm SoC package. Extract it from **your own device**.

## What the platform needs

| Blob | Purpose |
|---|---|
| `qcvss8480.mbn` | GPU / GMU (zap shader) — needed for any future GPU bring-up |
| `qcdxkmsuc8480.mbn` | GPU microcode |
| `qcav1e8480.mbn` | AV1 codec |
| ADSP / audio (AudioReach topology) | Audio DSP + LPASS |
| WCN / ath12k firmware | Wi-Fi |
| Various `.mbn` PIL images | remoteproc-loaded subsystems |

Place them under `/lib/firmware/qcom/glymur/` (and the ASUS model subdir
`/lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/` where drivers expect it).

## Extraction

`../boot-kit/scripts/collect-acpi-hw.sh` and the notes in `../docs/` describe how the ACPI
tables and driver identities were dumped. A PowerShell helper to pull firmware from the
Windows driver store (`extract_firmware.ps1`) exists in the original project tree; it is a
convenience for **your own** extraction, not a redistribution mechanism.

> If you're packaging ISOs (see `../iso/`), do **not** bundle these blobs into a public image.
> Document that the user must supply firmware from their own device.
