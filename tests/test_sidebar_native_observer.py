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
                       "snapshot:viewport.dropPresentation", "settings:host.settings",
                       "widgetRegistry", "registeredRows", "scalar(item.objectName)",
                       "activeFocusItem:", "settingsLoadedText", "settingsWriteText",
                       "settingsWriteError", "savedAnchor.ids", "view.data",
                       "JSON.stringify(area.presentationWidgetIds)"):
            with self.subTest(unsafe=unsafe):
                self.assertNotIn(unsafe, self.source)
        for required in ("targetRecord", "rejectionRecord", "operationRecord",
                         "originSurfaceGeneration", "expectedWorkspace",
                         "pendingRestore", "dropFlashOpacity"):
            with self.subTest(required=required):
                self.assertIn(required, self.source)

    def test_records_allowlisted_split_scroll_qualification_scalars(self):
        for required in (
                "availableMiddleHeight", "hierarchyHeight", "widgetHeight", "blankHeight",
                "naturalDemand", "naturalHeaderDemand", "naturalContentDemand",
                "presentedCount", "maximumScroll", "presentationWidgetIds",
                "layoutRevision", "inputBusy", "safeFocusObjectName", "geometryRecord",
                "settingsWriteState", "widgetRevision", "enabledWidgetCount",
                "widgetManagerCounters", "acceptedUpdates", "managerOpen",
                "managerAnchorPosition", "conservationError", "conserved",
                "interval:2000", "lastStateSignature"):
            with self.subTest(required=required):
                self.assertIn(required, self.source)

    def test_focus_and_widget_ids_use_explicit_sanitizers(self):
        self.assertIn("safeNames.indexOf(name)", self.source)
        self.assertIn("focusedWidgetId(panel ? panel.widgetArea : null, item)", self.source)
        self.assertIn('owner || (widgetId ? "widget-card" : "")', self.source)
        self.assertIn("function safeWidgetId(value)", self.source)
        self.assertIn(".filter(function(id) { return id !== \"\" }).slice(0, 32)", self.source)
        self.assertIn("presentationWidgetIds.map(function(id)", self.source)
        self.assertNotIn("JSON.stringify(area.presentationWidgetIds)", self.source)

    def test_manager_geometry_uses_panel_local_anchor_and_native_popup_size(self):
        self.assertIn("manager.managerAnchorPosition.x", self.source)
        self.assertIn("width:managerPopup.width", self.source)
        self.assertNotIn("rectRecord(managerPopup", self.source)

    def test_connections_match_production_property_and_signal_contracts(self):
        contracts = {
            "components/DockSidebarViewport.qml": (
                "activationDispatched", "pendingRestore", "restoring", "dropSurfaceGeneration",
                "dropPresentation", "dropFlashKey", "dropFlashOpacity", "panelConnector",
                "presentationVisible", "naturalContentHeight", "rowCount", "listView"),
            "components/DockSidebarWidgetArea.qml": (
                "naturalWidgetHeaderHeight", "naturalWidgetContentHeight",
                "presentedWidgetCount", "layoutRevision", "pendingRestore", "restoring",
                "inputBusy", "presentationWidgetIds", "scrollView", "popupWindow",
                "popupGeometry", "maximumScroll", "savedAnchor", "sectionVisible", "cards"),
            "components/DockSidebarWidgetManager.qml": (
                "managerOpen", "managerAnchor", "managerAnchorPosition", "popupWindow"),
            "components/DockSidebarController.qml": (
                "scrollStates", "widgetRevision", "widgetPopupId", "interactionBusy",
                "widgetIds", "widgetReorderActive", "widgetManager"),
            "DockHost.qml": ("settingsRevision", "settingsWriteState"),
        }
        for relative_path, names in contracts.items():
            contract_source = (ROOT / relative_path).read_text()
            for name in names:
                with self.subTest(component=relative_path, name=name):
                    self.assertRegex(contract_source, rf"(?:property|signal|function)\s+[^\n;]*\b{name}\b")


if __name__ == "__main__":
    unittest.main()
