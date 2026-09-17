pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import "DockSidebarModel.js" as SidebarModel

Item {
  id: root
  required property var controller
  readonly property var listView: list
  readonly property int rowCount: controller.projection.rows.length
  readonly property real rowHeight: Math.max(44, Math.ceil(metrics.height + Style.space(16)))
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

  ListView {
    id: list
    objectName: "sidebar-window-list"
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    orientation: ListView.Vertical
    // ScriptModel reconciles supplied domain keys; index is geometry only.
    model: ScriptModel { objectProp: "key"; values: root.controller.projection.rows }
    delegate: DockSidebarRow {
      required property var modelData
      readonly property string stableKey: modelData.key
      row: root.controller.rowsByKey[stableKey] || modelData
      controller: root.controller
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
  }
  onRowHeightChanged: {
    if (!root.previousKeys.length) return
    root.pendingRestore = true
    Qt.callLater(root.restoreAnchor)
  }
  onHeightChanged: root.requestRestore()
  Component.onCompleted: { root.pendingRestore = true; Qt.callLater(root.restoreAnchor) }
  Component.onDestruction: root.captureAnchor()
}
