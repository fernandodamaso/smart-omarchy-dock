import QtQuick
import QtTest
import "../components"
import "../components/DockModel.js" as DockModel

// Real ownership fixture for the background mode-drag layer: the production
// gesture surface in the production stacking order, so every assertion is about
// who actually receives the press rather than about a synthetic overlay.
//
//   panel-level surface   (bottom: header, list and footer sit above it)
//   header / ListView / footer
//   blank-tail surface    (top, geometry = the list's blankRegion)
//
// The list owns its delegates; the blank-tail surface owns only the part of the
// viewport no delegate covers; the panel surface owns the padding no foreground
// item reaches. Nothing declines a press, so hover eligibility and press
// ownership can never disagree.
TestCase {
  id: testCase

  name: "PressFallThrough"
  when: windowShown
  visible: true
  width: 400
  height: 400

  property var events: []
  property var cancels: []
  property int rowClicks: 0
  property int chromeClicks: 0
  property var rows: ["a", "b"]

  // Same helper the sidebar panel binds, so the fixture can never drift from
  // the geometry it is qualifying.
  readonly property var region: DockModel.sidebarBlankRegion(
    list.contentHeight, list.height, list.contentY, list.width)

  Item {
    id: stack

    anchors.fill: parent

    // Bottom of the stack: the panel-level background surface.
    DockPositionDragSurface {
      id: panelSurface

      anchors.fill: parent
      switchThreshold: 48
      presentationMode: "sidebar"
      animationsEnabled: false
      onPositionRequested: (position, expectedPosition, expectedPresentation) =>
        testCase.events.push({ source: "panel", position: position,
          expectedPresentation: expectedPresentation })
      onGestureCancelled: reason => testCase.cancels.push({ source: "panel", reason: reason })
    }

    Rectangle {
      id: header

      x: 0
      y: 0
      width: stack.width
      height: 40
      color: "#cccccc"

      MouseArea {
        anchors.fill: parent
        onClicked: testCase.chromeClicks++
      }
    }

    ListView {
      id: list

      x: 0
      y: header.height
      width: stack.width
      height: 200
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: testCase.rows
      delegate: Rectangle {
        width: list.width
        height: 60
        color: "#eeeeee"

        // The whole delegate, including its empty interior, is the row's target.
        MouseArea {
          anchors.fill: parent
          onClicked: testCase.rowClicks++
        }
      }
    }

    Rectangle {
      id: footer

      x: 0
      y: list.y + list.height
      width: stack.width
      height: 60
      color: "#cccccc"

      MouseArea {
        anchors.fill: parent
        onClicked: testCase.chromeClicks++
      }
    }

    // Above the list, covering exactly the pixels no delegate owns.
    DockPositionDragSurface {
      id: tailSurface

      x: list.x + region.x
      y: list.y + region.y
      width: region.width
      height: region.height
      visible: width > 0 && height > 0
      switchThreshold: 48
      presentationMode: "sidebar"
      animationsEnabled: false
      onPositionRequested: (position, expectedPosition, expectedPresentation) =>
        testCase.events.push({ source: "tail", position: position,
          expectedPresentation: expectedPresentation })
      onGestureCancelled: reason => testCase.cancels.push({ source: "tail", reason: reason })
    }
  }

  // The list relayouts its contentHeight asynchronously after a model change.
  function settleRows(count) {
    var values = []
    for (var i = 0; i < count; ++i) values.push("row-" + i)
    rows = values
    wait(60)
    list.contentY = 0
  }

  function reset() {
    events = []
    cancels = []
    rowClicks = 0
    chromeClicks = 0
    panelSurface.dockPosition = "left"
    panelSurface.requestedPosition = "left"
    panelSurface.presentationMode = "sidebar"
    tailSurface.dockPosition = "left"
    tailSurface.requestedPosition = "left"
    tailSurface.presentationMode = "sidebar"
    settleRows(2)
    verify(!panelSurface.pressed)
    verify(!tailSurface.pressed)
    compare(list.contentY, 0)
  }

  function test_blank_tail_starts_the_gesture_and_nothing_else_moves() {
    reset()
    compare(region.height, 80, "short content leaves a blank tail")
    verify(tailSurface.visible)
    mousePress(tailSurface, 200, 40, Qt.LeftButton)
    verify(tailSurface.pressed, "the blank tail captures the press")
    verify(!panelSurface.pressed, "the panel surface stays below the list")
    mouseMove(tailSurface, 200, 120, 20, Qt.LeftButton)
    mouseRelease(tailSurface, 200, 120, Qt.LeftButton)
    compare(events.length, 1, "one request per completed gesture")
    compare(events[0].source, "tail")
    compare(events[0].position, "bottom")
    compare(events[0].expectedPresentation, "sidebar")
    compare(rowClicks, 0)
    compare(chromeClicks, 0)
    compare(list.contentY, 0, "the mode gesture never scrolled the list")
    verify(!tailSurface.pressed)
  }

  function test_sub_threshold_blank_tail_drag_does_not_switch() {
    reset()
    mousePress(tailSurface, 200, 20, Qt.LeftButton)
    verify(tailSurface.pressed)
    mouseMove(tailSurface, 200, 45, 20, Qt.LeftButton)
    mouseRelease(tailSurface, 200, 45, Qt.LeftButton)
    compare(events.length, 0, "movement below the threshold is a plain release")
    compare(cancels.length, 0)
    compare(rowClicks, 0)
    compare(list.contentY, 0)
  }

  function test_row_interior_belongs_to_the_row() {
    reset()
    mouseClick(list, 200, 30, Qt.LeftButton)
    compare(rowClicks, 1, "the delegate keeps its whole interior")
    verify(!tailSurface.pressed)
    verify(!panelSurface.pressed)
    compare(events.length, 0)
  }

  function test_header_and_footer_keep_their_input() {
    reset()
    mouseClick(header, 200, 20, Qt.LeftButton)
    mouseClick(footer, 200, 30, Qt.LeftButton)
    compare(chromeClicks, 2)
    verify(!panelSurface.pressed)
    verify(!tailSurface.pressed)
    compare(events.length, 0)
  }

  function test_padding_below_the_footer_starts_a_panel_gesture() {
    reset()
    compare(region.height, 80)
    mousePress(panelSurface, 300, 310, Qt.LeftButton)
    verify(panelSurface.pressed, "empty padding belongs to the panel surface")
    verify(!tailSurface.pressed)
    mouseMove(panelSurface, 300, 390, 20, Qt.LeftButton)
    mouseRelease(panelSurface, 300, 390, Qt.LeftButton)
    compare(events.length, 1)
    compare(events[0].source, "panel")
    compare(events[0].position, "bottom")
    compare(events[0].expectedPresentation, "sidebar")
    compare(rowClicks, 0)
    compare(chromeClicks, 0)
  }

  function test_classic_dock_orientation_background_switches_left() {
    reset()
    panelSurface.dockPosition = "bottom"
    panelSurface.requestedPosition = "bottom"
    panelSurface.presentationMode = "classic"
    mousePress(panelSurface, 300, 310, Qt.LeftButton)
    verify(panelSurface.pressed)
    mouseMove(panelSurface, 200, 310, 20, Qt.LeftButton)
    mouseRelease(panelSurface, 200, 310, Qt.LeftButton)
    compare(events.length, 1)
    compare(events[0].position, "left")
    compare(events[0].expectedPresentation, "classic")
  }

  function test_overflowing_content_leaves_no_blank_tail() {
    reset()
    settleRows(5)
    verify(list.contentHeight > list.height, "the list now overflows its viewport")
    compare(region.height, 0, "an overflowing list has no blank region")
    verify(!tailSurface.visible, "the tail surface removes itself")
    // The very point that was blank tail is now a delegate's pixel.
    mouseClick(list, 200, 160, Qt.LeftButton)
    compare(rowClicks, 1, "the row owns the point once content covers it")
    verify(!tailSurface.pressed)
    verify(!panelSurface.pressed)
    compare(events.length, 0)
  }

  function test_scrolling_still_works_with_the_gesture_layer_present() {
    reset()
    settleRows(5)
    verify(list.contentHeight > list.height)
    mouseDrag(list, 200, 150, 0, -80, Qt.LeftButton, Qt.NoModifier, 20)
    verify(list.contentY > 0, "the list still flicks")
    compare(events.length, 0, "a row flick is never a mode gesture")
    compare(rowClicks, 0)
  }

  function test_wheel_over_the_blank_tail_never_presses_anything() {
    reset()
    compare(region.height, 80)
    mouseWheel(tailSurface, 200, 40, 0, -120)
    compare(events.length, 0)
    compare(cancels.length, 0)
    verify(!tailSurface.pressed)
    verify(!panelSurface.pressed)
    compare(list.contentY, 0)
  }
}
