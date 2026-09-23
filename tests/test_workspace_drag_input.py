"""Execute the production workspace-drag handlers against real Qt pointer events."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


def qml_block(source, declaration, *, contains=None, indent=2):
    """Extract exactly one indentation-bounded production QML block."""
    lines = source.splitlines()
    prefix = " " * indent
    matches = []
    for index, line in enumerate(lines):
        if not line.startswith(prefix + declaration):
            continue
        depth = 0
        end = None
        for end_index in range(index, len(lines)):
            text = lines[end_index]
            depth += text.count("{") - text.count("}")
            if end_index > index and depth == 0:
                end = end_index
                break
        if end is None:
            raise AssertionError("Unclosed production QML block: " + declaration)
        block = "\n".join(lines[index:end + 1])
        if contains is None or contains in block:
            matches.append(block)
    if len(matches) != 1:
        raise AssertionError(
            f"Expected one production block {declaration!r}, found {len(matches)}")
    return matches[0]


def production_blocks():
    item_source = (ROOT / "components/DockItem.qml").read_text()
    group_source = (ROOT / "components/DockWorkspaceGroup.qml").read_text()
    item = {
        "launch": qml_block(item_source, "function launch("),
        "dispatch_application": qml_block(
            item_source, "function dispatchApplicationAction("),
        "dispatch_pointer": qml_block(
            item_source, "function dispatchPointerAction("),
        "cancel": qml_block(item_source, "function cancelWorkspaceDrag("),
        "grab": qml_block(item_source, "function workspaceGrabChanged("),
        "tap": qml_block(
            item_source, "TapHandler {",
            contains="acceptedButtons: Qt.LeftButton\n    acceptedModifiers: Qt.NoModifier"),
        "ctrl_tap": qml_block(
            item_source, "TapHandler {",
            contains="acceptedButtons: Qt.LeftButton\n    acceptedModifiers: Qt.ControlModifier"),
        "drag": qml_block(
            item_source, "DragHandler {", contains="id: workspaceDragHandler"),
        "timer": qml_block(
            item_source, "Timer {", contains="id: workspaceReleaseCleanup"),
        "helper": (qml_block(item_source, "function updateWorkspaceGesture(")
                   if "function updateWorkspaceGesture(" in item_source else ""),
    }
    group = {
        "cancel": qml_block(group_source, "function cancelWorkspaceMonitorDrag("),
        "grab": qml_block(group_source, "function workspaceMonitorGrabChanged("),
        "source": re.search(
            r"^  readonly property bool workspaceMonitorDragSource:[\s\S]*?"
            r"(?=^  readonly property bool (?:workspaceMonitorDragSourceActive|headerInputSuppressed):)",
            group_source, re.MULTILINE).group(0).rstrip(),
        "tap": qml_block(
            group_source, "TapHandler {", contains="acceptedModifiers: Qt.NoModifier",
            indent=4),
        "escape": qml_block(
            group_source, "Keys.onEscapePressed:",
            contains='cancelWorkspaceMonitorDrag("escape")', indent=4),
        "drag": qml_block(
            group_source, "DragHandler {", contains="id: workspaceMonitorDragHandler",
            indent=4),
        "timer": qml_block(
            group_source, "Timer {", contains="id: workspaceMonitorReleaseCleanup",
            indent=4),
        "helper": (qml_block(
            group_source, "function updateWorkspaceMonitorGesture(")
                   if "function updateWorkspaceMonitorGesture(" in group_source else ""),
    }
    return item, group


def qml_source():
    item, group = production_blocks()
    model_uri = (ROOT / "components/DockModel.js").as_uri()
    components_uri = (ROOT / "components").as_uri()
    dock_source = (ROOT / "components/Dock.qml").read_text()
    drag_binding = re.search(
        r"^        dragScenePosition: root\.workspaceDragActive \? workspaceDrag\.pointerScene\n"
        r"^          : root\.workspaceMonitorDragActive \?[\s\S]*?"
        r"(?=^        onViewportChanged:)",
        dock_source, re.MULTILINE)
    if not drag_binding:
        raise AssertionError("Missing production Dock dragScenePosition binding")
    drag_binding = textwrap.dedent(drag_binding.group(0)).rstrip()
    natural_width = re.search(
        r"^              naturalWidth: modelData\.item\._monitorDragPlaceholder\n"
        r"^                \?[\s\S]*?^                : workspaceCard\.width",
        dock_source, re.MULTILINE)
    natural_height = re.search(
        r"^              naturalHeight: modelData\.item\._monitorDragPlaceholder\n"
        r"^                \?[\s\S]*?^                : workspaceCard\.height",
        dock_source, re.MULTILINE)
    if not natural_width or not natural_height:
        raise AssertionError("Missing production placeholder size bindings")
    natural_width = textwrap.dedent(natural_width.group(0)).rstrip()
    natural_height = textwrap.dedent(natural_height.group(0)).rstrip()
    return f'''import QtQuick
import QtTest
import "{model_uri}" as DockModel
import "{components_uri}" as Components

Item {{
  id: scene
  width: 700
  height: 240

  Component {{
    id: iconFactory
    Item {{
      id: root
      objectName: "icon"
      width: 240
      height: 80
      property bool workspaceDragEnabled: true
      property bool presentationActive: true
      property bool workspaceGestureOwned: false
      property bool workspaceGestureConsumed: false
      property bool presentationVisible: true
      property bool sticky: false
      property bool originOnly: false
      property bool pinnedItem: false
      property var runningToplevels: [{{ title: "window" }}]
      readonly property int runningCount: runningToplevels.length
      readonly property bool workspaceDragActive: workspaceDrag !== null
        && workspaceDrag.active
      readonly property bool workspaceInputSuppressed: workspaceDragActive
        || workspaceGestureOwned
      property var applicationActions: ({{ clickAction: "focus-or-launch",
        middleClickAction: "none", scrollAction: "none" }})
      property var windowActions: iconActions
      property string activationMonitor: ""
      property string workspaceActivationTarget: ""
      property int lastActivatedToplevel: -1
      property var workspaceDrag: iconDrag
      property int beginCalls: iconDrag.beginCalls
      property int activationCalls: iconActions.activationCalls
      property int cancelCalls: iconDrag.cancelCalls
      function dismissPopups() {{}}
      function previewDismissRequested() {{}}
      {item["launch"]}
      {item["dispatch_application"]}
      {item["dispatch_pointer"]}
      {item["cancel"]}
      {item["grab"]}
      Item {{
        id: applicationArtwork
        property url renderedSource: ""
      }}
      {item["tap"]}
      {item["ctrl_tap"]}
      {item["helper"]}
      {item["drag"]}
      {item["timer"]}
    }}
  }}

  Component {{
    id: headerFactory
    Item {{
      id: root
      objectName: "header-surface"
      width: 300
      height: 120
      property string label: "3"
      property int count: 1
      property bool switchable: true
      property bool windowDragActive: false
      property bool presentationVisible: sourceSlot.width > 0
        && viewport.containsItem(sourceSlot)
      property bool workspaceMonitorGestureOwned: false
      property bool workspaceMonitorGestureStarted: false
      property point workspaceMonitorPressPoint: Qt.point(0, 0)
      property string workspaceIdentity: "id:3"
      property string workspaceOwnerMonitor: "id:0"
      property var workspaceMonitorDragDock: root
      property var workspaceMonitorDrag: monitorDrag
      readonly property bool workspaceMonitorDragActive: monitorDrag.active
      {group["source"]}
      readonly property bool headerInputSuppressed: windowDragActive
        || workspaceMonitorDragActive || workspaceMonitorGestureOwned
      opacity: workspaceMonitorDragSource && workspaceMonitorDrag
        && workspaceMonitorDrag.captureReady ? 0.55 : 1
      property int beginCalls: monitorDrag.beginCalls
      property int finishCalls: monitorDrag.finishCalls
      property int cancelCalls: monitorDrag.cancelCalls
      property int activations: 0
      property bool monitorHandlerEnabled: header.monitorHandlerEnabled
      property bool numberActiveFocus: header.activeFocus
      signal activated(bool pullToMonitor)
      onActivated: activations++
      {group["escape"]}
      {group["cancel"]}
      {group["grab"]}
      {group["helper"]}
      function collapseSource() {{
        sourceSlot.present = false
        sourceSlot.settle()
      }}
      function clipSource() {{
        viewport.width = 80
      }}
      Components.DockWorkspaceLayout {{
        id: viewport
        width: 300
        height: 100
        rowY: 10
        contentPadding: 0
        animationsEnabled: false
        Components.DockAnimatedSlot {{
          id: sourceSlot
          naturalWidth: 240
          naturalHeight: 80
          animationsEnabled: false
          Item {{
            id: header
            width: 240
            height: 80
            property bool monitorHandlerEnabled: workspaceMonitorDragHandler.enabled
            {group["tap"]}
            {group["drag"]}
            {group["timer"]}
          }}
        }}
      }}
    }}
  }}

  Component {{
    id: coordinateFactory
    Item {{
      id: root
      property bool workspaceDragActive: false
      property bool workspaceMonitorDragActive: false
      property point sceneOrigin: Qt.point(0, 0)
      property var workspaceDrag: windowState
      property var workspaceMonitorDrag: monitorState
      property alias monitorPointer: monitorState.pointerVirtual
      property alias windowPointer: windowState.pointerScene
      QtObject {{
        id: windowState
        property point pointerScene: Qt.point(0, 0)
      }}
      QtObject {{
        id: monitorState
        property point pointerVirtual: Qt.point(0, 0)
      }}
      Components.DockWorkspaceLayout {{
        id: layout
        width: 300
        height: 100
        {drag_binding}
      }}
      property alias dragScenePosition: layout.dragScenePosition
    }}
  }}

  Component {{
    id: placeholderFactory
    Item {{
      id: root
      property var modelData: ({{ item: ({{ _monitorDragPlaceholder: true }}) }})
      property real cardWidth: 120
      property real cardHeight: 50
      property var workspaceMonitorDrag: monitorState
      property alias ghostSize: monitorState.ghostSize
      property alias slotWidth: workspaceCardSlot.width
      property alias slotHeight: workspaceCardSlot.height
      QtObject {{
        id: monitorState
        property size ghostSize: Qt.size(0, 0)
      }}
      Components.DockAnimatedSlot {{
        id: workspaceCardSlot
        property var modelData: root.modelData
        animationsEnabled: false
        {natural_width}
        {natural_height}
        Rectangle {{
          id: workspaceCard
          width: root.cardWidth
          height: root.cardHeight
        }}
      }}
    }}
  }}

  QtObject {{
    id: iconActions
    property int activationCalls: 0
    property var activeToplevel: null
    property var lastActivationMonitor: null
    property var lastWorkspaceTargetOverride: null
    property int pullCalls: 0
    function activateToplevel(toplevel, originOnly, activationMonitor, focusAfterRestore, workspaceTargetOverride) {{
      activationCalls++
      lastActivationMonitor = activationMonitor
      lastWorkspaceTargetOverride = workspaceTargetOverride
      return true
    }}
    function pullToplevelToMonitorWorkspace(toplevel, originOnly, monitor) {{
      activationCalls++
      pullCalls++
      lastActivationMonitor = monitor
      lastWorkspaceTargetOverride = undefined
      return true
    }}
  }}

  QtObject {{
    id: iconDrag
    property bool active: false
    property var sourceItem: null
    property int beginCalls: 0
    property int cancelCalls: 0
    function begin(source) {{ beginCalls++; sourceItem = source; active = true; return true }}
    function updatePointer() {{}}
    function finish() {{ sourceItem = null; active = false; return true }}
    function cancel() {{ cancelCalls++; active = false }}
  }}

  QtObject {{
    id: monitorDrag
    property bool active: false
    property bool awaitingConfirmation: false
    property var sourceDock: null
    property string sourceWorkspace: ""
    property bool captureReady: false
    property bool beginResult: true
    property int beginCalls: 0
    property int finishCalls: 0
    property int cancelCalls: 0
    function begin(dock, workspace) {{
      beginCalls++
      sourceDock = dock
      sourceWorkspace = workspace
      active = beginResult
      return beginResult
    }}
    function updatePointer() {{}}
    function finish() {{ finishCalls++; active = false; return true }}
    function cancel() {{ cancelCalls++; active = false }}
  }}

  TestCase {{
    id: testCase
    name: "WorkspaceDragProductionInput"
    when: windowShown
    function freshIcon() {{
      iconDrag.active = false
      iconDrag.sourceItem = null
      iconDrag.beginCalls = 0
      iconDrag.cancelCalls = 0
      iconActions.activationCalls = 0
      iconActions.lastActivationMonitor = null
      iconActions.lastWorkspaceTargetOverride = null
      var value = createTemporaryObject(iconFactory, scene)
      verify(value)
      return value
    }}
    function freshHeader() {{
      monitorDrag.active = false
      monitorDrag.sourceDock = null
      monitorDrag.sourceWorkspace = ""
      monitorDrag.beginCalls = 0
      monitorDrag.finishCalls = 0
      monitorDrag.cancelCalls = 0
      var value = createTemporaryObject(headerFactory, scene)
      verify(value)
      wait(30)
      return value
    }}
    function freshCoordinates() {{
      var value = createTemporaryObject(coordinateFactory, scene)
      verify(value)
      return value
    }}
    function freshPlaceholder() {{
      var value = createTemporaryObject(placeholderFactory, scene)
      verify(value)
      wait(0)
      return value
    }}
    function test_iconJitterIsClick() {{
      var icon = freshIcon()
      mousePress(icon, 30, 30, Qt.LeftButton)
      mouseMove(icon, 31, 30, 20)
      mouseRelease(icon, 31, 30, Qt.LeftButton)
      compare(icon.beginCalls, 0)
      compare(icon.activationCalls, 1)
      compare(iconActions.lastActivationMonitor, "")
      compare(iconActions.lastWorkspaceTargetOverride, undefined)
      tryCompare(icon, "workspaceGestureOwned", false)
    }}
    function test_iconCtrlClickRecordsDockMonitor() {{
      var icon = freshIcon()
      icon.activationMonitor = "id:fixture-monitor"
      iconActions.pullCalls = 0
      mouseClick(icon, 30, 30, Qt.LeftButton, Qt.ControlModifier)
      compare(icon.activationCalls, 1)
      // Ctrl moves just the window into the clicked monitor's active workspace.
      compare(iconActions.pullCalls, 1)
      compare(iconActions.lastActivationMonitor, "id:fixture-monitor")
      compare(iconActions.lastWorkspaceTargetOverride, undefined)
    }}
    function test_iconMixedModifiersDoNotActivate() {{
      var icon = freshIcon()
      mouseClick(icon, 30, 30, Qt.LeftButton, Qt.ShiftModifier)
      mouseClick(icon, 30, 30, Qt.LeftButton,
        Qt.ControlModifier | Qt.ShiftModifier)
      compare(icon.activationCalls, 0)
    }}
    function test_headerFirstMoveCrossesThreshold() {{
      var header = freshHeader()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + delta, 30, 20)
      compare(header.beginCalls, 1)
      mouseRelease(header, 30 + delta, 30, Qt.LeftButton)
      compare(header.finishCalls, 1)
      compare(header.activations, 0)
      compare(header.numberActiveFocus, false)
    }}
    function test_headerMouseTapDoesNotRetainKeyboardFocusRing() {{
      var header = freshHeader()
      mouseClick(header, 30, 30, Qt.LeftButton)
      compare(header.activations, 1)
      compare(header.numberActiveFocus, false)
    }}
    function test_iconThresholdAndSecondClick() {{
      var threshold = Application.styleHints.startDragDistance
      var icon = freshIcon()
      mousePress(icon, 30, 30, Qt.LeftButton)
      var below = 30 + Math.max(0, threshold - 1)
      mouseMove(icon, below, 30, 20)
      compare(icon.beginCalls, 0)
      mouseMove(icon, 30 + threshold, 30, 20)
      compare(icon.beginCalls, 1)
      mouseRelease(icon, 30 + threshold, 30, Qt.LeftButton)
      compare(icon.activationCalls, 0)
      tryCompare(icon, "workspaceGestureOwned", false)
      mouseClick(icon, 30, 30, Qt.LeftButton)
      compare(icon.activationCalls, 1)
    }}
    function test_headerExactThresholdAndContinuedMotion() {{
      var threshold = Application.styleHints.startDragDistance
      var header = freshHeader()
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + Math.max(0, threshold - 1), 30, 20)
      compare(header.beginCalls, 0)
      mouseMove(header, 30 + threshold, 30, 20)
      compare(header.beginCalls, 1)
      mouseMove(header, 30 + threshold + 10, 30, 20)
      compare(header.beginCalls, 1)
      mouseRelease(header, 30 + threshold + 10, 30, Qt.LeftButton)
      compare(header.finishCalls, 1)
      tryCompare(header, "workspaceMonitorGestureOwned", false)
    }}
    function test_headerGrabSurvivesDelegateIdentityReuse() {{
      var header = freshHeader()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + delta, 30, 20)
      compare(header.beginCalls, 1)
      header.workspaceIdentity = "workspace-monitor-placeholder:id:3"
      header.switchable = false
      verify(header.monitorHandlerEnabled,
        "delegate reuse must not disable the handler that owns the pointer")
      mouseMove(header, 30 + delta + 10, 30, 20)
      mouseRelease(header, 30 + delta + 10, 30, Qt.LeftButton)
      compare(header.cancelCalls, 0)
      compare(header.finishCalls, 1,
        "the pointer owner must finish after its delegate is reused")
      tryCompare(header, "workspaceMonitorGestureOwned", false)
      compare(header.numberActiveFocus, false)
    }}
    function test_headerCancellationDoesNotFinish() {{
      var header = freshHeader()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + delta, 30, 20)
      compare(header.beginCalls, 1)
      header.cancelWorkspaceMonitorDrag("test cancellation")
      compare(header.finishCalls, 0)
      compare(header.cancelCalls, 1)
      mouseRelease(header, 30 + delta, 30, Qt.LeftButton)
      tryCompare(header, "workspaceMonitorGestureOwned", false)
    }}
    function test_headerEscapeCancels() {{
      var header = freshHeader()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + delta, 30, 20)
      compare(header.beginCalls, 1)
      keyPress(Qt.Key_Escape)
      compare(header.finishCalls, 0)
      compare(header.cancelCalls, 1)
      mouseRelease(header, 30 + delta, 30, Qt.LeftButton)
    }}
    function test_iconFirstMoveCrossesThreshold() {{
      var icon = freshIcon()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(icon, 30, 30, Qt.LeftButton)
      mouseMove(icon, 30 + delta, 30, 20)
      compare(icon.beginCalls, 1)
      mouseRelease(icon, 30 + delta, 30, Qt.LeftButton)
      compare(icon.activationCalls, 0)
    }}
    function test_iconOutsideReleaseKeepsNextClick() {{
      var icon = freshIcon()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(icon, 30, 30, Qt.LeftButton)
      mouseMove(icon, 30 + delta, 30, 20)
      compare(icon.beginCalls, 1)
      mouseMove(scene, 600, 200, 20)
      mouseRelease(scene, 600, 200, Qt.LeftButton)
      tryCompare(icon, "workspaceGestureOwned", false)
      compare(icon.workspaceGestureConsumed, false)
      mouseClick(icon, 30, 30, Qt.LeftButton)
      compare(icon.activationCalls, 1)
    }}
    function test_iconCtrlReleasedBeforeCanceledGestureEndsDoesNotActivate() {{
      var icon = freshIcon()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(icon, 30, 30, Qt.LeftButton, Qt.ControlModifier)
      mouseMove(icon, 30 + delta, 30, 20,
        Qt.LeftButton, Qt.ControlModifier)
      compare(icon.beginCalls, 1)
      mouseMove(scene, 600, 200, 20, Qt.LeftButton, Qt.NoModifier)
      mouseRelease(scene, 600, 200, Qt.LeftButton)
      tryCompare(icon, "workspaceGestureOwned", false)
      compare(icon.activationCalls, 0)
      mouseClick(icon, 30, 30, Qt.LeftButton)
      compare(icon.activationCalls, 1)
    }}
    function test_iconCtrlHeldThroughCanceledGestureDoesNotActivate() {{
      var icon = freshIcon()
      var delta = Application.styleHints.startDragDistance + 7
      mousePress(icon, 30, 30, Qt.LeftButton, Qt.ControlModifier)
      mouseMove(icon, 30 + delta, 30, 20,
        Qt.LeftButton, Qt.ControlModifier)
      compare(icon.beginCalls, 1)
      mouseMove(scene, 600, 200, 20,
        Qt.LeftButton, Qt.ControlModifier)
      mouseRelease(scene, 600, 200, Qt.LeftButton, Qt.ControlModifier)
      tryCompare(icon, "workspaceGestureOwned", false)
      compare(icon.activationCalls, 0)
      mouseClick(icon, 30, 30, Qt.LeftButton)
      compare(icon.activationCalls, 1)
    }}
    function test_clippedSourceGrabSurvivesCollapseAndScroll() {{
      var delta = Application.styleHints.startDragDistance + 7
      var header = freshHeader()
      verify(header.presentationVisible)
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + delta, 30, 20)
      compare(header.beginCalls, 1)
      header.collapseSource()
      compare(header.presentationVisible, false)
      verify(header.monitorHandlerEnabled)
      compare(header.cancelCalls, 0)
      header.clipSource()
      compare(header.presentationVisible, false)
      verify(header.monitorHandlerEnabled)
      compare(header.cancelCalls, 0)
      mouseRelease(header, 30 + delta, 30, Qt.LeftButton)
      compare(header.finishCalls, 1)
      tryCompare(header, "workspaceMonitorGestureOwned", false)
    }}
    function test_idleClippedSourceCannotStart() {{
      var header = freshHeader()
      header.clipSource()
      compare(header.presentationVisible, false)
      verify(!header.monitorHandlerEnabled)
      mousePress(header, 30, 30, Qt.LeftButton)
      mouseMove(header, 30 + Application.styleHints.startDragDistance + 7, 30, 20)
      compare(header.beginCalls, 0)
      mouseRelease(header, 30, 30, Qt.LeftButton)
    }}
    function test_sourceIdentityControlsStyleDuringConfirmation() {{
      var source = freshHeader()
      var other = freshHeader()
      monitorDrag.sourceDock = source
      monitorDrag.sourceWorkspace = "id:3"
      monitorDrag.active = true
      monitorDrag.captureReady = false
      compare(source.workspaceMonitorDragSource, true)
      compare(other.workspaceMonitorDragSource, false)
      compare(source.opacity, 1)
      compare(other.opacity, 1)
      monitorDrag.captureReady = true
      compare(source.opacity, 0.55)
      compare(other.opacity, 1)
      monitorDrag.active = false
      monitorDrag.awaitingConfirmation = true
      compare(source.workspaceMonitorDragSource, true)
      compare(other.workspaceMonitorDragSource, false)
      compare(source.opacity, 0.55)
      monitorDrag.awaitingConfirmation = false
      monitorDrag.sourceDock = null
      monitorDrag.sourceWorkspace = ""
    }}
    function test_monitorPointerConvertsIntoDestinationScene() {{
      var destination = freshCoordinates()
      destination.sceneOrigin = Qt.point(1920, -120)
      destination.monitorPointer = Qt.point(2200, -10)
      destination.windowPointer = Qt.point(3736, -754)
      destination.workspaceMonitorDragActive = true
      compare(destination.dragScenePosition, Qt.point(280, 110))
      destination.sceneOrigin = Qt.point(-640, 80)
      destination.monitorPointer = Qt.point(-360, 220)
      compare(destination.dragScenePosition, Qt.point(280, 140))
      destination.workspaceMonitorDragActive = false
      destination.workspaceDragActive = true
      compare(destination.dragScenePosition, Qt.point(3736, -754))
    }}
    function test_placeholderKeepsCapturedDimensionsUntilPendingEnds() {{
      var placeholder = freshPlaceholder()
      placeholder.ghostSize = Qt.size(120, 50)
      compare(placeholder.slotWidth, 120)
      compare(placeholder.slotHeight, 50)
      placeholder.ghostSize = Qt.size(160, 64)
      compare(placeholder.slotWidth, 160)
      compare(placeholder.slotHeight, 64)
      placeholder.modelData = ({{ item: ({{ _monitorDragPlaceholder: false }}) }})
      compare(placeholder.slotWidth, 120)
      compare(placeholder.slotHeight, 50)
    }}
  }}
}}
'''


class WorkspaceDragInputTest(unittest.TestCase):
    def test_production_handlers_with_real_qt_events(self):
        runner = shutil.which("qmltestrunner")
        if not runner:
            candidate = Path("/usr/lib/qt6/bin/qmltestrunner")
            runner = str(candidate) if candidate.is_file() else None
        if not runner:
            if os.environ.get("CI"):
                self.fail("CI must provide qmltestrunner for workspace drag input")
            self.skipTest("qmltestrunner unavailable; no Qt input qualification")
        with tempfile.TemporaryDirectory(prefix="smartdock-workspace-drag-input-") as directory:
            path = Path(directory)
            (path / "WorkspaceDragInput.qml").write_text(qml_source())
            (path / "tst_workspace_drag_input.qml").write_text(
                "import QtQuick\nimport QtTest\nWorkspaceDragInput {}\n")
            result = subprocess.run(
                [runner, "-input", str(path)], capture_output=True, text=True,
                timeout=60, env=dict(os.environ, QT_QPA_PLATFORM="offscreen",
                                     QML_DISABLE_DISK_CACHE="1"))
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertNotIn("Warnings while loading", output)
        print(output, end="")


if __name__ == "__main__":
    unittest.main()
