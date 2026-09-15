import QtQuick
import Quickshell
import qs.Commons
import "components" as Components

ShellRoot {
  id: harness

  readonly property string state: Quickshell.env("SMARTDOCK_PREVIEW_STATE") || "default"
  readonly property string position: Quickshell.env("SMARTDOCK_PREVIEW_POSITION") || "bottom"
  property bool previewStaged: false
  property bool parentFrameSwapped: false
  property bool previewShown: false
  readonly property var defaultActivities: [
    {
      targetId: "30512CE29E2EAEB3E32228BBC7F6DE78",
      serviceId: "whatsapp", label: "WhatsApp",
      profileKey: "Default", domain: "web.whatsapp.com",
      count: 10, windowAddress: "0x1"
    },
    {
      targetId: "055FDF733D6876A727CB8B094DDC277C",
      serviceId: "gmail", label: "Gmail",
      profileKey: "Profile 1", domain: "mail.google.com",
      count: 13, windowAddress: "0x2"
    }
  ]
  readonly property var activities: state === "no-activity" ? []
    : state === "overflow" ? overflowActivities() : defaultActivities
  readonly property var previewMembers: state === "one-window"
    ? [firstWindow] : [firstWindow, secondWindow]

  function overflowActivities() {
    var rows = []
    for (var i = 0; i < 20; ++i) {
      var gmail = i % 2 === 0
      rows.push({
        targetId: (4096 + i).toString(16).toUpperCase(),
        serviceId: gmail ? "gmail" : "whatsapp",
        label: gmail ? "Gmail" : "WhatsApp",
        profileKey: "Profile " + (i + 1),
        domain: gmail ? "mail.google.com" : "web.whatsapp.com",
        count: 24 - i,
        windowAddress: gmail ? "0x2" : "0x1"
      })
    }
    return rows
  }

  function showPreviewWhenReady() {
    if (previewShown || !previewStaged || !parentFrameSwapped)
      return
    previewShown = true
    preview.visible = true
    preview.reanchor()
  }

  QtObject {
    id: actions
    function windowState(toplevel) { return { workspace: "name:Work" } }
    function activateToplevel(toplevel, originOnly) { return true }
    function closeToplevel(toplevel) { return true }
  }

  QtObject {
    id: firstWindow
    property string title: "Chat"
    property string appId: "google-chrome"
  }

  QtObject {
    id: secondWindow
    property string title: "Themes"
    property string appId: "google-chrome"
  }

  FloatingWindow {
    id: anchorWindow
    title: "SmartDock Browser Activity Preview Harness"
    readonly property int anchorSize: Style.space(64)
    readonly property bool horizontal:
      harness.position === "top" || harness.position === "bottom"
    implicitWidth: horizontal
      ? Math.max(anchorSize, preview.implicitWidth)
      : anchorSize + preview.popupGap + preview.implicitWidth
    implicitHeight: horizontal
      ? anchorSize + preview.popupGap + preview.implicitHeight
      : Math.max(anchorSize, preview.implicitHeight)
    color: "transparent"

    Item {
      id: anchorItem
      x: harness.position === "left" ? 0
        : harness.position === "right" ? parent.width - width
        : (parent.width - width) / 2
      y: harness.position === "top" ? 0
        : harness.position === "bottom" ? parent.height - height
        : (parent.height - height) / 2
      width: anchorWindow.anchorSize
      height: width
      property string presentationId: "mock/chrome"
      property var identityToplevel: null
      property bool originOnly: false
      property var previewActivities: harness.activities

      Rectangle {
        anchors.fill: parent
        radius: Style.space(16)
        color: Color.menu.background
        border.width: Style.spacing.hairline
        border.color: Color.menu.border
      }
    }

    onClosed: Qt.quit()
  }

  Connections {
    target: anchorWindow.contentItem
      ? anchorWindow.contentItem.Window.window : null
    enabled: !harness.previewShown
    function onFrameSwapped() {
      harness.parentFrameSwapped = true
      harness.showPreviewWhenReady()
    }
  }

  Components.DockWindowPreview {
    id: preview
    windowActions: actions
    position: harness.position
    visibleItems: []
    // Direct mock members have no visible-item owner to refresh from.
    desktopId: ""
    previewCaptureEnabled: false
    previewArtwork: ({
      "Chat": Qt.resolvedUrl("assets/chat-preview.svg"),
      "Themes": Qt.resolvedUrl("assets/themes-preview.svg")
    })
    onActivityRequested: activity => console.log(
      "browser-activity-preview: clicked", activity.targetId)
  }

  Component.onCompleted: {
    preview.anchorItem = anchorItem
    preview.applicationEntry = {
      name: "Google Chrome",
      icon: "google-chrome"
    }
    preview.members = harness.previewMembers
    preview.anchorHovered = true
    previewStaged = true
    harness.showPreviewWhenReady()
  }
}
