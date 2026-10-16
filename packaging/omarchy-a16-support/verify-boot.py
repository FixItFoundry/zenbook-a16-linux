#!/usr/bin/python
"""Check installed A16 boot artifacts without booting them."""
import hashlib
import json
import os
import re
import shlex
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


def verify(root, release=None):
    versioned = release is not None
    if versioned:
        if not re.fullmatch(r"7\.2\.10-omarchy-a16-[1-9][0-9]*", release):
            raise ValueError(f"unsupported standalone A16 kernel release: {release}")
        package = (root / "usr/lib/modules" / release / "pkgbase").read_text().strip()
        if package != "linux-omarchy-a16-7.2.10-" + release.rsplit("-", 1)[1]:
            raise ValueError("standalone kernel pkgbase does not identify its versioned payload")
    else:
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
    if versioned:
        metadata = json.loads((modules / "zenbook-a16-boot.json").read_text())
        config = root / f"usr/share/doc/{package}/config"
        if (not isinstance(metadata, dict) or type(metadata.get("schema")) is not int
                or metadata.get("schema") != 1 or metadata.get("kernel_release") != release
                or metadata.get("kernel_package") != package
                or metadata.get("dsp_policy") != "omarchy-a16-legacy-v1"
                or not isinstance(metadata.get("source_tree"), str)
                or not re.fullmatch(r"[0-9a-f]{40}", metadata["source_tree"])):
            raise ValueError("standalone kernel lacks its build-bound legacy DSP metadata")
        verify_image(modules / "vmlinuz")
        for name, content in (("kernel", kernel), ("dtb", dtb), ("config", config.read_bytes())):
            if metadata.get(f"{name}_sha256") != hashlib.sha256(content).hexdigest():
                raise ValueError(f"standalone kernel metadata does not match the installed {name}")
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


def checked_output(command, **kwargs):
    kwargs.setdefault("text", True)
    try:
        return subprocess.check_output(command, stderr=subprocess.PIPE, **kwargs)
    except FileNotFoundError as error:
        raise ValueError(f"required verification tool missing: {command[0]}; install it before retrying") from error
    except subprocess.CalledProcessError as error:
        raise ValueError(f"{command[0]} failed: {error.stderr!r}") from error


def check_initramfs_firmware(path, tool="lsinitrd", required_files=()):
    """Inspect extracted archive members, never filenames in compressed bytes."""
    if not path.is_file() or path.stat().st_size == 0:
        return False
    with tempfile.TemporaryDirectory(prefix="a16-initrd-") as directory:
        extracted = Path(directory).resolve()
        if tool == "lsinitrd":
            checked_output([tool, "--unpack", str(path.resolve())], cwd=directory)
            trees = [extracted]
        else:
            checked_output([tool, str(path.resolve()), str(extracted / "unpacked")])
            unpacked = extracted / "unpacked"
            trees = [unpacked / "main", unpacked / "early2", unpacked / "early", unpacked]
        def member(relative):
            # Later initramfs archives override early archive members.
            return next((tree / relative for tree in trees
                         if (tree / relative).exists() or (tree / relative).is_symlink()), None)

        def nonempty(candidate):
            return (candidate is not None and candidate.resolve().is_relative_to(extracted)
                    and candidate.is_file() and candidate.stat().st_size > 0)

        for name in ("qcadsp8480.mbn", "adsp_dtbs.elf", "qccdsp8480.mbn", "cdsp_dtbs.elf"):
            found = False
            for prefix in ("lib/firmware", "usr/lib/firmware"):
                for suffix, decoder in (("", None), (".zst", "zstd"), (".xz", "xz")):
                    candidate = member(f"{prefix}/qcom/glymur/ASUSTeK/UX3607OA/{name}{suffix}")
                    if nonempty(candidate):
                        if decoder and not checked_output([decoder, "-dc", str(candidate)], text=False):
                            continue
                        found = True
            if not found:
                return False
        for relative, source in required_files:
            candidate = member(relative)
            if not nonempty(candidate) or candidate.read_bytes() != source.read_bytes():
                raise ValueError(f"initramfs missing or stale pre-root DSP policy member: {relative}")
    return True


def initramfs_policy_files(root, tool):
    files = [("usr/lib/zenbook-a16/dsp-policy.sh", root / "usr/lib/zenbook-a16/dsp-policy.sh"),
             ("etc/modprobe.d/zenbook-a16-remoteproc.conf", root / "usr/share/omarchy-a16/remoteproc-blacklist.conf")]
    if tool == "lsinitrd":
        files.append(("lib/dracut/hooks/pre-mount/01-zenbook-a16-pre-udev.sh",
                      root / "usr/lib/dracut/modules.d/90zenbook-a16/zenbook-a16-pre-udev.sh"))
    else:
        files.append(("scripts/init-premount/zenbook-a16",
                      root / "etc/initramfs-tools/scripts/init-premount/zenbook-a16"))
    return files


