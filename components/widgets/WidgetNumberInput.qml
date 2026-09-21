import QtQuick

WidgetTextInput {
  id: root
  property real minimum: -999999
  property real maximum: 999999
  property real step: 1
  property real numericValue: 0

  inputMethodHints: Qt.ImhFormattedNumbersOnly
  validator: DoubleValidator { bottom: root.minimum; top: root.maximum }

  function commitValue() {
    var parsed = Number(text)
    if (!isFinite(parsed)) parsed = root.numericValue
    root.numericValue = Math.max(root.minimum, Math.min(root.maximum, parsed))
    root.text = String(root.numericValue)
  }

  function nudge(delta) {
    root.numericValue = Math.max(root.minimum, Math.min(root.maximum,
      root.numericValue + delta * root.step))
    root.text = String(root.numericValue)
  }

  Component.onCompleted: text = String(root.numericValue)
  onNumericValueChanged: if (!activeFocus) text = String(root.numericValue)
  onEditingFinished: commitValue()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Up) {
      root.nudge(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.nudge(-1)
      event.accepted = true
    }
  }
}