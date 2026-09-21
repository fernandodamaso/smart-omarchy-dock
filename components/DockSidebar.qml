pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Wayland._BackgroundEffect
import qs.Commons
import qs.Ui as Ui
import "DockModel.js" as DockModel
import "DockSidebarInteractionModel.js" as InteractionModel

PanelWindow {
  id: root
  required property var host
  required property var controller
  readonly property var viewport: sidebarViewport
  readonly property var resizeHandle: resizeHandle
  readonly property var contextMenu: sidebarContext
  readonly property var widgetArea: widgets
  readonly property var widgetOverflowButton: widgetOverflow
  readonly property var collapseControl: collapseButton
  property var menuTarget: null
  property var menuAnchor: null
  property var menuMembers: []
  property var menuEntry: null
  readonly property string preferenceFeedback: !host ? "" : host.settingsWriteState === "error"
    ? "Unsaved preferences: " + String(host.settingsWriteError || "Persistence failed")
    : host.settingsWriteState === "saving" ? "Saving preferences" : controller.mutationFeedback
  readonly property string badgeScopeOwner: "smartdock-sidebar:" + String(screen && screen.name || "")
  // Per-panel collapse; other mirrored panels keep their own override.
  readonly property bool panelCollapsed: controller.collapsedFor(screen)
  // Official Lucide panel icons; edge does not flip these names.
  readonly property string collapseIcon: root.panelCollapsed
    ? "panel-left-open" : "panel-left-close"
  // Match viewport inner pad + resize-edge allowance + list scroll gutter so the
  // expanded collapse control shares the monitor/workspace card right edge.
  readonly property real panelInnerPad: Style.space(6)
  readonly property real resizeEdgeAllowance: 8
  readonly property real scrollGutter: 6
  readonly property real expandedHeaderLeftInset: root.panelInnerPad
    + (!root.panelCollapsed && root.controller.edge === "right" ? root.resizeEdgeAllowance : 0)
  readonly property real expandedHeaderRightInset: root.panelInnerPad
    + (!root.panelCollapsed && root.controller.edge === "left" ? root.resizeEdgeAllowance : 0)
    + (!root.panelCollapsed ? root.scrollGutter : 0)
  readonly property var pinStripAdd: pinnedStrip.addPinButton
  // Per-output clamp of the shared expanded-width preference.
  readonly property var panelGeometry: controller.geometryFor(screen)
  objectName: "smartdock-sidebar"
  // Never bind PanelWindow.visible: Quickshell already ties it to screen, and a
  // second binding (even screen!==null or geometry.mapped) loops through
  // width/exclusiveZone and damages the first ListView heading.
  implicitWidth: Math.round(panelGeometry.width)
  anchors.top: true
  anchors.bottom: true
  anchors.left: controller.edge === "left"
  anchors.right: controller.edge === "right"
  // The handle lives inside this total width. Reserve that persistent width once.
  exclusiveZone: panelGeometry.mapped ? implicitWidth : 0
  WlrLayershell.namespace: "smartdock-sidebar"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  color: "transparent"
  // Scoped compositor blur behind this panel only (ext-background-effect-v1).
  // Requires Hyprland protocol support; no desktop-wide layerrule / config edits.
  // Region comes from Quickshell; PendingRegion is the attached property type.
  BackgroundEffect.blurRegion: Region {
    item: root.contentItem
  }

  function syncBadges() {
    if (root.host && root.host.badgeTracker) root.host.badgeTracker.syncWorkspaceScopes(
      root.badgeScopeOwner,
      root.visible ? root.controller.projectionFor(root.panelCollapsed).badgeItems : [])
  }

  function closeSurfaces() {
    sidebarContext.dismiss()
    picker.visible = false
    sidebarViewport.cancelInputs("surface-close")
    root.controller.cancelResize("surface-close")
    widgets.closePopup()
    // A disappearing mirror must not release another panel's widget session.
    root.controller.interactionBusy = root.controller.widgetPopupId !== ""
    if (root.host && root.host.badgeTracker) root.host.badgeTracker.syncWorkspaceScopes(root.badgeScopeOwner, [])
  }

  function openContext(target, anchorItem) {
    if (root.controller.interactionBusy || !anchorItem) return false
    var row = target && target.key ? (root.controller.rowsByKey[target.key] || target) : target
    if (!root.controller.targetIsCurrent(row || target)) return false
    // Nested Herdr rows have no app/window menu.
    if (row && (row.kind === "herdr-agent" || row.kind === "herdr-tab"
        || row.kind === "herdr-state"))
      return false
    // Tab rows have no app menu of their own; reuse the owning window.
    if (row && row.kind === "browser-tab") {
      var parent = row.windowKey ? root.controller.rowsByKey[row.windowKey] : null
      if (!parent || parent.kind !== "window") return false
      row = parent
      target = root.controller.captureTarget(parent.key) || parent
      if (!root.controller.targetIsCurrent(target)) return false
    }
    root.menuTarget = row || target
    root.menuAnchor = anchorItem
    root.menuMembers = InteractionModel.contextMenuMembers(root.menuTarget, anchorItem)
    root.menuEntry = anchorItem.entry || (root.menuTarget.item && root.menuTarget.item.entry) || null
    sidebarContext.open()
    return true
  }

  property Item pickerAnchorItem: null

  function openPinPicker(anchor) {
    if (root.controller.interactionBusy && !picker.visible) return false
    var candidate = anchor && anchor.visible ? anchor : null
    if (!candidate || !candidate.width)
      candidate = (root.pinStripAdd && root.pinStripAdd.visible) ? root.pinStripAdd : launcher
    if (!candidate) return false
    root.pickerAnchorItem = candidate
    picker.open()
    return true
  }

  function refreshContext() {
    if (!sidebarContext.visible) {
      root.refreshPickerAnchor()
      return
    }
    var stripOwned = !!(root.menuAnchor && root.menuAnchor.pinStripOwned === true)
    if (stripOwned) {
      // Pin shelf lives outside the viewport; do not treat it as a scrolled row.
      if (!root.menuAnchor.visible || root.menuAnchor.rowKey !== root.menuTarget.key
          || !root.controller.targetIsCurrent(root.menuTarget))
        sidebarContext.dismiss()
      else if (sidebarContext.anchor && typeof sidebarContext.anchor.updateAnchor === "function")
        sidebarContext.anchor.updateAnchor()
      root.refreshPickerAnchor()
      return
    }
    var point = root.menuAnchor ? sidebarViewport.mapFromItem(root.menuAnchor, 0, 0) : null
    if (!root.menuAnchor || !root.menuAnchor.visible || root.menuAnchor.rowKey !== root.menuTarget.key
        || !root.controller.targetIsCurrent(root.menuTarget) || !point
        || point.y + root.menuAnchor.height <= 0 || point.y >= sidebarViewport.height) {
      sidebarContext.dismiss()
    } else {
      sidebarContext.anchor.updateAnchor()
    }
    root.refreshPickerAnchor()
  }

  function refreshPickerAnchor() {
    if (!picker.visible) return
    var anchor = root.pickerAnchorItem
    var footer = anchor === root.pinStripAdd || anchor === launcher
      || !!(anchor && anchor.pinStripOwned === true)
    var point = null
    if (anchor && anchor.visible && !footer)
      point = sidebarViewport.mapFromItem(anchor, 0, 0)
    var decision = InteractionModel.pickerAnchorDecision(anchor, {
      footer: footer,
      visible: !!(anchor && anchor.visible),
      width: anchor ? anchor.width : 0,
      y: point ? point.y : 0,
      height: anchor ? anchor.height : 0,
      viewportHeight: sidebarViewport.height
    })
    if (decision.action === "dismiss") {
      picker.visible = false
      return
    }
    if (picker.anchor && typeof picker.anchor.updateAnchor === "function")
      picker.anchor.updateAnchor()
  }

  // Ghostty-like translucent tint (background-opacity 0.85). Text/icons stay
  // opaque because only the fill alpha is reduced, not Item.opacity.
  // Omarchy package omarchy 4.0.3-1 (no Git revision; inspected 2026-09-18):
  // qs.Ui BorderSurface/Button/PanelActionButton and qs.Commons Color/Style/
  // Border/Util; first-party BorderSurface usage in plugins/panels/tailscale.
  // Theme-reactive card fills for expanded section chrome (phase 4).
  readonly property QtObject sidebarAppearance: QtObject {
    readonly property color monitorFill: Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035))
    readonly property color workspaceFill: Qt.darker(Color.background, 1.04)
    readonly property color workspaceHoverFill: Qt.tint(workspaceFill, Util.alpha(Color.foreground, 0.09))
    readonly property color activeWorkspaceBorder: Util.alpha(Color.accent, 0.50)
    readonly property real cardRadius: Math.min(3, Style.cornerRadius)
  }

  Ui.BorderSurface {
    id: surface
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.85)
    borderSpec: Border.none()
    clip: true
    // Subtle desktop-facing divider instead of a full bright panel outline.
    Rectangle {
      width: 1
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: root.controller.edge === "left" ? parent.right : undefined
      anchors.left: root.controller.edge === "right" ? parent.left : undefined
      color: Util.alpha(Color.foreground, 0.10)
    }
    Column {
      id: controls
      x: root.panelCollapsed ? Style.space(6) : root.expandedHeaderLeftInset
      width: Math.max(0, surface.width - (root.panelCollapsed
        ? Style.space(12)
        : (root.expandedHeaderLeftInset + root.expandedHeaderRightInset)))
      y: Style.space(0)
      spacing: Style.space(2)
      Item {
        id: headerBar
        width: parent.width
        height: Style.space(44)
        Row {
          id: brandRow
          visible: !root.panelCollapsed
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: collapseButton.left
          anchors.rightMargin: Style.space(8)
            + (widgetOverflow.visible ? widgetOverflow.width + Style.space(8) : 0)
          spacing: 0
          Accessible.role: Accessible.StaticText
          Accessible.name: "SmartDock"
          Text {
            text: "Smart"
            textFormat: Text.PlainText
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            text: "Dock"
            textFormat: Text.PlainText
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
        }
        // Collapse stays centered in rail even when overflow is present; overflow
        // sits immediately left of the collapse control without shifting it.
        // Collapse keeps rail centering via explicit x: conditional anchor
        // attach/detach (horizontalCenter vs right) sticks at a stale offset
        // across hide/show + collapse toggles and never recovers. A pure
        // value binding re-centers on every width/mode change.
        Ui.Button {
          id: collapseButton
          anchors.verticalCenter: parent.verticalCenter
          x: root.panelCollapsed
            ? Math.round((parent.width - width) / 2)
            : parent.width - width
          width: Style.space(30)
          height: Style.space(30)
          iconText: ""
          tooltipText: (root.panelCollapsed ? "Expand sidebar" : "Collapse to icon rail")
            + (root.preferenceFeedback ? " · " + root.preferenceFeedback : "")
          Accessible.role: Accessible.Button
          Accessible.name: tooltipText
          focusable: true
          enabled: !root.controller.interactionBusy
          onClicked: root.controller.requestCollapse(root.screen)
          DockLucideIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            iconName: root.collapseIcon
            iconSize: 14
            tint: Color.foreground
          }
        }
        Ui.Button {
          id: widgetOverflow
          visible: widgets.overflowNeeded
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: collapseButton.left
          anchors.rightMargin: Style.space(8)
          width: visible ? Style.space(30) : 0
          height: Style.space(30)
          iconText: ""
          tooltipText: "Widgets"
          Accessible.role: Accessible.Button
          Accessible.name: "Open widgets"
          focusable: visible
          onClicked: widgets.openOverflow(widgetOverflow)
          DockLucideIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            iconName: "layout-grid"
            iconSize: 14
            tint: Color.foreground
            visible: widgetOverflow.visible
          }
        }
      }
      Text {
        width: parent.width
        visible: root.preferenceFeedback !== "" && !root.panelCollapsed
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
      appearance: root.sidebarAppearance
      panelConnector: String(root.screen && root.screen.name || "")
      panelCollapsed: root.panelCollapsed
      onContextRequested: (target, anchorItem) => root.openContext(target, anchorItem)
      onDismissContextRequested: sidebarContext.dismiss()
      anchors.top: controls.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: widgets.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(6) + (!root.panelCollapsed && root.controller.edge === "right" ? 8 : 0)
      anchors.rightMargin: Style.space(6) + (!root.panelCollapsed && root.controller.edge === "left" ? 8 : 0)
    }
    DockSidebarWidgetArea {
      id: widgets
      controller: root.controller
      panel: root
      anchors.left: sidebarViewport.left
      anchors.right: sidebarViewport.right
      anchors.bottom: pinnedStrip.top
      availableContentHeight: Math.max(0, pinnedStrip.y - controls.y - controls.height)
      windowRowHeight: sidebarViewport.rowHeight
    }
    DockSidebarPinnedStrip {
      id: pinnedStrip
      controller: root.controller
      panel: root
      appearance: root.sidebarAppearance
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: utilities.top
      // No blank pinned gap in rail — strip height and margin both collapse.
      anchors.bottomMargin: root.panelCollapsed ? 0 : Style.space(8)
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10) + (!root.panelCollapsed && root.controller.edge === "left" ? 8 : 0)
    }
    Column {
      id: utilities
      x: root.panelCollapsed ? Style.space(6) : Style.space(10)
      width: Math.max(0, surface.width - (root.panelCollapsed ? Style.space(12) : Style.space(20)))
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(8)
      spacing: Style.space(6)
      Item {
        id: launcher
        width: parent.width
        height: Style.space(36)
        focus: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Applications"
        Ui.BorderSurface {
          anchors.fill: parent
          radius: root.sidebarAppearance.cardRadius
          color: launcherPress.pressed
            ? Style.pressedFillFor(Color.foreground, Color.accent)
            : (launcherHover.hovered || launcher.activeFocus)
              ? root.sidebarAppearance.workspaceHoverFill
              : root.sidebarAppearance.workspaceFill
          borderSpec: launcher.activeFocus
            ? Border.controlSpec("focus", Color.foreground, Color.accent)
            : Border.none()
          enabled: false
        }
        DockLucideIcon {
          id: launcherIcon
          anchors.verticalCenter: parent.verticalCenter
          x: root.panelCollapsed ? (parent.width - width) / 2 : Style.space(11)
          width: 21
          height: 21
          iconName: "layout-grid"
          iconSize: 21
          tint: Util.alpha(Color.foreground, 0.82)
        }
        Text {
          visible: !root.panelCollapsed
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: launcherIcon.right
          anchors.leftMargin: Style.space(11)
          anchors.right: launcherChevron.left
          anchors.rightMargin: Style.space(6)
          text: "Applications"
          textFormat: Text.PlainText
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
        DockLucideIcon {
          id: launcherChevron
          visible: !root.panelCollapsed
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: Style.space(11)
          width: 14
          height: 14
          iconName: "chevron-right"
          iconSize: 14
          tint: Util.alpha(Color.foreground, 0.55)
        }
        HoverHandler { id: launcherHover }
        TapHandler {
          id: launcherPress
          acceptedButtons: Qt.LeftButton
          onTapped: {
            launcher.forceActiveFocus(Qt.MouseFocusReason)
            var command = DockModel.normalizeSetting("controlCommand", root.controller.settings.controlCommand)
            if (command) Quickshell.execDetached(["sh", "-lc", command])
          }
        }
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: {
            launcher.forceActiveFocus(Qt.MouseFocusReason)
            // Pin picker only — never run the desktop launcher on right-click.
            root.openPinPicker(launcher)
          }
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            var command = DockModel.normalizeSetting("controlCommand", root.controller.settings.controlCommand)
            if (command) Quickshell.execDetached(["sh", "-lc", command])
            event.accepted = true
          }
        }
        DockToolTip {
          anchorItem: launcher
          position: "bottom"
          requestedVisible: launcherHover.hovered && !root.controller.rowDragActive
          text: "Launch applications; right-click to add a pinned application"
          fontFamily: Style.font.family
          fontSize: Style.font.bodySmall
        }
      }
      Ui.Button {
        id: trashButton
        visible: root.host.showTrash
        width: parent.width
        height: visible ? Style.space(36) : 0
        text: root.panelCollapsed ? "" : "Trash"
        iconText: ""
        leftAlign: !root.panelCollapsed
        horizontalPadding: root.panelCollapsed ? Style.spacing.controlPaddingX : Style.space(28)
        tooltipText: "Open Trash"
        Accessible.role: Accessible.Button
        Accessible.name: "Open Trash"
        focusable: visible
        onClicked: root.host.openTrash()
        DockLucideIcon {
          anchors.verticalCenter: parent.verticalCenter
          x: root.panelCollapsed ? (parent.width - width) / 2 : Style.space(8)
          width: 14
          height: 14
          iconName: "trash-2"
          iconSize: 14
          tint: Color.foreground
          visible: trashButton.visible
        }
      }
    }
  }

  DockSidebarResizeHandle {
    id: resizeHandle
    controller: root.controller
    screen: root.screen
    panelWidth: root.width
    screenX: root.screen ? Number(root.screen.x || 0) : 0
    screenWidth: root.screen ? Number(root.screen.width || 0) : 0
    affordanceColor: Util.alpha(Color.foreground, 0.28)
    animationsEnabled: root.controller.settings.interfaceAnimationsEnabled !== false
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

  DockContextMenu {
    id: sidebarContext
    anchorItem: root.menuAnchor
    position: root.controller.edge
    autoHide: false
    pinnedItem: root.menuTarget ? (root.controller.settings.pinned || []).map(DockModel.normalizedId)
      .indexOf(DockModel.normalizedId(root.menuTarget.desktopId)) >= 0 : false
    runningToplevels: root.menuMembers
    windowActions: root.host.windowActions
    originOnly: true
    sidebarMode: true
    workspaceContext: root.menuTarget && root.menuTarget.kind === "workspace" ? root.menuTarget : null
    externalTargetValidator: function() { return root.controller.targetIsCurrent(root.menuTarget) }
    interfaceAnimationsEnabled: root.controller.settings.interfaceAnimationsEnabled !== false
    onOpenNewWindow: {
      if (root.menuEntry && typeof root.menuEntry.execute === "function") root.menuEntry.execute()
    }
    onVisibleChanged: root.controller.interactionBusy = visible || picker.visible
      || root.controller.resizeActive || root.controller.rowDragActive || root.controller.widgetPopupId !== ""
    onKeyboardDismissed: root.controller.releaseNavigationFocus()
  }
  Connections {
    target: sidebarViewport.listView
    function onContentYChanged() { root.refreshContext() }
  }

  DockAppPicker {
    id: picker
    anchorItem: root.pickerAnchorItem || root.pinStripAdd || launcher
    position: root.controller.edge
    pinned: root.controller.settings.pinned || []
    iconOverrides: root.controller.settings.iconOverrides || ({})
    iconReloadRevision: root.host.iconReloadRevision
    onApplicationSelected: desktopId => root.host.pinApplication(desktopId)
    onVisibleChanged: {
      root.controller.interactionBusy = visible || sidebarContext.visible || root.controller.resizeActive
        || root.controller.rowDragActive || root.controller.widgetPopupId !== ""
      if (visible) root.controller.closeWidgetPopup()
      if (!visible) root.pickerAnchorItem = null
    }
  }
  Connections {
    target: root.pickerAnchorItem
    ignoreUnknownSignals: true
    function onVisibleChanged() { root.refreshPickerAnchor() }
    function onWidthChanged() { root.refreshPickerAnchor() }
  }
  Connections {
    target: root.controller
    function onRefreshed() { root.syncBadges(); root.refreshContext() }
    function onPinPickerRequested(anchor) { root.openPinPicker(anchor) }
    function onToplevelsChanged() { Qt.callLater(root.refreshContext) }
    function onHyprToplevelsChanged() { Qt.callLater(root.refreshContext) }
    function onScopeRevisionChanged() { Qt.callLater(root.refreshContext) }
    function onWorkspacesChanged() { Qt.callLater(root.refreshContext) }
    function onMonitorsChanged() { Qt.callLater(root.refreshContext) }
    function onMinimizedOriginsChanged() { Qt.callLater(root.refreshContext) }
    function onSettingsChanged() { Qt.callLater(root.refreshContext) }
    function onSurfaceInvalidated() { root.closeSurfaces() }
  }
  onVisibleChanged: { root.syncBadges(); if (!visible) root.closeSurfaces() }
  onPanelCollapsedChanged: root.syncBadges()
  onWidthChanged: Qt.callLater(root.refreshContext)
  onHeightChanged: Qt.callLater(root.refreshContext)
  Component.onCompleted: root.syncBadges()
  Component.onDestruction: root.closeSurfaces()
}