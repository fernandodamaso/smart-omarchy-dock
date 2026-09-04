import QtQuick
import QtTest
import "../components/DockTrashModel.js" as TrashModel

TestCase {
  name: "ShowTrash"

  function test_defaultsToShowingTrash() {
    compare(TrashModel.normalizeShowTrash(undefined), true)
    compare(TrashModel.normalizeShowTrash("false"), true)
  }

  function test_normalizesShowTrashAsBoolean() {
    compare(TrashModel.normalizeShowTrash(true), true)
    compare(TrashModel.normalizeShowTrash(false), false)
  }

  function test_removesTrashSectionExtentWhenHidden() {
    compare(TrashModel.sectionMainExtent(true, 56, 12), 68)
    compare(TrashModel.sectionMainExtent(false, 56, 12), 0)
    compare(TrashModel.sectionMainExtent(true, -10, 12), 12)
  }

  function test_refreshesTrashOnlyWhenVisibleAndIdle() {
    compare(TrashModel.shouldRefresh(true, false), true)
    compare(TrashModel.shouldRefresh(false, false), false)
    compare(TrashModel.shouldRefresh(true, true), false)
  }
}
