#!/usr/bin/env bash
# Retire only the exact global hooks shipped before kernel scoping was added.
set -Eeuo pipefail
root=/
check=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) [[ $# -ge 2 && -d $2 ]] || exit 2; root=$2; shift 2 ;;
        --check) check=1; shift ;;
        *) echo "Unknown migration option: $1" >&2; exit 2 ;;
    esac
done

remove=()
while read -r expected relative; do
    path="$root/$relative"
    [[ -e $path || -L $path ]] || continue
    if [[ ! -f $path || -L $path ]]; then
        echo "Legacy hook requires review before upgrading: $path" >&2
        exit 1
    fi
    actual=$(sha256sum "$path" | cut -d ' ' -f1)
    if [[ $actual != "$expected" ]]; then
        echo "Modified legacy hook requires review before upgrading: $path" >&2
        exit 1
    fi
    remove+=("$path")
done <<'KNOWN_HOOKS'
be08e996e71019df753f3ef574d091e09f439a75a67b322439ab01c500f87d2e etc/modprobe.d/zenbook-a16-remoteproc.conf
552f28a17310724774b2fc6872a7ffc1d7176fe1a95e2d7a1bac2a3b5908fec6 etc/grub.d/09_zenbook_a16
08cb140353a4b38e7c936677c31ef02163ce58822d80629abc1482787339d6d2 etc/initramfs-tools/scripts/init-premount/zenbook-a16
KNOWN_HOOKS

# Old rescue initramfs blacklists disappear at switch-root; require a kernel guard.
if [[ -e "$root/etc/modprobe.d/zenbook-a16-remoteproc.conf" ]]; then
    for entry in "$root/boot/loader/entries/"*.conf "$root/boot/efi/loader/entries/"*.conf \
        "$root/boot/grub/grub.cfg" "$root/boot/grub2/grub.cfg"; do
        [[ -f $entry ]] || continue
        while read -r directive args || [[ -n ${directive:-} ]]; do
            case "$directive" in linux|linuxefi|options) ;; *) continue ;; esac
            rescue=0 blocked=0
            read -r -a words <<< "$args"
            for word in "${words[@]}"; do
                word=${word//\"/}
                word=${word//\'/}
                [[ $word != omarchy.a16.dsp=off ]] || rescue=1
                case "$word" in
                    module_blacklist=*)
                        case ",${word#module_blacklist=}," in *,qcom_q6v5_pas,*) blocked=1 ;; esac
                        ;;
                esac
            done
            if [[ $rescue == 1 && $blocked == 0 ]]; then
                echo "DSP-disabled rescue needs module_blacklist=qcom_q6v5_pas (merge any existing list) before retiring the legacy blacklist: $entry" >&2
                exit 1
            fi
        done < "$entry"
    done
fi

# Validate the complete migration before removing any known file.
if [[ $check == 0 && ${#remove[@]} -gt 0 ]]; then
    rm -- "${remove[@]}"
fi
