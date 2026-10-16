"""Exercise generated Arch package functions without makepkg or a kernel build."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class ArchPackages(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)

    def prepare(self, revision=None, directory=None):
        output = self.work / (directory or f'package-{revision}')
        arguments = [sys.executable, str(HERE / 'prepare-package.py'), str(output)]
        if revision is not None:
            arguments += ['--pkgrel', str(revision)]
        subprocess.run(arguments, check=True, capture_output=True, text=True)
        return output

    def names(self, recipe):
        result = subprocess.run(['bash', '-c', 'source "$1"; printf "%s\\n" "${pkgname[@]}"',
                                 'test', str(recipe)], check=True, capture_output=True, text=True)
        return result.stdout.splitlines()

    def test_versioned_payloads_and_separate_tracking_packages(self):
        for revision in (2, 3):
            output = self.prepare(revision)
            kernel = f'linux-omarchy-a16-7.2.10-{revision}'
            self.assertEqual(self.names(output / 'PKGBUILD'),
                             [kernel, kernel + '-headers', 'linux-omarchy-a16-tracking',
                              'linux-omarchy-a16-tracking-headers'])
            recipe = (output / 'PKGBUILD').read_text()
            self.assertNotIn('@KERNEL_PACKAGE@', recipe)
            self.assertNotIn('omarchy-a16-dsp-abi=', recipe)
            self.assertNotIn('replaces=', recipe)
            self.assertNotIn('conflicts=', recipe)
            result = subprocess.run(['bash', '-c', 'source "$1"; package_linux-omarchy-a16-tracking; '
                                     'printf "%s\\n" "${depends[@]}"; '
                                     'package_linux-omarchy-a16-tracking-headers; '
                                     'printf "%s\\n" "${depends[@]}"', 'test', str(output / 'PKGBUILD')],
                                    check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.splitlines(), [f'{kernel}=7.2.10-{revision}',
                                                          f'{kernel}-headers=7.2.10-{revision}'])

    def test_generation_is_reproducible_and_checksum_pinned(self):
        first, second = self.prepare(2), self.prepare(2, 'repeat')
        for name in ('PKGBUILD', 'a16-backport.tar.xz'):
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        with tarfile.open(first / 'a16-backport.tar.xz') as archive:
            names = archive.getnames()
            self.assertIn('a16-backport/PKGBUILD.in', names)
            self.assertIn('a16-backport/build.json', names)
            self.assertEqual(len([name for name in names if '/patches/' in name]), 127)
            checksums = archive.extractfile('a16-backport/SHA256SUMS').read().decode()
            for line in checksums.splitlines():
                digest, name = line.split('  ', 1)
                self.assertEqual(hashlib.sha256(archive.extractfile('a16-backport/' + name).read()).hexdigest(), digest)

    def fake_build_tools(self):
        binary = self.work / 'bin'
        binary.mkdir(exist_ok=True)
        programs = {
            'make': '''import os, shutil, sys
from pathlib import Path
args = sys.argv[1:]
options = dict(arg.split('=', 1) for arg in args if '=' in arg)
release = os.environ['A16_TEST_RELEASE']
if 'kernelrelease' in args:
    print(release)
elif 'modules_install' in args:
    modules = Path(options['INSTALL_MOD_PATH']) / 'lib/modules' / release
    modules.mkdir(parents=True)
    (modules / 'modules.builtin').write_text('built-in fixture\\n')
    (modules / 'fixture.ko').write_text(release)
elif 'dtbs_install' in args:
    target = Path(options['INSTALL_DTBS_PATH']) / 'qcom/glymur-asus-zenbook-a16-ux3607oa.dtb'
    target.parent.mkdir(parents=True)
    target.write_bytes(Path(os.environ['srcdir'], 'dtb').read_bytes())
elif 'run-command' in args:
    target = Path(options['KBUILD_RUN_COMMAND'].split()[-1]) / 'include/config/kernel.release'
    target.parent.mkdir(parents=True)
    target.write_text(release)
else:
    raise SystemExit('Unexpected make invocation: ' + repr(args))
''',
            'install': '''import shutil, sys
from pathlib import Path
args = [arg for arg in sys.argv[1:] if not arg.startswith('-')]
if '-d' in sys.argv:
    for name in args:
        Path(name).mkdir(parents=True, exist_ok=True)
else:
    destination = Path(args[-1])
    if any(arg.startswith('-D') for arg in sys.argv):
        destination.parent.mkdir(parents=True, exist_ok=True)
    for name in args[:-1]:
        shutil.copyfile(name, destination / Path(name).name if destination.is_dir() else destination)
''',
            'depmod': '',
            'sha256sum': '''import hashlib, sys
from pathlib import Path
for name in sys.argv[1:]:
    print(hashlib.sha256(Path(name).read_bytes()).hexdigest() + '  ' + name)
''',
        }
        for name, source in programs.items():
            program = binary / name
            program.write_text(f'#!{sys.executable}\n' + source)
            program.chmod(0o755)
        (binary / 'python').symlink_to(sys.executable)
        return binary

    def payload(self, revision, binary, default=False):
        output = self.prepare(None if default else revision)
        source = output / 'src'
        source.mkdir()
        with tarfile.open(output / 'a16-backport.tar.xz') as archive:
            archive.extractall(source, filter='data')
        (source / 'linux-7.2').mkdir()
        (source / 'build/arch/arm64/boot').mkdir(parents=True)
        (source / 'build/arch/arm64/boot/Image').write_bytes(f'kernel fixture {revision}'.encode())
        (source / 'build/.config').write_text(f'CONFIG_REVISION_{revision}=y\n')
        (source / 'build/System.map').write_text(f'map {revision}\n')
        (source / 'dtb').write_bytes(f'dtb fixture {revision}'.encode())
        kernel = f'linux-omarchy-a16-7.2.10-{revision}'
        environment = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'],
                           srcdir=str(source), A16_TEST_RELEASE=f'7.2.10-omarchy-a16-{revision}', CC='true')
        payloads = []
        for name in (kernel, kernel + '-headers'):
            package = output / name
            package.mkdir()
            subprocess.run(['bash', '-e', '-c', 'source "$1"; "package_$2"', 'test',
                            str(output / 'PKGBUILD'), name],
                           env=dict(environment, pkgdir=str(package)), check=True, capture_output=True, text=True)
            payloads.append(package)
        return payloads

    def test_two_revisions_preserve_old_modules_headers_dtbs_and_metadata(self):
        binary = self.fake_build_tools()
        installed = self.work / 'installed'
        for revision in (2, 3):
            for package in self.payload(revision, binary):
                shutil.copytree(package, installed, dirs_exist_ok=True, symlinks=True)
            release = f'7.2.10-omarchy-a16-{revision}'
            kernel = f'linux-omarchy-a16-7.2.10-{revision}'
            modules = installed / 'usr/lib/modules' / release
            metadata = json.loads((modules / 'zenbook-a16-boot.json').read_text())
            dtb = installed / f'boot/dtbs/{kernel}/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb'
            self.assertEqual(metadata['kernel_sha256'], hashlib.sha256((modules / 'vmlinuz').read_bytes()).hexdigest())
            self.assertEqual(metadata['dtb_sha256'], hashlib.sha256(dtb.read_bytes()).hexdigest())
            self.assertEqual(metadata['dsp_policy'], 'omarchy-a16-legacy-v1')
            self.assertEqual(metadata['source_tree'], json.loads((HERE / 'build.json').read_text())['source_tree'])
            self.assertEqual((modules / 'pkgbase').read_text().strip(), kernel)
            self.assertEqual((modules / 'build/include/config/kernel.release').read_text(), release)
            self.assertFalse((modules / 'omarchy-a16-dsp-abi').exists())
            if revision == 2:
                old = {path.relative_to(installed): path.read_bytes() for path in installed.rglob('*') if path.is_file()}
        for name, content in old.items():
            self.assertEqual((installed / name).read_bytes(), content, f'old artifact changed: {name}')
        self.assertTrue((installed / 'usr/src/linux-omarchy-a16-7.2.10-2').is_symlink())
        self.assertTrue((installed / 'usr/src/linux-omarchy-a16-7.2.10-3').is_symlink())

    def test_default_revision_does_not_collide_with_legacy_fixed_package_two(self):
        # These are the paths owned by the previously shipped fixed-name pkgrel 2.
        old_release = '7.2.10-omarchy-a16-2'
        old_files = {
            f'usr/lib/modules/{old_release}/vmlinuz': b'working old kernel',
            f'usr/lib/modules/{old_release}/pkgbase': b'linux-omarchy-a16\n',
            f'usr/lib/modules/{old_release}/build/include/config/kernel.release': old_release.encode(),
            'boot/dtbs/linux-omarchy-a16/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb': b'working old dtb',
            'usr/share/doc/linux-omarchy-a16/kernel-release': old_release.encode(),
            'boot/EFI/Linux/machine_linux-omarchy-a16.efi': b'working old UKI',
        }
        installed = self.work / 'installed'
        for name, content in old_files.items():
            target = installed / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        for package in self.payload(3, self.fake_build_tools(), default=True):
            owned = {str(path.relative_to(package)) for path in package.rglob('*')
                     if path.is_file() or path.is_symlink()}
            self.assertFalse(owned.intersection(old_files))
            shutil.copytree(package, installed, dirs_exist_ok=True, symlinks=True)
        for name, content in old_files.items():
            self.assertEqual((installed / name).read_bytes(), content)
        new_modules = installed / 'usr/lib/modules/7.2.10-omarchy-a16-3'
        self.assertEqual((new_modules / 'pkgbase').read_text().strip(), 'linux-omarchy-a16-7.2.10-3')

    def test_explicit_preset_uses_its_release_dtb_and_limine_prefix(self):
        package, _ = self.payload(2, self.fake_build_tools())
        name = 'linux-omarchy-a16-7.2.10-2'
        release = '7.2.10-omarchy-a16-2'
        config = package / f'usr/lib/modules/{release}/uki.conf'
        self.assertEqual(config.read_text(), '[UKI]\nDeviceTreeAuto=/boot/dtbs/' + name
                         + '/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb\n')
        self.assertFalse((package / 'etc/kernel/uki.conf').exists())
        shared_signing = package / 'etc/kernel/uki.conf'
        shared_signing.parent.mkdir(parents=True)
        signing_bytes = b'[UKI]\nSecureBootPrivateKey=/existing/private-key\n'
        shared_signing.write_bytes(signing_bytes)
        machine = package / 'etc/machine-id'
        machine.write_text('fixturemachine\n')
        preset = package / f'etc/mkinitcpio.d/{name}.preset'
        sandboxed = self.work / 'preset'
        text = preset.read_text()
        for prefix in ('/usr/', '/etc/', '/boot/'):
            text = text.replace(prefix, str(package) + prefix)
        sandboxed.write_text(text)
        override = package / 'etc/default/limine'
        override.parent.mkdir(parents=True)
        for setting, expected in (('', 'fixturemachine'), ('CUSTOM_UKI_NAME=custom', 'custom'),
                                  ('CUSTOM_UKI_NAME=../invalid', 'fixturemachine')):
            override.write_text(setting + '\n')
            result = subprocess.run(['bash', '-c', 'source "$1"; printf "%s\n" "$ALL_kver" '
                                     '"$default_uki" "$default_options"', 'test', str(sandboxed)],
                                    check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.splitlines(),
                             [release, str(package) + f'/boot/EFI/Linux/{expected}_{name}.efi',
                              f'--ukiconfig {package}/usr/lib/modules/{release}/uki.conf'])
            self.assertEqual(shared_signing.read_bytes(), signing_bytes)

    def test_invalid_revision_fails_before_output_creation(self):
        output = self.work / 'invalid'
        result = subprocess.run([sys.executable, str(HERE / 'prepare-package.py'), str(output), '--pkgrel', '0'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('positive', result.stderr)
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
