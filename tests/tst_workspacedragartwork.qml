import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "DockWorkspaceDragArtwork"
  when: windowShown
  visible: true
  width: 300
  height: 120

  property int revision: 0
  Item { id: source; width: 42; height: 42 }
  QtObject {
    id: actions
    property int moves: 0
    function captureWorkspaceMove(values) { return values.slice() }
    function workspaceMoveMembers(values) { return values }
    function resolveWorkspaceDropTarget(identity) {
      return identity === "id:12" ? { identity: identity } : null
    }
    function workspaceMoveWouldChange(values, identity) { return true }
    function moveCapturedToplevels(values, identity) { moves++; return true }
  }
  Component {
    id: artwork
    Rectangle {
      objectName: "injectedArtwork"
      property int observedRevision: testCase.revision
    }
  }
  Component {
    id: dragComponent
    Components.DockWorkspaceDrag {
      width: 300
      height: 120
      windowActions: actions
      targetAtScenePoint: function(point) { return "id:12" }
      artworkDelegate: artwork
    }
  }

  function init() { actions.moves = 0; revision = 0 }
  function makeDrag() {
    var drag = createTemporaryObject(dragComponent, testCase)
    verify(drag)
    return drag
  }
  function loaderFor(drag) {
    var loader = findChild(drag, "workspaceDragArtwork")
    verify(loader)
    return loader
  }
  function start(drag) {
    verify(drag.begin(source, [source, source], Qt.point(100, 50), ""))
    var loader = loaderFor(drag)
    tryCompare(loader, "status", Loader.Ready)
    verify(loader.item)
    compare(loader.item.objectName, "injectedArtwork")
    compare(loader.item.width, drag.iconSize)
    compare(loader.item.height, drag.iconSize)
    compare(loader.item.enabled, false)
    compare(drag.liveCount, 2)
    return loader
  }
  function test_loadOnlyDuringSessionAndRelease() {
    var drag = makeDrag()
    var loader = loaderFor(drag)
    compare(loader.active, false)
    compare(loader.item, null)
    start(drag)
    verify(drag.finish(Qt.point(100, 50)))
    compare(actions.moves, 1)
    compare(loader.active, false)
    compare(loader.item, null)
    compare(drag.sourceItem, null)
    drag.cancel("duplicate cleanup")
    compare(actions.moves, 1)
  }
  function test_liveArtworkBindingsAndRepeatedCancel() {
    var drag = makeDrag()
    var loader = start(drag)
    compare(loader.item.observedRevision, 0)
    revision = 7
    compare(loader.item.observedRevision, 7)
    drag.iconSize = 60
    compare(loader.item.width, 60)
    compare(loader.item.height, 60)
    drag.cancel("cancelled grab")
    compare(loader.item, null)
    compare(actions.moves, 0)
    start(drag)
    compare(loader.item.observedRevision, 7)
    drag.cancel("second gesture")
    compare(loader.item, null)
    compare(actions.moves, 0)
  }
  function test_invalidStartNeverCreatesArtwork() {
    var drag = makeDrag()
    verify(!drag.begin(null, [source], Qt.point(100, 50), ""))
    compare(loaderFor(drag).item, null)
    verify(!drag.begin(source, [], Qt.point(100, 50), ""))
    compare(loaderFor(drag).item, null)
    compare(actions.moves, 0)
  }
}
