"""A stale boot artifact must fail even when Limine's hook returned success."""
import importlib.util
import contextlib
import io
import lzma
import gzip
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("boot_check", Path(__file__).with_name("verify-boot.py"))
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


def image(parts):
    data = bytearray(4096)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3C, 64)
    data[64:68] = b"PE\0\0"
    struct.pack_into("<H", data, 70, len(parts))
    offset = 1024
    for index, (name, content) in enumerate(parts):
        entry = 88 + index * 40
        data[entry:entry + 8] = name.encode().ljust(8, b"\0")
        struct.pack_into("<IIII", data, entry + 8, len(content), 0, len(content), offset)
        data[offset:offset + len(content)] = content
        offset += len(content)
    return bytes(data)


class BootVerification(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.release = "7.2.10-omarchy-a16-2"
        for name, content in {
            "etc/machine-id": "machine",
            "usr/share/doc/linux-omarchy-a16/kernel-release": self.release,
            f"usr/lib/modules/{self.release}/vmlinuz": "kernel",
            f"usr/lib/modules/{self.release}/build/include/config/kernel.release": self.release,
            "boot/dtbs/linux-omarchy-a16/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb": "a16 dtb",
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.uki = self.root / "boot/EFI/Linux/machine_linux-omarchy-a16.efi"
        self.uki.parent.mkdir(parents=True)
        self.parts = [(".linux", b"kernel"), (".uname", self.release.encode() + b"\0"),
                      (".initrd", b"initramfs"), (".dtbauto", b"other board"),
                      (".dtbauto", b"a16 dtb")]
        self.uki.write_bytes(image(self.parts))

    def test_matching_multiboard_uki(self):
        self.assertEqual(boot.verify(self.root)["kernel_release"], self.release)

    def test_limine_custom_prefix_and_config_precedence(self):
        configs = {
            "usr/share/limine-entry-tool.d/default.conf": "vendor",
            "etc/limine-entry-tool.conf": "local",
            "etc/limine-entry-tool.d/omarchy-defaults.conf": "omarchy",
            "etc/default/limine": "override",
        }
        for name, prefix in configs.items():
            config = self.root / name
            config.parent.mkdir(parents=True, exist_ok=True)
            config.write_text(f'CUSTOM_UKI_NAME="{prefix}"\n')
            renamed = self.uki.with_name(f"{prefix}_linux-omarchy-a16.efi")
            self.uki.rename(renamed)
            self.uki = renamed
            self.assertEqual(boot.verify(self.root)["uki"], str(renamed))
        config.write_text('CUSTOM_UKI_NAME="../invalid"\n')
        self.uki.rename(self.uki.with_name("machine_linux-omarchy-a16.efi"))
        self.assertTrue(boot.verify(self.root)["uki"].endswith("machine_linux-omarchy-a16.efi"))

    def test_rejects_stale_kernel_dtb_release_and_missing_initrd(self):
        for name in (".linux", ".dtbauto", ".uname", ".initrd"):
            with self.subTest(name=name):
                changed = [(key, b"" if key == ".initrd" else b"stale") if key == name
                           else (key, value) for key, value in self.parts]
                self.uki.write_bytes(image(changed))
                with self.assertRaises(ValueError):
                    boot.verify(self.root)

    def test_rejects_mismatched_headers(self):
        path = self.root / f"usr/lib/modules/{self.release}/build/include/config/kernel.release"
        path.write_text("different kernel")
        with self.assertRaises(ValueError):
            boot.verify(self.root)

    def test_shared_kernel_updates_follow_abi_instead_of_version_pin(self):
        updated = "7.2.11-2-omarchy"
        (self.root / "usr/share/doc/linux-omarchy-a16").rename(self.root / "usr/share/doc/linux-omarchy")
        metadata = self.root / "usr/share/doc/linux-omarchy/kernel-release"
        metadata.write_text(updated)
        modules = self.root / f"usr/lib/modules/{updated}"
        (self.root / f"usr/lib/modules/{self.release}").rename(modules)
        (modules / "build/include/config/kernel.release").write_text(updated)
        marker = modules / "omarchy-a16-dsp-abi"
        marker.write_text("1\n")
        (self.root / "boot/dtbs/linux-omarchy-a16").rename(self.root / "boot/dtbs/linux-omarchy")
        self.uki.unlink()
        self.uki = self.root / "boot/EFI/Linux/machine_linux-omarchy.efi"
        self.uki.write_bytes(image([(key, updated.encode()) if key == ".uname" else (key, value)
                                    for key, value in self.parts]))
        self.assertEqual(boot.verify(self.root)["kernel_release"], updated)
        marker.write_text("2\n")
        with self.assertRaises(ValueError):
            boot.verify(self.root)

    def install_versioned_kernel(self, revision):
        release = f"7.2.10-omarchy-a16-{revision}"
        package = f"linux-omarchy-a16-7.2.10-{revision}"
        kernel = bytearray(128)
        struct.pack_into("<Q", kernel, 16, 4096)
        kernel[56:60] = b"ARM\x64"
        kernel[-1] = revision
        config = f"CONFIG_A16_REVISION_{revision}=y\n".encode()
        dtb = f"a16 dtb revision {revision}".encode()
        modules = self.root / "usr/lib/modules" / release
        headers = modules / "build/include/config/kernel.release"
        headers.parent.mkdir(parents=True, exist_ok=True)
        headers.write_text(release)
        (modules / "vmlinuz").write_bytes(kernel)
        (modules / "pkgbase").write_text(package + "\n")
        staged_dtb = self.root / f"boot/dtbs/{package}/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb"
        staged_dtb.parent.mkdir(parents=True)
        staged_dtb.write_bytes(dtb)
        documentation = self.root / "usr/share/doc" / package
        documentation.mkdir(parents=True)
        (documentation / "config").write_bytes(config)
        (modules / "zenbook-a16-boot.json").write_text(json.dumps({
            "schema": 1, "kernel_release": release, "kernel_package": package,
            "kernel_sha256": hashlib.sha256(kernel).hexdigest(),
            "dtb_sha256": hashlib.sha256(dtb).hexdigest(),
            "config_sha256": hashlib.sha256(config).hexdigest(),
            "source_tree": "4d6a5f56ffa9571ec5b5f053ecbe4861c158b2b2",
            "source_status": "source replay verified; hardware acceptance pending",
            "dsp_policy": "omarchy-a16-legacy-v1", "cmdline": [],
        }))
        uki = self.root / f"boot/EFI/Linux/machine_{package}.efi"
        uki.write_bytes(image([(".linux", bytes(kernel)), (".uname", release.encode()),
                               (".initrd", b"initramfs"), (".dtbauto", dtb)]))
        return release, modules, uki

    def test_explicit_versioned_standalone_verification_preserves_older_uki(self):
        old_release, _, old_uki = self.install_versioned_kernel(3)
        old_bytes = old_uki.read_bytes()
        new_release, _, new_uki = self.install_versioned_kernel(4)
        self.assertEqual(boot.verify(self.root, old_release)["uki"], str(old_uki))
        self.assertEqual(boot.verify(self.root, new_release)["uki"], str(new_uki))
        self.assertEqual(old_uki.read_bytes(), old_bytes)
        self.assertEqual(boot.verify(self.root)["kernel_release"], self.release)

    def test_versioned_metadata_cannot_claim_shared_abi_or_stale_artifacts(self):
        release, modules, _ = self.install_versioned_kernel(3)
        metadata = modules / "zenbook-a16-boot.json"
        original = json.loads(metadata.read_text())
        for key, value in (("dsp_policy", "pre-root-v1"), ("kernel_package", "linux-omarchy"),
                           ("kernel_sha256", "0" * 64), ("dtb_sha256", "0" * 64),
                           ("config_sha256", "0" * 64), ("source_tree", [])):
            with self.subTest(key=key):
                metadata.write_text(json.dumps(dict(original, **{key: value})))
                with self.assertRaises(ValueError):
                    boot.verify(self.root, release)
        self.assertFalse((modules / "omarchy-a16-dsp-abi").exists())

    def test_rejects_truncated_pe(self):
        with self.assertRaises((ValueError, struct.error)):
            boot.sections(b"MZ")



def cpio_image(members):
    data = bytearray()
    for name, content in [*members.items(), ("TRAILER!!!", b"")]:
        filename = name.encode() + b"\0"
        fields = [0, 0o100644, 0, 0, 1, 0, len(content), 0, 0, 0, 0, len(filename), 0]
        data.extend(b"070701" + b"".join(f"{field:08x}".encode() for field in fields))
        data.extend(filename)
        data.extend(b"\0" * (-len(data) % 4))
        data.extend(content)
        data.extend(b"\0" * (-len(data) % 4))
    return gzip.compress(data)


def dtb_image(nodes):
    strings, structure = bytearray(), bytearray()
    def token(value):
        structure.extend(struct.pack(">I", value))
    def begin(name):
        token(1)
        structure.extend(name.encode() + b"\0")
        structure.extend(b"\0" * (-len(structure) % 4))
    def properties(values):
        for key, value in values.items():
            offset = len(strings)
            strings.extend(key.encode() + b"\0")
            content = b"" if value is None else value.encode() + b"\0"
            structure.extend(struct.pack(">III", 3, len(content), offset) + content)
            structure.extend(b"\0" * (-len(structure) % 4))
    begin("")
    properties(nodes["/"])
    begin("soc@0")
    for path, values in nodes.items():
        if path == "/":
            continue
        begin(path.rsplit("/", 1)[1])
        properties(values)
        token(2)
    token(2)
    token(2)
    token(9)
    total = 56 + len(structure) + len(strings)
    header = struct.pack(">10I", 0xd00dfeed, total, 56, 56 + len(structure), 40, 17, 16, 0,
                         len(strings), len(structure))
    return header + bytes(16) + structure + strings


class GrubVerification(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.release = "7.3.0-rc5-a16"
        self.kernel = self.root / f"boot/vmlinuz-{self.release}"
        self.kernel.parent.mkdir()
        kernel = bytearray(4096)
        kernel[:2] = b"MZ"
        struct.pack_into("<Q", kernel, 16, 8192)
        kernel[56:60] = b"ARM\x64"
        struct.pack_into("<I", kernel, 60, 64)
        kernel[64:68] = b"PE\0\0"
        struct.pack_into("<HH", kernel, 68, 0xaa64, 2)
        for index, (name, virtual_size, raw_size, offset) in enumerate(
                ((b".text", 2048, 2048, 512), (b".data", 4096, 1536, 2560))):
            start = 88 + index * 40
            kernel[start:start + 8] = name.ljust(8, b"\0")
            struct.pack_into("<IIII", kernel, start + 8, virtual_size, offset, raw_size, offset)
        self.kernel.write_bytes(kernel)
        self.dtb = self.root / f"boot/dtb-{self.release}"
        self.nodes = {"/": {"compatible": "asus,zenbook-a16-ux3607oa"}}
        for address in ("6c80000", "6ca0000"):
            self.nodes[f"/soc@0/soundwire@{address}"] = {
                "compatible": "qcom,soundwire-v3.1.0", "status": "okay", "qcom,keep-runtime-active": None}
        self.dtb.write_bytes(dtb_image(self.nodes))
        self.params = ["clk_ignore_unused", "pd_ignore_unused", "cma=128M", "glymur_pci_skip=5",
                       "selinux=0", "asus_glymur_ec.fan_profile=2",
                       "modprobe.blacklist=i2c_qcom_cci,qcom_camss,ov02c10"]
        self.metadata = self.root / f"usr/lib/modules/{self.release}/zenbook-a16-boot.json"
        self.metadata.parent.mkdir(parents=True)
        self.write_metadata()
        self.members = {f"usr/lib/firmware/qcom/glymur/ASUSTeK/UX3607OA/{name}": b"firmware data"
                        for name in ("qcadsp8480.mbn", "adsp_dtbs.elf", "qccdsp8480.mbn", "cdsp_dtbs.elf")}
        for tool in ("lsinitrd", "unmkinitramfs"):
            for relative, source in boot.initramfs_policy_files(self.root, tool):
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_bytes(f"trusted policy {relative}".encode())
                self.members[relative] = source.read_bytes()
        self.initrd = self.root / f"boot/initramfs-{self.release}.img"
        self.write_archive()
        self.mount_target, self.fstype, self.fsroot = self.root, "ext4", "/"
        self.bls = self.root / f"boot/loader/entries/machine-{self.release}.conf"
        self.bls.parent.mkdir(parents=True)
        self.bls.write_text(self.bls_text())
        self.grub = self.root / "boot/grub/grub.cfg"
        self.grub.parent.mkdir()
        self.grub.write_text(self.grub_text())
        self.command_patch = mock.patch.object(boot.subprocess, "check_output", side_effect=self.command)
        self.command_patch.start()
        self.addCleanup(self.command_patch.stop)

    def write_metadata(self):
        self.metadata.write_text(json.dumps({
            "schema": 1, "kernel_release": self.release, "dsp_policy": "pre-root-v1",
            "kernel_sha256": hashlib.sha256(self.kernel.read_bytes()).hexdigest(),
            "dtb_sha256": hashlib.sha256(self.dtb.read_bytes()).hexdigest(), "cmdline": self.params}))

    def write_archive(self):
        self.archive = cpio_image(self.members)
        self.initrd.write_bytes(self.archive)

    def bls_text(self, prefix="/boot"):
        return (f"title Fedora\nversion {self.release}\nlinux {prefix}/vmlinuz-{self.release}\n"
                f"initrd {prefix}/initramfs-{self.release}.img\ndevicetree {prefix}/dtb-{self.release}\n"
                f"options root=UUID=rootuuid {' '.join(self.params)}\n")

    def grub_text(self, prefix="/boot"):
        return (f"insmod fdt\nmenuentry 'Ubuntu' --id 'zenbook-a16-{self.release}' {{\n"
                " search --no-floppy --fs-uuid --set=root bootuuid\n"
                f" linux {prefix}/vmlinuz-{self.release} root=UUID=rootuuid {' '.join(self.params)}\n"
                f" initrd {prefix}/initramfs-{self.release}.img\n"
                f" devicetree {prefix}/dtb-{self.release}\n}}\n")

    def command(self, arguments, **kwargs):
        tool = arguments[0]
        if tool == "findmnt":
            return json.dumps({"filesystems": [{"target": str(self.mount_target), "fstype": self.fstype,
                                                "fsroot": self.fsroot, "uuid": "bootuuid"}]})
        if tool in ("lsinitrd", "unmkinitramfs"):
            image = Path(arguments[-1] if tool == "lsinitrd" else arguments[1])
            if image.read_bytes() != self.archive:
                raise boot.subprocess.CalledProcessError(1, arguments, stderr="not an initramfs archive")
            output = Path(kwargs["cwd"]) if tool == "lsinitrd" else Path(arguments[2]) / "main"
            for name, content in self.members.items():
                destination = output / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
            return ""
        if tool == "dtc":
            if Path(arguments[-1]).read_bytes()[:4] != b"\xd0\x0d\xfe\xed":
                raise boot.subprocess.CalledProcessError(1, arguments, stderr="invalid DTB")
            return "/dts-v1/;"
        if tool == "fdtget":
            if arguments[1] == "-p":
                return "\n".join(self.nodes[arguments[-1]])
            values = self.nodes[arguments[-2]]
            return values[arguments[-1]] + "\n"
        if tool == "xz":
            try:
                return lzma.decompress(Path(arguments[-1]).read_bytes())
            except lzma.LZMAError as error:
                raise boot.subprocess.CalledProcessError(1, arguments, stderr="invalid xz") from error
        raise AssertionError(arguments)

    def test_valid_bls_and_ubuntu_with_actual_manifest_flags(self):
        self.assertEqual(boot.verify_grub_bls(self.root, self.release)["status"], "pass")
        self.assertEqual(boot.verify_grub_ubuntu(self.root, self.release)["status"], "pass")

    def test_validate_kernel_cli_also_checks_requested_initramfs(self):
        arguments = ["verify-boot.py", "--validate-kernel", "--modules-dir", str(self.metadata.parent),
                     "--kernel-release", self.release, "--kernel-image", str(self.kernel),
                     "--dtb-image", str(self.dtb), "--root", str(self.root), "--initramfs-image", str(self.initrd)]
        with mock.patch.object(boot.sys, "argv", arguments), contextlib.redirect_stdout(io.StringIO()):
            boot.main()
        del self.members["usr/lib/zenbook-a16/dsp-policy.sh"]
        self.write_archive()
        with mock.patch.object(boot.sys, "argv", arguments), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as failure:
                boot.main()
            self.assertEqual(failure.exception.code, 1)

    def test_metadata_requires_an_object(self):
        self.metadata.write_text("[]")
        with self.assertRaisesRegex(ValueError, "metadata"):
            boot.verify_grub_bls(self.root, self.release)

    def test_image_bss_memory_size_may_exceed_file_size(self):
        self.assertGreater(struct.unpack_from("<Q", self.kernel.read_bytes(), 16)[0], self.kernel.stat().st_size)
        boot.verify_image(self.kernel)

    def test_separate_boot_paths_resolve_on_the_boot_filesystem(self):
        self.mount_target = self.root / "boot"
        self.bls.write_text(self.bls_text(prefix=""))
        self.grub.write_text(self.grub_text(prefix=""))
        self.assertEqual(boot.verify_grub_bls(self.root, self.release)["status"], "pass")
        self.assertEqual(boot.verify_grub_ubuntu(self.root, self.release)["status"], "pass")
        self.bls.write_text(self.bls_text())
        with self.assertRaises(ValueError):
            boot.verify_grub_bls(self.root, self.release)

    def test_arbitrary_initrd_names_are_not_archive_members(self):
        self.initrd.write_bytes(b"qcadsp8480.mbn qccdsp8480.mbn adsp_dtbs.elf cdsp_dtbs.elf")
        with self.assertRaisesRegex(ValueError, "not an initramfs"):
            boot.verify_grub_bls(self.root, self.release)

    def test_missing_wrong_path_or_empty_firmware_fails(self):
        original = dict(self.members)
        for name in (name for name in original if "/firmware/" in name):
            for mutation in ("missing", "wrong-path", "empty"):
                with self.subTest(name=name, mutation=mutation):
                    self.members = dict(original)
                    content = self.members.pop(name)
                    if mutation == "wrong-path":
                        self.members[name.replace("UX3607OA/", "another-board/")] = content
                    elif mutation == "empty":
                        self.members[name] = b""
                    self.write_archive()
                    with self.assertRaisesRegex(ValueError, "DSP firmware"):
                        boot.verify_grub_bls(self.root, self.release)

    def test_runtime_policy_and_registered_hook_must_match_installed_sources(self):
        original = dict(self.members)
        for tool, verify in (("lsinitrd", boot.verify_grub_bls), ("unmkinitramfs", boot.verify_grub_ubuntu)):
            for relative, _ in boot.initramfs_policy_files(self.root, tool):
                for replacement in (None, b"stale policy"):
                    with self.subTest(tool=tool, member=relative, replacement=replacement):
                        self.members = dict(original)
                        del self.members[relative]
                        if replacement is not None:
                            self.members[relative] = replacement
                        self.write_archive()
                        with self.assertRaisesRegex(ValueError, "pre-root DSP policy"):
                            verify(self.root, self.release)

    def test_compressed_firmware_requires_successful_nonempty_decode(self):
        self.members = {name + ".xz" if "/firmware/" in name else name:
                        lzma.compress(content) if "/firmware/" in name else content
                        for name, content in self.members.items()}
        self.write_archive()
        self.assertEqual(boot.verify_grub_bls(self.root, self.release)["status"], "pass")
        original = self.command
        def empty_decode(arguments, **kwargs):
            return b"" if arguments[0] == "xz" else original(arguments, **kwargs)
        with mock.patch.object(boot.subprocess, "check_output", side_effect=empty_decode):
            with self.assertRaisesRegex(ValueError, "DSP firmware"):
                boot.verify_grub_bls(self.root, self.release)

    def test_missing_tools_and_failed_commands_fail_closed(self):
        for tool in ("findmnt", "lsinitrd", "dtc", "fdtget"):
            for error in (FileNotFoundError(), boot.subprocess.CalledProcessError(1, tool, stderr="failed")):
                with self.subTest(tool=tool, error=type(error)):
                    original = self.command
                    def fail(arguments, **kwargs):
                        if arguments[0] == tool:
                            raise error
                        return original(arguments, **kwargs)
                    with mock.patch.object(boot.subprocess, "check_output", side_effect=fail):
                        with self.assertRaisesRegex(ValueError, tool):
                            boot.verify_grub_bls(self.root, self.release)

    def test_invalid_dtb_or_property_on_wrong_node_fails(self):
        self.dtb.write_bytes(b"not a dtb qcom,keep-runtime-active;")
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, "dtc"):
            boot.verify_grub_bls(self.root, self.release)
        self.dtb.write_bytes(dtb_image(self.nodes))
        self.write_metadata()
        self.nodes["/"]["qcom,keep-runtime-active"] = None
        del self.nodes["/soc@0/soundwire@6ca0000"]["qcom,keep-runtime-active"]
        with self.assertRaisesRegex(ValueError, "SoundWire"):
            boot.verify_grub_bls(self.root, self.release)
        self.nodes["/soc@0/soundwire@6ca0000"]["qcom,keep-runtime-active"] = None
        self.nodes["/soc@0/soundwire@6c80000"]["status"] = "disabled"
        with self.assertRaisesRegex(ValueError, "SoundWire"):
            boot.verify_grub_bls(self.root, self.release)

    def test_bls_comments_missing_commands_stale_paths_and_conflicts_fail(self):
        valid = self.bls_text()
        cases = [
            f"version {self.release}\ndevicetree /nonexistent\n# {' '.join(self.params)}\n",
            valid.replace(f"version {self.release}", "version stale"),
            valid.replace(f"version {self.release}\n", ""),
            valid.replace(f"vmlinuz-{self.release}", "vmlinuz-stale"),
            valid.replace(f"initramfs-{self.release}.img", "initramfs-stale.img"),
            valid.replace(f"dtb-{self.release}", "dtb-missing"),
            valid.replace("clk_ignore_unused", "# clk_ignore_unused"),
            valid.replace("cma=128M", "cma=128M cma=1M"),
            valid.replace("cma=128M", "cma=128M-extra"),
            valid + f"linux /boot/vmlinuz-{self.release}\n",
        ]
        for text in cases:
            with self.subTest(text=text):
                self.bls.write_text(text)
                with self.assertRaises((ValueError, OSError)):
                    boot.verify_grub_bls(self.root, self.release)

    def test_ubuntu_checks_exact_a16_ids_and_preserves_stock_fallback(self):
        valid = self.grub_text()
        rescue = valid.replace(f"--id 'zenbook-a16-{self.release}'", f"--id 'zenbook-a16-{self.release}-rescue'")
        stock = ("menuentry 'Stock Ubuntu' {\n"
                 f" linux /boot/vmlinuz-{self.release} root=UUID=rootuuid\n"
                 f" initrd /boot/initramfs-{self.release}.img\n}}\n")
        self.grub.write_text(valid + rescue + stock)
        self.assertEqual(boot.verify_grub_ubuntu(self.root, self.release)["status"], "pass")
        self.grub.write_text(rescue + stock)
        with self.assertRaisesRegex(ValueError, "no complete GRUB"):
            boot.verify_grub_ubuntu(self.root, self.release)
        self.grub.write_text(valid + rescue.replace("cma=128M", "cma=1M") + stock)
        with self.assertRaisesRegex(ValueError, "cma"):
            boot.verify_grub_ubuntu(self.root, self.release)

    def test_ubuntu_comments_split_entries_and_wrong_search_fail(self):
        valid = self.grub_text()
        cases = ["\n".join("# " + line for line in valid.splitlines()),
                 valid.replace(f" initrd /boot/initramfs-{self.release}.img", "# initrd omitted"),
                 valid.replace(f" devicetree /boot/dtb-{self.release}", "}\nmenuentry 'different' {\n devicetree /boot/dtb-missing"),
                 valid.replace("bootuuid", "wronguuid"),
                 valid.replace("insmod fdt", "# insmod fdt"),
                 valid.replace("cma=128M", "# cma=128M"),
                 valid.replace(f"dtb-{self.release}", "dtb-missing"),
                 valid.replace(" bootuuid\n", " bootuuid\n set root=wrong\n"),
                 valid.replace(" linux /boot/", " if false; then\n linux /boot/").replace(" initrd /boot/", " fi\n initrd /boot/"),
                 valid.replace("insmod fdt", "if false; then\ninsmod fdt\nfi"),
                 valid + valid]
        for text in cases:
            with self.subTest(text=text):
                self.grub.write_text(text)
                with self.assertRaises((ValueError, OSError)):
                    boot.verify_grub_ubuntu(self.root, self.release)

    def test_ubuntu_inline_control_blocks_and_quoted_keywords(self):
        for prelude in (
                "if [ x = x ]; then set timeout=5; fi;",
                "if true; then if false; then :; fi; else :; fi",
                "for item in a b; do echo item; done;",
                "while false; do :; done; until true; do :; done",
                "case x in x) echo x;; esac;",
                "echo if for while until case fi done esac",
                "set label='if; fi'; echo \";\" 'if' # if; fi;",
                r"echo \; fi",
                "if true; then \\\n :; fi"):
            with self.subTest(prelude=prelude):
                self.grub.write_text(prelude + "\n" + self.grub_text())
                self.assertEqual(boot.verify_grub_ubuntu(self.root, self.release)["status"], "pass")
        self.grub.write_text(self.grub_text().replace("insmod fdt\n", "insmod fdt; "))
        self.assertEqual(boot.verify_grub_ubuntu(self.root, self.release)["status"], "pass")
        self.grub.write_text(self.grub_text() + " \t # trailing comment")
        self.assertEqual(boot.verify_grub_ubuntu(self.root, self.release)["status"], "pass")

    def test_ubuntu_inline_conditionals_do_not_bypass_artifact_checks(self):
        valid = self.grub_text()
        for text in (
                valid.replace("insmod fdt", "if false; then insmod fdt; fi"),
                valid.replace(" linux ", " if false; then linux ").replace(" initrd ", " fi; initrd "),
                valid.replace(" search ", " if false; then search ").replace(" linux ", " fi; linux "),
                valid.replace(" devicetree ", " if false; then devicetree ").replace("\n}", "; fi\n}"),
                "if true; then\n" + valid,
                "fi;\n" + valid,
                "echo 'unterminated\n" + valid):
            with self.subTest(text=text):
                self.grub.write_text(text)
                with self.assertRaises(ValueError):
                    boot.verify_grub_ubuntu(self.root, self.release)

    def test_invalid_or_truncated_image_fails_even_with_matching_hash(self):
        valid = self.kernel.read_bytes()
        for content in (b"vmlinuz", valid[:64], valid[:-1], valid.replace(b"ARM\x64", b"nope")):
            self.kernel.write_bytes(content)
            self.write_metadata()
            with self.assertRaisesRegex(ValueError, "Image"):
                boot.verify_grub_bls(self.root, self.release)

    def test_manifest_hash_release_policy_and_options_must_match(self):
        valid = json.loads(self.metadata.read_text())
        for key, value in (("schema", 2), ("schema", True), ("kernel_release", "stale"),
                           ("dsp_policy", "none"), ("kernel_sha256", "0" * 64),
                           ("dtb_sha256", "0" * 64), ("cmdline", []),
                           ("cmdline", ["cma=128M", "cma=1M"]), ("cmdline", ["$kernelopts"])):
            with self.subTest(key=key, value=value):
                self.metadata.write_text(json.dumps(dict(valid, **{key: value})))
                with self.assertRaises(ValueError):
                    boot.verify_grub_bls(self.root, self.release)
        self.metadata.unlink()
        with self.assertRaises(OSError):
            boot.verify_grub_bls(self.root, self.release)

    def test_btrfs_subvolume_boot_and_unknown_mounts_are_refused(self):
        self.fstype, self.fsroot = "btrfs", "/@root"
        for verify in (boot.verify_grub_bls, boot.verify_grub_ubuntu):
            with self.assertRaisesRegex(ValueError, "Btrfs.*separate /boot"):
                verify(self.root, self.release)
        self.mount_target, self.fsroot = self.root / "boot", "/"
        self.bls.write_text(self.bls_text(prefix=""))
        self.assertEqual(boot.verify_grub_bls(self.root, self.release)["status"], "pass")
        self.mount_target = self.root / "boot/efi"
        with self.assertRaisesRegex(ValueError, "unsupported boot mount"):
            boot.verify_grub_bls(self.root, self.release)


if __name__ == "__main__":
    unittest.main()
