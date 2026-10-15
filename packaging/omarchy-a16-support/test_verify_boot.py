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

    def test_rejects_truncated_pe(self):
        with self.assertRaises((ValueError, struct.error)):
            boot.sections(b"MZ")


if __name__ == "__main__":
    unittest.main()
