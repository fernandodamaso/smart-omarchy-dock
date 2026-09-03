import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "DockWindowPreviewModel.js" as PreviewModel

Item {
  id: root

  required property var toplevel
  required property var windowActions
  required property var applicationEntry
  required property bool captureEnabled
  property int previewWidth: 216
  property int previewHeight: 122
  signal activateRequested(var toplevel)
  signal closeRequested(var toplevel)

  readonly property var windowState: root.windowActions
    ? root.windowActions.windowState(root.toplevel) : ({})
  readonly property string titleText: {
    var title = root.toplevel ? String(root.toplevel.title || "").trim() : ""
    if (title) return title
    var appId = root.toplevel ? String(root.toplevel.appId || "").trim() : ""
    if (appId) return appId
    return root.applicationEntry && root.applicationEntry.name
      ? String(root.applicationEntry.name) : "Window"
  }
  readonly property string statusText: PreviewModel.previewStatus(windowState)
  readonly property string iconSource: root.applicationEntry
    && root.applicationEntry.icon
      ? Quickshell.iconPath(root.applicationEntry.icon, true)
      : Quickshell.iconPath("application-x-executable", true)

  BorderSurface {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec(
      "menu", "border", Color.menu.border, Math.max(1, Style.space(1)))
  }

  Rectangle {
    id: previewFrame

    x: 8
    y: 8
    width: parent.width - 16
    height: root.previewHeight
    radius: Math.max(4, Style.cornerRadius - 2)
    color: Color.background
    clip: true

    ScreencopyView {
      id: preview

      anchors.centerIn: parent
      captureSource: root.captureEnabled ? root.toplevel : null
      live: false
      paintCursor: false
      constraintSize: Qt.size(root.previewWidth, root.previewHeight)
      width: hasContent ? Math.min(parent.width, Math.max(1, implicitWidth)) : 0
      height: hasContent ? Math.min(parent.height, Math.max(1, implicitHeight)) : 0
      visible: hasContent

      onCaptureSourceChanged: {
        if (!captureSource || !root.captureEnabled) return
        Qt.callLater(() => {
          if (preview.captureSource && root.captureEnabled)
            preview.captureFrame()
        })
      }
    }

    Text {
      anchors.centerIn: parent
      visible: !preview.hasContent
      text: "Preview unavailable"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  IconImage {
    x: 10
    y: previewFrame.y + previewFrame.height + 10
    width: 26
    height: 26
    source: root.iconSource
    asynchronous: true
  }

  Text {
    x: 44
    y: previewFrame.y + previewFrame.height + 9
    width: parent.width - x - closeButton.width - 18
    text: root.titleText
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    x: 44
    y: previewFrame.y + previewFrame.height + 29
    width: parent.width - x - closeButton.width - 18
    text: root.statusText
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  MouseArea {
    anchors.fill: parent
    anchors.rightMargin: closeButton.width + 10
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activateRequested(root.toplevel)
  }

  Rectangle {
    id: closeButton

    width: 30
    height: 30
    radius: 15
    x: parent.width - width - 8
    y: previewFrame.y + previewFrame.height + 9
    color: closeMouse.containsMouse
      ? Color.menu.selectedBackground : "transparent"
    z: 2

    DockLucideIcon {
      anchors.centerIn: parent
      width: 16
      height: 16
      iconName: "x"
      tint: closeMouse.containsMouse
        ? Color.menu.selectedText : Color.menu.text
    }

    MouseArea {
      id: closeMouse

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested(root.toplevel)
    }
  }

  Component.onDestruction: preview.captureSource = null
}
