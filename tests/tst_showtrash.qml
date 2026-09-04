import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel

TestCase {
  name: "ShowTrash"

  function test_defaultsToShowingTrash() {
    compare(DockModel.settingsDefaults().showTrash, true)
  }

  function test_normalizesShowTrashAsBoolean() {
    compare(DockModel.normalizeSetting("showTrash", true), true)
    compare(DockModel.normalizeSetting("showTrash", false), false)
    compare(DockModel.normalizeSetting("showTrash", undefined), true)
    compare(DockModel.normalizeSetting("showTrash", "false"), true)
  }

  function test_removesTrashSectionExtentWhenHidden() {
    compare(DockModel.trashSectionMainExtent(true, 56), 68)
    compare(DockModel.trashSectionMainExtent(false, 56), 0)
    compare(DockModel.trashSectionMainExtent(true, -10), 12)
  }
}