def verify_dtb(dtb_path):
    if not dtb_path.is_file() or dtb_path.stat().st_size == 0:
        raise ValueError(f"DTB missing or empty: {dtb_path}")
    checked_output(["dtc", "-I", "dtb", "-O", "dts", str(dtb_path)])
    compatible = checked_output(["fdtget", "-t", "s", str(dtb_path), "/", "compatible"]).split()
    if "asus,zenbook-a16-ux3607oa" not in compatible:
        raise ValueError(f"DTB is not for the ASUS A16: {dtb_path}")
    for node in ("/soc@0/soundwire@6c80000", "/soc@0/soundwire@6ca0000"):
        properties = checked_output(["fdtget", "-p", str(dtb_path), node]).split()
        status = checked_output(["fdtget", "-t", "s", str(dtb_path), node, "status"]).strip()
        compatible = checked_output(["fdtget", "-t", "s", str(dtb_path), node, "compatible"]).split()
        if ("qcom,keep-runtime-active" not in properties or status not in ("okay", "ok")
                or "qcom,soundwire-v3.1.0" not in compatible):
            raise ValueError(f"DTB lacks an enabled SoundWire controller with qcom,keep-runtime-active: {node}")
    return True


def kernel_release(root, release):
    if not release:
        for package in ("linux-zenbook-a16", "linux-omarchy-a16"):
            metadata = root / f"usr/share/doc/{package}/kernel-release"
            if metadata.is_file():
                release = metadata.read_text().strip()
                break
    if not release:
        images = sorted((root / "boot").glob("vmlinuz-*"))
        if len(images) != 1:
            raise ValueError("cannot determine one kernel release; specify --kernel-release")
        release = images[0].name.removeprefix("vmlinuz-")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", release):
        raise ValueError(f"invalid kernel release: {release!r}")
    return release


def validate_kernel_metadata(root, release, kernel, dtb, modules_dir=None):
    directory = modules_dir if modules_dir is not None else root / "usr/lib/modules" / release
    metadata = json.loads((directory / "zenbook-a16-boot.json").read_text())
    if (not isinstance(metadata, dict) or type(metadata.get("schema")) is not int
            or metadata.get("schema") != 1 or metadata.get("kernel_release") != release
            or metadata.get("dsp_policy") != "pre-root-v1"):
        raise ValueError("kernel metadata lacks the supported A16 pre-root DSP policy; rebuild the kernel bundle")
    for key, path in (("kernel_sha256", kernel), ("dtb_sha256", dtb)):
        if metadata.get(key) != hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError(f"kernel metadata {key} does not match {path}; rebuild the kernel bundle")
    options = metadata.get("cmdline")
    if (not isinstance(options, list) or not options
            or any(not isinstance(option, str) or not re.fullmatch(r"[A-Za-z0-9_.,=+:/-]+", option)
                   for option in options)
            or len({option.split("=", 1)[0] for option in options}) != len(options)):
        raise ValueError("kernel metadata must contain unique literal cmdline parameters")
    return metadata


def verify_image(path):
    with path.open("rb") as image:
        header = image.read(64)
        if len(header) != 64 or header[56:60] != b"ARM\x64":
            raise ValueError(f"not a raw arm64 Image: {path}")
        # image_size includes zero-filled BSS; it is a memory size, not a file size.
        if struct.unpack_from("<Q", header, 16)[0] < 64:
            raise ValueError(f"invalid arm64 Image memory size: {path}")
        if header[:2] == b"MZ":
            image.seek(struct.unpack_from("<I", header, 60)[0])
            pe = image.read(24)
            if len(pe) != 24 or pe[:4] != b"PE\0\0" or struct.unpack_from("<H", pe, 4)[0] != 0xaa64:
                raise ValueError(f"invalid arm64 Image PE header: {path}")
            count = struct.unpack_from("<H", pe, 6)[0]
            image.seek(struct.unpack_from("<H", pe, 20)[0], 1)
            table = image.read(count * 40)
            if count == 0 or len(table) != count * 40:
                raise ValueError(f"truncated arm64 Image PE sections: {path}")
            for index in range(count):
                size, offset = struct.unpack_from("<II", table, index * 40 + 16)
                if size and offset + size > path.stat().st_size:
                    raise ValueError(f"truncated arm64 Image PE section: {path}")


