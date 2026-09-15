import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "MonitorSectionLayout"
  when: windowShown
  visible: true
  width: 900
  height: 180

  Component {
    id: layoutComponent
    Components.DockWorkspaceLayout {
      id: layout
      width: 320
      height: 120
      rowY: 48
      contentPadding: 10
      property alias firstWrapper: firstWrapper
      property alias firstCard: firstCard
      property alias secondWrapper: secondWrapper
      property alias secondCard: secondCard
      property alias secondPrefix: secondPrefix

      Item {
        id: firstWrapper
        width: firstPrefix.width + 6 + firstSlot.width
        height: 56
        Rectangle { id: firstPrefix; width: 72; height: 56 }
        Components.DockAnimatedSlot {
          id: firstSlot
          x: firstPrefix.width + 6
          naturalWidth: 100
          naturalHeight: 56
          animationsEnabled: false
          Rectangle { id: firstCard; width: 100; height: 56 }
        }
      }

      Item {
        id: secondWrapper
        width: secondPrefix.width + (secondPrefix.visible ? 6 : 0) + secondSlot.width
        height: 56
        Rectangle {
          id: secondPrefix
          width: visible ? 84 : 0
          height: 56
          visible: true
        }
        Components.DockAnimatedSlot {
          id: secondSlot
          x: secondPrefix.width + (secondPrefix.visible ? 6 : 0)
          naturalWidth: 120
          naturalHeight: 56
          animationsEnabled: false
          Rectangle { id: secondCard; width: 120; height: 56 }
        }
      }
    }
  }

  function makeLayout() {
    var layout = createTemporaryObject(layoutComponent, testCase)
    verify(layout)
    wait(30)
    return layout
  }

  function test_prefixesStayInOneRowAndFlowIntoDesiredWidth() {
    var layout = makeLayout()
    compare(layout.firstWrapper.height, 56)
    compare(layout.secondWrapper.height, 56)
    compare(layout.firstCard.height, 56)
    compare(layout.secondCard.height, 56)
    var withPrefix = layout.desiredWidth
    layout.secondPrefix.visible = false
    wait(30)
    verify(layout.desiredWidth < withPrefix,
      'prefix width participates in the same horizontal content row')
  }

  function test_exactFitAndFractionalThresholdRemainStable() {
    var layout = makeLayout()
    layout.width = layout.desiredWidth
    compare(layout.overflowing, false)
    compare(layout.maximumOffset, 0)
    layout.width = layout.desiredWidth - 0.25
    compare(layout.overflowing, true)
    verify(layout.navigationWidth > 0)
    layout.width = layout.desiredWidth + 0.25
    compare(layout.overflowing, false)
    compare(layout.contentX, 0)
  }

  function test_revealMapsTheActualCardNotItsPrefix() {
    var layout = makeLayout()
    layout.width = 210
    verify(layout.overflowing)
    layout.scrollBy(10000)
    layout.ensureVisible(layout.firstCard, 30)
    var point = layout.mapFromItem(layout.firstCard, 0, 0)
    verify(point.x >= layout.navigationWidth,
      'header-only reveal maps from the real card inside its prefix wrapper')
    verify(point.x + 30 <= layout.width - layout.navigationWidth)
  }

  function test_animatedCardWidthControlsWrapperOccupancy() {
    var layout = makeLayout()
    var initial = layout.firstWrapper.width
    var slot = layout.firstCard.parent.parent
    slot.present = false
    slot.settle()
    wait(0)
    compare(slot.width, 0)
    verify(layout.firstWrapper.width < initial,
      'wrapper tracks the currently occupied animated card width, not natural width')
  }
}
