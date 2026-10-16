#!/usr/bin/env python3
"""Create a self-contained, checksum-pinned makepkg directory."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New makepkg output directory")
    parser.add_argument("--pkgrel", type=int, default=3, help="Positive rebuild revision (default: 3)")
    args = parser.parse_args()
    if args.pkgrel < 1:
        parser.error("--pkgrel must be positive")
    here = Path(__file__).resolve().parent
    meta = json.loads((here / "build.json").read_text())
    files = []
    for line in (here / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        path = (here / name).resolve()
        if not path.is_relative_to(here):
            raise SystemExit(f"invalid source path: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f"checksum mismatch: {name}")
        files.append(name)
    files.append("SHA256SUMS")
    # Normalize archive metadata. The source bundle is reproducible independently
    # of the filesystem, builder identity and checkout timestamps.
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name in sorted(files):
            data = (here / name).read_bytes()
            info = tarfile.TarInfo("a16-backport/" + name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    data = lzma.compress(raw.getvalue(), preset=6)
    recipe = (here / "PKGBUILD.in").read_text()
    for key, value in {
        "@PKGREL@": str(args.pkgrel),
        "@KERNEL_PACKAGE@": f"linux-omarchy-a16-7.2.10-{args.pkgrel}",
        "@KERNEL_RELEASE@": f"7.2.10-omarchy-a16-{args.pkgrel}",
        "@BASE_SHA256@": meta["base_archive_sha256"],
        "@STABLE_SHA256@": meta["stable_patch_sha256"],
        "@BUNDLE_SHA256@": hashlib.sha256(data).hexdigest(),
        "@SOURCE_TREE@": meta["source_tree"],
        "@BASE_TREE@": meta["base_tree"],
    }.items():
        recipe = recipe.replace(key, value)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / "a16-backport.tar.xz").write_bytes(data)
    (output / "PKGBUILD").write_text(recipe)
    print(f"Created {output}; run makepkg in an Arch Linux ARM build environment")


if __name__ == "__main__":
    main()
