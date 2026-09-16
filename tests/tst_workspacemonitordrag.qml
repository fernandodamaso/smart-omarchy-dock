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
    function canMoveWorkspaceToMonitor(workspace, monitor) {
      return allowed && workspace === "id:3" && monitor === "id:1"
    }
    function moveWorkspaceToMonitor(workspace, monitor) {
      if (!canMoveWorkspaceToMonitor(workspace, monitor)) return false
      moves++
      movedWorkspace = workspace
      movedMonitor = monitor
      return true
    }
  }

  Component {
    id: dockComponent
    Item {
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
      function workspaceMonitorSectionHits() { return sectionHits }
      function cardForWorkspace(identity) { return null }
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
      onEnded: endings++
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
  }

  function verifyClean(scene) {
    compare(scene.drag.active, false)
    compare(scene.drag.sourceDock, null)
    compare(scene.drag.hoveredTarget, null)
    compare(scene.drag.hoveredMonitor, "")
    compare(scene.drag.pointerDock, null)
    compare(scene.source.dragRevealed, false)
    compare(scene.destination.dragRevealed, false)
    compare(scene.source.workspaceMonitorDropHighlighted, false)
    compare(scene.destination.workspaceMonitorDropHighlighted, false)
  }

  function test_virtualCoordinatesRevealProxyHandoffAndCommitOnce() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 4, "id:0", Qt.point(100, 100)))
    compare(scene.drag.pointerVirtual, Qt.point(-1436, 844))
    compare(scene.drag.pointerDock, scene.source)

    // Source-local coordinates continue beyond its grabbed window. Adding the
    // source monitor's logical origin places the pointer on the foreign edge.
    scene.drag.updatePointer(Qt.point(2436, -745))
    compare(scene.drag.pointerVirtual, Qt.point(900, -1))
    compare(scene.drag.pointerDock, scene.destination)
    compare(scene.destination.dragRevealed, true)
    compare(scene.drag.hoveredTarget, null)

    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, scene.destination)
    compare(scene.destination.workspaceMonitorDropHighlighted, true)
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    compare(actions.movedWorkspace, "id:3")
    compare(actions.movedMonitor, "id:1")
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    compare(scene.drag.endings, 1)
    verifyClean(scene)
  }

  function test_ineligibleSameMonitorAndOutsideDropsCancel() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
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
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, null)
    verify(!scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 0)
    verifyClean(scene)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:1", Qt.point(100, 100)))
    scene.drag.updatePointer(Qt.point(2436, -745))
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
    verifyClean(scene)
  }

  function test_alreadyVisibleDestinationAcceptsDirectDrop() {
    var scene = makeScene()
    scene.destination.dockShown = true
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.destination.dragRevealed, false)
    compare(scene.drag.hoveredTarget, scene.destination)
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    verifyClean(scene)
  }

  function test_invalidatedDockCancelsAndCleansForeignState() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    scene.drag.updatePointer(Qt.point(2436, -745))
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredTarget, scene.destination)
    scene.drag.unregisterDock(scene.destination)
    verifyClean(scene)
    compare(scene.drag.endings, 1)
    compare(actions.moves, 0)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
    scene.drag.unregisterDock(scene.source)
    verifyClean(scene)
    compare(scene.drag.endings, 1)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:3", "Work", 0, "id:0", Qt.point(100, 100)))
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
    compare(scene.drag.sectionHits[0].rect.y, 800)

    scene.drag.updatePointer(Qt.point(2436, -745))
    compare(scene.destination.dragRevealed, true)
    scene.destination.sectionHits = [
      { identity: "id:1", rect: Qt.rect(600, -80, 720, 70) }
    ]
    scene.drag.updatePointer(Qt.point(2436, -784))
    compare(scene.drag.hoveredMonitor, "id:1",
      "revealed destination sections must retarget from live geometry, not pickup snapshots")
    verify(scene.drag.finish(Qt.point(2436, -784)))
    compare(actions.moves, 1)
    compare(actions.movedMonitor, "id:1")
    verifyClean(scene)
  }
}
