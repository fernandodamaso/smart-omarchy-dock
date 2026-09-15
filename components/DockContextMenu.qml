pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockMenuModel.js" as DockMenuModel

PopupWindow {
  id: root

  required property Item anchorItem
  required property string position
  required property bool autoHide
  required property bool pinnedItem
  required property var runningToplevels
  required property var windowActions
  property bool interfaceAnimationsEnabled: true
  property bool originOnly: false
  property bool controlItem: false

  signal openLauncher()
  signal openNewWindow()
  signal addApplication()
  signal removeFromDock()
  signal hideFromDock()
  signal toggleAutoHide()

  property string page: "app"
  property var pageStack: []
  property var targetContexts: []
  property var pageTarget: null
  property var selectedToplevel: pageTarget ? pageTarget.toplevel : null
  property int openGeneration: 0
  property int activeMenuIndex: -1
  property real entranceOpacity: 0
  property real entranceOffset: 0

  readonly property var selectedHandle:
    root.windowActions.handleFor(selectedToplevel)
  readonly property var selectedInfo: selectedHandle
    ? selectedHandle.lastIpcObject || ({})
    : ({})
  readonly property bool selectedMinimized: {
    var originsRevision = root.windowActions.minimizedOriginsSnapshot
    return root.windowActions.isMinimized(selectedToplevel)
  }
  readonly property bool selectedFakeFullscreen:
    DockModel.isFakeFullscreen(selectedInfo)
  readonly property int selectedWorkspaceId: {
    var workspace = selectedInfo.workspace
      || (selectedHandle ? selectedHandle.workspace : null)
    var id = Number(workspace ? workspace.id : -1)
    return Number.isInteger(id) ? id : -1
  }
  readonly property var runningWindowStates: buildWindowStates()
  readonly property var runningWindowCounts:
    DockModel.windowStateCounts(runningWindowStates)
  readonly property int minimizedCount: runningWindowCounts.minimized
  readonly property int visibleWindowCount: runningWindowCounts.visible
  readonly property var pageActions: buildPageActions()

  onRunningToplevelsChanged: {
    // The open menu owns captured QObject/address identities. Any membership
    // change invalidates that snapshot rather than silently retargeting a row.
    if (visible)
      dismiss()
  }

  function open() {
    openGeneration += 1
    targetContexts = buildTargetContexts()
    pageStack = []
    pageTarget = targetContexts.length === 1 ? targetContexts[0] : null
    page = DockMenuModel.initialPage(
      root.controlItem, targetContexts.length, pageTarget !== null)

    entranceOpacity = interfaceAnimationsEnabled ? 0 : 1
    entranceOffset = interfaceAnimationsEnabled ? 6 : 0
    visible = true
    if (interfaceAnimationsEnabled) Qt.callLater(function() {
      if (visible) {
        entranceOpacity = 1
        entranceOffset = 0
      }
    })
    Qt.callLater(resetActiveMenuIndex)
    if (menuSurface) menuSurface.forceActiveFocus()
  }

  function dismiss() {
    visible = false
    entranceOpacity = 0
    entranceOffset = 0
    page = "app"
    pageStack = []
    targetContexts = []
    pageTarget = null
    activeMenuIndex = -1
  }

  function targetContextFor(toplevel, index) {
    if (!toplevel) return null

    var address = root.windowActions.addressFor(toplevel)
    var key = address !== ""
      ? "address:" + address
      : "snapshot:" + root.openGeneration + ":" + index
    return {
      key: key,
      toplevel: toplevel,
      address: address
    }
  }

  function buildTargetContexts() {
    var targets = []
    for (var i = 0; i < root.runningToplevels.length; ++i) {
      var target = targetContextFor(root.runningToplevels[i], i)
      if (target)
        targets.push(target)
    }
    return targets
  }

  function targetIsValid(targetContext) {
    return DockMenuModel.targetIsCurrent(
      targetContext,
      root.runningToplevels,
      function(toplevel) {
        return root.windowActions.addressFor(toplevel)
      })
  }

  function targetHandle(targetContext) {
    if (!targetContext || !targetIsValid(targetContext)) return null
    return root.windowActions.handleFor(targetContext.toplevel)
  }

  function targetInfo(targetContext) {
    var handle = targetHandle(targetContext)
    return handle ? handle.lastIpcObject || ({}) : ({})
  }

  function targetWorkspaceId(targetContext) {
    var handle = targetHandle(targetContext)
    if (!handle) return -1

    var info = handle.lastIpcObject || ({})
    var workspace = info.workspace || handle.workspace || null
    var id = Number(workspace ? workspace.id : -1)
    return Number.isInteger(id) ? id : -1
  }

  function targetTitle(targetContext, fallbackIndex) {
    if (!targetContext || !targetContext.toplevel)
      return "Window " + (fallbackIndex + 1)
    return String(targetContext.toplevel.title || "").trim()
      || "Window " + (fallbackIndex + 1)
  }

  function targetStatusLabel(targetContext) {
    if (!targetContext || !targetContext.toplevel) return ""
    return windowStatusLabel(targetContext.toplevel)
  }

  function targetSubtitle(targetContext, fallbackIndex) {
    var title = targetTitle(targetContext, fallbackIndex)
    var workspaceId = targetWorkspaceId(targetContext)
    var suffix = workspaceId > 0 ? " · Workspace " + workspaceId : ""
    return title + suffix
  }

  function targetMinimized(targetContext) {
    if (!targetContext || !targetIsValid(targetContext)) return false
    var originsRevision = root.windowActions.minimizedOriginsSnapshot
    return root.windowActions.isMinimized(targetContext.toplevel)
  }

  function targetFakeFullscreen(targetContext) {
    if (!targetContext || !targetIsValid(targetContext)) return false
    return DockModel.isFakeFullscreen(targetInfo(targetContext))
  }

  function pushPage(nextPage, targetContext) {
    root.pageStack = root.pageStack.concat([{
      page: root.page,
      targetContext: root.pageTarget
    }])
    root.pageTarget = targetContext || null
    root.page = nextPage
    Qt.callLater(root.resetActiveMenuIndex)
  }

  function goBack() {
    if (root.pageStack.length === 0) {
      root.dismiss()
      return false
    }

    var previous = root.pageStack[root.pageStack.length - 1]
    root.pageStack = root.pageStack.slice(0, root.pageStack.length - 1)
    root.pageTarget = previous.targetContext || null
    root.page = previous.page
    Qt.callLater(root.resetActiveMenuIndex)
    return true
  }

  function minimizeRestoreSelected() {
    // Compatibility entry point used by the existing grouped-action harness.
    var changed = root.selectedMinimized
      ? root.windowActions.restoreToplevel(root.selectedToplevel, root.originOnly)
      : root.windowActions.minimizeToplevel(root.selectedToplevel, root.originOnly)
    root.dismiss()
    return changed
  }

  function minimizeRestoreTarget(targetContext) {
    if (!targetIsValid(targetContext)) {
      root.dismiss()
      return false
    }

    var toplevel = targetContext.toplevel
    var changed = targetMinimized(targetContext)
      ? root.windowActions.restoreToplevel(toplevel, root.originOnly)
      : root.windowActions.minimizeToplevel(toplevel, root.originOnly)
    root.dismiss()
    return changed
  }

  function selectedAddress() {
    return root.windowActions.addressFor(selectedToplevel)
  }

  function windowState(toplevel) {
    return root.windowActions.windowState(toplevel)
  }

  function buildWindowStates() {
    var originsRevision = root.windowActions.minimizedOriginsSnapshot
    var states = []
    for (var i = 0; i < runningToplevels.length; ++i)
      states.push(windowState(runningToplevels[i]))
    return states
  }

  function windowStatusLabel(toplevel) {
    return DockModel.windowStatusLabel(windowState(toplevel))
  }

  function dispatchRequest(request) {
    if (!request) return false
    Hyprland.dispatch(request)
    return true
  }

  function moveTargetToWorkspace(targetContext, workspace) {
    if (!targetIsValid(targetContext)) {
      root.dismiss()
      return false
    }

    var request = DockModel.moveWindowRequest(
      targetContext.address, workspace, Hyprland.usingLua)
    if (!request) return false

    root.windowActions.forgetOrigin(targetContext.toplevel)
    dispatchRequest(request)
    dismiss()
    return true
  }

  function toggleTargetFakeFullscreen(targetContext) {
    if (!targetIsValid(targetContext)) {
      root.dismiss()
      return false
    }

    var enable = !targetFakeFullscreen(targetContext)
    var request = DockModel.fakeFullscreenRequest(
      targetContext.address, enable, Hyprland.usingLua)
    if (request) {
      dispatchRequest(request)
    } else if (targetContext.toplevel) {
      targetContext.toplevel.maximized = enable
    }
    dismiss()
    return true
  }

  function applicationActionRecords(prefix) {
    var records = [
      DockMenuModel.actionRecord(
        prefix + ":open-new", "Open New Window", "plus", true,
        "open-new", null)
    ]

    records.push(DockMenuModel.actionRecord(
      prefix + ":hide", "Hide from Dock", "eye-off", true,
      "hide-from-dock", null))

    if (root.pinnedItem) {
      records.push(DockMenuModel.actionRecord(
        prefix + ":remove", "Remove from Dock", "minus", true,
        "remove-from-dock", null))
    }
    return records
  }

  function appPageActions() {
    var records = [
      DockMenuModel.headerRecord(
        "app:header",
        "Open Windows",
        root.targetContexts.length === 0
          ? "No open windows"
          : root.targetContexts.length + " open windows")
    ]

    if (root.targetContexts.length === 0) {
      records.push(DockMenuModel.actionRecord(
        "app:none", "No open windows", "app-window", false, "noop", null))
    } else {
      for (var i = 0; i < root.targetContexts.length; ++i) {
        var target = root.targetContexts[i]
        var status = targetStatusLabel(target)
        var label = (target.toplevel && target.toplevel.activated ? "● " : "")
          + (status !== "" ? status + " " : "")
          + targetTitle(target, i)
        records.push(DockMenuModel.actionRecord(
          "app:window:" + target.key,
          label,
          "app-window",
          true,
          "open-window-page",
          target,
          { submenu: true }))
      }
    }

    records.push(DockMenuModel.separatorRecord("app:application-actions"))
    return records.concat(applicationActionRecords("app"))
  }

  function windowPageActions() {
    var target = root.pageTarget
    var valid = targetIsValid(target)
    var addressValid = valid && String(target ? target.address : "") !== ""
    var index = Math.max(0, root.targetContexts.indexOf(target))
    var records = []

    if (root.pageStack.length > 0) {
      records.push(DockMenuModel.actionRecord(
        "window:back", "Back", "arrow-left", true, "back", null))
    }

    records.push(DockMenuModel.headerRecord(
      "window:header",
      "Window",
      targetSubtitle(target, index)))

    records.push(DockMenuModel.actionRecord(
      "window:minimize",
      targetMinimized(target) ? "Restore Window" : "Minimize",
      targetMinimized(target) ? "maximize-2" : "minus",
      addressValid,
      "minimize-restore",
      target))

    records.push(DockMenuModel.actionRecord(
      "window:workspace",
      "Move to Workspace…",
      "arrow-right-left",
      addressValid,
      "open-workspaces-page",
      target,
      { submenu: true }))

    records.push(DockMenuModel.actionRecord(
      "window:fullscreen-bars",
      targetFakeFullscreen(target) ? "Restore Size" : "Fullscreen (Keep Bars)",
      targetFakeFullscreen(target) ? "minimize-2" : "maximize-2",
      addressValid,
      "toggle-fake-fullscreen",
      target,
      { checked: targetFakeFullscreen(target) }))

    records.push(DockMenuModel.separatorRecord("window:application-actions"))
    records = records.concat(applicationActionRecords("window"))

    records.push(DockMenuModel.separatorRecord("window:close-separator"))
    records.push(DockMenuModel.actionRecord(
      "window:close", "Close Window", "x", valid,
      "close-window", target))
    return records
  }

  function workspacePageActions() {
    var target = root.pageTarget
    var valid = targetIsValid(target)
    var currentWorkspace = targetWorkspaceId(target)
    var index = Math.max(0, root.targetContexts.indexOf(target))
    var records = [
      DockMenuModel.actionRecord(
        "workspace:back", "Back", "arrow-left", true, "back", null),
      DockMenuModel.headerRecord(
        "workspace:header", "Move to Workspace", targetTitle(target, index))
    ]

    for (var workspace = 1; workspace <= 10; ++workspace) {
      records.push(DockMenuModel.actionRecord(
        "workspace:" + workspace,
        "Workspace " + workspace,
        "",
        valid && String(target ? target.address : "") !== ""
          && workspace !== currentWorkspace,
        "move-workspace",
        target,
        {
          checked: workspace === currentWorkspace,
          workspace: workspace,
          iconText: workspace === currentWorkspace ? "✓" : String(workspace)
        }))
    }
    return records
  }

  function controlPageActions() {
    return [
      DockMenuModel.headerRecord("controls:header", "Dock Controls", ""),
      DockMenuModel.actionRecord(
        "controls:launcher", "Open App Launcher",
        DockModel.dockControlIcon("launcher", root.autoHide),
        true, "open-launcher", null),
      DockMenuModel.actionRecord(
        "controls:add", "Add Application",
        DockModel.dockControlIcon("add", root.autoHide),
        true, "add-application", null),
      DockMenuModel.actionRecord(
        "controls:auto-hide",
        root.autoHide ? "Disable Auto-Hide" : "Enable Auto-Hide",
        DockModel.dockControlIcon("auto-hide", root.autoHide),
        true, "toggle-auto-hide", null)
    ]
  }

  function buildPageActions() {
    if (root.controlItem || root.page === "controls")
      return controlPageActions()
    if (root.page === "window")
      return windowPageActions()
    if (root.page === "workspaces")
      return workspacePageActions()
    return appPageActions()
  }

  function setActiveMenuIndex(index) {
    if (index < 0 || index >= root.pageActions.length) return
    if (!DockMenuModel.isFocusable(root.pageActions[index])) return
    root.activeMenuIndex = index
  }

  function resetActiveMenuIndex() {
    root.activeMenuIndex = DockMenuModel.firstEnabledIndex(root.pageActions)
    Qt.callLater(root.ensureActiveVisible)
  }

  function moveActiveMenuIndex(delta) {
    var step = DockMenuModel.cursorStep(
      root.pageActions, root.activeMenuIndex, delta, root.pageTarget)
    // Cursor movement may change only the shared highlight. If that invariant
    // is ever violated, close instead of silently retargeting an action.
    if (step.targetContext !== root.pageTarget) {
      root.dismiss()
      return
    }
    root.activeMenuIndex = step.index
    Qt.callLater(root.ensureActiveVisible)
  }

  function ensureActiveVisible() {
    if (!menuList || root.activeMenuIndex < 0) return
    var item = actionRepeater.itemAt(root.activeMenuIndex)
    if (!item) return
    menuList.contentY = DockMenuModel.contentYForRow(
      menuList.contentY,
      menuList.height,
      item.y,
      item.height,
      actionColumn.height)
  }

  function activateCurrentMenuItem() {
    var index = root.activeMenuIndex
    if (index < 0 || index >= root.pageActions.length) return
    dispatchAction(root.pageActions[index], index)
  }

  function dispatchAction(record, index) {
    if (!record || record.kind !== "action" || record.enabled === false)
      return false

    root.setActiveMenuIndex(index)

    var targetContext = record.targetContext || null
    if (targetContext && !root.targetIsValid(targetContext)) {
      root.dismiss()
      return false
    }

    switch (record.command) {
    case "back":
      return root.goBack()
    case "open-window-page":
      root.pushPage("window", targetContext)
      return true
    case "open-workspaces-page":
      root.pushPage("workspaces", targetContext)
      return true
    case "minimize-restore":
      return root.minimizeRestoreTarget(targetContext)
    case "move-workspace":
      return root.moveTargetToWorkspace(targetContext, record.workspace)
    case "toggle-fake-fullscreen":
      return root.toggleTargetFakeFullscreen(targetContext)
    case "close-window":
      root.windowActions.closeToplevel(targetContext.toplevel)
      root.dismiss()
      return true
    case "open-new":
      root.dismiss()
      root.openNewWindow()
      return true
    case "hide-from-dock":
      root.dismiss()
      root.hideFromDock()
      return true
    case "remove-from-dock":
      root.dismiss()
      root.removeFromDock()
      return true
    case "open-launcher":
      root.dismiss()
      Qt.callLater(function() { root.openLauncher() })
      return true
    case "add-application":
      root.dismiss()
      root.addApplication()
      return true
    case "toggle-auto-hide":
      root.toggleAutoHide()
      root.dismiss()
      return true
    default:
      return false
    }
  }

  onPageChanged: Qt.callLater(resetActiveMenuIndex)
  onPageActionsChanged: Qt.callLater(resetActiveMenuIndex)
  onInterfaceAnimationsEnabledChanged: {
    if (!interfaceAnimationsEnabled) {
      entranceOpacity = 1
      entranceOffset = 0
    }
  }

  implicitWidth: root.controlItem ? Style.space(210) : Style.space(300)
  implicitHeight: Math.min(520, actionColumn.implicitHeight + 12)
  color: "transparent"
  grabFocus: true

  anchor {
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.anchor.window) return

      var x = root.anchorItem.width / 2 - root.implicitWidth / 2
      var y = root.anchorItem.height + 8
      if (root.position === "bottom")
        y = -root.implicitHeight - 8
      else if (root.position === "left") {
        x = root.anchorItem.width + 8
        y = root.anchorItem.height / 2 - root.implicitHeight / 2
      } else if (root.position === "right") {
        x = -root.implicitWidth - 8
        y = root.anchorItem.height / 2 - root.implicitHeight / 2
      }

      var point = root.anchor.window.contentItem.mapFromItem(
        root.anchorItem, x, y)
      if (root.position === "top" || root.position === "bottom")
        point.x = Math.max(
          8,
          Math.min(
            point.x,
            root.anchor.window.width - root.implicitWidth - 8))
      else
        point.y = Math.max(
          8,
          Math.min(
            point.y,
            root.anchor.window.height - root.implicitHeight - 8))

      root.anchor.rect.x = Math.round(point.x)
      root.anchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    id: menuSurface

    anchors.fill: parent
    opacity: root.entranceOpacity
    transform: Translate {
      x: root.position === "left" ? -root.entranceOffset
        : root.position === "right" ? root.entranceOffset : 0
      y: root.position === "top" ? -root.entranceOffset
        : root.position === "bottom" ? root.entranceOffset : 0
      Behavior on x {
        enabled: root.interfaceAnimationsEnabled
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
      Behavior on y {
        enabled: root.interfaceAnimationsEnabled
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
    Behavior on opacity {
      enabled: root.interfaceAnimationsEnabled
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
    focus: true
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec(
      "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Down) {
        root.moveActiveMenuIndex(1)
        event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        root.moveActiveMenuIndex(-1)
        event.accepted = true
      } else if (event.key === Qt.Key_Return
                 || event.key === Qt.Key_Enter
                 || event.key === Qt.Key_Space) {
        root.activateCurrentMenuItem()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape
                 || event.key === Qt.Key_Backspace
                 || event.key === Qt.Key_Left) {
        if (root.pageStack.length > 0)
          root.goBack()
        else
          root.dismiss()
        event.accepted = true
      }
    }

    Flickable {
      id: menuList

      anchors.fill: parent
      anchors.margins: 6
      contentWidth: width
      contentHeight: actionColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: actionColumn

        width: menuList.width

        Repeater {
          id: actionRepeater

          model: root.pageActions

          delegate: Item {
            id: row

            required property var modelData
            required property int index

            width: actionColumn.width
            height: modelData.kind === "separator"
              ? Style.spacing.md
              : modelData.kind === "header"
                ? (modelData.subtitle !== "" ? Style.space(48) : Style.space(34))
                : Style.spacing.popupRowHeight

            Text {
              visible: row.modelData.kind === "header"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.topMargin: Style.spacing.xs
              text: row.modelData.text || ""
              textFormat: Text.PlainText
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            Text {
              visible: row.modelData.kind === "header"
                && String(row.modelData.subtitle || "") !== ""
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.bottomMargin: Style.spacing.xs
              text: row.modelData.subtitle || ""
              textFormat: Text.PlainText
              color: Util.alpha(Color.menu.text, 0.68)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            PanelSeparator {
              visible: row.modelData.kind === "separator"
              anchors.centerIn: parent
              width: parent.width - Style.spacing.controlPaddingX * 2
              foreground: Color.menu.text
              strength: 0.2
            }

            DockMenuAction {
              visible: row.modelData.kind === "action"
              anchors.fill: parent
              enabled: row.modelData.enabled !== false
              text: row.modelData.text || ""
              iconName: row.modelData.iconName || ""
              iconText: row.modelData.iconText || ""
              checked: row.modelData.checked === true
              submenu: row.modelData.submenu === true
              hasCursor: root.activeMenuIndex === row.index

              onCursorRequested: {
                if (root)
                  root.setActiveMenuIndex(row.index)
              }
              onTriggered: {
                if (root)
                  root.dispatchAction(row.modelData, row.index)
              }
            }
          }
        }
      }
    }
  }
}
