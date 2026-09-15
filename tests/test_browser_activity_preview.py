"""Exercise production preview-session code with real Qt binding notifications.

Only compositor membership and rendering/anchoring are stubbed. The session
methods, activity bindings and change handlers are read from the production
component on every run, so the original assignment-order bug fails this test.
This does not qualify the graphical Quickshell popup or Hyprland focus.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def qml_block(source, declaration):
    pattern = r"^  " + re.escape(declaration) + r"[^\n]*\n.*?^  \}"
    match = re.search(pattern, source, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError("Missing production QML block: " + declaration)
    return match.group(0)


def preview_session_source():
    source = (ROOT / "components/DockWindowPreview.qml").read_text()
    state = source.split("  property Item anchorItem:", 1)[1].split(
        "  readonly property bool pending:", 1)[0]
    state = "  property Item anchorItem:" + state
    state = state.replace("property DockWorkspaceLayout clipItem", "property var clipItem")
    bindings = source.split("  readonly property var activityPresentation:", 1)[1].split(
        "  readonly property bool showWindowPreviews:", 1)[0]
    bindings = "  readonly property var activityPresentation:" + bindings
    names = ["clearSession", "dismissImmediately", "requestPreview", "releasePreview"]
    # Keep the harness runnable against the pre-fix source for red/green checks.
    if "  function refreshActivityContent(" in source:
        names.append("refreshActivityContent")
    methods = "\n".join(qml_block(source, "function " + name + "(") for name in names)
    handlers = "\n".join(qml_block(source, name + ": {") for name in (
        "onActivityRowsChanged", "onAnchorItemChanged"))
    connections = re.search(
        r"^  Connections \{\n    target: root.anchorItem\n.*?^  \}", source,
        re.MULTILINE | re.DOTALL)
    if not connections:
        raise AssertionError("Missing production anchor Connections")
    components = (ROOT / "components").as_uri()
    return f'''import QtQuick
import "{components}/DockBrowserActivityModel.js" as ActivityModel
import "{components}/DockWindowPreviewModel.js" as PreviewModel
Item {{
  id: root
  visible: false
  property var mutedServices: []
{state}
{bindings}
  readonly property bool pending: openTimer.running
  property bool popupHovered: false
  function liveMembers(values) {{ return values }}
  function reanchor() {{}}
  function refreshAnchorGeometry() {{}}
  Timer {{ id: openTimer; interval: 60000 }}
  Timer {{ id: closeTimer; interval: 60000 }}
{methods}
{handlers}
{connections.group(0)}
}}
'''


QML_TEST = r'''import QtQuick
import QtTest
Item {
  id: scene
  width: 400
  height: 300
  Component { id: sessionFactory; PreviewSession {} }
  Component {
    id: anchorFactory
    Item {
      property string presentationId: ""
      property var identityToplevel: null
      property bool originOnly: false
      property var previewActivities: []
    }
  }
  TestCase {
    name: "BrowserActivityPreviewSession"
    when: windowShown
    property var preview
    property var chrome
    property var ordinary
    function init() {
      preview = createTemporaryObject(sessionFactory, scene)
      chrome = createTemporaryObject(anchorFactory, scene, {
        presentationId: "chrome", previewActivities: [{
          targetId: "A1", serviceId: "gmail", label: "Gmail", count: 13,
          profileKey: "Default", domain: "mail.google.com", windowAddress: "0x1"
        }]
      })
      ordinary = createTemporaryObject(anchorFactory, scene, {presentationId: "editor"})
      verify(preview !== null)
      verify(chrome !== null)
      verify(ordinary !== null)
    }
    function cleanup() { preview.dismissImmediately() }
    function request(anchor, count) {
      var members = []
      for (var i = 0; i < count; ++i) members.push({title: "window " + i})
      preview.requestPreview(anchor, anchor.presentationId, members, {name: anchor.presentationId})
    }
    function test_activityToOrdinaryKeepsIncomingAnchor() {
      request(chrome, 1)
      preview.visible = true
      request(ordinary, 2)
      compare(preview.anchorItem, ordinary)
      compare(preview.members.length, 2)
      compare(preview.activityRows.length, 0)
      compare(preview.presentationId, "editor")
      verify(preview.visible)
      verify(!preview.pending)
      wait(1)
      compare(preview.anchorItem, ordinary)
      verify(preview.visible)
    }
    function test_ordinaryToActivityKeepsIncomingAnchor() {
      request(ordinary, 2)
      preview.visible = true
      request(chrome, 1)
      compare(preview.anchorItem, chrome)
      compare(preview.members.length, 1)
      compare(preview.activityTotal, 13)
      verify(preview.visible)
      wait(1)
      compare(preview.anchorItem, chrome)
    }
    function test_sameActivityAnchorCanRefreshMembers() {
      request(chrome, 1)
      preview.visible = true
      request(chrome, 2)
      compare(preview.anchorItem, chrome)
      compare(preview.members.length, 2)
      compare(preview.activityTotal, 13)
      verify(preview.visible)
    }
    function test_lastActivityStillDismissesSingleWindow() {
      request(chrome, 1)
      preview.visible = true
      chrome.previewActivities = []
      tryCompare(preview, "anchorItem", null)
      compare(preview.members.length, 0)
      verify(!preview.visible)
      verify(!preview.pending)
    }
    function test_activityLossKeepsOrdinaryTwoWindowPreview() {
      request(chrome, 2)
      preview.visible = true
      chrome.previewActivities = []
      wait(1)
      compare(preview.anchorItem, chrome)
      compare(preview.members.length, 2)
      compare(preview.activityRows.length, 0)
      verify(preview.visible)
    }
    function test_lastActivityCancelsPendingSingleWindowPreview() {
      request(chrome, 1)
      verify(preview.pending)
      chrome.previewActivities = []
      tryCompare(preview, "anchorItem", null)
      verify(!preview.pending)
      verify(!preview.visible)
    }
    function test_oldActivityLossDoesNotDismissNewSession() {
      request(chrome, 1)
      preview.visible = true
      chrome.previewActivities = []
      request(ordinary, 2)
      wait(1)
      compare(preview.anchorItem, ordinary)
      compare(preview.presentationId, "editor")
      verify(preview.visible)
    }
    function test_mutingLastServiceKeepsActivityCardOpen() {
      request(chrome, 1)
      preview.visible = true
      preview.mutedServices = ["gmail"]
      wait(1)
      compare(preview.anchorItem, chrome)
      compare(preview.activityRows.length, 1)
      compare(preview.activityTotal, 0)
      verify(preview.visible)
    }
  }
}
'''


class BrowserActivityPreviewTest(unittest.TestCase):
    def test_production_session_with_qt_notifications(self):
        runner = shutil.which("qmltestrunner")
        if not runner:
            candidate = Path("/usr/lib/qt6/bin/qmltestrunner")
            runner = str(candidate) if candidate.is_file() else None
        if not runner:
            if os.environ.get("CI"):
                self.fail("CI must provide qmltestrunner for the preview regression")
            self.skipTest("qmltestrunner unavailable; no Qt lifecycle qualification")
        with tempfile.TemporaryDirectory(prefix="smartdock-preview-session-") as directory:
            path = Path(directory)
            (path / "PreviewSession.qml").write_text(preview_session_source())
            (path / "tst_preview_session.qml").write_text(QML_TEST)
            result = subprocess.run(
                [runner, "-input", str(path)], capture_output=True, text=True,
                timeout=45, env=dict(os.environ, QT_QPA_PLATFORM="offscreen"))
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("Binding loop detected", output)
        print(result.stdout, end="")


if __name__ == "__main__":
    unittest.main()
