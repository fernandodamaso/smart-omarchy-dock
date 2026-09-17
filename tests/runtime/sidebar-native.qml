import QtQuick
import Quickshell
import "." as Plugin

// Live-data observer, NOT a simulated pass. One real host in a disposable guest.
// No injected windows, replaced dispatchers or copied renderer. Titles are omitted.
ShellRoot {
  id: root
  property var host: null
  property var hooks: []
  property var lastPress: null
  property var pending: []
  property var dragBefore: null
  property int sequence: 0
  property bool announced: false
  Component {
    id: hostFactory
    Plugin.DockHost { configPath: Qt.resolvedUrl("fixture-config.json"); runtimeMode: "standalone" }
  }
  Component {
    id: hookFactory
    Connections {
      property var watchedInput: null
      target: watchedInput
      function onFocusRequested() { root.lastPress = root.snapshot() }
    }
  }
  function snapshot() {
    if (!root.host) return null
    var actions = root.host.windowActions
    return {time:Date.now(), connector:root.host.sidebarController.selectedConnector,
      activeAddress:actions.addressFor(actions.activeToplevel),
      workspaces:actions.currentWorkspaces().map(function(workspace) {
        var identity=actions.canonicalWorkspaceIdentity(workspace)
        var owner=actions.resolveWorkspaceDropTarget(identity)
        return {identity:identity,owner:owner ? owner.monitor : ""}
      }), windows:actions.currentToplevels().map(function(toplevel) {
        return {address:actions.addressFor(toplevel),
          workspace:actions.reliableWorkspaceForToplevel(toplevel),minimized:actions.isMinimized(toplevel)}
      })}
  }
  function emitRecord(record) { console.log("sidebar-native: " + JSON.stringify(record)) }
  function observeInputRows() {
    var panel = root.host ? root.host.sidebarPanel : null
    var inputs = []
    if (panel) {
      var list = panel.viewport.listView
      for (var i=0;i<list.count;++i) {
        var item=list.itemAtIndex(i)
        if (item && item.input) inputs.push(item.input)
      }
    }
    var retained=[]
    root.hooks.forEach(function(hook) {
      if (hook.watchedInput && inputs.indexOf(hook.watchedInput)>=0) retained.push(hook)
      else hook.destroy()
    })
    inputs.forEach(function(input) {
      if (!retained.some(function(hook) {return hook.watchedInput===input}))
        retained.push(hookFactory.createObject(root,{watchedInput:input}))
    })
    root.hooks=retained
    if (panel && root.host.settingsLoaded && !root.announced) {
      root.announced=true
      root.emitRecord({event:"ready",state:root.snapshot(),verdict:"not-qualified"})
    }
  }
  Connections {
    target: root.host && root.host.sidebarPanel ? root.host.sidebarPanel.viewport : null
    function onActivationDispatched(target,control,connector,modifiers,accepted) {
      var record={event:"activation",sequence:++root.sequence,time:Date.now(),
        key:target ? target.key : "",address:target ? target.address || "" : "",
        kind:target ? target.kind : "",control:control,connector:connector,
        modifiers:modifiers,accepted:accepted,before:root.lastPress}
      root.lastPress=null
      root.pending=root.pending.concat([record])
      settle.restart()
    }
  }
  Connections {
    target: root.host ? root.host.sidebarController : null
    function onRowDragActiveChanged() {
      var controller=root.host.sidebarController
      if (controller.rowDragActive) {
        root.dragBefore=root.lastPress || root.snapshot()
        root.emitRecord({event:"drag-start",key:controller.dragSession.target.key,state:root.dragBefore})
      } else {
        root.pending=root.pending.concat([{event:"drag-ended",sequence:++root.sequence,
          time:Date.now(),before:root.dragBefore}])
        root.dragBefore=null
        settle.restart()
      }
    }
  }
  Timer {
    id: settle
    interval: 250
    onTriggered: {
      var after=root.snapshot(),records=root.pending
      root.pending=[]
      records.forEach(function(record) {record.after=after;root.emitRecord(record)})
    }
  }
  Timer { interval:100; repeat:true; running:true; onTriggered:root.observeInputRows() }
  Component.onCompleted: root.host=hostFactory.createObject(root)
  Component.onDestruction: if (root.host) root.host.destroy()
}
