#!/bin/bash
# Build the GLYMUR AudioReach topology (.tplg) from PUBLIC BSD-3-Clause source.
#
# Source: https://github.com/linux-msm/audioreach-topology  (Linaro Ltd, BSD-3-Clause)
# This is NOT proprietary firmware — it compiles from open source with open tools.
# Proven to instantiate the GLYMUR-A16 sound card on real hardware (2026-07-18).
#
# Requires: alsa-topology-utils (provides /usr/bin/alsatplg) + m4
#   Fedora:  sudo dnf install -y alsa-topology-utils m4
#   Debian/Ubuntu: sudo apt install -y alsa-utils m4   # alsatplg ships in alsa-utils there
set -e

WORK="${1:-$PWD/audioreach-topology}"
OUT="${2:-$PWD}"

if ! command -v alsatplg >/dev/null; then
  echo "ERROR: alsatplg not found. Install alsa-topology-utils (Fedora) or alsa-utils (Debian)." >&2
  exit 1
fi

if [ ! -d "$WORK" ]; then
  git clone --depth 1 https://github.com/linux-msm/audioreach-topology.git "$WORK"
fi
cd "$WORK"

# GLYMUR-CRD = the GLYMUR SoC reference topology.
# X1E80100-CRD = superset (MM1-6) that also instantiates the A16 card and exposes the
#                full 4x WSA8845 speaker control tree; useful as a starting point.
for board in GLYMUR-CRD X1E80100-CRD; do
  m4 "$board.m4" > "/tmp/$board.conf"
  alsatplg -c "/tmp/$board.conf" -o "$OUT/$board.tplg"
  echo "built: $OUT/$board.tplg ($(stat -c%s "$OUT/$board.tplg") bytes)"
done

echo
echo "To use on the A16, the snd-x1e80100 machine driver requests"
echo "  /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin"
echo "Install whichever topology you built under that name, e.g.:"
echo "  sudo install -Dm644 $OUT/GLYMUR-CRD.tplg /lib/firmware/qcom/glymur/GLYMUR-A16-tplg.bin"
echo "then reboot (or rebind: echo sound | sudo tee /sys/bus/platform/drivers/snd-x1e80100/{unbind,bind})."
