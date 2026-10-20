#!/usr/bin/env python3
"""Exercise build retries with real Git worktrees and a tiny failing Makefile."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
BUILDS = ("rc5-20261013", "rc5-qcom-bridge-20261018")


class BuildResumeChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.linux = self.root / "linux"
        self.linux.mkdir()
        self.project = self.root / "project"
        self.env = {**os.environ, "BUILD_RPM": "0", "BUILD_DEB": "0", "STAGE_BUNDLE": "0",
                    "PACKAGE_REVISION": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                    "GIT_CONFIG_SYSTEM": os.devnull, "GIT_AUTHOR_NAME": "Fixture",
                    "GIT_AUTHOR_EMAIL": "fixture@localhost", "GIT_COMMITTER_NAME": "Fixture",
                    "GIT_COMMITTER_EMAIL": "fixture@localhost"}
        self.git(self.linux, "init", "-q")
        (self.linux / "Makefile").write_text(
            ".PHONY: olddefconfig kernelrelease Image modules dtbs\n"
            "olddefconfig:\n\t@echo olddefconfig >> '$(O)/calls'\n"
            "kernelrelease:\n\t@echo fixture$(LOCALVERSION)\n"
            "Image:\n\t@test -f '$(O)/retained.o' || "
            "{ echo object > '$(O)/retained.o'; echo 'missing dependency' >&2; exit 37; }\n"
            "\t@mkdir -p '$(O)/arch/arm64/boot/dts/qcom'\n"
            "\t@echo dtb > '$(O)/arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb'\n"
            "modules dtbs:\n\t@:\n")
        merge = self.linux / "scripts/kconfig/merge_config.sh"
        merge.parent.mkdir(parents=True)
        merge.write_text('#!/bin/sh\ncp "$4" "$3/.config"\n')
        merge.chmod(0o755)
        self.git(self.linux, "add", ".")
        self.git(self.linux, "commit", "-qm", "Fixture base")
        base = self.git(self.linux, "rev-parse", "HEAD")
        (self.linux / "patched").write_text("patched source\n")
        self.git(self.linux, "add", ".")
        self.git(self.linux, "commit", "-qm", "Fixture patch")
        tree = self.git(self.linux, "rev-parse", "HEAD^{tree}")
        series = self.project / "patches/rc5-20261013"
        series.mkdir(parents=True)
        (series / "fixture.patch").write_text(self.git(self.linux, "format-patch", "-1", "--stdout") + "\n")
        (series / "series").write_text("fixture.patch\n")
        bridge = self.project / "patches/qcom-glymur-bridge-20261018"
        bridge.mkdir()
        (bridge / "series").write_text("")
        for build in BUILDS:
            folder = self.project / "kernel" / build
            folder.mkdir(parents=True)
            for name in ("build.sh", "verify.py"):
                shutil.copy2(REPO / "kernel" / build / name, folder / name)
            (folder / "build.json").write_text(json.dumps({
                "base": base, "source_tree": tree, "release": "fixture+", "patch_count": 1,
                "base_patch_count": 1, "bridge_patch_count": 0, "prior_source_tree": tree}))
            (folder / "config").write_text("CONFIG_FIXTURE=y\n")
            (folder / "SHA256SUMS").write_text("")
        (self.project / "kernel/qcom-glymur-bridge.config").write_text("")
        commands = self.root / "commands"
        commands.mkdir()
        for name in ("dtc", "fdtget"):
            command = commands / name
            command.write_text("#!/bin/sh\necho 'qcom,keep-runtime-active;'\n")
            command.chmod(0o755)
        self.env["PATH"] = f"{commands}:{os.environ['PATH']}"
        self.other = self.root / "other.git"
        self.git(self.root, "clone", "--bare", "-q", str(self.linux), str(self.other))

    def git(self, directory, *args):
        return subprocess.check_output(["git", "-C", str(directory), *args],
                                       env=self.env, text=True, stderr=subprocess.PIPE).strip()

    def run_build(self, build, resume=False, linux=None):
        return subprocess.run(
            ["bash", str(self.project / "kernel" / build / "build.sh"),
             *(["--resume"] if resume else []), str(linux or self.linux), str(self.root / build)],
            env=self.env, text=True, capture_output=True)

    def test_failed_build_reuses_patches_config_and_objects(self):
        for build in BUILDS:
            with self.subTest(build=build):
                linux = self.other if "bridge" in build else self.linux
                result = self.run_build(build, linux=linux)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("missing dependency", result.stderr)
                output = self.root / build
                source = output / "source"
                head = self.git(source, "rev-parse", "HEAD")
                obj = output / "build/retained.o"
                stat = obj.stat()
                config = output / "build/.config"
                config.write_text(config.read_text() + "CONFIG_PRESERVED=y\n")
                self.assertNotEqual(self.run_build(build, linux=linux).returncode, 0)
                result = self.run_build(build, resume=True, linux=linux)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Build complete", result.stdout)
                self.assertEqual(self.git(source, "rev-parse", "HEAD"), head)
                self.assertIn("CONFIG_PRESERVED=y", config.read_text())
                self.assertEqual((obj.stat().st_ino, obj.stat().st_mtime_ns), (stat.st_ino, stat.st_mtime_ns))

    def test_resume_refuses_missing_modified_wrong_or_unfinished_source(self):
        for build in BUILDS:
            with self.subTest(build=build):
                self.assertNotEqual(self.run_build(build, resume=True).returncode, 0)
                self.run_build(build)
                output = self.root / build
                source = output / "source"
                calls = output / "build/calls"
                before = calls.read_bytes()
                for path in (source / "patched", source / "untracked"):
                    path.write_text("modified\n")
                    result = self.run_build(build, resume=True)
                    self.assertIn("modified worktree", result.stderr)
                    if path.name == "patched":
                        self.git(source, "checkout", "--", "patched")
                    else:
                        path.unlink()
                (source / "patched").write_text("staged change\n")
                self.git(source, "add", "patched")
                self.assertIn("modified worktree", self.run_build(build, resume=True).stderr)
                self.git(source, "restore", "--staged", "--worktree", "patched")
                state = Path(self.git(source, "rev-parse", "--git-path", "rebase-apply"))
                state.mkdir()
                self.assertIn("unfinished git am", self.run_build(build, resume=True).stderr)
                state.rmdir()
                self.assertIn("different Linux repository", self.run_build(build, resume=True, linux=self.other).stderr)
                self.git(source, "checkout", "--detach", "HEAD^")
                self.assertIn("patched source tree", self.run_build(build, resume=True).stderr)
                self.assertEqual(calls.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
