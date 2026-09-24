import QtQuick
import QtQuick.Shapes
import qs.Commons
import "DockHerdrModel.js" as HerdrModel

Item {
  id: root

  property var status: ""
  property real size: 24
  property color ringColor: Color.background
  property bool animationsEnabled: true
  readonly property string normalizedStatus: HerdrModel.normalizeStatus(status)
  readonly property bool marked: normalizedStatus === "blocked"
    || normalizedStatus === "working" || normalizedStatus === "done"
  readonly property bool pulsing: pulseAnimation.running

  width: size
  height: size
  implicitWidth: 24
  implicitHeight: 24
  visible: marked
  activeFocusOnTab: false
  focus: false

  DockHerdrStatusColors { id: statusColors }

  Rectangle {
    id: pulseRing
    objectName: "herdr-status-pulse"
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    border.width: 2
    border.color: statusColors.color("blocked")
    opacity: 0
    visible: root.normalizedStatus === "blocked" && root.animationsEnabled
  }

  SequentialAnimation {
    id: pulseAnimation
    running: root.normalizedStatus === "blocked" && root.animationsEnabled
    loops: Animation.Infinite
    ParallelAnimation {
      NumberAnimation {
        target: pulseRing
        property: "scale"
        from: 1
        to: (root.size + 14) / root.size
        duration: 800
        easing.type: Easing.InOutQuad
      }
      NumberAnimation {
        target: pulseRing
        property: "opacity"
        from: 0.55
        to: 0
        duration: 800
        easing.type: Easing.InOutQuad
      }
    }
    PauseAnimation { duration: 800 }
  }

  Rectangle {
    objectName: "herdr-status-disc"
    anchors.fill: parent
    radius: width / 2
    color: root.normalizedStatus === "working"
      ? Color.background : statusColors.color(root.normalizedStatus)
    border.width: 3
    border.color: root.ringColor
  }

  DockHerdrWorkingIndicator {
    objectName: "herdr-status-working-spinner"
    visible: root.normalizedStatus === "working"
    active: visible
    animationsEnabled: root.animationsEnabled
    tint: statusColors.color("working")
    width: Math.max(0, root.size - 6)
    height: width
    anchors.centerIn: parent
  }

  Text {
    objectName: "herdr-status-blocked-glyph"
    visible: root.normalizedStatus === "blocked"
    anchors.centerIn: parent
    text: "!"
    color: Color.background
    font.family: Style.font.family
    font.pixelSize: Math.max(10, root.size * 0.54)
    font.bold: true
    renderType: Text.NativeRendering
  }

  Shape {
    id: doneGlyph
    objectName: "herdr-status-done-glyph"
    visible: root.normalizedStatus === "done"
    width: root.size * 0.50
    height: root.size * 0.42
    anchors.centerIn: parent

    ShapePath {
      fillColor: "transparent"
      strokeColor: Color.background
      strokeWidth: 3
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: 0
      startY: doneGlyph.height * 0.52
      PathLine { x: doneGlyph.width * 0.32; y: doneGlyph.height * 0.84 }
      PathLine { x: doneGlyph.width; y: 0 }
    }
  }
}
