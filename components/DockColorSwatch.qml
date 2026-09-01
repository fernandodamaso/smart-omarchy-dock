import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string value
  property color fallbackColor: Color.menu.background
  // Resolved preview color. `value` may be a symbolic @theme.token and is
  // intentionally kept as a string for persistence and selection state.
  property color displayColor: root.fallbackColor
  signal clicked()

  implicitWidth: Style.space(34)
  implicitHeight: Style.space(30)
  radius: Style.cornerRadius
  color: root.displayColor
  borderSpec: Border.controlSpec(
    root.enabled && mouse.containsMouse ? "hover-cursor" : "normal",
    Color.menu.text, Color.accent)
  opacity: root.enabled ? 1 : 0.5

  MouseArea {
    id: mouse

    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    onClicked: root.clicked()
  }
}
