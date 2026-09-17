pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui

// A domain row, not a second generic UI kit. Native surfaces/buttons own
// control chrome; SmartDock owns window identity, artwork and badge semantics.
Item {
  id: root
  required property var row
  required property var controller
  property var viewport: null
  readonly property var input: rowInput
  readonly property string desktopId: String(row.desktopId || "")
  readonly property var entry: row.item ? row.item.entry : null
  readonly property var browserProfileService: controller.host ? controller.host.browserProfileService : null
  readonly property string browserProfileKey: profile ? profile.key : ""
  readonly property bool navigable: ["window", "workspace", "application", "launcher"].indexOf(kind) >= 0
  required property bool collapsed
  required property real rowHeight
  readonly property string rowKey: row.key
  readonly property string kind: row.kind
  readonly property bool hasArtwork: kind === "window" || kind === "application" || kind === "launcher"
  readonly property string liveTitle: kind === "window" && row.toplevel
    ? String(row.toplevel.title || "Untitled window") : String(row.label || "")
  readonly property bool focusedWindow: kind === "window" && row.toplevel && row.toplevel.activated === true
  readonly property string accessibleLabel: liveTitle
    + (row.workspaceIdentity ? " · Workspace " + row.workspaceIdentity : "")
    + (row.monitorIdentity ? " · Monitor " + row.monitorIdentity : "")
    + (row.minimized ? " · Minimized" : "") + (row.sticky ? " · Sticky" : "")
  readonly property var profile: hasArtwork ? controller.profileForRow(row) : null
  readonly property real padding: Math.min(Style.space(8), width / 8)
  objectName: "sidebar-row:" + rowKey
  implicitHeight: rowHeight
  height: rowHeight
  clip: true
  Accessible.role: kind === "application" ? Accessible.Button : Accessible.ListItem
  Accessible.name: accessibleLabel
  Keys.forwardTo: root.viewport ? [root.viewport.keyboard] : []
  onActiveFocusChanged: if (activeFocus) root.controller.focusedRowKey = root.rowKey
  opacity: root.controller.dragSession && root.controller.dragSession.target.key === root.rowKey ? 0.4 : 1

  Ui.BorderSurface {
    anchors.fill: parent
    color: root.focusedWindow || root.row.active || root.row.focused
      || (root.controller.dragTarget && root.controller.dragTarget.key === root.rowKey)
      ? Style.selectedFillFor(Color.foreground, Color.accent) : "transparent"
    borderSpec: root.activeFocus ? Border.controlSpec("focus", Color.foreground, Color.accent) : Border.none()
  }
  DockAppIcon {
    id: artwork
    visible: root.hasArtwork
    width: Math.min(32, Math.max(0, root.width - root.padding * 2))
    height: width
    x: root.collapsed ? (root.width - width) / 2 : root.padding
    anchors.verticalCenter: parent.verticalCenter
    desktopId: String(root.row.desktopId || "")
    desktopIcon: root.row.item && root.row.item.entry ? String(root.row.item.entry.icon || "") : ""
    iconOverrides: root.controller.settings.iconOverrides || ({})
    reloadRevision: root.controller.host.iconReloadRevision || 0
    profileKey: root.profile ? root.profile.key : ""
    profileName: root.profile && root.profile.entry ? String(root.profile.entry.name || "") : ""
    profileAvatarPath: root.profile && root.profile.entry ? String(root.profile.entry.avatarPath || "") : ""
    profileBadgesEnabled: root.controller.settings.browserProfileBadgesEnabled !== false
    opacity: root.row.minimized ? 0.65 : 1
  }
  Text {
    id: label
    objectName: "sidebar-label"
    visible: !root.collapsed || !root.hasArtwork
    x: root.collapsed ? root.padding : root.hasArtwork ? artwork.x + artwork.width + root.padding : root.padding
    width: Math.max(0, root.width - x - root.padding - (fold.visible ? fold.width : 0))
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.collapsed && root.kind === "monitor" ? String(root.row.connector || "?")
      : root.collapsed && root.kind === "section" ? (root.row.key === "section:pinned" ? "Pins" : "?")
      : root.liveTitle
    elide: Text.ElideRight
    horizontalAlignment: root.collapsed ? Text.AlignHCenter : Text.AlignLeft
    color: root.kind === "monitor" || root.kind === "section" ? Color.muted
      : root.row.urgent ? Color.urgent : Color.foreground
    font.family: Style.font.family
    font.pixelSize: root.kind === "monitor" || root.kind === "section" ? Style.font.caption : Style.font.bodySmall
    font.bold: root.kind === "workspace" || root.kind === "application"
  }
  DockSidebarRowInput {
    id: rowInput
    anchors.fill: parent
    controller: root.controller
    rowKey: root.rowKey
    enabled: root.navigable
    onFocusRequested: root.forceActiveFocus(Qt.MouseFocusReason)
    onActivated: function(target, control, connector, modifiers) {
      if (root.viewport) root.viewport.activate(target, control, connector, modifiers)
    }
    onContextRequested: target => { if (root.viewport) root.viewport.contextRequested(target, root) }
    onDragMoved: point => { if (root.viewport) root.viewport.moveDrag(point) }
    onDragReleased: point => { if (root.viewport) root.viewport.finishDrag(point) }
  }
  Ui.Button {
    id: fold
    objectName: "sidebar-app-fold"
    visible: root.kind === "application" && !root.collapsed
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(root.rowHeight, root.width / 3)
    height: root.rowHeight
    iconText: root.row.folded ? "▸" : "▾"
    tooltipText: root.row.folded ? "Expand " + root.liveTitle : "Fold " + root.liveTitle
    focusable: false
    enabled: !root.controller.interactionBusy
    onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.controller.toggleApplication(root.rowKey) }
  }
  DockApplicationBadge {
    anchors.right: artwork.right
    anchors.top: artwork.top
    severity: root.hasArtwork ? root.controller.badgeForRow(root.row) : "none"
  }
  // Text-only hover help; never a thumbnail, automatic preview or activation.
  HoverHandler { id: hover }
  Controls.ToolTip {
    visible: hover.hovered && !root.controller.rowDragActive && (root.collapsed || label.truncated)
    delay: 400
    contentItem: Text {
      text: root.accessibleLabel
      textFormat: Text.PlainText
      color: Color.tooltip.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    background: Ui.BorderSurface {
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, Style.normalBorderWidth)
    }
  }
}
