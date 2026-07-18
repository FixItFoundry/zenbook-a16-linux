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
/lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin        # AudioReach topology
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

## How the audio topology was derived (from a PUBLIC source)

glymur (sm8750) has no upstream AudioReach topology, and the sound machine driver on this build
is `snd-x1e80100`, which requests `qcom/glymur/GLYMUR-A16-tplg.bin`. We satisfied that with the
**x1e80100 "Romulus" topology**, which *is* in public `linux-firmware`
(`qcom/x1e80100/X1E80100-Romulus-tplg.bin`) — it drives the same WSA8845 4.0 speaker layout well
enough for the A16. So the topology is derivable entirely from public firmware:

```bash
# from a linux-firmware checkout (or your distro's own /lib/firmware):
sudo install -Dm644 qcom/x1e80100/X1E80100-Romulus-tplg.bin \
    /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin
```
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
