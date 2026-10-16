#!/usr/bin/python3
"""Stage only build-identified A16 kernel/DTB pairs and emit their boot entries."""
import importlib.util
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

DTB = 'glymur-asus-zenbook-a16-ux3607oa.dtb'


def verifier(root):
    path = root / 'usr/lib/zenbook-a16/verify-boot.py'
    spec = importlib.util.spec_from_file_location('a16_verify', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def pair(root, release):
    if not re.fullmatch(r'[A-Za-z0-9_.+\-]+', release):
        raise ValueError('invalid kernel release')
    kernel = root / f'boot/vmlinuz-{release}'
    candidates = [root / f'usr/lib/modules/{release}/dtb/qcom/{DTB}',
                  root / f'lib/modules/{release}/dtb/qcom/{DTB}',
                  root / f'boot/dtb-{release}']
    dtb = next((path for path in candidates if path.is_file()), candidates[0])
    policy = verifier(root).validate_kernel_metadata(root, release, kernel, dtb)
    return kernel, dtb, policy


def options(existing, policy, rescue=False):
    tokens = shlex.split(existing)
    keys = {token.split('=', 1)[0] for token in policy['cmdline']} | {'omarchy.a16.dsp'}
    result = [token for token in tokens if token.split('=', 1)[0] not in keys]
    result += policy['cmdline']
    if rescue:
        result.append('omarchy.a16.dsp=off')
    # These are literal kernel tokens, never shell or GRUB expressions.
    if any(not re.fullmatch(r'[A-Za-z0-9_.,:/=+@%\-]+', token) for token in result):
        raise ValueError('unsupported nonliteral kernel command line')
    if not any(token.startswith('root=') for token in result):
        raise ValueError('kernel command line has no root= device')
    return ' '.join(result)


def stage(root, release):
    kernel, source, policy = pair(root, release)
    for dest in (root / f'boot/dtb-{release}', root / f'boot/dtbs/{release}/qcom/{DTB}',
                 root / f'boot/glymur/{release}.dtb'):
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists() or not os.path.samefile(source, dest):
            shutil.copyfile(source, dest)
    return policy


def update_bls(root, release, extra=None):
    policy = stage(root, release)
    directories = [root / 'boot/loader/entries', root / 'boot/efi/loader/entries']
    if extra:
        directories.append(Path(extra))
    found = False
    for directory in dict.fromkeys(directories):
        for entry in sorted(directory.glob('*.conf')):
            if entry.stem.endswith('-a16-rescue'):
                continue
            text = entry.read_text()
            lines = text.splitlines()
            kernels = [line.split(None, 1)[1] for line in lines if line.startswith('linux ')]
            if not any(Path(value).name == f'vmlinuz-{release}' or
                       (Path(value).name == 'linux' and release in Path(value).parts)
                       for value in kernels):
                continue
            option_lines = [line for line in lines if line.startswith('options ')]
            if len(option_lines) != 1 or len(kernels) != 1:
                raise ValueError(f'ambiguous BLS entry: {entry}')
            boot_options = options(option_lines[0][8:], policy)
            lines = [line for line in lines if not line.startswith(('devicetree ', 'options '))]
            lines += [f'devicetree /dtbs/{release}/qcom/{DTB}', f'options {boot_options}']
            entry.write_text('\n'.join(lines) + '\n')
            rescue = entry.with_name(entry.stem + '-a16-rescue.conf')
            if not entry.stem.endswith('-a16-rescue'):
                rescue_lines = [line + ' (DSP disabled rescue)' if line.startswith('title ') else line
                                for line in lines if not line.startswith('options ')]
                rescue_lines.append(f'options {options(boot_options, policy, rescue=True)}')
                rescue.write_text('\n'.join(rescue_lines) + '\n')
            found = True
    if not found:
        raise ValueError(f'no generated BLS entry references kernel {release}')


def grub_entries(root):
    # GRUB locates the filesystem containing /boot by UUID, independent of root=.
    probe = lambda target: subprocess.check_output(
        ['grub-probe', f'--target={target}', '/boot'], text=True).strip()
    uuid, fs = probe('fs_uuid'), probe('fs')
    if not re.fullmatch(r'[A-Za-z0-9-]+', uuid) or not re.fullmatch(r'[A-Za-z0-9_]+', fs):
        raise ValueError('invalid GRUB filesystem identity')
    mountpoint = subprocess.check_output(['findmnt', '-n', '-o', 'TARGET', '-T', '/boot'], text=True).strip()
    prefix = '' if mountpoint == '/boot' else '/boot'
    cmdline = (root / 'etc/kernel/cmdline').read_text().strip()
    result = ['insmod fdt']
    found = False
    for metadata in sorted((root / 'usr/lib/modules').glob('*/zenbook-a16-boot.json')):
        found = True
        release = metadata.parent.name
        _, _, policy = pair(root, release)
        if not (root / f'boot/initrd.img-{release}').is_file():
            raise ValueError(f'missing initramfs for {release}')
        for rescue in (False, True):
            title = f'Zenbook A16 {release}' + (' (DSP disabled rescue)' if rescue else '')
            entry_id = f"zenbook-a16-{release}" + ("-rescue" if rescue else "")
            result += [f"menuentry '{title}' --id '{entry_id}' {{", f'  insmod {fs}',
                       f'  search --no-floppy --fs-uuid --set=root {uuid}',
                       f'  linux {prefix}/vmlinuz-{release} {options(cmdline, policy, rescue)}',
                       f'  devicetree {prefix}/dtb-{release}',
                       f'  initrd {prefix}/initrd.img-{release}', '}']
    if not found:
        raise ValueError('no build-identified A16 kernels installed')
    return '\n'.join(result) + '\n'


def reject_shared_btrfs_boot():
    root_fs = subprocess.check_output(['findmnt', '-n', '-o', 'FSTYPE,FSROOT', '/'], text=True).split()
    boot_target = subprocess.check_output(['findmnt', '-n', '-o', 'TARGET', '-T', '/boot'], text=True).strip()
    if root_fs and root_fs[0] == 'btrfs' and len(root_fs) > 1 and root_fs[1] != '/' and boot_target != '/boot':
        raise ValueError('Btrfs subvolume root requires a separately mounted /boot; boot mirroring is unsupported')


def main():
    root = Path('/')
    reject_shared_btrfs_boot()
    if sys.argv[1] == 'grub':
        print(grub_entries(root), end='')
    elif sys.argv[1] == 'bls':
        update_bls(root, sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif sys.argv[1] == 'stage':
        stage(root, sys.argv[2])
    else:
        raise ValueError('unknown artifact operation')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'zenbook-a16: {error}')
