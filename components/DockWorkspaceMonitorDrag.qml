import QtQuick

// Host-owned cross-window gesture state. Docks provide virtual rectangles and
// render their own proxy so this component stays usable in headless Qt tests.
Item {
  id: root

  required property var windowActions
  property var docks: []
  property bool active: false
  property var sourceDock: null
  property string sourceWorkspace: ""
  property string sourceMonitor: ""
  property string sourceLabel: ""
  property int sourceCount: 0
  property point pointerVirtual: Qt.point(0, 0)
  property var pointerDock: null
  property var hoveredTarget: null
  property bool finishing: false
  property bool ending: false
  property color accent: docks.length > 0
    ? docks[0].workspaceMonitorDragAccent : "#808080"
  property color background: docks.length > 0
    ? docks[0].workspaceMonitorDragBackground : "#303030"
  property color foreground: docks.length > 0
    ? docks[0].workspaceMonitorDragForeground : "white"
  property string fontFamily: docks.length > 0
    ? docks[0].workspaceMonitorDragFontFamily : ""
  property int fontSize: docks.length > 0
    ? docks[0].workspaceMonitorDragFontSize : 12
  signal ended()

  function validPoint(point) {
    return point && isFinite(point.x) && isFinite(point.y)
  }

  function contains(rect, point) {
    return rect && point && rect.width > 0 && rect.height > 0
      && point.x >= rect.x && point.x < rect.x + rect.width
      && point.y >= rect.y && point.y < rect.y + rect.height
  }

  function registered(dock) {
    return dock && docks.indexOf(dock) >= 0
  }

  function available(dock) {
    return registered(dock) && dock.visible !== false
      && dock.workspaceMonitorDragAvailable !== false
      && String(dock.monitorIdentity || "") !== ""
  }

  function registerDock(dock) {
    if (!dock || registered(dock)) return false
    docks = docks.concat([dock])
    return true
  }

  function unregisterDock(dock) {
    var index = docks.indexOf(dock)
    if (index < 0) return false
    var cancelsSession = active && (dock === sourceDock || dock === hoveredTarget
      || dock === pointerDock || dock.dragRevealed)
    if (dock) {
      dock.dragRevealed = false
      dock.workspaceMonitorDropHighlighted = false
    }
    docks = docks.slice(0, index).concat(docks.slice(index + 1))
    if (cancelsSession) cancel("dock removed")
    return true
  }

  function sceneToVirtual(dock, scenePoint) {
    var origin = dock && dock.sceneOrigin ? dock.sceneOrigin
      : dock && dock.monitorOrigin ? dock.monitorOrigin : Qt.point(0, 0)
    return Qt.point(Number(origin.x) + Number(scenePoint.x),
      Number(origin.y) + Number(scenePoint.y))
  }

  function pointerDockAt(point) {
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (available(dock) && contains(dock.monitorRect, point)) return dock
    }
    return null
  }

  function canTarget(dock) {
    return available(dock) && dock !== sourceDock
      && String(dock.monitorIdentity || "") !== sourceMonitor
      && windowActions
      && windowActions.canMoveWorkspaceToMonitor(sourceWorkspace, dock.monitorIdentity)
  }

  function begin(dock, workspace, label, count, monitor, scenePoint) {
    if (active || finishing || ending || !available(dock) || !windowActions
        || !validPoint(scenePoint) || !workspace || !monitor) return false
    sourceDock = dock
    sourceWorkspace = String(workspace)
    sourceMonitor = String(monitor)
    sourceLabel = String(label || workspace)
    sourceCount = Math.max(0, Number(count) || 0)
    active = true
    try {
      updatePointer(scenePoint)
      return active
    } catch (error) {
      cancel("begin failed")
      throw error
    }
  }

  function updatePointer(scenePoint) {
    if (!active || ending) return false
    if (!validPoint(scenePoint) || !available(sourceDock)) {
      cancel("invalid session")
      return false
    }

    pointerVirtual = sceneToVirtual(sourceDock, scenePoint)
    pointerDock = pointerDockAt(pointerVirtual)
    hoveredTarget = null
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      dock.workspaceMonitorDropHighlighted = false
      if (dock === sourceDock) continue
      if (dock.dragRevealed && !available(dock)) {
        cancel("destination unavailable")
        return false
      }
      if (!available(dock)) continue
      if (contains(dock.revealRect, pointerVirtual)) dock.dragRevealed = true
      if (!hoveredTarget && (dock.dragRevealed || dock.dockShown)
          && contains(dock.dropRect, pointerVirtual) && canTarget(dock))
        hoveredTarget = dock
    }
    if (hoveredTarget) hoveredTarget.workspaceMonitorDropHighlighted = true
    return hoveredTarget !== null
  }

  function finish(scenePoint) {
    if (!active || finishing || ending) return false
    finishing = true
    try {
      updatePointer(scenePoint)
      if (!active || !hoveredTarget || !canTarget(hoveredTarget)) return false
      return windowActions.moveWorkspaceToMonitor(
        sourceWorkspace, hoveredTarget.monitorIdentity)
    } finally {
      endSession()
      finishing = false
    }
  }

  function endSession() {
    if (!active || ending) return
    ending = true
    active = false
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      dock.dragRevealed = false
      dock.workspaceMonitorDropHighlighted = false
    }
    sourceDock = null
    sourceWorkspace = ""
    sourceMonitor = ""
    sourceLabel = ""
    sourceCount = 0
    pointerVirtual = Qt.point(0, 0)
    pointerDock = null
    hoveredTarget = null
    ended()
    ending = false
  }

  function cancel(reason) {
    endSession()
  }

  onSourceDockChanged: if (active && !sourceDock) cancel("source destroyed")
  onWindowActionsChanged: if (active) cancel("controller replaced")
  onEnabledChanged: if (!enabled) cancel("disabled")
  Component.onDestruction: cancel("coordinator destroyed")
}
