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
  property var cancels: []

  Component {
    id: surfaceFactory

    DockPositionDragSurface {
      width: 300
      height: 100
      // Deterministic hint/armed assertions; the animation preference itself
      // is qualified by tst_interfaceanimations.
      animationsEnabled: false
    }
  }

  // The embedded hint pill is the only child that exposes a `shown` state.
  function feedback(surface) {
    for (var i = 0; i < surface.children.length; ++i) {
      if (surface.children[i].shown !== undefined) return surface.children[i]
    }
    return null
  }

  function makeSurface(position, requested, presentation, token) {
    events = []
    cancels = []
    var surface = createTemporaryObject(surfaceFactory, testCase, {
      dockPosition: position,
      requestedPosition: requested,
      switchThreshold: 48,
      presentationMode: presentation === undefined ? "" : presentation,
      gestureToken: token === undefined ? null : token
    })
    verify(surface !== null)
    surface.positionRequested.connect(function(nextPosition, expectedPosition, gestureToken) {
      testCase.events = testCase.events.concat([{
        position: nextPosition,
        expectedPosition: expectedPosition,
        gestureToken: gestureToken
      }])
    })
    surface.gestureCancelled.connect(function(reason) {
      testCase.cancels = testCase.cancels.concat([reason])
    })
    return surface
  }

  function drag(surface, fromX, fromY, toX, toY) {
    mouseDrag(surface, fromX, fromY, toX - fromX, toY - fromY,
      Qt.LeftButton, Qt.NoModifier, 20)
  }

  function test_bottom_drag_left_commits_once() {
    var surface = makeSurface("bottom", "bottom", "classic", "press-1")
    drag(surface, 220, 50, 150, 50)
    compare(events.length, 1)
    compare(events[0].position, "left")
    compare(events[0].expectedPosition, "bottom")
    compare(events[0].gestureToken, "press-1")
    compare(cancels.length, 0)
  }

  function test_left_drag_down_commits_once() {
    var surface = makeSurface("left", "left", "sidebar", "press-2")
    drag(surface, 150, 20, 150, 80)
    compare(events.length, 1)
    compare(events[0].position, "bottom")
    compare(events[0].expectedPosition, "left")
    compare(events[0].gestureToken, "press-2")
  }

  function test_gesture_token_is_captured_at_press() {
    var surface = makeSurface("bottom", "bottom", "classic", "press-time")
    mousePress(surface, 240, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    verify(surface.armed)
    // The host re-resolves its presentation state after the press; the commit
    // must still carry the token captured when the pointer went down so the
    // host can reject the gesture as stale instead of writing against new state.
    surface.gestureToken = "later-state"
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 1)
    compare(events[0].gestureToken, "press-time")
    compare(surface.capturedGestureToken, "later-state",
      "release re-captures the current token for the next gesture")
  }

  function test_right_edge_uses_the_same_downward_target() {
    var surface = makeSurface("right", "right", "sidebar")
    drag(surface, 150, 20, 150, 80)
    compare(events.length, 1)
    compare(events[0].position, "bottom")
    compare(surface.destinationEdge, "bottom")
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
    var surface = makeSurface("bottom", "top", undefined, "press-legacy")
    drag(surface, 220, 50, 150, 50)
    compare(events.length, 1)
    compare(events[0].position, "left")
    compare(events[0].expectedPosition, "top")
    compare(events[0].gestureToken, "press-legacy")
  }

  function test_disabled_surface_does_not_start_gesture() {
    var surface = makeSurface("bottom", "bottom")
    surface.interactionAllowed = false
    mousePress(surface, 220, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0)
    verify(!surface.pressed)
  }

  function test_a_stationary_press_changes_nothing() {
    var surface = makeSurface("bottom", "bottom", "classic")
    mousePress(surface, 150, 50, Qt.LeftButton)
    verify(surface.pressed)
    compare(surface.hintVisible, false, "no hint before the dead zone")
    compare(surface.armed, false)
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0)
    compare(surface.gestureActive, false)
    compare(feedback(surface).text, "", "the pill clears after the gesture")
  }

  function test_feedback_follows_hint_armed_and_reversal_states() {
    var surface = makeSurface("bottom", "bottom", "classic")
    var pill = feedback(surface)
    verify(pill !== null)

    mousePress(surface, 240, 50, Qt.LeftButton)
    // Past the dead zone, short of the threshold: directional hint only.
    mouseMove(surface, 225, 50, 20, Qt.LeftButton)
    compare(surface.hintVisible, true)
    compare(surface.armed, false)
    // The destination edge is fixed for the whole gesture; only `armed` gates
    // the silhouette, so an unarmed hint still names its destination edge.
    compare(surface.destinationEdge, "left")
    compare(surface.hintText, "Drag left to switch to sidebar")
    compare(pill.text, "Drag left to switch to sidebar")

    // Past the threshold: armed silhouette plus the release prompt.
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    compare(surface.armed, true)
    compare(surface.destinationEdge, "left")
    compare(surface.armedText, "Release to switch to sidebar")
    compare(pill.text, "Release to switch to sidebar")

    // Reversing below the threshold disarms and restores the hint.
    mouseMove(surface, 225, 50, 20, Qt.LeftButton)
    compare(surface.armed, false)
    compare(surface.hintVisible, true)
    compare(pill.text, "Drag left to switch to sidebar")

    // Still short of the threshold on release: no request at all.
    mouseRelease(surface, 225, 50, Qt.LeftButton)
    compare(events.length, 0)
    compare(pill.text, "", "the pill clears after the gesture")
    compare(surface.gestureActive, false)
  }

  function test_wrong_direction_movement_never_arms() {
    var surface = makeSurface("bottom", "bottom", "classic")
    mousePress(surface, 100, 50, Qt.LeftButton)
    mouseMove(surface, 250, 90, 20, Qt.LeftButton)
    compare(surface.hintVisible, true, "any movement past the dead zone hints")
    compare(surface.armed, false, "wrong-direction movement never arms")
    mouseRelease(surface, 250, 90, Qt.LeftButton)
    compare(events.length, 0)
  }

  function test_escape_cancels_without_a_request() {
    var surface = makeSurface("bottom", "bottom", "classic")
    mousePress(surface, 240, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    verify(surface.armed)
    keyClick(Qt.Key_Escape)
    compare(surface.gestureActive, false, "Escape releases the gesture state")
    compare(surface.armed, false)
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0, "Escape commits nothing")
    compare(cancels.length, 1)
    compare(cancels[0], "escape")
  }

  function test_interaction_conflict_cancels_without_a_request() {
    var surface = makeSurface("bottom", "bottom", "classic")
    mousePress(surface, 240, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    verify(surface.armed)
    // A menu, popup, row drag or resize opening mid-gesture yields ownership.
    surface.interactionAllowed = false
    compare(cancels.length, 1)
    compare(cancels[0], "interaction-conflict")
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0, "a conflicting interaction commits nothing")
    compare(surface.gestureActive, false)
  }

  function test_presentation_change_during_drag_blocks_the_commit() {
    var surface = makeSurface("bottom", "bottom", "classic")
    mousePress(surface, 240, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    verify(surface.armed)
    // Another renderer changed the mode underneath this press.
    surface.presentationMode = "sidebar"
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0, "a stale intent is never submitted")
    compare(cancels.length, 0)
  }

  function test_cancel_without_a_pressed_gesture_is_a_noop() {
    var surface = makeSurface("bottom", "bottom", "classic")
    surface.cancelGesture("escape")
    compare(cancels.length, 0, "cancelling an idle surface signals nothing")
    mousePress(surface, 240, 50, Qt.LeftButton)
    mouseMove(surface, 150, 50, 20, Qt.LeftButton)
    verify(surface.armed)
    surface.cancelGesture("first")
    surface.cancelGesture("second")
    compare(cancels.length, 1, "a cancelled gesture only reports once")
    compare(cancels[0], "first")
    mouseRelease(surface, 150, 50, Qt.LeftButton)
    compare(events.length, 0)
  }
}
