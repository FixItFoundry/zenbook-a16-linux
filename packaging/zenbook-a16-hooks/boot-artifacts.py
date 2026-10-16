#!/usr/bin/python3
"""Stage only build-identified A16 kernel/DTB pairs and emit their boot entries."""
import importlib.util
import json
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


def managed(root, release, modules_dir=None):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.+\-]*', release):
        raise ValueError('invalid kernel release')
    legacy = 'zenbooka16' in release.lower()
    packaged = re.search(r'-a16pkg[0-9]+', release) is not None
    directory = modules_dir if modules_dir is not None else root / f'usr/lib/modules/{release}'
    metadata = directory / 'zenbook-a16-boot.json'
    if not metadata.exists() and not legacy and not packaged:
        return False
    policy = json.loads(metadata.read_text())
    if (not isinstance(policy, dict) or type(policy.get('schema')) is not int or policy['schema'] != 1
            or policy.get('kernel_release') != release or policy.get('dsp_policy') != 'pre-root-v1'
            or (policy.get('package_family') != 'zenbook-a16' and not (legacy and not packaged and 'package_family' not in policy))):
        raise ValueError(f'invalid managed A16 kernel metadata: {metadata}')
    if (policy.get('package_family') == 'zenbook-a16'
            and (not isinstance(policy.get('source_tree'), str)
                 or not re.fullmatch(r'[a-f0-9]{40}', policy['source_tree']))):
        raise ValueError(f'managed A16 metadata lacks source_tree: {metadata}')
    return True


def pair(root, release):
    if not re.fullmatch(r'[A-Za-z0-9_.+\-]+', release):
        raise ValueError('invalid kernel release')
    if not managed(root, release):
        raise ValueError(f'kernel is not managed by Zenbook A16: {release}')
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
        blocked = [name for token in result if token.startswith('module_blacklist=')
                   for name in token.split('=', 1)[1].split(',')]
        result = [token for token in result if not token.startswith('module_blacklist=')]
        result += ['omarchy.a16.dsp=off', 'module_blacklist=' + ','.join(dict.fromkeys(blocked + ['qcom_q6v5_pas']))]
    # These are literal kernel tokens, never shell or GRUB expressions.
    if any(not re.fullmatch(r'[A-Za-z0-9_.,:/=+@%\-]+', token) for token in result):
        raise ValueError('unsupported nonliteral kernel command line')
    if not any(token.startswith('root=') for token in result):
        raise ValueError('kernel command line has no root= device')
    return ' '.join(result)


def stage(root, release):
    if not managed(root, release):
        return
    kernel, source, policy = pair(root, release)
    for dest in (root / f'boot/dtb-{release}', root / f'boot/dtbs/{release}/qcom/{DTB}',
                 root / f'boot/glymur/{release}.dtb'):
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists() or not os.path.samefile(source, dest):
            shutil.copyfile(source, dest)
    return policy


def boot_prefix(root):
    target = subprocess.check_output(['findmnt', '-n', '-o', 'TARGET', '-T', str(root / 'boot')], text=True).strip()
    if target == str(root / 'boot'):
        return ''
    if target == str(root):
        return '/boot'
    raise ValueError(f'unsupported boot mount: {target}')


def update_bls(root, release, extra=None):
    if not managed(root, release):
        return
    prefix = boot_prefix(root)
    initrd = root / f'boot/initramfs-{release}.img'
    if not initrd.is_file() or initrd.stat().st_size == 0:
        raise ValueError(f'missing canonical initramfs for {release}')
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
            lines = [line for line in lines if not line.startswith(('linux ', 'initrd ', 'devicetree ', 'options '))]
            lines += [f'linux {prefix}/vmlinuz-{release}', f'initrd {prefix}/initramfs-{release}.img',
                      f'devicetree {prefix}/dtbs/{release}/qcom/{DTB}', f'options {boot_options}']
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
    releases = sorted(metadata.parent.name for metadata in (root / 'usr/lib/modules').glob('*/zenbook-a16-boot.json')
                      if managed(root, metadata.parent.name))
    if not releases:
        return ''
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
    for release in releases:
        found = True
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


