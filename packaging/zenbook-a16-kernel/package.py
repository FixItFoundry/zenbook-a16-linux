#!/usr/bin/env python3
"""Package a verified A16 build without installing it on the build host."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DTB = 'glymur-asus-zenbook-a16-ux3607oa.dtb'
CMDLINE = ['clk_ignore_unused', 'pd_ignore_unused', 'cma=128M', 'glymur_pci_skip=5',
           'selinux=0', 'asus_glymur_ec.fan_profile=2',
           'modprobe.blacklist=i2c_qcom_cci,qcom_camss,ov02c10']


def write_metadata(bundle, build_file, revision):
    build = json.loads(build_file.read_text())
    if revision < 1 or not build['release'].endswith('+'):
        raise ValueError('positive package revision and recorded + release required')
    release = build['release'][:-1] + f'-a16pkg{revision}+'
    version = build['promotion_date'].replace('-', '') + f'.{revision}'
    if not re.fullmatch(r'[A-Za-z0-9.+-]+', release) or not re.fullmatch(r'\d{8}\.\d+', version):
        raise ValueError('invalid package identity')
    paths = {'kernel_sha256': bundle / f'vmlinuz-{release}',
             'dtb_sha256': bundle / DTB, 'config_sha256': bundle / f'config-{release}'}
    data = {'schema': 1, 'package_family': 'zenbook-a16', 'package_version': version,
            'kernel_release': release, 'source_tree': build['source_tree'],
            'dsp_policy': 'pre-root-v1', 'cmdline': CMDLINE}
    data.update({key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in paths.items()})
    (bundle / f'lib/modules/{release}/zenbook-a16-boot.json').write_text(json.dumps(data, indent=2) + '\n')
    return data


def copy(source, destination, mode=None):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if mode is not None:
        destination.chmod(mode)


def stage(bundle, output, distro):
    release = (bundle / 'usr/share/doc/linux-zenbook-a16/kernel-release').read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9.+-]+-a16pkg[1-9][0-9]*\+', release):
        raise ValueError('build a versioned package release; refusing the installed baseline identity')
    modules = bundle / f'lib/modules/{release}'
    spec = importlib.util.spec_from_file_location('verify_boot', REPO / 'packaging/omarchy-a16-support/verify-boot.py')
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    kernel, dtb = bundle / f'vmlinuz-{release}', bundle / DTB
    verifier.verify_image(kernel)
    verifier.verify_dtb(dtb)
    data = verifier.validate_kernel_metadata(bundle, release, kernel, dtb, modules)
    version = data.get('package_version', '')
    if data.get('package_family') != 'zenbook-a16' or not re.fullmatch(r'\d{8}\.[1-9][0-9]*', version):
        raise ValueError('missing managed package identity')
    config = bundle / f'config-{release}'
    if data.get('config_sha256') != hashlib.sha256(config.read_bytes()).hexdigest():
        raise ValueError('kernel configuration hash mismatch')
    if not (modules / 'build/Makefile').is_file() or (modules / 'build').is_symlink():
        raise ValueError('matching external-module build headers are required')
    if (modules / 'build/include/config/kernel.release').read_text().strip() != release:
        raise ValueError('kernel build headers belong to another release')
    for path in modules.rglob('*'):
        if path.is_symlink() and not path.resolve().is_relative_to(modules.resolve()):
            raise ValueError(f'module/header symlink escapes staged build: {path}')
    suffix = re.sub(r'[^a-z0-9+.-]', '-', release.lower())
    name = ('kernel-zenbook-a16-' if distro == 'fedora' else 'linux-image-') + suffix
    roots = {kind: output / kind for kind in ('kernel', 'support', 'tracking')}
    for root in roots.values():
        root.mkdir(parents=True, exist_ok=False)
    payload = roots['kernel']
    shutil.copytree(modules, payload / f'usr/lib/modules/{release}', symlinks=True)
    copy(kernel, payload / f'boot/vmlinuz-{release}')
    for dest in (f'boot/dtb-{release}', f'boot/glymur/{release}.dtb',
                 f'boot/dtbs/{release}/qcom/{DTB}', f'usr/lib/modules/{release}/dtb/qcom/{DTB}'):
        copy(dtb, payload / dest)
    copy(config, payload / f'boot/config-{release}')
    copy(REPO / 'LICENSE', payload / f'usr/share/doc/{name}/LICENSE')
    copy(modules / 'zenbook-a16-boot.json', payload / f'usr/share/doc/{name}/build.json')
    support = roots['support']
    subprocess.run(['bash', str(REPO / 'packaging/zenbook-a16-hooks/install-hooks.sh'),
                    '--root', str(support), '--distro', distro], check=True)
    copy(HERE / 'package-kernel.sh', support / 'usr/lib/zenbook-a16/package-kernel', 0o755)
    copy(REPO / 'iso/glymur-fetch-firmware.sh', support / 'usr/lib/zenbook-a16/check-firmware', 0o755)
    copy(REPO / 'LICENSE', support / 'usr/share/doc/zenbook-a16-support/LICENSE')
    if distro == 'ubuntu':
        keep = support / 'etc/apt/apt.conf.d/01zenbook-a16-keep-kernels'
        keep.parent.mkdir(parents=True)
        keep.write_text('APT::NeverAutoRemove { "^linux-image-.*-zenbooka16-.*$"; };\n')
    marker = roots['tracking'] / 'usr/share/doc/zenbook-a16-kernel/kernel-release'
    marker.parent.mkdir(parents=True)
    marker.write_text(release + '\n')
    return roots, name, release, version


def script(action, distro, release):
    return f'/usr/lib/zenbook-a16/package-kernel {action} {distro} {release}'


def migration_check():
    migration = (REPO / 'packaging/zenbook-a16-hooks/migrate-hooks.sh').read_text()
    return "bash -s -- --check <<'A16_MIGRATE'\n" + migration + 'A16_MIGRATE\n'


def rpm_spec(roots, name, release, version):
    support_files = '\n'.join('/' + str(p.relative_to(roots['support']))
                              for p in sorted(roots['support'].rglob('*')) if p.is_file() or p.is_symlink())
    # Disable buildroot rewriting: modules already carry the kernel build's signatures.
    return f'''%global __os_install_post %{{nil}}
%global debug_package %{{nil}}
Name: zenbook-a16-kernel
Version: {version}
Release: 1
Summary: Track the tested Zenbook A16 kernel
License: GPL-2.0-only
URL: https://github.com/FixItFoundry/zenbook-a16-linux
Source0: payload.tar
BuildArch: aarch64
AutoReqProv: no
Requires: {name} = %{{version}}-%{{release}}

%description
Tracks a versioned kernel. Earlier kernel packages are retained for rollback.

%package -n {name}
Summary: Versioned Zenbook A16 kernel, modules, DTB and build headers
AutoReqProv: no
Requires: zenbook-a16-support >= %{{version}}
Requires(pre): zenbook-a16-support >= %{{version}}
Provides: installonlypkg(kernel)

%description -n {name}
Build-identified A16 kernel. Installing it preserves existing kernel versions.

%package -n zenbook-a16-support
Summary: Zenbook A16 boot integration and verification
AutoReqProv: no
Requires: bash, coreutils, python3, kmod, util-linux, dtc, dracut, systemd, systemd-udev, grubby, grub2-tools, xz, zstd
Requires(pre): bash, coreutils

%description -n zenbook-a16-support
Scoped initramfs and boot hooks for managed A16 kernels. Firmware is not included.

%prep
%setup -q -c

%build

%install
mkdir -p %{{buildroot}}
cp -a kernel/. support/. tracking/. %{{buildroot}}/

%pre -n zenbook-a16-support
{migration_check().replace('%', '%%')}
%post -n zenbook-a16-support
/usr/lib/zenbook-a16/migrate-hooks

%pre -n {name}
{script('pre', 'fedora', release)}

%post -n {name}
{script('post', 'fedora', release)}

%preun -n {name}
if [ "$1" = 0 ]; then
  {script('remove-check', 'fedora', release)}
fi

%postun -n {name}
if [ "$1" = 0 ]; then
  {script('remove', 'fedora', release)}
fi

%files
%defattr(-,root,root,-)
/usr/share/doc/zenbook-a16-kernel

%files -n {name}
%defattr(-,root,root,-)
/usr/lib/modules/{release}
/boot/vmlinuz-{release}
/boot/config-{release}
/boot/dtb-{release}
/boot/dtbs/{release}
/boot/glymur/{release}.dtb
/usr/share/doc/{name}

%files -n zenbook-a16-support
%defattr(-,root,root,-)
{support_files}
'''


def debian_controls(roots, name, release, version):
    for kind, pkg in (('kernel', name), ('support', 'zenbook-a16-support'), ('tracking', 'zenbook-a16-kernel')):
        control_dir = roots[kind] / 'DEBIAN'
        control_dir.mkdir()
        relations = {'kernel': f'Pre-Depends: zenbook-a16-support (>= {version})\n',
                     'support': 'Depends: bash, coreutils, python3, kmod, util-linux, device-tree-compiler, initramfs-tools, udev, grub-common, grub2-common, xz-utils, zstd\n',
                     'tracking': f'Depends: {name} (= {version})\n'}[kind]
        (control_dir / 'control').write_text(
            f'Package: {pkg}\nVersion: {version}\nArchitecture: arm64\n'
            'Maintainer: Jesse Casco <jesse.casco@gmail.com>\n'
            'Section: kernel\nPriority: optional\n' + relations +
            'Homepage: https://github.com/FixItFoundry/zenbook-a16-linux\n'
            'Description: Managed Zenbook A16 kernel support\n'
            ' Versioned artifacts and scoped boot hooks; firmware is supplied separately.\n')
    for filename, cases, action in [('preinst', 'install|upgrade', 'pre'), ('postinst', 'configure', 'post'),
                                     ('prerm', 'remove', 'remove-check'), ('postrm', 'remove', 'remove')]:
        path = roots['kernel'] / 'DEBIAN' / filename
        path.write_text(f'#!/bin/sh\nset -eu\ncase "$1" in\n  {cases}) {script(action, "ubuntu", release)} ;;\nesac\n')
        path.chmod(0o755)
    for filename, body in [('preinst', 'case "$1" in\ninstall|upgrade)\n' + migration_check() + ';;\nesac\n'),
                           ('postinst', 'case "$1" in\nconfigure) /usr/lib/zenbook-a16/migrate-hooks ;;\nesac\n')]:
        path = roots['support'] / 'DEBIAN' / filename
        path.write_text('#!/bin/sh\nset -eu\n' + body)
        path.chmod(0o755)


def build_packages(bundle, output, distro):
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='a16-packaging-', dir=output.parent) as directory:
        work = Path(directory)
        roots, name, release, version = stage(bundle, work / 'payload', distro)
        if distro == 'fedora':
            for sub in ('BUILD', 'BUILDROOT', 'SPECS', 'SOURCES', 'RPMS', 'SRPMS'):
                (work / sub).mkdir()
            with tarfile.open(work / 'SOURCES/payload.tar', 'w') as archive:
                for kind, root in roots.items():
                    archive.add(root, arcname=kind)
            spec = work / 'SPECS/zenbook-a16.spec'
            spec.write_text(rpm_spec(roots, name, release, version))
            subprocess.run(['rpmbuild', '-bb', '--target', 'aarch64', '--define', f'_topdir {work}', str(spec)], check=True)
            packages = list((work / 'RPMS').rglob('*.rpm'))
            if len(packages) != 3:
                raise ValueError('expected kernel, support and tracking RPMs')
            for path in packages:
                shutil.copy2(path, output / path.name)
        else:
            debian_controls(roots, name, release, version)
            for kind, pkg in [('kernel', name), ('support', 'zenbook-a16-support'), ('tracking', 'zenbook-a16-kernel')]:
                subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(roots[kind]),
                                str(output / f'{pkg}_{version}_arm64.deb')], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    metadata = commands.add_parser('metadata')
    metadata.add_argument('bundle', type=Path)
    metadata.add_argument('build_file', type=Path)
    metadata.add_argument('revision', type=int)
    build = commands.add_parser('build')
    build.add_argument('distro', choices=('fedora', 'ubuntu'))
    build.add_argument('bundle', type=Path)
    build.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.command == 'metadata':
        write_metadata(args.bundle, args.build_file, args.revision)
    else:
        build_packages(args.bundle.resolve(), args.output.resolve(), args.distro)


if __name__ == '__main__':
    main()
