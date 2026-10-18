"""Exercise staged package contents and lifecycle failures without installing anything."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('package', HERE / 'package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class Packages(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bundle = self.root / 'bundle'
        self.bundle.mkdir()
        self.build = self.root / 'build.json'
        self.build.write_text(json.dumps({'release': '7.3.0-rc5-ZenbookA16-20261013-rc5-soc2+',
                                         'promotion_date': '2026-10-14', 'source_tree': 'e' * 40}))
        self.env = os.environ.copy()
        if sys.platform == 'darwin':
            # GNU install -D shim affects only the temporary package tree.
            shim = self.root / 'bin/install'
            shim.parent.mkdir()
            shim.write_text('#!' + sys.executable + '\nimport pathlib,shutil,sys\n'
                            'dest=pathlib.Path(sys.argv[-1]); dest.parent.mkdir(parents=True,exist_ok=True)\n'
                            'shutil.copyfile(sys.argv[-2],dest); dest.chmod(int(sys.argv[1][-3:],8))\n')
            shim.chmod(0o755)
            self.env['PATH'] = str(shim.parent) + os.pathsep + self.env['PATH']

    def fixture(self, revision):
        release = f'7.3.0-rc5-ZenbookA16-20261013-rc5-soc2-a16pkg{revision}+'
        modules = self.bundle / f'lib/modules/{release}'
        (modules / 'build/include/config').mkdir(parents=True)
        (modules / 'build/include/config/kernel.release').write_text(release + '\n')
        (modules / 'build/Makefile').write_text('# generated external-module build headers\n')
        (modules / 'driver.ko').write_bytes(b'signed module fixture')
        image = bytearray(4096)
        image[56:60] = b'ARM\x64'
        struct.pack_into('<Q', image, 16, 8192)
        (self.bundle / f'vmlinuz-{release}').write_bytes(image)
        (self.bundle / package.DTB).write_bytes(b'DTB fixture validated by the DT-tool adapter')
        (self.bundle / f'config-{release}').write_text('CONFIG_TEST=y\n')
        marker = self.bundle / 'usr/share/doc/linux-zenbook-a16/kernel-release'
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(release + '\n')
        package.write_metadata(self.bundle, self.build, revision)
        return release

    def dt_tools(self, args, **kwargs):
        if args[0] == 'dtc':
            return '// fixture\n'
        self.assertEqual(args[0], 'fdtget')
        if args[-1] == 'compatible':
            return 'asus,zenbook-a16-ux3607oa\n' if args[-2] == '/' else 'qcom,soundwire-v3.1.0\n'
        if args[-1] == 'status':
            return 'okay\n'
        return 'qcom,keep-runtime-active\n'

    def stage(self, distro, suffix):
        with patch.dict(os.environ, self.env), patch.object(package.subprocess, 'check_output', side_effect=self.dt_tools):
            return package.stage(self.bundle, self.root / suffix, distro)

    def test_both_formats_include_exact_boot_metadata_and_headers(self):
        release = self.fixture(1)
        for distro in ('fedora', 'ubuntu'):
            with self.subTest(distro=distro):
                roots, name, actual, version = self.stage(distro, distro)
                self.assertEqual(actual, release)
                self.assertEqual(version, '20261014.1')
                modules = roots['kernel'] / f'usr/lib/modules/{release}'
                data = json.loads((modules / 'zenbook-a16-boot.json').read_text())
                self.assertEqual(data['package_family'], 'zenbook-a16')
                self.assertEqual(data['kernel_sha256'], hashlib.sha256((roots['kernel'] / f'boot/vmlinuz-{release}').read_bytes()).hexdigest())
                self.assertTrue((modules / 'build/Makefile').is_file())
                self.assertEqual((modules / 'omarchy-a16-dsp-abi').read_text(), '1\n')
                self.assertTrue((roots['support'] / 'usr/lib/zenbook-a16/package-kernel').is_file())
                self.assertTrue((roots['support'] / 'usr/lib/zenbook-a16/activate-hardware').is_file())
                self.assertTrue((roots['support'] / 'usr/share/omarchy-a16/51-glymur-ucm.conf').is_file())
                self.assertTrue((roots['support'] / 'usr/share/alsa/ucm2/conf.d/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA.conf').is_file())
                self.assertTrue((roots['support'] / 'usr/share/alsa/ucm2/conf.d/glymur/ASUSTeKCOMPUTERINC.-ZenbookA16UX3607OA-1.0-UX3607OA.conf').is_symlink())
                self.assertFalse((roots['support'] / 'usr/lib/firmware').exists())
                if distro == 'fedora':
                    recipe = package.rpm_spec(roots, name, release, version)
                    self.assertIn('Requires(pre): zenbook-a16-support >= %{version}', recipe)
                    self.assertIn('Provides: installonlypkg(kernel)', recipe)
                    self.assertIn('Provides: zenbook-a16-dsp-abi = 1', recipe)
                    self.assertIn('Provides: omarchy-a16-dsp-abi = 1', recipe)
                    self.assertNotIn('kernel-uname-r =', recipe)
                    self.assertNotIn('Obsoletes:', recipe)
                    self.assertIn('%global __os_install_post %{nil}', recipe)
                    self.assertIn('%pre -n zenbook-a16-support\nbash -s -- --check', recipe)
                    self.assertIn('%post -n zenbook-a16-support\n/usr/lib/zenbook-a16/migrate-hooks\n/usr/lib/zenbook-a16/activate-hardware', recipe)
                else:
                    package.debian_controls(roots, name, release, version)
                    control = (roots['kernel'] / 'DEBIAN/control').read_text()
                    self.assertIn('Pre-Depends: zenbook-a16-support (>= 20261014.1)', control)
                    self.assertIn('Provides: zenbook-a16-dsp-abi (= 1), omarchy-a16-dsp-abi (= 1)', control)
                    self.assertNotIn('Replaces:', control)
                    self.assertIn('NeverAutoRemove', (roots['support'] / 'etc/apt/apt.conf.d/01zenbook-a16-keep-kernels').read_text())
                    for script in ('preinst', 'postinst', 'prerm', 'postrm'):
                        subprocess.run(['sh', '-n', str(roots['kernel'] / 'DEBIAN' / script)], check=True)
                    for script in ('preinst', 'postinst'):
                        subprocess.run(['sh', '-n', str(roots['support'] / 'DEBIAN' / script)], check=True)
                    self.assertIn('bash -s -- --check', (roots['support'] / 'DEBIAN/preinst').read_text())
                    self.assertIn('/usr/lib/zenbook-a16/migrate-hooks && /usr/lib/zenbook-a16/activate-hardware', (roots['support'] / 'DEBIAN/postinst').read_text())

    def test_revisions_have_disjoint_kernel_files(self):
        self.fixture(1)
        first = self.stage('fedora', 'first')
        self.fixture(2)
        second = self.stage('fedora', 'second')
        self.assertNotEqual(first[1], second[1])
        files = lambda root: {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() or p.is_symlink()}
        self.assertFalse(files(first[0]['kernel']) & files(second[0]['kernel']))

    def test_tampered_image_config_and_headers_fail_before_staging(self):
        release = self.fixture(1)
        for target in (self.bundle / f'vmlinuz-{release}', self.bundle / f'config-{release}',
                       self.bundle / f'lib/modules/{release}/build/include/config/kernel.release'):
            with self.subTest(target=target.name):
                original = target.read_bytes()
                target.write_bytes(b'wrong')
                with self.assertRaises((ValueError, OSError)):
                    self.stage('fedora', 'bad')
                self.assertFalse((self.root / 'bad').exists())
                target.write_bytes(original)

    def test_external_module_symlink_rejected(self):
        release = self.fixture(1)
        (self.bundle / f'lib/modules/{release}/outside').symlink_to(self.build)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.stage('fedora', 'bad')

    def test_no_baseline_replacement_identity(self):
        self.fixture(1)
        marker = self.bundle / 'usr/share/doc/linux-zenbook-a16/kernel-release'
        marker.write_text(json.loads(self.build.read_text())['release'])
        with self.assertRaisesRegex(ValueError, 'baseline identity'):
            self.stage('fedora', 'bad')


class Lifecycle(unittest.TestCase):
    def test_existing_kernel_artifact_stops_before_firmware_or_boot_changes(self):
        release = '7.3-ZenbookA16-a16pkg1+'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'lifecycle.sh'
            script.write_text((HERE / 'package-kernel.sh').read_text().replace('/usr/lib/', str(root / 'usr/lib') + '/').replace('/boot/', str(root / 'boot') + '/'))
            artifact = root / f'boot/vmlinuz-{release}'
            artifact.parent.mkdir()
            artifact.write_bytes(b'working kernel')
            result = subprocess.run(['bash', str(script), 'pre', 'fedora', release], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('Refusing to replace', result.stderr)
            self.assertEqual(artifact.read_bytes(), b'working kernel')

    def test_running_and_saved_rollback_kernels_cannot_be_removed(self):
        release = '7.3-ZenbookA16-a16pkg1+'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'lifecycle.sh'
            script.write_text((HERE / 'package-kernel.sh').read_text().replace('/var/lib/', str(root / 'var/lib') + '/'))
            uname = root / 'uname'
            uname.write_text('#!/bin/sh\nprintf "%s\\n" "$RUNNING"\n')
            uname.chmod(0o755)
            env = os.environ | {'PATH': str(root) + os.pathsep + os.environ['PATH'], 'RUNNING': release}
            result = subprocess.run(['bash', str(script), 'remove-check', 'ubuntu', release], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('running A16 kernel', result.stderr)
            state = root / 'var/lib/zenbook-a16/rollback.json'
            state.parent.mkdir(parents=True)
            state.write_text(json.dumps({'kernel': '/boot/vmlinuz-' + release}))
            result = subprocess.run(['bash', str(script), 'remove-check', 'ubuntu', release], env=env | {'RUNNING': 'stock'}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('preserved rollback kernel', result.stderr)

    def test_failed_boot_generation_or_removal_restores_default_and_stops(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'package-kernel.sh'
            script.write_text((HERE / 'package-kernel.sh').read_text())
            commands = {'python3': 'echo "$*" >> "$TRACE"; exit 0',
                        'depmod': 'echo depmod >> "$TRACE"',
                        'dracut': 'echo dracut >> "$TRACE"; exit 23',
                        'update-initramfs': 'echo update-initramfs >> "$TRACE"; exit 23',
                        'kernel-install': 'echo kernel-install >> "$TRACE"; exit 91'}
            for name, body in commands.items():
                path = root / name
                path.write_text('#!/bin/sh\n' + body + '\n')
                path.chmod(0o755)
            trace = root / 'trace'
            for action, distro, failure in (('post', 'fedora', 23), ('post', 'ubuntu', 23),
                                            ('remove', 'fedora', 91), ('remove', 'ubuntu', 23)):
                with self.subTest(action=action, distro=distro):
                    trace.write_text('')
                    result = subprocess.run(['bash', str(script), action, distro, '7.3-ZenbookA16-a16pkg1+'],
                        env=os.environ | {'PATH': str(root) + os.pathsep + os.environ['PATH'], 'TRACE': str(trace)}, capture_output=True)
                    self.assertEqual(result.returncode, failure)
                    lines = trace.read_text().splitlines()
                    self.assertIn('restore-default', lines[-1])
                    if action == 'post':
                        self.assertNotIn('kernel-install', lines)

    def test_invalid_release_cannot_reach_native_tools(self):
        for release in ('../bad', '7.3-baseline+', '7.3-a16pkg0+', '7.3-a16pkg1+;bad'):
            result = subprocess.run(['bash', str(HERE / 'package-kernel.sh'), 'post', 'fedora', release], capture_output=True)
            self.assertEqual(result.returncode, 2)


if __name__ == '__main__':
    unittest.main()
