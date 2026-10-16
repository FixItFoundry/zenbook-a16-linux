#!/usr/bin/python
"""Check the installed A16 UKI after Limine's pacman hook, without booting it."""
import hashlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


def sections(data):
    """Read PE virtual section contents (excluding file-alignment padding)."""
    if data[:2] != b"MZ":
        raise ValueError("boot image has no DOS header")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("boot image has no PE header")
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    result = []
    for index in range(count):
        start = pe + 24 + optional_size + index * 40
        name = data[start:start + 8].rstrip(b"\0").decode("ascii")
        size, _, raw_size, offset = struct.unpack_from("<IIII", data, start + 8)
        # A PE BSS section can have virtual storage without file contents.
        if raw_size == 0:
            continue
        if size > raw_size or offset + raw_size > len(data):
            raise ValueError(f"invalid PE section bounds: {name}")
        result.append((name, data[offset:offset + size]))
    return result


def verify(root):
    package = "linux-omarchy"
    metadata = root / f"usr/share/doc/{package}/kernel-release"
    if not metadata.exists():
        # Compatibility for the original independently named test kernel.
        package = "linux-omarchy-a16"
        metadata = root / f"usr/share/doc/{package}/kernel-release"
    release = metadata.read_text().strip()
    modules = root / "usr/lib/modules" / release
    if package == "linux-omarchy":
        if (modules / "omarchy-a16-dsp-abi").read_text().strip() != "1":
            raise ValueError("the shared kernel lacks the required A16 DSP ABI")
    elif not release.startswith("7.2.10-omarchy-a16-"):
        raise ValueError(f"unaudited A16 development kernel release: {release}")
    headers = (modules / "build/include/config/kernel.release").read_text().strip()
    if headers != release:
        raise ValueError("installed headers do not match the A16 kernel")
    kernel = (modules / "vmlinuz").read_bytes()
    dtb = (root / f"boot/dtbs/{package}/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb").read_bytes()
    machine = (root / "etc/machine-id").read_text().strip()
    # Follow Limine's config order and prefix validation, without executing config.
    configs = [*sorted((root / "usr/share/limine-entry-tool.d").glob("*.conf")),
               root / "etc/limine-entry-tool.conf",
               *sorted((root / "etc/limine-entry-tool.d").glob("*.conf")),
               root / "etc/default/limine"]
    custom = ""
    for config in configs:
        if config.is_file():
            for line in config.read_text().splitlines():
                match = re.match(r"^\s*CUSTOM_UKI_NAME\s*=\s*(.*)$", line)
                if match:
                    custom = match[1].removesuffix('"').removeprefix('"')
    prefix = custom if re.fullmatch(r"[a-z0-9]+", custom) else machine
    uki = root / f"boot/EFI/Linux/{prefix}_{package}.efi"
    parts = sections(uki.read_bytes())
    single = dict(parts)
    if single.get(".uname", b"").rstrip(b"\0").decode() != release:
        raise ValueError("the installed UKI has a stale or missing kernel release")
    if single.get(".linux") != kernel:
        raise ValueError("the installed UKI does not contain the installed kernel")
    if not single.get(".initrd"):
        raise ValueError("the installed UKI has no initramfs")
    if not any(name == ".dtbauto" and content == dtb for name, content in parts):
        raise ValueError("the installed UKI does not contain the matching A16 device tree")
    return {"status": "pass", "kernel_release": release, "uki": str(uki),
            "uki_sha256": hashlib.sha256(uki.read_bytes()).hexdigest(),
            "kernel_sha256": hashlib.sha256(kernel).hexdigest(),
            "dtb_sha256": hashlib.sha256(dtb).hexdigest()}


def save_report(mode, report):
    report["checked_at"] = datetime.now(timezone.utc).isoformat()
    state = Path("/var/lib/omarchy-a16")
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=state, delete=False) as output:
        json.dump(report, output, indent=2)
        output.write("\n")
        temporary = output.name
    os.replace(temporary, state / f"boot-{mode}-update.json")


def main():
    if sys.argv[1:] not in (["pre"], ["post"]):
        raise SystemExit("usage: verify-boot pre|post")
    # The shared ISO can carry this package on other machines. Activate only
    # after A16 hardware setup has selected its initramfs profile.
    if not Path("/etc/mkinitcpio.conf.d/zz-zenbook-a16-dsp.conf").exists():
        return
    mode = sys.argv[1]
    try:
        filesystem = subprocess.check_output(
            ["findmnt", "--noheadings", "--mountpoint", "/boot", "--output", "FSTYPE"],
            text=True).strip()
        if filesystem != "vfat":
            raise ValueError("the A16 EFI system partition must be mounted at /boot")
        if mode == "post":
            report = verify(Path("/"))
        else:
            # Permit repairs of a stale image or mismatched headers; the mount
            # must be present before pacman replaces any kernel/DTB files.
            report = {"status": "pass", "esp": "/boot", "filesystem": filesystem}
    except (OSError, ValueError, UnicodeError, struct.error, subprocess.CalledProcessError) as error:
        save_report(mode, {"status": "fail", "error": str(error)})
        print(f"A16 {mode}-update boot verification failed: {error}", file=sys.stderr)
        print("Keep the current session running; repair /boot and run limine-update before rebooting.", file=sys.stderr)
        raise SystemExit(1)
    save_report(mode, report)
    print(f"A16 {mode}-update boot check passed: {report.get('kernel_release', '/boot mounted')}")


if __name__ == "__main__":
    main()
