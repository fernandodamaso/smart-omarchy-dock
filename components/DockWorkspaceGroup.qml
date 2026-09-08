import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string label
  required property int count
  required property bool active
  required property int slotSize
  property bool switchable: true
  property bool urgent: false
  property string position: "bottom"
  property bool presentationVisible: true
  property DockWorkspaceLayout viewport: null
  Connections {
    target: root.viewport
    function onViewportChanged() {
      root.presentationVisible = !root.viewport || root.viewport.containsItem(header)
      headerTooltip.scheduleReanchor()
    }
  }
  readonly property real headerWidth: header.width
  default property alias items: appRow.data
  signal activated()

  width: header.width + appRow.width + (appRow.width > 0 ? 10 : 2)
  height: slotSize + 10
  radius: Math.max(14, Style.cornerRadius)
  color: active ? Util.alpha(Color.accent, 0.08) : Util.alpha(Color.background, 0.32)
  border.width: 1
  border.color: urgent ? Color.urgent : active ? Util.alpha(Color.accent, 0.32) : Util.alpha(Color.foreground, 0.09)
  Behavior on color { ColorAnimation { duration: 140 } }
  Behavior on border.color { ColorAnimation { duration: 140 } }

  Rectangle {
    id: header
    color: Util.alpha(Color.foreground, headerHover.hovered ? 0.06 : 0)
    Behavior on color { ColorAnimation { duration: 140 } }
    radius: root.radius - 1
    border.width: activeFocus ? 1 : 0
    border.color: Color.accent
    x: 1
    y: 1
    width: Math.min(80, Math.max(30, title.implicitWidth + 12))
    height: parent.height - 2
    Accessible.role: Accessible.Button
    Accessible.name: root.label + ", " + root.count + " windows" + (root.urgent ? ", urgent" : "")
    Accessible.onPressAction: if (root.switchable) root.activated()
    activeFocusOnTab: root.switchable
    Keys.onReturnPressed: if (root.switchable) root.activated()
    Keys.onSpacePressed: if (root.switchable) root.activated()
    Text {
      id: title
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -5
      width: Math.min(implicitWidth, parent.width - 8)
      elide: Text.ElideRight
      text: root.label
      horizontalAlignment: Text.AlignHCenter
      color: root.active ? Color.accent : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Math.max(Style.font.body, root.slotSize * 0.32)
      font.bold: true
    }
    TapHandler { enabled: root.switchable; onTapped: root.activated() }
    HoverHandler { id: headerHover; cursorShape: root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: title.bottom
      anchors.topMargin: 5
      width: 5
      height: 5
      radius: 3
      color: root.urgent ? Color.urgent : root.active ? Color.accent : Util.alpha(Color.foreground, 0.32)
    }
    DockToolTip {
      id: headerTooltip
      anchorItem: header
      position: root.position
      requestedVisible: headerHover.hovered && root.presentationVisible
      text: root.label + " — " + root.count + " windows" + (root.urgent ? " — urgent" : "")
      fontFamily: Style.font.family
      fontSize: Style.font.body
    }
  }
  Row {
    id: appRow
    x: header.width + 4
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6
  }
}
