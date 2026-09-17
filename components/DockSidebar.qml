pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "DockModel.js" as DockModel

PanelWindow {
  id: root
  required property var host
  required property var controller
  readonly property var viewport: sidebarViewport
  readonly property string preferenceFeedback: !host ? "" : host.settingsWriteState === "error"
    ? "Unsaved preferences: " + String(host.settingsWriteError || "Persistence failed")
    : host.settingsWriteState === "saving" ? "Saving preferences" : controller.mutationFeedback
  readonly property string badgeScopeOwner: "smartdock-sidebar"
  objectName: "smartdock-sidebar"
  visible: screen !== null && controller.geometry.mapped
  implicitWidth: Math.round(controller.geometry.width)
  anchors.top: true
  anchors.bottom: true
  anchors.left: controller.edge === "left"
  anchors.right: controller.edge === "right"
  // The handle lives inside this total width. Reserve that persistent width once.
  exclusiveZone: implicitWidth
  WlrLayershell.namespace: "smartdock-sidebar"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  color: "transparent"

  function syncBadges() {
    if (root.host && root.host.badgeTracker) root.host.badgeTracker.syncWorkspaceScopes(
      root.badgeScopeOwner, root.visible ? root.controller.projection.badgeItems : [])
  }

  function closeSurfaces() {
    picker.visible = false
    root.controller.cancelResize("surface-close")
    root.controller.interactionBusy = false
    if (root.host && root.host.badgeTracker) root.host.badgeTracker.syncWorkspaceScopes(root.badgeScopeOwner, [])
  }

  Ui.BorderSurface {
    id: surface
    anchors.fill: parent
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
    clip: true
    Column {
      id: controls
      x: surface.contentLeftInset
      width: Math.max(0, surface.width - surface.contentLeftInset - surface.contentRightInset)
      y: surface.contentTopInset
      Ui.Button {
        width: parent.width
        height: sidebarViewport.rowHeight
        iconText: root.controller.collapsed ? "»" : "«"
        tooltipText: (root.controller.collapsed ? "Expand sidebar" : "Collapse to icon rail")
          + (root.preferenceFeedback ? " · " + root.preferenceFeedback : "")
        Accessible.role: Accessible.Button
        Accessible.name: tooltipText
        focusable: true
        enabled: !root.controller.interactionBusy
        onClicked: root.controller.requestCollapse()
      }
      Text {
        width: parent.width
        visible: text !== "" && !root.controller.collapsed
        height: visible ? implicitHeight : 0
        text: root.preferenceFeedback
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    DockSidebarViewport {
      id: sidebarViewport
      controller: root.controller
      anchors.top: controls.bottom
      anchors.bottom: utilities.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: surface.contentLeftInset + (!root.controller.collapsed && root.controller.edge === "right" ? 8 : 0)
      anchors.rightMargin: surface.contentRightInset + (!root.controller.collapsed && root.controller.edge === "left" ? 8 : 0)
    }
    Column {
      id: utilities
      x: surface.contentLeftInset
      width: Math.max(0, surface.width - surface.contentLeftInset - surface.contentRightInset)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: surface.contentBottomInset
      // Utilities are not widgets. SB-05 supplies the bounded provider footer.
      Ui.Button {
        id: launcher
        width: parent.width
        height: Math.min(sidebarViewport.rowHeight, root.height / (root.host.showTrash ? 5 : 4))
        text: root.controller.collapsed ? "⌕" : "Applications"
        tooltipText: "Launch applications; right-click to add a pinned application"
        Accessible.role: Accessible.Button
        Accessible.name: "Applications"
        focusable: true
        onClicked: {
          var command = DockModel.normalizeSetting("controlCommand", root.controller.settings.controlCommand)
          if (command) Quickshell.execDetached(["sh", "-lc", command])
        }
        onRightClicked: picker.open()
      }
      Ui.Button {
        visible: root.host.showTrash
        width: parent.width
        height: visible ? Math.min(sidebarViewport.rowHeight, root.height / 5) : 0
        text: root.controller.collapsed ? "♲" : "Trash"
        tooltipText: "Open Trash"
        Accessible.role: Accessible.Button
        Accessible.name: "Open Trash"
        focusable: visible
        onClicked: root.host.openTrash()
      }
    }
  }

  DockSidebarResizeHandle {
    id: resizeHandle
    controller: root.controller
    panelWidth: root.width
    screenX: root.controller.selectedScreen ? Number(root.controller.selectedScreen.x || 0) : 0
    screenWidth: root.controller.selectedScreen ? Number(root.controller.selectedScreen.width || 0) : 0
    width: 8
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: root.controller.edge === "left" ? parent.right : undefined
    anchors.left: root.controller.edge === "right" ? parent.left : undefined
    z: 20
  }

  Shortcut {
    sequence: "Escape"
    enabled: root.visible && root.controller.resizeActive
    onActivated: root.controller.cancelResize("escape")
  }

  DockAppPicker {
    id: picker
    anchorItem: launcher
    position: root.controller.edge
    pinned: root.controller.settings.pinned || []
    iconOverrides: root.controller.settings.iconOverrides || ({})
    iconReloadRevision: root.host.iconReloadRevision
    onApplicationSelected: desktopId => root.host.pinApplication(desktopId)
    onVisibleChanged: root.controller.interactionBusy = visible || root.controller.resizeActive
  }
  Connections {
    target: root.controller
    function onRefreshed() { root.syncBadges() }
    function onSurfaceInvalidated() { root.closeSurfaces() }
  }
  onVisibleChanged: root.syncBadges()
  Component.onCompleted: root.syncBadges()
  Component.onDestruction: root.closeSurfaces()
}
