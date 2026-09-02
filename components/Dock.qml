pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

PanelWindow {
  id: root

  required property var settings
  required property var windowActions
  required property int trashItemCount
  required property bool trashStateKnown
  required property var workspaceWindowCounts
  required property bool workspaceCountsReady
  required property int workspaceCountsRevision
  signal reorderRequested(string sourceDesktopId, string targetDesktopId)
  signal pinRequested(string desktopId)
  signal unpinRequested(string desktopId)
  signal hideRequested(string desktopId)
  signal autoHideRequested(bool enabled)
  signal settingChanged(string key, var value)
  signal settingsPatchRequested(var patch)
  signal resetSettingsRequested()
  signal openTrashRequested()
  signal emptyTrashRequested()

  property int dragSource: -1
  property int dragTarget: -1
  property int openMenuCount: 0
  property bool autoHideRevealed: false
  property int fullscreenStateRevision: 0
  property int workspaceStateRevision: 0
  property var settingPreviews: ({})

  readonly property int iconSize: DockModel.normalizeSetting(
    "iconSize", effectiveSetting("iconSize"))
  readonly property real magnification: DockModel.normalizeSetting(
    "magnification", effectiveSetting("magnification"))
  readonly property real magnificationRadius: DockModel.normalizeSetting(
    "magnificationRadius", effectiveSetting("magnificationRadius"))
  readonly property bool hoverGlowEnabled: DockModel.normalizeSetting(
    "hoverGlowEnabled", effectiveSetting("hoverGlowEnabled"))
  readonly property real hoverGlowOpacity: DockModel.normalizeSetting(
    "hoverGlowOpacity", effectiveSetting("hoverGlowOpacity"))
  readonly property real hoverGlowRadius: DockModel.normalizeSetting(
    "hoverGlowRadius", effectiveSetting("hoverGlowRadius"))
  readonly property int edgeMargin: settings.margin === undefined ? 10 : settings.margin
  // Names exposed by Dock Settings. Values are live bindings to Omarchy's
  // Color singleton so symbolic overrides follow a theme change immediately.
  readonly property var themeColorTokens: ({
    "background": Color.background,
    "foreground": Color.foreground,
    "accent": Color.accent,
    "muted": Color.muted,
    "urgent": Color.urgent,
    "bar.background": Color.bar.background,
    "bar.text": Color.bar.text,
    "bar.active": Color.bar.active,
    "popups.background": Color.popups.background,
    "popups.text": Color.popups.text,
    "popups.border": Color.popups.border,
    "tooltip.background": Color.tooltip.background,
    "tooltip.text": Color.tooltip.text,
    "tooltip.border": Color.tooltip.border,
    "menu.background": Color.menu.background,
    "menu.text": Color.menu.text,
    "menu.border": Color.menu.border,
    "menu.selected-background": Color.menu.selectedBackground,
    "menu.selected-text": Color.menu.selectedText,
    "menu.selected-border": Color.menu.selectedBorder,
    "notifications.background": Color.notifications.background,
    "notifications.text": Color.notifications.text,
    "notifications.border": Color.notifications.border,
    "notifications.countdown": Color.notifications.countdown
  })
  readonly property bool backgroundColorEnabled: DockModel.normalizeSetting(
    "backgroundColorEnabled", effectiveSetting("backgroundColorEnabled"))
  readonly property string backgroundColorOverride: DockModel.normalizeSetting(
    "backgroundColor", effectiveSetting("backgroundColor"))
  readonly property color dockBackgroundBaseColor: DockModel.effectiveColor(
    backgroundColorEnabled, backgroundColorOverride, Color.menu.background,
    themeColorTokens)
  readonly property real backgroundOpacity: DockModel.normalizeSetting(
    "backgroundOpacity", effectiveSetting("backgroundOpacity"))
  readonly property color dockBackgroundColor: Qt.rgba(
    dockBackgroundBaseColor.r,
    dockBackgroundBaseColor.g,
    dockBackgroundBaseColor.b,
    DockModel.surfaceOpacity(dockBackgroundBaseColor.a, backgroundOpacity))
  readonly property bool borderColorEnabled: DockModel.normalizeSetting(
    "borderColorEnabled", effectiveSetting("borderColorEnabled"))
  readonly property string borderColorOverride: DockModel.normalizeSetting(
    "borderColor", effectiveSetting("borderColor"))
  readonly property bool borderWidthEnabled: DockModel.normalizeSetting(
    "borderWidthEnabled", effectiveSetting("borderWidthEnabled"))
  readonly property var themeDockBorderSpec: Border.surfaceSpec(
    "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property real themeBorderWidth: Math.max(
    Border.top(themeDockBorderSpec), Border.right(themeDockBorderSpec),
    Border.bottom(themeDockBorderSpec), Border.left(themeDockBorderSpec))
  readonly property real borderWidth: DockModel.effectiveBorderWidth(
    borderWidthEnabled, effectiveSetting("borderWidth"), themeBorderWidth)
  readonly property color dockBorderColor: DockModel.effectiveColor(
    borderColorEnabled, borderColorOverride, Color.menu.border,
    themeColorTokens)
  readonly property var dockBorderSpec: {
    var spec = {
      color: themeDockBorderSpec.color,
      widths: themeDockBorderSpec.widths,
      gradient: themeDockBorderSpec.gradient
    }
    if (root.borderColorEnabled && root.borderColorOverride !== "") {
      spec.color = root.dockBorderColor
      spec.gradient = { colors: [], angle: 0, enabled: false }
    }
    if (root.borderWidthEnabled)
      spec.widths = Border.flat(spec.color, root.borderWidth).widths
    return spec
  }
  readonly property bool autoHide: DockModel.normalizeSetting(
    "autoHide", effectiveSetting("autoHide"))
  readonly property bool reserveSpace: DockModel.shouldReserveSpace(
    DockModel.normalizeSetting("reserveSpace", effectiveSetting("reserveSpace")),
    autoHide)
  readonly property string clickAction: DockModel.normalizeSetting(
    "clickAction", effectiveSetting("clickAction"))
  readonly property string controlCommand: DockModel.normalizeSetting(
    "controlCommand", effectiveSetting("controlCommand"))
  readonly property string position: DockModel.normalizeSetting(
    "position", effectiveSetting("position"))
  readonly property bool vertical: position === "left" || position === "right"
  readonly property bool fullLength: DockModel.normalizeSetting(
    "fullLength", effectiveSetting("fullLength"))
  readonly property bool sortByWorkspace: DockModel.normalizeSetting(
    "sortByWorkspace", effectiveSetting("sortByWorkspace"))
  readonly property bool groupWindows: DockModel.normalizeSetting(
    "groupWindows", effectiveSetting("groupWindows"))
  readonly property var pinned: settings.pinned || []
  readonly property var hiddenApplications: DockModel.normalizeSetting(
    "hiddenApplications", effectiveSetting("hiddenApplications"))
  readonly property var applications: DesktopEntries.applications.values || []
  readonly property var toplevels: ToplevelManager.toplevels.values || []
  readonly property var hyprToplevels: Hyprland.toplevels
    ? Hyprland.toplevels.values || [] : []
  readonly property var hyprWorkspaces: Hyprland.workspaces
    ? Hyprland.workspaces.values || [] : []
  readonly property var hyprMonitors: Hyprland.monitors
    ? Hyprland.monitors.values || [] : []
  readonly property int focusedWorkspaceId: {
    var revision = workspaceStateRevision + workspaceCountsRevision
    return DockModel.focusedWorkspaceIdFromMonitors(
      hyprMonitors, Hyprland.focusedWorkspace)
  }
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property var fullscreenOwnerToplevel: DockModel.fullscreenOwner(
    toplevels, hyprToplevels, focusedWorkspaceId, activeToplevel,
    fullscreenStateRevision)
  readonly property bool fullscreenModeActive: fullscreenOwnerToplevel !== null
  readonly property var visibleItems: DockModel.buildVisibleItems(
    pinned, toplevels, applications, hyprToplevels, sortByWorkspace,
    groupWindows, hiddenApplications)
  readonly property var visibleWorkspaceIds: {
    var revision = workspaceStateRevision + workspaceCountsRevision
    return DockModel.visibleWorkspaceIds(
      hyprWorkspaces, focusedWorkspaceId, hyprToplevels,
      workspaceWindowCounts, workspaceCountsReady)
  }
  readonly property int itemSize: iconSize + 14
  readonly property int reservedSize: iconSize + 24 + edgeMargin
  readonly property int mainPadding: 10
  readonly property int revealThickness: 3
  readonly property int crossExtent: vertical
    ? Math.ceil(iconSize * magnification + 80) + edgeMargin
    : Math.ceil(iconSize * magnification + 48) + edgeMargin
  readonly property int appMainExtent: visibleItems.length * itemSize
  readonly property int workspaceMainExtent: vertical
    ? Math.max(0, visibleWorkspaceIds.length * 32 + 6)
    : Math.max(0, visibleWorkspaceIds.length * 32 + 6)
  readonly property int trailingMainExtent: 12 + itemSize + 12 + workspaceMainExtent
  readonly property int compactMainExtent: mainPadding * 2 + itemSize
    + appMainExtent + trailingMainExtent
  readonly property bool keepAutoHideOpen: windowPointer.hovered
    || appPicker.visible || dockSettings.visible || openMenuCount > 0 || dragSource >= 0
  readonly property bool dockShown: !autoHide || autoHideRevealed
  readonly property real pointerPosition: !pointer.hovered
    ? -10000
    : vertical
      ? pointer.point.position.y
      : pointer.point.position.x

  function effectiveSetting(key) {
    return settingPreviews[key] !== undefined ? settingPreviews[key] : settings[key]
  }

  function previewSetting(key, value) {
    var previews = DockModel.mergeSettings(settingPreviews, ({}))
    previews[key] = value
    settingPreviews = previews
  }

  function clearSettingPreview(key) {
    if (settingPreviews[key] === undefined) return
    var previews = {}
    for (var previewKey in settingPreviews) {
      if (previewKey !== key) previews[previewKey] = settingPreviews[previewKey]
    }
    settingPreviews = previews
  }

  function clearSettingPreviews() {
    settingPreviews = ({})
  }

  function reorderOffset(index) {
    if (dragSource < 0 || dragTarget < 0) return 0
    if (dragSource < dragTarget && index > dragSource && index <= dragTarget)
      return -itemSize
    if (dragSource > dragTarget && index >= dragTarget && index < dragSource)
      return itemSize
    return 0
  }

  function visiblePinnedTargetIndex(position) {
    var candidateIndex = Math.floor(position / itemSize)
    var nearestIndex = -1
    var nearestDistance = Infinity

    for (var i = 0; i < visibleItems.length; ++i) {
      if (!visibleItems[i] || !visibleItems[i].pinned) continue

      var distance = Math.abs(i - candidateIndex)
      if (distance < nearestDistance
          || (distance === nearestDistance && i > nearestIndex)) {
        nearestIndex = i
        nearestDistance = distance
      }
    }

    return nearestIndex
  }

  function updateDragTarget(position) {
    dragTarget = visiblePinnedTargetIndex(position)
  }

  function finishDrag() {
    var from = dragSource
    var to = dragTarget
    var sourceItem = from >= 0 && from < visibleItems.length
      ? visibleItems[from] : null
    var targetItem = to >= 0 && to < visibleItems.length
      ? visibleItems[to] : null
    dragSource = -1
    dragTarget = -1
    if (sourceItem && targetItem && sourceItem.pinned && targetItem.pinned
        && from !== to) {
      reorderRequested(String(sourceItem.desktopId),
        String(targetItem.desktopId))
    }
  }

  function updateAutoHideState() {
    if (!autoHide) {
      hideTimer.stop()
      autoHideRevealed = false
    } else if (keepAutoHideOpen) {
      hideTimer.stop()
      autoHideRevealed = true
    } else if (autoHideRevealed) {
      hideTimer.restart()
    }
  }

  onAutoHideChanged: updateAutoHideState()
  onKeepAutoHideOpenChanged: updateAutoHideState()

  Timer {
    id: fullscreenStateRefreshTimer

    interval: 80
    repeat: false
    onTriggered: root.fullscreenStateRevision++
  }

  Timer {
    id: workspaceStateRefreshTimer

    interval: 80
    repeat: false
    onTriggered: root.workspaceStateRevision++
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = event ? event.name : ""
      if (DockModel.shouldRefreshFullscreenPresentation(name)) {
        Hyprland.refreshToplevels()
        fullscreenStateRefreshTimer.restart()
      }
      if (DockModel.shouldRefreshWorkspaceState(name)) {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        workspaceStateRefreshTimer.restart()
      }
    }
  }

  Connections {
    target: Hyprland.workspaces

    function onValuesChanged() {
      workspaceStateRefreshTimer.restart()
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      workspaceStateRefreshTimer.restart()
    }
  }

  Connections {
    target: Hyprland.monitors

    function onValuesChanged() {
      workspaceStateRefreshTimer.restart()
    }
  }

  Connections {
    target: ToplevelManager

    function onActiveToplevelChanged() {
      fullscreenStateRefreshTimer.restart()
      Hyprland.refreshMonitors()
      workspaceStateRefreshTimer.restart()
    }
  }

  anchors {
    top: position === "top" || (vertical && fullLength)
    bottom: position === "bottom" || (vertical && fullLength)
    left: position === "left" || (!vertical && fullLength)
    right: position === "right" || (!vertical && fullLength)
  }
  implicitWidth: vertical
    ? crossExtent
    : fullLength ? 0 : compactMainExtent
  implicitHeight: vertical
    ? fullLength ? 0 : compactMainExtent
    : crossExtent
  color: "transparent"
  exclusionMode: reserveSpace ? ExclusionMode.Normal : ExclusionMode.Ignore
  WlrLayershell.exclusiveZone: reserveSpace ? reservedSize : 0
  WlrLayershell.namespace: "smartdock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {
    item: root.dockShown ? interactionArea : revealStrip
  }

  Timer {
    id: hideTimer

    interval: 800
    onTriggered: if (root.autoHide && !root.keepAutoHideOpen)
      root.autoHideRevealed = false
  }

  Item {
    id: interactionArea

    anchors.fill: parent
  }

  Item {
    id: revealStrip

    x: root.position === "right" ? parent.width - width : 0
    y: root.position === "bottom" ? parent.height - height : 0
    width: root.vertical ? root.revealThickness : parent.width
    height: root.vertical ? parent.height : root.revealThickness
  }

  BorderSurface {
    id: dockBackground

    x: root.vertical
      ? root.position === "left" ? root.edgeMargin : parent.width - width - root.edgeMargin
      : 0
    y: root.vertical
      ? 0
      : root.position === "top" ? root.edgeMargin : parent.height - height - root.edgeMargin
    width: root.vertical ? root.iconSize + 24 : parent.width
    height: root.vertical ? parent.height : root.iconSize + 24
    radius: Style.cornerRadius
    color: root.dockBackgroundColor
    borderSpec: root.dockBorderSpec
    transform: Translate {
      x: !root.autoHide || root.dockShown
        ? 0
        : root.position === "left"
          ? -(dockBackground.width + root.edgeMargin)
          : root.position === "right" ? dockBackground.width + root.edgeMargin : 0
      y: !root.autoHide || root.dockShown
        ? 0
        : root.position === "top"
          ? -(dockBackground.height + root.edgeMargin)
          : root.position === "bottom" ? dockBackground.height + root.edgeMargin : 0

      Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Item {
      id: dockLayout

      anchors.fill: parent

      readonly property real leadingEnd: root.mainPadding + root.itemSize
      readonly property real trailingStart: (root.vertical ? height : width)
        - root.mainPadding - root.trailingMainExtent
      readonly property real centeredAppStart: ((root.vertical ? height : width)
        - root.appMainExtent) / 2
      readonly property real appStart: root.fullLength
        ? Math.max(leadingEnd, Math.min(centeredAppStart,
            Math.max(leadingEnd, trailingStart - root.appMainExtent)))
        : leadingEnd

      DockControlItem {
        id: controlItem

        x: root.vertical ? (parent.width - width) / 2 : root.mainPadding
        y: root.vertical ? root.mainPadding : (parent.height - height) / 2
        controlCommand: root.controlCommand
        windowActions: root.windowActions
        slotSize: root.itemSize
        iconSize: root.iconSize
        magnification: root.magnification
        magnificationRadius: root.magnificationRadius
        hoverGlowEnabled: root.hoverGlowEnabled
        hoverGlowOpacity: root.hoverGlowOpacity
        hoverGlowRadius: root.hoverGlowRadius
        pointerPosition: root.pointerPosition
        autoHide: root.autoHide
        position: root.position
        vertical: root.vertical
        onSettingsRequested: dockSettings.open()
        onAddApplicationRequested: appPicker.open()
        onAutoHideToggled: enabled => root.autoHideRequested(enabled)
        onContextMenuVisibilityChanged: visible => {
          root.openMenuCount = Math.max(0, root.openMenuCount + (visible ? 1 : -1))
        }
      }

      Grid {
        id: appGrid

        x: root.vertical ? (parent.width - width) / 2 : parent.appStart
        y: root.vertical ? parent.appStart : (parent.height - height) / 2
        columns: root.vertical ? 1 : Math.max(1, root.visibleItems.length)
        rows: root.vertical ? Math.max(1, root.visibleItems.length) : 1

        Repeater {
          model: root.visibleItems

          DockItem {
            required property var modelData
            required property int index

            desktopId: modelData.desktopId
            pinnedItem: modelData.pinned
            runningToplevels: modelData.toplevels
            focused: DockModel.hasActiveMember(
              modelData.toplevels, root.activeToplevel)
            windowActions: root.windowActions
            hyprToplevels: root.hyprToplevels
            fullscreenModeActive: root.fullscreenModeActive
            fullscreenEmphasized:
              modelData.toplevels.indexOf(root.fullscreenOwnerToplevel) >= 0
            itemIndex: index
            slotSize: root.itemSize
            iconSize: root.iconSize
            magnification: root.magnification
            magnificationRadius: root.magnificationRadius
            hoverGlowEnabled: root.hoverGlowEnabled
            hoverGlowOpacity: root.hoverGlowOpacity
            hoverGlowRadius: root.hoverGlowRadius
            pointerPosition: root.pointerPosition
              - (root.vertical ? appGrid.y : appGrid.x)
            clickAction: root.clickAction
            autoHide: root.autoHide
            position: root.position
            vertical: root.vertical
            reorderOffset: root.reorderOffset(index)
            onDragStarted: itemIndex => {
              root.dragSource = itemIndex
              root.dragTarget = itemIndex
            }
            onDragMoved: mainPosition => root.updateDragTarget(mainPosition)
            onDragFinished: root.finishDrag()
            onRemoveRequested: desktopId => root.unpinRequested(desktopId)
            onHideRequested: desktopId => root.hideRequested(desktopId)
            onContextMenuVisibilityChanged: visible => {
              root.openMenuCount = Math.max(0,
                root.openMenuCount + (visible ? 1 : -1))
            }
          }
        }
      }

      DockSeparator {
        id: appTrashSeparator

        x: root.vertical ? (parent.width - width) / 2 : parent.trailingStart
        y: root.vertical ? parent.trailingStart : (parent.height - height) / 2
        vertical: root.vertical
        slotSize: root.itemSize
        iconSize: root.iconSize
      }

      DockTrashItem {
        id: trashItem

        x: root.vertical
          ? (parent.width - width) / 2
          : parent.trailingStart + appTrashSeparator.width
        y: root.vertical
          ? parent.trailingStart + appTrashSeparator.height
          : (parent.height - height) / 2
        trashItemCount: root.trashItemCount
        trashStateKnown: root.trashStateKnown
        slotSize: root.itemSize
        iconSize: root.iconSize
        magnification: root.magnification
        magnificationRadius: root.magnificationRadius
        hoverGlowEnabled: root.hoverGlowEnabled
        hoverGlowOpacity: root.hoverGlowOpacity
        hoverGlowRadius: root.hoverGlowRadius
        pointerPosition: root.pointerPosition
        position: root.position
        vertical: root.vertical
        onOpenRequested: root.openTrashRequested()
        onEmptyRequested: root.emptyTrashRequested()
        onContextMenuVisibilityChanged: visible => {
          root.openMenuCount = Math.max(0,
            root.openMenuCount + (visible ? 1 : -1))
        }
      }

      DockSeparator {
        id: trashWorkspaceSeparator

        x: root.vertical
          ? (parent.width - width) / 2
          : parent.trailingStart + appTrashSeparator.width + trashItem.width
        y: root.vertical
          ? parent.trailingStart + appTrashSeparator.height + trashItem.height
          : (parent.height - height) / 2
        vertical: root.vertical
        slotSize: root.itemSize
        iconSize: root.iconSize
      }

      DockWorkspaceStrip {
        id: workspaceStrip

        x: root.vertical
          ? (parent.width - width) / 2
          : parent.trailingStart + appTrashSeparator.width + trashItem.width
            + trashWorkspaceSeparator.width
        y: root.vertical
          ? parent.trailingStart + appTrashSeparator.height + trashItem.height
            + trashWorkspaceSeparator.height
          : (parent.height - height) / 2
        workspaceIds: root.visibleWorkspaceIds
        workspaces: root.hyprWorkspaces
        hyprToplevels: root.hyprToplevels
        workspaceWindowCounts: root.workspaceWindowCounts
        workspaceCountsReady: root.workspaceCountsReady
        workspaceStateRevision: root.workspaceStateRevision + root.workspaceCountsRevision
        focusedWorkspaceId: root.focusedWorkspaceId
        vertical: root.vertical
        slotSize: root.itemSize
        iconSize: root.iconSize
        position: root.position
        onWorkspaceRequested: workspaceId => {
          var request = DockModel.focusWorkspaceRequest(
            workspaceId, Hyprland.usingLua)
          if (request) Hyprland.dispatch(request)
        }
      }
    }

    HoverHandler {
      id: pointer
    }
  }

  DockAppPicker {
    id: appPicker

    anchorItem: dockBackground
    position: root.position
    pinned: root.pinned
    onApplicationSelected: desktopId => root.pinRequested(desktopId)
  }

  DockSettings {
    id: dockSettings

    anchorItem: controlItem
    position: root.position
    settings: root.settings
    onVisibleChanged: if (!visible) root.clearSettingPreviews()
    onSettingPreviewed: (key, value) => root.previewSetting(key, value)
    onSettingCommitted: (key, value) => {
      root.settingChanged(key, value)
      root.clearSettingPreview(key)
    }
    onSettingsPatchCommitted: patch => {
      root.settingsPatchRequested(patch)
      for (var key in patch) root.clearSettingPreview(key)
    }
    onResetRequested: {
      root.clearSettingPreviews()
      root.resetSettingsRequested()
    }
  }

  HoverHandler {
    id: windowPointer
  }
}
