import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: root

  required property string desktopId
  required property bool pinnedItem
  required property var runningToplevels
  required property bool focused
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
  required property string clickAction
  required property bool autoHide
  required property string position
  required property bool vertical
  property real reorderOffset: 0
  property int lastActivatedToplevel: -1
  signal dragStarted(int itemIndex)
  signal dragMoved(real mainPosition)
  signal dragFinished()
  signal addApplicationRequested()
  signal removeRequested(string desktopId)
  signal hideRequested(string desktopId)
  signal autoHideToggled(bool enabled)
  signal contextMenuVisibilityChanged(bool visible)

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

  function activateOrLaunch() {
    if (clickAction === "focus-or-launch" && runningCount > 0) {
      lastActivatedToplevel = DockModel.nextToplevelIndex(
        lastActivatedToplevel, runningCount)
      root.windowActions.activateToplevel(
        runningToplevels[lastActivatedToplevel])
      return
    }
    launch()
  }

  function closeRunning() {
    if (runningToplevel)
      root.windowActions.closeToplevel(runningToplevel)
  }

  onRunningToplevelsChanged: lastActivatedToplevel = -1

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

    DockApplicationStateIndicator {
      id: applicationStateIndicator

      position: root.position
      iconWidth: iconContainer.width
      iconHeight: iconContainer.height
      running: root.runningCount > 0
      focused: root.focused
      runningColor: Color.foreground
      focusedColor: Color.accent
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
      // Workspace badges need to remain legible over arbitrary application
      // icons. Use the theme's opaque accent role instead of the menu
      // selected-background tint, which is intentionally very subtle.
      color: Color.accent
      border.width: 0
      z: 3

      Text {
        id: workspaceBadgeText

        anchors.centerIn: parent
        text: root.workspaceBadge
        color: "#ffffff"
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  PanelToolTip {
    visible: mouse.hovered && !contextMenu.visible
    text: root.tooltipLabel()
    fontFamily: Style.font.family
    fontSize: Style.font.body
  }

  function tooltipLabel() {
    var name = root.entry ? root.entry.name : root.desktopId
    var state = root.focused ? "focused application"
      : root.runningCount > 0 ? "running application" : ""
    var label = state ? name + " — " + state : name
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
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    onTapped: root.activateOrLaunch()
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: contextMenu.open()
  }

  DragHandler {
    id: dragHandler

    enabled: root.pinnedItem
    target: null
    acceptedButtons: Qt.LeftButton
    xAxis.enabled: !root.vertical
    yAxis.enabled: root.vertical
    onActiveChanged: {
      if (active)
        root.dragStarted(root.itemIndex)
      else
        root.dragFinished()
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
