#!/bin/bash
# Build the A16 candidate with a pinned public AudioReach macro library.
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
upstream=${1:?Usage: build-glymur-a16-tplg.sh AUDIOREACH_CHECKOUT OUTPUT_DIRECTORY}
output=${2:?Supply a separate output directory}
revision=b4c1510fe6686ab8053715a02c34bec875ca5c6c
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
m4 "$source_dir/GLYMUR-A16.m4" > "$output/GLYMUR-A16.conf"
alsatplg -c "$output/GLYMUR-A16.conf" -o "$output/GLYMUR-A16.tplg"
alsatplg -d "$output/GLYMUR-A16.tplg" -o "$output/GLYMUR-A16.decoded.conf"
python3 "$source_dir/verify-glymur-a16-topology.py" "$output/GLYMUR-A16.decoded.conf"
{
  printf 'audioreach_commit=%s\n' "$revision"
  alsatplg --version
  sha256sum "$source_dir/GLYMUR-A16.m4" "$output/GLYMUR-A16.tplg"
} > "$output/GLYMUR-A16.build.txt"
