import QtQuick

// Eight-logical-pixel inner-edge handle. Pointer motion is converted back to
// screen-global logical X before it reaches the controller, so a right-anchored
// panel can move its window origin without feeding that motion back into resize.
Item {
  id: root
  required property var controller
  property real panelWidth: 0
  property real screenX: 0
  property real screenWidth: 0
  readonly property var pointerTarget: resizeDrag.target
  readonly property bool resizeEnabled: visible && controller
    && controller.mode === "sidebar" && !controller.collapsed
    && (!controller.interactionBusy || controller.resizeActive)
  visible: controller && !controller.collapsed

  function screenGlobalX(sceneX) {
    var origin = root.screenX
    if (root.controller && root.controller.edge === "right")
      origin += root.screenWidth - root.panelWidth
    return origin + Number(sceneX || 0)
  }

  function cancelActiveResize(reason) {
    if (root.controller) root.controller.cancelResize(reason || "grab-loss")
  }

  HoverHandler {
    enabled: root.resizeEnabled
    cursorShape: Qt.SizeHorCursor
  }

  DragHandler {
    id: resizeDrag
    target: null
    acceptedButtons: Qt.LeftButton
    enabled: root.resizeEnabled
    property bool cancelledByGrabLoss: false

    onActiveChanged: {
      if (active) {
        cancelledByGrabLoss = false
        root.controller.beginResize(root.screenGlobalX(centroid.scenePosition.x))
      } else if (root.controller && root.controller.resizeActive && !cancelledByGrabLoss) {
        root.controller.finishResize(false)
      }
    }

    onTranslationChanged: {
      if (active && root.controller && root.controller.resizeActive)
        root.controller.updateResize(root.screenGlobalX(centroid.scenePosition.x))
    }

    onGrabChanged: function(transition, point) {
      if (transition === PointerDevice.CancelGrabExclusive) {
        cancelledByGrabLoss = true
        root.cancelActiveResize("grab-loss")
      }
    }
  }
}
