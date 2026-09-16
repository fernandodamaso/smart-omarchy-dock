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
  property string hoveredMonitor: ""
  property var sectionHits: []
  property point pointerScene: Qt.point(0, 0)
  property bool captureReady: false
  property int captureGeneration: 0
  property var ghostImage: null
  property url ghostUrl: ""
  property size ghostSize: Qt.size(0, 0)
  property point grabOffset: Qt.point(0, 0)
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

  function canTargetMonitor(monitor) {
    return !!monitor && String(monitor) !== sourceMonitor && windowActions
      && windowActions.canMoveWorkspaceToMonitor(sourceWorkspace, monitor)
  }

  function snapshotSectionHits() {
    var hits = []
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock || typeof dock.workspaceMonitorSectionHits !== "function") continue
      var list = dock.workspaceMonitorSectionHits() || []
      for (var j = 0; j < list.length; ++j) {
        var hit = list[j]
        if (!hit || !hit.identity || !hit.rect) continue
        hits.push({ dock: dock, identity: String(hit.identity), rect: hit.rect })
      }
    }
    return hits
  }

  function captureGhost(dock, workspace, scenePoint) {
    ghostImage = null
    ghostUrl = ""
    captureReady = false
    ghostSize = Qt.size(0, 0)
    grabOffset = Qt.point(0, 0)
    captureGeneration += 1
    var generation = captureGeneration
    if (!dock || typeof dock.cardForWorkspace !== "function" || !dock.workspaceDragMapItem) return
    var card = dock.cardForWorkspace(workspace)
    if (!card) return
    ghostSize = Qt.size(card.width, card.height)
    var area = dock.workspaceDragMapItem
    var origin = card.mapToItem(area, 0, 0)
    grabOffset = Qt.point(
      scenePoint.x - Number(area.x) - origin.x,
      scenePoint.y - Number(area.y) - origin.y)
    try {
      card.grabToImage(function(result) {
        if (generation !== captureGeneration || !active || ending) return
        if (!result) return
        ghostImage = result
        ghostUrl = result.url || ""
        ghostSize = Qt.size(card.width, card.height)
        captureReady = true
      })
    } catch (error) {
      ghostImage = null
      ghostUrl = ""
      captureReady = false
    }
  }

  function begin(dock, workspace, label, count, monitor, scenePoint) {
    if (active || finishing || ending || !available(dock) || !windowActions
        || !validPoint(scenePoint) || !workspace || !monitor)
      return false
    sourceDock = dock
    sourceWorkspace = String(workspace)
    sourceMonitor = String(monitor)
    sourceLabel = String(label || workspace)
    sourceCount = Math.max(0, Number(count) || 0)
    try {
      sectionHits = snapshotSectionHits()
    } catch (error) {
      sectionHits = []
    }
    try {
      captureGhost(dock, workspace, scenePoint)
    } catch (error) {
      ghostImage = null
      ghostUrl = ""
      captureReady = false
    }
    active = true
    try {
      updatePointer(scenePoint)
      return active
    } catch (error) {
      cancel("begin failed")
      throw error
    }
  }

  function refreshSectionHits() {
    if (!active || ending) return
    try {
      sectionHits = snapshotSectionHits()
    } catch (error) {
      sectionHits = []
    }
  }

  function sectionHitAt(point) {
    for (var i = 0; i < sectionHits.length; ++i) {
      var hit = sectionHits[i]
      if (hit && hit.identity && contains(hit.rect, point)) return hit
    }
    return null
  }

  function sectionTargetAt(point) {
    var hit = sectionHitAt(point)
    return hit && canTargetMonitor(hit.identity) ? hit : null
  }

  function updatePointer(scenePoint) {
    if (!active || ending) return false
    if (!validPoint(scenePoint) || !available(sourceDock)) {
      cancel("invalid session")
      return false
    }

    pointerScene = scenePoint
    refreshSectionHits()
    pointerVirtual = sceneToVirtual(sourceDock, scenePoint)
    pointerDock = pointerDockAt(pointerVirtual)
    hoveredTarget = null
    hoveredMonitor = ""
    var covering = sectionHitAt(pointerVirtual)
    var section = sectionTargetAt(pointerVirtual)
    if (section) {
      hoveredTarget = section.dock
      hoveredMonitor = section.identity
    }
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      dock.workspaceMonitorDropHighlighted = false
      if (dock.dragRevealed && !available(dock) && dock !== sourceDock) {
        cancel("destination unavailable")
        return false
      }
      if (!available(dock)) continue
      if (contains(dock.revealRect, pointerVirtual)) dock.dragRevealed = true
      if (!hoveredMonitor && !covering && dock !== sourceDock
          && (dock.dragRevealed || dock.dockShown)
          && contains(dock.dropRect, pointerVirtual)
          && canTargetMonitor(dock.monitorIdentity)) {
        hoveredTarget = dock
        hoveredMonitor = String(dock.monitorIdentity)
      }
    }
    if (hoveredTarget) hoveredTarget.workspaceMonitorDropHighlighted = true
    return hoveredMonitor !== ""
  }

  function finish(scenePoint) {
    if (!active || finishing || ending) return false
    finishing = true
    try {
      updatePointer(scenePoint)
      if (!active || !hoveredMonitor || !canTargetMonitor(hoveredMonitor))
        return false
      return windowActions.moveWorkspaceToMonitor(sourceWorkspace, hoveredMonitor)
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
    hoveredMonitor = ""
    pointerScene = Qt.point(0, 0)
    sectionHits = []
    captureGeneration += 1
    captureReady = false
    ghostImage = null
    ghostUrl = ""
    ghostSize = Qt.size(0, 0)
    grabOffset = Qt.point(0, 0)
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
