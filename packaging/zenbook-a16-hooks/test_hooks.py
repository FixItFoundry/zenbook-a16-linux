#!/usr/bin/env python3
"""Fixture-only checks: no mounts, initramfs generation or real DSP startup."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
spec = importlib.util.spec_from_file_location('artifacts', HERE / 'boot-artifacts.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class BootHooks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.release = '7.3.0-a16-test+'
        self.kernel = self.put(f'boot/vmlinuz-{self.release}', b'kernel fixture')
        self.dtb = self.put(f'usr/lib/modules/{self.release}/dtb/qcom/{artifacts.DTB}', b'dtb fixture')
        self.put('usr/lib/zenbook-a16/verify-boot.py',
                 (REPO / 'packaging/omarchy-a16-support/verify-boot.py').read_bytes())
        self.metadata = self.put(f'usr/lib/modules/{self.release}/zenbook-a16-boot.json', b'')
        self.policy = {'schema': 1, 'kernel_release': self.release, 'dsp_policy': 'pre-root-v1',
                       'kernel_sha256': hashlib.sha256(self.kernel.read_bytes()).hexdigest(),
                       'dtb_sha256': hashlib.sha256(self.dtb.read_bytes()).hexdigest(),
                       'cmdline': ['clk_ignore_unused', 'pd_ignore_unused', 'glymur_pci_skip=5']}
        self.metadata.write_text(json.dumps(self.policy))
        self.put('etc/kernel/cmdline', b'root=UUID=root-device ro glymur_pci_skip=4')
        self.put(f'boot/initrd.img-{self.release}', b'initramfs fixture')

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def bls(self):
        return self.put('boot/loader/entries/test.conf',
                        f'title Linux\nversion {self.release}\nlinux /vmlinuz-{self.release}\n'
                        f'initrd /initramfs-{self.release}.img\noptions root=UUID=root ro glymur_pci_skip=4\n'.encode())

    def test_bls_exact_pair_and_rescue_idempotent(self):
        entry = self.bls()
        artifacts.update_bls(self.root, self.release)
        first = entry.read_text()
        rescue = entry.with_name('test-a16-rescue.conf')
        rescue_text = rescue.read_text()
        artifacts.update_bls(self.root, self.release)
        self.assertEqual(entry.read_text(), first)
        self.assertEqual(rescue.read_text(), rescue_text)
        self.assertIn(f'devicetree /dtbs/{self.release}/qcom/{artifacts.DTB}', first)
        self.assertIn('glymur_pci_skip=5', first)
        self.assertNotIn('glymur_pci_skip=4', first)
        self.assertIn('omarchy.a16.dsp=off', rescue_text)
        self.assertEqual((self.root / f'boot/dtb-{self.release}').read_bytes(), self.dtb.read_bytes())

    def test_same_file_staging(self):
        artifacts.stage(self.root, self.release)
        self.dtb.unlink()
        artifacts.stage(self.root, self.release)

    def test_no_bls_entry_rejected(self):
        with self.assertRaisesRegex(ValueError, 'no generated BLS'):
            artifacts.update_bls(self.root, self.release)

    def test_similar_release_not_modified(self):
        entry = self.bls()
        entry.write_text(entry.read_text().replace(self.release, self.release + '-other'))
        with self.assertRaisesRegex(ValueError, 'no generated BLS'):
            artifacts.update_bls(self.root, self.release)
        self.assertNotIn('devicetree', entry.read_text())

    def test_missing_malformed_metadata_rejected_before_entry_mutation(self):
        entry = self.bls()
        original = entry.read_text()
        for bad in (None, '', '{}', '[]', '{'):
            with self.subTest(bad=bad):
                if bad is None:
                    self.metadata.unlink(missing_ok=True)
                else:
                    self.metadata.write_text(bad)
                with self.assertRaises((OSError, ValueError, AttributeError)):
                    artifacts.update_bls(self.root, self.release)
                self.assertEqual(entry.read_text(), original)

    def test_mismatched_identity_rejected(self):
        for field, bad in [('kernel_release', 'wrong'), ('kernel_sha256', '0'*64),
                           ('dtb_sha256', '0'*64), ('dsp_policy', '1'), ('cmdline', ['a', 'a'])]:
            with self.subTest(field=field):
                self.metadata.write_text(json.dumps(self.policy | {field: bad}))
                with self.assertRaises(ValueError):
                    artifacts.stage(self.root, self.release)

    def test_unversioned_dtb_never_fallback(self):
        self.dtb.unlink()
        self.put(f'usr/share/zenbook-a16/dtb/{artifacts.DTB}', b'dtb fixture')
        with self.assertRaises(OSError):
            artifacts.stage(self.root, self.release)

    def test_grub_emits_linked_pair_and_rescue(self):
        artifacts.stage(self.root, self.release)
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['boot-uuid', 'ext2', '/boot']):
            text = artifacts.grub_entries(self.root)
        self.assertTrue(text.startswith('insmod fdt\n'))
        self.assertEqual(text.count('menuentry '), 2)
        self.assertIn(f"--id 'zenbook-a16-{self.release}'", text)
        self.assertIn(f"--id 'zenbook-a16-{self.release}-rescue'", text)
        self.assertIn(f'linux /vmlinuz-{self.release} root=UUID=root-device ro', text)
        self.assertIn(f'devicetree /dtb-{self.release}', text)
        self.assertIn('search --no-floppy --fs-uuid --set=root boot-uuid', text)
        self.assertIn('omarchy.a16.dsp=off', text)
        self.assertNotIn('arm64.nopauth', text)

    def test_missing_verifier_rejected(self):
        (self.root / 'usr/lib/zenbook-a16/verify-boot.py').unlink()
        with self.assertRaises(OSError):
            artifacts.stage(self.root, self.release)

    def test_shared_btrfs_boot_rejected(self):
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['btrfs /@', '/']):
            with self.assertRaisesRegex(ValueError, 'separately mounted /boot'):
                artifacts.reject_shared_btrfs_boot()

    def test_check_and_install_sources(self):
        env = os.environ.copy()
        if sys.platform == 'darwin':
            # Only emulate GNU install's -D on this macOS development host.
            install = self.put('test-bin/install', (
                '#!' + sys.executable + '\nimport pathlib, shutil, sys\n'
                'dest = pathlib.Path(sys.argv[-1])\ndest.parent.mkdir(parents=True, exist_ok=True)\n'
                'shutil.copyfile(sys.argv[-2], dest)\ndest.chmod(int(sys.argv[1][-3:], 8))\n').encode())
            install.chmod(0o755)
            env['PATH'] = str(install.parent) + os.pathsep + env['PATH']
        for distro in ('fedora', 'ubuntu'):
            subprocess.run(['bash', str(HERE / 'install-hooks.sh'), '--root', str(self.root),
                            '--distro', distro, '--check'], check=True, capture_output=True)
            self.assertFalse((self.root / 'etc/grub.d').exists())
            subprocess.run(['bash', str(HERE / 'install-hooks.sh'), '--root', str(self.root),
                            '--distro', distro], check=True, capture_output=True, env=env)
            self.assertEqual((self.root / 'usr/lib/zenbook-a16/dsp-policy.sh').read_text(),
                             (REPO / 'packaging/omarchy-a16-support/initcpio-hook').read_text())

    def test_arch_rejected_without_writes(self):
        result = subprocess.run(['bash', str(HERE / 'install-hooks.sh'), '--root', str(self.root),
                                 '--distro', 'arch'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Omarchy', result.stderr)
        self.assertFalse((self.root / 'etc/mkinitcpio.conf.d').exists())


class InitramfsModules(unittest.TestCase):
    def test_dracut_core_required_platform_optional_and_hostonly_scoped(self):
        source = HERE / 'fedora/90zenbook-a16/module-setup.sh'
        script = r'''
source "$1"
hostonly=yes
instmods() {
    [[ -z $hostonly ]] || exit 81
    if [[ $1 == -c ]]; then
        [[ " $* " == *' qrtr_smd '* ]] || exit 82
        [[ " $* " != *' phy_qcom_qmp_pcie_multiphy '* ]] || exit 83
        [[ ${missing_core:-0} == 0 ]] || return 1
    fi
}
installkernel || exit 84
[[ $hostonly == yes ]] || exit 85
missing_core=1
if installkernel; then exit 86; fi
'''
        subprocess.run(['bash', '-c', script, 'test', str(source)], check=True, capture_output=True)


class DspAdapters(unittest.TestCase):
    def test_shared_policy_all_failure_paths(self):
        # The shared runtime's own fixtures cover ready/crashed/offline/rescue, exact board,
        # driver failure, settle ordering and /root, /sysroot, /new_root mount guards.
        subprocess.run(['bash', str(REPO / 'packaging/omarchy-a16-support/test.sh')], check=True,
                       capture_output=True, text=True)

    def test_adapter_runtime_uses_shared_readiness_rescue_and_board_gate(self):
        for name in ('fedora/90zenbook-a16/zenbook-a16-pre-udev.sh', 'ubuntu/init-premount-zenbook-a16'):
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                policy = (REPO / 'packaging/omarchy-a16-support/initcpio-hook').read_text()
                for old, new in (('/sys/firmware/devicetree/base/compatible', 'compatible'),
                                 ('/sys/class/remoteproc', 'remote'), ('/proc/mounts', 'mounts')):
                    policy = policy.replace(old, str(root / new))
                (root / 'policy').write_text(policy)
                for number, processor, state in ((0, 'adsp', 'running'), (1, 'cdsp', 'running'), (2, 'soccp', 'attached')):
                    remote = root / f'remote/remoteproc{number}'
                    remote.mkdir(parents=True)
                    (remote / 'name').write_text(processor)
                    (remote / 'state').write_text(state)
                adapter = (HERE / name).read_text().replace('. /lib/dracut-lib.sh', ':')
                adapter = adapter.replace('/usr/lib/zenbook-a16/dsp-policy.sh', str(root / 'policy'))
                adapter = adapter.replace('/proc/cmdline', str(root / 'cmdline'))
                adapter = '\n'.join(line for line in adapter.splitlines() if line != 'run_hook')
                for mode in ('ready', 'rescue', 'other-board', 'missing-board', 'module-failure', 'not-ready', 'settle-failure', 'root-mounted'):
                    with self.subTest(adapter=name, mode=mode):
                        (root / 'compatible').write_bytes(b'asus,zenbook-a16-ux3607oa\0qcom,glymur\0')
                        (root / 'cmdline').write_text('omarchy.a16.dsp=off' if mode == 'rescue' else '')
                        (root / 'mounts').write_text('/dev/sda /root ext4 rw 0 0\n' if mode == 'root-mounted' else '')
                        (root / 'remote/remoteproc1/state').write_text('offline' if mode == 'not-ready' else 'running')
                        if mode == 'other-board':
                            (root / 'compatible').write_bytes(b'qcom,glymur\0')
                        if mode == 'missing-board':
                            (root / 'compatible').unlink()
                        setup = """
