pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property bool present: true
  property bool animateEntrance: false
  property bool animationsEnabled: true
  property int exitRevision: 0
  property real naturalWidth: 0
  property real naturalHeight: 0
  property real trailingGap: 0
  property real occupiedProgress: 1
  property real opacityProgress: 1
  property bool motionReady: false
  default property alias content: content.data
  signal exitFinished(int exitRevision)

  width: Math.max(0, (root.naturalWidth + root.trailingGap) * root.occupiedProgress)
  height: root.naturalHeight
  opacity: root.opacityProgress
  clip: root.occupiedProgress < 1 || root.opacityProgress < 1

  function settle() {
    finishTimer.stop()
    var wasReady = motionReady
    motionReady = false
    occupiedProgress = present ? 1 : 0
    opacityProgress = present ? 1 : 0
    motionReady = wasReady
  }

  function retarget() {
    if (!motionReady) return
    finishTimer.stop()
    if (!animationsEnabled) {
      settle()
      return
    }
    if (!present) finishTimer.restart()
    occupiedProgress = present ? 1 : 0
    opacityProgress = present ? 1 : 0
  }

  Component.onCompleted: {
    if (animationsEnabled && ((present && animateEntrance)
        || (!present && exitRevision > 0))) {
      occupiedProgress = present ? 0 : 1
      opacityProgress = present ? 0 : 1
      motionReady = true
      Qt.callLater(retarget)
    } else {
      settle()
      motionReady = true
    }
  }

  onPresentChanged: retarget()
  onAnimationsEnabledChanged: {
    if (!animationsEnabled) settle()
    else retarget()
  }

  Behavior on occupiedProgress {
    enabled: root.motionReady && root.animationsEnabled
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }
  Behavior on opacityProgress {
    enabled: root.motionReady && root.animationsEnabled
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  Item {
    id: content
    width: root.naturalWidth
    height: root.naturalHeight
  }

  Timer {
    id: finishTimer
    interval: 190
    repeat: false
    onTriggered: {
      if (!root.present && root.occupiedProgress <= 0)
        root.exitFinished(root.exitRevision)
    }
  }
}
