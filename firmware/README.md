# Firmware — almost all of it is now upstream and redistributable

⚠️ **This file previously said "none of it is redistributable — extract it from your own
device." That was true when written and is now WRONG.** Upstream `linux-firmware` has absorbed
glymur. Verified against tag **20260622** on 2026-08-02.

**Consequence: bootable images for this laptop CAN be published.** The long-standing position
that no image could ship because firmware was proprietary no longer holds.

---

## What is upstream and redistributable

All of the below are in [`kernel-firmware/linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware)
at tag `20260622`.

### Wi-Fi — `ath12k/QCC2072/hw1.0/`

```
Notice.txt   board-2.bin   firmware-2.bin
```

`WHENCE` says: **`Licence: Redistributable. See LICENSE.QualcommAtheros_ath10k`**

★ Version `WLAN.COL.1.0.c2-00074-QCACOLSWPL_V1_TO_SILICONZ-1` — **byte-for-byte the build this
hardware reports at probe.** Upstream ships exactly what the machine runs.

⚠️ Note the *modern bundled* layout: `firmware-2.bin` replaces the older loose
`amss.bin` / `m3.bin` / `aux_ucode.bin` set this document used to list. Do not go hunting for
files that current ath12k no longer asks for.

### Bluetooth — `qca/`

```
ornbtfw11.tlv   ornnv11.bin
```

Listed in `WHENCE` under *"btqca — Qualcomm Atheros Bluetooth support for QCA_QCC2072 chip"*.

### DSPs, GPU and audio — `qcom/glymur/`

```
adsp.mbn      adsp_dtb.mbn      adspr.jsn  adsps.jsn  adspua.jsn
cdsp.mbn      cdsp_dtb.mbn      cdspr.jsn
gen80100_zap.mbn                            <- the GPU zap shader
GLYMUR-CRD-tplg.bin                         <- audio topology, reference design
```

★ **`gen80100_zap.mbn` closes a gap `docs/hardware.md` recorded as open.** The Adreno driver
falls back to `SECVID_TRUST_CNTL` because the file is not installed locally, not because it does
not exist.

---

## What is genuinely NOT upstream

Two things, and neither is a proprietary blob that must be extracted.

### 1. The A16 audio topology

Upstream ships `GLYMUR-CRD-tplg.bin` — Qualcomm's **CRD reference design**, not this laptop.

The AudioReach driver derives the filename from the `model` property of the `sound` node:

```dts
sound {
    model = "GLYMUR-ASUS-Zenbook-A16-UX3607OA";  ->  GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin
};
```

So the "missing firmware" is a file named after **our own model string**. It is **open source**
and built from [`tplg/`](tplg/) in this repo. It is not a redistribution problem.

⚠️ Worth testing: the in-tree upstream A16 DT (`x2e94100-asus-zenbook-a16.dts`) has **no sound
node at all** — upstream has not done audio on this laptop. Whether `model = "GLYMUR-CRD"` would
load the reference topology usefully on A16 hardware (4× WSA8845 in a 4.0 layout) is untested,
and is the cheapest experiment available here.

### 2. `soccp.mbn`

Upstream has `soccp.mbn` for **kaanapali** but not for **glymur**. Probably irrelevant — the
SOCCP on this laptop is **UEFI-loaded and already running**, which is exactly why the device tree
deliberately omits `&remoteproc_soccp`.

---

## Getting the firmware

**Preferred — upstream, redistributable:**

```sh
git clone --depth 1 --branch 20260622 \
  https://gitlab.com/kernel-firmware/linux-firmware.git
sudo cp -a linux-firmware/ath12k/QCC2072 /lib/firmware/ath12k/
sudo cp -a linux-firmware/qcom/glymur    /lib/firmware/qcom/
sudo cp -a linux-firmware/qca/orn*       /lib/firmware/qca/
```

Or install your distro's `linux-firmware` once it reaches a tag ≥ 20260622.
⚠️ Fedora 44 ships `ath12k/QCN9274` and `WCN7850` but **not** `QCC2072` yet, which is why the
live images in [`../iso/`](../iso/) inject it explicitly.

**Fallback — from your own device:** [`../iso/glymur-fetch-firmware.sh`](../iso/glymur-fetch-firmware.sh)
still works and remains the answer for anything upstream lacks.

---

## Why this matters

Published live images for this laptop can now carry working Wi-Fi, Bluetooth, audio DSP and the
GPU zap shader with no proprietary redistribution. The only piece an image cannot ship is the
A16 audio topology — and that is ours to build and license as we choose.
