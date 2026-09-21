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

  function test_geometry_and_fixed_dot_grid() {
    var indicator = createTemporaryObject(indicatorFactory, test)
    verify(indicator !== null)
    compare(indicator.width, 10)
    compare(indicator.height, 10)
    compare(indicator.implicitWidth, 10)
    compare(indicator.implicitHeight, 10)
    compare(indicator.activeFocusOnTab, false)
    compare(indicator.focus, false)

    var positions = [
      [0, 0], [4, 0], [8, 0], [8, 4],
      [8, 8], [4, 8], [0, 8], [0, 4]
    ]
    for (var i = 0; i < positions.length; ++i) {
      var dot = findByName(indicator, "herdr-working-dot-" + String(i))
      verify(dot !== null)
      compare(dot.x, positions[i][0])
      compare(dot.y, positions[i][1])
      compare(dot.width, 2)
      compare(dot.height, 2)
      compare(dot.radius, 1)
    }
  }

  function test_all_eight_phases_have_exact_three_step_trail() {
    var indicator = createTemporaryObject(indicatorFactory, test)
    verify(indicator !== null)

    for (var phase = 0; phase < 8; ++phase) {
      indicator.phase = phase
      compare(indicator.trailOpacity(phase), 1.0)
      compare(indicator.trailOpacity((phase + 7) % 8), 0.65)
      compare(indicator.trailOpacity((phase + 6) % 8), 0.30)
      for (var distance = 3; distance < 8; ++distance)
        compare(indicator.trailOpacity((phase - distance + 8) % 8), 0.0)
    }
  }

  function test_phase_wrap_stop_reset_restart_and_tint() {
    var indicator = createTemporaryObject(indicatorFactory, test)
    verify(indicator !== null)
    compare(indicator.timerRunning, false)
    compare(indicator.phase, 0)

    indicator.tint = "#ff3366"
    var firstDot = findByName(indicator, "herdr-working-dot-0")
    verify(firstDot !== null)
    compare(firstDot.color, indicator.tint)

    // Start from the last phase so the next 110ms tick proves wrap to zero.
    indicator.phase = 7
    indicator.active = true
    compare(indicator.timerRunning, true)
    tryCompare(indicator, "phase", 0, 300)

    tryVerify(function() { return indicator.phase !== 0 }, 300)
    indicator.active = false
    compare(indicator.timerRunning, false)
    compare(indicator.phase, 0)
    for (var i = 0; i < 8; ++i) {
      var dot = findByName(indicator, "herdr-working-dot-" + String(i))
      compare(dot.opacity, 0)
      compare(dot.visible, false)
    }

    indicator.active = true
    compare(indicator.timerRunning, true)
    tryVerify(function() { return indicator.phase !== 0 }, 300)
  }
}
