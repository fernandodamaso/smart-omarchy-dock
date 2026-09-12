import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string label
  readonly property string displayLabel: /^[0-9]+$/.test(root.label) ? root.label : "*"
  required property int count
  required property bool active
  required property int slotSize
  property bool switchable: true
  property bool urgent: false
  property bool dropHighlighted: false
  property bool windowDragActive: false
  property string position: "bottom"
  property bool presentationVisible: true
  property bool animationsEnabled: true
  property var applicationModel: null
  property Component applicationDelegate: null
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

  readonly property real appOccupancy: Math.min(1, appRow.width / Math.max(1, slotSize))
  width: header.width + appRow.width + 2 + 14 * appOccupancy
  height: slotSize + 10
  radius: Math.max(12, Style.cornerRadius - 4)
  color: dropHighlighted ? Util.alpha(Color.accent, 0.24)
    : active ? Util.alpha(Color.accent, workspaceHover.hovered ? 0.13 : 0.10) : Util.alpha(Color.background, workspaceHover.hovered ? 0.42 : 0.26)
  border.width: 1
  border.color: dropHighlighted ? Color.accent
    : urgent ? Color.urgent : active ? Util.alpha(Color.accent, 0.50) : Util.alpha(Color.foreground, workspaceHover.hovered ? 0.14 : 0.07)
  Behavior on color {
    enabled: root.animationsEnabled
    ColorAnimation { duration: 160 }
  }
  Behavior on border.color {
    enabled: root.animationsEnabled
    ColorAnimation { duration: 160 }
  }
  HoverHandler { id: workspaceHover }

  Rectangle {
    id: header
    color: "transparent"
    radius: Math.max(10, root.radius - 2)
    border.width: activeFocus ? 1 : 0
    border.color: Color.accent
    x: 1
    y: 1
    width: Math.min(80, Math.max(30, title.implicitWidth + 12))
    height: parent.height - 2
    Accessible.role: Accessible.Button
    Accessible.name: root.label + ", " + root.count + " windows" + (root.urgent ? ", urgent" : "")
    Accessible.onPressAction: if (root.switchable && !root.windowDragActive) root.activated()
    activeFocusOnTab: root.switchable && !root.windowDragActive
    Keys.onReturnPressed: if (root.switchable && !root.windowDragActive) root.activated()
    Keys.onSpacePressed: if (root.switchable && !root.windowDragActive) root.activated()
    Text {
      id: title
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - 8)
      elide: Text.ElideRight
      text: root.displayLabel
      horizontalAlignment: Text.AlignHCenter
      color: root.active ? Color.accent : Color.foreground
      Behavior on color {
        enabled: root.animationsEnabled
        ColorAnimation { duration: 160 }
      }
      font.family: Style.font.family
      font.pixelSize: Math.max(Style.font.body, root.slotSize * 0.38)
      font.bold: true
    }
    TapHandler { enabled: root.switchable && !root.windowDragActive; onTapped: root.activated() }
    HoverHandler { id: headerHover; cursorShape: root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    DockToolTip {
      id: headerTooltip
      anchorItem: header
      position: root.position
      requestedVisible: headerHover.hovered && root.presentationVisible && !root.windowDragActive
      text: root.label + " — " + root.count + " windows" + (root.urgent ? " — urgent" : "")
      fontFamily: Style.font.family
      fontSize: Style.font.body
    }
  }

  Rectangle {
    id: groupDivider
    x: header.width + 5
    visible: root.appOccupancy > 0
    opacity: root.appOccupancy
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: Math.max(18, parent.height * 0.48)
    radius: 1
    color: Util.alpha(Color.foreground, root.active ? 0.13 : 0.09)
  }

  Row {
    id: appRow
    x: header.width + 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.applicationModel
      delegate: root.applicationDelegate
    }
  }
}