def grub_menu(root):
    menus, stack, depth = [], [], 0
    for line in (root / 'boot/grub/grub.cfg').read_text().splitlines():
        tokens = shlex.split(line, comments=True)
        if tokens and tokens[0] in ('menuentry', 'submenu'):
            entry_id = None
            for index, token in enumerate(tokens):
                if token in ('--id', '$menuentry_id_option', '${menuentry_id_option}'):
                    entry_id = tokens[index + 1]
                elif token.startswith('--id='):
                    entry_id = token[5:]
            node = {'kind': tokens[0], 'title': tokens[1], 'id': entry_id, 'children': [], 'linux': [], 'cmdline': [], 'artifacts': []}
            parent = next((item for item, _ in reversed(stack) if item['kind'] == 'submenu'), None)
            (parent['children'] if parent else menus).append(node)
            stack.append((node, depth))
        elif tokens and stack and stack[-1][0]['kind'] == 'menuentry':
            if tokens[0] in ('linux', 'linuxefi'):
                stack[-1][0]['linux'].append(tokens[1])
                stack[-1][0]['cmdline'] = tokens[2:]
            if tokens[0] in ('linux', 'linuxefi', 'initrd', 'initrdefi', 'devicetree', 'search'):
                stack[-1][0]['artifacts'].append(tokens)
        depth += sum(1 if token.strip(';') == '{' else -1 if token.strip(';') == '}' else 0 for token in tokens)
        while stack and depth <= stack[-1][1]:
            stack.pop()
    return menus


def selected_entry(root, selection, with_cmdline=False, stable=False):
    all_menus = grub_menu(root)
    menus, identifiers = all_menus, []
    for component in selection.split('>'):
        if component.isdecimal():
            matches = menus[int(component):int(component) + 1]
        else:
            matches = [entry for entry in menus if component in (entry['id'], entry['title'])]
        if len(matches) != 1:
            raise ValueError(f'cannot establish existing GRUB default: {selection}')
        entry = matches[0]
        if not entry['id'] or not re.fullmatch(r'[A-Za-z0-9_.+:-]+', entry['id']):
            raise ValueError('existing GRUB default needs a stable literal menu ID')
        identifiers.append(entry['id'])
        menus = entry['children']
    if entry['kind'] != 'menuentry' or len(entry['linux']) != 1:
        raise ValueError('existing GRUB default is not one explicit kernel entry')
    path = entry['linux'][0]
    if not path.startswith('/') or '..' in Path(path).parts or '$' in path:
        raise ValueError('unsupported existing GRUB kernel path')
    candidates = [root / path.lstrip('/'), root / 'boot' / path.lstrip('/')]
    kernel = next((candidate for candidate in candidates if candidate.is_file()), None)
    if kernel is None:
        raise ValueError('existing default kernel image is missing; refusing to replace the rollback target')
    if stable and entry['id'].startswith('gnulinux-simple-'):
        release = kernel.name.removeprefix('vmlinuz-')
        matches = []
        def visit(nodes, parents):
            for candidate in nodes:
                path = parents + [candidate['id']]
                if (candidate['id'] and candidate['id'].startswith(f'gnulinux-{release}-advanced-')
                        and candidate['artifacts'] == entry['artifacts']
                        and all(identifier and re.fullmatch(r'[A-Za-z0-9_.+:-]+', identifier) for identifier in path)):
                    matches.append(path)
                visit(candidate['children'], path)
        visit(all_menus, [])
        if len(matches) != 1:
            raise ValueError('the Ubuntu simple default needs one equivalent versioned Advanced-options entry')
        identifiers = matches[0]
    result = ('>'.join(identifiers), '/' + str(kernel.relative_to(root)))
    return (*result, entry['cmdline']) if with_cmdline else result


def grub_default(root):
    value = '0'
    configs = [root / 'etc/default/grub', *sorted((root / 'etc/default/grub.d').glob('*.cfg'))]
    for config in configs:
        if not config.is_file():
            continue
        for line in config.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            match = re.match(r'^\s*(?:export\s+)?GRUB_DEFAULT=(.*)$', line)
            if match:
                tokens = shlex.split(match[1], comments=True)
                if len(tokens) != 1 or any(char in tokens[0] for char in '$`\n'):
                    raise ValueError('GRUB_DEFAULT must be a literal index, menu ID, title or saved')
                value = tokens[0]
            elif 'GRUB_DEFAULT' in line:
                raise ValueError('conditional GRUB_DEFAULT is unsupported; choose a literal default before installing')
    return value


