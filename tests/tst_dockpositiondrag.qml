import QtQuick
import QtTest
import "../components"

TestCase {
  id: testCase

  name: "DockPositionDrag"
  when: windowShown
  visible: true
  width: 420
  height: 220

  property var events: []

  Component {
    id: surfaceFactory
    DockPositionDragSurface {
      width: 300
      height: 100
    }
  }

  function makeSurface(position, requested) {
    events = []
    var surface = createTemporaryObject(surfaceFactory, testCase, {
      dockPosition: position,
      requestedPosition: requested,
      switchThreshold: 48
    })
    verify(surface !== null)
    surface.positionRequested.connect(function(nextPosition, expectedPosition) {
      testCase.events = testCase.events.concat([{
        position: nextPosition,
        expectedPosition: expectedPosition
      }])
    })
    return surface
  }

  function drag(surface, fromX, fromY, toX, toY) {
    mouseDrag(surface, fromX, fromY, toX - fromX, toY - fromY,
      Qt.LeftButton, Qt.NoModifier, 20)
  }

  function test_bottom_drag_left_commits_once() {
    var surface = makeSurface("bottom", "bottom")
    drag(surface, 220, 50, 150, 50)
    compare(events.length, 1)
    compare(events[0].position, "left")
    compare(events[0].expectedPosition, "bottom")
  }

  function test_left_drag_down_commits_once() {
    var surface = makeSurface("left", "left")
    drag(surface, 150, 20, 150, 80)
    compare(events.length, 1)
    compare(events[0].position, "bottom")
    compare(events[0].expectedPosition, "left")
  }

  function test_short_or_wrong_direction_drag_is_noop() {
    var surface = makeSurface("bottom", "bottom")
    drag(surface, 200, 50, 170, 50)
    compare(events.length, 0)
    drag(surface, 200, 50, 250, 80)
    compare(events.length, 0)

    surface.destroy()
    surface = makeSurface("left", "left")
    drag(surface, 150, 70, 120, 20)
    compare(events.length, 0)
  }

  function test_legacy_requested_value_is_preserved_as_stale_token() {
    var surface = makeSurface("bottom", "top")
    drag(surface, 220, 50, 150, 50)
    compare(events.length, 1)
    compare(events[0].position, "left")
    compare(events[0].expectedPosition, "top")
  }

  function test_disabled_surface_does_not_start_gesture() {
    var surface = makeSurface("bottom", "bottom")
    surface.interactionAllowed = false
    mousePress(surface, 220, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0)
  }
}
