import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel

TestCase {
  name: "RestoreWorkspaceTargets"

  function test_acceptsNamedWorkspaceWithSpaces() {
    compare(
      DockModel.normalizeWorkspaceTarget("name:Design work"),
      "name:Design work")
    compare(
      DockModel.restoreWindowRequest("0xabc123", "name:Design work", false),
      "movetoworkspace name:Design work,address:0xabc123")
    compare(
      DockModel.restoreWindowRequest("0xabc123", "name:Design work", true),
      'hl.dsp.window.move({ window = "address:0xabc123", workspace = "name:Design work", follow = true })')
  }

  function test_rejectsUnsafeNamedWorkspaceTargets() {
    compare(
      DockModel.normalizeWorkspaceTarget("name:Design work,closewindow"), "")
    compare(
      DockModel.normalizeWorkspaceTarget('name:Design "work"'), "")
    compare(
      DockModel.normalizeWorkspaceTarget("name:Design\nwork"), "")
  }
}
