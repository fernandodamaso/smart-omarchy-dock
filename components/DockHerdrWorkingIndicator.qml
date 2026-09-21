import QtQuick

// Small, presentation-only working-state trail for Herdr rows.
// The caller owns runtime visibility eligibility and resolves the live theme tint.
Item {
  id: root

  width: 10
  height: 10
  implicitWidth: 10
  implicitHeight: 10
  activeFocusOnTab: false
  focus: false

  property bool active: false
  property color tint: "white"
  property int phase: 0
  readonly property bool timerRunning: phaseTimer.running

  function trailOpacity(dotIndex) {
    var distance = (root.phase - Number(dotIndex) + 8) % 8
    if (distance === 0) return 1.0
    if (distance === 1) return 0.65
    if (distance === 2) return 0.30
    return 0.0
  }

  onActiveChanged: {
    if (!active) phase = 0
  }

  Timer {
    id: phaseTimer
    interval: 110
    repeat: true
    running: root.active
    onTriggered: root.phase = (root.phase + 1) % 8
  }

  Repeater {
    model: [
      { x: 0, y: 0 },
      { x: 4, y: 0 },
      { x: 8, y: 0 },
      { x: 8, y: 4 },
      { x: 8, y: 8 },
      { x: 4, y: 8 },
      { x: 0, y: 8 },
      { x: 0, y: 4 }
    ]

    delegate: Rectangle {
      required property var modelData
      required property int index

      objectName: "herdr-working-dot-" + String(index)
      x: modelData.x
      y: modelData.y
      width: 2
      height: 2
      radius: 1
      color: root.tint
      opacity: root.active ? root.trailOpacity(index) : 0
      visible: opacity > 0
    }
  }
}
