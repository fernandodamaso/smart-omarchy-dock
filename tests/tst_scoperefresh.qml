import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "DockScopeRefresh"

  QtObject {
    id: toplevelModel
    property var values: []
  }

  QtObject {
    id: monitorModel
    property var values: []
  }

  QtObject {
    id: workspaceModel
    property var values: []
  }

  QtObject {
    id: refreshSource
    property var toplevel: null
    property int refreshCalls: 0

    function refreshMonitors() { refreshCalls++ }
    function refreshWorkspaces() { refreshCalls++ }
    function refreshToplevels() {
      refreshCalls++
      Qt.callLater(function() {
        if (toplevel) toplevel.workspace = ({ id: 2, name: "2" })
      })
    }
  }

  Component {
    id: toplevelComponent

    QtObject {
      property var workspace: ({ id: 1, name: "1" })
      property var monitor: ({ id: 0, name: "MON-0" })
      property var waylandHandle: null
      property var lastIpcObject: ({})
      readonly property int workspaceId: workspace.id
    }
  }

  Components.DockScopeRefreshController {
    id: controller
    toplevelModel: toplevelModel
    monitorModel: monitorModel
    workspaceModel: workspaceModel
    refreshSource: refreshSource
  }

  function test_existingWindowUpdatesAfterAsyncRefreshWithoutMembershipChange() {
    var handle = createTemporaryObject(toplevelComponent, testCase)
    toplevelModel.values = [handle]
    refreshSource.toplevel = handle
    wait(20)

    var before = controller.revision
    controller.requestRefresh()
    controller.requestRefresh()

    tryCompare(refreshSource, "refreshCalls", 3, 500)
    tryCompare(handle, "workspaceId", 2, 500)
    tryCompare(controller, "revision", before + 1, 500)
    wait(120)
    compare(refreshSource.refreshCalls, 3)
    compare(controller.revision, before + 1)
    compare(toplevelModel.values.length, 1)
  }

  function test_lateMappingAndRemovalDropPerObjectSubscription() {
    var handle = createTemporaryObject(toplevelComponent, testCase)
    toplevelModel.values = [handle]
    wait(20)

    var beforeMapping = controller.revision
    handle.waylandHandle = ({ appId: "demo" })
    tryCompare(controller, "revision", beforeMapping + 1, 500)

    var beforeIpcUpdate = controller.revision
    handle.lastIpcObject = ({ workspace: ({ id: 2, name: "2" }) })
    tryCompare(controller, "revision", beforeIpcUpdate + 1, 500)

    var beforeRemoval = controller.revision
    toplevelModel.values = []
    tryCompare(controller, "revision", beforeRemoval + 1, 500)

    var afterRemoval = controller.revision
    handle.workspace = ({ id: 3, name: "3" })
    wait(40)
    compare(controller.revision, afterRemoval)
  }
}
