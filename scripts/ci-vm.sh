#!/bin/bash
# Run repository checks in a disposable overlay of the existing Omarchy CI image.
set -euo pipefail
if [[ $# != 2 ]]; then
  echo 'usage: ci-vm.sh IMAGE_DIRECTORY NEW_OUTPUT_DIRECTORY' >&2
  exit 2
fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=$(realpath "$1")
out=$(realpath -m "$2")
case "$out" in
  "$repo"|"$repo/"*) echo 'keep CI output outside the checkout' >&2; exit 2 ;;
esac
for file in base.qcow2 vmlinuz initrd cmdline; do
  [[ -s $image/$file ]] || { echo "missing image input: $file" >&2; exit 1; }
done
for tool in qemu-system-x86_64 qemu-img ssh ssh-keygen python3 git timeout sha256sum; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo '/dev/kvm is unavailable' >&2; exit 1; }
mkdir -- "$out"
state=$(mktemp -d "${VM_STATE_DIR:-/tmp}/a16-ci.XXXXXX")
pid=
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  if [[ -n $pid ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf -- "$state"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
port=$((20000 + RANDOM % 10000))
ssh_args=(-i "$state/key" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=2 -o LogLevel=ERROR omarchy@127.0.0.1)
# Include working changes, but not ignored build outputs or private captures.
python3 - "$repo" "$out/sources.tar.gz" <<'PY'
from pathlib import Path
import subprocess, sys, tarfile
repo = Path(sys.argv[1])
paths = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--cached',
    '--others', '--exclude-standard', '--', 'LICENSE', 'iso', 'kernel', 'packaging',
    'patches', 'scripts', 'tweaks']).decode().split('\0')
with tarfile.open(sys.argv[2], 'w:gz') as archive:
    for name in sorted(set(paths) - {''}):
        if (repo / name).exists():
            archive.add(repo / name, arcname=name, recursive=False)
PY
sha256sum "$out/sources.tar.gz" "$image/"{base.qcow2,vmlinuz,initrd,cmdline} > "$out/SHA256SUMS"
{ uname -a; qemu-system-x86_64 --version; git -C "$repo" rev-parse HEAD; } > "$out/host.txt"
ssh-keygen -q -t ed25519 -N '' -C a16-ci -f "$state/key"
keys=$(printf 'd /home/omarchy/.ssh 0700 omarchy omarchy -\nf+ /home/omarchy/.ssh/authorized_keys 0600 omarchy omarchy - %s\nf /etc/sudoers.d/99-a16-ci 0440 root root - omarchy ALL=(root) NOPASSWD: /usr/bin/env OMARCHY_ALLOW_DIRECT_PACMAN=1 /usr/bin/pacman -Syu --noconfirm --needed python git make rpm-tools\n' \
  "$(cat "$state/key.pub")" | base64 -w0)
qemu-img create -qf qcow2 -b "$image/base.qcow2" -F qcow2 "$state/run.qcow2"
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp "${SMP:-4}" -m "${MEM:-6G}" \
  -kernel "$image/vmlinuz" -initrd "$image/initrd" \
  -append "$(cat "$image/cmdline") systemd.tty.term.console=dumb" \
  -uuid "$(cat /proc/sys/kernel/random/uuid)" \
  -drive "file=$state/run.qcow2,format=qcow2,if=none,id=d0" -device virtio-blk-pci,drive=d0 \
  -smbios "type=11,value=io.systemd.credential.binary:tmpfiles.extra=$keys" \
  -device virtio-vga -device virtio-rng-pci -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$port-:22" -device virtio-net-pci,netdev=n0 \
  > "$out/qemu.log" 2>&1 &
pid=$!
started=$SECONDS
until timeout 5 ssh "${ssh_args[@]}" true 2>/dev/null; do
  if ! kill -0 "$pid" 2>/dev/null || ((SECONDS - started >= 300)); then
    echo 'VM failed to become reachable; see qemu.log' >&2
    exit 1
  fi
  sleep 1
done
timeout 60 ssh "${ssh_args[@]}" 'mkdir -p ~/src && tar xzf - -C ~/src' < "$out/sources.tar.gz"
set +e
timeout --foreground "${CI_VM_TIMEOUT:-900}" ssh "${ssh_args[@]}" \
  'set -e; uname -a; sudo -n /usr/bin/env OMARCHY_ALLOW_DIRECT_PACMAN=1 /usr/bin/pacman -Syu --noconfirm --needed python git make rpm-tools; pacman -Q python git make rpm-tools; cd ~/src; python3 -B scripts/ci.py' \
  2>&1 | tee "$out/run.log"
status=("${PIPESTATUS[@]}")
rc=${status[0]}
if ((rc == 0)); then rc=${status[1]}; fi
set -e
printf '%s\n' "$rc" > "$out/exit-code"
exit "$rc"
