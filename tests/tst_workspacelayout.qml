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

  function test_activeHeaderAndCollapseClamp() {
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

  function test_smallExtentAndUtilitySpaceChanges() {
    var layout = makeLayout({ width: 12 })
    verify(layout.viewportWidth > 0)
    verify(layout.maximumOffset >= 0)
    layout.scrollBy(10000)
    compare(layout.contentX, layout.maximumOffset)
    // Hiding the host's fixed Trash returns width to this same viewport.
    layout.width = 100
    verify(layout.contentX <= layout.maximumOffset)
    layout.width = 800
    compare(layout.contentX, 0)
    verify(layout.containsItem(layout.last))
  }
}
