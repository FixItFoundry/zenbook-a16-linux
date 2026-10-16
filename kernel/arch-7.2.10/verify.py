#!/usr/bin/env python3
"""Verify the Arch/stable/A16 source stack without changing a checkout."""
import hashlib
import json
import lzma
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify.py LINUX_GIT_REPOSITORY patch-7.2.10.xz")
    kernel, stable = map(lambda p: Path(p).resolve(), sys.argv[1:])
    here = Path(__file__).resolve().parent
    meta = json.loads((here / "build.json").read_text())
    for line in (here / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        path = (here / name).resolve()
        if not path.is_relative_to(here):
            raise SystemExit(f"invalid checksum path: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit(f"checksum mismatch: {name}")
    data = stable.read_bytes()
    if hashlib.sha256(data).hexdigest() != meta["stable_patch_sha256"]:
        raise SystemExit("stable patch checksum mismatch")
    names = (here / "series").read_text().splitlines()
    if len(names) != meta["patch_count"] or len(set(names)) != len(names):
        raise SystemExit("invalid series length or duplicate patches")
    if any(Path(n).name != n or not n.endswith(".patch") for n in names):
        raise SystemExit("invalid patch name")
    with tempfile.TemporaryDirectory(prefix="a16-arch-verify-") as tmp:
        env = {**os.environ, "GIT_INDEX_FILE": str(Path(tmp) / "index")}

        def git(*args, data=None):
            result = subprocess.run(
                ["git", "-C", str(kernel), *args], env=env, input=data,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            if result.returncode:
                raise SystemExit(result.stderr.decode(errors="replace"))
            return result.stdout.decode().strip()

        git("read-tree", meta["base_commit"])
        if git("write-tree") != meta["base_tree"]:
            raise SystemExit("base tree mismatch")
        git("apply", "--cached", "--whitespace=nowarn", "-", data=lzma.decompress(data))
        for index, name in enumerate(names, 1):
            git("apply", "--cached", str(here / "patches" / name))
            if index == 5 and git("write-tree") != meta["arch_baseline_tree"]:
                raise SystemExit("Arch baseline mismatch")
        actual = git("write-tree")
        if actual != meta["source_tree"]:
            raise SystemExit(f"source tree mismatch: {actual}")
    print(f"PASS: verified stable patch + {len(names)} patches reproduce {actual}")


if __name__ == "__main__":
    main()
