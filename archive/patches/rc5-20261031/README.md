# RC / Upstream Development Patch Stack (`patches/rc`)

Layered patch stack for the `rc` development track ([`kernel/rc`](../../kernel/rc/README.md)), used to stage and test LKML series, Qualcomm `qcom-next` / `laptops-kernel` enablement, and local contributor patches before promoting them to [`patches/stable`](../stable/README.md) or submitting upstream.

| Layer | Directory | Patches | Resulting Source Tree | Purpose |
|---|---|---:|---|---|
| 1. Base A16 stack | [`base/`](base/README.md) | 64 | `732b59a49185ef2c3c1cb462db166137dcf757a4` | Core UX3607OA board DT, eDP v8, HID keyboard/backlight, SoundWire, Wi-Fi, EC fan/thermal, and stability fixes on `v7.3-rc5` (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`) |
| 2. Qualcomm bridge | [`qcom-glymur-bridge/`](qcom-glymur-bridge/README.md) | 40 | `a17d7e30ee161a146706c0752c11a389454a9062` | Bridged `qcom-next` and `qcom-topics` Glymur enablement (dispcc, adreno Gen8, UCSI, fTPM, IRIS, cpufreq, TCSR) |
| 3. Camera & microphone | [`camera-microphone/`](camera-microphone/README.md) | 10 | `5cc084c973c02c41eaa968599b0e687a93222d46` | CCI, PM8010, HM1092, nonsecure CSID0/VFE0 CAMSS path, AudioReach channel-map clearing, and DMIC01 4 mA/slew-1 pin settings |
| 4. USB3 PHY calibration | [`glymur-usb3/`](glymur-usb3/README.md) | 1 | `b3ae7b3a8a4c74930dfeb905c6471c16da0f69f0` | Konrad Dybcio's Glymur USB3 QMP combo PHY SERDES/TX/RX/PCS table update and `tracks.json` CI contract |

## Replay Without Modifying a Checkout

```sh
# Replay layers 1 + 2 (104 patches):
python3 kernel/rc/replay.py /path/to/linux.git

# Replay layers 1 + 2 + 3 (114 patches):
python3 patches/rc/camera-microphone/replay.py /path/to/linux.git

# Replay all 4 layers + reverse check (115 patches):
python3 scripts/ci.py --replay-only --track rc --linux-git /path/to/linux.git
```
