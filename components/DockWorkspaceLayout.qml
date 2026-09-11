pragma ComponentBehavior: Bound

import QtQuick

// Owns the bounded horizontal content area; utility icons stay in the host.
Item {
  id: root

  default property alias items: content.data
  property real contentPadding: 12
  property real rowY: 0
  property real buttonSize: 24
  property color foreground: "white"
  property color background: "#303030"
  property color accent: "#808080"
  property bool animationsEnabled: true
  property bool windowDragActive: false
  property point dragScenePosition: Qt.point(0, 0)
  property int dragNavigationDirection: 0
  readonly property real desiredWidth: content.implicitWidth + contentPadding * 2
  readonly property bool overflowing: desiredWidth > width
  readonly property real navigationWidth: overflowing ? Math.min(buttonSize, width / 3) : 0
  readonly property real viewportWidth: viewport.width
  readonly property real maximumOffset: Math.max(0, viewport.contentWidth - viewport.width)
  property alias contentX: viewport.contentX
  signal viewportChanged()

  function clampOffset() {
    viewport.contentX = Math.max(0, Math.min(maximumOffset, viewport.contentX))
  }

  function scrollBy(amount) {
    viewport.contentX = Math.max(0, Math.min(maximumOffset, viewport.contentX + amount))
  }

  function ensureVisible(item, extent) {
    if (windowDragActive || !item || viewport.width <= 0) return
    content.forceLayout()
    var point = content.mapFromItem(item, 0, 0)
    var start = point.x + contentPadding
    var end = start + Math.min(extent === undefined ? item.width : extent, viewport.width)
    if (start < viewport.contentX) viewport.contentX = start
    else if (end > viewport.contentX + viewport.width) viewport.contentX = end - viewport.width
    clampOffset()
  }

  function containsItem(item) {
    if (!item || !item.visible || viewport.width <= 0) return false
    var point = viewport.mapFromItem(item, 0, 0)
    return point.x >= 0 && point.x + item.width <= viewport.width
  }

  function containsScenePoint(scenePoint) {
    if (!visible || !scenePoint || !isFinite(scenePoint.x) || !isFinite(scenePoint.y)
        || viewport.width <= 0 || viewport.height <= 0) return false
    var point = viewport.mapFromItem(null, scenePoint.x, scenePoint.y)
    return point.x >= 0 && point.x < viewport.width
      && point.y >= 0 && point.y < viewport.height
  }

  function navigationDirectionAt(scenePoint) {
    if (!visible || !overflowing || !scenePoint
        || !isFinite(scenePoint.x) || !isFinite(scenePoint.y)) return 0
    for (var i = 0; i < navigationButtons.count; ++i) {
      var button = navigationButtons.itemAt(i)
      if (!button || !button.visible || button.width <= 0) continue
      var point = button.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (point.x >= 0 && point.x < button.width
          && point.y >= 0 && point.y < button.height) return i === 0 ? -1 : 1
    }
    return 0
  }

  function updateDragNavigation() {
    var direction = windowDragActive ? navigationDirectionAt(dragScenePosition) : 0
    if (direction === dragNavigationDirection) return
    dragDwell.stop()
    dragScroll.stop()
    dragNavigationDirection = direction
    if (direction !== 0) dragDwell.restart()
  }

  function dragScrollStep() {
    if (!windowDragActive || dragNavigationDirection === 0) return
    scrollBy(dragNavigationDirection * 12)
  }

  onWindowDragActiveChanged: updateDragNavigation()
  onDragScenePositionChanged: updateDragNavigation()
  onViewportChanged: updateDragNavigation()
  onMaximumOffsetChanged: { clampOffset(); viewportChanged() }
  onWidthChanged: { clampOffset(); viewportChanged() }
  onRowYChanged: viewportChanged()
  onXChanged: viewportChanged()
  onYChanged: viewportChanged()
  onVisibleChanged: { updateDragNavigation(); viewportChanged() }

  Timer {
    id: dragDwell
    interval: 250
    repeat: false
    onTriggered: {
      if (!root.windowDragActive || root.dragNavigationDirection === 0) return
      root.dragScrollStep()
      dragScroll.start()
    }
  }

  Timer {
    id: dragScroll
    interval: 40
    repeat: true
    onTriggered: root.dragScrollStep()
  }

  Flickable {
    id: viewport
    x: root.navigationWidth
    width: Math.max(0, root.width - root.navigationWidth * 2)
    height: root.height
    contentWidth: root.desiredWidth
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.HorizontalFlick
    interactive: root.overflowing && !root.windowDragActive
    onContentXChanged: root.viewportChanged()
    onWidthChanged: root.viewportChanged()

    Row {
      id: content
      x: root.contentPadding
      y: root.rowY
      spacing: 8
      onImplicitWidthChanged: Qt.callLater(root.clampOffset)
      onPositioningComplete: root.viewportChanged()
    }
  }

  Repeater {
    id: navigationButtons
    model: 2
    Rectangle {
      required property int index
      objectName: index === 0 ? "previousCards" : "nextCards"
      x: index === 0 ? 0 : root.width - width
      y: root.rowY
      width: root.navigationWidth
      height: 32
      radius: 4
      visible: root.overflowing
      enabled: index === 0 ? root.contentX > 0 : root.contentX < root.maximumOffset
      opacity: enabled ? 1 : 0.4
      color: navHover.hovered ? root.accent : root.background
      Accessible.role: Accessible.Button
      Accessible.name: index === 0 ? "Previous workspace cards" : "Next workspace cards"
      Accessible.onPressAction: if (!root.windowDragActive) root.scrollBy((index === 0 ? -1 : 1) * root.viewportWidth * 0.8)
      activeFocusOnTab: visible && enabled && !root.windowDragActive
      Keys.onReturnPressed: if (!root.windowDragActive) root.scrollBy((index === 0 ? -1 : 1) * root.viewportWidth * 0.8)
      Keys.onSpacePressed: if (!root.windowDragActive) root.scrollBy((index === 0 ? -1 : 1) * root.viewportWidth * 0.8)
      Text {
        anchors.centerIn: parent
        text: parent.index === 0 ? "‹" : "›"
        color: root.foreground
        font.pixelSize: 24
      }
      HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
      TapHandler {
        enabled: !root.windowDragActive
        onTapped: root.scrollBy((parent.index === 0 ? -1 : 1) * root.viewportWidth * 0.8)
      }
    }
  }
}
