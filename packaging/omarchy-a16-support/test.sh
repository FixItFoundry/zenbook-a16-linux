#!/bin/bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

source "$here/initcpio-hook"
sleep() { :; }
for spec in '0 adsp running' '1 cdsp running' '2 soccp attached'; do
  read -r number name state <<< "$spec"
  mkdir -p "$scratch/remote/remoteproc$number"
  printf '%s\n' "$name" > "$scratch/remote/remoteproc$number/name"
  printf '%s\n' "$state" > "$scratch/remote/remoteproc$number/state"
done
a16_wait_remoteprocs "$scratch/remote" 1 || fail 'ready processors rejected'
echo offline > "$scratch/remote/remoteproc1/state"
if a16_wait_remoteprocs "$scratch/remote" 1; then fail 'offline CDSP accepted'; fi
[[ $(cat "$scratch/remote/remoteproc1/state") == offline ]] || fail 'hook attempted a hand start'
echo running > "$scratch/remote/remoteproc1/state"
echo crashed > "$scratch/remote/remoteproc2/state"
if a16_wait_remoteprocs "$scratch/remote" 1; then fail 'crashed SoCCP accepted'; fi
echo attached > "$scratch/remote/remoteproc2/state"

# Execute the real hook against a temporary sysfs/proc fixture.
sed -e "s|/sys/firmware/devicetree/base/compatible|$scratch/compatible|g" \
  -e "s|/sys/class/remoteproc|$scratch/remote|g" \
  -e "s|/proc/mounts|$scratch/mounts|g" "$here/initcpio-hook" > "$scratch/hook"
source "$scratch/hook"
msg() { :; }
getarg() { printf '%s' "${dsp_mode:-}"; }
modprobe() { echo "$*" >> "$scratch/modprobes"; return "${module_status:-0}"; }
udevadm() { echo "$*" > "$scratch/settle"; }
a16_emergency() { echo "$*" > "$scratch/emergency"; }
printf 'asus,zenbook-a16-ux3607oa\0qcom,glymur\0' > "$scratch/compatible"
: > "$scratch/mounts"
dsp_mode=off
run_hook
[[ ! -e $scratch/modprobes ]] || fail 'rescue boot loaded DSPs'
dsp_mode=
printf '/dev/sda2 /sysroot btrfs rw 0 0\n' > "$scratch/mounts"
if run_hook; then fail 'late startup accepted'; fi
[[ -s $scratch/emergency && ! -e $scratch/modprobes ]] || fail 'late startup reached module load'
rm "$scratch/emergency"
: > "$scratch/mounts"
module_status=1
if run_hook; then fail 'module failure accepted'; fi
[[ -s $scratch/emergency && ! -e $scratch/settle ]] || fail 'module failure did not stop boot'
rm "$scratch/emergency" "$scratch/modprobes"
module_status=0
run_hook
[[ $(wc -l < "$scratch/modprobes") == 2 && -s $scratch/settle ]] || fail 'ready boot did not settle devices'
[[ ! -e $scratch/emergency ]] || fail 'ready boot entered emergency'
rm "$scratch/modprobes" "$scratch/settle"

# Exercise the runtime with only commands added by base and our build hook.
mkdir -p "$scratch/initramfs-bin" "$scratch/firmware/qcom/glymur/ASUSTeK/UX3607OA"
ln -s "$(command -v grep)" "$scratch/initramfs-bin/grep"
for name in qcadsp8480.mbn adsp_dtbs.elf qccdsp8480.mbn cdsp_dtbs.elf; do
  echo fixture > "$scratch/firmware/qcom/glymur/ASUSTeK/UX3607OA/$name"
done
echo fixture > "$scratch/firmware/qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin"
sed "s|/usr/lib/firmware|$scratch/firmware|g" "$here/initcpio-install" > "$scratch/install"
source "$scratch/install"
add_file() { :; }
add_module() { :; }
add_runscript() { :; }
add_binary() { ln -s "$(command -v "$1")" "$scratch/initramfs-bin/$1"; }
KERNELVERSION=7.2.10-omarchy-a16-1 build
PATH="$scratch/initramfs-bin" run_hook
[[ -s $scratch/modprobes && -s $scratch/settle ]] || fail 'minimal initramfs silently skipped A16 DSP startup'
rm "$scratch/modprobes" "$scratch/settle"

printf 'asus,ux3607oa-other\0qcom,glymur\0' > "$scratch/compatible"
run_hook
[[ ! -e $scratch/modprobes ]] || fail 'partial model name accepted'

(
  HOOKS=(base udev autodetect modconf block keyboard encrypt filesystems)
  KERNELVERSION=7.2.10-omarchy-a16-1
  source "$here/mkinitcpio.conf"
  [[ ${HOOKS[*]} == 'base udev omarchy-a16-dsp autodetect modconf block keyboard encrypt filesystems' ]] || fail 'wrong hook ordering'
  source "$here/mkinitcpio.conf"
  [[ ${HOOKS[*]} == 'base udev omarchy-a16-dsp autodetect modconf block keyboard encrypt filesystems' ]] || fail 'duplicate hook'
  HOOKS=(base systemd block filesystems)
  if source "$here/mkinitcpio.conf"; then fail 'unsupported systemd profile accepted'; fi
  KERNELVERSION=7.2.10-stock
  source "$here/mkinitcpio.conf"
  [[ ${HOOKS[*]} == 'base systemd block filesystems' ]] || fail 'unrelated kernel modified'
)
echo 'PASS: early DSP readiness, failure, rescue, model gating and initramfs ordering'
