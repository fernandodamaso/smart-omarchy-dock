import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel
import "../components/DockWindowModel.js" as DockWindowModel

TestCase {
  name: "DockWindowCycling"

  function hasFunction(object, name) {
    var available = object && typeof object[name] === "function"
    verify(available, name + " must be implemented")
    return available
  }

  function test_definesScrollActionWithoutChangingClickVocabulary() {
    compare(DockModel.settingsDefaults().scrollAction, "none")
    compare(DockModel.normalizeSetting("scrollAction", "cycle-windows"),
      "cycle-windows")
    compare(DockModel.normalizeSetting("scrollAction", "close"), "none")
    compare(DockModel.normalizeSetting("scrollAction", "bogus"), "none")

    var actions = DockModel.normalizeApplicationActionConfig({
      clickAction: "focus-or-launch",
      middleClickAction: "close",
      scrollAction: "cycle-windows"
    })
    compare(actions.clickAction, "focus-or-launch")
    compare(actions.middleClickAction, "close")
    compare(actions.scrollAction, "cycle-windows")

    compare(DockModel.resolveApplicationPointerAction(
      actions, "scroll", {}), "cycle-windows")
    compare(DockModel.resolveApplicationPointerAction(
      actions, "scroll", { shift: true }), "none")
    compare(DockModel.resolveApplicationPointerAction(
      actions, "scroll", { control: true }), "none")

    compare(DockModel.applicationActionCanRun("cycle-windows", 1), false)
    compare(DockModel.applicationActionCanRun("cycle-windows", 2), true)

    compare(DockModel.applicationActionValues().indexOf("cycle-windows"), -1)
  }

  function test_wrapsForwardAndBackwardFromTheActiveMember() {
    if (!hasFunction(DockWindowModel, "cycleTargetIndex")) return

    compare(DockWindowModel.cycleTargetIndex(3, 0, 1), 1)
    compare(DockWindowModel.cycleTargetIndex(3, 2, 1), 0)
    compare(DockWindowModel.cycleTargetIndex(3, 0, -1), 2)
    compare(DockWindowModel.cycleTargetIndex(3, 2, -1), 1)
    compare(DockWindowModel.cycleTargetIndex(3, -1, 1), 0)
    compare(DockWindowModel.cycleTargetIndex(3, -1, -1), 2)
    compare(DockWindowModel.cycleTargetIndex(1, 0, 1), -1)
    compare(DockWindowModel.cycleTargetIndex(3, 0, 0), -1)
  }

  function test_filtersStaleMembersBeforeSelectingCycleTarget() {
    if (!hasFunction(DockWindowModel, "cycleGroupMember")) return

    var first = { title: "First" }
    var second = { title: "Second" }
    var third = { title: "Third" }
    var stale = { title: "Stale" }
    var live = [first, second, third]

    compare(DockWindowModel.cycleGroupMember(
      [first, stale, second, third], second, live, 1), third)
    compare(DockWindowModel.cycleGroupMember(
      [first, stale, second, third], second, live, -1), first)
    compare(DockWindowModel.cycleGroupMember(
      [stale, first, second], stale, [first, second], 1), first)
    compare(DockWindowModel.cycleGroupMember(
      [first], first, [first], 1), null)
  }

  function test_acceptsOnlyDominantVerticalWheelInput() {
    if (!hasFunction(DockWindowModel, "dominantVerticalWheelDelta")) return

    compare(DockWindowModel.dominantVerticalWheelDelta(0, 120), 120)
    compare(DockWindowModel.dominantVerticalWheelDelta(20, -80), -80)
    compare(DockWindowModel.dominantVerticalWheelDelta(120, 20), 0)
    compare(DockWindowModel.dominantVerticalWheelDelta(40, -40), 0)
    compare(DockWindowModel.dominantVerticalWheelDelta(40, 0), 0)
  }

  function test_accumulatesHighResolutionWheelSteps() {
    if (!hasFunction(DockWindowModel, "accumulateWheelSteps")) return
    if (!hasFunction(DockWindowModel, "wheelStepDirection")) return

    var partial = DockWindowModel.accumulateWheelSteps(0, 60, 120)
    compare(partial.steps, 0)
    compare(partial.remainder, 60)

    var completed = DockWindowModel.accumulateWheelSteps(
      partial.remainder, 60, 120)
    compare(completed.steps, 1)
    compare(completed.remainder, 0)

    var backwards = DockWindowModel.accumulateWheelSteps(0, -250, 120)
    compare(backwards.steps, -2)
    compare(backwards.remainder, -10)

    compare(DockWindowModel.wheelStepDirection(2), 1)
    compare(DockWindowModel.wheelStepDirection(-2), -1)
    compare(DockWindowModel.wheelStepDirection(0), 0)
  }

  function test_resetsResidualAfterIdleGapOrBackwardsClock() {
    if (!hasFunction(DockWindowModel, "wheelRemainderForTimestamp")) return

    compare(DockWindowModel.wheelRemainderForTimestamp(
      60, 1000, 1100, 220), 60)
    compare(DockWindowModel.wheelRemainderForTimestamp(
      60, 1000, 1220, 220), 60)
    compare(DockWindowModel.wheelRemainderForTimestamp(
      60, 1000, 1221, 220), 0)
    compare(DockWindowModel.wheelRemainderForTimestamp(
      60, 1000, 999, 220), 0)
  }
}
