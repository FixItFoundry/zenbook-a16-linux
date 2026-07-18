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
| ADSP audio DSP (`adsp.mbn` / `qcadsp8480.mbn`) | Audio DSP + LPASS (the AudioReach **topology** is open source — see [`tplg/`](tplg/)) |
| WCN / ath12k firmware | Wi-Fi |
| Various `.mbn` PIL images | remoteproc-loaded subsystems |

Place them under `/lib/firmware/qcom/glymur/` (and the ASUS model subdir
`/lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/` where drivers expect it).

## Exact files the glymur drivers request

Create these under `/lib/firmware/` on the target rootfs (these are the paths the drivers on this
build actually look for):

**Wi‑Fi — ath12k (Qualcomm QCC2072):**
```
/lib/firmware/ath12k/QCC2072/hw1.0/amss.bin
/lib/firmware/ath12k/QCC2072/hw1.0/m3.bin
/lib/firmware/ath12k/QCC2072/hw1.0/board.bin        # (some builds: board-2.bin)
/lib/firmware/ath12k/QCC2072/hw1.0/regdb.bin
/lib/firmware/ath12k/QCC2072/hw1.0/aux_ucode.bin
```
**Audio + co‑processors (ADSP / AudioReach):**
```
/lib/firmware/qcom/glymur/adsp.mbn
/lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin        # AudioReach topology — OPEN SOURCE, build from tplg/
/lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn
/lib/firmware/qcom/glymur/cdsp*.mbn , *.jsn          # as your drivers request
```
Redistributable (usually already present from your distro's `linux-firmware`):
`/lib/firmware/regulatory.db` + `regulatory.db.p7s`.

## Where to get them (pick what applies)
1. **From any Linux you already run on the A16** (including this project's own build) — just copy
   `/lib/firmware/{ath12k,qcom/glymur}` off it. By far the easiest if you have a working install.
2. **From your device's Windows install** — the Qualcomm SoC package under
   `C:\Windows\System32\DriverStore\FileRepository\`. The `.mbn`/board blobs live there; the
   Windows filenames differ from the Linux names above, so match by role/size.
3. **Upstream [`linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware)** carries the
   generic Qualcomm/ath12k bits for some SoCs; the glymur/ASUSTeK ADSP topology is device-specific
   and generally must come from your own device.

After placing the files, `sudo depmod -a` (if needed) and reboot — Wi‑Fi + audio should come up.

> **No prebuilt images are published** — precisely because a *useful* image would have to carry
> this firmware. Build your own with `../iso/` and bake in your own firmware (below).

## The audio topology is OPEN SOURCE (not a blob)

The sound machine driver on this build is `snd-x1e80100`, which requests
`qcom/glymur/GLYMUR-A16-tplg.bin`. That file is an **AudioReach topology**, and AudioReach
topologies are **open source** — they are NOT part of the proprietary firmware.

Upstream [`linux-msm/audioreach-topology`](https://github.com/linux-msm/audioreach-topology)
(**BSD-3-Clause**, © Linaro Ltd) ships an `m4` topology source for the GLYMUR SoC
(`GLYMUR-CRD.m4`) plus X1E80100 laptop variants. It compiles to a `.tplg` with open tools
(`m4` + `alsatplg` from `alsa-topology-utils`) — no proprietary input at any step:

```bash
sudo dnf install -y alsa-topology-utils m4          # Debian/Ubuntu: alsa-utils m4
git clone --depth 1 https://github.com/linux-msm/audioreach-topology.git
cd audioreach-topology
m4 GLYMUR-CRD.m4 > /tmp/GLYMUR-CRD.conf
alsatplg -c /tmp/GLYMUR-CRD.conf -o /tmp/GLYMUR-CRD.tplg
sudo install -Dm644 /tmp/GLYMUR-CRD.tplg /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin
```

A prebuilt `GLYMUR-CRD.tplg` and a build script are in [`tplg/`](tplg/). **Verified on real
hardware (2026-07-18):** the upstream topology instantiates the `GLYMUR-A16` card and brings up
the full 4×WSA8845 speaker control tree — see [`tplg/README.md`](tplg/README.md) for details and
the note on producing a true no-regression drop-in.

The rest of the audio path — the ADSP image (`adsp.mbn` / `qcadsp8480.mbn`) — is the
device-specific Qualcomm blob and must come from **your own device**, not linux-firmware.

## Bake firmware into your own build

Once the files are under `/lib/firmware/...` (paths listed above):

- **On a running install:** drop them into `/lib/firmware`, then `sudo depmod -a` and reboot —
  Wi‑Fi + audio come up.
- **Into an image built with `../iso/build-all-overnight.sh`:** the builder's `addfw()` step
  extracts an overlay tarball `a16-fw.tar.gz` into the rootfs. Build your own overlay:
  ```bash
  # stage your firmware under a matching tree (…/lib/firmware/…), then:
  tar czf a16-fw.tar.gz -C /your/staging \
      lib/firmware/ath12k lib/firmware/qcom/glymur \
      lib/firmware/regulatory.db lib/firmware/regulatory.db.p7s
  # drop a16-fw.tar.gz next to the builder — addfw() picks it up automatically.
  ```
  The resulting image works out-of-the-box **on your own device** — just don't redistribute it,
  since it then contains non-free firmware.
