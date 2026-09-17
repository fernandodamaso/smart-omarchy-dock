pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import "DockSidebarModel.js" as SidebarModel
import "DockSidebarInteractionModel.js" as InteractionModel

FocusScope {
  id: root
  required property var controller
  readonly property var listView: list
  readonly property int rowCount: controller.projection.rows.length
  readonly property real rowHeight: Math.max(44, Math.ceil(metrics.height + Style.space(16)))
  activeFocusOnTab: true
  property var dragPoint: null
  signal contextRequested(var target, var anchorItem)
  signal dismissContextRequested()
  signal activationDispatched(var target, bool control, string connector, int modifiers, bool accepted)
  property bool restoring: false
  property bool pendingRestore: false
  property var previousKeys: []
  property real previousRowHeight: rowHeight
  FontMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }

  function captureAnchor() {
    if (root.restoring || root.pendingRestore || !list.count) return
    var index = list.indexAt(1, list.contentY + 1)
    if (index < 0) index = Math.min(list.count - 1, Math.max(0, Math.floor(list.contentY / root.rowHeight)))
    var row = root.controller.projection.rows[index]
    var item = list.itemAtIndex(index)
    if (row) root.controller.scrollAnchor = {key:row.key,
      offset:list.contentY - (item ? item.y : index * root.rowHeight)}
    root.previousKeys = root.controller.projection.rows.map(function(value) { return value.key })
  }

  function requestRestore() {
    var keys = root.controller.projection.rows.map(function(value) { return value.key })
    // Pure data/focus refresh is not a scroll command.
    if (JSON.stringify(keys) === JSON.stringify(root.previousKeys)
        && root.previousRowHeight === root.rowHeight) {
      root.pendingRestore = false
      return
    }
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
  }

  function restoreAnchor() {
    root.restoring = true
    list.forceLayout()
    var rows = root.controller.projection.rows
    var anchor = SidebarModel.recoverAnchor(root.controller.scrollAnchor, root.previousKeys, rows)
    var index = rows.findIndex(function(row) { return row.key === anchor.key })
    if (index >= 0) {
      list.positionViewAtIndex(index, ListView.Beginning)
      list.forceLayout()
      var item = list.itemAtIndex(index)
      var desired = (item ? item.y : index * root.rowHeight) + anchor.offset
      list.contentY = Math.min(Math.max(list.originY, desired),
        Math.max(list.originY, list.contentHeight - list.height + list.originY))
    } else list.contentY = list.originY
    root.previousKeys = rows.map(function(row) { return row.key })
    root.previousRowHeight = root.rowHeight
    root.pendingRestore = false
    root.restoring = false
  }

  function activate(target, control, connector, modifiers) {
    var accepted = root.controller.activateTarget(target, control, connector)
    root.activationDispatched(target, control === true, connector, modifiers, accepted)
    return accepted
  }

  function focusRow(key) {
    var rows = root.controller.projection.rows
    var index = rows.findIndex(function(row) { return row.key === key })
    if (index < 0 || !InteractionModel.focusable(rows[index])) return false
    root.controller.rememberNavigationFocus()
    root.controller.focusedRowKey = key
    list.positionViewAtIndex(index, ListView.Contain)
    list.forceLayout()
    var item = list.itemAtIndex(index)
    if (item) item.forceActiveFocus(Qt.TabFocusReason)
    return item !== null
  }

  function currentDelegate() {
    var index = root.controller.projection.rows.findIndex(function(row) {
      return row.key === root.controller.focusedRowKey
    })
    return index >= 0 ? list.itemAtIndex(index) : null
  }

  function cancelInputs(reason) {
    for (var i = 0; i < list.count; ++i) {
      var item = list.itemAtIndex(i)
      if (item && item.input) item.input.cancelGesture(reason)
    }
    root.controller.cancelRowDrag(reason)
    root.dragPoint = null
  }

  function rowHits() {
    var hits = []
    for (var i = 0; i < list.count; ++i) {
      var item = list.itemAtIndex(i)
      if (!item || !item.visible) continue
      var point = root.mapFromItem(item, 0, 0)
      hits.push({key:item.rowKey, kind:item.row.kind,
        workspaceIdentity:item.row.workspaceIdentity || "",
        monitorIdentity:item.row.monitorIdentity || "",
        x:point.x, y:point.y, width:item.width, height:item.height})
    }
    return hits
  }

  function dropKey() {
    if (!root.controller.dragSession) return ""
    return InteractionModel.hitTarget(root.dragPoint, root.rowHits(),
      {x:0,y:0,width:root.width,height:root.height}, root.controller.dragSession.target.kind)
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
      : InteractionModel.nextKey(root.controller.projection.rows, "", "home"))
  }

  // Defer until a pointer-selected child has updated the key. Mapping/hovering
  // never triggers this; re-entry via Tab restores a real visible focus target.
  onActiveFocusChanged: if (activeFocus) Qt.callLater(root.enterNavigation)

  Timer {
    interval: 16
    repeat: true
    running: root.controller.rowDragActive && root.dragPoint !== null
    onTriggered: {
      var delta = root.dragPoint.x >= 0 && root.dragPoint.x < root.width
        ? InteractionModel.autoScrollStep(root.dragPoint.y, root.height) : 0
      if (!delta) return
      list.contentY = Math.max(list.originY, Math.min(
        Math.max(list.originY, list.contentHeight - list.height + list.originY), list.contentY + delta))
      list.forceLayout()
      root.controller.updateRowDrag(root.dropKey())
    }
  }

  ListView {
    id: list
    objectName: "sidebar-window-list"
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    orientation: ListView.Vertical
    keyNavigationEnabled: false
    // ScriptModel reconciles supplied domain keys; index is geometry only.
    model: ScriptModel { objectProp: "key"; values: root.controller.projection.rows }
    delegate: DockSidebarRow {
      required property var modelData
      readonly property string stableKey: modelData.key
      row: root.controller.rowsByKey[stableKey] || modelData
      controller: root.controller
      viewport: root
      collapsed: root.controller.collapsed
      rowHeight: root.rowHeight
      width: list.width
    }
    onMovementEnded: root.captureAnchor()
    onContentYChanged: if (!root.pendingRestore) root.captureAnchor()
  }
  Connections {
    target: root.controller
    function onAboutToRefresh() { root.captureAnchor(); root.pendingRestore = true }
    function onRefreshed() { root.requestRestore() }
    function onSurfaceInvalidated() { root.cancelInputs("surface-invalidated") }
    function onRowDragActiveChanged() { if (!root.controller.rowDragActive) root.dragPoint = null }
  }
  onRowHeightChanged: {
    if (!root.previousKeys.length) return
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
  }
  onHeightChanged: root.requestRestore()
  Component.onCompleted: { root.pendingRestore = true; Qt.callLater(root.restoreAnchor) }
  // A passive proxy uses the same native artwork as the actual window row.
  Item {
    visible: root.controller.rowDragActive && root.dragPoint !== null
    enabled: false
    z: 100
    x: root.dragPoint ? Math.max(0, Math.min(root.width - width, root.dragPoint.x + 12)) : 0
    y: root.dragPoint ? Math.max(0, Math.min(root.height - height, root.dragPoint.y + 12)) : 0
    width: Math.min(160, root.width)
    height: root.rowHeight
    property var sourceRow: root.controller.dragSession
      ? root.controller.rowsByKey[root.controller.dragSession.target.key] : null
    DockAppIcon {
      visible: parent.sourceRow && parent.sourceRow.kind === "window"
      width: 32; height: 32
      anchors.verticalCenter: parent.verticalCenter
      desktopId: parent.sourceRow ? String(parent.sourceRow.desktopId || "") : ""
      desktopIcon: parent.sourceRow && parent.sourceRow.item && parent.sourceRow.item.entry
        ? String(parent.sourceRow.item.entry.icon || "") : ""
      iconOverrides: root.controller.settings.iconOverrides || ({})
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
  Component.onDestruction: { root.cancelInputs("viewport-destroyed"); root.captureAnchor() }
}
