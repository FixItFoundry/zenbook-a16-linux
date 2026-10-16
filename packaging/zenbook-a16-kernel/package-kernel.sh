#!/usr/bin/env bash
# Native package lifecycle; every boot artifact is keyed by the kernel release.
set -Eeuo pipefail
action=${1:?action required}
distro=${2:?distribution required}
release=${3:?kernel release required}
[[ "$distro" == fedora || "$distro" == ubuntu ]] || exit 2
[[ "$release" =~ ^[A-Za-z0-9.+-]+-a16pkg[1-9][0-9]*\+$ ]] || exit 2
helper=/usr/lib/zenbook-a16/boot-artifacts.py

restore_boot_default() {
    local result=$?
    trap - EXIT
    python3 "$helper" restore-default || result=1
    exit "$result"
}

case "$action" in
    pre)
        # Even a reinstall must not replace a running or rollback kernel in place.
        for path in "/usr/lib/modules/$release" "/boot/vmlinuz-$release" "/boot/dtb-$release" \
            "/boot/dtbs/$release" "/boot/glymur/$release.dtb" "/boot/config-$release" \
            "/boot/initramfs-$release.img" "/boot/initrd.img-$release"; do
            [[ ! -e "$path" && ! -L "$path" ]] || {
                echo "Refusing to replace $path; build with a new PACKAGE_REVISION." >&2
                exit 1
            }
        done
        /usr/lib/zenbook-a16/migrate-hooks
        /usr/lib/zenbook-a16/check-firmware --check
        python3 "$helper" preserve-default "$distro"
        [[ -s /etc/kernel/cmdline ]] || { echo 'Installed root command line is required in /etc/kernel/cmdline.' >&2; exit 1; }
        ;;
    post)
        # A later failure must not leave a newly selected kernel as the default.
        trap restore_boot_default EXIT
        python3 "$helper" managed "$release"
        depmod -a "$release"
        if [[ "$distro" == fedora ]]; then
            dracut --force --no-hostonly --kver "$release" "/boot/initramfs-$release.img"
            kernel-install add "$release" "/boot/vmlinuz-$release" "/boot/initramfs-$release.img"
        else
            mode=-c
            [[ ! -e "/boot/initrd.img-$release" ]] || mode=-u
            update-initramfs "$mode" -k "$release"
            /etc/kernel/postinst.d/zz-zenbook-a16 "$release" "/boot/vmlinuz-$release"
        fi
        python3 /usr/lib/zenbook-a16/verify-boot.py --bootloader "grub-$([[ $distro == fedora ]] && echo bls || echo ubuntu)" --kernel-release "$release"
        ;;
    remove-check)
        [[ "$(uname -r)" != "$release" ]] || { echo 'Refusing to remove the running A16 kernel.' >&2; exit 1; }
        python3 - "$release" <<'PY'
import json
from pathlib import Path
import sys
state = Path('/var/lib/zenbook-a16/rollback.json')
if state.exists() and json.loads(state.read_text()).get('kernel') == '/boot/vmlinuz-' + sys.argv[1]:
    sys.exit('Refusing to remove the preserved rollback kernel.')
PY
        ;;
    remove)
        trap restore_boot_default EXIT
        # Native package managers remove the owned Image/DTBs/modules themselves.
        if [[ "$distro" == fedora ]]; then
            kernel-install remove "$release"
            python3 - "$release" <<'PY'
from pathlib import Path
import sys
for directory in (Path('/boot/loader/entries'), Path('/boot/efi/loader/entries')):
    for entry in directory.glob('*.conf'):
        if ('version ' + sys.argv[1]) in entry.read_text().splitlines():
            entry.unlink()
PY
            rm -f "/boot/initramfs-$release.img"
        else
            update-initramfs -d -k "$release"
            update-grub
        fi
        ;;
    *) exit 2 ;;
esac