def distro_name(root):
    data = {}
    for line in (root / 'etc/os-release').read_text().splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            tokens = shlex.split(value)
            if len(tokens) == 1:
                data[key] = tokens[0]
    names = set((data.get('ID', '') + ' ' + data.get('ID_LIKE', '')).split())
    if names & {'fedora', 'rhel'}:
        return 'fedora'
    if names & {'ubuntu', 'debian'}:
        return 'ubuntu'
    raise ValueError('cannot determine Fedora/Ubuntu boot default policy')


def fedora_default(root, kernel=None):
    if kernel is None:
        kernel = subprocess.check_output(['grubby', '--default-kernel'], text=True).strip()
    if not kernel.startswith('/boot/') or '..' in Path(kernel).parts or not (root / kernel.lstrip('/')).is_file():
        raise ValueError('existing Fedora default kernel image is missing or unsupported')
    info = subprocess.check_output(['grubby', '--info', kernel], text=True)
    values = {}
    for line in info.splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            tokens = shlex.split(value)
            if key in values or len(tokens) != 1:
                raise ValueError('ambiguous grubby default kernel information')
            values[key] = tokens[0]
    entry_id = values.get('id', '')
    if values.get('kernel') != kernel or not re.fullmatch(r'[A-Za-z0-9_.+:-]+', entry_id):
        raise ValueError('Fedora default kernel needs a stable BLS entry ID')
    return entry_id, kernel


def preserve_default(root, distro=None):
    reject_shared_btrfs_boot()
    state_path = root / 'var/lib/zenbook-a16/rollback.json'
    if state_path.exists():
        state = json.loads(state_path.read_text())
        validate_rollback(root, state)
        if distro is not None and state['distro'] != distro:
            raise ValueError('preserved rollback state belongs to another distribution')
        if state['distro'] == 'ubuntu':
            expected = 'saved' if state['mode'] == 'saved' else state['entry_id']
            if grub_default(root) != expected or selected_entry(root, state['entry_id']) != (state['entry_id'], state['kernel']):
                raise ValueError('preserved Ubuntu boot default policy changed')
            if state['mode'] == 'saved':
                output = subprocess.check_output(['grub-editenv', '/boot/grub/grubenv', 'list'], text=True)
                if [line[12:] for line in output.splitlines() if line.startswith('saved_entry=')] != [state['entry_id']]:
                    raise ValueError('the saved boot default changed; review the preserved rollback policy before upgrading')
            if not (root / 'etc/kernel/cmdline').is_file():
                raise ValueError('installed kernel command line is missing')
        elif not (root / 'etc/kernel/cmdline').is_file() or fedora_default(root) != (state['entry_id'], state['kernel']):
            raise ValueError('preserved Fedora boot entry changed')
        return state
    distro = distro or distro_name(root)
    if distro == 'fedora':
        if not (root / 'etc/kernel/cmdline').is_file():
            raise ValueError('Fedora requires an existing /etc/kernel/cmdline before installing A16 packages')
        entry_id, kernel = fedora_default(root)
        mode, cmdline = 'saved', None
    elif distro == 'ubuntu':
        selection = grub_default(root)
        mode = 'saved' if selection == 'saved' else 'id'
        if mode == 'saved':
            output = subprocess.check_output(['grub-editenv', '/boot/grub/grubenv', 'list'], text=True)
            saved = [line[12:] for line in output.splitlines() if line.startswith('saved_entry=')]
            if len(saved) != 1 or not saved[0]:
                raise ValueError('GRUB_DEFAULT=saved requires one existing saved_entry')
            selection = saved[0]
        entry_id, kernel, cmdline = selected_entry(root, selection, with_cmdline=True, stable=True)
    else:
        raise ValueError('unsupported boot default policy')
    state = {'schema': 1, 'distro': distro, 'kernel': kernel, 'entry_id': entry_id, 'mode': mode}
    validate_rollback(root, state)
    if distro == 'ubuntu':
        pin = root / 'etc/default/grub.d/99-zenbook-a16-default.cfg'
        value = 'saved' if mode == 'saved' else entry_id
        content = '# Preserve the pre-install boot selection while adding A16 kernels.\nGRUB_DEFAULT=' + shlex.quote(value) + '\n'
        if pin.exists() and pin.read_text() != content:
            raise ValueError(f'refusing to overwrite existing boot default policy: {pin}')
        kernel_cmdline = root / 'etc/kernel/cmdline'
        if not kernel_cmdline.exists():
            # Derive the installed root identity from its existing entry, never the live installer.
            literal = [token for token in cmdline if token not in ('$vt_handoff', '${vt_handoff}')]
            line = options(shlex.join(literal), {'cmdline': []})
            kernel_cmdline.parent.mkdir(parents=True, exist_ok=True)
            kernel_cmdline.write_text(line + '\n')
        pin.parent.mkdir(parents=True, exist_ok=True)
        pin.write_text(content)
        if grub_default(root) != value:
            raise ValueError('a later GRUB drop-in overrides the preserved default; resolve it before installing')
        if mode == 'saved':
            subprocess.run(['grub-editenv', '/boot/grub/grubenv', 'set', 'saved_entry=' + entry_id], check=True)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2) + '\n')
    return state


