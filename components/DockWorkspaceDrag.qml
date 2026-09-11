import QtQuick

// Scene-local gesture state only. The existing host owns all window actions.
Item {
  id: root

  required property var windowActions
  property var targetAtScenePoint: function(point) { return "" }
  property bool active: false
  property Item sourceItem: null
  property var members: []
  property point pointerScene: Qt.point(0, 0)
  property string hoveredIdentity: ""
  property url iconSource: ""
  property int iconSize: 42
  property color accent: "#808080"
  property color background: "#303030"
  property color foreground: "white"
  property string fontFamily: ""
  property int fontSize: 12
  property int liveCount: 0
  property bool finishing: false
  property bool ending: false
  signal aboutToBegin()
  signal ended()

  function validPoint(point) {
    return point && isFinite(point.x) && isFinite(point.y)
  }

  function begin(source, toplevels, scenePoint, sourceIcon) {
    if (active || finishing || ending || !source || !windowActions
        || !validPoint(scenePoint)) return false
    var captured = windowActions.captureWorkspaceMove(toplevels)
    if (!captured || captured.length === 0) return false
    aboutToBegin()
    sourceItem = source
    members = captured
    liveCount = captured.length
    iconSource = sourceIcon || ""
    pointerScene = scenePoint
    active = true
    try {
      updatePointer(scenePoint)
      return active
    } catch (error) {
      cancel("begin failed")
      throw error
    }
  }

  function updatePointer(scenePoint) {
    if (!active || ending) return false
    if (!validPoint(scenePoint) || !sourceItem || !windowActions) {
      cancel("invalid session")
      return false
    }
    pointerScene = scenePoint
    try {
      var live = windowActions.workspaceMoveMembers(members)
      if (!live || live.length === 0) {
        cancel("captured members unavailable")
        return false
      }
      liveCount = live.length
      var identity = targetAtScenePoint(scenePoint) || ""
      var destination = windowActions.resolveWorkspaceDropTarget(identity)
      hoveredIdentity = destination
        && windowActions.workspaceMoveWouldChange(members, destination.identity)
        ? destination.identity : ""
      return hoveredIdentity !== ""
    } catch (error) {
      cancel("target lookup failed")
      throw error
    }
  }

  function finish(scenePoint) {
    if (!active || finishing || ending) return false
    finishing = true
    try {
      updatePointer(scenePoint)
      if (!active || !hoveredIdentity) return false
      return windowActions.moveCapturedToplevels(members, hoveredIdentity)
    } finally {
      endSession()
      finishing = false
    }
  }

  function endSession() {
    if (!active || ending) return
    ending = true
    active = false
    sourceItem = null
    members = []
    liveCount = 0
    pointerScene = Qt.point(0, 0)
    hoveredIdentity = ""
    iconSource = ""
    ended()
    ending = false
  }

  function cancel(reason) {
    endSession()
  }

  onSourceItemChanged: if (active && !sourceItem) cancel("source destroyed")
  onWindowActionsChanged: if (active) cancel("controller replaced")
  onEnabledChanged: if (!enabled) cancel("disabled")
  Component.onDestruction: cancel("scene destroyed")

  Item {
    id: proxy
    objectName: "workspaceDragProxy"
    visible: root.active
    enabled: false
    z: 100
    width: root.iconSize
    height: root.iconSize
    readonly property point pointerLocal: root.mapFromItem(
      null, root.pointerScene.x, root.pointerScene.y)
    x: pointerLocal.x - width / 2
    y: pointerLocal.y - height / 2
    opacity: 0.85

    Image {
      anchors.fill: parent
      source: root.iconSource
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }
    Rectangle {
      visible: root.liveCount > 1
      width: Math.max(18, countLabel.implicitWidth + 8)
      height: 18
      radius: height / 2
      x: parent.width - width / 2
      y: -height / 2
      color: root.accent
      border.color: root.background
      border.width: 1
      Text {
        id: countLabel
        anchors.centerIn: parent
        text: String(root.liveCount)
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: true
        color: root.foreground
      }
    }
  }
}
