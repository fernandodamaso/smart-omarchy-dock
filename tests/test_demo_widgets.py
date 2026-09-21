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
    def run_seed(self, payload):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        config = root / "dock.json"
        marker = root / ".demo-widgets-seeded-v1"
        config.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        result = seed.seed_demo_widgets(config, marker)
        return config, marker, result

    def test_empty_widget_list_is_seeded_once(self):
        config, marker, result = self.run_seed({"sidebarWidgets": [], "pinned": []})
        self.assertEqual(result, "seeded")
        self.assertEqual(json.loads(config.read_text())["sidebarWidgets"], seed.DEMO_WIDGET_IDS)
        self.assertTrue(marker.exists())

        data = json.loads(config.read_text())
        data["sidebarWidgets"] = []
        config.write_text(json.dumps(data) + "\n")
        self.assertEqual(seed.seed_demo_widgets(config, marker), "already")
        self.assertEqual(json.loads(config.read_text())["sidebarWidgets"], [])

    def test_missing_widget_key_is_seeded(self):
        config, marker, result = self.run_seed({"pinned": []})
        self.assertEqual(result, "seeded")
        self.assertEqual(json.loads(config.read_text())["sidebarWidgets"], seed.DEMO_WIDGET_IDS)
        self.assertTrue(marker.exists())

    def test_existing_nonempty_widget_selection_is_preserved_and_marked(self):
        config, marker, result = self.run_seed({"sidebarWidgets": ["future.clock"], "pinned": []})
        self.assertEqual(result, "preserved")
        self.assertEqual(json.loads(config.read_text())["sidebarWidgets"], ["future.clock"])
        self.assertTrue(marker.exists())

    def test_invalid_widget_type_is_not_touched_or_marked(self):
        config, marker, result = self.run_seed({"sidebarWidgets": "broken", "pinned": []})
        before = config.read_text()
        self.assertEqual(result, "invalid")
        self.assertEqual(config.read_text(), before)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
