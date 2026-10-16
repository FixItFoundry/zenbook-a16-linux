"""A stale boot artifact must fail even when Limine's hook returned success."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

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

    def test_rejects_truncated_pe(self):
        with self.assertRaises((ValueError, struct.error)):
            boot.sections(b"MZ")


if __name__ == "__main__":
    unittest.main()
