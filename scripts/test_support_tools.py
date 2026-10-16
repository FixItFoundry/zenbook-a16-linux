#!/usr/bin/env python3
"""Exercise firmware checks and CPU-profile errors without touching host sysfs."""
import os
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class BuildManifestChecks(unittest.TestCase):
    def test_current_build_inputs_match_recorded_checksums(self):
        manifest = REPO / "kernel/rc5-20261013/SHA256SUMS"
        for line in manifest.read_text().splitlines():
            expected, name = line.split("  ", 1)
            with self.subTest(file=name):
                self.assertEqual(hashlib.sha256((REPO / name).read_bytes()).hexdigest(), expected)


class FirmwareChecks(unittest.TestCase):
    def test_current_board_files_and_missing_rampatch(self):
        required = [
            "ath12k/QCC2072/hw1.0/board-2.bin",
            "ath12k/QCC2072/hw1.0/firmware-2.bin", "qca/clnbtfw10.tlv",
            "qcom/gen80500_sqe.fw", "qcom/gen80500_gmu.bin",
            "qcom/glymur/ASUSTeK/UX3607OA/qcadsp8480.mbn",
            "qcom/glymur/ASUSTeK/UX3607OA/adsp_dtbs.elf",
            "qcom/glymur/ASUSTeK/UX3607OA/qccdsp8480.mbn",
            "qcom/glymur/ASUSTeK/UX3607OA/cdsp_dtbs.elf",
            "qcom/glymur/GLYMUR-ASUS-Zenbook-A16-UX3607OA-tplg.bin",
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in required:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"firmware fixture")
            def check():
                return subprocess.run(
                    ["bash", str(REPO / "iso/glymur-fetch-firmware.sh"), "--check"],
                    env={**os.environ, "DEST": directory}, capture_output=True, text=True)
            self.assertEqual(check().returncode, 0)
            rampatch = root / "qca/clnbtfw10.tlv"
            rampatch.rename(root / "qca/hmtbtfw20.tlv")
            result = check()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("MISSING  qca/clnbtfw10.tlv", result.stdout)
            rampatch.touch()
            self.assertNotEqual(check().returncode, 0)


class CpuProfileChecks(unittest.TestCase):
    def run_profile(self, break_target=None, profile="balanced"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for policy in ("policy0", "policy6", "policy12"):
                path = root / policy
                path.mkdir()
                (path / "cpuinfo_max_freq").write_text("4723200\n")
                (path / "scaling_max_freq").write_text("4723200\n")
                (path / "boost").write_text("1\n")
            if break_target:
                path = root / break_target
                path.unlink()
                path.mkdir()  # A write fails even when tests run as root.
            script = root / "profile.sh"
            script.write_text((REPO / "tweaks/usr/local/bin/glymur-cpu-profile.sh").read_text()
                              .replace("CPUFREQ=/sys/devices/system/cpu/cpufreq", f'CPUFREQ="{root}"'))
            logger = root / "logger"
            logger.write_text("#!/bin/sh\nexit 0\n")
            logger.chmod(0o755)
            result = subprocess.run(["bash", str(script), profile], text=True, capture_output=True,
                                    env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}"})
            limits = [(root / p / "scaling_max_freq").read_text().strip()
                      for p in ("policy0", "policy6", "policy12")
                      if (root / p / "scaling_max_freq").is_file()]
            return result, limits

    def test_balanced_caps_are_applied(self):
        result, limits = self.run_profile()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(limits, ["2918400", "3628800", "3628800"])

    def test_write_failures_never_report_success(self):
        for target, profile in (("policy6/scaling_max_freq", "balanced"),
                                ("policy6/boost", "balanced"),
                                ("policy6/scaling_max_freq", "reset")):
            with self.subTest(target=target, profile=profile):
                result, _ = self.run_profile(target, profile)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("applied", result.stdout)
                self.assertNotIn("reset: all policies", result.stdout)


if __name__ == "__main__":
    unittest.main()
