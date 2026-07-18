# Audio topology (.tplg) — built from PUBLIC open source

Unlike the ADSP and Wi‑Fi firmware (which are proprietary and **not** in this repo), the
AudioReach **audio topology is open source** and reproducible with open tools. There is
nothing to extract from a blob here.

## Source

[`linux-msm/audioreach-topology`](https://github.com/linux-msm/audioreach-topology) —
**BSD-3-Clause**, © Linaro Ltd. It ships an `m4` topology source for the GLYMUR SoC
(`GLYMUR-CRD.m4`) plus X1E80100 laptop variants. The A16 is an X1E80100-class machine, and
the AudioReach topology is largely SoC-agnostic (it describes the DSP graph, not register
addresses), so these compile to a topology the A16 accepts.

## Contents of this directory

| File | What it is |
|---|---|
| `GLYMUR-CRD.m4` | The upstream BSD-3 topology source for the GLYMUR SoC (vendored for reference; © Linaro) |
| `GLYMUR-CRD.tplg` | Prebuilt topology compiled from `GLYMUR-CRD.m4` with `alsatplg` (BSD-3, redistributable) |
| `build-glymur-tplg.sh` | Recipe that clones upstream and builds `GLYMUR-CRD.tplg` + `X1E80100-CRD.tplg` |
| `LICENSE.BSD-3-Clause` | The upstream license (retained for attribution) |

## Build it yourself

```bash
sudo dnf install -y alsa-topology-utils m4     # Fedora  (Debian/Ubuntu: alsa-utils m4)
./build-glymur-tplg.sh
```

`alsatplg` (from `alsa-topology-utils`) + `m4` is the whole toolchain — no cmake/g++ needed.

## Install on the A16

The `snd-x1e80100` machine driver requests `qcom/glymur/GLYMUR-A16-tplg.bin`:

```bash
sudo install -Dm644 GLYMUR-CRD.tplg /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin
sudo reboot   # or hot-rebind the driver
```

## Verified on hardware (2026-07-18)

The upstream `X1E80100-CRD.tplg` was swapped onto a real A16 and **instantiated the
`GLYMUR-A16` card** — MultiMedia1/2/5/6 playback, MultiMedia3/4 capture, the full 4×WSA8845
speaker control tree (WSA_RX0/RX1, WSA2, compander, softclip, VI‑sense) and the headset‑jack
input. Confirms the audio topology is open-source-reproducible on this device.

### Note on a true drop-in

This project's daily-driver install uses a hand-tuned topology whose UCM profile and
`glymur-audio-route.sh` are matched to its exact PCM layout (MM1/2 playback + MM3/4 capture).
The upstream files are **not byte-identical drop-ins** — `GLYMUR-CRD` exposes a
playback + capture pair, `X1E80100-CRD` exposes MM1–6 — so swapping one in also means
re-tuning UCM. For a no-regression drop-in, author a `GLYMUR-A16.m4` in the upstream `m4`
framework reproducing MM1/2‑playback + MM3/4‑capture + `WSA_CODEC_DMA_RX_0` (up to 4ch) +
`VA_CODEC_DMA_TX_0`, then compile it the same way.
