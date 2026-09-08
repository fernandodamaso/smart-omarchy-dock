pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root
  visible: false

  property var toplevelModel: null
  property var monitorModel: null
  property var workspaceModel: null
  property var refreshSource: null
  property int revision: 0

  function valuesOf(model) {
    return model && model.values ? model.values : []
  }

  function requestRefresh() {
    refreshTimer.restart()
  }

  function invalidate() {
    invalidationTimer.restart()
  }

  function refresh() {
    if (!root.refreshSource) return
    root.refreshSource.refreshMonitors()
    root.refreshSource.refreshWorkspaces()
    root.refreshSource.refreshToplevels()
  }

  component ObjectObserver: Item {
    id: observer
    visible: false
    required property var modelData

    Connections {
      target: observer.modelData
      ignoreUnknownSignals: true
      function onAddressChanged() { root.invalidate() }
      function onActiveChanged() { root.invalidate() }
      function onActiveWorkspaceChanged() { root.invalidate() }
      function onFocusedChanged() { root.invalidate() }
      function onHasFullscreenChanged() { root.invalidate() }
      function onHyprlandHandleChanged() { root.invalidate() }
      function onLastIpcObjectChanged() { root.invalidate() }
      function onMonitorChanged() { root.invalidate() }
      function onNameChanged() { root.invalidate() }
      function onUrgentChanged() { root.invalidate() }
      function onWaylandHandleChanged() { root.invalidate() }
      function onWorkspaceChanged() { root.invalidate() }
    }
  }

  Timer {
    id: refreshTimer
    interval: 80
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: invalidationTimer
    interval: 0
    repeat: false
    onTriggered: root.revision++
  }

  Connections {
    target: root.toplevelModel
    ignoreUnknownSignals: true
    function onValuesChanged() { root.invalidate() }
  }

  Connections {
    target: root.monitorModel
    ignoreUnknownSignals: true
    function onValuesChanged() { root.invalidate() }
  }

  Connections {
    target: root.workspaceModel
    ignoreUnknownSignals: true
    function onValuesChanged() { root.invalidate() }
  }

  Instantiator {
    model: root.valuesOf(root.toplevelModel)
    delegate: ObjectObserver {}
  }

  Instantiator {
    model: root.valuesOf(root.monitorModel)
    delegate: ObjectObserver {}
  }

  Instantiator {
    model: root.valuesOf(root.workspaceModel)
    delegate: ObjectObserver {}
  }
}
