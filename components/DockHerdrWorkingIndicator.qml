import QtQuick
import QtQuick.Shapes
import qs.Commons

// Smooth, wall-clock-synchronised Herdr working spinner. FrameAnimation only
// refreshes the shared phase; inactive/reduced-motion instances retain the arc.
Item {
  id: root

  width: 20
  height: 20
  implicitWidth: 20
  implicitHeight: 20
  activeFocusOnTab: false
  focus: false

  property bool active: false
  property bool animationsEnabled: true
  property color tint: "white"
  readonly property bool animating: frameAnimation.running
  readonly property var arc: arcPath

  function synchronizedRotation() {
    return (Date.now() % 1100) / 1100 * 360
  }

  function updateRotation() {
    if (root.active && root.animationsEnabled)
      root.rotation = root.synchronizedRotation()
    else
      root.rotation = 0
  }

  onActiveChanged: updateRotation()
  onAnimationsEnabledChanged: updateRotation()

  FrameAnimation {
    id: frameAnimation
    running: root.active && root.animationsEnabled
    onTriggered: root.rotation = root.synchronizedRotation()
  }

  Item {
    width: 20
    height: 20
    anchors.centerIn: parent
    scale: Math.min(root.width, root.height) / 20

    Shape {
      objectName: "herdr-working-shape"
      anchors.fill: parent

      ShapePath {
        objectName: "herdr-working-track"
        fillColor: "transparent"
        strokeColor: Util.alpha(Color.foreground, 0.18)
        strokeWidth: 3

        PathMove { x: 10; y: 3.5 }
        PathArc { x: 10; y: 16.5; radiusX: 6.5; radiusY: 6.5 }
        PathArc { x: 10; y: 3.5; radiusX: 6.5; radiusY: 6.5 }
      }

      ShapePath {
        id: arcPath
        objectName: "herdr-working-arc"
        fillColor: "transparent"
        strokeColor: root.tint
        strokeWidth: 3
        capStyle: ShapePath.RoundCap

        PathMove { x: 10; y: 3.5 }
        PathArc { x: 16.5; y: 10; radiusX: 6.5; radiusY: 6.5 }
      }
    }
  }
}
