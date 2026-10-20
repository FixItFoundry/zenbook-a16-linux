# Firmware for the current A16 baseline

[`iso/glymur-fetch-firmware.sh`](../iso/glymur-fetch-firmware.sh) is the list of
known required firmware requests. It accepts uncompressed, `.xz` or `.zst`
files and preserves Linux firmware paths. Passing this presence check does not
establish successful firmware loading or hardware acceptance.

| Component | Required location |
|---|---|
| Wi-Fi | `ath12k/QCC2072/hw1.0/{board-2.bin,firmware-2.bin}` |
| Bluetooth rampatch | `qca/clnbtfw10.tlv` |
| GPU | `qcom/{gen80100_sqe.fw,gen80100_gmu.bin}` |
| ASUS ADSP | `qcom/glymur/ASUSTeK/UX3607OA/{qcadsp8480.mbn,adsp_dtbs.elf}` |
| ASUS CDSP | `qcom/glymur/ASUSTeK/UX3607OA/{qccdsp8480.mbn,cdsp_dtbs.elf}` |
| Audio topology | `qcom/glymur/ASUSTeK/UX3607OA-tplg.bin` or `qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin` |

The current boot reports missing `clnbtfw10.tlv`. Older `hmt*` or `orn*` files
are not substitutes. The board-specific Bluetooth NVM request and pairing still
need confirmation after the rampatch loads; copying an existing `qca` directory
preserves those filenames without guessing a replacement.

Use distro/upstream `linux-firmware` where it supplies the exact files. Obtain
ASUS board-signed DSP firmware from a verified matching source, including the
[ASUS UX3607OA package](https://www.asus.com/us/supportonly/ux3607oa/helpdesk_download/)
where required. Generic reference-board DSP files are not interchangeable with
ASUS-signed files. Check the license attached to each redistributed file;
upstream availability of some firmware does not establish redistribution rights
for every file in an OEM package.

Copy an existing Linux firmware tree into a staging directory, or check one:

```sh
DEST=/path/to/stage/firmware iso/glymur-fetch-firmware.sh --from-linux /path/to/source
DEST=/path/to/stage/firmware iso/glymur-fetch-firmware.sh --check
```

The check intentionally fails until every known required file is present. It
never renames Windows driver binaries to guessed Linux names. The A16 topology
candidate is built by [`tplg/build-glymur-a16-tplg.sh`](tplg/build-glymur-a16-tplg.sh)
from pinned sources and verified before installation under the model-specific
name. A generic CRD topology is not a tested drop-in replacement.

No standalone Glymur `soccp.mbn` is required by this manifest: the current
kernel attaches to the firmware-loaded SoCCP. See
[`docs/current-build.md`](../docs/current-build.md) for accepted behavior and limits.