def boot_surface(root, path):
    """Refuse layouts where current-root files do not prove GRUB's view."""
    output = checked_output(["findmnt", "--json", "--target", str(path),
                             "--output", "TARGET,FSTYPE,FSROOT,UUID"])
    try:
        mount, = json.loads(output)["filesystems"]
        target = Path(mount["target"]).resolve()
        fstype, fsroot = mount["fstype"], mount["fsroot"]
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"cannot determine boot filesystem for {path}") from error
    if target not in (root.resolve(), (root / "boot").resolve()):
        raise ValueError(f"unsupported boot mount {target}; mount the target root and a separate /boot before verification")
    if fstype == "btrfs" and fsroot != "/":
        raise ValueError("Btrfs subvolume /boot cannot be verified against GRUB's top-level view; use a separate /boot filesystem")
    if fsroot != "/":
        raise ValueError(f"unsupported boot filesystem root {fsroot}; use a separate /boot filesystem")
    return target, mount.get("uuid")


def boot_path(surface, value):
    if not value.startswith("/") or any(character in value for character in "$();{}"):
        raise ValueError(f"boot entry requires a literal absolute artifact path: {value}")
    path = surface / value.lstrip("/")
    if not path.resolve().is_relative_to(surface):
        raise ValueError(f"boot artifact escapes its filesystem: {value}")
    return path


def require_options(options, required):
    for parameter in required:
        key = parameter.split("=", 1)[0]
        matches = [option for option in options if option.split("=", 1)[0] == key]
        if matches != [parameter]:
            raise ValueError(f"boot entry missing or conflicting required cmdline parameter: {parameter}")
    if any(any(character in option for character in "$;{}()") for option in options):
        raise ValueError("unresolved or unsupported boot entry options; expand kernelopts before verification")
    roots = [option for option in options if option.startswith("root=")]
    if len(roots) != 1 or roots[0] == "root=":
        raise ValueError("boot entry requires exactly one nonempty root= option")


def verify_entry(root, release, surface, directives, tool):
    for key in ("linux", "initrd", "devicetree", "options"):
        if len(directives.get(key, [])) != 1:
            raise ValueError(f"boot entry requires exactly one {key} directive")
    for key in ("linux", "initrd", "devicetree"):
        if len(directives[key][0]) != 1:
            raise ValueError(f"boot entry requires one literal {key} artifact")
    kernel = boot_path(surface, directives["linux"][0][0])
    initrd = boot_path(surface, directives["initrd"][0][0])
    dtb = boot_path(surface, directives["devicetree"][0][0])
    expected_kernel = root / f"boot/vmlinuz-{release}"
    expected_initrds = [root / f"boot/initramfs-{release}.img", root / f"boot/initrd.img-{release}"]
    if kernel.resolve() != expected_kernel.resolve() or initrd.resolve() not in [p.resolve() for p in expected_initrds]:
        raise ValueError(f"boot entry artifacts do not match kernel release {release}")
    if not dtb.resolve().is_relative_to((root / "boot").resolve()):
        raise ValueError("boot entry DTB must be staged under /boot")
    metadata = validate_kernel_metadata(root, release, kernel, dtb)
    require_options(directives["options"][0], metadata["cmdline"])
    verify_image(kernel)
    if not check_initramfs_firmware(initrd, tool, initramfs_policy_files(root, tool)):
        raise ValueError(f"initramfs lacks nonempty ASUS DSP firmware and DSP DTBs: {initrd}")
    verify_dtb(dtb)
    return kernel, initrd, dtb


def verify_grub_bls(root, release=None):
    release = kernel_release(root, release)
    entries = sorted((root / "boot/loader/entries").glob("*.conf"))
    matching = []
    for entry in entries:
        directives = {}
        for line in entry.read_text().splitlines():
            words = shlex.split(line, comments=True)
            if words:
                directives.setdefault(words[0], []).append(words[1:])
        if directives.get("version") == [[release]] or release in entry.stem:
            if directives.get("version") != [[release]]:
                raise ValueError(f"BLS entry has missing or mismatched version: {entry}")
            matching.append((entry, directives))
    if not matching:
        raise ValueError(f"no BLS entry for kernel {release} in /boot/loader/entries")
    for entry, directives in matching:
        surface, _ = boot_surface(root, entry)
        kernel, initrd, dtb = verify_entry(root, release, surface, directives, "lsinitrd")
    return {"status": "pass", "bootloader": "grub-bls", "kernel_release": release,
            "vmlinuz": str(kernel), "initramfs": str(initrd), "dtb": str(dtb)}


