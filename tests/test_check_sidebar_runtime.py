"""Native sidebar fixture configuration must be explicit, safe, and archivable."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tests/runtime/check-sidebar.sh"


class CheckSidebarRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "native.log"
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        omarchy_shell = self.root / "omarchy" / "shell"
        omarchy_shell.mkdir(parents=True)
        self.write_command("hyprctl", "printf '[]\\n'")
        self.write_command("qs", "printf '%s\\n' '{\"event\":\"ready\"}'")

    def tearDown(self):
        self.directory.cleanup()

    def write_command(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def run_native(self, override):
        path = self.root / "override.json"
        path.write_text(override)
        environment = os.environ | {
            "SMARTDOCK_ISOLATED_RUNTIME": "1",
            "SMARTDOCK_RUNTIME_LOG": str(self.log),
            "SMARTDOCK_NATIVE_CONFIG_OVERRIDE": str(path),
            "SMARTDOCK_NATIVE_EVIDENCE_DIR": str(self.evidence),
            "OMARCHY_PATH": str(self.root / "omarchy"),
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
        }
        return subprocess.run([str(SCRIPT), "--native"], cwd=ROOT, env=environment,
                              text=True, capture_output=True)

    def test_native_override_is_applied_and_initial_config_is_archived(self):
        result = self.run_native(json.dumps({
            "sidebarWidgets": ["herdr.agents", "example.clock"],
            "sidebarWidgetCollapsed": {"example.clock": True},
            "sidebarExpandedWidth": 400,
        }))
        self.assertEqual(result.returncode, 0, result.stderr)
        config = self.evidence / "native-initial-fixture-config.json"
        archived = json.loads(config.read_text())
        self.assertEqual(archived["presentationMode"], "sidebar")
        self.assertEqual(archived["sidebarWidgets"], ["herdr.agents", "example.clock"])
        self.assertTrue(archived["sidebarWidgetCollapsed"]["example.clock"])
        self.assertEqual(archived["sidebarExpandedWidth"], 400)
        digest = (self.evidence / "native-initial-fixture-config.sha256").read_text()
        self.assertEqual(digest, hashlib.sha256(config.read_bytes()).hexdigest() + "  " + config.name + "\n")

    def test_malformed_or_private_override_fails_closed_without_archive(self):
        for override in ('{"sidebarWidgets":',
                         '{"sidebarWidgets":"herdr.agents","token":"private"}'):
            with self.subTest(override=override):
                result = self.run_native(override)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("SMARTDOCK_NATIVE_CONFIG_OVERRIDE", result.stderr)
                self.assertEqual(list(self.evidence.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
