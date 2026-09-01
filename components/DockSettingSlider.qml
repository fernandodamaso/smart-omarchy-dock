import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property int decimals: 0
  property string suffix: ""
  signal previewed(real value)
  signal committed(real value)

  function formatted(value) {
    return Number(value).toFixed(decimals) + suffix
  }

  function snapped(value) {
    var normalized = minimum + Math.round((value - minimum) / step) * step
    return Math.max(minimum, Math.min(maximum, normalized))
  }

  implicitWidth: 420
  implicitHeight: 34

  Text {
    id: labelText

    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 152
    text: root.label
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  PanelSlider {
    id: slider

    anchors.left: labelText.right
    anchors.right: valueText.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    value: root.value
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    integer: root.step >= 1
    trackColor: Style.normalFillFor(Color.menu.text, Color.accent)
    fillColor: Color.accent
    knobColor: Color.menu.text
    tickColor: Color.menu.background
    onMoved: value => root.previewed(root.snapped(value))
    onReleased: value => root.committed(root.snapped(value))
  }

  Text {
    id: valueText

    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: 62
    horizontalAlignment: Text.AlignRight
    text: root.formatted(root.snapped(slider.liveValue))
    color: Util.alpha(Color.menu.text, 0.78)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
