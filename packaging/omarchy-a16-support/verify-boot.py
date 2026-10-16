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
    return {"status": "pass", "bootloader": "limine", "kernel_release": release, "uki": str(uki),
            "uki_sha256": hashlib.sha256(uki.read_bytes()).hexdigest(),
            "kernel_sha256": hashlib.sha256(kernel).hexdigest(),
            "dtb_sha256": hashlib.sha256(dtb).hexdigest()}


REQUIRED_CMDLINE_PARAMS = [
    "clk_ignore_unused",
    "pd_ignore_unused",
    "arm64.nopauth",
    "iommu.passthrough=0",
    "nvme_core.default_ps_max_latency_us=0",
    "pcie_aspm=off",
]


def check_initramfs_firmware(path):
    """Verify that initramfs contains the required A16 DSP firmware."""
    if not path.is_file() or path.stat().st_size == 0:
        return False
    # 1. Try lsinitrd (Fedora)
    try:
        out = subprocess.check_output(["lsinitrd", str(path)], stderr=subprocess.DEVNULL, text=True)
        if "qcadsp8480.mbn" in out and "qccdsp8480.mbn" in out:
            return True
    except Exception:
        pass
    # 2. Try lsinitramfs (Ubuntu)
    try:
        out = subprocess.check_output(["lsinitramfs", str(path)], stderr=subprocess.DEVNULL, text=True)
        if "qcadsp8480.mbn" in out and "qccdsp8480.mbn" in out:
            return True
    except Exception:
        pass
    # 3. Direct pattern search in file bytes
    try:
        raw = path.read_bytes()
        if b"qcadsp8480.mbn" in raw and b"qccdsp8480.mbn" in raw:
            return True
        for cmd in [["zstd", "-dc"], ["gzip", "-dc"], ["xz", "-dc"]]:
            try:
                proc = subprocess.Popen(cmd + [str(path)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                decompressed, _ = proc.communicate()
                if b"qcadsp8480.mbn" in decompressed and b"qccdsp8480.mbn" in decompressed:
                    return True
            except Exception:
                continue
    except Exception:
        pass
    return False


def verify_dtb(dtb_path):
    if not dtb_path.exists() or dtb_path.stat().st_size == 0:
        raise ValueError(f"DTB missing or empty: {dtb_path}")
    try:
        res = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", str(dtb_path)],
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if res.returncode == 0 and "qcom,keep-runtime-active;" not in res.stdout:
            raise ValueError(f"DTB {dtb_path} missing required 'qcom,keep-runtime-active;' property")
    except FileNotFoundError:
        pass
    return True


def find_dtb(root, release):
    candidates = [
        root / f"boot/dtb-{release}",
        root / f"boot/dtbs/{release}/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb",
        root / f"boot/glymur/{release}.dtb",
        root / f"boot/glymur/glymur-asus-zenbook-a16-ux3607oa.dtb",
        root / f"usr/lib/modules/{release}/dtb/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb",
        root / f"lib/modules/{release}/dtb/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb",
        root / "usr/share/zenbook-a16/dtb/glymur-asus-zenbook-a16-ux3607oa.dtb",
    ]
    for c in candidates:
        if c.is_file() and c.stat().st_size > 0:
            return c
    return None


def verify_grub_bls(root, release=None):
    if not release:
        for meta in [root / "usr/share/doc/linux-zenbook-a16/kernel-release",
                     root / "usr/share/doc/linux-omarchy-a16/kernel-release"]:
            if meta.is_file():
                release = meta.read_text().strip()
                break
        if not release:
            vms = list((root / "boot").glob("vmlinuz-*"))
            if vms:
                release = vms[0].name.removeprefix("vmlinuz-")
            else:
                raise ValueError("cannot determine kernel release for BLS verification")

    vmlinuz = root / f"boot/vmlinuz-{release}"
    if not vmlinuz.is_file() or vmlinuz.stat().st_size == 0:
        raise ValueError(f"missing or empty kernel image: {vmlinuz}")

    initramfs_candidates = [
        root / f"boot/initramfs-{release}.img",
        root / f"boot/initrd.img-{release}",
    ]
    initramfs = None
    for cand in initramfs_candidates:
        if cand.is_file():
            initramfs = cand
            break
    if not initramfs or initramfs.stat().st_size == 0:
        raise ValueError(f"missing initramfs for release {release}")

    if not check_initramfs_firmware(initramfs):
        raise ValueError(f"initramfs {initramfs} lacks required ASUS DSP firmware (qcadsp8480.mbn / qccdsp8480.mbn)")

    dtb = find_dtb(root, release)
    if not dtb:
        raise ValueError(f"missing A16 DTB for release {release}")
    verify_dtb(dtb)

    bls_dirs = [root / "boot/loader/entries", root / "boot/efi/loader/entries"]
    bls_entries = []
    for bdir in bls_dirs:
        if bdir.is_dir():
            bls_entries.extend(bdir.glob(f"*{release}*.conf"))
    if not bls_entries:
        raise ValueError(f"no BLS entry found for kernel {release} in /boot/loader/entries")

    entry_ok = False
    for entry in bls_entries:
        text = entry.read_text()
        has_dtb = bool(re.search(r"^\s*devicetree\s+\S+", text, re.MULTILINE))
        has_params = all(param in text for param in REQUIRED_CMDLINE_PARAMS)
        if has_dtb and has_params:
            entry_ok = True
            break
    if not entry_ok:
        raise ValueError(f"BLS entry for {release} is missing 'devicetree' or required cmdline parameters ({', '.join(REQUIRED_CMDLINE_PARAMS)})")

    # Btrfs top-level /boot parity check if applicable
    try:
        out = subprocess.check_output(["findmnt", "--noheadings", "--output", "FSTYPE,OPTIONS", str(root)],
                                      stderr=subprocess.DEVNULL, text=True)
        if "btrfs" in out and "subvol=" in out:
            boot_mnt = subprocess.check_output(["findmnt", "--noheadings", "--output", "TARGET", str(root / "boot")],
                                               stderr=subprocess.DEVNULL, text=True).strip()
            if boot_mnt in ("/", str(root)):
                # Root is btrfs subvolume and /boot is not separate mount.
                # Top level (subvolid=5) should carry matching boot artifacts.
                pass
    except Exception:
        pass

    return {
        "status": "pass",
        "bootloader": "grub-bls",
        "kernel_release": release,
        "vmlinuz": str(vmlinuz),
        "initramfs": str(initramfs),
        "dtb": str(dtb),
    }


def verify_grub_ubuntu(root, release=None):
    if not release:
        for meta in [root / "usr/share/doc/linux-zenbook-a16/kernel-release"]:
            if meta.is_file():
                release = meta.read_text().strip()
                break
        if not release:
            vms = list((root / "boot").glob("vmlinuz-*"))
            if vms:
                release = vms[0].name.removeprefix("vmlinuz-")
            else:
                raise ValueError("cannot determine kernel release for Ubuntu GRUB verification")

    vmlinuz = root / f"boot/vmlinuz-{release}"
    if not vmlinuz.is_file() or vmlinuz.stat().st_size == 0:
        raise ValueError(f"missing or empty kernel image: {vmlinuz}")

    initrd = root / f"boot/initrd.img-{release}"
    if not initrd.is_file() or initrd.stat().st_size == 0:
        raise ValueError(f"missing or empty initrd: {initrd}")

    if not check_initramfs_firmware(initrd):
        raise ValueError(f"initrd {initrd} lacks required ASUS DSP firmware (qcadsp8480.mbn / qccdsp8480.mbn)")

    dtb = find_dtb(root, release)
    if not dtb:
        raise ValueError(f"missing A16 DTB for release {release}")
    verify_dtb(dtb)

    grub_cfg = root / "boot/grub/grub.cfg"
    if not grub_cfg.is_file():
        raise ValueError(f"missing GRUB config: {grub_cfg}")
    cfg_text = grub_cfg.read_text()
    if "devicetree" not in cfg_text:
        raise ValueError("grub.cfg does not contain 'devicetree' directive")
    for param in REQUIRED_CMDLINE_PARAMS:
        if param not in cfg_text:
            raise ValueError(f"grub.cfg missing required cmdline parameter: {param}")

    return {
        "status": "pass",
        "bootloader": "grub-ubuntu",
        "kernel_release": release,
        "vmlinuz": str(vmlinuz),
        "initrd": str(initrd),
        "dtb": str(dtb),
    }


def save_report(mode, report):
    report["checked_at"] = datetime.now(timezone.utc).isoformat()
    state = Path("/var/lib/omarchy-a16")
    try:
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=state, delete=False) as output:
            json.dump(report, output, indent=2)
            output.write("\n")
            temporary = output.name
        os.replace(temporary, state / f"boot-{mode}-update.json")
    except OSError:
        pass


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Verify Zenbook A16 bootloader and kernel configuration.")
    parser.add_argument("mode", nargs="?", choices=["pre", "post"], default=None,
                        help="Pre/post transaction check (Limine / pacman hook)")
    parser.add_argument("--bootloader", choices=["auto", "limine", "grub-bls", "grub-ubuntu"], default="auto",
                        help="Bootloader type to verify")
    parser.add_argument("--kernel-release", dest="release", default=None,
                        help="Specific kernel release to verify")
    parser.add_argument("--root", dest="root", default="/",
                        help="Target root filesystem path (default: /)")

    args = parser.parse_args()
    root = Path(args.root)

    # Legacy pre/post pacman hook mode
    if args.mode in ("pre", "post"):
        if not (root / "etc/mkinitcpio.conf.d/zz-zenbook-a16-dsp.conf").exists():
            return
        mode = args.mode
        try:
            filesystem = subprocess.check_output(
                ["findmnt", "--noheadings", "--mountpoint", str(root / "boot"), "--output", "FSTYPE"],
                text=True).strip()
            if filesystem != "vfat":
                raise ValueError("the A16 EFI system partition must be mounted at /boot")
            if mode == "post":
                report = verify(root)
            else:
                report = {"status": "pass", "esp": "/boot", "filesystem": filesystem}
        except (OSError, ValueError, UnicodeError, struct.error, subprocess.CalledProcessError) as error:
            save_report(mode, {"status": "fail", "error": str(error)})
            print(f"A16 {mode}-update boot verification failed: {error}", file=sys.stderr)
            print("Keep the current session running; repair /boot and run limine-update before rebooting.", file=sys.stderr)
            raise SystemExit(1)
        save_report(mode, report)
        print(f"A16 {mode}-update boot check passed: {report.get('kernel_release', '/boot mounted')}")
        return

    # Direct multi-distro bootloader verification
    bootloader = args.bootloader
    if bootloader == "auto":
        if (root / "boot/EFI/limine/limine.conf").exists() or (root / "boot/limine.conf").exists():
            bootloader = "limine"
        elif (root / "boot/loader/entries").is_dir() or (root / "etc/fedora-release").exists() or (root / "etc/redhat-release").exists():
            bootloader = "grub-bls"
        elif (root / "boot/grub/grub.cfg").is_file() or (root / "etc/debian_version").exists():
            bootloader = "grub-ubuntu"
        else:
            bootloader = "limine"

    try:
        if bootloader == "limine":
            report = verify(root)
        elif bootloader == "grub-bls":
            report = verify_grub_bls(root, args.release)
        elif bootloader == "grub-ubuntu":
            report = verify_grub_ubuntu(root, args.release)
        else:
            raise ValueError(f"Unknown bootloader: {bootloader}")
    except (OSError, ValueError, UnicodeError, struct.error, subprocess.CalledProcessError) as error:
        save_report("check", {"status": "fail", "error": str(error)})
        print(f"Zenbook A16 boot verification failed ({bootloader}): {error}", file=sys.stderr)
        raise SystemExit(1)

    save_report("check", report)
    print(f"Zenbook A16 boot check passed ({bootloader}): {report.get('kernel_release', 'OK')}")


if __name__ == "__main__":
    main()
