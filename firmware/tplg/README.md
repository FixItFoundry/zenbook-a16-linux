# Audio topology (`.tplg`) — built from upstream AudioReach

The ASUS Zenbook A16 (`UX3607OA`) AudioReach topology is built directly from
upstream [`linux-msm/audioreach-topology`](https://github.com/linux-msm/audioreach-topology)
(`glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA.m4`, BSD-3-Clause).

## Contents of this directory

| File | What it is |
|---|---|
| `build-glymur-a16-tplg.sh` | Builds and verifies `GLYMUR-A16.tplg` from the pinned upstream `glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA.m4` (`31eaaac0`) |
| `verify-glymur-a16-topology.py` | Verifies the decoded PCM IDs, channel capabilities, and speaker/DMIC routes expected by our UCM |
| `GLYMUR-CRD.m4` / `GLYMUR-CRD.tplg` / `build-glymur-tplg.sh` | Historical reference-board files kept from bringup (not a drop-in for the A16 UCM) |
| `LICENSE.BSD-3-Clause` | Upstream BSD-3-Clause license |

## Build and install

`alsatplg` (`alsa-topology-utils` on Fedora, `alsa-utils` on Debian/Ubuntu) and
`m4` are the only build dependencies:

```bash
git clone https://github.com/linux-msm/audioreach-topology.git /tmp/audioreach-topology
git -C /tmp/audioreach-topology checkout 31eaaac08da364cb346681b132129028b9c583f4
./firmware/tplg/build-glymur-a16-tplg.sh /tmp/audioreach-topology /tmp/a16-tplg

sudo install -Dm644 /tmp/a16-tplg/GLYMUR-A16.tplg \
  /lib/firmware/qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin
```

## UCM pairing (`MM1` speakers, `MM2` DMICs)

Upstream `GLYMUR-ASUS-Zenbook-A16-UX3607OA.m4` maps:

- `hw:,0` (`MultiMedia1`, 4 ch) → `WSA_CODEC_DMA_RX_0` (4× WSA8845 speakers)
- `hw:,1` (`MultiMedia2`, 1–2 ch) ← `VA_CODEC_DMA_TX_0` (internal DMICs)
- `hw:,2` / `hw:,3` / `hw:,6` (`MultiMedia3`/`4`/`7`) → `DISPLAY_PORT_RX_0/1/2`
- `hw:,4` / `hw:,5` (`MultiMedia5`/`6`) ↔ WCD9378 headset playback/capture

Our UCM (`tweaks/usr/share/alsa/ucm2/Qualcomm/glymur/HiFi.conf`, installed for
Fedora and Ubuntu by `packaging/zenbook-a16-hooks/install-hooks.sh` +
`activate-hardware.sh`) matches this `MM1`/`MM2` layout, as does upstream
`alsa-ucm-conf`. If upgrading from an older `MM2`/`MM4` topology on disk,
replace the installed `-tplg.bin` at the same time so topology and UCM match.
