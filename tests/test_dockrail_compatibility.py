#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("dockrail_paths", ROOT / "scripts/dockrail_paths.py")
paths = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(paths)

class DockrailPathTests(unittest.TestCase):
    def env(self, home, **extra):
        value = {"HOME": str(home)}
        value.update(extra)
        return value

    def test_defaults_are_canonical_and_side_effect_free(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            resolved = paths.resolve_paths(self.env(home))
            self.assertEqual(resolved.config_file, home / ".config/dockrail/dock.json")
            self.assertEqual(resolved.config_source, "canonical-default")
            self.assertEqual(resolved.legacy_config_root, home / ".config/smartdock")
            self.assertEqual(resolved.migration_root, home / ".local/state/dockrail/migrations")
            self.assertEqual(list(home.iterdir()), [])

    def test_canonical_override_wins(self):
        resolved = paths.resolve_paths(self.env("/tmp/home",
            DOCKRAIL_CONFIG="/tmp/new/dock.json",
            SMARTDOCK_CONFIG="/tmp/old/dock.json"))
        self.assertEqual(resolved.config_file, Path("/tmp/new/dock.json"))
        self.assertEqual(resolved.config_source, "DOCKRAIL_CONFIG")

    def test_legacy_override_is_accepted(self):
        resolved = paths.resolve_paths(self.env("/tmp/home",
            SMARTDOCK_CONFIG="/tmp/old/dock.json"))
        self.assertEqual(resolved.config_file, Path("/tmp/old/dock.json"))
        self.assertEqual(resolved.config_source, "SMARTDOCK_CONFIG")

    def test_empty_overrides_are_unset(self):
        resolved = paths.resolve_paths(self.env("/tmp/home",
            DOCKRAIL_CONFIG="", SMARTDOCK_CONFIG=""))
        self.assertEqual(resolved.config_source, "canonical-default")

    def test_custom_xdg_bases(self):
        resolved = paths.resolve_paths(self.env("/tmp/home",
            XDG_CONFIG_HOME="/cfg", XDG_DATA_HOME="/data",
            XDG_CACHE_HOME="/cache", XDG_STATE_HOME="/state", XDG_BIN_HOME="/bin"))
        self.assertEqual(resolved.canonical_config_root, Path("/cfg/dockrail"))
        self.assertEqual(resolved.legacy_data_root, Path("/data/smartdock"))
        self.assertEqual(resolved.canonical_client_root, Path("/data/dockrail-cli"))
        self.assertEqual(resolved.canonical_cache_root, Path("/cache/dockrail"))
        self.assertEqual(resolved.migration_root, Path("/state/dockrail/migrations"))
        self.assertEqual(resolved.bin_home, Path("/bin"))

class LauncherContractTests(unittest.TestCase):
    def test_legacy_launcher_is_thin(self):
        text = (ROOT / "scripts/smartdock").read_text()
        self.assertIn('exec "$script_dir/dockrail" "$@"', text)
        self.assertNotIn("qs ", text)
        self.assertNotIn("python3", text)

    def test_canonical_launcher_keeps_stable_ipc_client(self):
        text = (ROOT / "scripts/dockrail").read_text()
        self.assertIn("smartdock_cli.py", text)
        self.assertIn("SMARTDOCK_CONFIG", text)
        self.assertIn("DOCKRAIL_CONFIG", text)

    def test_installer_installs_both_commands(self):
        text = (ROOT / "install.sh").read_text()
        self.assertIn('"$bin_home/dockrail"', text)
        self.assertIn('"$bin_home/smartdock"', text)
        self.assertIn("dockrail_paths.py", text)

if __name__ == "__main__":
    unittest.main()
