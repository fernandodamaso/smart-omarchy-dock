pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui

Item {
  id: root
  required property var controller
  required property string widgetId
  property bool collapsed: false
  property bool dropBefore: false
  property bool dropAfter: false
  readonly property var snapshot: controller.widgetView(widgetId)
  readonly property var descriptor: snapshot ? snapshot.descriptor : null
  readonly property string title: descriptor && descriptor.label ? String(descriptor.label) : widgetId
  readonly property string iconName: descriptor && descriptor.iconName ? String(descriptor.iconName) : "layout-grid"
  readonly property int badgeCount: snapshot && snapshot.data && typeof snapshot.data.count === "number"
    ? Math.max(0, Math.floor(snapshot.data.count)) : 0
  signal toggleRequested()
  signal removeRequested()
  signal dragStarted(real sceneX, real sceneY)
  signal dragMoved(real sceneX, real sceneY)
  signal dragFinished(real sceneX, real sceneY, bool cancelled)

  activeFocusOnTab: true
  implicitHeight: header.height + (collapsed ? 0 : body.implicitHeight)
  height: implicitHeight

  Ui.BorderSurface {
    anchors.fill: parent
    radius: Math.min(3, Style.cornerRadius)
    color: root.activeFocus || cardHover.hovered || cardContext.pressed
      ? Qt.tint(Color.background, Util.alpha(Color.foreground, 0.09))
      : Qt.darker(Color.background, 1.04)
    borderSpec: root.activeFocus
      ? Border.controlSpec("focus", Color.foreground, Color.accent)
      : Border.none()
  }

  Rectangle {
    visible: root.dropBefore
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 2
    color: Color.accent
  }

  Rectangle {
    visible: root.dropAfter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 2
    color: Color.accent
  }

  HoverHandler { id: cardHover }

  TapHandler {
    id: cardContext
    acceptedButtons: Qt.RightButton
    onTapped: cardMenu.popup()
  }

  Item {
    id: header
    width: parent.width
    height: Style.space(40)

    Item {
      id: dragHandle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: parent.height
      Accessible.role: Accessible.Button
      Accessible.name: "Drag " + root.title + " to reorder"

      DockLucideIcon {
        anchors.centerIn: parent
        width: 14
        height: 14
        iconName: "move"
        iconSize: 14
        tint: Util.alpha(Color.foreground, 0.55)
      }

      MouseArea {
        id: dragMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property bool dragging: false
        property real startY: 0

        onPressed: function(mouse) { startY = mouse.y }
        onPositionChanged: function(mouse) {
          var point = mapToItem(null, mouse.x, mouse.y)
          if (!dragging && Math.abs(mouse.y - startY) >= 5) {
            dragging = true
            root.dragStarted(point.x, point.y)
          }
          if (dragging) root.dragMoved(point.x, point.y)
        }
        onReleased: function(mouse) {
          if (!dragging) return
          var point = mapToItem(null, mouse.x, mouse.y)
          dragging = false
          root.dragFinished(point.x, point.y, false)
        }
        onCanceled: {
          if (dragging) root.dragFinished(0, 0, true)
          dragging = false
        }
      }
    }

    DockLucideIcon {
      id: widgetIcon
      anchors.left: dragHandle.right
      anchors.verticalCenter: parent.verticalCenter
      width: 18
      height: 18
      iconName: root.iconName
      iconSize: 18
      tint: Color.foreground
    }

    Text {
      anchors.left: widgetIcon.right
      anchors.leftMargin: Style.space(8)
      anchors.right: badge.visible ? badge.left : collapseButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Rectangle {
      id: badge
      visible: root.badgeCount > 0
      anchors.right: collapseButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(18, badgeText.implicitWidth + 8)
      height: 18
      radius: 9
      color: Color.accent
      Accessible.role: Accessible.StaticText
      Accessible.name: root.badgeCount + " notifications"

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: root.badgeCount > 99 ? "99+" : String(root.badgeCount)
        textFormat: Text.PlainText
        color: Color.background
        font.family: Style.font.family
        font.pixelSize: 9
        font.bold: true
      }
    }

    Ui.Button {
      id: collapseButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: Style.space(28)
      iconText: ""
      tooltipText: (root.collapsed ? "Expand " : "Collapse ") + root.title
      Accessible.role: Accessible.Button
      Accessible.name: tooltipText
      focusable: true
      onClicked: root.toggleRequested()

      DockLucideIcon {
        anchors.centerIn: parent
        width: 13
        height: 13
        iconName: "chevron-right"
        iconSize: 13
        rotation: root.collapsed ? 0 : 90
        tint: Color.foreground
      }
    }
  }

  Item {
    id: body
    anchors.top: header.bottom
    width: parent.width
    implicitHeight: widgetView.hasView ? widgetView.implicitHeight + Style.space(12) : Style.space(34)
    height: root.collapsed ? 0 : implicitHeight
    clip: true

    DockSidebarWidgetView {
      id: widgetView
      controller: root.controller
      widgetId: root.widgetId
      presentation: "expanded"
      popupAnchor: header
      viewEnabled: !root.collapsed
      x: Style.space(8)
      y: Style.space(6)
      width: Math.max(0, parent.width - Style.space(16))
      height: Math.min(240, implicitHeight)
    }

    Text {
      visible: !widgetView.hasView
      anchors.centerIn: parent
      text: !root.snapshot ? "Unavailable" : String(root.snapshot.status || "Unavailable")
      textFormat: Text.PlainText
      color: Util.alpha(Color.foreground, 0.68)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      Accessible.role: Accessible.StaticText
      Accessible.name: root.title + ": " + text
    }
  }

  Controls.Menu {
    id: cardMenu
    Controls.MenuItem {
      text: "Remove from Widgets"
      onTriggered: root.removeRequested()
    }
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      root.toggleRequested()
      event.accepted = true
    }
  }
}
