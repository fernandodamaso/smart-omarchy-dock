import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string label
  property bool showFullLabel: false
  readonly property string displayLabel: root.showFullLabel || /^[0-9]+$/.test(root.label)
    ? root.label : "*"
  required property int count
  required property bool active
  required property int slotSize
  property bool switchable: true
  property bool urgent: false
  property bool dropHighlighted: false
  property bool windowDragActive: false
  property var workspaceMonitorDrag: null
  property var workspaceMonitorDragDock: null
  property string workspaceIdentity: ""
  property string workspaceOwnerMonitor: ""
  property bool workspaceMonitorGestureOwned: false
  readonly property bool workspaceMonitorDragActive:
    workspaceMonitorDrag && workspaceMonitorDrag.active
  readonly property bool workspaceMonitorDragSource: workspaceMonitorDragActive
    && workspaceMonitorDrag.sourceDock === workspaceMonitorDragDock
    && workspaceMonitorDrag.sourceWorkspace === workspaceIdentity
  readonly property bool headerInputSuppressed: windowDragActive
    || workspaceMonitorDragActive || workspaceMonitorGestureOwned
  property string position: "bottom"
  property bool presentationVisible: true
  property bool animationsEnabled: true
  property var applicationModel: null
  property Component applicationDelegate: null
  property DockWorkspaceLayout viewport: null
  Connections {
    target: root.viewport
    function onViewportChanged() {
      if (root.viewport && root.viewport.viewportWidth <= 0) return
      root.presentationVisible = !root.viewport || root.viewport.containsItem(header)
      headerTooltip.scheduleReanchor()
    }
  }
  readonly property real headerWidth: header.width
  default property alias items: appRow.data
  signal activated()

  function cancelWorkspaceMonitorDrag(reason) {
    if (root.workspaceMonitorDrag
        && root.workspaceMonitorDrag.sourceDock === root.workspaceMonitorDragDock
        && root.workspaceMonitorDrag.sourceWorkspace === root.workspaceIdentity)
      root.workspaceMonitorDrag.cancel(reason)
  }

  function workspaceMonitorGrabChanged(transition, point) {
    if (!root.workspaceMonitorDrag
        || root.workspaceMonitorDrag.sourceDock !== root.workspaceMonitorDragDock
        || root.workspaceMonitorDrag.sourceWorkspace !== root.workspaceIdentity) return
    if (transition === PointerDevice.UngrabExclusive) {
      if (point.state === EventPoint.Released)
        root.workspaceMonitorDrag.finish(point.scenePosition)
      else
        cancelWorkspaceMonitorDrag("non-release ungrab")
    } else if (transition === PointerDevice.CancelGrabExclusive
        || transition === PointerDevice.CancelGrabPassive) {
      cancelWorkspaceMonitorDrag("grab cancelled")
    }
  }

  onPresentationVisibleChanged: if (!presentationVisible)
    cancelWorkspaceMonitorDrag("source hidden")
  onWorkspaceIdentityChanged: cancelWorkspaceMonitorDrag("workspace changed")
  onWorkspaceOwnerMonitorChanged: cancelWorkspaceMonitorDrag("workspace owner changed")
  onWorkspaceMonitorDragDockChanged: cancelWorkspaceMonitorDrag("dock changed")
  onWindowDragActiveChanged: if (windowDragActive)
    cancelWorkspaceMonitorDrag("window drag started")
  onParentChanged: cancelWorkspaceMonitorDrag("source reparented")
  Component.onDestruction: cancelWorkspaceMonitorDrag("source destroyed")

  readonly property real appOccupancy: Math.min(1, appRow.width / Math.max(1, slotSize))
  width: header.width + appRow.width + 2 + 14 * appOccupancy
  height: slotSize + 10
  radius: Math.max(12, Style.cornerRadius - 4)
  color: dropHighlighted ? Util.alpha(Color.accent, 0.24)
    : active ? Util.alpha(Color.accent, workspaceHover.hovered ? 0.13 : 0.10) : Util.alpha(Color.background, workspaceHover.hovered ? 0.42 : 0.26)
  border.width: 1
  border.color: dropHighlighted ? Color.accent
    : urgent ? Color.urgent : active ? Util.alpha(Color.accent, 0.50) : Util.alpha(Color.foreground, workspaceHover.hovered ? 0.14 : 0.07)
  opacity: workspaceMonitorDragSource && workspaceMonitorDrag
    && workspaceMonitorDrag.captureReady ? 0.55 : 1
  Behavior on color {
    enabled: root.animationsEnabled
    ColorAnimation { duration: 160 }
  }
  Behavior on border.color {
    enabled: root.animationsEnabled
    ColorAnimation { duration: 160 }
  }
  HoverHandler { id: workspaceHover }

  Rectangle {
    id: header
    color: "transparent"
    radius: Math.max(10, root.radius - 2)
    border.width: activeFocus && !root.workspaceMonitorDragSource ? 1 : 0
    border.color: Color.accent
    x: 1
    y: 1
    width: Math.min(80, Math.max(root.slotSize, title.implicitWidth + 16))
    height: parent.height - 2
    Accessible.role: Accessible.Button
    Accessible.name: root.label + ", " + root.count + " windows" + (root.urgent ? ", urgent" : "")
    Accessible.onPressAction: if (root.switchable && !root.headerInputSuppressed) root.activated()
    activeFocusOnTab: root.switchable && !root.headerInputSuppressed
    Keys.onReturnPressed: if (root.switchable && !root.headerInputSuppressed) root.activated()
    Keys.onSpacePressed: if (root.switchable && !root.headerInputSuppressed) root.activated()
    Keys.onEscapePressed: event => {
      if (!root.workspaceMonitorDragActive) return
      root.cancelWorkspaceMonitorDrag("escape")
      event.accepted = true
    }
    Text {
      id: title
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - 8)
      elide: Text.ElideRight
      text: root.displayLabel
      horizontalAlignment: Text.AlignHCenter
      color: root.active ? Color.accent : Color.foreground
      Behavior on color {
        enabled: root.animationsEnabled
        ColorAnimation { duration: 160 }
      }
      font.family: Style.font.family
      font.pixelSize: Math.max(Style.font.body, root.slotSize * 0.38)
      font.bold: true
    }
    TapHandler {
      enabled: root.switchable && !root.headerInputSuppressed
      onPressedChanged: if (pressed)
        header.forceActiveFocus(Qt.MouseFocusReason)
      onTapped: root.activated()
    }
    HoverHandler {
      id: headerHover
      cursorShape: root.workspaceMonitorDragSource ? Qt.ClosedHandCursor
        : root.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    DockToolTip {
      id: headerTooltip
      anchorItem: header
      position: root.position
      requestedVisible: headerHover.hovered && root.presentationVisible
        && !root.headerInputSuppressed
      text: root.label + " — " + root.count + " windows" + (root.urgent ? " — urgent" : "")
      fontFamily: Style.font.family
      fontSize: Style.font.body
    }
    DragHandler {
      id: workspaceMonitorDragHandler
      enabled: root.switchable && root.workspaceIdentity !== ""
        && root.workspaceMonitorDrag && root.workspaceMonitorDragDock
        && root.presentationVisible && !root.windowDragActive
        && (active || root.workspaceMonitorGestureOwned
          || !root.workspaceMonitorDrag.active)
      target: null
      acceptedButtons: Qt.LeftButton
      dragThreshold: 0
      xAxis.enabled: true
      yAxis.enabled: true
      grabPermissions: PointerHandler.CanTakeOverFromItems
        | PointerHandler.CanTakeOverFromHandlersOfDifferentType
      cursorShape: Qt.ClosedHandCursor
      onActiveChanged: {
        if (active) {
          workspaceMonitorReleaseCleanup.stop()
          root.workspaceMonitorGestureOwned = true
          if (root.workspaceMonitorDrag.begin(root.workspaceMonitorDragDock,
            root.workspaceIdentity, root.label, root.count,
            root.workspaceOwnerMonitor, centroid.scenePosition))
            header.forceActiveFocus(Qt.MouseFocusReason)
        } else {
          workspaceMonitorReleaseCleanup.restart()
          header.focus = false
        }
      }
      onActiveTranslationChanged: if (active && root.workspaceMonitorDrag
          && root.workspaceMonitorDrag.sourceDock === root.workspaceMonitorDragDock)
        root.workspaceMonitorDrag.updatePointer(centroid.scenePosition)
      onGrabChanged: (transition, point) => {
        if (transition === PointerDevice.GrabPassive
            || transition === PointerDevice.GrabExclusive)
          header.forceActiveFocus(Qt.MouseFocusReason)
        root.workspaceMonitorGrabChanged(transition, point)
      }
      onCanceled: root.cancelWorkspaceMonitorDrag("grab stolen")
      onEnabledChanged: if (!enabled)
        root.cancelWorkspaceMonitorDrag("handler disabled")
    }
    Timer {
      id: workspaceMonitorReleaseCleanup
      interval: 0
      repeat: false
      onTriggered: {
        root.cancelWorkspaceMonitorDrag("grab ended without release")
        root.workspaceMonitorGestureOwned = false
      }
    }
  }

  Rectangle {
    id: groupDivider
    x: header.width + 5
    visible: root.appOccupancy > 0
    opacity: root.appOccupancy
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: Math.max(18, parent.height * 0.48)
    radius: 1
    color: Util.alpha(Color.foreground, root.active ? 0.13 : 0.09)
  }

  Row {
    id: appRow
    x: header.width + 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.applicationModel
      delegate: root.applicationDelegate
    }
  }
}
