import QtQuick

// Host-owned cross-window gesture state. Docks provide virtual rectangles and
// render their own proxy so this component stays usable in headless Qt tests.
Item {
  id: root

  required property var windowActions
  property var docks: []
  property bool active: false
  property bool awaitingConfirmation: false
  property bool moveDispatched: false
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
  property var geometrySnapshots: []
  property point pointerScene: Qt.point(0, 0)
  property bool captureReady: false
  property int captureGeneration: 0
  property var ghostImage: null
  property url ghostUrl: ""
  property size ghostSize: Qt.size(0, 0)
  property point grabOffset: Qt.point(0, 0)
  property bool finishing: false
  property bool ending: false
  property string pendingMonitor: ""
  readonly property string projectionMonitor: active ? hoveredMonitor
    : awaitingConfirmation ? pendingMonitor : ""
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

  Timer {
    id: revealSettling
    interval: 180
    repeat: false
    onTriggered: {
      var dock = root.revealDock
      root.revealDock = null
      if (!root.active || !dock) return
      root.refreshTargetGeometry(dock)
      root.updatePointer(root.pointerScene)
    }
  }

  Timer {
    id: confirmationTimer
    interval: 2000
    repeat: false
    onTriggered: root.confirmationTimedOut()
  }

  property var revealDock: null

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
    return registered(dock) && dock.workspaceMonitorDragAvailable !== false
      && String(dock.monitorIdentity || "") !== ""
  }

  function geometryAvailable(dock) {
    return available(dock) && dock.visible !== false && dock.dockShown !== false
  }

  function registerDock(dock) {
    if (!dock || registered(dock)) return false
    docks = docks.concat([dock])
    return true
  }

  function unregisterDock(dock) {
    var index = docks.indexOf(dock)
    if (index < 0) return false
    var cancelsSession = (active || awaitingConfirmation)
      && (dock === sourceDock || dock === hoveredTarget || dock === pointerDock
        || dock.dragRevealed || String(dock.monitorIdentity || "") === pendingMonitor)
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
    geometrySnapshots = []
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!geometryAvailable(dock)) continue
      var list = typeof dock.workspaceMonitorSectionHits === "function"
        ? dock.workspaceMonitorSectionHits() || [] : []
      var fallback = typeof dock.workspaceMonitorViewportRect === "function"
        ? dock.workspaceMonitorViewportRect() : dock.dropRect
      var snapshot = { dock: dock, sections: [], fallback: fallback }
      for (var j = 0; j < list.length; ++j) {
        var hit = list[j]
        if (!hit || !hit.identity || !hit.rect) continue
        var section = { dock: dock, identity: String(hit.identity), rect: hit.rect }
        snapshot.sections.push(section)
        hits.push(section)
      }
      geometrySnapshots.push(snapshot)
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
    if (!dock || typeof dock.cardForWorkspace !== "function") return false
    var card = dock.cardForWorkspace(workspace)
    if (!card || typeof card.grabToImage !== "function") return false
    ghostSize = Qt.size(card.width, card.height)
    var origin = card.mapToItem(null, 0, 0)
    grabOffset = Qt.point(scenePoint.x - origin.x, scenePoint.y - origin.y)
    try {
      card.grabToImage(function(result) {
        if (generation !== captureGeneration || ending) return
        if (!result || !result.url) {
          cancel("capture failed")
          return
        }
        ghostImage = result
        ghostUrl = result.url
        captureReady = true
        updatePointer(pointerScene)
      })
    } catch (error) {
      return false
    }
    return true
  }

  function resetBeginFailure() {
    clearPointerState()
    clearPending()
  }

  function begin(dock, workspace, label, count, monitor, scenePoint) {
    if (active || awaitingConfirmation || finishing || ending || !available(dock) || !windowActions
        || !validPoint(scenePoint) || !workspace || !monitor)
      return false
    sourceDock = dock
    sourceWorkspace = String(workspace)
    sourceMonitor = String(monitor)
    sourceLabel = String(label || workspace)
    sourceCount = Math.max(0, Number(count) || 0)
    try {
      if (!captureGhost(dock, workspace, scenePoint)) {
        resetBeginFailure()
        return false
      }
    } catch (error) {
      resetBeginFailure()
      return false
    }
    try {
      sectionHits = snapshotSectionHits()
    } catch (error) {
      sectionHits = []
      geometrySnapshots = []
    }
    pendingMonitor = ""
    moveDispatched = false
    active = true
    try {
      updatePointer(scenePoint)
      return active
    } catch (error) {
      cancel("begin failed")
      throw error
    }
  }

  function refreshTargetGeometry(dock) {
    if ((!active && !awaitingConfirmation) || ending) return
    try {
      if (dock) {
        var selected = []
        if (geometryAvailable(dock) && typeof dock.workspaceMonitorSectionHits === "function") {
          var list = dock.workspaceMonitorSectionHits() || []
          for (var selectedIndex = 0; selectedIndex < list.length; ++selectedIndex) {
            var hit = list[selectedIndex]
            if (hit && hit.identity && hit.rect)
              selected.push({ dock: dock, identity: String(hit.identity), rect: hit.rect })
          }
        }
        var merged = geometrySnapshots.slice()
        var index = -1
        for (var i = 0; i < merged.length; ++i) {
          if (merged[i].dock === dock) {
            index = i
            break
          }
        }
        var snapshot = {
          dock: dock,
          sections: selected,
          fallback: geometryAvailable(dock)
            ? (typeof dock.workspaceMonitorViewportRect === "function"
              ? dock.workspaceMonitorViewportRect() : dock.dropRect)
            : Qt.rect(0, 0, 0, 0)
        }
        if (index < 0) merged.push(snapshot)
        else merged[index] = snapshot
        geometrySnapshots = merged
        sectionHits = merged.reduce(function(result, entry) {
          return result.concat(entry.sections)
        }, [])
        return
      }
      sectionHits = snapshotSectionHits()
    } catch (error) {
      sectionHits = []
      geometrySnapshots = []
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
    if (!sourceStillOwned()) {
      cancel("source owner changed")
      return false
    }

    pointerScene = scenePoint
    pointerVirtual = sceneToVirtual(sourceDock, scenePoint)
    pointerDock = pointerDockAt(pointerVirtual)
    var nextHoveredTarget = null
    var nextHoveredMonitor = ""
    if (!captureReady) {
      hoveredTarget = null
      hoveredMonitor = ""
      for (var waitingIndex = 0; waitingIndex < docks.length; ++waitingIndex) {
        if (docks[waitingIndex]) docks[waitingIndex].workspaceMonitorDropHighlighted = false
      }
      return false
    }
    var covering = sectionHitAt(pointerVirtual)
    var section = sectionTargetAt(pointerVirtual)
    if (section) {
      nextHoveredTarget = section.dock
      nextHoveredMonitor = section.identity
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
      if (dock !== sourceDock && contains(dock.revealRect, pointerVirtual)) {
        if (!dock.dragRevealed) {
          dock.dragRevealed = true
          revealDock = dock
          revealSettling.restart()
        }
        continue
      }
      if (!nextHoveredMonitor && !covering && dock !== sourceDock
          && geometryAvailable(dock) && (dock.dragRevealed || dock.dockShown)
          && contains((function() {
            for (var s = 0; s < geometrySnapshots.length; ++s)
              if (geometrySnapshots[s].dock === dock) return geometrySnapshots[s].fallback
            return null
          })(), pointerVirtual)
          && canTargetMonitor(dock.monitorIdentity)) {
        nextHoveredTarget = dock
        nextHoveredMonitor = String(dock.monitorIdentity)
      }
    }
    hoveredTarget = nextHoveredTarget
    hoveredMonitor = nextHoveredMonitor
    if (hoveredTarget) hoveredTarget.workspaceMonitorDropHighlighted = true
    return captureReady && hoveredMonitor !== ""
  }

  function sourceStillOwned() {
    if (!windowActions || typeof windowActions.resolveWorkspaceDropTarget !== "function")
      return true
    try {
      var resolved = windowActions.resolveWorkspaceDropTarget(sourceWorkspace)
      return resolved && String(resolved.monitor || "") === sourceMonitor
    } catch (error) {
      return false
    }
  }

  function clearPointerState() {
    active = false
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      dock.dragRevealed = false
      dock.workspaceMonitorDropHighlighted = false
    }
    pointerVirtual = Qt.point(0, 0)
    pointerDock = null
    hoveredTarget = null
    hoveredMonitor = ""
    pointerScene = Qt.point(0, 0)
    sectionHits = []
    geometrySnapshots = []
    revealDock = null
    revealSettling.stop()
    captureGeneration += 1
    captureReady = false
    ghostImage = null
    ghostUrl = ""
    grabOffset = Qt.point(0, 0)
  }

  function clearPending() {
    confirmationTimer.stop()
    awaitingConfirmation = false
    pendingMonitor = ""
    moveDispatched = false
    sourceDock = null
    sourceWorkspace = ""
    sourceMonitor = ""
    sourceLabel = ""
    sourceCount = 0
    ghostSize = Qt.size(0, 0)
  }

  function reconcileCompositorOwnership() {
    if (!awaitingConfirmation || !windowActions
        || typeof windowActions.resolveWorkspaceDropTarget !== "function") return false
    var resolved = windowActions.resolveWorkspaceDropTarget(sourceWorkspace)
    if (!resolved || String(resolved.monitor || "") !== pendingMonitor) return false
    clearPending()
    return true
  }

  function confirmationTimedOut() {
    if (!awaitingConfirmation) return false
    clearPending()
    return true
  }

  function finish(scenePoint) {
    if (!active || finishing || ending || moveDispatched) return false
    finishing = true
    try {
      if (!captureReady || !sourceStillOwned()) {
        cancel("invalid release")
        return false
      }
      updatePointer(scenePoint)
      var target = hoveredMonitor
      if (!active || !target || !canTargetMonitor(target)) {
        cancel("invalid release")
        return false
      }
      moveDispatched = true
      var dispatched = false
      try {
        dispatched = windowActions.moveWorkspaceToMonitor(sourceWorkspace, target) === true
      } catch (error) {
        dispatched = false
      }
      if (!dispatched) {
        cancel("move rejected")
        return false
      }
      pendingMonitor = String(target)
      awaitingConfirmation = true
      clearPointerState()
      confirmationTimer.restart()
      ended()
      return true
    } finally {
      finishing = false
    }
  }

  function endSession() {
    if ((!active && !awaitingConfirmation) || ending) return
    ending = true
    clearPointerState()
    clearPending()
    ended()
    ending = false
  }

  function cancel(reason) {
    endSession()
  }

  onSourceDockChanged: if ((active || awaitingConfirmation) && !sourceDock) cancel("source destroyed")
  onWindowActionsChanged: if (active || awaitingConfirmation) cancel("controller replaced")
  onEnabledChanged: if (!enabled) cancel("disabled")
  Component.onDestruction: cancel("coordinator destroyed")
}
