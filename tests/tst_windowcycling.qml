import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel
import "../components/DockWindowModel.js" as DockWindowModel

TestCase {
  name: "WindowCycling"

  function test_wrapsForwardAndBackwardFromActiveMember() {
    compare(DockWindowModel.cycleTargetIndex(3, 2, 1), 0)
    compare(DockWindowModel.cycleTargetIndex(3, 0, -1), 2)
    compare(DockWindowModel.cycleTargetIndex(3, 1, 1), 2)
    compare(DockWindowModel.cycleTargetIndex(3, 1, -1), 0)
  }

  function test_usesActualActiveMemberAsCycleOrigin() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var third = { title: "Third" }
    var group = [first, second, third]

    compare(DockWindowModel.cycleGroupMember(group, second, group, 1), third)
    compare(DockWindowModel.cycleGroupMember(group, second, group, -1), first)
  }

  function test_rejectsEmptyAndSingleMemberGroups() {
    var only = { title: "Only" }

    compare(DockWindowModel.cycleTargetIndex(0, -1, 1), -1)
    compare(DockWindowModel.cycleTargetIndex(1, 0, 1), -1)
    compare(DockWindowModel.cycleGroupMember([], null, [], 1), null)
    compare(DockWindowModel.cycleGroupMember([only], only, [only], -1), null)
  }

  function test_recoversFromStaleOriginIndices() {
    compare(DockWindowModel.cycleTargetIndex(3, 99, 1), 0)
    compare(DockWindowModel.cycleTargetIndex(3, -2, -1), 2)
    compare(DockWindowModel.cycleTargetIndex(3, 1, 0), -1)
  }

  function test_filtersStaleMembersBeforeChoosingCycleTarget() {
    var first = { title: "First" }
    var stale = { title: "Stale" }
    var third = { title: "Third" }

    compare(DockWindowModel.cycleGroupMember(
      [first, stale, third], first, [first, third], 1), third)
    compare(DockWindowModel.cycleGroupMember(
      [first, stale, third], third, [first, third], 1), first)
  }

  function test_acceptsOnlyDominantVerticalWheelDirection() {
    compare(DockWindowModel.dominantVerticalWheelDelta(20, 80), 80)
    compare(DockWindowModel.dominantVerticalWheelDelta(-20, -80), -80)
    compare(DockWindowModel.dominantVerticalWheelDelta(80, 20), 0)
    compare(DockWindowModel.dominantVerticalWheelDelta(-80, -20), 0)
    compare(DockWindowModel.dominantVerticalWheelDelta(40, 40), 0)
    compare(DockWindowModel.dominantVerticalWheelDelta(NaN, 60), 60)
  }

  function test_accumulatesHighResolutionVerticalDeltas() {
    var state = { remainder: 0 }
    for (var i = 0; i < 3; ++i) {
      state = DockModel.accumulateWheelSteps(state.remainder, 0, 30)
      compare(state.steps, 0)
    }

    state = DockModel.accumulateWheelSteps(state.remainder, 0, 30)
    compare(state.steps, 1)
    compare(state.remainder, 0)

    var negative = DockModel.accumulateWheelSteps(0, 0, -35)
    negative = DockModel.accumulateWheelSteps(negative.remainder, 0, -85)
    compare(negative.steps, -1)
    compare(negative.remainder, 0)
  }

  function test_resetsResidualOnlyAfterAbout220Milliseconds() {
    compare(DockWindowModel.wheelRemainderForTimestamp(60, 1000, 1220), 60)
    compare(DockWindowModel.wheelRemainderForTimestamp(60, 1000, 1221), 0)
    compare(DockWindowModel.wheelRemainderForTimestamp(60, 0, 1000), 0)
    compare(DockWindowModel.wheelRemainderForTimestamp(60, 1200, 1100), 0)

    var carried = DockWindowModel.wheelRemainderForTimestamp(60, 1000, 1220)
    var completed = DockModel.accumulateWheelSteps(carried, 0, 60)
    compare(completed.steps, 1)
    compare(completed.remainder, 0)

    var reset = DockWindowModel.wheelRemainderForTimestamp(60, 1000, 1221)
    var fresh = DockModel.accumulateWheelSteps(reset, 0, 60)
    compare(fresh.steps, 0)
    compare(fresh.remainder, 60)
  }
}
