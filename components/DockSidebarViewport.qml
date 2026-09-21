pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "DockSidebarModel.js" as SidebarModel
import "DockSidebarInteractionModel.js" as InteractionModel
import "DockIconModel.js" as DockIconModel

FocusScope {
  id: root
  required property var controller
  // Theme-reactive card fills from the owning panel (phase 4).
  property var appearance: null
  // Connector of the owning PanelWindow; rows stamp this for Ctrl/drag.
  property string panelConnector: ""
  property bool panelCollapsed: false
  // Effective owning-panel visibility. Rail mode is separately excluded below.
  property bool presentationVisible: true
  // Phase 5 drives whole-workspace hover highlight; chrome already binds it.
  property string hoveredWorkspaceKey: ""
  readonly property var viewProjection: controller.projectionFor(panelCollapsed)
  readonly property var visibleRows: viewProjection.rows
  readonly property var sectionSpans: viewProjection.sectionSpans || []
  readonly property var listView: list
  property Component contentTail: null
  readonly property var contentTailItem: contentTailLoader.item
  property var contentTailDragPoint: null
  signal contentTailAutoScrolled()
  readonly property int rowCount: visibleRows.length
  readonly property real rowHeight: Math.max(34, Math.ceil(metrics.height + Style.space(12)))
  readonly property real workspaceCardInset: Style.space(5)
  readonly property real scrollGutter: 6
  readonly property real cardRadius: appearance && appearance.cardRadius !== undefined
    ? appearance.cardRadius : Math.min(3, Style.cornerRadius)
  readonly property color monitorFill: appearance ? appearance.monitorFill
    : Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035))
  readonly property color workspaceFill: appearance ? appearance.workspaceFill
    : Qt.darker(Color.background, 1.04)
  readonly property color workspaceHoverFill: appearance ? appearance.workspaceHoverFill
    : Qt.tint(workspaceFill, Util.alpha(Color.foreground, 0.09))
  readonly property color monitorDropFill: Style.pressedFillFor(Color.accent, Color.accent)
  activeFocusOnTab: true
  property var dragPoint: null
  signal contextRequested(var target, var anchorItem)
  signal dismissContextRequested()
  signal activationDispatched(var target, bool control, string connector, int modifiers, bool accepted)
  property bool restoring: false
  property bool pendingRestore: false
  property var previousKeys: []
  property real previousRowHeight: rowHeight
  property bool previousCollapsed: false
  // Mode whose list coordinates are valid for capture; updated after restore.
  // onPanelCollapsedChanged sees the new value, so this retains the outgoing mode.
  property bool scrollModeCollapsed: false
  property real previousContentHeight: 0
  property string previousHeightMap: ""
  // Bump when list geometry/model changes so offscreen span estimates refresh.
  property int sectionChromeRevision: 0
  FontMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.body }

  // Inline workspace chips are measured here, once per workspace, so every row
  // of that workspace renders the same badge width and therefore the same
  // artwork/label/hover/selection/guide geometry — including rows whose
  // leading delegate is scrolled out of view. The probes are invisible Text
  // nodes that exist only to measure the production badge font; nothing paints
  // them and they never join the hierarchy list.
  readonly property var inlineWorkspaceTargets: root.panelCollapsed
    ? [] : (root.viewProjection.workspaceTargets || [])
  readonly property real inlineWorkspaceBadgeAvailable: InteractionModel
    .sidebarInlineWorkspaceBadgeAvailableWidth(list.width, root.workspaceCardInset, Style.space)
  readonly property var inlineWorkspaceBadgeWidths: {
    var widths = {}
    for (var i = 0; i < inlineBadgeProbe.count; ++i) {
      var probe = inlineBadgeProbe.itemAt(i)
      if (probe) widths[probe.workspaceKey] = probe.layoutWidth
    }
    return widths
  }

  Repeater {
    id: inlineBadgeProbe
    model: ScriptModel { objectProp: "key"; values: root.inlineWorkspaceTargets }
    delegate: Text {
      required property var modelData
      visible: false
      text: InteractionModel.workspaceBadgeLabel(modelData.workspaceIdentity, modelData.label)
      textFormat: Text.PlainText
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      renderType: Text.NativeRendering
      readonly property string workspaceKey: String(modelData.key)
      readonly property real layoutWidth: InteractionModel.sidebarInlineWorkspaceBadgeLayoutWidth(
        implicitWidth, root.inlineWorkspaceBadgeAvailable, Style.space)
    }
  }

  function rowIntersectsViewport(rowY, rowHeightValue) {
    return root.presentationVisible && !root.panelCollapsed
      && InteractionModel.viewportIntersects(rowY, rowHeightValue, list.contentY, list.height)
  }

  function estimatedRowHeight(row) {
    var attention = root.controller.attentionForRow(row)
    var hasAlert = InteractionModel.sidebarRowHasNumericAlert(
      root.panelCollapsed, attention.countVisible)
    var base = InteractionModel.estimatedSidebarRowHeight(row, root.panelCollapsed,
      root.rowHeight, Style.space, hasAlert)
    if (root.windowFooterActive()
        && InteractionModel.isMonitorFinalKey(row.key, root.sectionSpans))
      return base + root.footerExtraHeight()
    return base
  }

  function rowMetricsFor(row) {
    var attention = root.controller.attentionForRow(row)
    var hasAlert = InteractionModel.sidebarRowHasNumericAlert(
      root.panelCollapsed, attention.countVisible)
    var metrics = InteractionModel.sidebarRowMetrics(row, root.panelCollapsed,
      root.rowHeight, Style.space, hasAlert)
    if (root.windowFooterActive()
        && InteractionModel.isMonitorFinalKey(row.key, root.sectionSpans)) {
      var extra = root.footerExtraHeight()
      metrics.gapAfter += extra
      metrics.height += extra
    }
    return metrics
  }

  function windowFooterActive() {
    var session = root.controller.dragSession
    return !!(root.controller.rowDragActive && session
      && session.target && session.target.kind === "window")
  }

  function footerTargetHeight() {
    return InteractionModel.newWorkspaceFooterTargetHeight(root.panelCollapsed)
  }

  function footerExtraHeight() {
    return InteractionModel.newWorkspaceFooterExtra(root.panelCollapsed, Style.space)
  }

  function isMonitorFinalKey(key) {
    return InteractionModel.isMonitorFinalKey(key, root.sectionSpans)
  }

  function footerKeyForRowKey(rowKey) {
    if (!InteractionModel.isMonitorFinalKey(rowKey, root.sectionSpans)) return ""
    var spans = root.sectionSpans
    for (var i = 0; i < spans.length; ++i) {
      var span = spans[i]
      if (!span || span.kind !== "monitor" || span.lastKey !== rowKey) continue
      var monitorRow = root.controller.rowsByKey[span.key]
      var identity = monitorRow ? String(monitorRow.monitorIdentity || "") : ""
      if (!identity) return ""
      return InteractionModel.newWorkspaceFooterKey(identity)
    }
    return ""
  }

  function refreshDragTarget() {
    if (!root.controller.rowDragActive || root.dragPoint === null) return
    root.controller.updateRowDrag(root.dropKey())
  }

  function beginContentTailDrag(sceneX, sceneY) {
    root.contentTailDragPoint = root.mapFromItem(null, sceneX, sceneY)
  }

  function updateContentTailDrag(sceneX, sceneY) {
    root.contentTailDragPoint = root.mapFromItem(null, sceneX, sceneY)
  }

  function endContentTailDrag() {
    root.contentTailDragPoint = null
  }

  function heightMap() {
    var rows = root.visibleRows
    var parts = []
    for (var i = 0; i < rows.length; ++i) {
      var item = list.itemAtIndex(i)
      parts.push(item ? Math.round(item.height) : Math.round(root.estimatedRowHeight(rows[i])))
    }
    return parts.join(",")
  }

  function rowYAtIndex(index) {
    var item = list.itemAtIndex(index)
    if (item) return item.y
    var y = 0
    var rows = root.visibleRows
    for (var i = 0; i < index && i < rows.length; ++i)
      y += root.estimatedRowHeight(rows[i])
    return y
  }

  // Content-coordinate Y for section painters: prefer live item.y, else
  // originY + shared-metrics prefix (same alert-aware heights as the ListView).
  function contentRowY(index) {
    var _rev = root.sectionChromeRevision
    var item = list.itemAtIndex(index)
    if (item) return item.y
    var y = list.originY
    var rows = root.visibleRows
    for (var i = 0; i < index && i < rows.length; ++i)
      y += root.estimatedRowHeight(rows[i])
    return y
  }

  function indexForKey(key) {
    var rows = root.visibleRows
    for (var i = 0; i < rows.length; ++i) {
      if (rows[i].key === key) return i
    }
    return -1
  }

  // Phase-3 span Y contract for painters.
  function sectionSpanRect(span) {
    var _rev = root.sectionChromeRevision
    if (!span || !span.firstKey || !span.lastKey)
      return { y: 0, height: 0 }
    var firstIdx = root.indexForKey(span.firstKey)
    var lastIdx = root.indexForKey(span.lastKey)
    if (firstIdx < 0 || lastIdx < 0)
      return { y: 0, height: 0 }
    var rows = root.visibleRows
    var firstM = root.rowMetricsFor(rows[firstIdx])
    var lastM = root.rowMetricsFor(rows[lastIdx])
    var top = root.contentRowY(firstIdx) + firstM.contentY
    var bottom = span.kind === "workspace"
      ? root.contentRowY(lastIdx) + lastM.contentY + lastM.contentHeight + Style.space(5)
      : root.contentRowY(lastIdx) + lastM.contentY + lastM.contentHeight + lastM.gapAfter
    return { y: top, height: Math.max(0, bottom - top) }
  }

  function bumpSectionChrome() {
    root.sectionChromeRevision += 1
  }

  function captureAnchor() {
    // Never write during restore or while list rows belong to a different mode.
    if (root.restoring || root.pendingRestore || !list.count) return
    if (root.scrollModeCollapsed !== root.panelCollapsed) return
    var index = list.indexAt(1, list.contentY + 1)
    if (index < 0) {
      var rows = root.visibleRows
      var y = 0
      index = 0
      for (var i = 0; i < rows.length; ++i) {
        var next = y + root.estimatedRowHeight(rows[i])
        if (list.contentY + 1 < next) { index = i; break }
        y = next
        index = i
      }
    }
    var row = root.visibleRows[index]
    var item = list.itemAtIndex(index)
    var keys = root.visibleRows.map(function(value) { return value.key })
    if (row) {
      root.controller.writeScrollState(root.panelConnector, root.panelCollapsed, {
        key: row.key,
        offset: list.contentY - (item ? item.y : root.rowYAtIndex(index))
      }, keys)
    }
    root.previousKeys = keys
    root.previousRowHeight = root.rowHeight
    root.previousCollapsed = root.panelCollapsed
    root.previousContentHeight = list.contentHeight
    root.previousHeightMap = root.heightMap()
  }

  function requestRestore() {
    // Avoid nested restore while forceLayout/contentY settle.
    if (root.restoring) return
    var keys = root.visibleRows.map(function(value) { return value.key })
    var map = root.heightMap()
    if (!InteractionModel.shouldRestoreScroll({
      keys: root.previousKeys, rowHeight: root.previousRowHeight,
      collapsed: root.previousCollapsed, contentHeight: root.previousContentHeight,
      heightMap: root.previousHeightMap
    }, {
      keys: keys, rowHeight: root.rowHeight, collapsed: root.panelCollapsed,
      contentHeight: list.contentHeight, heightMap: map
    })) {
      root.pendingRestore = false
      root.scrollModeCollapsed = root.panelCollapsed
      return
    }
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
  }

  function restoreAnchor() {
    root.restoring = true
    list.forceLayout()
    var rows = root.visibleRows
    var state = root.controller.readScrollState(root.panelConnector, root.panelCollapsed)
    var oldKeys = state.keys.length ? state.keys : root.previousKeys
    var anchor = SidebarModel.recoverAnchor(state.anchor, oldKeys, rows)
    var index = rows.findIndex(function(row) { return row.key === anchor.key })
    if (index >= 0) {
      list.positionViewAtIndex(index, ListView.Beginning)
      list.forceLayout()
      var item = list.itemAtIndex(index)
      var desired = (item ? item.y : root.rowYAtIndex(index)) + anchor.offset
      list.contentY = Math.min(Math.max(list.originY, desired),
        Math.max(list.originY, list.contentHeight - list.height + list.originY))
    } else list.contentY = list.originY
    var keys = rows.map(function(row) { return row.key })
    root.controller.writeScrollState(root.panelConnector, root.panelCollapsed, anchor, keys)
    root.previousKeys = keys
    root.previousRowHeight = root.rowHeight
    root.previousCollapsed = root.panelCollapsed
    root.previousContentHeight = list.contentHeight
    root.previousHeightMap = root.heightMap()
    root.scrollModeCollapsed = root.panelCollapsed
    root.pendingRestore = false
    root.restoring = false
    root.bumpSectionChrome()
  }

  function activate(target, control, connector, modifiers) {
    var accepted = root.controller.activateTarget(
      target, control, connector, Number(modifiers || 0))
    root.activationDispatched(target, control === true, connector, modifiers, accepted)
    return accepted
  }

  function focusRow(key) {
    var rows = root.visibleRows
    var index = rows.findIndex(function(row) { return row.key === key })
    if (index < 0 || !InteractionModel.focusable(rows[index])) return false
    if (root.controller.alertControlKey && root.controller.alertControlKey !== key)
      root.controller.clearAlertControl()
    root.controller.rememberNavigationFocus()
    root.controller.focusedRowKey = key
    list.positionViewAtIndex(index, ListView.Contain)
    list.forceLayout()
    var item = list.itemAtIndex(index)
    if (item) item.forceActiveFocus(Qt.TabFocusReason)
    return item !== null
  }

  function currentDelegate() {
    var index = root.visibleRows.findIndex(function(row) {
      return row.key === root.controller.focusedRowKey
    })
    return index >= 0 ? list.itemAtIndex(index) : null
  }

  function viewportHasKeyboardFocus() {
    var win = root.Window ? root.Window.window : null
    var focusItem = win ? win.activeFocusItem : null
    if (!focusItem) return !!root.activeFocus
    for (var item = focusItem; item; item = item.parent) {
      if (item === root) return true
    }
    return false
  }

  function syncFocusForProjection() {
    var hadFocus = root.viewportHasKeyboardFocus()
    var next = SidebarModel.remapFocusKey(root.controller.focusedRowKey, root.visibleRows,
      root.controller.rowsByKey)
    if (next !== root.controller.focusedRowKey)
      root.controller.focusedRowKey = next
    // Restore only when this viewport already owned keyboard focus (no steal).
    if (hadFocus && next)
      root.focusRow(next)
  }

  function cancelInputs(reason) {
    for (var i = 0; i < list.count; ++i) {
      var item = list.itemAtIndex(i)
      if (item && item.input) item.input.cancelGesture(reason)
    }
    root.controller.cancelRowDrag(reason)
    root.dragPoint = null
    root.hoveredWorkspaceKey = ""
  }

  function rowHits() {
    var hits = []
    var footerActive = root.windowFooterActive()
    var extra = footerActive ? root.footerExtraHeight() : 0
    for (var i = 0; i < list.count; ++i) {
      var item = list.itemAtIndex(i)
      if (!item || !item.visible) continue
      var point = root.mapFromItem(item, 0, 0)
      var height = item.height
      if (footerActive && extra > 0
          && InteractionModel.isMonitorFinalKey(item.rowKey, root.sectionSpans))
        height = Math.max(0, height - extra)
      hits.push({key:item.rowKey, kind:item.row.kind,
        workspaceIdentity:item.row.workspaceIdentity || "",
        monitorIdentity:item.row.monitorIdentity || "",
        x:point.x, y:point.y, width:item.width, height:height})
    }
    return hits
  }

  function footerHits() {
    var hits = []
    if (!root.windowFooterActive()) return hits
    var viewport = { x: 0, y: 0, width: root.width, height: root.height }
    var extra = root.footerExtraHeight()
    var target = root.footerTargetHeight()
    var separation = Style.space(5)
    for (var i = 0; i < list.count; ++i) {
      var item = list.itemAtIndex(i)
      if (!item || !item.visible) continue
      if (!InteractionModel.isMonitorFinalKey(item.rowKey, root.sectionSpans)) continue
      var footerKey = root.footerKeyForRowKey(item.rowKey)
      if (!footerKey) continue
      var monitorIdentity = InteractionModel.parseNewWorkspaceFooterKey(footerKey)
      if (!monitorIdentity) continue
      if (root.controller.windowActions) {
        var canonical = root.controller.windowActions.canonicalMonitorIdentity(monitorIdentity)
        if (!canonical) continue
      }
      var origin = root.mapFromItem(item, 0, 0)
      var inset = root.workspaceCardInset
      var rect = {
        x: origin.x + inset,
        y: origin.y + Math.max(0, item.height - extra) + separation,
        width: Math.max(0, item.width - inset * 2),
        height: target
      }
      var clipped = InteractionModel.clipRect(rect, viewport)
      if (!clipped) continue
      hits.push({
        key: footerKey,
        kind: "new-workspace",
        monitorIdentity: monitorIdentity,
        x: clipped.x, y: clipped.y, width: clipped.width, height: clipped.height
      })
    }
    return hits
  }

  // Workspace drops use painted monitor-card spans (headers, rows, padding,
  // empty interior), clipped to this hierarchy viewport — not footer/header
  // or gaps between cards. Keys remain the monitor row keys.
  function monitorCardHits() {
    var viewport = { x: 0, y: 0, width: root.width, height: root.height }
    var hits = []
    var spans = root.sectionSpans
    for (var i = 0; i < spans.length; ++i) {
      var span = spans[i]
      if (!span || span.kind !== "monitor") continue
      var geom = root.sectionSpanRect(span)
      if (!(geom.height > 0)) continue
      var origin = root.mapFromItem(list.contentItem, 0, geom.y)
      var clipped = InteractionModel.clipRect({
        x: origin.x, y: origin.y, width: list.width, height: geom.height
      }, viewport)
      if (!clipped) continue
      var row = root.controller.rowsByKey[span.key]
      hits.push({
        key: span.key,
        kind: "monitor",
        monitorIdentity: row ? (row.monitorIdentity || "") : "",
        x: clipped.x, y: clipped.y, width: clipped.width, height: clipped.height
      })
    }
    return hits
  }

  function dropKey() {
    if (!root.controller.dragSession) return ""
    var sourceKind = root.controller.dragSession.target.kind
    if (sourceKind === "workspace") {
      var cardHits = root.monitorCardHits()
      return InteractionModel.hitTarget(root.dragPoint, cardHits,
        {x:0,y:0,width:root.width,height:root.height}, sourceKind)
    }
    var viewport = {x:0,y:0,width:root.width,height:root.height}
    var footers = root.footerHits()
    for (var i = 0; i < footers.length; ++i) {
      var footer = footers[i]
      if (footer.width > 0 && footer.height > 0
          && root.dragPoint
          && root.dragPoint.x >= footer.x && root.dragPoint.x < footer.x + footer.width
          && root.dragPoint.y >= footer.y && root.dragPoint.y < footer.y + footer.height
          && viewport.width > 0 && viewport.height > 0
          && root.dragPoint.x >= viewport.x && root.dragPoint.x < viewport.x + viewport.width
          && root.dragPoint.y >= viewport.y && root.dragPoint.y < viewport.y + viewport.height)
        return footer.key
    }
    var hits = root.rowHits()
    return InteractionModel.hitTarget(root.dragPoint, hits,
      viewport, sourceKind)
  }

  function moveDrag(scenePoint) {
    root.dragPoint = root.mapFromItem(null, scenePoint.x, scenePoint.y)
    root.controller.updateRowDrag(root.dropKey())
  }

  function finishDrag(scenePoint) {
    root.dragPoint = root.mapFromItem(null, scenePoint.x, scenePoint.y)
    var key = root.dropKey()
    var result = root.controller.finishRowDrag(key)
    root.dragPoint = null
    return result
  }

  readonly property var keyboard: keyboardAdapter
  DockSidebarKeyboard { id: keyboardAdapter; viewport: root }
  Keys.forwardTo: [keyboardAdapter]
  function enterNavigation() {
    if (!root.activeFocus || root.controller.interactionBusy) return
    var item = root.currentDelegate()
    if (item && item.activeFocus) return
    root.focusRow(item ? root.controller.focusedRowKey
      : InteractionModel.nextKey(root.visibleRows, "", "home"))
  }

  // Defer until a pointer-selected child has updated the key. Mapping/hovering
  // never triggers this; re-entry via Tab restores a real visible focus target.
  onActiveFocusChanged: if (activeFocus) Qt.callLater(root.enterNavigation)
  onPanelCollapsedChanged: {
    root.hoveredWorkspaceKey = ""
    // Outgoing mode was already captured while scrollModeCollapsed matched.
    // visibleRows already flipped; never capture new coordinates into either key here.
    var incoming = root.controller.readScrollState(root.panelConnector, root.panelCollapsed)
    if (incoming.keys.length)
      root.previousKeys = incoming.keys
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
    root.syncFocusForProjection()
    root.bumpSectionChrome()
  }

  Timer {
    interval: 16
    repeat: true
    running: (root.controller.rowDragActive && root.dragPoint !== null)
      || root.contentTailDragPoint !== null
    onTriggered: {
      var point = root.controller.rowDragActive ? root.dragPoint : root.contentTailDragPoint
      var delta = point && point.x >= 0 && point.x < root.width
        ? InteractionModel.autoScrollStep(point.y, root.height) : 0
      if (!delta) return
      list.contentY = Math.max(list.originY, Math.min(
        Math.max(list.originY, list.contentHeight - list.height + list.originY), list.contentY + delta))
      list.forceLayout()
      if (root.controller.rowDragActive) root.controller.updateRowDrag(root.dropKey())
      else root.contentTailAutoScrolled()
    }
  }

  ListView {
    id: list
    objectName: "sidebar-window-list"
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.rightMargin: root.scrollGutter
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    orientation: ListView.Vertical
    keyNavigationEnabled: false

    // ScriptModel reconciles supplied domain keys; index is geometry only.
    model: ScriptModel { objectProp: "key"; values: root.visibleRows }
    delegate: DockSidebarRow {
      required property var modelData
      readonly property string stableKey: modelData.key
      // Visual metadata differs between expanded and rail projections.
      row: modelData
      controller: root.controller
      viewport: root
      appearance: root.appearance
      panelConnector: root.panelConnector
      collapsed: root.panelCollapsed
      rowHeight: root.rowHeight
      herdrAnimationEligible: root.rowIntersectsViewport(y, height)
      width: list.width
    }
    footer: Item {
      id: contentTailHost
      width: list.width
      height: root.panelCollapsed || !contentTailLoader.item
        ? 0 : Math.max(0, contentTailLoader.item.implicitHeight)
      Loader {
        id: contentTailLoader
        anchors.fill: parent
        active: root.contentTail !== null
        sourceComponent: root.contentTail
        onLoaded: Qt.callLater(root.requestRestore)
      }
      onHeightChanged: {
        root.bumpSectionChrome()
        root.refreshDragTarget()
        if (!root.restoring && !root.pendingRestore) {
          root.pendingRestore = true
          root.requestRestore()
        }
      }
    }
    onMovementEnded: root.captureAnchor()
    onContentYChanged: {
      if (!root.pendingRestore) root.captureAnchor()
      root.bumpSectionChrome()
      root.refreshDragTarget()
    }
    onContentHeightChanged: {
      // Rail alert 36→58 (and similar) can grow a row above the viewport without
      // a controller refresh; restore from the mode's saved anchor. Arm pending
      // first so contentY drift cannot overwrite that state via captureAnchor.
      root.bumpSectionChrome()
      root.refreshDragTarget()
      if (root.restoring || root.pendingRestore) return
      root.pendingRestore = true
      root.requestRestore()
    }
    onCountChanged: { root.bumpSectionChrome(); root.refreshDragTarget() }
    onOriginYChanged: { root.bumpSectionChrome(); root.refreshDragTarget() }

    Controls.ScrollBar.horizontal: Controls.ScrollBar {
      policy: Controls.ScrollBar.AlwaysOff
    }
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: verticalScrollBar
      parent: root
      anchors.top: list.top
      anchors.bottom: list.bottom
      anchors.right: root.right
      width: root.scrollGutter
      padding: 0
      policy: list.contentHeight > list.height
        ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
      contentItem: Rectangle {
        implicitWidth: root.scrollGutter
        implicitHeight: 40
        radius: width / 2
        color: Util.alpha(Color.foreground,
          verticalScrollBar.pressed ? 0.45
            : (verticalScrollBar.hovered ? 0.32 : 0.18))
      }
      background: Item {
        implicitWidth: root.scrollGutter
      }
    }

    // Section cards scroll with the list: parented to contentItem, below rows.
    // Monitor z < workspace z < delegates. No nested ListViews; no input.
    Item {
      id: sectionChromeHost
      parent: list.contentItem
      z: -2
      width: list.width
      height: Math.max(list.contentHeight, 1)
      // Direction A rail reuses the same sectionSpans + appearance cards.
      visible: true
      enabled: false

      Repeater {
        id: monitorChrome
        model: ScriptModel { objectProp: "key"; values: root.sectionSpans }
        delegate: Ui.BorderSurface {
          required property var modelData
          required property int index
          readonly property bool isMonitor: modelData && modelData.kind === "monitor"
          readonly property var geom: isMonitor ? root.sectionSpanRect(modelData) : { y: 0, height: 0 }
          readonly property bool dropTargetCard: isMonitor
            && root.controller.dragTarget
            && root.controller.dragTarget.key === modelData.key
          visible: isMonitor && geom.height > 0
          x: 0
          y: geom.y
          width: sectionChromeHost.width
          height: geom.height
          z: 0
          radius: root.cardRadius
          color: dropTargetCard ? root.monitorDropFill : root.monitorFill
          // No active-monitor outline; focused evidence stays on the topology
          // strip / rail. Drag-drop still uses monitorDropFill above.
          borderSpec: Border.none()
        }
      }

      Repeater {
        id: workspaceChrome
        model: ScriptModel { objectProp: "key"; values: root.sectionSpans }
        delegate: Item {
          required property var modelData
          required property int index
          readonly property bool isWorkspace: modelData && modelData.kind === "workspace"
          readonly property var geom: isWorkspace ? root.sectionSpanRect(modelData) : { y: 0, height: 0 }
          readonly property bool hoveredCard: isWorkspace
            && root.hoveredWorkspaceKey !== ""
            && modelData.key === root.hoveredWorkspaceKey
          visible: isWorkspace && geom.height > 0
          x: root.workspaceCardInset
          y: geom.y
          width: Math.max(0, sectionChromeHost.width - root.workspaceCardInset * 2)
          height: geom.height
          z: 1
          enabled: false

          Ui.BorderSurface {
            anchors.fill: parent
            radius: root.cardRadius
            color: parent.hoveredCard ? root.workspaceHoverFill : root.workspaceFill
            borderSpec: Border.none()
          }

          // Faint separator at the whole workspace card end (not under heading).
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Util.alpha(Color.foreground, 0.08)
          }
        }
      }
    }
  }
  Connections {
    target: root.controller
    function onAboutToRefresh() { root.captureAnchor(); root.pendingRestore = true }
    function onRefreshed() { root.requestRestore(); root.bumpSectionChrome() }
    function onSurfaceInvalidated() { root.cancelInputs("surface-invalidated") }
    function onRowDragActiveChanged() { if (!root.controller.rowDragActive) root.dragPoint = null }
  }
  onRowHeightChanged: {
    if (!root.previousKeys.length) return
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
    root.bumpSectionChrome()
  }
  onHeightChanged: root.requestRestore()
  onVisibleRowsChanged: root.bumpSectionChrome()
  Component.onCompleted: {
    root.scrollModeCollapsed = root.panelCollapsed
    root.previousCollapsed = root.panelCollapsed
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
  }
  // A passive proxy uses the same native artwork as the actual window row.
  // The proxy follows the cursor (+12 both axes); horizontal travel clamps by
  // the 22px leading artwork so the ghost keeps moving across the full panel
  // instead of pinning near the left edge behind its 160px width.
  Item {
    visible: root.controller.rowDragActive && root.dragPoint !== null
    enabled: false
    z: 100
    x: InteractionModel.dragProxyOffset(root.dragPoint ? root.dragPoint.x + 12 : 0, root.width, 22)
    y: InteractionModel.dragProxyOffset(root.dragPoint ? root.dragPoint.y + 12 : 0, root.height, height)
    width: Math.min(160, root.width)
    height: root.rowHeight
    property var sourceRow: root.controller.dragSession
      ? root.controller.rowsByKey[root.controller.dragSession.target.key] : null
    property var sourceWindowRule: sourceRow && sourceRow.kind === "window" && sourceRow.toplevel
      ? DockIconModel.matchWindowRule(root.controller.windowIconOverrides || [],
          String(sourceRow.toplevel.appId || ""), String(sourceRow.toplevel.title || ""))
      : null
    DockAppIcon {
      visible: parent.sourceRow && parent.sourceRow.kind === "window"
      width: 22; height: 22
      anchors.verticalCenter: parent.verticalCenter
      desktopId: parent.sourceRow ? String(parent.sourceRow.desktopId || "") : ""
      desktopIcon: parent.sourceRow && parent.sourceRow.item && parent.sourceRow.item.entry
        ? String(parent.sourceRow.item.entry.icon || "") : ""
      iconOverrides: root.controller.settings.iconOverrides || ({})
      windowOverrideSource: parent.sourceWindowRule
        ? String(parent.sourceWindowRule.source || "") : ""
      reloadRevision: root.controller.host.iconReloadRevision || 0
    }
    Text {
      visible: parent.sourceRow && parent.sourceRow.kind === "workspace"
      anchors.fill: parent
      text: parent.sourceRow ? String(parent.sourceRow.label || "") : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
  Component.onDestruction: {
    root.endContentTailDrag()
    root.cancelInputs("viewport-destroyed")
    root.captureAnchor()
  }
}