def verify_grub_ubuntu(root, release=None):
    release = kernel_release(root, release)
    config = root / "boot/grub/grub.cfg"
    surface, uuid = boot_surface(root, config)
    if not uuid:
        raise ValueError("cannot determine boot filesystem UUID for GRUB search validation")
    normal_id = f"zenbook-a16-{release}"
    wanted = {normal_id, f"{normal_id}-rescue"}
    matching = {}
    fdt_loaded = False
    directives = None
    depth = conditional_depth = outer_braces = 0
    for line in config.read_text().splitlines():
        words = shlex.split(line, comments=True)
        if not words:
            continue
        if directives is None and conditional_depth == 0 and outer_braces == 0 and words == ["insmod", "fdt"]:
            fdt_loaded = True
        if words[0] == "menuentry" and words[-1] == "{":
            if directives is not None:
                raise ValueError("nested GRUB menuentry is unsupported")
            entry_id = next((word.removeprefix("--id=") for word in words if word.startswith("--id=")), None)
            if "--id" in words and words.index("--id") + 1 < len(words):
                entry_id = words[words.index("--id") + 1]
            directives = {"fdt_loaded": fdt_loaded, "search": [],
                          "unsupported": conditional_depth != 0, "id": entry_id}
            depth = 1
            continue
        if words[0] in ("if", "for", "while", "until", "case"):
            conditional_depth += 1
        elif words[0] in ("fi", "done", "esac"):
            conditional_depth -= 1
        if directives is None:
            outer_braces += words.count("{") - words.count("}")
            continue
        if words[0] == "search":
            directives["search"].append(words[1:])
        elif words[0] in ("linux", "linuxefi", "initrd", "initrdefi", "devicetree"):
            if conditional_depth:
                directives["unsupported"] = True
            if words[0] in ("linux", "linuxefi"):
                directives.setdefault("linux", []).append(words[1:2])
                directives.setdefault("options", []).append(words[2:])
            else:
                key = "initrd" if words[0] == "initrdefi" else words[0]
                directives.setdefault(key, []).append(words[1:])
        elif (words[0] in ("eval", "source", "configfile", "chainloader")
              or words[0] == "set" and any(word.startswith("root=") for word in words[1:])
              and directives["search"]):
            directives["unsupported"] = True
        depth += words.count("{") - words.count("}")
        if depth == 0:
            if directives["id"] in wanted:
                if directives["id"] in matching:
                    raise ValueError(f"duplicate A16 GRUB menuentry ID: {directives['id']}")
                matching[directives["id"]] = directives
            directives = None
    if directives is not None or conditional_depth != 0 or outer_braces != 0:
        raise ValueError("unterminated GRUB menuentry or control block")
    if normal_id not in matching:
        raise ValueError(f"no complete GRUB menuentry with --id {normal_id}")
    for directives in matching.values():
        if directives["unsupported"]:
            raise ValueError("unsupported conditional artifacts or root override in A16 GRUB menuentry; regenerate the A16 entry")
        if not directives["fdt_loaded"]:
            raise ValueError("GRUB requires unconditional insmod fdt before the A16 menuentry")
        searches = directives["search"]
        if not searches or any("--fs-uuid" not in search or "--set=root" not in search
                               or search[-1] != uuid for search in searches):
            raise ValueError("GRUB menuentry must search --fs-uuid --set=root for the verified boot filesystem UUID")
        kernel, initrd, dtb = verify_entry(root, release, surface, directives, "unmkinitramfs")
    return {"status": "pass", "bootloader": "grub-ubuntu", "kernel_release": release,
            "vmlinuz": str(kernel), "initrd": str(initrd), "dtb": str(dtb)}


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

    parser.add_argument("--validate-kernel", action="store_true", help="Validate bundle artifacts against kernel policy metadata")
    parser.add_argument("--modules-dir", type=Path)
    parser.add_argument("--kernel-image", type=Path)
    parser.add_argument("--dtb-image", type=Path)
    parser.add_argument("--initramfs-image", type=Path, help="Also verify a dracut initramfs against policy sources under --root")

    args = parser.parse_args()
    root = Path(args.root)

    if args.validate_kernel:
        if not all((args.release, args.modules_dir, args.kernel_image, args.dtb_image)):
            parser.error("--validate-kernel requires --kernel-release, --modules-dir, --kernel-image and --dtb-image")
        try:
            kernel_release(root, args.release)
            verify_image(args.kernel_image)
            verify_dtb(args.dtb_image)
            validate_kernel_metadata(root, args.release, args.kernel_image, args.dtb_image, args.modules_dir)
            if args.initramfs_image and not check_initramfs_firmware(
                    args.initramfs_image, "lsinitrd", initramfs_policy_files(root, "lsinitrd")):
                raise ValueError("initramfs lacks nonempty ASUS DSP firmware and DSP DTBs")
        except (OSError, ValueError, UnicodeError, struct.error) as error:
            parser.exit(1, f"A16 kernel policy validation failed: {error}\n")
        print(f"A16 kernel policy validated: {args.release}")
        return

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
            report = verify(root, args.release)
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
