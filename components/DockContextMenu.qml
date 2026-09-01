pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

PopupWindow {
  id: root

  required property Item anchorItem
  required property string position
  required property bool autoHide
  required property bool pinnedItem
  required property var runningToplevels
  property bool controlItem: false
  signal openLauncher()
  signal openSettings()
  signal openNewWindow()
  signal addApplication()
  signal removeFromDock()
  signal toggleAutoHide()

  readonly property string minimizedWorkspace: "special:smartdock-minimized"
  property string page: "windows"
  property var selectedToplevel: null
  property var minimizedOrigins: ({})
  readonly property var selectedHandle: hyprToplevelFor(selectedToplevel)
  readonly property var selectedInfo: selectedHandle
    ? selectedHandle.lastIpcObject || ({})
    : ({})
  readonly property bool selectedFloating: selectedInfo.floating === true
  readonly property bool selectedPinned: selectedInfo.pinned === true
  readonly property bool selectedMinimized: isToplevelMinimized(selectedToplevel)
  readonly property bool selectedFakeFullscreen:
    DockModel.isFakeFullscreen(selectedInfo)
  readonly property var runningWindowStates: buildWindowStates()
  readonly property var runningWindowCounts:
    DockModel.windowStateCounts(runningWindowStates)
  readonly property int minimizedCount: runningWindowCounts.minimized
  readonly property int visibleWindowCount: runningWindowCounts.visible
  readonly property int selectedWorkspaceId: selectedHandle && selectedHandle.workspace
    ? selectedHandle.workspace.id
    : -1

  function open() {
    page = "windows"
    selectedToplevel = null
    visible = true
  }

  function dismiss() {
    visible = false
    page = "windows"
    selectedToplevel = null
  }

  function selectWindow(toplevel) {
    selectedToplevel = toplevel
    page = "actions"
  }

  function hyprToplevelFor(toplevel) {
    if (!toplevel || !Hyprland.toplevels) return null
    var handles = Hyprland.toplevels.values || []
    for (var i = 0; i < handles.length; ++i) {
      if (handles[i] && handles[i].wayland === toplevel)
        return handles[i]
    }
    return null
  }

  function selectedAddress() {
    return DockModel.normalizeWindowAddress(
      selectedHandle ? selectedHandle.address : "")
  }

  function windowState(toplevel) {
    var handle = hyprToplevelFor(toplevel)
    var address = DockModel.normalizeWindowAddress(handle ? handle.address : "")
    var workspace = handle ? handle.workspace : null
    var workspaceId = workspace ? Number(workspace.id) : -1
    var workspaceName = workspace ? String(workspace.name || "").trim() : ""
    var minimized = workspaceName === minimizedWorkspace
      || (address !== "" && minimizedOrigins[address] !== undefined)

    if (Number.isInteger(workspaceId) && workspaceId > 0)
      workspaceName = String(workspaceId)
    else if (workspaceName.indexOf("name:") !== 0
             && workspaceName.indexOf("special:") !== 0
             && workspaceName !== "")
      workspaceName = "name:" + workspaceName

    return { minimized: minimized, workspace: workspaceName }
  }

  function buildWindowStates() {
    var states = []
    for (var i = 0; i < runningToplevels.length; ++i)
      states.push(windowState(runningToplevels[i]))
    return states
  }

  function windowStatusLabel(toplevel) {
    return DockModel.windowStatusLabel(windowState(toplevel))
  }

  function copyMap(source) {
    var result = {}
    for (var key in source) result[key] = source[key]
    return result
  }

  function workspaceTarget(workspace) {
    if (!workspace) return ""
    var id = Number(workspace.id)
    if (Number.isInteger(id) && id > 0) return String(id)

    var name = String(workspace.name || "").trim()
    if (!name || name.indexOf("special:") === 0) return ""
    return name.indexOf("name:") === 0 ? name : "name:" + name
  }

  function addressFor(toplevel) {
    var handle = hyprToplevelFor(toplevel)
    return DockModel.normalizeWindowAddress(handle ? handle.address : "")
  }

  function isToplevelMinimized(toplevel) {
    var handle = hyprToplevelFor(toplevel)
    var address = DockModel.normalizeWindowAddress(handle ? handle.address : "")
    var workspaceName = handle && handle.workspace
      ? String(handle.workspace.name || "") : ""
    return workspaceName === minimizedWorkspace
      || (address !== "" && minimizedOrigins[address] !== undefined)
  }

  function clearMinimizedOrigin(address) {
    if (!address || minimizedOrigins[address] === undefined) return
    var origins = copyMap(minimizedOrigins)
    delete origins[address]
    minimizedOrigins = origins
  }

  function minimizeToplevel(toplevel) {
    var handle = hyprToplevelFor(toplevel)
    var address = DockModel.normalizeWindowAddress(handle ? handle.address : "")
    if (!address) return

    var origin = workspaceTarget(handle ? handle.workspace : null)
      || workspaceTarget(Hyprland.focusedWorkspace)
    if (!origin) return

    var origins = copyMap(minimizedOrigins)
    origins[address] = origin
    minimizedOrigins = origins
    dispatchRequest(DockModel.minimizeWindowRequest(address, Hyprland.usingLua))
  }

  function restoreToplevel(toplevel) {
    var address = addressFor(toplevel)
    if (!address) return

    var target = minimizedOrigins[address]
      || workspaceTarget(Hyprland.focusedWorkspace)
    if (!target) return

    clearMinimizedOrigin(address)
    dispatchRequest(DockModel.restoreWindowRequest(
      address, target, Hyprland.usingLua))
  }

  function activateToplevel(toplevel) {
    if (!toplevel) return
    if (isToplevelMinimized(toplevel))
      restoreToplevel(toplevel)
    else
      toplevel.activate()
  }

  function dispatchRequest(request) {
    if (request) Hyprland.dispatch(request)
  }

  function moveSelectedToWorkspace(workspace) {
    clearMinimizedOrigin(selectedAddress())
    dispatchRequest(DockModel.moveWindowRequest(
      selectedAddress(), workspace, Hyprland.usingLua))
    dismiss()
  }

  function toggleSelectedFloating() {
    dispatchRequest(DockModel.floatWindowRequest(
      selectedAddress(), "toggle", Hyprland.usingLua))
    dismiss()
  }

  function toggleSelectedPinned() {
    var address = selectedAddress()
    if (!selectedPinned && !selectedFloating) {
      dispatchRequest(DockModel.floatWindowRequest(
        address, "enable", Hyprland.usingLua))
    }
    dispatchRequest(DockModel.pinWindowRequest(address, Hyprland.usingLua))
    dismiss()
  }

  function toggleSelectedFakeFullscreen() {
    var enable = !selectedFakeFullscreen
    var request = DockModel.fakeFullscreenRequest(
      selectedAddress(), enable, Hyprland.usingLua)
    if (request)
      dispatchRequest(request)
    else if (selectedToplevel)
      selectedToplevel.maximized = enable
    dismiss()
  }

  function selectedTitle() {
    if (!selectedToplevel) return "Window"
    var title = String(selectedToplevel.title || "").trim()
    return title || String(selectedToplevel.appId || "Window")
  }

  implicitWidth: 200
  implicitHeight: page === "windows"
    ? controlItem
      ? 72 + 4 * 38
      : Math.min(520, 72 + Math.max(1, runningToplevels.length) * 38
        + (pinnedItem ? 2 : 1) * 38)
    : page === "actions" ? 388 : 470
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

      var point = root.anchor.window.contentItem.mapFromItem(root.anchorItem, x, y)
      if (root.position === "top" || root.position === "bottom")
        point.x = Math.max(8, Math.min(point.x, root.anchor.window.width - root.implicitWidth - 8))
      else
        point.y = Math.max(8, Math.min(point.y, root.anchor.window.height - root.implicitHeight - 8))

      root.anchor.rect.x = Math.round(point.x)
      root.anchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec(
      "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

    Flickable {
      anchors.fill: parent
      anchors.margins: 6
      contentWidth: width
      contentHeight: menuPages.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: menuPages

        width: parent.width

        Column {
          visible: root.page === "windows"
          width: parent.width

          Text {
            width: parent.width
            height: 32
            leftPadding: 12
            verticalAlignment: Text.AlignVCenter
            text: root.controlItem ? "Dock Controls" : "Open Windows"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          DockMenuAction {
            visible: !root.controlItem && root.runningToplevels.length === 0
            enabled: false
            text: "No open windows"
          }

          Repeater {
            model: root.controlItem ? [] : root.runningToplevels

            DockMenuAction {
              required property var modelData
              required property int index

              readonly property string statusLabel: root
                ? root.windowStatusLabel(modelData) : ""

              iconName: "app-window"
              text: (modelData && modelData.activated ? "● " : "")
                + statusLabel
                + (statusLabel !== "" ? " " : "")
                + (String(modelData && modelData.title || "").trim()
                  || "Window " + (index + 1))
              onTriggered: if (root) root.selectWindow(modelData)
            }
          }

          Item {
            visible: !root.controlItem
            width: 188
            height: 10

            Rectangle {
              anchors.centerIn: parent
              width: 164
              height: 1
              color: Util.alpha(Color.menu.border, 0.35)
            }
          }

          DockMenuAction {
            visible: !root.controlItem
            iconName: "plus"
            text: "Open New Window"
            onTriggered: {
              root.dismiss()
              root.openNewWindow()
            }
          }

          DockMenuAction {
            visible: root.controlItem
            iconName: DockModel.dockControlIcon("launcher", root.autoHide)
            text: "Open App Launcher"
            onTriggered: {
              root.dismiss()
              Qt.callLater(() => root.openLauncher())
            }
          }

          DockMenuAction {
            visible: root.controlItem
            iconName: DockModel.dockControlIcon("settings", root.autoHide)
            text: "Dock Settings…"
            onTriggered: {
              root.dismiss()
              Qt.callLater(() => root.openSettings())
            }
          }

          DockMenuAction {
            visible: root.controlItem
            iconName: DockModel.dockControlIcon("add", root.autoHide)
            text: "Add Application"
            onTriggered: {
              root.dismiss()
              root.addApplication()
            }
          }

          DockMenuAction {
            visible: !root.controlItem && root.pinnedItem
            iconName: "minus"
            text: "Remove from Dock"
            onTriggered: {
              root.dismiss()
              root.removeFromDock()
            }
          }

          DockMenuAction {
            visible: root.controlItem
            iconName: DockModel.dockControlIcon("auto-hide", root.autoHide)
            text: root.autoHide ? "Disable Auto-Hide" : "Enable Auto-Hide"
            onTriggered: {
              root.toggleAutoHide()
              root.dismiss()
            }
          }
        }

        Column {
          visible: root.page === "actions"
          width: parent.width

          DockMenuAction {
            iconName: "chevron-left"
            text: "Back to Windows"
            onTriggered: root.page = "windows"
          }

          Text {
            width: parent.width - 24
            height: 32
            leftPadding: 12
            rightPadding: 12
            verticalAlignment: Text.AlignVCenter
            text: root.selectedTitle()
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          DockMenuAction {
            iconName: "focus"
            text: "Focus"
            enabled: root.selectedToplevel !== null
            onTriggered: {
              root.activateToplevel(root.selectedToplevel)
              root.dismiss()
            }
          }

          DockMenuAction {
            iconName: "arrow-right-left"
            text: "Move to Workspace…"
            enabled: root.selectedAddress() !== ""
            onTriggered: root.page = "workspaces"
          }

          DockMenuAction {
            iconName: root.selectedFakeFullscreen ? "minimize-2" : "maximize-2"
            text: root.selectedFakeFullscreen
              ? "Restore Size" : "Fullscreen (Keep Bars)"
            enabled: root.selectedAddress() !== ""
            onTriggered: root.toggleSelectedFakeFullscreen()
          }

          DockMenuAction {
            iconName: root.selectedMinimized ? "maximize-2" : "minus"
            text: root.selectedMinimized ? "Restore Window" : "Minimize"
            enabled: root.selectedAddress() !== ""
            onTriggered: {
              if (root.selectedMinimized)
                root.restoreToplevel(root.selectedToplevel)
              else
                root.minimizeToplevel(root.selectedToplevel)
              root.dismiss()
            }
          }

          DockMenuAction {
            iconName: root.selectedFloating ? "square" : "move"
            text: root.selectedFloating ? "Tile Window" : "Float Window"
            enabled: root.selectedAddress() !== ""
            onTriggered: root.toggleSelectedFloating()
          }

          DockMenuAction {
            iconName: root.selectedPinned ? "pin-off" : "pin"
            text: root.selectedPinned ? "Unpin from Workspaces" : "Pin to All Workspaces"
            enabled: root.selectedAddress() !== ""
            onTriggered: root.toggleSelectedPinned()
          }

          Item {
            width: 188
            height: 10

            Rectangle {
              anchors.centerIn: parent
              width: 164
              height: 1
              color: Util.alpha(Color.menu.border, 0.35)
            }
          }

          DockMenuAction {
            iconName: "x"
            text: "Close Window"
            enabled: root.selectedToplevel !== null
            onTriggered: {
              root.selectedToplevel.close()
              root.dismiss()
            }
          }
        }

        Column {
          visible: root.page === "workspaces"
          width: parent.width

          DockMenuAction {
            iconName: "chevron-left"
            text: "Back to Actions"
            onTriggered: root.page = "actions"
          }

          Text {
            width: parent.width
            height: 32
            leftPadding: 12
            verticalAlignment: Text.AlignVCenter
            text: "Move to Workspace"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Repeater {
            model: 10

            DockMenuAction {
              required property int index

              readonly property int workspaceNumber: index + 1
              iconName: "layout-grid"
              text: "Workspace " + workspaceNumber
                + (root.selectedWorkspaceId === workspaceNumber ? "  ✓" : "")
              enabled: root.selectedWorkspaceId !== workspaceNumber
              onTriggered: root.moveSelectedToWorkspace(workspaceNumber)
            }
          }
        }
      }
    }
  }
}
