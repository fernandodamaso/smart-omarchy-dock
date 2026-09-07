import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string label
  required property int count
  required property bool expanded
  required property int slotSize
  property bool switchable: true
  default property alias items: appRow.data
  signal activated()

  width: header.width + (expanded ? appRow.width : 0) + 8
  height: slotSize + 6
  radius: Style.cornerRadius
  color: expanded ? Color.background : "transparent"
  border.width: expanded ? 2 : 1
  border.color: expanded ? Color.accent : Color.menu.border

  Item {
    id: header
    width: Math.max(56, title.implicitWidth + 20)
    height: parent.height
    Accessible.role: Accessible.Button
    Accessible.name: root.label + ", " + root.count + " windows"
    Accessible.onPressAction: if (root.switchable) root.activated()
    activeFocusOnTab: root.switchable
    Keys.onReturnPressed: if (root.switchable) root.activated()
    Keys.onSpacePressed: if (root.switchable) root.activated()
    Text {
      id: title
      anchors.centerIn: parent
      text: root.label + "\n" + root.count
      horizontalAlignment: Text.AlignHCenter
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: root.expanded
    }
    TapHandler { enabled: root.switchable; onTapped: root.activated() }
    HoverHandler { cursorShape: root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor }
  }
  Row {
    id: appRow
    x: header.width
    visible: root.expanded
  }
}