info() { :; }; warn() { :; }; sleep() { :; }
getarg() { printf '%s' "$DSP_MODE"; }
"""
                        checks = """
modprobe() { echo "load:$*"; test "$MODE" != module-failure; }
udevadm() { echo settle; test "$MODE" != settle-failure; }
a16_emergency() { echo "emergency:$*"; exit 29; }
run_hook
echo finished
"""
                        result = subprocess.run(['sh', '-c', setup + adapter + checks], text=True,
                                                capture_output=True, env=os.environ | {'MODE': mode, 'DSP_MODE': 'off' if mode == 'rescue' else ''})
                        if mode in ('module-failure', 'not-ready', 'settle-failure', 'root-mounted'):
                            self.assertEqual(result.returncode, 29)
                            self.assertNotIn('finished', result.stdout)
                            self.assertIn('emergency:', result.stdout)
                        else:
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertIn('finished', result.stdout)
                        if mode in ('rescue', 'other-board', 'missing-board', 'root-mounted'):
                            self.assertNotIn('load:', result.stdout)
                        if mode == 'ready':
                            self.assertIn('settle', result.stdout)

    def test_adapter_emergencies_never_resume_root_mount(self):
        for name in ('fedora/90zenbook-a16/zenbook-a16-pre-udev.sh', 'ubuntu/init-premount-zenbook-a16'):
            with self.subTest(adapter=name):
                text = (HERE / name).read_text()
                text = '\n'.join(line for line in text.splitlines()
                                 if not line.startswith('. ') and line != 'run_hook')
                text = text.replace('/bin/sh -i </dev/console >/dev/console 2>&1', 'true')
                script = 'warn() { :; }; info() { :; };\n' + text + '\na16_emergency test\nexit 93\n'
                with self.assertRaises(subprocess.TimeoutExpired):
                    subprocess.run(['sh', '-c', script], timeout=0.1, capture_output=True)


if __name__ == '__main__':
    unittest.main()
