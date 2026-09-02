import QtQuick
import "DockBadgeModel.js" as BadgeModel

Item {
  id: root

  required property string position
  readonly property real xOffset: BadgeModel.urgentMotionVector(
    root.position, motionState.displacement).x
  readonly property real yOffset: BadgeModel.urgentMotionVector(
    root.position, motionState.displacement).y

  visible: false
  width: 0
  height: 0

  function play() {
    motion.stop()
    motionState.displacement = 0
    motion.start()
  }

  function stop() {
    motion.stop()
    motionState.displacement = 0
  }

  QtObject {
    id: motionState
    property real displacement: 0
  }

  SequentialAnimation {
    id: motion
    loops: 1

    NumberAnimation {
      target: motionState
      property: "displacement"
      from: 0
      to: 5
      duration: 130
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: motionState
      property: "displacement"
      to: 0
      duration: 130
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: motionState
      property: "displacement"
      to: 3
      duration: 130
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: motionState
      property: "displacement"
      to: 0
      duration: 130
      easing.type: Easing.OutCubic
    }
  }
}
