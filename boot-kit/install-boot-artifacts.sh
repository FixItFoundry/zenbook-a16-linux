#!/usr/bin/env bash
# Mirror a kernel's boot artifacts to EVERY /boot that GRUB might read, then
# point saved_entry at a menu entry.
#
# WHY THIS EXISTS
#   The root filesystem is btrfs with five subvolumes, and the TOP LEVEL (ID 5)
#   carries its own /boot that mirrors the running root. GRUB reads the top-level
#   copy, not the running root:
#
#     EFI/fedora/grub.cfg -> search --fs-uuid <fs-uuid>   (a FILESYSTEM uuid,
#                             with no subvolume selector) -> top level (ID 5)
#       -> configfile ($dev)/boot/grub2/grub.cfg
#       -> load_env -f $config_directory/grubenv             (top level's)
#
#   Each menuentry re-runs `search --set=root --fs-uuid ...`, which resolves to
#   the top level as well. So the bootloader loads vmlinuz/initrd/DTB from the
#   top-level /boot, while the kernel mounts root from the default subvolume via
#   rootflags and reads /lib/modules from THERE.
#
#   Net effect: vmlinuz, initrd and DTB must exist in BOTH /boot trees. The
#   module tree only needs to exist in the default subvolume.
#
#   Getting this wrong is invisible until boot: the menu lists the entry, then
#   GRUB reports "file not found" for the DTB, vmlinuz or initrd.
#
# USAGE
#   install-boot-artifacts.sh RELEASE [MENU_ID] [TOPLEVEL_SUBVOL_ID]
#
#     RELEASE    kernelrelease, e.g. 7.3.0-rc5-ZenbookA16-20261002-rc5-integrated1+
#     MENU_ID    GRUB --id to record as saved_entry; default $RELEASE
#     TOP        top-level subvolid, default 5
#
# Env: DEV=<esp-less block device> (default /dev/nvme0n1p17)
#
# Assumes the release is already installed in the running root. This mirrors only
# the bootloader-visible files; it does not run modules_install or dracut.

set -Eeuo pipefail

REL=${1:?usage: install-boot-artifacts.sh RELEASE [MENU_ID] [TOPLEVEL_SUBVOL_ID]}
MENU_ID=${2:-$REL}
TOP=${3:-5}
DEV=${DEV:-/dev/nvme0n1p17}

RUNNING_ENV=/boot/grub2/grubenv
ESP_ENV=/boot/efi/EFI/fedora/grubenv

echo "== release : $REL"
echo "== menu id : $MENU_ID"
echo "== subvolid: $TOP on $DEV"

for f in "/boot/vmlinuz-$REL" "/boot/initrd.img-$REL" "/boot/glymur/$REL.dtb"; do
    [[ -e $f ]] || { echo "error: not installed in the running root: $f" >&2; exit 1; }
done

T=$(mktemp -d)
cleanup() {
    sudo -n umount "$T" 2>/dev/null || true
    rmdir "$T" 2>/dev/null || true
}
trap cleanup EXIT

sudo -n mount -o "rw,subvolid=$TOP" "$DEV" "$T"
[[ -d $T/boot/grub2 ]] || {
    echo "error: $T/boot/grub2 missing; is subvolid $TOP correct?" >&2
    exit 1
}

echo "-- mirroring into subvolid $TOP"
sudo -n install -m 0644 "/boot/vmlinuz-$REL"    "$T/boot/vmlinuz-$REL"
sudo -n install -m 0644 "/boot/initrd.img-$REL" "$T/boot/initrd.img-$REL"
sudo -n install -m 0644 "/boot/glymur/$REL.dtb" "$T/boot/glymur/$REL.dtb"
[[ -e /boot/config-$REL ]] &&
    sudo -n install -m 0644 "/boot/config-$REL" "$T/boot/config-$REL"

echo "-- updating grubenv everywhere GRUB may read it"
for e in "$T/boot/grub2/grubenv" "$RUNNING_ENV" "$ESP_ENV"; do
    sudo -n test -f "$e" || continue
    # A stale next_entry outranks saved_entry and silently boots the wrong
    # kernel; prev_saved_entry can restore the old one. Clear both.
    sudo -n grub2-editenv "$e" unset next_entry 2>/dev/null || true
    sudo -n grub2-editenv "$e" unset prev_saved_entry 2>/dev/null || true
    sudo -n grub2-editenv "$e" set saved_entry="$MENU_ID"
    printf '   %s\n' "$e"
done

echo "-- verifying the mirrored files"
rc=0
for f in "$T/boot/vmlinuz-$REL" "$T/boot/initrd.img-$REL" "$T/boot/glymur/$REL.dtb"; do
    if sudo -n test -e "$f"; then
        printf '   OK      %s (%s bytes)\n' "${f#$T}" "$(sudo -n stat -c %s "$f")"
    else
        printf '   MISSING %s\n' "${f#$T}"
        rc=1
    fi
done

# Confirm every menuentry in the top-level config now resolves.
cfg=$T/boot/grub2/grub.cfg
if sudo -n test -f "$cfg"; then
    echo "-- auditing every entry in the top-level config against subvolid $TOP"
    sudo -n cp "$cfg" "$T/.audit.cfg"
    sudo -n chmod 644 "$T/.audit.cfg"
    missing=$(python3 - "$T/.audit.cfg" "$T" <<'PY'
import re, sys, os, subprocess
cfg, root = sys.argv[1], sys.argv[2]
cur, refs, bad = None, [], []
for ln in open(cfg):
    m = re.match(r'^(?:menuentry|submenu)\s+"([^"]*)".*--id ([A-Za-z0-9._-]+)', ln)
    if m:
        if cur is not None:
            bad += [f"{cur}:{k}" for k, p in refs if not os.path.exists(p)]
        cur = None if ln.startswith('submenu') else m.group(2)
        refs = []
        continue
    if cur:
        for key in ('devicetree', 'linux', 'initrd'):
            mm = re.match(rf'^\s+{key} (/boot/\S+)', ln)
            if mm:
                refs.append((key, root + mm.group(1)))
if cur is not None:
    bad += [f"{cur}:{k}" for k, p in refs if not os.path.exists(p)]
print('\n'.join(bad))
PY
)
    sudo -n rm -f "$T/.audit.cfg"
    if [[ -z $missing ]]; then
        echo "   all entries resolve"
    else
        echo "   UNRESOLVED:"; sed 's/^/     /' <<<"$missing"; rc=1
    fi
fi

sudo -n umount "$T"
rmdir "$T" 2>/dev/null || true
trap - EXIT

echo
if [[ $rc -eq 0 ]]; then
    echo "OK. Modules only need to exist in the default subvolume (rootflags=subvol=... on the cmdline)."
    echo "If you also changed 40_custom, regenerate grub.cfg into BOTH subvolumes."
else
    echo "FAILED - see above. Do not reboot until it is resolved." >&2
fi
exit $rc