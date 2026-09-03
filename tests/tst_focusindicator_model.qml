import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel

TestCase {
  name: "DockFocusIndicatorModel"

  function test_detectsActiveMemberByToplevelIdentity() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var values = [first, second]

    verify(DockModel.hasActiveMember(values, second))
    verify(DockModel.hasActiveMember({ values: values }, first))
    verify(!DockModel.hasActiveMember(values, { title: "Second" }))
    verify(!DockModel.hasActiveMember(values, null))
    verify(!DockModel.hasActiveMember(null, second))

    compare(values.length, 2)
    compare(values[0], first)
    compare(values[1], second)
  }

  function test_buildsPositionAwareRunningAndFocusedGeometry() {
    var topRunning = DockModel.applicationStateIndicatorGeometry(
      "top", 42, 42, true, false)
    compare(topRunning.visible, true)
    compare(topRunning.x, 19)
    compare(topRunning.y, -6)
    compare(topRunning.width, 4)
    compare(topRunning.height, 4)

    var topFocused = DockModel.applicationStateIndicatorGeometry(
      "top", 42, 42, true, true)
    compare(topFocused.x, 15)
    compare(topFocused.y, -6)
    compare(topFocused.width, 12)
    compare(topFocused.height, 4)

    var bottomFocused = DockModel.applicationStateIndicatorGeometry(
      "bottom", 42, 42, true, true)
    compare(bottomFocused.x, 15)
    compare(bottomFocused.y, 44)
    compare(bottomFocused.width, 12)
    compare(bottomFocused.height, 4)

    var leftFocused = DockModel.applicationStateIndicatorGeometry(
      "left", 42, 42, true, true)
    compare(leftFocused.x, 44)
    compare(leftFocused.y, 15)
    compare(leftFocused.width, 4)
    compare(leftFocused.height, 12)

    var rightFocused = DockModel.applicationStateIndicatorGeometry(
      "right", 42, 42, true, true)
    compare(rightFocused.x, -6)
    compare(rightFocused.y, 15)
    compare(rightFocused.width, 4)
    compare(rightFocused.height, 12)
  }

  function test_hidesMarkerWhenApplicationIsNotRunning() {
    var geometry = DockModel.applicationStateIndicatorGeometry(
      "bottom", 42, 42, false, false)
    compare(geometry.visible, false)
    compare(geometry.width, 4)
    compare(geometry.height, 4)
  }

  function test_scalesFocusedMarkerWithinBoundedIconAwareRange() {
    var small = DockModel.applicationStateIndicatorGeometry(
      "bottom", 24, 24, true, true)
    compare(small.width, 10)
    compare(small.height, 3)

    var large = DockModel.applicationStateIndicatorGeometry(
      "bottom", 96, 96, true, true)
    compare(large.width, 18)
    compare(large.height, 5)
  }
}
