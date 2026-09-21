import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "smartdock_seed_demo_widgets.py"
SPEC = importlib.util.spec_from_file_location("seed_demo_widgets", MODULE_PATH)
seed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(seed)


class DemoWidgetSeedTests(unittest.TestCase):
    def setup_paths(self, payload):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        config = root / "dock.json"
        marker = root / ".demo-widgets-seeded-v2"
        config.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        return config, marker

    def test_existing_real_widget_is_preserved_and_demos_are_appended(self):
        config, marker = self.setup_paths({"sidebarWidgets": ["herdr.agents"], "pinned": []})
        self.assertEqual(seed.seed_demo_widgets(config, marker), "seeded")
        self.assertEqual(
            json.loads(config.read_text())["sidebarWidgets"],
            ["herdr.agents"] + seed.DEMO_WIDGET_IDS,
        )
        self.assertTrue(marker.exists())

    def test_marker_prevents_readding_after_user_removes_demo(self):
        config, marker = self.setup_paths({"sidebarWidgets": ["herdr.agents"], "pinned": []})
        seed.seed_demo_widgets(config, marker)
        data = json.loads(config.read_text())
        data["sidebarWidgets"].remove("demo.inputs")
        config.write_text(json.dumps(data) + "\n", encoding="utf-8")
        self.assertEqual(seed.seed_demo_widgets(config, marker), "already")
        self.assertNotIn("demo.inputs", json.loads(config.read_text())["sidebarWidgets"])

    def test_empty_selection_gets_all_demos(self):
        config, marker = self.setup_paths({"sidebarWidgets": [], "pinned": []})
        self.assertEqual(seed.seed_demo_widgets(config, marker), "seeded")
        self.assertEqual(json.loads(config.read_text())["sidebarWidgets"], seed.DEMO_WIDGET_IDS)

    def test_invalid_widget_type_is_not_touched(self):
        config, marker = self.setup_paths({"sidebarWidgets": "broken", "pinned": []})
        before = config.read_text()
        self.assertEqual(seed.seed_demo_widgets(config, marker), "invalid")
        self.assertEqual(config.read_text(), before)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
