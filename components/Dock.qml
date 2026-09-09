pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockWindowModel.js" as DockWindowModel
import "DockWindowPreviewModel.js" as PreviewModel
import "DockWorkspaceModel.js" as WorkspaceModel
import "DockBadgeModel.js" as BadgeModel
import "DockTrashModel.js" as TrashModel

PanelWindow {
  id: root

  required property var settings
  required property bool showTrash
  required property var windowActions
  required property var badgeTracker
  required property int trashItemCount
  required property bool trashStateKnown
  required property var workspaceWindowCounts
  required property bool workspaceCountsReady
  required property int workspaceCountsRevision
  required property int scopeRevision
  property var iconOverrides: ({})
  property int iconReloadRevision: 0
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
  property int badgeStateRevision: 0
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
  readonly property bool showPreviews: DockModel.normalizeSetting(
    "showPreviews", effectiveSetting("showPreviews"))
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
  readonly property bool workspaceBadgeBackgroundColorEnabled:
    DockModel.normalizeSetting(
      "workspaceBadgeBackgroundColorEnabled",
      effectiveSetting("workspaceBadgeBackgroundColorEnabled"))
  readonly property string workspaceBadgeBackgroundColorOverride:
    DockModel.normalizeSetting(
      "workspaceBadgeBackgroundColor",
      effectiveSetting("workspaceBadgeBackgroundColor"))
  readonly property color effectiveWorkspaceBadgeBackgroundColor:
    DockModel.effectiveColor(
      workspaceBadgeBackgroundColorEnabled,
      workspaceBadgeBackgroundColorOverride,
      Color.accent,
      themeColorTokens)
  readonly property bool workspaceBadgeTextColorEnabled:
    DockModel.normalizeSetting(
      "workspaceBadgeTextColorEnabled",
      effectiveSetting("workspaceBadgeTextColorEnabled"))
  readonly property string workspaceBadgeTextColorOverride:
    DockModel.normalizeSetting(
      "workspaceBadgeTextColor",
      effectiveSetting("workspaceBadgeTextColor"))
  readonly property color effectiveWorkspaceBadgeTextColor:
    DockModel.effectiveColor(
      workspaceBadgeTextColorEnabled,
      workspaceBadgeTextColorOverride,
      "#ffffff",
      themeColorTokens)
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
  readonly property var applicationActions: DockModel.normalizeApplicationActionConfig({
    clickAction: effectiveSetting("clickAction"),
    middleClickAction: effectiveSetting("middleClickAction"),
    scrollAction: effectiveSetting("scrollAction")
  })
  readonly property string controlCommand: DockModel.normalizeSetting(
    "controlCommand", effectiveSetting("controlCommand"))
  readonly property string position: DockModel.normalizeSetting(
    "position", effectiveSetting("position"))
  readonly property bool vertical: position === "left" || position === "right"
  readonly property bool fullLength: DockModel.normalizeSetting(
    "fullLength", effectiveSetting("fullLength"))
  readonly property bool sortByWorkspace: DockModel.normalizeSetting(
    "sortByWorkspace", effectiveSetting("sortByWorkspace"))
  readonly property string workspaceMonitorScope: DockModel.normalizeSetting(
    "workspaceMonitorScope", effectiveSetting("workspaceMonitorScope"))
  readonly property bool groupWindows: DockModel.normalizeSetting(
    "groupWindows", effectiveSetting("groupWindows"))
  readonly property string windowScope: DockWindowModel.normalizeWindowScope(
    effectiveSetting("windowScope"))
  readonly property bool showUrgentOutsideScope:
    DockWindowModel.normalizeShowUrgentOutsideScope(
      effectiveSetting("showUrgentOutsideScope"))
  readonly property bool attentionBadgesEnabled:
    typeof effectiveSetting("attentionBadgesEnabled") === "boolean"
      ? effectiveSetting("attentionBadgesEnabled") : true
  readonly property bool urgentWindowAnimationEnabled:
    typeof effectiveSetting("urgentWindowAnimationEnabled") === "boolean"
      ? effectiveSetting("urgentWindowAnimationEnabled") : true
  readonly property bool interfaceAnimationsEnabled: DockModel.normalizeSetting(
    "interfaceAnimationsEnabled", effectiveSetting("interfaceAnimationsEnabled"))
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
  readonly property var dockHyprMonitor: {
    var revision = scopeRevision
    return Hyprland.monitorFor(screen)
  }
  readonly property string focusedScopeWorkspace: {
    var revision = scopeRevision
    return DockWindowModel.focusedWorkspaceIdentity(
      hyprMonitors, Hyprland.focusedWorkspace)
  }
  readonly property var windowScopeContext: {
    var revision = scopeRevision
    return DockWindowModel.windowScopeContext(
      windowScope, focusedScopeWorkspace, dockHyprMonitor,
      showUrgentOutsideScope)
  }
  readonly property var filteredToplevels: {
    var revision = scopeRevision
    return DockWindowModel.filterToplevelsByScope(
      toplevels, hyprToplevels,
      windowActions ? windowActions.minimizedOriginsSnapshot : ({}),
      windowScopeContext)
  }
  readonly property int focusedWorkspaceId: {
    var revision = scopeRevision + workspaceCountsRevision
    return DockModel.focusedWorkspaceIdFromMonitors(
      hyprMonitors, Hyprland.focusedWorkspace)
  }
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property var fullscreenOwnerToplevel: DockModel.fullscreenOwner(
    toplevels, hyprToplevels, focusedWorkspaceId, activeToplevel,
    scopeRevision)
  readonly property bool fullscreenModeActive: fullscreenOwnerToplevel !== null
  property var visibleItems: []
  readonly property bool groupedRequested: !vertical
    && DockModel.normalizeSetting("workspaceLayout", effectiveSetting("workspaceLayout")) === "grouped"
  property var workspacePresentation: ({ groups: [], globalLaunchers: [], fallbackItems: [], renderedItems: [] })
  readonly property bool grouped: groupedRequested
  readonly property var renderedItems: grouped ? workspacePresentation.renderedItems : visibleItems
  readonly property string activeCardIdentity: {
    var active = workspacePresentation.groups.find(function(group) { return group.active })
    return active ? active.identity : ""
  }
  onActiveCardIdentityChanged: Qt.callLater(root.revealActiveWorkspace)

  readonly property var visibleWorkspaceIds: {
    var revision = scopeRevision + workspaceCountsRevision
    return DockModel.visibleWorkspaceIds(
      hyprWorkspaces, focusedWorkspaceId, hyprToplevels,
      workspaceWindowCounts, workspaceCountsReady)
  }
  readonly property int itemSize: iconSize + (grouped ? 14 : 22)
  readonly property int reservedSize: iconSize + (grouped ? 32 : 44) + edgeMargin
  readonly property int mainPadding: grouped ? 8 : 16
  readonly property int revealThickness: 3
  readonly property int crossExtent: vertical
    ? Math.ceil(iconSize * magnification + 80) + edgeMargin
    : Math.ceil(iconSize * magnification + 64) + edgeMargin
  readonly property int appMainExtent: grouped ? groupedLayout.desiredWidth : visibleItems.length * itemSize
  readonly property int workspaceMainExtent: grouped ? 0
    : (vertical ? workspaceStrip.height : workspaceStrip.width) + (showTrash ? 0 : 12)
  readonly property int trashMainExtent: TrashModel.sectionMainExtent(
    showTrash, itemSize, 12)
  readonly property int trailingMainExtent: TrashModel.trailingMainExtent(
    showTrash, itemSize, 12, workspaceMainExtent)
  readonly property int compactMainExtent: mainPadding * 2 + itemSize
    + appMainExtent + trailingMainExtent
  // Keep magnification space transparent, without shrinking the logical viewport.
  readonly property int groupedSurfaceTrim: mainPadding + groupedLayout.contentPadding - 4
  readonly property int groupedSurfaceGutter: Math.max(0, groupedLayout.contentPadding - 4)
  readonly property bool compactGroupedSurface: grouped && !vertical && !fullLength && !showTrash
    && (!screen || Math.max(compactMainExtent,
      compactMainExtent - groupedSurfaceTrim + groupedSurfaceGutter * 2) <= screen.width)
  readonly property int compactPanelExtent: compactGroupedSurface
    ? compactMainExtent - groupedSurfaceTrim + groupedSurfaceGutter * 2 : compactMainExtent
  readonly property bool keepAutoHideOpen: windowPointer.hovered
    || appPicker.visible || dockSettings.visible || openMenuCount > 0
    || dragSource >= 0 || windowPreview.interactionActive
  readonly property bool dockShown: !autoHide || autoHideRevealed
  readonly property real pointerPosition: !pointer.hovered
    ? -10000
    : vertical
      ? pointer.point.position.y
      : pointer.point.position.x

  function effectiveSetting(key) {
    return settingPreviews[key] !== undefined ? settingPreviews[key] : settings[key]
  }

  function refreshVisibleItems() {
    if (groupedRequested) {
      var monitor = dockHyprMonitor
      var ipc = monitor ? monitor.lastIpcObject || monitor : ({})
      var records = toplevels.map(function(toplevel) {
        return Object.assign({ toplevel: toplevel }, DockWindowModel.locationForToplevel(
          toplevel, hyprToplevels, windowActions ? windowActions.minimizedOriginsSnapshot : ({})))
      })
      var nextPresentation = WorkspaceModel.buildWorkspacePresentation(
        DockModel.buildVisibleItems(pinned, toplevels, applications, hyprToplevels,
          false, groupWindows, hiddenApplications), records, hyprWorkspaces, {
          monitor: DockWindowModel.monitorIdentity(monitor),
          monitorScope: workspaceMonitorScope,
          activeWorkspace: workspaceMonitorScope === "all" ? focusedScopeWorkspace
            : DockWindowModel.workspaceIdentity(ipc.activeWorkspace
            || (monitor ? monitor.activeWorkspace : null)),
          monitors: hyprMonitors,
          groupWindows: groupWindows
        })
      if (badgeTracker && screen)
        badgeTracker.syncWorkspaceScopes(screen.name,
          nextPresentation.groups.reduce(function(items, group) {
            return items.concat(group.items)
          }, []).concat(nextPresentation.globalLaunchers, nextPresentation.fallbackItems))
      if (!WorkspaceModel.presentationsEqual(workspacePresentation, nextPresentation)) {
        windowPreview.dismissImmediately()
        workspacePresentation = nextPresentation
      }
    }
    var nextItems = DockModel.buildVisibleItems(
      pinned, filteredToplevels, applications, hyprToplevels, sortByWorkspace,
      groupWindows, hiddenApplications)
    if (!DockModel.visibleItemsEqual(visibleItems, nextItems))
      visibleItems = nextItems
  }

  function scheduleVisibleItemsRefresh() {
    visibleItemsRefreshTimer.restart()
  }

  function primaryBadgeOwnerFor(index) {
    return BadgeModel.isPrimaryVisibleItem(renderedItems, index)
  }

  function attentionBadgeFor(item, index) {
    var badgeRevision = badgeStateRevision
    if (!attentionBadgesEnabled || !badgeTracker || !item) return "none"
    var owner = primaryBadgeOwnerFor(index)
    if (grouped)
      return badgeTracker.badgeFor(item.desktopId, { localUrgent: item.localUrgent, primaryOwner: owner })
    return owner ? badgeTracker.badgeFor(item.desktopId) : "none"
  }

  function revealActiveWorkspace() {
    if (!grouped) return
    for (var i = 0; i < workspaceCards.count; ++i) {
      var card = workspaceCards.itemAt(i)
      if (card && card.active) {
        groupedLayout.ensureVisible(card, card.headerWidth)
        break
      }
    }
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
  onOpenMenuCountChanged: if (openMenuCount > 0) windowPreview.dismissImmediately()
  onDragSourceChanged: if (dragSource >= 0) windowPreview.dismissImmediately()
  onShowPreviewsChanged: if (!showPreviews) windowPreview.dismissImmediately()
  onSettingsChanged: root.scheduleVisibleItemsRefresh()
  onSettingPreviewsChanged: root.scheduleVisibleItemsRefresh()
  onPinnedChanged: root.scheduleVisibleItemsRefresh()
  onWorkspaceMonitorScopeChanged: root.scheduleVisibleItemsRefresh()
  onFocusedScopeWorkspaceChanged: root.scheduleVisibleItemsRefresh()
  onSortByWorkspaceChanged: root.scheduleVisibleItemsRefresh()
  onGroupedChanged: {
    windowPreview.dismissImmediately()
    dragSource = -1
    dragTarget = -1
    if (!grouped && badgeTracker && screen) badgeTracker.syncWorkspaceScopes(screen.name, [])
    if (grouped) Qt.callLater(root.revealActiveWorkspace)
  }
  onDockHyprMonitorChanged: root.scheduleVisibleItemsRefresh()
  onHyprMonitorsChanged: root.scheduleVisibleItemsRefresh()
  onHyprWorkspacesChanged: root.scheduleVisibleItemsRefresh()
  Component.onDestruction: {
    if (badgeTracker && screen) badgeTracker.syncWorkspaceScopes(screen.name, [])
  }
  onWorkspaceCountsRevisionChanged: root.scheduleVisibleItemsRefresh()
  onGroupWindowsChanged: root.scheduleVisibleItemsRefresh()
  onHiddenApplicationsChanged: root.scheduleVisibleItemsRefresh()
  onScopeRevisionChanged: {
    if (windowPreview) windowPreview.dismissImmediately()
    root.scheduleVisibleItemsRefresh()
  }

  Component.onCompleted: root.scheduleVisibleItemsRefresh()

  Connections {
    target: root.windowActions
    function onMinimizedOriginsSnapshotChanged() { root.scheduleVisibleItemsRefresh() }
  }

  Connections {
    target: root.badgeTracker

    function onRevisionChanged() {
      root.badgeStateRevision++
      root.scheduleVisibleItemsRefresh()
    }
  }

  Timer {
    id: visibleItemsRefreshTimer

    interval: 0
    repeat: false
    onTriggered: root.refreshVisibleItems()
  }

  Timer {
    id: visibleItemsRawEventTimer

    interval: 80
    repeat: false
    onTriggered: root.scheduleVisibleItemsRefresh()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      var name = event ? event.name : ""
      if (["windowtitle", "windowtitlev2"].indexOf(String(name)) >= 0)
        visibleItemsRawEventTimer.restart()
    }
  }

  Connections {
    target: DesktopEntries.applications
    ignoreUnknownSignals: true

    function onValuesChanged() {
      root.scheduleVisibleItemsRefresh()
    }
  }

  Connections {
    target: ToplevelManager.toplevels
    ignoreUnknownSignals: true

    function onValuesChanged() {
      root.scheduleVisibleItemsRefresh()
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      root.scheduleVisibleItemsRefresh()
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
    : fullLength ? 0 : grouped && screen ? screen.width : compactPanelExtent
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

    // Keep the grouped native surface stable while cards resize inside it.
    // The compact input region leaves the transparent sides click-through.
    width: root.grouped && !root.fullLength
      ? Math.min(parent.width, root.compactPanelExtent) : parent.width
    height: parent.height
    x: (parent.width - width) / 2
  }

  Item {
    id: revealStrip

    x: root.vertical ? (root.position === "right" ? parent.width - width : 0)
      : interactionArea.x
    y: root.position === "bottom" ? parent.height - height : 0
    width: root.vertical ? root.revealThickness : interactionArea.width
    height: root.vertical ? parent.height : root.revealThickness
  }

  BorderSurface {
    id: dockBackground

    x: root.vertical
      ? root.position === "left" ? root.edgeMargin : parent.width - width - root.edgeMargin
      : interactionArea.x + (root.compactGroupedSurface ? root.groupedSurfaceGutter : 0)
    y: root.vertical
      ? 0
      : root.position === "top" ? root.edgeMargin : parent.height - height - root.edgeMargin
    width: root.vertical ? root.iconSize + 44
      : interactionArea.width - (root.compactGroupedSurface ? root.groupedSurfaceGutter * 2 : 0)
    height: root.vertical ? parent.height : root.iconSize + (root.grouped ? 32 : 44)
    radius: Math.max(18, Style.cornerRadius)
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

    Rectangle {
      x: dockBackground.radius
      y: Math.max(1, Border.top(root.dockBorderSpec))
      width: Math.max(0, parent.width - x * 2)
      height: 1
      visible: !root.borderColorEnabled && !root.borderWidthEnabled
      color: Qt.rgba(root.dockBorderColor.r, root.dockBorderColor.g,
        root.dockBorderColor.b, root.dockBorderColor.a * root.dockBackgroundColor.a * 0.12)
    }

    Item {
      id: dockLayout

      width: parent.width + (root.compactGroupedSurface ? root.groupedSurfaceTrim : 0)
      height: parent.height

      readonly property real leadingEnd: root.mainPadding + root.itemSize
      readonly property real trailingStart: (root.vertical ? height : width)
        - root.mainPadding - root.trailingMainExtent
      readonly property real trashOffset: root.showTrash
        ? (root.vertical ? appTrashSeparator.height : appTrashSeparator.width)
          + root.trashMainExtent : 0
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
        interfaceAnimationsEnabled: root.interfaceAnimationsEnabled
        onSettingsRequested: dockSettings.open()
        onAddApplicationRequested: appPicker.open()
        onAutoHideToggled: enabled => root.autoHideRequested(enabled)
        onContextMenuVisibilityChanged: visible => {
          root.openMenuCount = Math.max(0, root.openMenuCount + (visible ? 1 : -1))
        }
      }

      Grid {
        id: appGrid
        visible: !root.grouped

        x: root.vertical ? (parent.width - width) / 2 : parent.appStart
        y: root.vertical ? parent.appStart : (parent.height - height) / 2
        columns: root.vertical ? 1 : Math.max(1, root.visibleItems.length)
        rows: root.vertical ? Math.max(1, root.visibleItems.length) : 1

        Repeater {
          model: root.grouped ? [] : root.visibleItems

          AppIcon {}
        }
      }

      DockWorkspaceLayout {
        id: groupedLayout
        visible: root.grouped
        x: dockLayout.appStart
        width: Math.max(0, Math.min(desiredWidth, dockLayout.trailingStart - x))
        height: root.crossExtent - root.edgeMargin
        y: root.position === "top" ? 0 : dockLayout.height - height
        rowY: root.position === "top" ? (dockLayout.height - root.itemSize - 10) / 2
          : height - (dockLayout.height + root.itemSize + 10) / 2
        contentPadding: Math.ceil(root.iconSize * (root.magnification
          * DockModel.fullscreenIconPresentation(
            root.fullscreenModeActive, root.fullscreenModeActive, false).scale - 1) / 2) + 1
        foreground: Color.menu.text
        background: Color.menu.background
        accent: Color.accent
        animationsEnabled: root.interfaceAnimationsEnabled
        onViewportChanged: windowPreview.refreshAnchorGeometry()
        DockPresentationModel {
          id: workspacePresentationModel
          sourceItems: root.groupedRequested ? root.workspacePresentation.groups : []
          keyProperty: "identity"
          animationsEnabled: root.interfaceAnimationsEnabled
        }
        Repeater {
          model: root.groupedRequested ? root.workspacePresentation.globalLaunchers : []
          AppIcon { y: 2 }
        }
        Repeater {
          id: workspaceCards
          model: workspacePresentationModel.model
          DockAnimatedSlot {
            id: workspaceCardSlot
            required property var modelData
            required property int index
            present: modelData.present
            animateEntrance: modelData.animateEntrance
            animationsEnabled: root.interfaceAnimationsEnabled
            exitRevision: modelData.exitRevision
            naturalWidth: workspaceCard.width
            naturalHeight: workspaceCard.height
            trailingGap: 0
            onExitFinished: revision => workspacePresentationModel.completeRemoval(
              modelData.token, revision)

            DockWorkspaceGroup {
              id: workspaceCard
              animationsEnabled: root.interfaceAnimationsEnabled
              modelData: workspaceCardSlot.modelData.item
              property var modelData
              label: modelData.label
              count: modelData.count
              urgent: modelData.urgent === true && root.attentionBadgesEnabled
              position: root.position
              viewport: groupedLayout
              active: modelData.active
              slotSize: root.itemSize
              applicationModel: appPresentationModel.model
              applicationDelegate: Component {
                DockAnimatedSlot {
                  id: appSlot
                  required property var modelData
                  required property int index
                  present: modelData.present
                  animateEntrance: modelData.animateEntrance
                  animationsEnabled: root.interfaceAnimationsEnabled
                  exitRevision: modelData.exitRevision
                  naturalWidth: root.itemSize
                  naturalHeight: root.itemSize + 6
                  trailingGap: index < appPresentationModel.entries.length - 1 ? 6 : 0
                  onExitFinished: revision => appPresentationModel.completeRemoval(
                    modelData.token, revision)
                  AppIcon {
                    modelData: appSlot.modelData.item
                    index: appSlot.index
                    presentationActive: appSlot.modelData.present
                      && workspaceCardSlot.modelData.present
                  }
                }
              }
            onActivated: {
              var request = DockModel.focusWorkspaceTargetRequest(modelData.activationTarget, Hyprland.usingLua)
              if (request) Hyprland.dispatch(request)
            }
            }

            DockPresentationModel {
              id: appPresentationModel
              sourceItems: workspaceCard.modelData.items
              keyProperty: "presentationId"
              animationsEnabled: root.interfaceAnimationsEnabled
            }

          }
        }
        DockWorkspaceGroup {
          visible: root.groupedRequested && root.workspacePresentation.fallbackItems.length > 0
          label: "Other windows"
          position: root.position
          viewport: groupedLayout
          count: root.workspacePresentation.fallbackItems.reduce(function(total, item) {
            return total + item.toplevels.length
          }, 0)
          active: false
          switchable: false
          slotSize: root.itemSize
          Repeater {
            model: root.groupedRequested ? root.workspacePresentation.fallbackItems : []
            AppIcon {}
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
        visible: root.showTrash
      }

      DockTrashItem {
        id: trashItem

        x: root.vertical
          ? (parent.width - width) / 2
          : parent.trailingStart + appTrashSeparator.width
        y: root.vertical
          ? parent.trailingStart + appTrashSeparator.height
          : (parent.height - height) / 2
        visible: root.showTrash
        enabled: root.showTrash
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
        interfaceAnimationsEnabled: root.interfaceAnimationsEnabled
        vertical: root.vertical
        onOpenRequested: root.openTrashRequested()
        onEmptyRequested: root.emptyTrashRequested()
        onContextMenuVisibilityChanged: visible => {
          root.openMenuCount = Math.max(0, root.openMenuCount + (visible ? 1 : -1))
        }
      }

      DockSeparator {
        id: trashWorkspaceSeparator

        x: root.vertical
          ? (parent.width - width) / 2
          : parent.trailingStart + (root.showTrash ? appTrashSeparator.width + trashItem.width : 0)
        y: root.vertical
          ? parent.trailingStart + (root.showTrash ? appTrashSeparator.height + trashItem.height : 0)
          : (parent.height - height) / 2
        visible: !root.grouped
        vertical: root.vertical
        slotSize: root.itemSize
        iconSize: root.iconSize
      }

      DockWorkspaceStrip {
        id: workspaceStrip
        visible: !root.grouped

        x: root.vertical
          ? (parent.width - width) / 2
          : parent.trailingStart + parent.trashOffset + (root.showTrash ? 0 : 12)
        y: root.vertical
          ? parent.trailingStart + parent.trashOffset + (root.showTrash ? 0 : 12)
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
        animationsEnabled: root.interfaceAnimationsEnabled
        onWorkspaceRequested: workspaceId => {
          var request = DockModel.focusWorkspaceRequest(
            workspaceId, Hyprland.usingLua)
          if (request) Hyprland.dispatch(request)
        }
      }
    }

    HoverHandler {
      id: pointer
      parent: root.vertical ? dockBackground : dockLayout
    }
  }

  component AppIcon: DockItem {
    id: appItem
    required property var modelData
    required property int index
    originOnly: modelData.presentationId !== undefined
    scopeRevision: root.scopeRevision
    presentationId: modelData.presentationId || modelData.desktopId
    identityToplevel: modelData.identityToplevel || null

    desktopId: modelData.desktopId
    iconOverrides: root.iconOverrides
    iconReloadRevision: root.iconReloadRevision
    pinnedItem: modelData.pinned
    runningToplevels: modelData.toplevels
    focused: root.activeToplevel !== null
      && modelData.toplevels.indexOf(root.activeToplevel) >= 0
    windowActions: root.windowActions
    hyprToplevels: root.hyprToplevels
    badgeTracker: root.badgeTracker
    readonly property int renderedIndex: {
      if (!originOnly) return index
      var items = root.renderedItems
      return items.indexOf(PreviewModel.visiblePreviewTarget(
        items, presentationId, identityToplevel))
    }
    localUrgent: modelData.localUrgent === true
    sticky: modelData.sticky === true
    attentionScopeKey: originOnly && root.badgeTracker && root.screen
      ? root.badgeTracker.workspaceScopeKey(root.screen.name, modelData.presentationId) : ""
    attentionBadge: root.attentionBadgeFor(modelData, renderedIndex)
    attentionBadgesEnabled: root.attentionBadgesEnabled
    urgentWindowAnimationEnabled: root.urgentWindowAnimationEnabled
    interfaceAnimationsEnabled: root.interfaceAnimationsEnabled
    presentationActive: true
    primaryBadgeOwner: root.primaryBadgeOwnerFor(renderedIndex)
    presentationVisible: !originOnly || groupedLayout.containsItem(appItem)
    Connections {
      target: groupedLayout
      function onViewportChanged() {
        appItem.presentationVisible = !appItem.originOnly || groupedLayout.containsItem(appItem)
        if (!appItem.presentationVisible) appItem.dismissPopups()
        else appItem.refreshPopupGeometry()
      }
    }
    dockShown: root.dockShown
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
    pointerPosition: !pointer.hovered || !parent ? -10000 : root.vertical
      ? parent.mapFromItem(dockBackground, pointer.point.position.x, pointer.point.position.y).y
      : parent.mapFromItem(dockLayout, pointer.point.position.x, pointer.point.position.y).x
    applicationActions: root.applicationActions
    showPreviews: root.showPreviews
    workspaceBadgeBackgroundColor: root.effectiveWorkspaceBadgeBackgroundColor
    workspaceBadgeTextColor: root.effectiveWorkspaceBadgeTextColor
    autoHide: root.autoHide
    position: root.position
    vertical: root.vertical
    previewActive: windowPreview.anchorItem === appItem
      && windowPreview.interactionActive
    reorderOffset: originOnly ? 0 : root.reorderOffset(index)
    onDragStarted: itemIndex => {
      root.dragSource = itemIndex
      root.dragTarget = itemIndex
    }
    onDragMoved: mainPosition => root.updateDragTarget(mainPosition)
    onDragFinished: root.finishDrag()
    onRemoveRequested: desktopId => root.unpinRequested(desktopId)
    onHideRequested: desktopId => root.hideRequested(desktopId)
    onPreviewRequested: (anchorItem, desktopId, toplevels, applicationEntry) => {
      windowPreview.requestPreview(
        anchorItem, desktopId, toplevels, applicationEntry)
    }
    onPreviewReleased: anchorItem => windowPreview.releasePreview(anchorItem)
    onPreviewDismissRequested: windowPreview.dismissImmediately()
    onContextMenuVisibilityChanged: visible => {
      root.openMenuCount = Math.max(0,
        root.openMenuCount + (visible ? 1 : -1))
    }
  }

  DockWindowPreview {
    id: windowPreview

    windowActions: root.windowActions
    position: root.position
    visibleItems: root.renderedItems
    clipItem: root.grouped ? groupedLayout : null
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
    themeColorTokens: root.themeColorTokens
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
    parent: interactionArea
  }
}
