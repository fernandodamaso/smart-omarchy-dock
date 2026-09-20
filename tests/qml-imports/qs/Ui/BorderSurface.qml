import QtQuick

Rectangle {
  property var borderSpec: ({})
  readonly property real contentLeftInset: border.width
  readonly property real contentRightInset: border.width
  readonly property real contentTopInset: border.width
  readonly property real contentBottomInset: border.width

  border.width: borderSpec && borderSpec.width !== undefined ? borderSpec.width : 0
  border.color: borderSpec && borderSpec.color !== undefined ? borderSpec.color : "transparent"
}
