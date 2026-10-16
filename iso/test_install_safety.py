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

    def test_package_failures_abort(self):
        for package, variable in [('rpm', 'rpm_dir'), ('dpkg', 'deb_dir')]:
            with self.subTest(package=package):
                result = self.shell('zenbook-install-to-disk.sh',
                                    f'target="$1"; {variable}="$1"; {package}() {{ return 23; }}; '
                                    'install_kernel_packages; echo SUCCESS', self.root)
                self.assertEqual(result.returncode, 23)
                self.assertNotIn('SUCCESS', result.stdout)

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
                     'qca/clnbtfw10.tlv', 'qcom/gen80500_sqe.fw', 'qcom/gen80500_gmu.bin',
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
