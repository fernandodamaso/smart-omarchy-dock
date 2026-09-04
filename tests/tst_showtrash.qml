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

  function test_removesTrashSeparatorsAndGapWhenHidden() {
    compare(TrashModel.trailingMainExtent(false, 56, 12, 70), 70)
    compare(TrashModel.trailingMainExtent(true, 56, 12, 70), 150)
  }

  function test_refreshesTrashOnlyWhenVisibleAndIdle() {
    compare(TrashModel.shouldRefresh(true, false), true)
    compare(TrashModel.shouldRefresh(false, false), false)
    compare(TrashModel.shouldRefresh(true, true), false)
  }

  function test_dismissesOpenMenuWhenTrashBecomesHidden() {
    compare(TrashModel.shouldDismissMenu(false, true), true)
    compare(TrashModel.shouldDismissMenu(false, false), false)
    compare(TrashModel.shouldDismissMenu(true, true), false)
    compare(TrashModel.shouldDismissMenu(undefined, true), false)
  }
}
