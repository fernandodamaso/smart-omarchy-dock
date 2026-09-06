pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

PopupWindow {
  id: root

  required property Item anchorItem
  required property string position
  required property bool requestedVisible
  required property string text
  required property string fontFamily
  required property real fontSize

  readonly property var tooltipBorderSpec: Border.localOrSurfaceSpec(
    "tooltip", "border", Color.tooltip.border, Color.tooltip.border,
    Style.normalBorderWidth)
  property bool readyToShow: false

  function syncVisibility() {
    if (root.requestedVisible) {
      root.readyToShow = false
      showTimer.restart()
    } else {
      showTimer.stop()
      root.readyToShow = false
    }
  }

  function reanchor() {
    if (!root.anchorItem || !root.anchor.window) return

    var x = root.anchorItem.width / 2 - root.implicitWidth / 2
    var y = root.anchorItem.height + 6
    if (root.position === "bottom")
      y = -root.implicitHeight - 6
    else if (root.position === "left") {
      x = root.anchorItem.width + 6
      y = root.anchorItem.height / 2 - root.implicitHeight / 2
    } else if (root.position === "right") {
      x = -root.implicitWidth - 6
      y = root.anchorItem.height / 2 - root.implicitHeight / 2
    }

    var point = root.anchor.window.contentItem.mapFromItem(root.anchorItem, x, y)
    root.anchor.rect.x = Math.round(point.x)
    root.anchor.rect.y = Math.round(point.y)
  }

  function scheduleReanchor() {
    if (!root.readyToShow) return
    Qt.callLater(root.reanchor)
  }

  visible: root.readyToShow
  color: "transparent"
  implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
  implicitHeight: Math.ceil(tooltipBubble.implicitHeight)
  grabFocus: false
  mask: Region {}

  onRequestedVisibleChanged: root.syncVisibility()
  onPositionChanged: root.scheduleReanchor()
  onImplicitWidthChanged: root.scheduleReanchor()
  onImplicitHeightChanged: root.scheduleReanchor()
  onReadyToShowChanged: root.scheduleReanchor()
  Component.onCompleted: root.syncVisibility()

  Timer {
    id: showTimer

    interval: 400
    repeat: false
    onTriggered: if (root.requestedVisible) root.readyToShow = true
  }

  anchor {
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: root.reanchor()
  }

  Connections {
    target: root.anchorItem

    function onXChanged() { root.scheduleReanchor() }
    function onYChanged() { root.scheduleReanchor() }
    function onWidthChanged() { root.scheduleReanchor() }
    function onHeightChanged() { root.scheduleReanchor() }
  }

  BorderSurface {
    id: tooltipBubble

    implicitWidth: tooltipLabel.implicitWidth
    implicitHeight: tooltipLabel.implicitHeight
    color: Color.tooltip.background
    borderSpec: root.tooltipBorderSpec
    radius: Style.cornerRadius

    Text {
      id: tooltipLabel

      anchors.fill: parent
      textFormat: Text.PlainText
      text: root.text
      color: Color.tooltip.text
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      leftPadding: Border.left(root.tooltipBorderSpec)
        + Style.spacing.controlPaddingX
      rightPadding: Border.right(root.tooltipBorderSpec)
        + Style.spacing.controlPaddingX
      topPadding: Border.top(root.tooltipBorderSpec)
        + Style.spacing.controlPaddingY
      bottomPadding: Border.bottom(root.tooltipBorderSpec)
        + Style.spacing.controlPaddingY
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
}
