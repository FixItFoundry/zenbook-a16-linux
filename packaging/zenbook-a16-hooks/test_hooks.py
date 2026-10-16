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
        prefix = patch.object(artifacts, 'boot_prefix', return_value='')
        prefix.start()
        self.addCleanup(prefix.stop)
        self.release = '7.3.0-ZenbookA16-test-a16pkg1+'
        self.kernel = self.put(f'boot/vmlinuz-{self.release}', b'kernel fixture')
        self.dtb = self.put(f'usr/lib/modules/{self.release}/dtb/qcom/{artifacts.DTB}', b'dtb fixture')
        self.put('usr/lib/zenbook-a16/verify-boot.py',
                 (REPO / 'packaging/omarchy-a16-support/verify-boot.py').read_bytes())
        self.metadata = self.put(f'usr/lib/modules/{self.release}/zenbook-a16-boot.json', b'')
        self.policy = {'package_family': 'zenbook-a16', 'source_tree': 'a' * 40, 'schema': 1, 'kernel_release': self.release, 'dsp_policy': 'pre-root-v1',
                       'kernel_sha256': hashlib.sha256(self.kernel.read_bytes()).hexdigest(),
                       'dtb_sha256': hashlib.sha256(self.dtb.read_bytes()).hexdigest(),
                       'cmdline': ['clk_ignore_unused', 'pd_ignore_unused', 'glymur_pci_skip=5']}
        self.metadata.write_text(json.dumps(self.policy))
        self.put('etc/kernel/cmdline', b'root=UUID=root-device ro glymur_pci_skip=4')
        self.put(f'boot/initrd.img-{self.release}', b'initramfs fixture')
        self.put(f'boot/initramfs-{self.release}.img', b'initramfs fixture')

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

    def test_systemd_loader_copies_normalized_for_separate_and_shared_boot(self):
        for prefix in ('', '/boot'):
            with self.subTest(prefix=prefix):
                entry = self.put('boot/loader/entries/systemd.conf',
                    (f'title Kernel\nversion {self.release}\nlinux /machine-token/{self.release}/linux\n'
                     f'initrd /machine-token/{self.release}/initrd\noptions root=UUID=root ro\n').encode())
                with patch.object(artifacts, 'boot_prefix', return_value=prefix):
                    artifacts.update_bls(self.root, self.release)
                text = entry.read_text()
                self.assertIn(f'linux {prefix}/vmlinuz-{self.release}\n', text)
                self.assertIn(f'initrd {prefix}/initramfs-{self.release}.img\n', text)
                self.assertIn(f'devicetree {prefix}/dtbs/{self.release}/qcom/{artifacts.DTB}\n', text)
                self.assertNotIn('machine-token', text)

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

    def test_generation_keeps_legacy_unmanifested_kernel_as_distro_fallback(self):
        old = '7.3.0-ZenbookA16-recorded+'
        (self.root / f'usr/lib/modules/{old}').mkdir(parents=True)
        kernel = self.put(f'boot/vmlinuz-{old}', b'working old kernel')
        old_entry = self.put('boot/loader/entries/old.conf', f'linux /vmlinuz-{old}\n'.encode())
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['boot-uuid', 'ext2', '/boot']):
            output = artifacts.grub_entries(self.root)
        self.assertIn(self.release, output)
        self.assertNotIn(old, output)
        self.assertEqual(kernel.read_bytes(), b'working old kernel')
        self.assertEqual(old_entry.read_bytes(), f'linux /vmlinuz-{old}\n'.encode())
        with self.assertRaises(OSError):
            artifacts.managed(self.root, old)

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

    def test_two_managed_versions_keep_old_boot_artifacts_and_loader_default(self):
        self.bls()
        artifacts.update_bls(self.root, self.release)
        loader = self.put('boot/loader/loader.conf', b'default test.conf\n')
        old = {path: path.read_bytes() for path in (self.root / 'boot').rglob('*') if path.is_file()}
        new = self.release.replace('a16pkg1', 'a16pkg2')
        self.put(f'boot/vmlinuz-{new}', self.kernel.read_bytes())
        self.put(f'boot/initrd.img-{new}', b'new initramfs')
        self.put(f'boot/initramfs-{new}.img', b'new initramfs')
        self.put(f'usr/lib/modules/{new}/dtb/qcom/{artifacts.DTB}', self.dtb.read_bytes())
        self.put(f'usr/lib/modules/{new}/zenbook-a16-boot.json', json.dumps(self.policy | {'kernel_release': new}).encode())
        self.put('boot/loader/entries/new.conf',
                 f'title New\nversion {new}\nlinux /vmlinuz-{new}\noptions root=UUID=root ro\n'.encode())
        artifacts.update_bls(self.root, new)
        for path, content in old.items():
            self.assertEqual(path.read_bytes(), content)
        self.assertEqual(loader.read_bytes(), b'default test.conf\n')
        self.assertTrue((self.root / f'boot/dtb-{new}').is_file())
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['boot-uuid', 'ext2', '/boot']):
            entries = artifacts.grub_entries(self.root)
        self.assertEqual(entries.count('menuentry '), 4)
        self.assertIn(f"--id 'zenbook-a16-{self.release}'", entries)
        self.assertIn(f"--id 'zenbook-a16-{new}'", entries)


