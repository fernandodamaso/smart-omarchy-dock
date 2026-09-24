import QtQuick
import Quickshell
import "." as Plugin

// Live-data observer, NOT a simulated pass. One real host in a disposable guest.
// No injected windows, replaced dispatchers or copied renderer. Every record is
// constructed from an explicit scalar allowlist; never add rows, titles,
// toplevels, QObjects, presentation snapshots or private action payloads.
ShellRoot {
  id: root
  property var host: null
  property var panelHooks: []
  property var inputHooks: []
  property var lastPress: null
  property int sequence: 0
  property int gestureSequence: 0
  property string gestureConnector: ""
  property double gestureSurfaceGeneration: 0
  property bool releaseSeen: false
  property bool announced: false
  property string panelSignature: ""

  Component {
    id: hostFactory
    Plugin.DockHost { configPath: Qt.resolvedUrl("fixture-config.json"); runtimeMode: "standalone" }
  }

  Component {
    id: inputHookFactory
    Connections {
      property var watchedInput: null
      property var watchedViewport: null
      property string sourceType: "ordinary-row"
      target: watchedInput
      function onFocusRequested() {
        root.capturePress(watchedInput, watchedViewport, sourceType)
      }
      function onDragReleased() {
        root.releaseSeen = true
        root.emitRecord({event:"gesture-release", sequence:root.gestureSequence,
          time:Date.now(), connector:root.connectorFor(watchedViewport),
          surfaceGeneration:root.generationFor(watchedViewport)})
      }
      function onDragOwnedChanged() {
        if (!watchedInput || watchedInput.dragOwned || root.gestureSequence <= 0) return
        root.emitRecord({event:"input-cleanup", sequence:root.gestureSequence,
          time:Date.now(), connector:root.connectorFor(watchedViewport),
          surfaceGeneration:root.generationFor(watchedViewport),
          releaseObserved:root.releaseSeen,
          dragOwned:false, pressedTargetPresent:watchedInput.pressedTarget !== null,
          consumed:watchedInput.consumed === true})
      }
    }
  }

  Component {
    id: panelHookFactory
    QtObject {
      id: panelHook
      property var watchedPanel: null
      readonly property var watchedViewport: watchedPanel ? watchedPanel.viewport : null

      function report(reason) {
        if (!watchedViewport) return
        root.emitRecord(root.viewportRecord(watchedViewport, reason))
      }

      property Connections viewportConnections: Connections {
        target: panelHook.watchedViewport
        function onActivationDispatched(target, control, connector, modifiers, accepted) {
          root.emitActivation(target, control, connector, modifiers, accepted,
            panelHook.watchedViewport)
        }
        function onPendingRestoreChanged() { panelHook.report("pending-restore") }
        function onRestoringChanged() { panelHook.report("restoring") }
        function onDropSurfaceGenerationChanged() { panelHook.report("surface-generation") }
        function onDropPresentationChanged() { panelHook.report("presentation") }
        function onDropFlashKeyChanged() { panelHook.report("flash-key") }
        function onDropFlashOpacityChanged() { panelHook.report("flash-opacity") }
        function onPanelConnectorChanged() { panelHook.report("connector") }
        function onPresentationVisibleChanged() { panelHook.report("visibility") }
      }
      property Connections listConnections: Connections {
        target: panelHook.watchedViewport ? panelHook.watchedViewport.listView : null
        function onContentYChanged() { panelHook.report("content-y") }
      }
      Component.onCompleted: report("panel-observed")
    }
  }

  function scalar(value) {
    return value === undefined || value === null ? "" : String(value)
  }

  function connectorFor(viewport) {
    return viewport ? scalar(viewport.panelConnector) : ""
  }

  function generationFor(viewport) {
    return viewport ? Number(viewport.dropSurfaceGeneration || 0) : 0
  }

  function targetRecord(target) {
    return {present:!!target, kind:target ? scalar(target.kind) : "",
      key:target ? scalar(target.key) : "",
      address:target ? scalar(target.address) : "",
      workspace:target ? scalar(target.identity || target.workspaceIdentity) : "",
      monitor:target ? scalar(target.monitor || target.monitorIdentity) : ""}
  }

  function rejectionRecord(rejection) {
    return {present:!!rejection, sourceKind:rejection ? scalar(rejection.sourceKind) : "",
      key:rejection ? scalar(rejection.key) : "",
      reason:rejection ? scalar(rejection.reason) : "",
      workspace:rejection ? scalar(rejection.identity) : "",
      monitor:rejection ? scalar(rejection.monitor) : ""}
  }

  function anchorRecord(viewport) {
    if (!viewport || !root.host) return {present:false,key:"",offset:0}
    var state = root.host.sidebarController.readScrollState(
      connectorFor(viewport), viewport.panelCollapsed === true)
    var anchor = state && state.anchor ? state.anchor : null
    return {present:!!anchor, key:anchor ? scalar(anchor.key) : "",
      offset:anchor ? Number(anchor.offset || 0) : 0}
  }

  function viewportRecord(viewport, reason) {
    var presentation = viewport.dropPresentation
    return {event:"viewport-state", sequence:root.gestureSequence, time:Date.now(),
      reason:reason, connector:connectorFor(viewport),
      surfaceGeneration:generationFor(viewport),
      visible:viewport.presentationVisible === true,
      collapsed:viewport.panelCollapsed === true,
      pendingRestore:viewport.pendingRestore === true,
      restoring:viewport.restoring === true,
      contentY:Number(viewport.listView ? viewport.listView.contentY : 0),
      anchor:anchorRecord(viewport),
      flash:{active:scalar(viewport.dropFlashKey) !== "",
        key:scalar(viewport.dropFlashKey), opacity:Number(viewport.dropFlashOpacity || 0)},
      presentation:{present:!!presentation,
        token:presentation ? Number(presentation.token || 0) : 0,
        state:presentation ? scalar(presentation.state) : ""}}
  }

  function operationRecord(operation) {
    var controller = root.host ? root.host.sidebarController : null
    return {present:!!operation, state:operation ? scalar(operation.state) : "",
      token:operation ? Number(operation.token || 0) : 0,
      sourceKind:operation ? scalar(operation.sourceKind) : "",
      sourceKey:operation ? scalar(operation.sourceKey) : "",
      address:operation ? scalar(operation.address) : "",
      originConnector:operation ? scalar(operation.originConnector) : "",
      originSurfaceGeneration:operation ? Number(operation.originSurfaceGeneration || 0) : 0,
      expectedWorkspace:operation ? scalar(operation.expectedWorkspace) : "",
      expectedMonitor:operation ? scalar(operation.expectedMonitor) : "",
      deadline:operation ? Number(operation.deadline || 0) : 0,
      hasToplevel:!!(operation && operation.toplevel),
      originCurrent:!!(operation && controller && controller.dropOriginIsCurrent(operation)),
      entityAlive:!!(operation && controller && controller.dropEntityAlive(operation)),
      locationMatches:!!(operation && controller && controller.dropLocationMatches(operation))}
  }

  function emitRecord(record) {
    console.log("sidebar-native: " + JSON.stringify(record))
  }

  function capturePress(input, viewport, sourceType) {
    var target = root.host && input
      ? root.host.sidebarController.captureTarget(input.rowKey) : null
    var pressSequence = ++root.sequence
    root.lastPress = {sequence:pressSequence, sourceType:sourceType, source:targetRecord(target),
      connector:connectorFor(viewport), surfaceGeneration:generationFor(viewport)}
    root.emitRecord({event:"press", sequence:pressSequence,
      time:Date.now(), sourceType:sourceType, source:targetRecord(target),
      connector:connectorFor(viewport), surfaceGeneration:generationFor(viewport)})
  }

  function emitActivation(target, control, connector, modifiers, accepted, viewport) {
    var activationSequence = root.lastPress ? root.lastPress.sequence : ++root.sequence
    root.emitRecord({event:"activation", sequence:activationSequence,
      time:Date.now(), source:targetRecord(target), control:control === true,
      connector:scalar(connector), surfaceGeneration:generationFor(viewport),
      modifiers:Number(modifiers || 0), accepted:accepted === true,
      pressPresent:root.lastPress !== null,
      pressConnector:root.lastPress ? root.lastPress.connector : "",
      pressSurfaceGeneration:root.lastPress ? root.lastPress.surfaceGeneration : 0})
    root.lastPress = null
  }

  function rowInputCandidate(item) {
    return !!item && typeof item.capturePress === "function"
      && typeof item.cancelGesture === "function" && item.rowKey !== undefined
      && item.pressedTarget !== undefined && item.dragOwned !== undefined
  }

  function inlineInput(row) {
    var anchor = row ? row.inlineWorkspaceBadgeAnchor : null
    if (!anchor || row.leadingWorkspaceBadgeVisible !== true) return null
    var children = anchor.children || []
    for (var i=0;i<children.length;++i) {
      if (rowInputCandidate(children[i])) return children[i]
    }
    return null
  }

  function observePanelsAndInputs() {
    var panels = root.host ? root.host.sidebarPanels || [] : []
    var connectors = panels.map(function(panel) { return connectorFor(panel.viewport) })
    var signature = connectors.join("\u001f")
    if (signature !== root.panelSignature) {
      root.panelSignature = signature
      root.emitRecord({event:"panel-set", time:Date.now(), panelCount:panels.length,
        connectors:connectors})
    }
    var retainedPanels = []
    root.panelHooks.forEach(function(hook) {
      if (hook.watchedPanel && panels.indexOf(hook.watchedPanel) >= 0) retainedPanels.push(hook)
      else hook.destroy()
    })
    panels.forEach(function(panel) {
      if (!retainedPanels.some(function(hook) { return hook.watchedPanel === panel }))
        retainedPanels.push(panelHookFactory.createObject(root, {watchedPanel:panel}))
    })
    root.panelHooks = retainedPanels

    var inputs = []
    panels.forEach(function(panel) {
      var viewport = panel ? panel.viewport : null
      var list = viewport ? viewport.listView : null
      if (!list) return
      for (var i=0;i<list.count;++i) {
        var row = list.itemAtIndex(i)
        if (!row) continue
        if (row.input) inputs.push({input:row.input, viewport:viewport, sourceType:"ordinary-row"})
        var inline = inlineInput(row)
        if (inline) inputs.push({input:inline, viewport:viewport, sourceType:"inline-workspace-badge"})
      }
    })
    var retainedInputs = []
    root.inputHooks.forEach(function(hook) {
      var found = inputs.some(function(entry) {
        return hook.watchedInput === entry.input && hook.watchedViewport === entry.viewport
      })
      if (found) retainedInputs.push(hook)
      else hook.destroy()
    })
    inputs.forEach(function(entry) {
      if (!retainedInputs.some(function(hook) {
        return hook.watchedInput === entry.input && hook.watchedViewport === entry.viewport
      })) retainedInputs.push(inputHookFactory.createObject(root, {
        watchedInput:entry.input, watchedViewport:entry.viewport, sourceType:entry.sourceType
      }))
    })
    root.inputHooks = retainedInputs

    var expectedPanels = root.host && root.host.sidebarController
      ? root.host.sidebarController.mappedScreens.length : 0
    if (expectedPanels > 0 && panels.length === expectedPanels
        && root.host.settingsLoaded && !root.announced) {
      root.announced = true
      root.emitRecord({event:"ready", time:Date.now(), verdict:"not-qualified",
        panelCount:panels.length, connectors:connectors,
        observedInputCount:inputs.length,
        observedInlineInputCount:inputs.filter(function(entry) {
          return entry.sourceType === "inline-workspace-badge"
        }).length})
    }
  }

  Connections {
    target: root.host ? root.host.sidebarController : null
    function onRowDragActiveChanged() {
      var controller = root.host.sidebarController
      if (controller.rowDragActive) {
        var session = controller.dragSession
        root.gestureSequence = root.lastPress ? root.lastPress.sequence : ++root.sequence
        root.gestureConnector = session ? scalar(session.connector) : ""
        root.gestureSurfaceGeneration = session
          ? Number(session.originSurfaceGeneration || 0) : 0
        root.lastPress = null
        root.releaseSeen = false
        root.emitRecord({event:"gesture-start", sequence:root.gestureSequence,
          time:Date.now(), source:targetRecord(session ? session.target : null),
          connector:root.gestureConnector,
          surfaceGeneration:root.gestureSurfaceGeneration,
          sourceLocationPresent:!!(session && session.location),
          sourceWorkspace:session && session.location ? scalar(session.location.identity) : "",
          sourceMonitor:session && session.location ? scalar(session.location.monitor) : "",
          sourceMinimized:!!(session && session.location && session.location.minimized)})
      } else if (root.gestureSequence > 0) {
        root.emitRecord({event:"gesture-cleanup", sequence:root.gestureSequence,
          time:Date.now(), connector:root.gestureConnector,
          surfaceGeneration:root.gestureSurfaceGeneration,
          releaseObserved:root.releaseSeen,
          sessionCleared:controller.dragSession === null,
          targetCleared:controller.dragTarget === null,
          rejectionCleared:controller.dragRejection === null,
          interactionBusy:controller.interactionBusy === true,
          operationPresent:controller.dropOperation !== null})
      }
    }
    function onDragTargetChanged() {
      root.emitRecord({event:"target-transition", sequence:root.gestureSequence,
        time:Date.now(), connector:root.gestureConnector,
        surfaceGeneration:root.gestureSurfaceGeneration,
        target:targetRecord(root.host.sidebarController.dragTarget)})
    }
    function onDragRejectionChanged() {
      root.emitRecord({event:"rejection-transition", sequence:root.gestureSequence,
        time:Date.now(), connector:root.gestureConnector,
        surfaceGeneration:root.gestureSurfaceGeneration,
        rejection:rejectionRecord(root.host.sidebarController.dragRejection)})
    }
    function onDropOperationChanged() {
      root.emitRecord({event:"drop-operation", sequence:root.gestureSequence,
        time:Date.now(), operation:operationRecord(root.host.sidebarController.dropOperation)})
    }
    function onScrollStatesChanged() {
      root.panelHooks.forEach(function(hook) { hook.report("anchor") })
    }
  }

  Timer { interval:100; repeat:true; running:true; onTriggered:root.observePanelsAndInputs() }
  Component.onCompleted: root.host = hostFactory.createObject(root)
  Component.onDestruction: {
    root.inputHooks.forEach(function(hook) { hook.destroy() })
    root.panelHooks.forEach(function(hook) { hook.destroy() })
    root.inputHooks = []
    root.panelHooks = []
    if (root.host) root.host.destroy()
  }
}
