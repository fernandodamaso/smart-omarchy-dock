import QtQuick
import QtTest
import "../components/DockModel.js" as DockModel
import "../components/DockWindowModel.js" as DockWindowModel

TestCase {
  name: "WindowScopeComposition"

  function handle(toplevel, address, workspaceId, monitor, urgent) {
    return {
      wayland: toplevel,
      address: address,
      lastIpcObject: {
        workspace: { id: workspaceId, name: String(workspaceId) },
        monitor: monitor,
        urgent: urgent === true
      }
    }
  }

  function test_pinnedApplicationRunningElsewhereRemainsAsLauncher() {
    var remote = { appId: "demo" }
    var handles = [handle(remote, "0xa1", 2, 1, false)]
    var context = DockWindowModel.windowScopeContext(
      "workspace-monitor", { id: 1, name: "1" }, { id: 0, name: "LOCAL" }, true)
    var filtered = DockWindowModel.filterToplevelsByScope(
      [remote], handles, {}, context)
    compare(filtered.length, 0)

    var items = DockModel.buildVisibleItems(
      ["demo.desktop"], filtered,
      [{ id: "demo.desktop", startupClass: "demo" }], handles,
      true, true, [])
    compare(items.length, 1)
    compare(items[0].desktopId, "demo.desktop")
    compare(items[0].pinned, true)
    compare(items[0].toplevels.length, 0)
  }

  function test_sortByWorkspaceDoesNotChangeScopeEligibility() {
    var local = { appId: "local" }
    var remote = { appId: "remote" }
    var handles = [
      handle(local, "0xb1", 3, 0, false),
      handle(remote, "0xb2", 4, 0, false)
    ]
    var context = DockWindowModel.windowScopeContext(
      "workspace", { id: 3, name: "3" }, { id: 0, name: "LOCAL" }, false)
    var filtered = DockWindowModel.filterToplevelsByScope(
      [remote, local], handles, {}, context)
    compare(filtered.length, 1)
    compare(filtered[0], local)

    var items = DockModel.buildVisibleItems(
      [], filtered,
      [
        { id: "local.desktop", startupClass: "local" },
        { id: "remote.desktop", startupClass: "remote" }
      ], handles, true, true, [])
    compare(items.length, 1)
    compare(items[0].desktopId, "local.desktop")
    compare(items[0].toplevels[0], local)
  }
}