class InitramfsModules(unittest.TestCase):
    def test_dracut_core_required_platform_optional_and_hostonly_scoped(self):
        source = HERE / 'fedora/90zenbook-a16/module-setup.sh'
        script = r'''
source "$1"
a16_managed_kernel() { return 0; }
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


class DefaultPreservation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        guard = patch.object(artifacts, 'reject_shared_btrfs_boot')
        guard.start()
        self.addCleanup(guard.stop)
        self.put('boot/vmlinuz-old', 'old kernel')
        self.put('boot/initrd.img-old', 'old initramfs')
        self.put('boot/dtb-old', 'old dtb')
        self.put('etc/default/grub', 'GRUB_DEFAULT=0\n')
        self.old = "menuentry 'Old Linux' $menuentry_id_option 'old-id' {\n linux /boot/vmlinuz-old root=UUID=installed-root ro quiet $vt_handoff\n initrd /boot/initrd.img-old\n}\n"
        self.put('boot/grub/grub.cfg', self.old)

    def put(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_ubuntu_numeric_default_pinned_across_two_versions(self):
        old_files = {path: path.read_bytes() for path in (self.root / 'boot').glob('*') if path.is_file()}
        state = artifacts.preserve_default(self.root, 'ubuntu')
        snapshot = (self.root / 'var/lib/zenbook-a16/rollback.json').read_bytes()
        self.assertEqual(state['entry_id'], 'old-id')
        self.assertEqual((self.root / 'etc/default/grub').read_text(), 'GRUB_DEFAULT=0\n')
        self.assertEqual((self.root / 'etc/kernel/cmdline').read_text(), 'root=UUID=installed-root ro quiet\n')
        self.put('boot/vmlinuz-new', 'new kernel')
        self.put('boot/grub/grub.cfg', "menuentry 'New' --id 'new-id' {\n linux /boot/vmlinuz-new root=UUID=installed-root ro\n}\n" + self.old)
        artifacts.restore_default(self.root)
        artifacts.preserve_default(self.root, 'ubuntu')
        self.assertEqual(artifacts.grub_default(self.root), 'old-id')
        self.assertEqual((self.root / 'var/lib/zenbook-a16/rollback.json').read_bytes(), snapshot)
        for path, value in old_files.items():
            self.assertEqual(path.read_bytes(), value)

    def test_ubuntu_simple_id_pins_equivalent_versioned_entry(self):
        simple = self.old.replace('old-id', 'gnulinux-simple-bootuuid')
        versioned = self.old.replace('old-id', 'gnulinux-old-advanced-bootuuid')
        advanced = "submenu 'Advanced' --id 'gnulinux-advanced-bootuuid' {\n" + versioned + '}\n'
        self.put('boot/grub/grub.cfg', simple + advanced)
        state = artifacts.preserve_default(self.root, 'ubuntu')
        self.assertEqual(state['entry_id'], 'gnulinux-advanced-bootuuid>gnulinux-old-advanced-bootuuid')
        self.put('boot/vmlinuz-new', 'new kernel')
        self.put('boot/grub/grub.cfg', simple.replace('vmlinuz-old', 'vmlinuz-new') + advanced)
        artifacts.restore_default(self.root)
        self.assertEqual(artifacts.grub_default(self.root), state['entry_id'])

    def test_ubuntu_unversioned_simple_default_without_equivalent_refused(self):
        self.put('boot/grub/grub.cfg', self.old.replace('old-id', 'gnulinux-simple-bootuuid'))
        with self.assertRaisesRegex(ValueError, 'versioned Advanced'):
            artifacts.preserve_default(self.root, 'ubuntu')
        self.assertFalse((self.root / 'var/lib/zenbook-a16/rollback.json').exists())

    def test_later_grub_override_refused_before_snapshot(self):
        self.put('etc/default/grub.d/zz-override.cfg', 'GRUB_DEFAULT=0\n')
        with self.assertRaisesRegex(ValueError, 'later GRUB drop-in'):
            artifacts.preserve_default(self.root, 'ubuntu')
        self.assertFalse((self.root / 'var/lib/zenbook-a16/rollback.json').exists())

    def test_fedora_missing_cmdline_refused_before_snapshot(self):
        with self.assertRaisesRegex(ValueError, '/etc/kernel/cmdline'):
            artifacts.preserve_default(self.root, 'fedora')
        self.assertFalse((self.root / 'var/lib/zenbook-a16/rollback.json').exists())

    def test_ubuntu_saved_default_restored(self):
        self.put('etc/default/grub', 'GRUB_DEFAULT=saved\n')
        with patch.object(artifacts.subprocess, 'check_output', return_value='saved_entry=old-id\n'), patch.object(artifacts.subprocess, 'run'):
            artifacts.preserve_default(self.root, 'ubuntu')
        with patch.object(artifacts.subprocess, 'run') as run:
            artifacts.restore_default(self.root)
        self.assertEqual(run.call_args.args[0], ['grub-editenv', '/boot/grub/grubenv', 'set', 'saved_entry=old-id'])

    def test_changed_saved_default_is_not_silently_overridden(self):
        self.put('etc/default/grub', 'GRUB_DEFAULT=saved\n')
        with patch.object(artifacts.subprocess, 'check_output', return_value='saved_entry=old-id\n'), patch.object(artifacts.subprocess, 'run'):
            artifacts.preserve_default(self.root, 'ubuntu')
        snapshot = (self.root / 'var/lib/zenbook-a16/rollback.json').read_bytes()
        with patch.object(artifacts.subprocess, 'check_output', return_value='saved_entry=user-changed-id\n'), patch.object(artifacts.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'saved boot default changed'):
                artifacts.preserve_default(self.root, 'ubuntu')
            run.assert_not_called()
        self.assertEqual((self.root / 'var/lib/zenbook-a16/rollback.json').read_bytes(), snapshot)

    def test_ubuntu_submenu_index_becomes_stable_id_path(self):
        self.put('etc/default/grub', 'GRUB_DEFAULT="1>0"\n')
        self.put('boot/grub/grub.cfg', self.old + "submenu 'Advanced' --id 'advanced-id' {\n" + self.old + '}\n')
        state = artifacts.preserve_default(self.root, 'ubuntu')
        self.assertEqual(state['entry_id'], 'advanced-id>old-id')
        artifacts.restore_default(self.root)

    def test_existing_kernel_cmdline_preserved(self):
        self.put('etc/kernel/cmdline', 'root=UUID=user-choice rw\n')
        artifacts.preserve_default(self.root, 'ubuntu')
        self.assertEqual((self.root / 'etc/kernel/cmdline').read_text(), 'root=UUID=user-choice rw\n')

    def test_ambiguous_or_dynamic_defaults_fail_before_snapshot(self):
        for value in ('"$DEFAULT"', '99', 'unknown-id'):
            with self.subTest(value=value):
                self.put('etc/default/grub', 'GRUB_DEFAULT=' + value + '\n')
                with self.assertRaises(ValueError):
                    artifacts.preserve_default(self.root, 'ubuntu')
                self.assertFalse((self.root / 'var/lib/zenbook-a16/rollback.json').exists())

    def test_missing_rollback_kernel_refused(self):
        artifacts.preserve_default(self.root, 'ubuntu')
        (self.root / 'boot/vmlinuz-old').unlink()
        with self.assertRaisesRegex(ValueError, 'rollback kernel'):
            artifacts.preserve_default(self.root, 'ubuntu')

    def test_fedora_default_identity_preserved(self):
        self.put('etc/kernel/cmdline', 'root=UUID=old ro\n')
        info = 'index=0\nkernel="/boot/vmlinuz-old"\nargs="root=UUID=old ro"\nid="old-id"\n'
        with patch.object(artifacts.subprocess, 'check_output', side_effect=['/boot/vmlinuz-old\n', info]):
            state = artifacts.preserve_default(self.root, 'fedora')
        self.assertEqual(state['entry_id'], 'old-id')
        with patch.object(artifacts.subprocess, 'check_output', side_effect=[info, '/boot/vmlinuz-old\n']), patch.object(artifacts.subprocess, 'run') as run:
            artifacts.restore_default(self.root)
        self.assertEqual(run.call_args.args[0], ['grubby', '--set-default', '/boot/vmlinuz-old'])


class KernelScope(unittest.TestCase):
    def test_boot_prefix_matches_real_root_or_separate_boot_surface(self):
        for target, prefix in (('/boot', ''), ('/', '/boot')):
            with patch.object(artifacts.subprocess, 'check_output', return_value=target + '\n'):
                self.assertEqual(artifacts.boot_prefix(Path('/')), prefix)
        with patch.object(artifacts.subprocess, 'check_output', return_value='/boot/efi\n'):
            with self.assertRaisesRegex(ValueError, 'unsupported boot mount'):
                artifacts.boot_prefix(Path('/'))

    def test_stock_kernel_is_silent_noop(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse(artifacts.managed(root, '6.17.1-stock'))
            self.assertIsNone(artifacts.stage(root, '6.17.1-stock'))
            self.assertIsNone(artifacts.update_bls(root, '6.17.1-stock'))
            with patch.object(artifacts.subprocess, 'check_output') as command:
                self.assertEqual(artifacts.grub_entries(root), '')
                command.assert_not_called()

    def test_named_managed_kernel_cannot_skip_missing_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for release in ('7.3.0-ZenbookA16-20261013+', '7.3.0-next-a16pkg1+'):
                with self.subTest(release=release), self.assertRaises(OSError):
                    artifacts.managed(root, release)

    def test_stock_and_missing_managed_build_and_postinst_hooks(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ('fedora/95-zenbook-a16.install', 'ubuntu/zz-zenbook-a16', 'ubuntu/initramfs-hook-zenbook-a16'):
                text = (HERE / name).read_text()
                # Use the real metadata predicate with a fixture module tree; all further commands must remain unreachable.
                prefix = 'python3() { command python3 ' + str(HERE / 'boot-artifacts.py') + ' managed "$3" ' + directory + '; }\n'
                for release, success in (('6.17.1-stock', True), ('7.3.0-ZenbookA16-missing+', False)):
                    args = ['add', release] if name.startswith('fedora') else [release]
                    result = subprocess.run(['bash', '-c', prefix + text, 'test', *args], text=True,
                                            capture_output=True, env=os.environ | {'version': release})
                    self.assertEqual(result.returncode == 0, success, result.stderr)
                    if success:
                        self.assertEqual(result.stdout + result.stderr, '')

    def test_dracut_config_does_not_force_module_for_stock_kernels(self):
        text = (HERE / 'fedora/99-zenbook-a16.conf').read_text()
        active = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))
        self.assertNotIn('add_dracutmodules', active)
        self.assertNotIn('early_microcode', active)

    def test_dracut_stock_check_excludes_module_even_when_forced_install_is_called(self):
        text = (HERE / 'fedora/90zenbook-a16/module-setup.sh').read_text()
        script = 'python3() { return 4; };\n' + text + '\nkernel=6.17.1-stock\nif check; then exit 89; fi\ninstall\ninstallkernel\n'
        result = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout + result.stderr, '')


class LegacyMigration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        sources = {
            'etc/modprobe.d/zenbook-a16-remoteproc.conf': REPO / 'packaging/omarchy-a16-support/remoteproc-blacklist.conf',
            'etc/grub.d/09_zenbook_a16': HERE / 'ubuntu/09_zenbook_a16',
            'etc/initramfs-tools/scripts/init-premount/zenbook-a16': HERE / 'ubuntu/init-premount-zenbook-a16',
        }
        self.paths = []
        for name, source in sources.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(source.read_bytes())
            self.paths.append(path)

    def run_migration(self, *extra):
        return subprocess.run(['bash', str(HERE / 'migrate-hooks.sh'), '--root', str(self.root), *extra],
                              capture_output=True, text=True)

    def test_known_files_checked_then_retired(self):
        self.assertEqual(self.run_migration('--check').returncode, 0)
        self.assertTrue(all(path.exists() for path in self.paths))
        old_kernel = self.root / 'boot/vmlinuz-old'
        old_kernel.parent.mkdir()
        old_kernel.write_text('working kernel')
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(path.exists() for path in self.paths))
        self.assertEqual(old_kernel.read_text(), 'working kernel')

    def test_modified_legacy_file_prevents_all_removal(self):
        self.paths[1].write_text('# user customization\n')
        result = self.run_migration()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requires review', result.stderr)
        self.assertTrue(all(path.exists() for path in self.paths))
        self.assertEqual(self.paths[1].read_text(), '# user customization\n')

    def test_old_rescue_requires_hard_blacklist_before_any_migration(self):
        for relative, command in (('boot/loader/entries/old-rescue.conf', 'options'),
                                  ('boot/grub/grub.cfg', 'linux /boot/vmlinuz-old'),
                                  ('boot/grub2/grub.cfg', 'linuxefi /vmlinuz-old')):
            with self.subTest(config=relative):
                entry = self.root / relative
                entry.parent.mkdir(parents=True, exist_ok=True)
                content = command + ' root=UUID=root omarchy.a16.dsp=off\n'
                entry.write_text(content)
                result = self.run_migration('--check')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(entry), result.stderr)
                self.assertIn('module_blacklist=qcom_q6v5_pas', result.stderr)
                self.assertTrue(all(path.exists() for path in self.paths))
                self.assertEqual(entry.read_text(), content)
                entry.unlink()

    def test_hard_guarded_rescue_allows_migration_without_entry_rewrite(self):
        entry = self.root / 'boot/grub/grub.cfg'
        entry.parent.mkdir(parents=True)
        content = 'linux /boot/vmlinuz-old root=UUID=root omarchy.a16.dsp=off module_blacklist=other,qcom_q6v5_pas\n'
        entry.write_text(content)
        result = self.run_migration()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(path.exists() for path in self.paths))
        self.assertEqual(entry.read_text(), content)

    def test_legacy_symlink_is_never_removed(self):
        self.paths[1].unlink()
        self.paths[1].symlink_to(self.paths[0])
        self.assertNotEqual(self.run_migration().returncode, 0)
        self.assertTrue(self.paths[1].is_symlink())
        self.assertTrue(all(path.exists() for path in self.paths))


if __name__ == '__main__':
    unittest.main()
