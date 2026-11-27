#!/bin/bash
# Build the upstream A16 topology from a pinned linux-msm/audioreach-topology checkout.
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
upstream=${1:?Usage: build-glymur-a16-tplg.sh AUDIOREACH_CHECKOUT OUTPUT_DIRECTORY}
output=${2:?Supply a separate output directory}
revision=31eaaac08da364cb346681b132129028b9c583f4
m4_source=glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA.m4
[[ $(git -C "$upstream" rev-parse HEAD) == "$revision" ]] || {
  echo "AudioReach source must be pinned to $revision" >&2
  exit 1
}
[[ -z $(git -C "$upstream" status --porcelain --untracked-files=all) ]] || {
  echo "AudioReach checkout must be clean" >&2
  exit 1
}
mkdir -p "$output"
output=$(cd "$output" && pwd)
cd "$upstream"
m4 -I . "$m4_source" > "$output/GLYMUR-A16.conf"
alsatplg -c "$output/GLYMUR-A16.conf" -o "$output/GLYMUR-A16.tplg"
alsatplg -d "$output/GLYMUR-A16.tplg" -o "$output/GLYMUR-A16.decoded.conf"
python3 "$source_dir/verify-glymur-a16-topology.py" "$output/GLYMUR-A16.decoded.conf"
{
  printf 'audioreach_commit=%s\n' "$revision"
  alsatplg --version
  sha256sum "$m4_source" "$output/GLYMUR-A16.tplg"
} > "$output/GLYMUR-A16.build.txt"
