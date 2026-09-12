import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "DockWorkspaceDrag"
  when: windowShown
  visible: true
  width: 800
  height: 240

  Item { id: source; x: 20; y: 30; width: 40; height: 40 }
  QtObject {
    id: actions
    property int captures: 0
    property int moves: 0
    property bool live: true
    property bool valid: true
    property bool changes: true
    property bool failMove: false
    property string committed: ""
    function captureWorkspaceMove(values) {
      captures++
      return live && values.length ? [{ toplevel: values[0], address: "0x1" }] : []
    }
    function workspaceMoveMembers(values) { return live ? values : [] }
    function resolveWorkspaceDropTarget(identity) {
      return valid && identity === "id:12" ? { identity: identity, target: "12", monitor: "id:1" } : null
    }
    function workspaceMoveWouldChange(values, identity) { return live && valid && changes }
    function moveCapturedToplevels(values, identity) {
      moves++
      committed = identity
      if (failMove) throw new Error("transport failure")
      return true
    }
  }
  Component {
    id: dragComponent
    Components.DockWorkspaceDrag {
      windowActions: actions
      targetAtScenePoint: function(point) { return point.x >= 100 ? "id:12" : "" }
      property int endings: 0
      onEnded: endings++
    }
  }
  Component {
    id: scrollingSceneComponent
    Item {
      x: 60
      y: 100
      width: 300
      height: 100
      property alias layout: layout
      property alias drag: drag
      Components.DockWorkspaceLayout {
        id: layout
        anchors.fill: parent
        windowDragActive: drag.active
        dragScenePosition: drag.pointerScene
        onViewportChanged: if (drag.active) drag.updatePointer(drag.pointerScene)
        Rectangle { width: 150; height: 50 }
        Rectangle { id: destination; width: 150; height: 50 }
      }
      Components.DockWorkspaceDrag {
        id: drag
        anchors.fill: parent
        windowActions: actions
        targetAtScenePoint: function(point) {
          if (!layout.containsScenePoint(point)) return ""
          var local = destination.mapFromItem(null, point.x, point.y)
          return local.x >= 0 && local.x < destination.width
            && local.y >= 0 && local.y < destination.height ? "id:12" : ""
        }
      }
    }
  }
  function init() {
    actions.captures = 0
    actions.moves = 0
    actions.live = true
    actions.valid = true
    actions.changes = true
    actions.failMove = false
    actions.committed = ""
  }
  function makeDrag() {
    var drag = createTemporaryObject(dragComponent, testCase, { x: 13, y: 7 })
    verify(drag)
    return drag
  }
  function verifyClean(drag) {
    compare(drag.active, false)
    compare(drag.sourceItem, null)
    compare(drag.members.length, 0)
    compare(drag.hoveredIdentity, "")
    compare(drag.iconSource.toString(), "")
  }
  function test_captureOnceAndFinishOnce() {
    var drag = makeDrag()
    verify(drag.begin(source, [source], Qt.point(25, 35), ""))
    verify(!drag.begin(source, [source], Qt.point(150, 35), ""))
    drag.updatePointer(Qt.point(150, 35))
    compare(actions.captures, 1)
    compare(drag.pointerScene.x, 150)
    compare(drag.hoveredIdentity, "id:12")
    verify(drag.finish(Qt.point(150, 35)))
    compare(actions.moves, 1)
    compare(actions.committed, "id:12")
    verify(!drag.finish(Qt.point(150, 35)))
    drag.cancel("duplicate")
    compare(actions.moves, 1)
    compare(drag.endings, 1)
    verifyClean(drag)
  }
  function test_finalPointerAndVanishedDestination() {
    var drag = makeDrag()
    verify(drag.begin(source, [source], Qt.point(150, 35), ""))
    verify(!drag.finish(Qt.point(20, 35)))
    compare(actions.moves, 0)
    verifyClean(drag)
    verify(drag.begin(source, [source], Qt.point(150, 35), ""))
    actions.valid = false
    verify(!drag.finish(Qt.point(150, 35)))
    compare(actions.moves, 0)
    verifyClean(drag)
  }
  function test_cancelNoopAndClosedMembers() {
    var drag = makeDrag()
    verify(drag.begin(source, [source], Qt.point(150, 35), ""))
    drag.cancel("stolen grab")
    drag.cancel("duplicate")
    compare(drag.endings, 1)
    compare(actions.moves, 0)
    verifyClean(drag)
    verify(drag.begin(source, [source], Qt.point(150, 35), ""))
    actions.changes = false
    drag.updatePointer(Qt.point(150, 35))
    compare(drag.hoveredIdentity, "")
    verify(!drag.finish(Qt.point(150, 35)))
    compare(actions.moves, 0)
    actions.changes = true
    verify(drag.begin(source, [source], Qt.point(150, 35), ""))
    actions.live = false
    drag.updatePointer(Qt.point(150, 35))
    verifyClean(drag)
    compare(drag.endings, 3)
  }
  function test_transportFailureStillCleansUp() {
    var drag = makeDrag()
    verify(drag.begin(source, [source], Qt.point(150, 35), ""))
    actions.failMove = true
    var threw = false
    try { drag.finish(Qt.point(150, 35)) } catch (error) { threw = true }
    verify(threw)
    verifyClean(drag)
    compare(drag.endings, 1)
    drag.cancel("after failure")
    compare(actions.moves, 1)
  }
  function test_proxySceneMappingAndSourceDestruction() {
    var drag = makeDrag()
    var ephemeral = Qt.createQmlObject('import QtQuick; Item { width: 40; height: 40 }', testCase)
    verify(drag.begin(ephemeral, [ephemeral], Qt.point(150, 60), ""))
    var proxy = findChild(drag, "workspaceDragProxy")
    verify(proxy)
    var center = proxy.mapToItem(null, proxy.width / 2, proxy.height / 2)
    compare(center.x, 150)
    compare(center.y, 60)
    ephemeral.destroy()
    tryCompare(drag, "active", false)
    verifyClean(drag)
    compare(actions.moves, 0)
  }
  function test_stationaryPointerRetargetsAfterViewportScroll() {
    var scene = createTemporaryObject(scrollingSceneComponent, testCase)
    verify(scene)
    wait(30)
    var point = scene.layout.mapToItem(null, 150, 20)
    verify(scene.drag.begin(source, [source], point, ""))
    compare(scene.drag.hoveredIdentity, "")
    scene.layout.scrollBy(10000)
    compare(scene.drag.pointerScene, point)
    compare(scene.drag.hoveredIdentity, "id:12")
    scene.layout.scrollBy(-10000)
    compare(scene.drag.hoveredIdentity, "")
    scene.layout.scrollBy(10000)
    verify(scene.drag.finish(point))
    compare(actions.moves, 1)
    compare(actions.committed, "id:12")
    verifyClean(scene.drag)
    compare(scene.layout.windowDragActive, false)
  }
}
