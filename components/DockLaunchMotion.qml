import QtQuick

Item {
  id: root

  required property string position
  property bool active: false
  property bool animationsEnabled: true
  property real bounceDistance: 6
  readonly property real xOffset: vectorFor(root.position, motionState.displacement).x
  readonly property real yOffset: vectorFor(root.position, motionState.displacement).y
  readonly property bool running: motion.running

  visible: false
  width: 0
  height: 0

  function vectorFor(position, displacement) {
    switch (String(position || "")) {
    case "top":
      return ({ x: 0, y: displacement })
    case "left":
      return ({ x: displacement, y: 0 })
    case "right":
      return ({ x: -displacement, y: 0 })
    case "bottom":
    default:
      return ({ x: 0, y: -displacement })
    }
  }

  function restart() {
    motion.stop()
    motionState.displacement = 0
    if (root.active && root.animationsEnabled)
      motion.start()
  }

  function stop() {
    motion.stop()
    motionState.displacement = 0
  }

  Component.onCompleted: if (root.active && root.animationsEnabled) root.restart()
  onActiveChanged: {
    if (root.active) root.restart()
    else root.stop()
  }
  onAnimationsEnabledChanged: {
    if (root.active && root.animationsEnabled) root.restart()
    else root.stop()
  }

  QtObject {
    id: motionState
    property real displacement: 0
  }

  SequentialAnimation {
    id: motion
    loops: Animation.Infinite

    NumberAnimation {
      target: motionState
      property: "displacement"
      from: 0
      to: root.bounceDistance
      duration: 110
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: motionState
      property: "displacement"
      to: 0
      duration: 130
      easing.type: Easing.InCubic
    }
    NumberAnimation {
      target: motionState
      property: "displacement"
      to: root.bounceDistance * 0.65
      duration: 90
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: motionState
      property: "displacement"
      to: 0
      duration: 110
      easing.type: Easing.InCubic
    }
    PauseAnimation { duration: 240 }
  }
}