def validate_rollback(root, state):
    if (not isinstance(state, dict) or type(state.get('schema')) is not int or state['schema'] != 1
            or state.get('distro') not in ('fedora', 'ubuntu') or state.get('mode') not in ('saved', 'id')
            or not isinstance(state.get('entry_id'), str)
            or not re.fullmatch(r'[A-Za-z0-9_.+:>\-]+', state['entry_id'])
            or not isinstance(state.get('kernel'), str) or not state['kernel'].startswith('/boot/')
            or '..' in Path(state['kernel']).parts or not (root / state['kernel'].lstrip('/')).is_file()):
        raise ValueError('invalid or missing preserved rollback kernel; refusing to change the boot default')


def restore_default(root):
    state_path = root / 'var/lib/zenbook-a16/rollback.json'
    if not state_path.exists():
        return
    state = json.loads(state_path.read_text())
    validate_rollback(root, state)
    if state['distro'] == 'fedora':
        if fedora_default(root, state['kernel'])[0] != state['entry_id']:
            raise ValueError('preserved Fedora kernel entry identity has changed')
        subprocess.run(['grubby', '--set-default', state['kernel']], check=True)
        if subprocess.check_output(['grubby', '--default-kernel'], text=True).strip() != state['kernel']:
            raise ValueError('Fedora failed to restore the preserved boot default')
    else:
        if selected_entry(root, state['entry_id']) != (state['entry_id'], state['kernel']):
            raise ValueError('preserved Ubuntu kernel entry identity has changed')
        expected = 'saved' if state['mode'] == 'saved' else state['entry_id']
        if grub_default(root) != expected:
            raise ValueError('preserved Ubuntu default policy changed; refusing to override it')
        if state['mode'] == 'saved':
            subprocess.run(['grub-editenv', '/boot/grub/grubenv', 'set', 'saved_entry=' + state['entry_id']], check=True)


def main():
    root = Path('/')
    if sys.argv[1] == 'preserve-default':
        preserve_default(root, sys.argv[2] if len(sys.argv) > 2 else None)
        return 0
    if sys.argv[1] == 'restore-default':
        restore_default(root)
        return 0
    if sys.argv[1] == 'managed':
        return 0 if managed(root, sys.argv[2], Path(sys.argv[3]) if len(sys.argv) > 3 else None) else 4
    if sys.argv[1] in ('stage', 'bls') and not managed(root, sys.argv[2]):
        return 0
    if sys.argv[1] == 'grub' and not any(managed(root, metadata.parent.name)
            for metadata in (root / 'usr/lib/modules').glob('*/zenbook-a16-boot.json')):
        return 0
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
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'zenbook-a16: {error}')
