import QtQuick
import QtTest
import "runtime/workspace-drag-preview" as Preview
import "runtime/workspace-drag-preview/PreviewModel.js" as PreviewModel

TestCase {
  id: testCase
  name: "WorkspaceDragPreview"
  when: windowShown
  visible: true
  width: 900
  height: 400

  property var fixtures: ({
    monitors: [
      {
        identity: "id:0",
        connector: "DP-1",
        label: "Monitor A",
        activeWorkspace: "id:1",
        pinnedWorkspaces: []
      },
      {
        identity: "id:1",
        connector: "HDMI-A-1",
        label: "Monitor B",
        activeWorkspace: "id:4",
        pinnedWorkspaces: ["name:Work"]
      }
    ],
    workspaces: [
      { identity: "id:1", owner: "id:0", label: "1", count: 1, items: [] },
      { identity: "id:2", owner: "id:0", label: "2", count: 1, items: [] },
      { identity: "id:4", owner: "id:1", label: "4", count: 1, items: [] },
      { identity: "name:Work", owner: "id:1", label: "Work", count: 1, items: [] }
    ]
  })
  property var committed: JSON.parse(JSON.stringify(fixtures))
  property int commits: 0
  property int presentations: 0
  property var lastPresentation: null

  Component {
    id: dockComponent
    Item {
      id: dock
      property string monitorIdentity: "id:0"
      property point monitorOrigin: Qt.point(0, 0)
      property point sceneOrigin: Qt.point(0, 0)
      property rect monitorRect: Qt.rect(0, 0, 400, 200)
      property rect revealRect: Qt.rect(0, 190, 400, 10)
      property rect dropRect: Qt.rect(20, 120, 360, 60)
      property bool dragRevealed: false
      property bool dockShown: true
      property bool workspaceMonitorDropHighlighted: false
      property bool workspaceMonitorDragAvailable: true
      property color workspaceMonitorDragAccent: "#80a0ff"
      property color workspaceMonitorDragBackground: "#202020"
      property color workspaceMonitorDragForeground: "white"
      property string workspaceMonitorDragFontFamily: "Sans"
      property int workspaceMonitorDragFontSize: 12
      property var cards: ({})
      property var sectionHitRects: [
        { identity: monitorIdentity, rect: Qt.rect(20, 120, 360, 60) }
      ]

      function cardFor(workspaceIdentity) {
        return cards[workspaceIdentity] || null
      }

      function sectionAt(scenePoint) {
        var local = Qt.point(scenePoint.x - sceneOrigin.x, scenePoint.y - sceneOrigin.y)
        for (var i = 0; i < sectionHitRects.length; ++i) {
          var hit = sectionHitRects[i]
          var rect = hit.rect
          if (local.x >= rect.x && local.x < rect.x + rect.width
              && local.y >= rect.y && local.y < rect.y + rect.height)
            return hit.identity
        }
        if (local.x >= 0 && local.x < width && local.y >= 0 && local.y < height)
          return monitorIdentity
        return ""
      }

      function snapshotSectionHits() {
        return sectionHitRects
      }

      width: 400
      height: 200

      Rectangle {
        id: cardA
        objectName: "card-id:2"
        x: 40
        y: 130
        width: 80
        height: 40
        color: "#445566"
        property string workspaceIdentity: "id:2"
      }

      Component.onCompleted: cards = ({ "id:2": cardA, "name:Work": cardA })
    }
  }

  Component {
    id: dragComponent
    Preview.PreviewDrag {
      committedFixtures: testCase.committed
      animationsEnabled: false
      onFixturesCommitted: fixtures => {
        testCase.committed = fixtures
        testCase.commits++
      }
      onPresentationChanged: presentation => {
        testCase.lastPresentation = presentation
        testCase.presentations++
      }
    }
  }

  function makeScene() {
    testCase.committed = JSON.parse(JSON.stringify(testCase.fixtures))
    testCase.commits = 0
    testCase.presentations = 0
    testCase.lastPresentation = null
    var source = createTemporaryObject(dockComponent, testCase, {
      monitorIdentity: "id:0",
      monitorOrigin: Qt.point(0, 0),
      sceneOrigin: Qt.point(0, 0),
      monitorRect: Qt.rect(0, 0, 400, 200),
      dropRect: Qt.rect(20, 120, 360, 60)
    })
    var destination = createTemporaryObject(dockComponent, testCase, {
      x: 420,
      monitorIdentity: "id:1",
      monitorOrigin: Qt.point(420, 0),
      sceneOrigin: Qt.point(420, 0),
      monitorRect: Qt.rect(420, 0, 400, 200),
      dropRect: Qt.rect(20, 120, 360, 60),
      sectionHitRects: [
        { identity: "id:1", rect: Qt.rect(20, 120, 360, 60) }
      ]
    })
    var drag = createTemporaryObject(dragComponent, testCase)
    verify(drag)
    drag.registerDock(source)
    drag.registerDock(destination)
    return { drag: drag, source: source, destination: destination }
  }

  function verifyClean(scene) {
    compare(scene.drag.active, false)
    compare(scene.drag.sourceDock, null)
    compare(scene.drag.sourceWorkspace, "")
    compare(scene.drag.captureReady, false)
    compare(scene.drag.ghostUrl, "")
    compare(scene.source.workspaceMonitorDropHighlighted, false)
    compare(scene.destination.workspaceMonitorDropHighlighted, false)
  }

  function test_beginCaptureFinishCancelAndDuplicateFinish() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:2", "2", 1, "id:0", Qt.point(50, 140)))
    compare(scene.drag.active, true)
    compare(scene.drag.sourceWorkspace, "id:2")
    tryCompare(scene.drag, "captureReady", true, 1000)
    verify(scene.drag.ghostUrl !== "")
    compare(scene.drag.ghostSize.width, 80)
    compare(scene.drag.ghostSize.height, 40)

    scene.drag.updatePointer(Qt.point(480, 140))
    compare(scene.drag.targetMonitor, "id:1")
    verify(scene.drag.finish(Qt.point(480, 140)))
    compare(testCase.commits, 1)
    compare(testCase.committed.workspaces.find(w => w.identity === "id:2").owner, "id:1")
    verify(!scene.drag.finish(Qt.point(480, 140)))
    compare(testCase.commits, 1)
    verifyClean(scene)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:2", "2", 1, "id:0", Qt.point(50, 140)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.cancel("escape")
    compare(testCase.commits, 0)
    verifyClean(scene)
  }

  function test_rejectCurrentOwnerPinnedAndStaleCapture() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:2", "2", 1, "id:0", Qt.point(50, 140)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(60, 140))
    compare(scene.drag.targetMonitor, "")
    verify(!scene.drag.finish(Qt.point(60, 140)))
    compare(testCase.commits, 0)
    verifyClean(scene)

    scene = makeScene()
    verify(scene.drag.begin(scene.source, "name:Work", "Work", 1, "id:1", Qt.point(50, 140)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.updatePointer(Qt.point(60, 140))
    // Force a foreign target identity through section lookup on source dock background.
    scene.source.sectionHitRects = [
      { identity: "id:0", rect: Qt.rect(20, 120, 360, 60) }
    ]
    scene.drag.updatePointer(Qt.point(60, 140))
    compare(scene.drag.targetMonitor, "")
    verify(!scene.drag.finish(Qt.point(60, 140)))
    compare(testCase.commits, 0)
    verifyClean(scene)

    scene = makeScene()
    var generation = 0
    verify(scene.drag.begin(scene.source, "id:2", "2", 1, "id:0", Qt.point(50, 140)))
    generation = scene.drag.captureGeneration
    scene.drag.cancel("replaced")
    scene.drag.handleCaptureResult(generation, {
      image: "stale",
      url: "image://stale"
    }, 80, 40)
    compare(scene.drag.active, false)
    compare(scene.drag.ghostUrl, "")
  }

  function test_fixtureReplacementCancelsAndCleans() {
    var scene = makeScene()
    verify(scene.drag.begin(scene.source, "id:2", "2", 1, "id:0", Qt.point(50, 140)))
    tryCompare(scene.drag, "captureReady", true, 1000)
    scene.drag.cancel("fixture replacement")
    verifyClean(scene)
  }
}
