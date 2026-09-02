import QtQuick
import QtTest
import "../components/DockWindowModel.js" as DockWindowModel

TestCase {
  name: "DockWindowActionsModel"

  function test_filtersGroupMembersAgainstLiveToplevels() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var stale = { title: "Stale" }

    var members = DockWindowModel.liveGroupMembers(
      [first, null, stale, second], [first, second])

    compare(members.length, 2)
    compare(members[0], first)
    compare(members[1], second)
  }

  function test_resolvesActiveGroupMemberFromActualActiveToplevel() {
    var first = { title: "First" }
    var second = { title: "Second" }

    compare(
      DockWindowModel.activeGroupMember([first, second], second, [first, second]),
      second)
  }

  function test_fallsBackToFirstLiveGroupMember() {
    var first = { title: "First" }
    var second = { title: "Second" }
    var stale = { title: "Stale" }

    compare(
      DockWindowModel.activeGroupMember(
        [stale, first, second], stale, [first, second]),
      first)
    compare(
      DockWindowModel.activeGroupMember([stale], stale, [first, second]), null)
    compare(DockWindowModel.activeGroupMember([], null, [first, second]), null)
    compare(DockWindowModel.activeGroupMember(null, null, null), null)
  }
}
