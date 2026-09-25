import QtQuick
import QtQuick.Window
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

      property string lastStateSignature: ""

      function report(reason, heartbeat) {
        if (!watchedViewport) return
        try {
          var record = root.viewportRecord(watchedPanel, watchedViewport, reason)
          var signature = JSON.stringify(record.state)
          if (heartbeat !== true && signature === lastStateSignature) return
          lastStateSignature = signature
          root.emitRecord(record)
        } catch (error) {
          // The panel may be disappearing between a notify signal and this
          // observer callback. Native teardown must remain observational.
        }
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
        function onNaturalContentHeightChanged() { panelHook.report("hierarchy-demand") }
        function onRowCountChanged() { panelHook.report("hierarchy-count") }
      }
      property Connections listConnections: Connections {
        target: panelHook.watchedViewport ? panelHook.watchedViewport.listView : null
        function onContentYChanged() { panelHook.report("content-y") }
        function onContentHeightChanged() { panelHook.report("hierarchy-content-height") }
        function onHeightChanged() { panelHook.report("hierarchy-viewport-height") }
      }
      property Connections widgetConnections: Connections {
        target: panelHook.watchedPanel ? panelHook.watchedPanel.widgetArea : null
        function onHeightChanged() { panelHook.report("widget-allocation") }
        function onNaturalWidgetHeaderHeightChanged() { panelHook.report("widget-header-demand") }
        function onNaturalWidgetContentHeightChanged() { panelHook.report("widget-content-demand") }
        function onPresentedWidgetCountChanged() { panelHook.report("widget-count") }
        function onLayoutRevisionChanged() { panelHook.report("widget-layout") }
        function onPendingRestoreChanged() { panelHook.report("widget-pending-restore") }
        function onRestoringChanged() { panelHook.report("widget-restoring") }
        function onInputBusyChanged() { panelHook.report("widget-input") }
        function onPresentationWidgetIdsChanged() { panelHook.report("widget-ids") }
      }
      property Connections widgetScrollConnections: Connections {
        target: panelHook.watchedPanel && panelHook.watchedPanel.widgetArea
          ? panelHook.watchedPanel.widgetArea.scrollView : null
        function onContentYChanged() { panelHook.report("widget-content-y") }
        function onContentHeightChanged() { panelHook.report("widget-content-height") }
        function onHeightChanged() { panelHook.report("widget-viewport-height") }
      }
      property Connections managerConnections: Connections {
        target: panelHook.watchedPanel ? panelHook.watchedPanel.widgetManager : null
        function onManagerOpenChanged() { panelHook.report("manager-open") }
      }
      Component.onCompleted: report("panel-observed", true)
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

  function rectRecord(item, relativeTo) {
    try {
      if (!item || !relativeTo || !item.visible || item.Window.window !== relativeTo.Window.window)
        return {present:false,x:0,y:0,width:0,height:0}
      var point = relativeTo.mapFromItem(item, 0, 0)
      return {present:true, x:Number(point.x), y:Number(point.y),
        width:Number(item.width || 0), height:Number(item.height || 0)}
    } catch (error) {
      return {present:false,x:0,y:0,width:0,height:0}
    }
  }

  function safeFocusObjectName(item) {
    var name = item ? String(item.objectName || "") : ""
    var safeNames = ["smartdock-sidebar", "sidebar-widget-scroll",
      "widget-section-label", "widget-section-manage", "widget-section-plus"]
    return safeNames.indexOf(name) >= 0 ? name : ""
  }

  function safeWidgetId(value) {
    var id = typeof value === "string" ? value : ""
    return id.length <= 64 && /^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/.test(id) ? id : ""
  }

  function focusedWidgetId(area, item) {
    if (!area || !area.cards || !item) return ""
    for (var parent = item; parent; parent = parent.parent) {
      for (var index = 0; index < area.cards.count; ++index) {
        var card = area.cards.itemAt(index)
        if (card === parent) return safeWidgetId(card.widgetId)
      }
    }
    return ""
  }

  function activeFocusRecord(panel) {
    try {
      var window = panel && panel.contentItem ? panel.contentItem.Window.window : null
      var item = window ? window.activeFocusItem : null
      var owner = ""
      for (var parent = item; parent && !owner; parent = parent.parent)
        owner = safeFocusObjectName(parent)
      var widgetId = focusedWidgetId(panel ? panel.widgetArea : null, item)
      return {owner:owner || (widgetId ? "widget-card" : ""), widgetId:widgetId,
        connector:connectorFor(panel ? panel.viewport : null),
        rect:rectRecord(item, panel ? panel.contentItem : null)}
    } catch (error) {
      return {owner:"",widgetId:"",connector:"",rect:{present:false,x:0,y:0,width:0,height:0}}
    }
  }

  function widgetAnchorRecord(area, panel) {
    var anchor = area && area.controller ? area.controller.widgetPopupAnchor : null
    return rectRecord(anchor, panel ? panel.contentItem : null)
  }

  function widgetIds(area) {
    return area && Array.isArray(area.presentationWidgetIds)
      ? area.presentationWidgetIds.map(function(id) { return safeWidgetId(id) })
        .filter(function(id) { return id !== "" }).slice(0, 32) : []
  }

  function geometryRecord(geometry, present) {
    return {present:present === true, x:Number(geometry ? geometry.x : 0),
      y:Number(geometry ? geometry.y : 0), width:Number(geometry ? geometry.width : 0),
      height:Number(geometry ? geometry.height : 0)}
  }

  function widgetManagerCounters() {
    try {
      var manager = root.host && root.host.sidebarController
        ? root.host.sidebarController.widgetManager : null
      var counters = manager && typeof manager.diagnostics === "function"
        ? manager.diagnostics().counters : null
      return {acquisitions:Number(counters ? counters.acquisitions : 0),
        releases:Number(counters ? counters.releases : 0),
        activations:Number(counters ? counters.activations : 0),
        suspensions:Number(counters ? counters.suspensions : 0),
        acceptedUpdates:Number(counters ? counters.acceptedUpdates : 0),
        ignoredUpdates:Number(counters ? counters.ignoredUpdates : 0),
        failures:Number(counters ? counters.failures : 0)}
    } catch (error) {
      return {acquisitions:0,releases:0,activations:0,suspensions:0,
        acceptedUpdates:0,ignoredUpdates:0,failures:0}
    }
  }

  function viewportRecord(panel, viewport, reason) {
    var presentation = viewport.dropPresentation
    var area = panel ? panel.widgetArea : null
    var widgetScroll = area ? area.scrollView : null
    var manager = panel ? panel.widgetManager : null
    var middle = root.findObject(panel ? panel.contentItem : null, "sidebar-middle-region")
    var split = middle ? middle.split : null
    var popup = area ? area.popupWindow : null
    var managerPopup = manager ? manager.popupWindow : null
    var host = root.host
    return {event:"viewport-state", sequence:root.gestureSequence, time:Date.now(), reason:reason,
      state:{connector:connectorFor(viewport), surfaceGeneration:generationFor(viewport),
        visible:viewport.presentationVisible === true, collapsed:viewport.panelCollapsed === true,
        allocation:{availableMiddleHeight:Number(middle ? middle.height : 0),
          hierarchyHeight:Number(viewport.height || 0), widgetHeight:Number(area ? area.height : 0),
          blankHeight:Number(split ? split.blankHeight || 0 : 0),
          conservationError:Number(middle ? middle.height : 0) - Number(viewport.height || 0)
            - Number(area ? area.height : 0) - Number(split ? split.blankHeight || 0 : 0),
          conserved:Math.abs(Number(middle ? middle.height : 0) - Number(viewport.height || 0)
            - Number(area ? area.height : 0) - Number(split ? split.blankHeight || 0 : 0)) < 0.01},
        hierarchy:{naturalDemand:Number(viewport.naturalContentHeight || 0),
          presentedCount:Number(viewport.rowCount || 0), contentY:Number(viewport.listView ? viewport.listView.contentY : 0),
          contentHeight:Number(viewport.listView ? viewport.listView.contentHeight : 0),
          viewportHeight:Number(viewport.listView ? viewport.listView.height : 0),
          maximumScroll:Math.max(0, Number(viewport.listView ? viewport.listView.contentHeight - viewport.listView.height : 0)),
          anchor:anchorRecord(viewport), pendingRestore:viewport.pendingRestore === true,
          restoring:viewport.restoring === true},
        widgets:{naturalHeaderDemand:Number(area ? area.naturalWidgetHeaderHeight : 0),
          naturalContentDemand:Number(area ? area.naturalWidgetContentHeight : 0),
          presentedCount:Number(area ? area.presentedWidgetCount : 0), ids:widgetIds(area),
          visible:area ? area.sectionVisible === true : false,
          contentY:Number(widgetScroll ? widgetScroll.contentY : 0),
          contentHeight:Number(widgetScroll ? widgetScroll.contentHeight : 0),
          viewportHeight:Number(widgetScroll ? widgetScroll.height : 0),
          maximumScroll:Number(area ? area.maximumScroll : 0),
          anchor:{id:area && area.savedAnchor ? safeWidgetId(area.savedAnchor.id) : "",
            offset:area && area.savedAnchor ? Number(area.savedAnchor.offset || 0) : 0},
          pendingRestore:area ? area.pendingRestore === true : false,
          restoring:area ? area.restoring === true : false,
          inputBusy:area ? area.inputBusy === true : false,
          layoutRevision:Number(area ? area.layoutRevision : 0)},
        focus:activeFocusRecord(panel),
        popup:{open:popup ? popup.visible === true : false, anchor:widgetAnchorRecord(area, panel),
          rect:geometryRecord(area ? area.popupGeometry : null, popup ? popup.visible === true : false)},
        manager:{open:manager ? manager.managerOpen === true : false,
          anchor:rectRecord(manager ? manager.managerAnchor : null, panel ? panel.contentItem : null),
          anchorPosition:{x:Number(manager ? manager.managerAnchorPosition.x : 0),
            y:Number(manager ? manager.managerAnchorPosition.y : 0)},
          // Ui.PopupCard may live in a separate native window; mapFromItem is
          // invalid across that boundary. Its dimensions plus the panel-local
          // manager anchor remain observable and comparable between records.
          rect:geometryRecord(managerPopup ? {x:manager ? manager.managerAnchorPosition.x : 0,
            y:manager ? manager.managerAnchorPosition.y : 0, width:managerPopup.width,
            height:managerPopup.height} : null, manager ? manager.managerOpen === true : false)},
        settings:{revision:Number(host ? host.settingsRevision : 0),
          writeState:host ? scalar(host.settingsWriteState) : ""},
        diagnostics:{widgetRevision:Number(root.host && root.host.sidebarController
          ? root.host.sidebarController.widgetRevision : 0),
          enabledWidgetCount:Number(root.host && root.host.sidebarController
            ? root.host.sidebarController.widgetIds.length : 0),
          widgetManager:widgetManagerCounters(),
          widgetReorderActive:root.host && root.host.sidebarController
            ? root.host.sidebarController.widgetReorderActive === true : false,
          interactionBusy:root.host && root.host.sidebarController
            ? root.host.sidebarController.interactionBusy === true : false},
        flash:{active:scalar(viewport.dropFlashKey) !== "", key:scalar(viewport.dropFlashKey),
          opacity:Number(viewport.dropFlashOpacity || 0)},
        presentation:{present:!!presentation, token:presentation ? Number(presentation.token || 0) : 0,
          state:presentation ? scalar(presentation.state) : ""}}}
  }

  function findObject(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; ++i) {
      var found = root.findObject(children[i], name)
      if (found) return found
    }
    return null
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
    function onWidgetRevisionChanged() {
      root.panelHooks.forEach(function(hook) { hook.report("widget-revision") })
    }
    function onWidgetPopupIdChanged() {
      root.panelHooks.forEach(function(hook) { hook.report("widget-popup") })
    }
    function onInteractionBusyChanged() {
      root.panelHooks.forEach(function(hook) { hook.report("interaction-busy") })
    }
  }

  Connections {
    target: root.host
    function onSettingsRevisionChanged() {
      root.panelHooks.forEach(function(hook) { hook.report("settings-revision") })
    }
    function onSettingsWriteStateChanged() {
      root.panelHooks.forEach(function(hook) { hook.report("settings-write") })
    }
  }

  Timer { interval:100; repeat:true; running:true; onTriggered:root.observePanelsAndInputs() }
  Timer {
    interval:2000
    repeat:true
    running:true
    onTriggered: root.panelHooks.forEach(function(hook) { hook.report("heartbeat", true) })
  }
  Component.onCompleted: root.host = hostFactory.createObject(root)
  Component.onDestruction: {
    root.inputHooks.forEach(function(hook) { hook.destroy() })
    root.panelHooks.forEach(function(hook) { hook.destroy() })
    root.inputHooks = []
    root.panelHooks = []
    if (root.host) root.host.destroy()
  }
}
