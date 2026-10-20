#!/usr/bin/env python3
"""Installer regression checks using temporary files and command stubs only."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ISO = Path(__file__).resolve().parent


class InstallSafety(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def shell(self, script, body, *args):
        return subprocess.run(['bash', '-c', 'source "$1"; shift; ' + body,
                               'test', str(ISO / script), *map(str, args)],
                              text=True, capture_output=True)

    def modules(self):
        source = self.root / 'modules/k'
        source.mkdir(parents=True)
        (source / 'driver.ko').write_text('module')
        (source / 'zenbook-a16-boot.json').write_text('build metadata')
        (source / 'build').symlink_to('/not-in-installed-image')
        link = self.root / 'source-link'
        link.symlink_to(source, target_is_directory=True)
        return link

    def test_module_symlink_and_existing_destination(self):
        source = self.modules()
        destination = self.root / 'target/lib/modules/k'
        destination.mkdir(parents=True)
        (destination / 'existing').write_text('keep')
        result = self.shell('zenbook-install-to-disk.sh', 'copy_modules "$1" "$2"', source, destination)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(destination.is_symlink())
        self.assertEqual((destination / 'driver.ko').read_text(), 'module')
        self.assertEqual((destination / 'existing').read_text(), 'keep')
        self.assertFalse((destination / 'k').exists())
        self.assertFalse((destination / 'build').is_symlink())
        self.assertFalse((destination / 'zenbook-a16-dsp-abi').exists())

    def test_module_destination_symlink_is_rejected(self):
        source = self.modules()
        destination = self.root / 'destination'
        destination.symlink_to(self.root / 'elsewhere')
        result = self.shell('zenbook-install-to-disk.sh', 'copy_modules "$1" "$2"', source, destination)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'elsewhere').exists())

    def test_live_module_copy_is_repeatable(self):
        source = self.modules()
        (self.root / 'mods').mkdir()
        (self.root / 'mods/k').symlink_to(source, target_is_directory=True)
        result = self.shell('build-live-images.sh',
                            'MODS="$1/mods"; KREL=k; addmods "$1/live"; addmods "$1/live"', self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'live/lib/modules/k/driver.ko').read_text(), 'module')
        self.assertFalse((self.root / 'live/lib/modules/k/k').exists())

    def test_bundle_staging_copies_module_contents_without_forging_abi(self):
        self.modules()
        for name in ('Image', 'board.dtb'):
            (self.root / name).write_text(name)
        (self.root / 'no-repo/iso').mkdir(parents=True)
        shutil.copy(ISO / 'glymur-fetch-firmware.sh', self.root / 'no-repo/iso')
        result = self.shell('build-live-images.sh', '''
            MODS="$1/modules"; KREL=k; VM="$1/Image"; DTB="$1/board.dtb"
            FW="$1/no-fw"; REPO="$1/no-repo"; STAGE="$1/no-stage"
            stage_bundle_rootfs "$1/live"; stage_bundle_rootfs "$1/live"
        ''', self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        bundle = self.root / 'live/usr/share/zenbook-a16/bundle'
        self.assertEqual((bundle / 'lib/modules/k/driver.ko').read_text(), 'module')
        self.assertFalse((bundle / 'modules/k/k').exists())
        self.assertEqual((bundle / 'modules/k/zenbook-a16-boot.json').read_text(), 'build metadata')
        self.assertFalse((bundle / 'modules/k/omarchy-a16-dsp-abi').exists())
        self.assertFalse((bundle / 'modules/k/zenbook-a16-dsp-abi').exists())

    def test_distro_root_options_are_preserved(self):
        directory = self.root / 'boot/loader/entries'
        directory.mkdir(parents=True)
        expected = 'root=UUID=1234 ro rootflags=subvol=@ quiet'
        (directory / 'existing.conf').write_text('options ' + expected + '\n')
        result = self.shell('zenbook-install-to-disk.sh', 'target="$1"; read_target_cmdline', self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), expected)
        (directory / 'existing.conf').write_text('options root=$kernelopts\n')
        result = self.shell('zenbook-install-to-disk.sh', 'target="$1"; read_target_cmdline', self.root)
        self.assertNotEqual(result.returncode, 0)

    def test_missing_or_live_root_command_line_is_rejected(self):
        directory = self.root / 'etc/kernel'
        directory.mkdir(parents=True)
        (directory / 'cmdline').write_text('root=live:LABEL=GLYMURLIVE rd.live.image\n')
        result = self.shell('zenbook-install-to-disk.sh', 'target="$1"; read_target_cmdline', self.root)
        self.assertNotEqual(result.returncode, 0)

    def test_boot_layout_rejects_shared_subvolume_but_accepts_top_level(self):
        for mount, fsroot, allowed in [('ROOT', '/@', False), ('BOOT', '/', True), ('ROOT', '/', True)]:
            with self.subTest(mount=mount, fsroot=fsroot):
                result = self.shell('zenbook-install-to-disk.sh', '''
                    target="$1"; mount_kind="$2"; fsroot="$3"
                    findmnt() {
                        if [[ "$*" == *FSROOT* ]]; then echo "$fsroot"
                        elif [[ "$mount_kind" == BOOT ]]; then echo "$target/boot"
                        else echo "$target"; fi
                    }
                    check_boot_layout
                ''', self.root, mount, fsroot)
                self.assertEqual(result.returncode == 0, allowed, result.stderr)

    def package_fixture(self, distro):
        directory = self.root / ('rpms' if distro == 'fedora' else 'debs')
        directory.mkdir()
        extension = 'rpm' if distro == 'fedora' else 'deb'
        payload = 'kernel-zenbook-a16-k' if distro == 'fedora' else 'linux-image-k'
        for name in ('zenbook-a16-support', payload, 'zenbook-a16-kernel'):
            (directory / f'{name}.{extension}').write_text('package fixture')
        return directory

    def test_package_discovery_includes_support_payload_and_meta(self):
        for distro in ('fedora', 'ubuntu'):
            with self.subTest(distro=distro):
                directory = self.package_fixture(distro)
                result = self.shell('zenbook-install-to-disk.sh', '''
                    BUNDLE="$1"; DISTRO="$2"; KREL=k; target="$1/target"
                    rpm() { basename "$4" .rpm; }
                    dpkg-deb() { basename "$2" .deb; }; dpkg() { :; }
                    discover_kernel_packages
                    printf '%s\n' "${package_files[@]}"
                ''', self.root, distro)
                self.assertEqual(result.returncode, 0, result.stderr)
                files = result.stdout.splitlines()
                self.assertEqual(len(files), 3)
                self.assertIn('zenbook-a16-support', files[0])
                self.assertIn('zenbook-a16-kernel', files[2])
                shutil.rmtree(directory)

    def test_unexpected_and_accumulated_package_sets_are_rejected(self):
        directory = self.package_fixture('fedora')
        (directory / 'unrelated.rpm').write_text('unexpected package')
        result = self.shell('zenbook-install-to-disk.sh',
                            'BUNDLE="$1"; DISTRO=fedora; KREL=k; discover_kernel_packages', self.root)
        self.assertNotEqual(result.returncode, 0)
        (directory / 'unrelated.rpm').unlink()
        result = self.shell('zenbook-install-to-disk.sh', '''
            BUNDLE="$1"; DISTRO=fedora; KREL=another-release
            rpm() { basename "$4" .rpm; }
            discover_kernel_packages
        ''', self.root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unexpected package', result.stderr)

    def test_existing_release_is_rejected_and_old_release_preserved(self):
        paths = ('boot/vmlinuz-k', 'boot/config-k', 'boot/dtb-k', 'boot/glymur/k.dtb', 'boot/dtbs/k',
                 'boot/initramfs-k.img', 'boot/initrd.img-k', 'lib/modules/k', 'usr/lib/modules/k')
        for index, path in enumerate(paths):
            with self.subTest(path=path):
                target = self.root / str(index)
                existing = target / path
                existing.parent.mkdir(parents=True)
                existing.write_text('working artifact')
                result = self.shell('zenbook-install-to-disk.sh',
                                    'target="$1"; KREL=k; check_release_destinations', target)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(existing.read_text(), 'working artifact')
        target = self.root / 'new-target'
        old = target / 'boot/vmlinuz-old-release'
        old.parent.mkdir(parents=True)
        old.write_text('old kernel')
        result = self.shell('zenbook-install-to-disk.sh',
                            'target="$1"; KREL=k; check_release_destinations', target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(old.read_text(), 'old kernel')

    def test_package_failures_abort(self):
        for distro, command in [('fedora', 'rpm'), ('ubuntu', 'chroot')]:
            with self.subTest(distro=distro):
                result = self.shell('zenbook-install-to-disk.sh',
                                    f'target="$1"; DISTRO={distro}; package_files=(support payload meta); target_package_files=(/mnt/support /mnt/payload /mnt/meta); '
                                    f'{command}() {{ return 23; }}; '
                                    'install_kernel_packages; echo SUCCESS', self.root)
                self.assertEqual(result.returncode, 23)
                self.assertNotIn('SUCCESS', result.stdout)

    def test_package_dry_run_fails_before_any_target_writes(self):
        for distro in ('fedora', 'ubuntu'):
            with self.subTest(distro=distro):
                stage = self.root / distro
                stage.mkdir()
                directory = self.package_fixture(distro)
                bundle = stage / 'bundle'
                bundle.mkdir()
                directory.rename(bundle / directory.name)
                scripts = stage / 'iso'
                scripts.mkdir()
                shutil.copy(ISO / 'zenbook-install-to-disk.sh', scripts)
                (bundle / 'lib/modules/k').mkdir(parents=True)
                for filename in ('vmlinuz-k', 'glymur-asus-zenbook-a16-ux3607oa.dtb'):
                    (bundle / filename).write_text('build artifact')
                hooks = bundle / 'packaging/zenbook-a16-hooks/install-hooks.sh'
                hooks.parent.mkdir(parents=True)
                hooks.write_text('#!/bin/bash\nexit 0\n')
                hooks.chmod(0o755)
                verifier = bundle / 'packaging/omarchy-a16-support/verify-boot.py'
                verifier.parent.mkdir(parents=True)
                verifier.write_text('pass\n')
                (bundle / 'firmware/qcom').mkdir(parents=True)
                (bundle / 'glymur-fetch-firmware.sh').write_text('#!/bin/bash\nexit 0\n')
                target = stage / 'target'
                (target / 'etc/kernel').mkdir(parents=True)
                (target / 'mnt').mkdir()
                (target / 'etc/os-release').write_text(f'ID={distro}\n')
                (target / 'etc/kernel/cmdline').write_text('root=UUID=original ro\n')
                before = sorted(str(path.relative_to(target)) for path in target.rglob('*'))
                trace = stage / 'trace'
                result = subprocess.run(['bash', '-c', '''
                    source "$1"
                    trace="$3"
                    id() { echo 0; }; uname() { echo aarch64; }
                    mountpoint() { [[ "$2" != "$target/mnt" ]]; }
                    chroot() { if [[ "$2" == apt-get && "$3" == --simulate ]]; then return 37; fi; }
                    dtc() { :; }; fdtget() { :; }
                    findmnt() { if [[ "$*" == *FSROOT* ]]; then echo /; else echo "$target"; fi; }
                    mount() { printf 'mount %s\n' "$*" >> "$trace"; }
                    umount() { printf 'umount %s\n' "$*" >> "$trace"; }
                    rpm() { if [[ "$1" == -qp ]]; then basename "$4" .rpm; else return 37; fi; }
                    dpkg-deb() { basename "$2" .deb; }
                    KREL=k
                    main "$2"
                ''', 'test', str(scripts / 'zenbook-install-to-disk.sh'), str(target), str(trace)],
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 37, result.stderr)
                if distro == 'ubuntu':
                    operations = trace.read_text().splitlines()
                    self.assertEqual(len(operations), 3)
                    self.assertIn('remount,bind,ro', operations[1])
                    self.assertTrue(operations[2].startswith('umount '))
                    self.assertTrue(all(str(target / 'mnt') in operation for operation in operations))
                else:
                    self.assertFalse(trace.exists())
                self.assertEqual(sorted(str(path.relative_to(target)) for path in target.rglob('*')), before)
                self.assertEqual((target / 'etc/kernel/cmdline').read_text(), 'root=UUID=original ro\n')

    def test_ubuntu_package_staging_refuses_a_busy_mnt(self):
        target = self.root / 'target'
        (target / 'mnt').mkdir(parents=True)
        (target / 'mnt/existing-data').write_text('preserve')
        result = self.shell('zenbook-install-to-disk.sh', '''
            target="$1"; BUNDLE="$1/bundle"; package_files=(support payload meta)
            mountpoint() { return 1; }
            mount() { echo UNEXPECTED_MOUNT; return 99; }
            bind_package_directory
        ''', target)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('UNEXPECTED_MOUNT', result.stdout)
        self.assertEqual((target / 'mnt/existing-data').read_text(), 'preserve')

    def test_initramfs_and_boot_failures_abort_before_success(self):
        for distro, failing in [('fedora', 'dracut'), ('fedora', 'kernel-install'),
                                ('fedora', 'grub2-mkconfig'), ('ubuntu', 'update-initramfs'),
                                ('ubuntu', '/etc/kernel/postinst.d/zz-zenbook-a16')]:
            with self.subTest(distro=distro, failing=failing):
                result = self.shell('zenbook-install-to-disk.sh', '''
                    target="$1"; DISTRO="$2"; KREL=k; failing="$3"
                    chroot() { [[ "$2" != "$failing" ]] || return 29; }
                    configure_boot; echo SUCCESS
                ''', self.root, distro, failing)
                self.assertEqual(result.returncode, 29, result.stderr)
                self.assertNotIn('SUCCESS', result.stdout)

    def test_missing_and_failed_verifier_prevent_success(self):
        for present in (False, True):
            with self.subTest(present=present):
                if present:
                    verifier = self.root / 'usr/lib/zenbook-a16/verify-boot.py'
                    verifier.parent.mkdir(parents=True)
                    verifier.write_text('verifier')
                result = self.shell('zenbook-install-to-disk.sh', '''
                    target="$1"; KREL=k; bootloader_check=grub-bls
                    chroot() { return 31; }
                    verify_boot; echo 'complete and verified'
                ''', self.root)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('complete and verified', result.stdout)

    def test_live_build_propagates_helper_failure(self):
        stage = self.root / 'stage'
        (stage / 'fed_sqroot/usr/bin').mkdir(parents=True)
        (stage / 'modules/k').mkdir(parents=True)
        firmware = stage / 'firmware/qcom/glymur/ASUSTeK/UX3607OA'
        firmware.mkdir(parents=True)
        for name in ('qcadsp8480.mbn', 'adsp_dtbs.elf', 'qccdsp8480.mbn', 'cdsp_dtbs.elf'):
            (firmware / name).write_text('firmware')
        for name in ('ath12k/QCC2072/hw1.0/board-2.bin', 'ath12k/QCC2072/hw1.0/firmware-2.bin',
                     'qca/clnbtfw10.tlv', 'qcom/gen80100_sqe.fw', 'qcom/gen80100_gmu.bin',
                     'qcom/glymur/ASUSTeK/UX3607OA-tplg.bin'):
            path = stage / 'firmware' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('firmware')
        for name in ('vmlinuz-k' , 'initramfs-live-k.img', 'k.dtb', 'systemd-bootaa64.efi'):
            (stage / name).write_text('artifact')
        stubs = self.root / 'stubs.sh'
        stubs.write_text('''
            uname() { echo aarch64; }; id() { echo 0; }; chroot() { :; }
            install() { :; }; python3() { :; }; lsinitrd() { echo 'btrfs.ko dmsquash'; }
            mksquashfs() { :; }; parted() { :; }; losetup() { :; }
            mkfs.vfat() { :; }; mkfs.ext4() { :; }; blkid() { :; }
            dtc() { :; }; fdtget() { :; }; mountpoint() { return 1; }
            cp() { if [[ "$*" == *firmware/qcom* ]]; then return 37; fi; command cp "$@"; }
        ''')
        result = subprocess.run(['bash', str(ISO / 'build-live-images.sh'), 'fedora'],
                                env={**os.environ, 'BASH_ENV': str(stubs), 'STAGE': str(stage),
                                     'KREL': 'k', 'REPO': str(ISO.parent)},
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('fedora: aborted', result.stdout)
        self.assertNotIn('squashing rootfs', result.stdout)
        self.assertFalse(list((stage / 'out-live').glob('*.img')))


if __name__ == '__main__':
    unittest.main()
