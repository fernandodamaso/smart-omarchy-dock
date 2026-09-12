import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "DockWorkspaceLayout"
  when: windowShown
  visible: true
  width: 800
  height: 200

  Component {
    id: layoutComponent
    Components.DockWorkspaceLayout {
      width: 300
      height: 160
      rowY: 90
      property alias first: first
      property alias activeCard: activeCard
      property alias last: last
      Rectangle { id: first; width: 60; height: 56 }
      Rectangle { id: activeCard; width: 400; height: 56 }
      Rectangle { id: last; width: 60; height: 56 }
    }
  }

  function makeLayout(values) {
    var layout = createTemporaryObject(layoutComponent, testCase, values || {})
    verify(layout)
    wait(30)
    return layout
  }

  function test_exactFitAndFullLength() {
    var layout = makeLayout()
    layout.width = layout.desiredWidth
    compare(layout.overflowing, false)
    compare(layout.maximumOffset, 0)
    verify(layout.containsItem(layout.first))
    verify(layout.containsItem(layout.last))
    layout.width += 200
    compare(layout.maximumOffset, 0)
    compare(layout.contentX, 0)
  }

  function test_overflowMouseNavigationAndMapping() {
    var layout = makeLayout()
    verify(layout.overflowing)
    verify(layout.containsItem(layout.first))
    verify(!layout.containsItem(layout.last))
    var next = findChild(layout, "nextCards")
    verify(next)
    mouseClick(next, next.width / 2, next.height / 2)
    verify(layout.contentX > 0)
    layout.scrollBy(10000)
    compare(layout.contentX, layout.maximumOffset)
    verify(layout.containsItem(layout.last))
    var mapped = layout.mapFromItem(layout.last, 0, 0)
    verify(mapped.x >= layout.navigationWidth)
    verify(mapped.x + layout.last.width <= layout.width - layout.navigationWidth)
    compare(mapped.y, layout.rowY)
    layout.scrollBy(-10000)
    compare(layout.contentX, 0)
  }

  function test_activeHeaderAndWindowRemovalClamp() {
    var layout = makeLayout()
    layout.scrollBy(10000)
    layout.ensureVisible(layout.activeCard, 56)
    var point = layout.mapFromItem(layout.activeCard, 0, 0)
    verify(point.x >= layout.navigationWidth)
    verify(point.x + 56 <= layout.width - layout.navigationWidth)
    layout.scrollBy(10000)
    layout.activeCard.width = 56
    wait(30)
    compare(layout.overflowing, false)
    compare(layout.contentX, 0)
    layout.last.visible = false
    wait(30)
    compare(layout.contentX, 0)
  }

  function test_inactiveAppsStayReachableAfterActiveHeaderReveal() {
    var layout = makeLayout()
    layout.last.width = 240
    wait(30)
    layout.ensureVisible(layout.activeCard, 56)
    verify(layout.overflowing)
    compare(layout.last.width, 240)
    layout.scrollBy(10000)
    verify(layout.containsItem(layout.last))
    layout.ensureVisible(layout.first, 56)
    verify(layout.containsItem(layout.first))
    compare(layout.last.width, 240)
  }

  function test_smallExtentAndUtilitySpaceChanges() {
    var layout = makeLayout({ width: 12 })
    verify(layout.viewportWidth > 0)
    verify(layout.maximumOffset >= 0)
    layout.scrollBy(10000)
    compare(layout.contentX, layout.maximumOffset)
    layout.width = 100
    verify(layout.contentX <= layout.maximumOffset)
    layout.width = 800
    compare(layout.contentX, 0)
    verify(layout.containsItem(layout.last))
  }

  function test_sceneViewportAcceptsPartialCardOnly() {
    var layout = makeLayout({ x: 37, y: 11 })
    verify(!layout.containsItem(layout.activeCard), 'wide card does not fully fit')
    verify(layout.containsScenePoint(layout.activeCard.mapToItem(null, 20, 20)))
    verify(!layout.containsScenePoint(layout.activeCard.mapToItem(null, 390, 20)))
    verify(!layout.containsScenePoint(layout.mapToItem(null, -1, 20)))
    verify(!layout.containsScenePoint(layout.mapToItem(null, 100, -1)))
    verify(!layout.containsScenePoint(layout.mapToItem(null, 100, layout.height)))
    for (var name of ['previousCards', 'nextCards']) {
      var button = findChild(layout, name)
      var point = button.mapToItem(null, button.width / 2, button.height / 2)
      verify(!layout.containsScenePoint(point))
      compare(layout.navigationDirectionAt(point), name === 'previousCards' ? -1 : 1)
    }
    compare(layout.navigationDirectionAt(layout.mapToItem(null, 5, 5)), 0,
      'navigation zone is the actual button, not the full column')
    layout.width = layout.desiredWidth
    compare(layout.navigationDirectionAt(layout.mapToItem(null, 5, 100)), 0)
  }

  function test_dragDwellScrollClampAndCleanup() {
    var layout = makeLayout()
    var next = findChild(layout, 'nextCards')
    layout.dragScenePosition = next.mapToItem(null, next.width / 2, next.height / 2)
    layout.windowDragActive = true
    wait(100)
    compare(layout.contentX, 0, 'must dwell before scrolling')
    tryVerify(function() { return layout.contentX > 0 }, 700)
    var before = layout.contentX
    layout.ensureVisible(layout.first, 56)
    compare(layout.contentX, before, 'active-card reveal is paused during window dragging')
    layout.dragScenePosition = layout.mapToItem(null, 100, 100)
    before = layout.contentX
    wait(120)
    compare(layout.contentX, before, 'leaving navigation stops scrolling')
    layout.dragScenePosition = next.mapToItem(null, next.width / 2, next.height / 2)
    layout.scrollBy(10000)
    wait(320)
    compare(layout.contentX, layout.maximumOffset)
    compare(layout.dragNavigationDirection, 0, 'navigation timers stop at the boundary')
    var previous = findChild(layout, 'previousCards')
    layout.dragScenePosition = previous.mapToItem(null, previous.width / 2, previous.height / 2)
    tryVerify(function() { return layout.contentX < layout.maximumOffset }, 700)
    layout.windowDragActive = false
    before = layout.contentX
    wait(320)
    compare(layout.contentX, before, 'finish/cancel stops both timers')
    compare(layout.dragNavigationDirection, 0)
    layout.windowDragActive = true
    wait(100)
    compare(layout.contentX, before, 'a new drag gets a fresh dwell')
    layout.windowDragActive = false
  }
}
