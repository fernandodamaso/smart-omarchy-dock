import QtQuick
import "PreviewModel.js" as PreviewModel

Item {
  id: root

  property var committedFixtures: ({ monitors: [], workspaces: [] })
  property var docks: []
  property var overlayHost: null
  property bool animationsEnabled: true

  property bool active: false
  property bool finishing: false
  property bool ending: false
  property var sourceDock: null
  property string sourceWorkspace: ""
  property string sourceMonitor: ""
  property string sourceLabel: ""
  property int sourceCount: 0
  property var pointerDock: null
  property point pointerScene: Qt.point(0, 0)
  property point pointerVirtual: Qt.point(0, 0)
  property point grabOffset: Qt.point(0, 0)
  property string targetMonitor: ""
  property var hoveredTarget: null
  property bool captureReady: false
  property int captureGeneration: 0
  property var ghostImage: null
  property size ghostSize: Qt.size(0, 0)
  property url ghostUrl: ""
  property var baselineHits: ({})
  property var hoverDrag: null
  property color accent: "#7aa2f7"
  property color background: "#1f2335"
  property color foreground: "#c0caf5"
  property string fontFamily: ""
  property int fontSize: 12
  property int cursorShape: Qt.ArrowCursor

  signal fixturesCommitted(var fixtures)
  signal presentationChanged(var presentation)
  signal ended()

  function registered(dock) {
    return dock && docks.indexOf(dock) >= 0
  }

  function registerDock(dock) {
    if (!dock || registered(dock)) return false
    docks = docks.concat([dock])
    return true
  }

  function unregisterDock(dock) {
    var index = docks.indexOf(dock)
    if (index < 0) return false
    var cancels = active && (dock === sourceDock || dock === hoveredTarget
      || dock === pointerDock)
    docks = docks.slice(0, index).concat(docks.slice(index + 1))
    if (cancels) cancel("dock removed")
    return true
  }

  function emitPresentation(drag) {
    var presentation = PreviewModel.project(committedFixtures, drag)
    presentationChanged(presentation)
    return presentation
  }

  function begin(dock, workspace, label, count, monitor, scenePoint) {
    if (active || finishing || ending || !registered(dock) || !workspace || !monitor)
      return false
    if (!scenePoint || !isFinite(scenePoint.x) || !isFinite(scenePoint.y))
      return false

    var card = dock.cardFor ? dock.cardFor(workspace) : null
    if (!card) return false

    // Capture the full card before any drag dimming/placeholder opacity changes.
    captureReady = false
    ghostImage = null
    ghostUrl = ""
    ghostSize = Qt.size(card.width, card.height)
    var cardOrigin = card.mapToItem(null, 0, 0)
    grabOffset = Qt.point(scenePoint.x - cardOrigin.x, scenePoint.y - cardOrigin.y)
    captureGeneration += 1
    var generation = captureGeneration
    try {
      card.grabToImage(function (result) {
        root.handleCaptureResult(generation, result, card.width, card.height)
      })
    } catch (error) {
      cancel("capture failed")
      return false
    }

    sourceDock = dock
    sourceWorkspace = String(workspace)
    sourceMonitor = String(monitor)
    sourceLabel = String(label || workspace)
    sourceCount = Math.max(0, Number(count) || 0)
    pointerScene = scenePoint
    pointerVirtual = scenePoint
    pointerDock = dock
    targetMonitor = ""
    hoveredTarget = null
    baselineHits = snapshotBaselines()
    hoverDrag = null
    active = true
    emitPresentation(null)
    updatePointer(scenePoint)
    return active
  }

  function handleCaptureResult(generation, result, width, height) {
    if (generation !== captureGeneration || !active || ending)
      return
    if (!result) {
      cancel("capture failed")
      return
    }
    ghostImage = result
    ghostUrl = result.url || ""
    ghostSize = Qt.size(width, height)
    captureReady = true
  }

  function snapshotBaselines() {
    var hits = ({})
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      hits[dock.monitorIdentity] = dock.snapshotSectionHits
        ? dock.snapshotSectionHits()
        : (dock.sectionHitRects || [])
    }
    return hits
  }

  function resolveTarget(scenePoint) {
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      var section = ""
      var origin = dock.sceneOrigin || Qt.point(0, 0)
      var local = Qt.point(scenePoint.x - Number(origin.x),
        scenePoint.y - Number(origin.y))
      var list = baselineHits[dock.monitorIdentity] || []
      for (var j = 0; j < list.length; ++j) {
        var hit = list[j]
        var rect = hit.rect
        if (local.x >= rect.x && local.x < rect.x + rect.width
            && local.y >= rect.y && local.y < rect.y + rect.height) {
          section = hit.identity
          break
        }
      }
      // Snapshot-only targeting while dragging. Live sectionAt is reserved for
      // begin-time baselines and explicit scroll refresh of baselineHits.
      if (!section) continue
      if (section === sourceMonitor) {
        hoveredTarget = null
        cursorShape = Qt.ArrowCursor
        return ""
      }
      var drag = {
        workspaceIdentity: sourceWorkspace,
        targetMonitor: section
      }
      var projected = PreviewModel.project(committedFixtures, drag)
      if (projected.workspaceOwners[sourceWorkspace] !== section) {
        hoveredTarget = null
        cursorShape = Qt.ForbiddenCursor
        return ""
      }
      hoveredTarget = dock
      cursorShape = Qt.ClosedHandCursor
      return section
    }
    hoveredTarget = null
    cursorShape = Qt.ArrowCursor
    return ""
  }

  function clearHighlights() {
    for (var i = 0; i < docks.length; ++i) {
      if (!docks[i]) continue
      docks[i].workspaceMonitorDropHighlighted = false
      if (!active)
        docks[i].dragRevealed = false
    }
  }

  function updatePointer(scenePoint) {
    if (!active || ending) return false
    if (!scenePoint || !isFinite(scenePoint.x) || !isFinite(scenePoint.y)) {
      cancel("invalid pointer")
      return false
    }
    pointerScene = scenePoint
    pointerVirtual = scenePoint
    pointerDock = null
    for (var i = 0; i < docks.length; ++i) {
      var dock = docks[i]
      if (!dock) continue
      var origin = dock.sceneOrigin || Qt.point(0, 0)
      var localX = scenePoint.x - origin.x
      var localY = scenePoint.y - origin.y
      if (dock.width > 0 && dock.height > 0
          && localX >= 0 && localX < dock.width
          && localY >= 0 && localY < dock.height)
        pointerDock = dock
      if (dock.autoHideEnabled && dock.revealRect) {
        var reveal = dock.revealRect
        if (scenePoint.x >= reveal.x && scenePoint.x < reveal.x + reveal.width
            && scenePoint.y >= reveal.y && scenePoint.y < reveal.y + reveal.height)
          dock.dragRevealed = true
      }
    }
    clearHighlights()
    targetMonitor = resolveTarget(scenePoint)
    if (hoveredTarget)
      hoveredTarget.workspaceMonitorDropHighlighted = true
    hoverDrag = targetMonitor ? {
      workspaceIdentity: sourceWorkspace,
      targetMonitor: targetMonitor
    } : null
    emitPresentation(hoverDrag)
    return targetMonitor !== ""
  }

  function finish(scenePoint) {
    if (!active || finishing || ending) return false
    finishing = true
    try {
      updatePointer(scenePoint)
      if (!active || !targetMonitor) return false
      var next = PreviewModel.commit(committedFixtures, sourceWorkspace, targetMonitor)
      if (JSON.stringify(next) === JSON.stringify(committedFixtures))
        return false
      committedFixtures = next
      fixturesCommitted(next)
      emitPresentation(null)
      return true
    } finally {
      endSession()
      finishing = false
    }
  }

  function endSession() {
    if (!active || ending) return
    ending = true
    active = false
    clearHighlights()
    sourceDock = null
    sourceWorkspace = ""
    sourceMonitor = ""
    sourceLabel = ""
    sourceCount = 0
    pointerDock = null
    pointerScene = Qt.point(0, 0)
    pointerVirtual = Qt.point(0, 0)
    grabOffset = Qt.point(0, 0)
    targetMonitor = ""
    hoveredTarget = null
    captureReady = false
    ghostImage = null
    ghostUrl = ""
    ghostSize = Qt.size(0, 0)
    baselineHits = ({})
    hoverDrag = null
    emitPresentation(null)
    ended()
    ending = false
  }

  function cancel(reason) {
    captureGeneration += 1
    if (!active && !ending)
      return
    endSession()
  }
}
