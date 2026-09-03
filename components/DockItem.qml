import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel

Item {
  id: root

  required property string desktopId
  required property bool pinnedItem
  required property var runningToplevels
  required property var windowActions
  required property var hyprToplevels
  required property bool fullscreenModeActive
  required property bool fullscreenEmphasized
  required property int itemIndex
  required property int slotSize
  required property int iconSize
  required property real magnification
  required property real magnificationRadius
  required property bool hoverGlowEnabled
  required property real hoverGlowOpacity
  required property real hoverGlowRadius
  required property real pointerPosition
  required property var applicationActions
  required property color workspaceBadgeBackgroundColor
  required property color workspaceBadgeTextColor
  required property bool autoHide
  required property string position
  required property bool vertical
  required property bool previewActive
  property real reorderOffset: 0
  property int lastActivatedToplevel: -1
  property real wheelRemainder: 0
  property double lastWheelTimestamp: 0
  signal dragStarted(int itemIndex)
  signal dragMoved(real mainPosition)
  signal dragFinished()
  signal addApplicationRequested()
  signal removeRequested(string desktopId)
  signal hideRequested(string desktopId)
  signal autoHideToggled(bool enabled)
  signal contextMenuVisibilityChanged(bool visible)
  signal previewRequested(var anchorItem, string desktopId, var toplevels, var applicationEntry)
  signal previewReleased(var anchorItem)
  signal previewDismissRequested()

  // Reading the model makes this binding update when Quickshell finishes its
  // asynchronous desktop-entry scan. Calling byId() alone is not reactive.
  readonly property var applications: DesktopEntries.applications.values || []
  readonly property var entry: {
    var modelRevision = applications.length
    return DesktopEntries.byId(desktopId)
  }
  readonly property var runningToplevel: runningToplevels.length > 0
    ? runningToplevels[0]
    : null
  readonly property int runningCount: runningToplevels.length
  readonly property var activeToplevel: root.windowActions
    ? root.windowActions.activeToplevel : null
  readonly property string workspaceBadge: DockModel.workspaceBadgeText(
    runningToplevels, hyprToplevels)
  readonly property int minimizedCount: contextMenu.minimizedCount
  readonly property int visibleWindowCount: contextMenu.visibleWindowCount
  readonly property bool allWindowsMinimized: runningCount > 0 && visibleWindowCount === 0
  readonly property real dragOffset: dragHandler.active
    ? vertical ? dragHandler.activeTranslation.y : dragHandler.activeTranslation.x
    : 0
  readonly property real itemCenter: (vertical ? y + height / 2 : x + width / 2)
    + dragOffset + reorderOffset
  readonly property real distance: Math.abs(pointerPosition - itemCenter)
  readonly property real influence: pointerPosition < -1000
    ? 0
    : Math.exp(-(distance * distance) / (magnificationRadius * magnificationRadius))
  readonly property var fullscreenPresentation:
    DockModel.fullscreenIconPresentation(
      fullscreenModeActive, fullscreenEmphasized, mouse.hovered)
  readonly property real iconScale: fullscreenPresentation.scale
    * (1 + (magnification - 1) * influence)

  function launch() {
    if (entry)
      entry.execute()
    else
      Quickshell.execDetached(["gtk-launch", desktopId + ".desktop"])
  }

  function dispatchApplicationAction(action, options) {
    if (!DockModel.applicationActionCanRun(action, runningCount)) return false

    var request = options || ({})
    switch (action) {
    case "cycle-windows":
      // FDM-808 owns the actual cycle implementation. This hook lets that
      // successor branch reuse this canonical dispatcher without FDM-815
      // introducing cycle state or runtime wheel behavior.
      return root.windowActions
        && typeof root.windowActions.cycleToplevels === "function"
        ? root.windowActions.cycleToplevels(
            root.runningToplevels, request.direction, root.activeToplevel)
        : false
    case "minimize-restore":
      return root.windowActions.minimizeRestoreToplevels(root.runningToplevels)
    case "previews":
      if (root.runningCount < 2) return false
      root.previewRequested(root, root.desktopId, root.runningToplevels, root.entry)
      return true
    case "close":
      return root.windowActions.closeToplevels(root.runningToplevels)
    case "focus-or-launch":
      if (root.runningCount > 0) {
        // Preserve the pre-FDM-815 left-click behavior exactly: repeated
        // clicks walk the group in model order and activate the next window.
        root.lastActivatedToplevel = DockModel.nextToplevelIndex(
          root.lastActivatedToplevel, root.runningCount)
        return root.windowActions.activateToplevel(
          root.runningToplevels[root.lastActivatedToplevel])
      }
      root.launch()
      return true
    default:
      return false
    }
  }

  function dispatchPointerAction(input, modifiers, options) {
    return dispatchApplicationAction(DockModel.resolveApplicationPointerAction(
      applicationActions, input, modifiers), options)
  }

  onRunningToplevelsChanged: {
    lastActivatedToplevel = -1
    wheelRemainder = 0
    lastWheelTimestamp = 0
    if (runningCount < 2) root.previewDismissRequested()
  }

  width: vertical ? slotSize + 6 : slotSize
  height: vertical ? slotSize : slotSize + 6
  z: dragHandler.active ? 2 : 0
  transform: Translate {
    x: root.vertical ? 0 : root.dragOffset + root.reorderOffset
    y: root.vertical ? root.dragOffset + root.reorderOffset : 0
  }

  Behavior on reorderOffset {
    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
  }

  Item {
    id: iconContainer

    x: (root.width - root.iconSize) / 2
    y: (root.height - root.iconSize) / 2
    width: root.iconSize
    height: root.iconSize
    opacity: root.fullscreenPresentation.opacity
    transformOrigin: root.position === "top"
      ? Item.Top
      : root.position === "left"
        ? Item.Left
        : root.position === "right" ? Item.Right : Item.Bottom
    scale: root.iconScale

    Behavior on scale {
      NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
    }

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    RectangularShadow {
      id: hoverGlow

      anchors.fill: parent
      radius: Math.min(width, height) * 0.34
      blur: Math.max(8, root.iconSize * root.hoverGlowRadius / 100)
      spread: Math.max(1, root.iconSize * 0.06)
      offset: Qt.vector2d(0, 0)
      color: Color.accent
      opacity: root.hoverGlowEnabled && mouse.hovered
        ? root.hoverGlowOpacity : 0
      z: -1

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    IconImage {
      anchors.fill: parent
      opacity: root.allWindowsMinimized ? 0.56 : 1.0
      source: root.entry && root.entry.icon
        ? Quickshell.iconPath(root.entry.icon, true)
        : Quickshell.iconPath("application-x-executable", true)
      asynchronous: true

      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
      width: 4
      height: 4
      radius: 2
      x: root.position === "left"
        ? iconContainer.width + 2
        : root.position === "right"
          ? -6
          : (iconContainer.width - width) / 2
      y: root.position === "top"
        ? -6
        : root.position === "bottom"
          ? iconContainer.height + 2
          : (iconContainer.height - height) / 2
      color: root.visibleWindowCount > 0 ? Color.foreground : "transparent"
    }

    Rectangle {
      id: windowCountBadge

      visible: root.runningCount > 1
      width: Math.max(16, windowCountText.implicitWidth + 8)
      height: 16
      radius: Math.min(height / 2, Style.cornerRadius)
      x: iconContainer.width - width + 5
      y: -5
      color: Color.urgent
      border.width: Style.normalBorderWidth
      border.color: Color.background
      z: 3

      Text {
        id: windowCountText

        anchors.centerIn: parent
        text: root.runningCount > 99 ? "99+" : String(root.runningCount)
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Rectangle {
      id: minimizedCountBadge

      visible: root.minimizedCount > 0
      width: Math.max(22, minimizedCountText.implicitWidth + 8)
      height: 16
      radius: Math.min(height / 2, Style.cornerRadius)
      x: -5
      y: -5
      color: Color.muted
      border.width: Style.normalBorderWidth
      border.color: Color.background
      z: 3

      Text {
        id: minimizedCountText

        anchors.centerIn: parent
        text: "m" + (root.minimizedCount > 99 ? "99+" : String(root.minimizedCount))
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Rectangle {
      id: workspaceBadge

      visible: root.workspaceBadge !== ""
      width: Math.max(16, workspaceBadgeText.implicitWidth + 8)
      height: 16
      radius: Math.min(height / 2, Style.cornerRadius)
      x: -5
      y: iconContainer.height - height + 5
      color: root.workspaceBadgeBackgroundColor
      border.width: 0
      z: 3

      Text {
        id: workspaceBadgeText

        anchors.centerIn: parent
        text: root.workspaceBadge
        color: root.workspaceBadgeTextColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  PanelToolTip {
    visible: mouse.hovered && !contextMenu.visible && !root.previewActive
    text: root.tooltipLabel()
    fontFamily: Style.font.family
    fontSize: Style.font.body
  }

  function tooltipLabel() {
    var name = root.entry ? root.entry.name : root.desktopId
    if (root.minimizedCount > 0) {
      var word = root.runningCount === 1 ? "window" : "windows"
      return name + " (" + root.runningCount + " " + word
        + ", " + root.minimizedCount + " minimized)"
    }
    if (root.runningCount > 1)
      return name + " (" + root.runningCount + " windows)"
    return name
  }

  HoverHandler {
    id: mouse
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: {
      if (hovered) {
        if (root.runningCount >= 2 && !contextMenu.visible && !dragHandler.active)
          root.previewRequested(root, root.desktopId,
            root.runningToplevels, root.entry)
      } else if (root.previewActive || root.runningCount >= 2) {
        root.previewReleased(root)
      }
    }
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    // Read the release event's modifiers in one handler. Two overlapping
    // TapHandlers can lose the passive grab to the drag handler on compositors
    // that keep Shift in the pointer event, so dispatch all left-click
    // variants from the same event path.
    acceptedModifiers: Qt.KeyboardModifierMask
    onTapped: (eventPoint, button) => root.dispatchPointerAction(
      "left", DockModel.pointerModifierState(eventPoint.modifiers, {
        shift: Qt.ShiftModifier,
        control: Qt.ControlModifier,
        alt: Qt.AltModifier,
        meta: Qt.MetaModifier
      }))
  }

  TapHandler {
    acceptedButtons: Qt.MiddleButton
    acceptedModifiers: Qt.NoModifier
    onTapped: root.dispatchPointerAction("middle", {})
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    // Right click owns the context menu regardless of keyboard modifiers.
    acceptedModifiers: Qt.KeyboardModifierMask
    onTapped: {
      root.previewDismissRequested()
      contextMenu.open()
    }
  }

  WheelHandler {
    id: wheelHandler

    enabled: root.applicationActions.scrollAction !== "none"
    target: null
    onWheel: event => {
      // Ignore horizontal or diagonal gestures and keep sub-threshold
      // high-resolution deltas until they form one logical wheel step.
      event.accepted = false

      var verticalDelta = DockWindowModel.dominantVerticalWheelDelta(
        event.angleDelta.x, event.angleDelta.y)
      if (verticalDelta === 0 && event.pixelDelta) {
        // Touchpads may provide pixel deltas without a corresponding
        // angleDelta. They use the same accumulator, so small gestures still
        // produce one logical action instead of being dropped.
        verticalDelta = DockWindowModel.dominantVerticalWheelDelta(
          event.pixelDelta.x, event.pixelDelta.y)
      }
      if (verticalDelta === 0) return

      var now = Date.now()
      root.wheelRemainder = DockWindowModel.wheelRemainderForTimestamp(
        root.wheelRemainder, root.lastWheelTimestamp, now, 220)
      root.lastWheelTimestamp = now

      var accumulated = DockModel.accumulateWheelSteps(
        root.wheelRemainder, 0, verticalDelta)
      root.wheelRemainder = accumulated.remainder
      var direction = DockModel.wheelStepDirection(accumulated.steps)
      if (direction === 0) return

      var cycled = root.dispatchPointerAction(
        "scroll", {}, { direction: direction })
      event.accepted = cycled
    }
  }

  DragHandler {
    id: dragHandler

    enabled: root.pinnedItem
    target: null
    acceptedButtons: Qt.LeftButton
    acceptedModifiers: Qt.NoModifier
    xAxis.enabled: !root.vertical
    yAxis.enabled: root.vertical
    onActiveChanged: {
      if (active) {
        root.previewDismissRequested()
        root.dragStarted(root.itemIndex)
      } else {
        root.dragFinished()
      }
    }
    onActiveTranslationChanged: {
      if (active)
        root.dragMoved((root.vertical ? root.y + root.height / 2 : root.x + root.width / 2)
          + (root.vertical ? activeTranslation.y : activeTranslation.x))
    }
  }

  DockContextMenu {
    id: contextMenu

    anchorItem: root
    position: root.position
    autoHide: root.autoHide
    pinnedItem: root.pinnedItem
    runningToplevels: root.runningToplevels
    windowActions: root.windowActions
    onVisibleChanged: root.contextMenuVisibilityChanged(visible)
    onOpenNewWindow: root.launch()
    onAddApplication: root.addApplicationRequested()
    onRemoveFromDock: root.removeRequested(root.desktopId)
    onHideFromDock: root.hideRequested(root.desktopId)
    onToggleAutoHide: root.autoHideToggled(!root.autoHide)
  }
}
