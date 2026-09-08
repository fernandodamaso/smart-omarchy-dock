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
}
