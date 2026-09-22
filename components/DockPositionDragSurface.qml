pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "DockModel.js" as DockModel

// Background-only gesture that switches presentation mode between the classic
// bottom dock and the sidebar.
//
// A surface only ever covers genuinely empty panel background: the panel-level
// instance sits beneath foreground content, and regions a lower layer already
// owns (the sidebar's blank ListView tail) get their own surface declared above
// it with that region's exact geometry. Because no instance overlaps a row,
// control or scrollbar, nothing has to decline a press, and hover/cursor
// eligibility matches the press behaviour by construction.
//
// Commit happens once, on release, only while the destination is armed.
MouseArea {
  id: root

  property string dockPosition: "bottom"
  property var requestedPosition: dockPosition
  property real switchThreshold: 48
  // Small dead zone before the directional hint appears.
  property real moveDeadZone: 6
  property bool interactionAllowed: true
  // Presentation this panel renders. Captured at press so a concurrent mode
  // change invalidates the gesture instead of rewriting its intent.
  property string presentationMode: ""
  // Configured sidebar edge, used to place the destination silhouette.
  property string sidebarEdge: "left"
  // Press-time presentation token for this panel's output, injected by the
  // screen owner. Captured on press and emitted with the commit so the host can
  // reject a gesture whose state changed underneath it.
  property var gestureToken: null
  // Owned by the panel; mirrors the existing interface-animation preference.
  property bool animationsEnabled: true

  // Press origin in window coordinates, so a layout change under the pointer
  // cannot jump the measured displacement, plus the same point in this
  // surface's own coordinates for anchoring the hint.
  property real pressSceneX: 0
  property real pressSceneY: 0
  property real pressLocalX: 0
  property real pressLocalY: 0
  property real deltaX: 0
  property real deltaY: 0
  property string startEdge: "bottom"
  property var expectedPosition: "bottom"
  property string expectedPresentation: ""
  // Press-time copy of gestureToken; the commit emits this exact token so the
  // host validates against the state the gesture started from.
  property var capturedGestureToken: null
  property string candidatePosition: "bottom"
  property bool cancelRequested: false

  readonly property bool gestureActive: pressed && !cancelRequested
  readonly property bool hintVisible: gestureActive
    && DockModel.modeDragHintVisible(deltaX, deltaY, moveDeadZone)
  readonly property bool armed: gestureActive && candidatePosition !== startEdge
  readonly property string hintText: DockModel.modeDragHint(startEdge)
  readonly property string armedText: DockModel.modeDragArmedLabel(startEdge)
  readonly property string destinationPresentation: DockModel.modeDragDestination(startEdge)
  readonly property string destinationEdge: DockModel.modeDragDestinationEdge(startEdge, sidebarEdge)

  signal positionRequested(string position, var expectedPosition, var gestureToken)
  signal gestureCancelled(string reason)

  enabled: interactionAllowed
  hoverEnabled: true
  acceptedButtons: Qt.LeftButton
  cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

  DockModeDragFeedback {
    text: root.armed ? root.armedText
      : root.hintVisible ? root.hintText : ""
    animationsEnabled: root.animationsEnabled
    // Sits just above the press origin so it stays readable without following
    // the pointer or covering the empty space being dragged.
    x: Math.max(0, Math.min(parent.width - width, root.pressLocalX - width / 2))
    y: Math.max(0, Math.min(parent.height - height,
      root.pressLocalY - height - Style.space(12)))
  }

  function resetGesture() {
    startEdge = DockModel.dockGestureEdge(dockPosition)
    expectedPosition = requestedPosition
    expectedPresentation = presentationMode
    capturedGestureToken = gestureToken
    candidatePosition = startEdge
    deltaX = 0
    deltaY = 0
    cancelRequested = false
  }

  function trackMovement(x, y) {
    var point = root.mapToItem(null, x, y)
    deltaX = point.x - pressSceneX
    deltaY = point.y - pressSceneY
    candidatePosition = DockModel.dockPositionDragTarget(
      startEdge, deltaX, deltaY, switchThreshold)
  }

  function cancelGesture(reason) {
    if (!pressed || cancelRequested) return
    cancelRequested = true
    candidatePosition = startEdge
    root.gestureCancelled(reason)
  }

  onPressed: function(mouse) {
    resetGesture()
    pressLocalX = mouse.x
    pressLocalY = mouse.y
    var point = root.mapToItem(null, mouse.x, mouse.y)
    pressSceneX = point.x
    pressSceneY = point.y
  }

  onPositionChanged: function(mouse) {
    if (!gestureActive) return
    trackMovement(mouse.x, mouse.y)
  }

  onReleased: function(mouse) {
    if (!cancelRequested) trackMovement(mouse.x, mouse.y)
    // A mode write happens at most once per completed gesture, never when the
    // presentation changed underneath the press, and always against the token
    // captured at press time — the host re-validates it before writing.
    var commit = !cancelRequested && candidatePosition !== startEdge
      && expectedPresentation === presentationMode
    var position = candidatePosition
    var expected = expectedPosition
    var token = capturedGestureToken
    resetGesture()
    if (commit) root.positionRequested(position, expected, token)
  }

  onCanceled: {
    var cancelled = !cancelRequested
    resetGesture()
    if (cancelled) root.gestureCancelled("grab-lost")
  }

  onInteractionAllowedChanged: {
    if (!interactionAllowed && pressed) root.cancelGesture("interaction-conflict")
  }

  // Escape clears the gesture without a mode write. It uses the panel's own
  // window shortcut scope, so it never becomes a desktop-wide binding and
  // never moves keyboard focus.
  Shortcut {
    sequence: "Escape"
    enabled: root.gestureActive && root.interactionAllowed
    onActivated: root.cancelGesture("escape")
  }
}
