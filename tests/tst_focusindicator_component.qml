import QtQuick
import QtTest
import "../components" as Components

TestCase {
  name: "DockApplicationStateIndicator"

  Component {
    id: indicatorComponent

    Components.DockApplicationStateIndicator {
      position: "bottom"
      iconWidth: 42
      iconHeight: 42
      running: false
      focused: false
      runningColor: "#778899"
      focusedColor: "#aabbcc"
    }
  }

  function test_runningUsesCompactMarker() {
    var indicator = createTemporaryObject(indicatorComponent, this, {
      running: true,
      focused: false
    })
    verify(indicator)
    // TestCase is a non-visual parent, so assert the component's geometry
    // contract rather than effective scene visibility.
    compare(indicator.indicatorGeometry.visible, true)
    compare(indicator.width, 4)
    compare(indicator.height, 4)
    compare(indicator.markerColor, indicator.runningColor)
  }

  function test_focusedUsesDistinctLongMarker() {
    var indicator = createTemporaryObject(indicatorComponent, this, {
      running: true,
      focused: true
    })
    verify(indicator)
    compare(indicator.indicatorGeometry.visible, true)
    compare(indicator.width, 12)
    compare(indicator.height, 4)
    compare(indicator.markerColor, indicator.focusedColor)
  }

  function test_positionChangeReorientsFocusedMarker() {
    var indicator = createTemporaryObject(indicatorComponent, this, {
      running: true,
      focused: true,
      position: "left"
    })
    verify(indicator)
    compare(indicator.x, 44)
    compare(indicator.y, 15)
    compare(indicator.width, 4)
    compare(indicator.height, 12)

    indicator.position = "right"
    compare(indicator.x, -6)
    compare(indicator.y, 15)
    compare(indicator.width, 4)
    compare(indicator.height, 12)
  }

  function test_notRunningHidesMarker() {
    var indicator = createTemporaryObject(indicatorComponent, this)
    verify(indicator)
    compare(indicator.visible, false)
  }
}
