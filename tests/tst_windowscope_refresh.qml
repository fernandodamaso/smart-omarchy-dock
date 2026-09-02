import QtQuick
import QtTest
import "../components/DockWindowModel.js" as DockWindowModel

TestCase {
  name: "WindowScopeRefresh"

  function test_preservesAlreadyNormalizedWorkspaceIdentity() {
    compare(DockWindowModel.workspaceIdentity("id:2"), "id:2")
  }

  function test_fullscreenUsesTheSharedHostRefreshPath() {
    compare(DockWindowModel.shouldRefreshWindowScope("fullscreen"), true)
  }
}
