"""The portable runner must dispatch checks without local agent tooling."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("verify.sh")


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="poc runner ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        binary = self.root / "bin"; binary.mkdir()
        for name in ("xcodebuild", "python3"):
            stub = binary / name
            stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$CAPTURE"\n')
            stub.chmod(0o755)
        self.capture = self.root / "arguments.txt"
        self.env = dict(os.environ, PATH=str(binary) + ":/usr/bin:/bin", CAPTURE=str(self.capture),
                        POC_OUTPUT_DIR=str(self.root / "output"))
        for name in ("POC_SWIFT_PACKAGES_DIR", "TJ_GTFS_ZIP"):
            self.env.pop(name, None)

    def run_check(self, mode):
        completed = subprocess.run(["/bin/bash", str(SCRIPT), mode], env=self.env,
                                   capture_output=True, text=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return self.capture.read_text().splitlines()

    def test_build_dispatches_four_apps_without_rtk_or_optional_cache(self):
        args = self.run_check("build")
        self.assertEqual(args.count("-scheme"), 4)
        for scheme in ("poc-c67", "C67FoundationLab", "C67TripIntegration", "C67JourneyShowcase"):
            self.assertIn(scheme, args)
        self.assertNotIn("-clonedSourcePackagesDirPath", args)

    def test_dependency_cache_path_with_spaces_stays_one_argument(self):
        self.env["POC_SWIFT_PACKAGES_DIR"] = str(self.root / "public package cache")
        args = self.run_check("build")
        self.assertEqual(args.count(self.env["POC_SWIFT_PACKAGES_DIR"]), 4)
        self.assertEqual(args.count("-disableAutomaticPackageResolution"), 4)

    def test_tj_dispatch_supports_missing_or_explicit_zip(self):
        args = self.run_check("transjakarta")
        self.assertIn("unittest", args)
        self.assertNotIn("--gtfs-zip", args)
        self.capture.unlink()
        self.env["TJ_GTFS_ZIP"] = str(self.root / "captured snapshot.zip")
        args = self.run_check("transjakarta")
        self.assertEqual(args[args.index("--gtfs-zip") + 1], self.env["TJ_GTFS_ZIP"])


if __name__ == "__main__":
    unittest.main()
