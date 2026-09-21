pragma ComponentBehavior: Bound

import QtQuick
import "DockModel.js" as DockModel

MouseArea {
  id: root

  property string dockPosition: "bottom"
  property var requestedPosition: dockPosition
  property real switchThreshold: 48
  property bool interactionAllowed: true

  property real pressX: 0
  property real pressY: 0
  property string startPosition: "bottom"
  property var expectedPosition: "bottom"
  property string candidatePosition: "bottom"

  signal positionRequested(string position, var expectedPosition)

  enabled: interactionAllowed
  hoverEnabled: true
  acceptedButtons: Qt.LeftButton
  cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

  function resetGesture() {
    pressX = 0
    pressY = 0
    startPosition = DockModel.dockGestureEdge(dockPosition)
    expectedPosition = requestedPosition
    candidatePosition = startPosition
  }

  onPressed: function(mouse) {
    pressX = mouse.x
    pressY = mouse.y
    startPosition = DockModel.dockGestureEdge(dockPosition)
    expectedPosition = requestedPosition
    candidatePosition = startPosition
  }

  onPositionChanged: function(mouse) {
    if (!pressed) return
    candidatePosition = DockModel.dockPositionDragTarget(
      startPosition, mouse.x - pressX, mouse.y - pressY, switchThreshold)
  }

  onReleased: function(mouse) {
    candidatePosition = DockModel.dockPositionDragTarget(
      startPosition, mouse.x - pressX, mouse.y - pressY, switchThreshold)
    if (candidatePosition !== startPosition)
      root.positionRequested(candidatePosition, expectedPosition)
    resetGesture()
  }

  onCanceled: resetGesture()
}
