import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string label
  required property int count
  required property bool expanded
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

  width: header.width + (expanded ? appRow.width : 0) + 8
  height: slotSize + 6
  radius: Style.cornerRadius
  color: expanded ? Color.background : "transparent"
  border.width: expanded ? 2 : 1
  border.color: urgent ? Color.urgent : expanded ? Color.accent : Color.menu.border

  Item {
    id: header
    width: Math.min(120, Math.max(56, title.implicitWidth + 20))
    height: parent.height
    Accessible.role: Accessible.Button
    Accessible.name: root.label + ", " + root.count + " windows" + (root.urgent ? ", urgent" : "")
    Accessible.onPressAction: if (root.switchable) root.activated()
    activeFocusOnTab: root.switchable
    Keys.onReturnPressed: if (root.switchable) root.activated()
    Keys.onSpacePressed: if (root.switchable) root.activated()
    Text {
      id: title
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - 20)
      elide: Text.ElideRight
      text: root.label + "\n" + root.count
      horizontalAlignment: Text.AlignHCenter
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.expanded
    }
    TapHandler { enabled: root.switchable; onTapped: root.activated() }
    HoverHandler { id: headerHover; cursorShape: root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 4
      width: 5
      height: 5
      radius: 3
      visible: root.urgent
      color: Color.urgent
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
    x: header.width
    visible: root.expanded
  }
}
