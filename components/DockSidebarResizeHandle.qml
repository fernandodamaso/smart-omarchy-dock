import QtQuick

// Eight-logical-pixel inner-edge handle. Pointer motion is converted back to
// screen-global logical X before it reaches the controller, so a right-anchored
// panel can move its window origin without feeding that motion back into resize.
// Keep this file free of qs.* imports so isolated resize QML tests can load it;
// the parent injects a semantic affordance color from Omarchy tokens.
Item {
  id: root
  required property var controller
  property var screen: null
  property real panelWidth: 0
  property real screenX: 0
  property real screenWidth: 0
  property color affordanceColor: Qt.rgba(1, 1, 1, 0.28)
  property bool animationsEnabled: true
  readonly property bool panelCollapsed: controller && screen
    ? controller.collapsedFor(screen) : !!(controller && controller.collapsed)
  readonly property var pointerTarget: resizeDrag.target
  // Resize is a sidebar affordance: require this panel's output to actually be
  // sidebar-mapped rather than a global presentation default.
  readonly property bool resizeEnabled: visible && controller && root.screen
    && controller.connectorIsMapped(root.screen.name) && !root.panelCollapsed
    && (!controller.interactionBusy || controller.resizeActive)
  visible: controller && !root.panelCollapsed

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
    id: hover
    enabled: root.resizeEnabled
    cursorShape: Qt.SizeHorCursor
  }

  Rectangle {
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: hover.hovered || (root.controller && root.controller.resizeActive) ? 2 : 1
    color: hover.hovered || (root.controller && root.controller.resizeActive)
      ? root.affordanceColor : Qt.rgba(0, 0, 0, 0)
    Behavior on color {
      enabled: root.animationsEnabled
      ColorAnimation { duration: 120 }
    }
    Behavior on width {
      enabled: root.animationsEnabled
      NumberAnimation { duration: 120 }
    }
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
        root.controller.beginResize(root.screenGlobalX(centroid.scenePosition.x), root.screen)
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
