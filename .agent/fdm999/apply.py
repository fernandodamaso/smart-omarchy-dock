from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent

def read(path): return Path(path).read_text()
def write(path, source): Path(path).write_text(source)
def replace(source, old, new):
    if old not in source: raise RuntimeError('Missing expected source: ' + old[:100])
    return source.replace(old, new)
def block(source, marker):
    pos = source.index(marker)
    start = source.rfind('\n', 0, pos) + 1
    if marker.startswith('id:'):
        start = source.rfind('\n', 0, source.rfind('{', 0, pos)) + 1
    opening = source.index('{', start)
    tokens = re.finditer(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', source[opening:])
    depth = 0
    for token in tokens:
        if token.group() == '{': depth += 1
        elif token.group() == '}':
            depth -= 1
            if depth == 0: return source[start:opening + token.end()]
    raise RuntimeError('Unbalanced block: ' + marker)

MODEL = '''
// Natural demands and allocations are logical pixels. Never allocate from a
// virtualized ListView estimate or persist a runtime clamp as a preference.
function sidebarSplitLayout(input) {
  input = input || {}
  var A = Math.max(0, finite(input.availableHeight, 0))
  var H = Math.max(0, finite(input.hierarchyContentHeight, 0))
  var Wh = Math.max(0, finite(input.widgetHeaderHeight, 0))
  var W = Math.max(0, finite(input.widgetContentHeight, 0))
  var count = Math.max(0, Math.floor(finite(input.presentedWidgetCount, 0)))
  var h = 0, w = 0
  if (input.rail === true || count === 0 || A < Wh) {
    h = Math.min(H, A)
  } else {
    var wanted = Math.min(Number.MAX_VALUE, Wh + W)
    var hmin = Math.min(H, Math.max(0, finite(input.minHierarchyHeight, 0)))
    var wmin = Math.min(wanted, Math.max(Wh, finite(input.minWidgetHeight, Wh)))
    if (A < hmin + wmin) {
      h = Math.min(hmin, Math.max(0, A - Wh))
    } else {
      var request = finite(input.requestedSplitPx, 0.55 * A)
      var cap = Math.max(hmin, Math.min(A - wmin, request))
      h = Math.min(H, Math.max(cap, A - wanted))
    }
    w = Math.min(wanted, Math.max(0, A - h))
  }
  return {hierarchyHeight:h, widgetHeight:w, blankHeight:Math.max(0, A - h - w)}
}

// Panel-local stable-ID scroll anchors. These helpers never write settings.
function widgetScrollAnchor(cards, contentY) {
  cards = cards || []
  var y = Math.max(0, finite(contentY, 0))
  var ids = cards.map(function(card) { return card.id })
  if (!cards.length) return {id:"", offset:0, ids:ids}
  var index = cards.length - 1
  for (var i = 0; i < cards.length; ++i) {
    if (cards[i].y + cards[i].height > y) { index = i; break }
  }
  return {id:cards[index].id, offset:y - cards[index].y, ids:ids}
}
function widgetScrollPosition(anchor, cards, maximum) {
  anchor = anchor || {}; cards = cards || []
  var ids = cards.map(function(card) { return card.id })
  var index = ids.indexOf(anchor.id), offset = finite(anchor.offset, 0)
  if (index < 0) {
    var old = anchor.ids || [], at = old.indexOf(anchor.id)
    offset = 0
    for (var i = at + 1; i < old.length && index < 0; ++i) index = ids.indexOf(old[i])
    for (var j = at - 1; j >= 0 && index < 0; --j) index = ids.indexOf(old[j])
  }
  var y = index < 0 ? 0 : cards[index].y + offset
  return Math.max(0, Math.min(Math.max(0, finite(maximum, 0)), y))
}
function widgetFocusScroll(y, height, contentY, viewportHeight, maximum) {
  y = finite(y, 0); height = Math.max(0, finite(height, 0))
  var top = finite(contentY, 0), size = Math.max(0, finite(viewportHeight, 0))
  var next = height > size || y < top ? y : y + height > top + size ? y + height - size : top
  return Math.max(0, Math.min(Math.max(0, finite(maximum, 0)), next))
}
'''

MIDDLE = '''    Item {
      id: middleRegion
      objectName: "sidebar-middle-region"
      anchors.top: controls.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: pinnedStrip.top
      anchors.bottomMargin: root.panelCollapsed ? 0 : Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(6) + (!root.panelCollapsed ? root.resizeEdgeAllowance : 0)
      anchors.rightMargin: Style.space(6) + (!root.panelCollapsed ? root.resizeEdgeAllowance : 0)
      readonly property var split: WidgetModel.sidebarSplitLayout({
        availableHeight: Math.max(0, height),
        hierarchyContentHeight: sidebarViewport.naturalContentHeight,
        widgetHeaderHeight: sidebarWidgets.naturalWidgetHeaderHeight,
        widgetContentHeight: sidebarWidgets.naturalWidgetContentHeight,
        presentedWidgetCount: sidebarWidgets.presentedWidgetCount,
        rail: root.panelCollapsed,
        minHierarchyHeight: InteractionModel.sidebarRowMetrics({kind:"monitor"}, false,
          sidebarViewport.rowHeight, Style.space, false).height + 2 * sidebarViewport.rowHeight,
        minWidgetHeight: sidebarWidgets.naturalWidgetHeaderHeight + Style.space(34),
        requestedSplitPx: null
      })
      DockSidebarViewport {
        id: sidebarViewport
        width: parent.width
        height: middleRegion.split.hierarchyHeight
        controller: root.controller
        appearance: root.sidebarAppearance
        panelConnector: String(root.screen && root.screen.name || "")
        panelCollapsed: root.panelCollapsed
        presentationVisible: root.visible
        tabForwardTarget: sidebarWidgets.sectionVisible ? sidebarWidgets.manageControl : root.footerControl
        onContextRequested: (target, anchorItem) => root.openContext(target, anchorItem)
        onDismissContextRequested: sidebarContext.dismiss()
      }
      DockSidebarWidgetArea {
        id: sidebarWidgets
        y: sidebarViewport.height
        width: parent.width
        height: middleRegion.split.widgetHeight
        appearance: root.sidebarAppearance
        controller: root.controller
        panel: root
        viewport: sidebarViewport
        windowRowHeight: sidebarViewport.rowHeight
      }
      DockPositionDragSurface {
        id: viewportDragSurface
        y: middleRegion.split.hierarchyHeight + middleRegion.split.widgetHeight
        width: parent.width
        height: middleRegion.split.blankHeight
        visible: width > 0 && height > 0
        dockPosition: root.sidebarEdge
        requestedPosition: root.sidebarEdge
        switchThreshold: 48
        presentationMode: root.presentationMode
        gestureToken: root.modeGestureToken
        sidebarEdge: root.sidebarEdge
        animationsEnabled: root.animationsEnabled
        interactionAllowed: visible && !root.controller.interactionBusy
        onPositionRequested: (position, expectedPosition, gestureToken) =>
          root.commitModeSwitch(position, gestureToken)
      }
    }'''

SCROLL = '''  Flickable {
    id: widgetScroll
    objectName: "sidebar-widget-scroll"
    y: root.naturalWidgetHeaderHeight
    width: parent.width
    height: root.sectionVisible ? Math.max(0, root.height - y) : 0
    visible: height > 0
    clip: true
    contentWidth: width
    contentHeight: root.naturalWidgetContentHeight
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    onContentYChanged: {
      if (root.pendingRestore && root.inputBusy && !root.restoring && root.savedAnchor.id) {
        var delta = contentY - Math.max(0, Math.min(root.maximumScroll, root.lastContentY))
        root.savedAnchor = Object.assign({}, root.savedAnchor, {offset:root.savedAnchor.offset + delta})
      }
      root.lastContentY = contentY
      root.captureAnchor()
      geometryTimer.restart()
    }
    onContentHeightChanged: root.requestLayout()
    onMovementEnded: { if (root.pendingRestore) layoutTimer.restart(); else root.captureAnchor() }
    WheelHandler {
      target: null
      blocking: false
      onWheel: function(event) {
        root.wheelActive = true
        wheelIdle.restart()
        // Nonblocking observation: children retain first refusal/native wheel actions.
        event.accepted = false
      }
    }
    // Alpha mask, not another surface tint; no input item overlays the content.
    layer.enabled: root.remainingBelow && height > 0 && GraphicsInfo.api !== GraphicsInfo.Software
    layer.effect: OpacityMask {
      maskSource: Rectangle {
        width: widgetScroll.width; height: widgetScroll.height
        gradient: Gradient {
          GradientStop { position: Math.max(0, 1 - root.fadeHeight / Math.max(1, widgetScroll.height)); color: "white" }
          GradientStop { position: 1; color: "transparent" }
        }
      }
    }
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: verticalScrollBar
      parent: root
      x: root.width - width + root.viewport.scrollBarOutset
      y: widgetScroll.y
      width: root.viewport.scrollGutter
      height: widgetScroll.height
      padding: 0
      policy: widgetScroll.contentHeight > widgetScroll.height && widgetScroll.height > 0
        ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
      contentItem: Rectangle {
        implicitWidth: root.viewport.scrollGutter
        implicitHeight: 40
        radius: width / 2
        color: Util.alpha(Color.foreground, verticalScrollBar.pressed ? 0.45 : verticalScrollBar.hovered ? 0.32 : 0.18)
      }
      background: Item { implicitWidth: root.viewport.scrollGutter }
    }
'''
SUFFIX = '''
  Timer { id: layoutTimer; interval: 0; onTriggered: root.settleLayout() }
  Timer {
    id: geometryTimer
    interval: 0
    onTriggered: {
      root.layoutRevision = (root.layoutRevision + 1) % 1000000000
      root.anchorRevision = root.layoutRevision
      root.updatePopupAnchor()
    }
  }
  Timer { id: wheelIdle; interval: 150; onTriggered: root.wheelActive = false }
  Timer {
    interval: 16; repeat: true
    running: root.dragWidgetId !== ""
    onTriggered: {
      if (!root.dragPointInBody(root.dragSceneX, root.dragSceneY)) return
      var point = widgetScroll.mapFromItem(null, root.dragSceneX, root.dragSceneY)
      var delta = InteractionModel.autoScrollStep(point.y, widgetScroll.height)
      if (!delta) return
      widgetScroll.contentY = Math.max(0, Math.min(root.maximumScroll, widgetScroll.contentY + delta))
      root.updateDrag(root.dragSceneX, root.dragSceneY)
    }
  }
  Connections {
    target: root.Window.window
    function onActiveFocusItemChanged() { root.trackFocus() }
  }
  Connections {
    target: root.controller
    function onWidgetAnchorChanged() { geometryTimer.restart() }
    function onWidgetDragIdChanged() { root.syncDragFromController() }
    function onSurfaceInvalidated() { root.closePopup(); root.closeManager(); root.finishDrag(0, 0, true) }
    function onEdgeChanged() { root.finishDrag(0, 0, true); geometryTimer.restart() }
  }
  Connections {
    target: root.panel
    function onWidthChanged() { root.requestLayout() }
    function onHeightChanged() { root.requestLayout() }
    function onScreenChanged() { root.finishDrag(0, 0, true); geometryTimer.restart() }
    function onVisibleChanged() {
      if (!root.panel.visible) { root.closePopup(); root.closeManager(); root.finishDrag(0, 0, true) }
      root.requestLayout()
    }
    function onPanelCollapsedChanged() {
      if (root.panel.panelCollapsed) { root.closePopup(); root.closeManager(); root.finishDrag(0, 0, true) }
      root.requestLayout()
    }
  }
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape && root.dragWidgetId) {
      root.finishDrag(0, 0, true); event.accepted = true
    }
  }
  onPresentationWidgetIdsChanged: {
    if (root.dragWidgetId && JSON.stringify(root.dragOrder) !== JSON.stringify(root.presentationWidgetIds))
      root.finishDrag(0, 0, true)
    if (root.ownsWidgetFocus && root.focusedWidgetId && root.presentationWidgetIds.indexOf(root.focusedWidgetId) < 0)
      root.focusRecovery = {id:root.focusedWidgetId, ids:root.savedAnchor.ids || []}
    root.requestLayout()
  }
  onSectionVisibleChanged: {
    if (!sectionVisible) { root.closePopup(); root.finishDrag(0, 0, true) }
    root.requestLayout()
  }
  onInputBusyChanged: if (!inputBusy && root.pendingRestore) layoutTimer.restart()
  onPanelOriginChanged: geometryTimer.restart()
  onWidthChanged: root.requestLayout()
  onHeightChanged: root.requestLayout()
  Component.onCompleted: root.requestLayout()
  Component.onDestruction: { root.finishDrag(0, 0, true); root.closePopup() }
}
'''

if sys.argv[1] == 'model':
    path = 'components/DockSidebarWidgetModel.js'
    s = read(path)
    assert 'function sidebarSplitLayout(' not in s
    s += MODEL
    write(path, s)
    path = 'components/DockSidebarViewport.qml'
    s = read(path)
    s = replace(s, '  readonly property int rowCount:', '''  // Allocate from canonical projection metrics, never a virtualized estimate.
  readonly property real naturalContentHeight: {
    var total = 0
    for (var i = 0; i < root.visibleRows.length; ++i)
      total += root.rowMetricsFor(root.visibleRows[i]).height
    return total
  }
  readonly property int rowCount:''')
    write(path, s)
    sys.exit(0)

# Remove only obsolete Widget-tail ownership. Preserve hierarchy drag/restore.
path = 'components/DockSidebarViewport.qml'; s = read(path)
s = replace(s, '  required property var controller\n', '  required property var controller\n  property Item tabForwardTarget: null\n')
s = re.sub(r'^  (?:property Component contentTail:.*|readonly property var contentTailItem:.*|property var contentTailDragPoint:.*|signal contentTailAutoScrolled\(\))\n', '', s, flags=re.M)
for name in ['beginContentTailDrag', 'updateContentTailDrag', 'endContentTailDrag']:
    s = replace(s, block(s, 'function ' + name + '('), '')
s = replace(s, block(s, 'id: contentTailHost'), '')
s = replace(s, 'running: (root.controller.rowDragActive && root.dragPoint !== null)\n      || root.contentTailDragPoint !== null', 'running: root.controller.rowDragActive && root.dragPoint !== null')
s = replace(s, 'var point = root.controller.rowDragActive ? root.dragPoint : root.contentTailDragPoint', 'var point = root.dragPoint')
s = replace(s, '      else root.contentTailAutoScrolled()\n', '')
s = replace(s, '  function rowIntersectsViewport(', '''  function focusLastRow() {
    return root.focusRow(InteractionModel.nextKey(root.visibleRows, "", "end"))
  }
  function focusPaneBoundary(backwards) {
    if (backwards || !root.tabForwardTarget || !root.tabForwardTarget.visible) return false
    root.tabForwardTarget.forceActiveFocus(Qt.TabFocusReason)
    return true
  }

  function rowIntersectsViewport(''')
write(path, s)

path = 'components/DockSidebarKeyboard.qml'; s = read(path)
needle = '      controller.clearAlertControl()\n      if (isTab && direction === -1 && next'
s = replace(s, needle, '''      if (isTab && next === focusedKey) {
        if (typeof root.viewport.focusPaneBoundary === "function")
          event.accepted = root.viewport.focusPaneBoundary(direction < 0)
        return
      }

      controller.clearAlertControl()
      if (isTab && direction === -1 && next''')
write(path, s)

path = 'components/DockSidebar.qml'; s = read(path)
s = replace(s, 'import "DockModel.js" as DockModel', 'import "DockModel.js" as DockModel\nimport "DockSidebarWidgetModel.js" as WidgetModel')
s = replace(s, 'readonly property var widgetArea: sidebarViewport.contentTailItem', 'readonly property var widgetArea: sidebarWidgets\n  readonly property var widgetManageControl: widgetManage\n  readonly property var footerControl: pinnedStrip.visible ? pinnedStrip.firstFocusControl : launcher')
s = replace(s, block(s, 'id: viewportDragSurface'), '')
s = replace(s, block(s, 'id: sidebarViewport'), MIDDLE)
s = replace(s, '  function syncBadges() {', '''  function focusBeforeFooter() {
    return sidebarWidgets.sectionVisible ? sidebarWidgets.focusLastControl() : sidebarViewport.focusLastRow()
  }
  function syncBadges() {''')
s = replace(s, '        Keys.onPressed: function(event) {\n          if (event.key === Qt.Key_Return', '''        Keys.onPressed: function(event) {
          if (!pinnedStrip.visible && (event.key === Qt.Key_Backtab
              || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)))) {
            event.accepted = root.focusBeforeFooter()
            return
          }
          if (event.key === Qt.Key_Return''')
write(path, s)

path = 'components/DockSidebarWidgetArea.qml'; old = read(path)
header = block(old, 'id: sectionHeader')
header = replace(header, '        onClicked: root.openManager(manageButton)', '''        onClicked: root.openManager(manageButton)
        Keys.onBacktabPressed: function(event) { event.accepted = root.focusSectionBoundary(true) }
        Keys.onTabPressed: function(event) { event.accepted = root.focusSectionBoundary(false) }''')
column = block(old, 'id: cardColumn')
column = replace(column, '        model: root.presentationWidgetIds', '''        model: root.presentationWidgetIds
        onItemAdded: root.requestLayout()
        onItemRemoved: root.requestLayout()''')
column = re.sub(r'          presentationVisible:[\s\S]*?(?=          dropBefore:)', '''          presentationVisible: root.sectionVisible && root.panel.visible && root.itemIntersectsViewport(widgetCard)
          presentationClipItem: widgetScroll
          presentationRevision: root.layoutRevision
          bodyNavigationEnabled: widgetScroll.height > 0
''', column)
column = replace(column, 'onToggleRequested: root.controller.toggleWidgetCollapsed(modelData)', '''onToggleRequested: {
            root.prepareCollapse(widgetCard)
            root.controller.toggleWidgetCollapsed(modelData)
          }
          onCollapsedChanged: {
            if (collapsed && root.ownsWidgetFocus && root.focusedWidgetId === widgetId)
              widgetCard.focusCollapseControl()
          }
          onHeightChanged: root.requestLayout()
          onYChanged: root.requestLayout()''')
popup = block(old, 'id: popup')
popup = replace(popup, '      if (!visible) root.closePopup()\n      else Qt.callLater(root.updatePopupAnchor)', '      geometryTimer.restart()')
prefix = (HERE / 'area-prefix.qml.part').read_text()
prefix += '''  function lastTabStop(item) {
    if (!item || !item.visible || !item.enabled) return null
    var last = item.activeFocusOnTab ? item : null
    for (var i = 0; item.children && i < item.children.length; ++i) {
      var child = root.lastTabStop(item.children[i])
      if (child) last = child
    }
    return last
  }
  function focusLastControl() {
    if (!root.sectionVisible) return false
    var target = widgetScroll.height > 0 && cardRepeater.count
      ? root.lastTabStop(cardRepeater.itemAt(cardRepeater.count - 1)) : manageButton
    if (!target) target = manageButton
    target.forceActiveFocus(Qt.BacktabFocusReason)
    return true
  }
'''
write(path, prefix + '\n' + header + '\n' + SCROLL + column + '\n  }\n\n' + popup + SUFFIX)

path = 'components/DockWidgetCard.qml'; s = read(path)
s = replace(s, '  property bool collapsed: false', '''  property bool bodyNavigationEnabled: true
  function focusCollapseControl() { collapseButton.forceActiveFocus(Qt.TabFocusReason) }
  property bool collapsed: false''')
s = replace(s, '    objectName: "widget-card-body"', '    objectName: "widget-card-body"\n    visible: !root.collapsed && root.bodyNavigationEnabled')
write(path, s)

path = 'components/DockSidebarWidgetManager.qml'; s = read(path)
s = s.replace('// shared-scroll Widget tail', '// independent Widget pane').replace('the tail collapses', 'the section collapses')
s = replace(s, '  property Item managerAnchor: null\n', '''  property Item managerAnchor: null
  readonly property bool managerAnchorVisible: {
    var item = root.managerAnchor
    while (item) {
      if (!item.visible || item.opacity === 0) return false
      if (item === root.panel.contentItem) return true
      item = item.parent
    }
    return false
  }
  readonly property point managerAnchorPosition: {
    var item = root.managerAnchor, x = 0, y = 0
    while (item && item !== root.panel.contentItem) { x += item.x; y += item.y; item = item.parent }
    return Qt.point(x, y)
  }
  onManagerAnchorPositionChanged: anchorTimer.restart()
  onManagerAnchorVisibleChanged: anchorTimer.restart()
''')
s = replace(s, 'if (!anchor || !anchor.visible || !root.panel.visible || root.panel.panelCollapsed', 'if (!anchor || !root.managerAnchorVisible || !root.panel.visible || root.panel.panelCollapsed')
s = replace(s, 'Qt.callLater(root.updateAnchor)', 'anchorTimer.restart()')
s = replace(s, '  Component.onDestruction: root.close()', '''  Timer { id: anchorTimer; interval: 0; onTriggered: root.updateAnchor() }
  Connections {
    target: root.panel.widgetArea || null
    function onLayoutRevisionChanged() { anchorTimer.restart() }
    function onSectionVisibleChanged() { anchorTimer.restart() }
  }
  Component.onDestruction: root.close()''')
write(path, s)

path = 'components/DockSidebarPinnedStrip.qml'; s = read(path)
s = replace(s, '    anchors.leftMargin: root.panel && root.panel.viewport\n      ? root.panel.viewport.x - root.x + root.panel.viewport.workspaceCardInset + Style.space(4)\n      : Style.space(5) + Style.space(4)', '''    anchors.leftMargin: {
      if (!root.panel || !root.panel.viewport) return Style.space(5) + Style.space(4)
      var item = root.panel.viewport, x = 0
      while (item && item !== root.parent) { x += item.x; item = item.parent }
      return x - root.x + root.panel.viewport.workspaceCardInset + Style.space(4)
    }''')
s = replace(s, '      Repeater {\n        model: displayModel', '      Repeater {\n        id: pinRepeater\n        model: displayModel')
s = replace(s, '  property bool overflowOpen: false', '''  readonly property var firstFocusControl: root.visibleCount > 0
    ? pinRepeater.itemAt(0) : overflowButton.visible ? overflowButton : addPin
  Keys.onBacktabPressed: function(event) {
    if (root.firstFocusControl && root.firstFocusControl.activeFocus)
      event.accepted = root.panel.focusBeforeFooter()
  }
  property bool overflowOpen: false''')
write(path, s)

# Test-only source harness outputs are copied unchanged from durable staging.
for source in (HERE / 'tests').glob('*'):
    if source.is_file(): write('tests/' + source.name, source.read_text())
