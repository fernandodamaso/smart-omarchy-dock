import QtQuick
import QtTest
import "../components"

TestCase {
  id: test
  name: "HerdrWorkingIndicator"
  when: windowShown
  visible: true
  width: 100
  height: 100

  Component {
    id: indicatorFactory
    DockHerdrWorkingIndicator {}
  }

  Component {
    id: markFactory
    DockHerdrStatusMark {}
  }

  function findByName(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; ++i) {
      var hit = findByName(kids[i], name)
      if (hit) return hit
    }
    return null
  }

  function rotationDistance(a, b) {
    var delta = Math.abs(Number(a) - Number(b)) % 360
    return Math.min(delta, 360 - delta)
  }

  function test_spinner_geometry_and_arc() {
    var indicator = createTemporaryObject(indicatorFactory, test)
    verify(indicator !== null)
    compare(indicator.width, 20)
    compare(indicator.height, 20)
    compare(indicator.implicitWidth, 20)
    compare(indicator.implicitHeight, 20)
    compare(indicator.activeFocusOnTab, false)
    compare(indicator.focus, false)
    verify(indicator.arc !== null)
    compare(indicator.arc.objectName, "herdr-working-arc")
    compare(indicator.arc.strokeWidth, 3)
    var shape = findByName(indicator, "herdr-working-shape")
    verify(shape !== null)
  }

  function test_instances_share_wall_clock_rotation() {
    var indicator = createTemporaryObject(indicatorFactory, test)
    var sibling = createTemporaryObject(indicatorFactory, test)
    verify(indicator !== null)
    verify(sibling !== null)
    indicator.active = true
    sibling.active = true
    compare(indicator.animating, true)
    compare(sibling.animating, true)
    tryVerify(function() {
      return rotationDistance(indicator.rotation, sibling.rotation) < 4
        && rotationDistance(indicator.rotation, indicator.synchronizedRotation()) < 8
    }, 300)
  }

  function test_inactive_and_animations_off_are_static() {
    var indicator = createTemporaryObject(indicatorFactory, test)
    verify(indicator !== null)
    indicator.tint = "#ff3366"
    compare(indicator.arc.strokeColor, indicator.tint)
    compare(indicator.animating, false)
    compare(indicator.rotation, 0)
    wait(80)
    compare(indicator.rotation, 0)

    indicator.active = true
    compare(indicator.animating, true)
    indicator.animationsEnabled = false
    compare(indicator.animating, false)
    compare(indicator.rotation, 0)
    wait(80)
    compare(indicator.rotation, 0)
    verify(indicator.arc !== null)
  }

  function test_status_mark_states_and_reduced_motion() {
    var mark = createTemporaryObject(markFactory, test, {
      status: "blocked",
      size: 24,
      ringColor: "#123456"
    })
    verify(mark !== null)
    compare(mark.width, 24)
    compare(mark.height, 24)
    compare(mark.pulsing, true)
    verify(findByName(mark, "herdr-status-blocked-glyph").visible)
    var disc = findByName(mark, "herdr-status-disc")
    verify(disc !== null)
    compare(disc.border.width, 3)
    compare(disc.border.color, mark.ringColor)
    compare(disc.color, "#e0af68")

    mark.animationsEnabled = false
    compare(mark.pulsing, false)
    mark.status = "working"
    var spinner = findByName(mark, "herdr-status-working-spinner")
    verify(spinner !== null)
    verify(spinner.visible)
    compare(spinner.animating, false)
    verify(spinner.arc !== null)

    mark.status = "done"
    compare(disc.color, "#9ece6a")
    verify(findByName(mark, "herdr-status-done-glyph").visible)
    mark.status = "idle"
    compare(mark.visible, false)
  }
}
