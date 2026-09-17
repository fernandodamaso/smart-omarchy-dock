import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "DockWorkspaceMonitorDrag"
  when: windowShown
  visible: true
  width: 800
  height: 240

  QtObject {
    id: actions
    property bool allowed: true
    property int moves: 0
    property string movedWorkspace: ""
    property string movedMonitor: ""
    property string ownerMonitor: "id:0"
    property bool dispatchAccepted: true
    property bool dispatchThrows: false
    function canMoveWorkspaceToMonitor(workspace, monitor) {
      return allowed && workspace === "id:3" && monitor === "id:1"
    }
    function moveWorkspaceToMonitor(workspace, monitor) {
      if (dispatchThrows) throw new Error("dispatch")
      if (!dispatchAccepted) return false
      if (!canMoveWorkspaceToMonitor(workspace, monitor)) return false
      moves++
      movedWorkspace = workspace
      movedMonitor = monitor
      return true
    }
    function resolveWorkspaceDropTarget(workspace) {
      return { identity: workspace, monitor: ownerMonitor }
    }
  }

  Component {
    id: dockComponent
    Item {
      id: dock
      property string monitorIdentity: ""
      property point monitorOrigin: Qt.point(0, 0)
      property point sceneOrigin: monitorOrigin
      property rect monitorRect: Qt.rect(0, 0, 1, 1)
      property rect revealRect: Qt.rect(0, 0, 0, 0)
      property rect dropRect: Qt.rect(0, 0, 0, 0)
      property bool dragRevealed: false
      property bool dockShown: false
      property bool workspaceMonitorDropHighlighted: false
      property bool workspaceMonitorDragAvailable: true
      property var sectionHits: []
      property bool cardAvailable: true
      property string captureMode: "ok"
      property var pendingCapture: null
      property var card: dragCard
      function workspaceMonitorSectionHits() { return sectionHits }
      function workspaceMonitorViewportRect() { return dropRect }
      function cardForWorkspace(identity) { return cardAvailable ? dragCard : null }
      QtObject {
        id: dragCard
        property real width: 120
        property real height: 50
        function mapToItem(item, x, y) { return Qt.point(x + 10, y + 20) }
        function grabToImage(callback) {
          if (dock.captureMode === "throw") throw new Error("capture")
          if (dock.captureMode === "sync") {
            callback({ url: "image://workspace-drag-test" })
            return
          }
          dock.pendingCapture = callback
          Qt.callLater(function() {
            if (dock.pendingCapture !== callback) return
            callback(dock.captureMode === "empty" ? null
              : { url: "image://workspace-drag-test" })
          })
        }
      }
      property color workspaceMonitorDragAccent: "#80a0ff"
      property color workspaceMonitorDragBackground: "#202020"
      property color workspaceMonitorDragForeground: "white"
      property string workspaceMonitorDragFontFamily: "Sans"
      property int workspaceMonitorDragFontSize: 12
    }
  }

  Component {
    id: dragComponent
    Components.DockWorkspaceMonitorDrag {
      windowActions: actions
      property int endings: 0
      property var projectionChanges: []
      onEnded: endings++
      onProjectionMonitorChanged: projectionChanges =
        projectionChanges.concat([projectionMonitor])
    }
  }

  function makeDock(properties) {
    var dock = createTemporaryObject(dockComponent, testCase, properties)
    verify(dock)
    return dock
  }

  function makeScene() {
    var source = makeDock({
      monitorIdentity: "id:0",
      monitorOrigin: Qt.point(-1536, 0),
      sceneOrigin: Qt.point(-1536, 744),
      monitorRect: Qt.rect(-1536, 0, 1536, 864),
      dockShown: true,
      revealRect: Qt.rect(-1536, 861, 1536, 3),
      dropRect: Qt.rect(-1100, 790, 700, 64)
    })
    var destination = makeDock({
      monitorIdentity: "id:1",
      monitorOrigin: Qt.point(0, -1080),
      sceneOrigin: Qt.point(0, -120),
      monitorRect: Qt.rect(0, -1080, 1920, 1080),
      revealRect: Qt.rect(0, -3, 1920, 3),
      dropRect: Qt.rect(600, -80, 720, 70)
    })
    var drag = createTemporaryObject(dragComponent, testCase)
    verify(drag)
    drag.registerDock(source)
    drag.registerDock(destination)
    return { drag: drag, source: source, destination: destination }
  }

  function init() {
    actions.allowed = true
    actions.moves = 0
    actions.movedWorkspace = ""
    actions.movedMonitor = ""
    actions.ownerMonitor = "id:0"
    actions.dispatchAccepted = true
    actions.dispatchThrows = false
  }

  function verifyClean(scene) {
    compare(scene.drag.active, false)
    compare(scene.drag.awaitingConfirmation, false)
    compare(scene.drag.moveDispatched, false)
    compare(scene.drag.sourceDock, null)
    compare(scene.drag.hoveredTarget, null)
    compare(scene.drag.hoveredMonitor, "")
    compare(scene.drag.pointerDock, null)
    compare(scene.drag.ghostSize, Qt.size(0, 0))
    compare(scene.source.dragRevealed, false)
    compare(scene.destination.dragRevealed, false)
    compare(scene.source.workspaceMonitorDropHighlighted, false)
    compare(scene.destination.workspaceMonitorDropHighlighted, false)
  }

  function test_captureFailureAndStaleCallbacksNeverDispatch() {
    var scene = makeScene()
    scene.source.captureMode = "sync"
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    compare(scene.drag.captureReady, true,
      "a synchronous grab callback must arm the live drag")
    scene.drag.cancel("synchronous capture cleanup")
    verifyClean(scene)

    scene = makeScene()
    scene.source.cardAvailable = false
    verify(!scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    verifyClean(scene)

    scene = makeScene()
    scene.source.captureMode = "throw"
    verify(!scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    verifyClean(scene)

    scene = makeScene()
    scene.source.captureMode = "empty"
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "active", false, 1000)
    compare(actions.moves, 0)
    verifyClean(scene)

    scene = makeScene()
    scene.source.card.width = 140
    scene.source.card.height = 60
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    compare(scene.drag.ghostSize, Qt.size(140, 60))
    scene.source.card.width = 20
    scene.source.card.height = 20
    tryCompare(scene.drag, "captureReady", true, 1000)
    compare(scene.drag.ghostSize, Qt.size(140, 60))
    scene.drag.cancel("snapshot")
    verifyClean(scene)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    var callback = scene.source.pendingCapture
    scene.drag.cancel("escape")
    callback({ url: "image://stale" })
    compare(actions.moves, 0)
    verifyClean(scene)
    scene.drag.cancel("repeat")
    verifyClean(scene)
  }

  function test_oneShotDispatchConfirmationRejectionTimeoutAndRemoval() {
    var scene = makeScene()
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(scene.drag.awaitingConfirmation, true)
    compare(scene.drag.active, false)
    compare(scene.drag.ghostUrl, "")
    compare(scene.drag.ghostSize, Qt.size(120, 50))
    actions.ownerMonitor = "id:1"
    verify(scene.drag.reconcileCompositorOwnership())
    verifyClean(scene)
    actions.dispatchAccepted = true
    actions.dispatchThrows = false

    scene = makeScene()
    actions.ownerMonitor = "id:0"
    actions.moves = 0
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    actions.dispatchAccepted = false
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)
    actions.dispatchAccepted = true

    scene = makeScene()
    actions.ownerMonitor = "id:0"
    actions.moves = 0
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    actions.dispatchThrows = true
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)
    actions.dispatchThrows = false

    scene = makeScene()
    actions.ownerMonitor = "id:0"
    actions.moves = 0
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    verify(scene.drag.finish(Qt.point(2436, -784)))
    verify(scene.drag.awaitingConfirmation)
    scene.drag.confirmationTimedOut()
    verifyClean(scene)

    scene = makeScene()
    actions.moves = 0
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    verify(scene.drag.finish(Qt.point(2436, -784)))
    scene.drag.unregisterDock(scene.source)
    verifyClean(scene)
  }

  function test_virtualCoordinatesRevealProxyHandoffAndCommitOnce() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 4, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    compare(scene.drag.pointerVirtual, Qt.point(-1436, 844))
    compare(scene.drag.pointerDock, scene.source)

    // Source-local coordinates continue beyond its grabbed window. Adding the
    // source monitor's logical origin places the pointer on the foreign edge.
    scene.drag.updatePointer(Qt.point(2436, -745))
    compare(scene.drag.pointerVirtual, Qt.point(900, -1))
    compare(scene.drag.pointerDock, scene.destination)
    compare(scene.destination.dragRevealed, true)
    compare(scene.drag.hoveredTarget, null)
    scene.destination.dockShown = true
    wait(220)

    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, scene.destination)
    compare(scene.destination.workspaceMonitorDropHighlighted, true)
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    compare(actions.movedWorkspace, "id:3")
    compare(actions.movedMonitor, "id:1")
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    compare(scene.drag.awaitingConfirmation, true)
    scene.drag.confirmationTimedOut()
    compare(scene.drag.endings, 1)
    verifyClean(scene)
  }

  function test_rightToLeftPointerKeepsStableProjection() {
    var source = makeDock({
      monitorIdentity: "id:0",
      monitorOrigin: Qt.point(1920, 0),
      sceneOrigin: Qt.point(1920, 1014),
      monitorRect: Qt.rect(1920, 0, 1920, 1080),
      dockShown: true,
      dropRect: Qt.rect(2520, 1014, 720, 66)
    })
    var destination = makeDock({
      monitorIdentity: "id:1",
      monitorOrigin: Qt.point(0, 0),
      sceneOrigin: Qt.point(0, 1014),
      monitorRect: Qt.rect(0, 0, 1920, 1080),
      dockShown: true,
      dropRect: Qt.rect(600, 1014, 720, 66),
      sectionHits: [{ identity: "id:1", rect: Qt.rect(600, 1014, 720, 66) }]
    })
    var drag = createTemporaryObject(dragComponent, testCase)
    verify(drag)
    drag.registerDock(source)
    drag.registerDock(destination)

    verify(drag.begin(source, "id:3", "3", 1, "id:0", Qt.point(120, 30)))
    tryCompare(drag, "captureReady", true, 1000)
    drag.updatePointer(Qt.point(-1000, 30))
    compare(drag.pointerVirtual, Qt.point(920, 1044))
    compare(drag.projectionMonitor, "id:1")

    drag.projectionChanges = []
    drag.updatePointer(Qt.point(-990, 30))
    compare(drag.projectionMonitor, "id:1")
    compare(drag.projectionChanges.length, 0,
      "moving within one target must not transiently remove its placeholder")
    drag.cancel("test cleanup")
    verifyClean({ drag: drag, source: source, destination: destination })
  }

  function test_pendingSizeClearsAndNextDragCapturesFreshDimensions() {
    var scene = makeScene()
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(scene.drag.ghostSize, Qt.size(120, 50))
    scene.drag.confirmationTimedOut()
    verifyClean(scene)

    scene = makeScene()
    scene.source.card.width = 200
    scene.source.card.height = 70
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    compare(scene.drag.ghostSize, Qt.size(200, 70))
    scene.drag.cancel("explicit cancellation")
    verifyClean(scene)
  }

  function test_ineligibleSameMonitorAndOutsideDropsCancel() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -745))
    actions.allowed = false
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, null)
    compare(scene.destination.workspaceMonitorDropHighlighted, false)
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)

    scene = makeScene()
    scene.destination.monitorIdentity = "id:0"
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, null)
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)

    scene = makeScene()
    actions.ownerMonitor = "id:1"
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:1", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -745))
    wait(220)
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, null,
      "all-mode cards must not target the workspace's current owner")
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)
  }

  function test_sameDockForeignSectionCommitsOnReleaseOnly() {
    var scene = makeScene()
    scene.source.sectionHits = [
      { identity: "id:0", rect: Qt.rect(-1536, 790, 736, 64) },
      { identity: "id:1", rect: Qt.rect(-800, 790, 700, 64) }
    ]
    verify(scene.drag.begin(scene.source, "id:3", "Work", 4, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    compare(scene.drag.hoveredMonitor, "")
    compare(actions.moves, 0)

    scene.drag.updatePointer(Qt.point(836, 76))
    compare(scene.drag.hoveredMonitor, "id:1")
    compare(scene.drag.hoveredTarget, scene.source)
    compare(actions.moves, 0, "hovering the other monitor section must not move yet")

    verify(scene.drag.finish(Qt.point(836, 76)))
    compare(actions.moves, 1)
    compare(actions.movedWorkspace, "id:3")
    compare(actions.movedMonitor, "id:1")
    compare(scene.drag.awaitingConfirmation, true)
    scene.drag.confirmationTimedOut()
    verifyClean(scene)
  }

  function test_alreadyVisibleDestinationAcceptsDirectDrop() {
    var scene = makeScene()
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.destination.dragRevealed, false)
    compare(scene.drag.hoveredTarget, scene.destination)
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    scene.drag.confirmationTimedOut()
    verifyClean(scene)
  }

  function test_invalidatedDockCancelsAndCleansForeignState() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -745))
    scene.destination.dockShown = true
    wait(220)
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, scene.destination)
    scene.drag.unregisterDock(scene.destination)
    verifyClean(scene)
    compare(scene.drag.endings, 1)
    compare(actions.moves, 0)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.unregisterDock(scene.source)
    verifyClean(scene)
    compare(scene.drag.endings, 1)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -745))
    compare(scene.destination.dragRevealed, true)
    compare(scene.drag.hoveredTarget, null)
    scene.drag.unregisterDock(scene.destination)
    verifyClean(scene)
    compare(scene.drag.endings, 1)
  }

  function test_rejectedSectionBlocksPhysicalDockFallback() {
    var scene = makeScene()
    scene.destination.dockShown = true
    scene.destination.sectionHits = [
      { identity: "id:0", rect: Qt.rect(600, -80, 360, 70) },
      { identity: "id:1", rect: Qt.rect(960, -80, 360, 70) }
    ]
    verify(scene.drag.begin(scene.source, "id:3", "Work", 4, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredMonitor, "",
      "dropping onto the current-owner section of another dock must not fall through")
    compare(scene.drag.hoveredTarget, null)
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)
  }

  function test_sectionHitsRefreshAfterDestinationReveal() {
    var scene = makeScene()
    scene.destination.dropRect = Qt.rect(0, 0, 0, 0)
    scene.destination.sectionHits = [
      { identity: "id:1", rect: Qt.rect(600, 800, 720, 70) }
    ]
    verify(scene.drag.begin(scene.source, "id:3", "Work", 4, "id:0", Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    compare(scene.drag.sectionHits.length, 0,
      "hidden destination sections are not pickup targets")

    scene.drag.updatePointer(Qt.point(2436, -745))
    compare(scene.destination.dragRevealed, true)
    wait(220)
    scene.destination.dockShown = true
    scene.destination.sectionHits = [
      { identity: "id:1", rect: Qt.rect(600, -80, 720, 70) }
    ]
    scene.drag.refreshTargetGeometry(scene.destination)
    compare(scene.drag.sectionHits[0].rect.y, -80)
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredMonitor, "id:1",
      "revealed destination sections must retarget from live geometry, not pickup snapshots")
    verify(scene.drag.finish(Qt.point(2436, -784)))
    scene.drag.confirmationTimedOut()
    compare(actions.moves, 1)
    compare(actions.movedMonitor, "id:1")
    verifyClean(scene)
  }

  function test_revealAddsDestinationWithoutRefreshingSource() {
    var scene = makeScene()
    var sourceA = Qt.rect(0, 0, 100, 40)
    var sourceB = Qt.rect(60, 0, 40, 40)
    var destinationC = Qt.rect(100, 100, 100, 40)
    var destinationD = Qt.rect(120, 100, 80, 40)
    scene.source.dropRect = sourceA
    scene.source.sectionHits = [{ identity: "id:0", rect: sourceA }]
    scene.destination.dropRect = destinationC
    scene.destination.sectionHits = [{ identity: "id:1", rect: destinationC }]
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0",
      Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.source.sectionHits = [{ identity: "id:0", rect: sourceB }]
    scene.destination.dockShown = true
    scene.drag.refreshTargetGeometry(scene.destination)
    compare(scene.drag.geometrySnapshots.length, 2)
    compare(scene.drag.geometrySnapshots[0].dock, scene.source)
    compare(scene.drag.geometrySnapshots[0].sections[0].rect, sourceA)
    compare(scene.drag.geometrySnapshots[1].dock, scene.destination)
    compare(scene.drag.geometrySnapshots[1].sections[0].rect, destinationC)
    compare(scene.drag.sectionHitAt(Qt.point(20, 20)).rect, sourceA)

    scene.destination.sectionHits = [{ identity: "id:1", rect: destinationD }]
    scene.destination.dropRect = destinationD
    scene.drag.refreshTargetGeometry(scene.destination)
    compare(scene.drag.geometrySnapshots.length, 2)
    compare(scene.drag.geometrySnapshots[0].sections[0].rect, sourceA)
    compare(scene.drag.geometrySnapshots[1].sections[0].rect, destinationD)
    scene.drag.cancel("test cleanup")
    verifyClean(scene)
  }

  function test_targetedScrollKeepsSourceAndThirdDockSnapshots() {
    var scene = makeScene()
    var third = makeDock({
      monitorIdentity: "id:2",
      monitorOrigin: Qt.point(1920, 0),
      sceneOrigin: Qt.point(1920, 744),
      monitorRect: Qt.rect(1920, 0, 1920, 1080),
      dockShown: true,
      dropRect: Qt.rect(2100, 800, 120, 40)
    })
    scene.drag.registerDock(third)
    var sourceRect = Qt.rect(0, 0, 100, 40)
    var destinationRect = Qt.rect(100, 100, 100, 40)
    var thirdRect = Qt.rect(2100, 800, 120, 40)
    scene.source.sectionHits = [{ identity: "id:0", rect: sourceRect }]
    scene.destination.dockShown = true
    scene.destination.dropRect = destinationRect
    scene.destination.sectionHits = [{ identity: "id:1", rect: destinationRect }]
    third.sectionHits = [{ identity: "id:2", rect: thirdRect }]
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0",
      Qt.point(100, 100)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    var updatedDestination = Qt.rect(140, 100, 60, 40)
    scene.destination.sectionHits = [
      { identity: "id:1", rect: updatedDestination }
    ]
    scene.destination.dropRect = updatedDestination
    scene.drag.refreshTargetGeometry(scene.destination)
    compare(scene.drag.geometrySnapshots.length, 3)
    compare(scene.drag.geometrySnapshots[0].sections[0].rect, sourceRect)
    compare(scene.drag.geometrySnapshots[1].sections[0].rect, updatedDestination)
    compare(scene.drag.geometrySnapshots[2].sections[0].rect, thirdRect)
    scene.drag.cancel("test cleanup")
    verifyClean(scene)
  }
}
