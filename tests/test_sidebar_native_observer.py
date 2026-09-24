"""Static safety and coverage guards for the guest-only sidebar observer."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
OBSERVER = ROOT / "tests/runtime/sidebar-native.qml"


class SidebarNativeObserverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = OBSERVER.read_text()

    def test_observes_all_panels_and_inline_badge_inputs(self):
        self.assertIn("root.host.sidebarPanels || []", self.source)
        self.assertIsNone(re.search(r"root\.host\.sidebarPanel(?!s)", self.source))
        self.assertIn("inlineWorkspaceBadgeAnchor", self.source)
        self.assertIn('sourceType:"inline-workspace-badge"', self.source)
        self.assertIn("panels.forEach(function(panel)", self.source)

    def test_records_are_constructed_without_object_dumps(self):
        self.assertEqual(self.source.count('console.log("sidebar-native: "'), 1)
        for unsafe in ("JSON.stringify(target)", "JSON.stringify(operation)",
                       "JSON.stringify(row)", "currentToplevels()",
                       "currentWorkspaces()", "toplevel:operation.toplevel",
                       "snapshot:viewport.dropPresentation"):
            with self.subTest(unsafe=unsafe):
                self.assertNotIn(unsafe, self.source)
        for required in ("targetRecord", "rejectionRecord", "operationRecord",
                         "originSurfaceGeneration", "expectedWorkspace",
                         "pendingRestore", "dropFlashOpacity"):
            with self.subTest(required=required):
                self.assertIn(required, self.source)


if __name__ == "__main__":
    unittest.main()
