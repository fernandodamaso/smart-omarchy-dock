pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockTrashModel.js" as TrashModel

Item {
  id: root

  required property int trashItemCount
  required property bool trashStateKnown
  required property int slotSize
  required property int iconSize
  required property real magnification
  required property real magnificationRadius
  required property bool hoverGlowEnabled
  required property real hoverGlowOpacity
  required property real hoverGlowRadius
  required property real pointerPosition
  required property string position
  required property bool vertical
  signal openRequested()
  signal emptyRequested()
  signal contextMenuVisibilityChanged(bool visible)

  readonly property real itemCenter: vertical ? y + height / 2 : x + width / 2
  readonly property real distance: Math.abs(pointerPosition - itemCenter)
  readonly property real influence: pointerPosition < -1000
    ? 0
    : Math.exp(-(distance * distance) / (magnificationRadius * magnificationRadius))
  readonly property real iconScale: 1 + (magnification - 1) * influence

  width: vertical ? slotSize + 6 : slotSize
  height: vertical ? slotSize : slotSize + 6

  Item {
    id: iconContainer

    x: (root.width - root.iconSize) / 2
    y: (root.height - root.iconSize) / 2
    width: root.iconSize
    height: root.iconSize
    scale: root.iconScale
    transformOrigin: root.position === "top"
      ? Item.Top
      : root.position === "left"
        ? Item.Left
        : root.position === "right" ? Item.Right : Item.Bottom

    Behavior on scale {
      NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    RectangularShadow {
      id: hoverGlow

      anchors.fill: parent
      radius: Math.min(width, height) * 0.34
      blur: Math.max(8, root.iconSize * root.hoverGlowRadius / 100)
      spread: Math.max(1, root.iconSize * 0.06)
      offset: Qt.vector2d(0, 0)
      color: Color.accent
      opacity: root.hoverGlowEnabled && trashHover.hovered
        ? root.hoverGlowOpacity : 0
      z: -1

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    DockLucideIcon {
      anchors.fill: parent
      anchors.margins: Math.max(2, root.iconSize * 0.08)
      iconName: "trash-2"
      tint: "#ffffff"
    }
  }

  PanelToolTip {
    visible: trashHover.hovered && !trashMenu.visible
    text: root.trashStateKnown
      ? DockModel.trashTooltip(root.trashItemCount)
      : "Trash — checking…"
    fontFamily: Style.font.family
    fontSize: Style.font.body
  }

  HoverHandler {
    id: trashHover
    cursorShape: Qt.PointingHandCursor
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: root.openRequested()
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: trashMenu.open()
  }

  PopupWindow {
    id: trashMenu

    property bool confirmingEmpty: false

    function open() {
      confirmingEmpty = false
      visible = true
    }

    function dismiss() {
      confirmingEmpty = false
      visible = false
    }

    implicitWidth: confirmingEmpty ? 380 : 200
    implicitHeight: confirmingEmpty ? 190 : 132
    color: "transparent"
    grabFocus: true

    onVisibleChanged: root.contextMenuVisibilityChanged(visible)

    Connections {
      target: root

      function onVisibleChanged() {
        if (TrashModel.shouldDismissMenu(root.visible, trashMenu.visible))
          trashMenu.dismiss()
      }
    }

    anchor {
      window: root.QsWindow.window
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        if (!root.QsWindow.window) return

        var x = root.width / 2 - trashMenu.implicitWidth / 2
        var y = root.height + 8
        if (root.position === "bottom")
          y = -trashMenu.implicitHeight - 8
        else if (root.position === "left") {
          x = root.width + 8
          y = root.height / 2 - trashMenu.implicitHeight / 2
        } else if (root.position === "right") {
          x = -trashMenu.implicitWidth - 8
          y = root.height / 2 - trashMenu.implicitHeight / 2
        }

        var window = root.QsWindow.window
        var point = window.contentItem.mapFromItem(root, x, y)
        point.x = Math.max(8,
          Math.min(point.x, window.width - trashMenu.implicitWidth - 8))
        point.y = Math.max(8,
          Math.min(point.y, window.height - trashMenu.implicitHeight - 8))
        trashMenu.anchor.rect.x = Math.round(point.x)
        trashMenu.anchor.rect.y = Math.round(point.y)
      }
    }

    BorderSurface {
      anchors.fill: parent
      focus: true
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec(
        "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

      Keys.onPressed: event => {
        if (trashMenu.confirmingEmpty && emptyConfirm.handleKey(event)) {
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          trashMenu.dismiss()
          event.accepted = true
        }
      }

      Column {
        visible: !trashMenu.confirmingEmpty
        anchors.fill: parent
        anchors.margins: 6

        Text {
          width: parent.width
          height: 32
          leftPadding: 12
          verticalAlignment: Text.AlignVCenter
          text: "Trash"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        DockMenuAction {
          width: parent.width
          iconName: "folder-open"
          text: "Open Trash"
          onTriggered: {
            trashMenu.dismiss()
            root.openRequested()
          }
        }

        DockMenuAction {
          width: parent.width
          iconName: "trash-2"
          text: "Empty Trash…"
          enabled: root.trashStateKnown && root.trashItemCount > 0
          onTriggered: trashMenu.confirmingEmpty = true
        }
      }

      ConfirmDialog {
        id: emptyConfirm

        anchors.fill: parent
        opened: trashMenu.confirmingEmpty
        message: "Empty Trash? These items cannot be restored."
        confirmText: "Empty Trash"
        background: Color.menu.background
        foreground: Color.menu.text
        selectedText: Color.accent
        onCanceled: trashMenu.confirmingEmpty = false
        onConfirmed: {
          trashMenu.dismiss()
          root.emptyRequested()
        }
      }
    }
  }
}
