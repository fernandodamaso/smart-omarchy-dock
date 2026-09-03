pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockWindowPreviewModel.js" as PreviewModel

PopupWindow {
  id: root

  required property var windowActions
  required property string position
  required property var visibleItems

  property Item anchorItem: null
  property string desktopId: ""
  property var applicationEntry: null
  property var requestedToplevels: []
  property var members: []
  property bool anchorHovered: false
  property int openDelayMs: 250
  property int closeGraceMs: 180

  readonly property bool pending: openTimer.running
  readonly property bool popupHovered: popupHover.hovered
  readonly property bool interactionActive: root.pending || root.visible
    || root.anchorHovered || root.popupHovered
  readonly property bool orientationHorizontal:
    PreviewModel.orientationHorizontal(root.position)
  readonly property int tileWidth: 232
  readonly property int tileHeight: 176
  readonly property int tilePreviewHeight: 122
  readonly property int tileSpacing: 8
  readonly property int popupPadding: 8
  readonly property int popupGap: 8
  readonly property int desiredWidth: root.orientationHorizontal
    ? root.popupPadding * 2 + root.members.length * root.tileWidth
      + Math.max(0, root.members.length - 1) * root.tileSpacing
    : root.popupPadding * 2 + root.tileWidth
  readonly property int desiredHeight: root.orientationHorizontal
    ? root.popupPadding * 2 + root.tileHeight
    : root.popupPadding * 2 + root.members.length * root.tileHeight
      + Math.max(0, root.members.length - 1) * root.tileSpacing
  readonly property var anchorWindow: root.anchorItem
    ? root.anchorItem.QsWindow.window : null
  readonly property var anchorScreen: root.anchorWindow
    ? root.anchorWindow.screen : null
  readonly property var previewViewport: PreviewModel.previewViewport(
    root.anchorScreen ? root.anchorScreen.width : root.desiredWidth,
    root.anchorScreen ? root.anchorScreen.height : root.desiredHeight,
    root.desiredWidth, root.desiredHeight, root.popupPadding)

  function currentToplevels() {
    return ToplevelManager.toplevels
      ? ToplevelManager.toplevels.values || [] : []
  }

  function liveMembers(values) {
    return PreviewModel.groupedPreviewMembers(values, currentToplevels())
  }

  function visibleTarget() {
    var items = root.visibleItems || []
    for (var i = 0; i < items.length; ++i) {
      var item = items[i]
      if (item && String(item.desktopId || "") === root.desktopId)
        return item
    }
    return null
  }

  function clearSession() {
    root.desktopId = ""
    root.applicationEntry = null
    root.requestedToplevels = []
    root.members = []
    root.anchorHovered = false
    root.anchorItem = null
  }

  function dismissImmediately() {
    openTimer.stop()
    closeTimer.stop()
    root.visible = false
    root.clearSession()
  }

  function reanchor() {
    if (!root.anchorItem || !root.anchor.window) return

    var offset = PreviewModel.previewAnchorOffset(
      root.position, root.anchorItem.width, root.anchorItem.height,
      root.implicitWidth, root.implicitHeight, root.popupGap)
    var point = root.anchor.window.contentItem.mapFromItem(
      root.anchorItem, offset.x, offset.y)
    root.anchor.rect.x = Math.round(point.x)
    root.anchor.rect.y = Math.round(point.y)
  }

  function requestPreview(anchorItem, desktopId, toplevels, applicationEntry) {
    var requested = root.liveMembers(toplevels)
    if (!anchorItem || requested.length < 2) {
      if (root.anchorItem === anchorItem) root.dismissImmediately()
      return
    }

    var switchOpenAnchor = root.visible && root.anchorItem
      && root.anchorItem !== anchorItem
    closeTimer.stop()
    root.anchorItem = anchorItem
    root.desktopId = String(desktopId || "")
    root.applicationEntry = applicationEntry || null
    root.requestedToplevels = requested
    root.members = requested
    root.anchorHovered = true

    if (root.visible || switchOpenAnchor) {
      openTimer.stop()
      root.visible = true
      Qt.callLater(root.reanchor)
    } else {
      openTimer.restart()
    }
  }

  function releasePreview(anchorItem) {
    if (anchorItem && root.anchorItem !== anchorItem) return
    root.anchorHovered = false

    if (!root.visible) {
      root.dismissImmediately()
      return
    }
    if (!root.popupHovered) closeTimer.restart()
  }

  function refreshFromVisibleItems() {
    if (!root.anchorItem || !root.desktopId) return

    var target = root.visibleTarget()
    if (!target) {
      root.dismissImmediately()
      return
    }

    var refreshed = root.liveMembers(target.toplevels)
    if (refreshed.length < 2) {
      root.dismissImmediately()
      return
    }

    root.requestedToplevels = target.toplevels
    root.members = refreshed
    if (root.visible) Qt.callLater(root.reanchor)
  }

  function activateToplevel(toplevel) {
    if (!root.windowActions || !root.windowActions.activateToplevel(toplevel))
      return false
    root.dismissImmediately()
    return true
  }

  function closeToplevel(toplevel) {
    if (!root.windowActions) return false
    // Deliberately keep the popup open here. The compositor owns actual window
    // removal; visibleItemsChanged closes or shrinks the preview only after it
    // observes the resulting toplevel update.
    return root.windowActions.closeToplevel(toplevel)
  }

  implicitWidth: root.previewViewport.width
  implicitHeight: root.previewViewport.height
  color: "transparent"
  grabFocus: false

  anchor {
    window: root.anchorWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1
    onAnchoring: root.reanchor()
  }

  Timer {
    id: openTimer

    interval: root.openDelayMs
    repeat: false
    onTriggered: {
      root.refreshFromVisibleItems()
      if (!root.anchorHovered || !root.anchorItem || root.members.length < 2)
        return
      root.visible = true
      Qt.callLater(root.reanchor)
    }
  }

  Timer {
    id: closeTimer

    interval: root.closeGraceMs
    repeat: false
    onTriggered: {
      if (!root.anchorHovered && !root.popupHovered)
        root.dismissImmediately()
    }
  }

  BorderSurface {
    id: previewSurface

    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec(
      "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

    HoverHandler {
      id: popupHover
      onHoveredChanged: {
        if (hovered) {
          closeTimer.stop()
        } else if (!root.anchorHovered && root.visible) {
          closeTimer.restart()
        }
      }
    }

    Flickable {
      id: previewViewport

      x: root.popupPadding
      y: root.popupPadding
      width: parent.width - root.popupPadding * 2
      height: parent.height - root.popupPadding * 2
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: root.orientationHorizontal ? tileFlow.width : width
      contentHeight: root.orientationHorizontal ? height : tileFlow.height
      interactive: contentWidth > width || contentHeight > height

      WheelHandler {
        target: null
        onWheel: event => {
          var primary = Math.abs(event.angleDelta.y) >= Math.abs(event.angleDelta.x)
            ? event.angleDelta.y : event.angleDelta.x
          if (primary === 0) {
            event.accepted = false
            return
          }

          if (root.orientationHorizontal
              && previewViewport.contentWidth > previewViewport.width) {
            var maxX = previewViewport.contentWidth - previewViewport.width
            previewViewport.contentX = Math.max(
              0, Math.min(maxX, previewViewport.contentX - primary))
            event.accepted = true
          } else if (!root.orientationHorizontal
                     && previewViewport.contentHeight > previewViewport.height) {
            var maxY = previewViewport.contentHeight - previewViewport.height
            previewViewport.contentY = Math.max(
              0, Math.min(maxY, previewViewport.contentY - primary))
            event.accepted = true
          } else {
            event.accepted = false
          }
        }
      }

      Item {
        id: tileFlow

        width: root.orientationHorizontal
          ? root.members.length * root.tileWidth
            + Math.max(0, root.members.length - 1) * root.tileSpacing
          : previewViewport.width
        height: root.orientationHorizontal
          ? previewViewport.height
          : root.members.length * root.tileHeight
            + Math.max(0, root.members.length - 1) * root.tileSpacing

        Repeater {
          model: root.members

          DockWindowPreviewTile {
            required property var modelData
            required property int index

            toplevel: modelData
            windowActions: root.windowActions
            applicationEntry: root.applicationEntry
            captureEnabled: root.visible
            previewWidth: root.tileWidth - 16
            previewHeight: root.tilePreviewHeight
            width: root.tileWidth
            height: root.tileHeight
            x: root.orientationHorizontal
              ? index * (root.tileWidth + root.tileSpacing) : 0
            y: root.orientationHorizontal
              ? 0 : index * (root.tileHeight + root.tileSpacing)
            onActivateRequested: toplevel => root.activateToplevel(toplevel)
            onCloseRequested: toplevel => root.closeToplevel(toplevel)
          }
        }
      }
    }
  }

  onVisibleItemsChanged: root.refreshFromVisibleItems()
  onPositionChanged: if (root.visible) Qt.callLater(root.reanchor)
  onMembersChanged: if (root.visible && root.members.length >= 2)
    Qt.callLater(root.reanchor)
  onAnchorItemChanged: {
    if (!root.anchorItem && root.desktopId !== "")
      root.dismissImmediately()
  }

  Connections {
    target: root.anchorItem
    function onDestroyed() { root.dismissImmediately() }
  }

  Connections {
    target: root.anchorScreen
    function onDestroyed() { root.dismissImmediately() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.refreshFromVisibleItems() }
  }

  Component.onDestruction: root.dismissImmediately()
}
