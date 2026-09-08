import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockBadgeModel.js" as BadgeModel
import "DockWindowModel.js" as DockWindowModel

Item {
  id: root

  required property string desktopId
  required property bool pinnedItem
  required property var runningToplevels
  required property bool focused
  required property var windowActions
  required property var hyprToplevels
  required property var badgeTracker
  required property string attentionBadge
  required property bool attentionBadgesEnabled
  required property bool urgentWindowAnimationEnabled
  required property bool primaryBadgeOwner
  required property bool dockShown
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
  required property bool showPreviews
  required property color workspaceBadgeBackgroundColor
  required property color workspaceBadgeTextColor
  required property bool autoHide
  required property string position
  required property bool vertical
  required property bool previewActive
  property bool originOnly: false
  property bool localUrgent: false
  property bool sticky: false
  property string attentionScopeKey: ""
  property bool presentationVisible: true
  property bool motionReady: false
  readonly property var attentionScope: attentionScopeKey
    ? ({ localUrgent: localUrgent, primaryOwner: primaryBadgeOwner }) : null
  readonly property bool motionOwner: attentionScopeKey !== "" || primaryBadgeOwner

  function dismissPopups() {
    contextMenu.dismiss()
    previewReleased(root)
  }

  function refreshPopupGeometry() {
    if (!presentationVisible) return
    tooltip.scheduleReanchor()
    if (contextMenu.visible) contextMenu.anchor.updateAnchor()
  }
  onPresentationVisibleChanged: if (!presentationVisible) dismissPopups()
  property int scopeRevision: 0
  property bool menuOpen: false
  onScopeRevisionChanged: if (originOnly && contextMenu.visible) contextMenu.dismiss()
  onVisibleChanged: if (!visible) {
    contextMenu.dismiss()
    root.previewReleased(root)
  }
  Component.onDestruction: {
    if (menuOpen) {
      menuOpen = false
      root.contextMenuVisibilityChanged(false)
    }
    root.previewReleased(root)
  }
  property string presentationId: desktopId
  property var identityToplevel: null
  // Kept as an optional compatibility hook for preview controllers that use
  // the earlier FDM-814 name; the host's previewActive binding remains the
  // canonical source.
  property bool previewInteractionActive: false
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
  readonly property string workspaceBadge: originOnly ? "" : DockModel.workspaceBadgeText(
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
  readonly property var urgentBadgeState: badgeTracker
    ? badgeTracker.urgentStateFor(desktopId, motionOwner, attentionScopeKey)
    : ({ windowUrgent: false, primaryOwner: primaryBadgeOwner,
         windowUrgentRevision: 0 })
  readonly property bool windowUrgent: urgentBadgeState.windowUrgent === true
  readonly property int windowUrgentRevision:
    Number(urgentBadgeState.windowUrgentRevision || 0)
  readonly property bool attentionActive: badgeTracker
    ? badgeTracker.motionAttentionFor(desktopId, attentionScope) : false
  readonly property bool urgentMotionSuppressed: !presentationVisible || mouse.hovered
    || dragHandler.active || contextMenu.visible
    || previewActive || previewInteractionActive

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
      return root.windowActions.cycleToplevels(
        root.runningToplevels, request.direction, root.windowActions.activeToplevel, root.originOnly)
    case "minimize-restore":
      return root.windowActions.minimizeRestoreToplevels(root.runningToplevels, root.originOnly)
    case "previews":
      if (!root.showPreviews || root.runningCount < 2) return false
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
          root.runningToplevels[root.lastActivatedToplevel], root.originOnly)
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

  function primeUrgentMotion() {
    if (!badgeTracker || !motionOwner) return
    if (!attentionScopeKey) badgeTracker.ensureUrgentState(desktopId)
    var state = badgeTracker.urgentStateFor(desktopId, true, attentionScopeKey)
    badgeTracker.primeUrgentMotion(
      desktopId, Number(state.windowUrgentRevision || 0), attentionScopeKey)
  }

  function requestUrgentMotion(reminder) {
    if (!motionReady || !badgeTracker || !motionOwner) return
    if (urgentMotionSuppressed) attentionMotion.stop()
    var play = badgeTracker.requestUrgentMotion(desktopId, {
      revision: windowUrgentRevision,
      windowUrgent: windowUrgent,
      attentionActive: attentionActive,
      reminder: reminder === true,
      primaryOwner: true,
      badgesEnabled: attentionBadgesEnabled,
      animationEnabled: urgentWindowAnimationEnabled,
      dockShown: dockShown && presentationVisible,
      interactionActive: urgentMotionSuppressed,
      now: Date.now()
    }, attentionScopeKey)
    if (play && !urgentMotionSuppressed) attentionMotion.play()
  }

  Component.onCompleted: {
    primeUrgentMotion()
    motionReady = true
    requestUrgentMotion(false)
  }
  onAttentionActiveChanged: {
    if (attentionActive) {
      requestUrgentMotion(true)
      return
    }
    attentionReminderTimer.stop()
    attentionMotion.stop()
    requestUrgentMotion(false)
  }
  onWindowUrgentRevisionChanged: requestUrgentMotion()
  onWindowUrgentChanged: requestUrgentMotion()
  onDockShownChanged: requestUrgentMotion()
  onUrgentMotionSuppressedChanged: {
    if (urgentMotionSuppressed) attentionMotion.stop()
    requestUrgentMotion()
  }
  onUrgentWindowAnimationEnabledChanged: {
    if (!urgentWindowAnimationEnabled) {
      attentionReminderTimer.stop()
      attentionMotion.stop()
    }
    requestUrgentMotion()
  }
  onAttentionBadgesEnabledChanged: {
    if (!attentionBadgesEnabled) {
      attentionReminderTimer.stop()
      attentionMotion.stop()
    }
    requestUrgentMotion()
  }

  Timer {
    id: attentionReminderTimer
    interval: 3000
    repeat: true
    running: root.motionReady && root.motionOwner && root.attentionActive
      && root.dockShown && root.presentationVisible
      && root.attentionBadgesEnabled
      && root.urgentWindowAnimationEnabled
    onTriggered: root.requestUrgentMotion(true)
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

  DockAttentionMotion {
    id: attentionMotion
    position: root.position
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

    Item {
      id: motionContent

      anchors.fill: parent
      transform: Translate {
        x: attentionMotion.xOffset
        y: attentionMotion.yOffset
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
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Math.max(10, Style.cornerRadius)
        color: Util.alpha(Color.background, mouse.hovered ? 0.36 : 0)
        border.width: 1
        border.color: Util.alpha(Color.foreground, mouse.hovered ? 0.14 : 0)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
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
        id: windowCountBadge

        visible: root.runningCount > 1
        width: Math.max(16, windowCountText.implicitWidth + 8)
        height: 16
        radius: height / 2
        x: iconContainer.width - width + 5
        y: -5
        color: Color.accent
        border.width: Style.normalBorderWidth
        border.color: Color.background
        z: 3

        Text {
          id: windowCountText

          anchors.centerIn: parent
          text: root.runningCount > 99 ? "99+" : String(root.runningCount)
          color: Color.background
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      DockApplicationBadge {
        severity: root.attentionBadge
        x: iconContainer.width - width + 3
        y: root.runningCount > 1 ? 13 : -3
      }

      Rectangle {
        visible: root.sticky
        width: 10
        height: 10
        radius: 2
        x: -3
        y: iconContainer.height - height + 3
        color: Color.background
        border.width: 2
        border.color: Color.accent
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

    // Keep the persistent running/focus indicator anchored to the dock slot;
    // only the application artwork/badges receive the transient nudge offset.
    DockApplicationStateIndicator {
      id: applicationStateIndicator

      // Grouped cards keep the marker on the slot, within the compact edge inset.
      // Flat/vertical docks retain their existing magnified marker presentation.
      parent: root.originOnly ? root : iconContainer
      x: indicatorGeometry.x + (root.originOnly ? iconContainer.x : 0)
      y: indicatorGeometry.y + (root.originOnly ? iconContainer.y : 0)
      opacity: root.originOnly ? iconContainer.opacity : 1
      position: root.position
      iconWidth: iconContainer.width
      iconHeight: iconContainer.height
      running: root.runningCount > 0
      focused: root.focused
      runningColor: Color.foreground
      focusedColor: Color.accent
    }
  }

  DockToolTip {
    id: tooltip
    anchorItem: root
    position: root.position
    requestedVisible: root.presentationVisible && mouse.hovered && !contextMenu.visible && !root.previewActive && !dragHandler.active && root.reorderOffset === 0
    text: root.tooltipLabel()
    fontFamily: Style.font.family
    fontSize: Style.font.body
  }

  function tooltipLabel() {
    var name = root.entry ? root.entry.name : root.desktopId
    var state = root.focused ? "focused application"
      : root.runningCount > 0 ? "running application" : ""
    var label = state ? name + " — " + state : name
    if (root.sticky) label += " (sticky on this monitor)"
    if (root.minimizedCount > 0) {
      var word = root.runningCount === 1 ? "window" : "windows"
      return label + " (" + root.runningCount + " " + word
        + ", " + root.minimizedCount + " minimized)"
    }
    if (root.runningCount > 1)
      return label + " (" + root.runningCount + " windows)"
    return label
  }

  HoverHandler {
    id: mouse
    cursorShape: Qt.PointingHandCursor
    onHoveredChanged: {
      if (hovered) {
        if (root.showPreviews && root.runningCount >= 2
            && !contextMenu.visible && !dragHandler.active)
          root.previewRequested(root, root.desktopId,
            root.runningToplevels, root.entry)
      } else if (root.previewActive || root.runningCount >= 2) {
        root.previewReleased(root)
      }
    }
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    acceptedModifiers: Qt.NoModifier
    onTapped: root.dispatchPointerAction("left", {})
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

    enabled: root.runningCount >= 2
      && root.applicationActions.scrollAction === "cycle-windows"
    target: null
    onWheel: event => {
      event.accepted = false

      var verticalDelta = DockWindowModel.dominantVerticalWheelDelta(
        event.angleDelta.x, event.angleDelta.y)
      if (verticalDelta === 0) return

      var now = Date.now()
      root.wheelRemainder = DockWindowModel.wheelRemainderForTimestamp(
        root.wheelRemainder, root.lastWheelTimestamp, now, 220)
      root.lastWheelTimestamp = now

      var accumulated = DockWindowModel.accumulateWheelSteps(
        root.wheelRemainder, verticalDelta, 120)
      root.wheelRemainder = accumulated.remainder
      var direction = DockWindowModel.wheelStepDirection(accumulated.steps)
      if (direction === 0) return

      var cycled = root.dispatchPointerAction(
        "scroll", {}, { direction: direction })
      event.accepted = cycled
    }
  }

  DragHandler {
    id: dragHandler

    enabled: root.pinnedItem && !root.originOnly
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
    originOnly: root.originOnly
    onVisibleChanged: {
      if (root.menuOpen !== visible) {
        root.menuOpen = visible
        root.contextMenuVisibilityChanged(visible)
      }
    }
    onOpenNewWindow: root.launch()
    onAddApplication: root.addApplicationRequested()
    onRemoveFromDock: root.removeRequested(root.desktopId)
    onHideFromDock: root.hideRequested(root.desktopId)
    onToggleAutoHide: root.autoHideToggled(!root.autoHide)
  }
}
