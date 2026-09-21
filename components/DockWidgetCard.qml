pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui
import "widgets"

Item {
  id: root
  required property var controller
  required property string widgetId
  property bool collapsed: false
  property bool dropBefore: false
  property bool dropAfter: false
  property bool interfaceAnimationsEnabled: true
  property bool presentationVisible: true
  property Item presentationClipItem: null
  property real presentationRevision: 0
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

  // Set by the drag-handle MouseArea; parent clears it when beginDrag rejects.
  property bool dragActive: false
  readonly property int dragThreshold: 6

  activeFocusOnTab: true
  implicitHeight: header.height + (collapsed ? 0 : body.implicitHeight)
  height: implicitHeight

  Ui.BorderSurface {
    id: cardSurface
    objectName: "widget-card-surface"
    anchors.fill: parent
    radius: Math.min(4, Style.cornerRadius)
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
    objectName: "widget-card-header"
    width: parent.width
    height: Style.space(34)

    // Header double-click keeps ordinary pointer ownership stealable so the
    // parent ListView can still take vertical drags for scrolling. Reorder
    // stays on the explicit drag handle below, where stealing is intentional.
    MouseArea {
      id: headerToggle
      objectName: "widget-card-header-toggle"
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: dragHandle.left
      acceptedButtons: Qt.LeftButton
      preventStealing: false
      onDoubleClicked: root.toggleRequested()
    }

    Item {
      id: dragHandle
      anchors.right: collapseButton.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: parent.height
      z: 1
      Accessible.role: Accessible.Button
      Accessible.name: "Drag " + root.title + " to reorder"

      WidgetIcon {
        anchors.centerIn: parent
        width: 13
        height: 13
        iconName: "move"
        sizeToken: "xs"
        containerVariant: "plain"
        tint: Util.alpha(Color.foreground, 0.55)
        accessibleName: "Drag affordance"
      }

      MouseArea {
        id: dragMouse
        objectName: "widget-card-drag-handle"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property real startX: 0
        property real startY: 0

        onPressed: function(mouse) {
          startX = mouse.x
          startY = mouse.y
          root.dragActive = false
        }
        onPositionChanged: function(mouse) {
          var dx = mouse.x - startX
          var dy = mouse.y - startY
          var point = mapToItem(null, mouse.x, mouse.y)
          if (!root.dragActive
              && Math.sqrt(dx * dx + dy * dy) >= root.dragThreshold) {
            root.dragActive = true
            root.dragStarted(point.x, point.y)
          }
          if (root.dragActive)
            root.dragMoved(point.x, point.y)
        }
        onReleased: function(mouse) {
          if (!root.dragActive) return
          var point = mapToItem(null, mouse.x, mouse.y)
          root.dragActive = false
          root.dragFinished(point.x, point.y, false)
        }
        onCanceled: {
          if (root.dragActive)
            root.dragFinished(0, 0, true)
          root.dragActive = false
        }
      }
    }

    WidgetIcon {
      id: widgetIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      width: 18
      height: 18
      iconName: root.iconName
      sizeToken: "md"
      containerVariant: "plain"
      tint: Color.foreground
      accessibleName: root.title
    }

    Text {
      id: titleLabel
      objectName: "widget-card-title"
      anchors.left: widgetIcon.right
      anchors.leftMargin: Style.space(7)
      anchors.right: badge.visible ? badge.left : dragHandle.left
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
      anchors.right: dragHandle.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(17, badgeText.implicitWidth + 8)
      height: 17
      radius: 8.5
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
      objectName: "widget-card-collapse"
      anchors.right: parent.right
      anchors.rightMargin: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(24)
      height: Style.space(24)
      z: 2
      iconText: ""
      tooltipText: (root.collapsed ? "Expand " : "Collapse ") + root.title
      Accessible.role: Accessible.Button
      Accessible.name: tooltipText
      focusable: true
      onClicked: root.toggleRequested()

      WidgetIcon {
        anchors.centerIn: parent
        width: 13
        height: 13
        iconName: "chevron-right"
        sizeToken: "xs"
        containerVariant: "plain"
        accessibleName: collapseButton.tooltipText
        rotation: root.collapsed ? 0 : 90
        tint: Color.foreground
      }
    }
  }

  Item {
    id: body
    anchors.top: header.bottom
    width: parent.width
    implicitHeight: widgetView.hasView ? widgetView.implicitHeight + Style.space(16) : Style.space(56)
    height: root.collapsed ? 0 : implicitHeight
    clip: true

    Rectangle {
      anchors.fill: parent
      color: Qt.tint(Color.background, Util.alpha(Color.foreground, 0.025))
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: Util.alpha(Color.foreground, 0.10)
    }

    DockSidebarWidgetView {
      id: widgetView
      controller: root.controller
      widgetId: root.widgetId
      presentation: "expanded"
      popupAnchor: header
      viewEnabled: !root.collapsed
      interfaceAnimationsEnabled: root.interfaceAnimationsEnabled
      presentationVisible: root.presentationVisible && !root.collapsed && root.visible
      presentationClipItem: root.presentationClipItem
      presentationRevision: root.presentationRevision
      x: Style.space(9)
      y: Style.space(7)
      width: Math.max(0, parent.width - Style.space(18))
      height: implicitHeight
    }

    WidgetState {
      id: frameworkState
      visible: !widgetView.hasView
      anchors.fill: parent
      anchors.margins: Style.space(6)
      compact: true
      kind: !root.snapshot ? "unavailable"
        : root.snapshot.status === "loading" ? "loading"
        : root.snapshot.status === "error" ? "error"
        : root.snapshot.status === "stale" ? "stale" : "unavailable"
      title: root.title
      message: kind === "loading" ? "Loading"
        : kind === "error" ? "Widget content failed"
        : kind === "stale" ? "Widget data may be stale" : "Widget content is unavailable"
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
