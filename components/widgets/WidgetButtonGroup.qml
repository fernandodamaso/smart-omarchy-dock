import QtQuick
import qs.Commons

Item {
  id: root
  default property alias content: body.data
  property int gap: Style.space(5)
  implicitWidth: body.implicitWidth
  implicitHeight: body.implicitHeight
  width: parent ? parent.width : implicitWidth

  // Local wrap layout: Flow left-aligns every row; we center each wrapped row
  // (including a short final row) while keeping children as-is for focus/clicks.
  Item {
    id: body
    width: root.width
    implicitWidth: Math.ceil(contentWidth)
    implicitHeight: Math.ceil(contentHeight)
    height: implicitHeight

    property real contentWidth: 0
    property real contentHeight: 0
    property bool layoutScheduled: false
    property var watched: []

    function scheduleLayout() {
      if (layoutScheduled)
        return
      layoutScheduled = true
      Qt.callLater(runLayout)
    }

    function runLayout() {
      layoutScheduled = false
      layoutChildren()
    }

    function clearWatchers() {
      for (var i = 0; i < watched.length; ++i) {
        var entry = watched[i]
        if (!entry || !entry.child)
          continue
        try {
          entry.child.widthChanged.disconnect(entry.handler)
          entry.child.heightChanged.disconnect(entry.handler)
          entry.child.visibleChanged.disconnect(entry.handler)
          entry.child.implicitWidthChanged.disconnect(entry.handler)
          entry.child.implicitHeightChanged.disconnect(entry.handler)
        } catch (e) {
        }
      }
      watched = []
    }

    function hookChildren() {
      clearWatchers()
      for (var i = 0; i < children.length; ++i) {
        var child = children[i]
        if (!child)
          continue
        var handler = scheduleLayout
        child.widthChanged.connect(handler)
        child.heightChanged.connect(handler)
        child.visibleChanged.connect(handler)
        child.implicitWidthChanged.connect(handler)
        child.implicitHeightChanged.connect(handler)
        watched.push({ child: child, handler: handler })
      }
    }

    function layoutChildren() {
      var items = []
      for (var i = 0; i < children.length; ++i) {
        var child = children[i]
        if (!child || !child.visible)
          continue
        items.push(child)
      }

      if (items.length === 0) {
        contentWidth = 0
        contentHeight = 0
        return
      }

      var available = width
      var rows = []
      var row = []
      var rowWidth = 0
      var rowHeight = 0
      var maxRowWidth = 0

      function pushRow() {
        if (row.length === 0)
          return
        rows.push({ items: row, width: rowWidth, height: rowHeight })
        maxRowWidth = Math.max(maxRowWidth, rowWidth)
        row = []
        rowWidth = 0
        rowHeight = 0
      }

      for (var j = 0; j < items.length; ++j) {
        var item = items[j]
        var itemWidth = item.width
        var itemHeight = item.height
        var nextWidth = row.length === 0 ? itemWidth : rowWidth + root.gap + itemWidth
        if (row.length > 0 && available > 0 && nextWidth > available) {
          pushRow()
          nextWidth = itemWidth
        }
        row.push(item)
        rowWidth = nextWidth
        rowHeight = Math.max(rowHeight, itemHeight)
      }
      pushRow()

      var y = 0
      for (var r = 0; r < rows.length; ++r) {
        var placed = rows[r]
        var offset = available > 0 ? Math.max(0, (available - placed.width) / 2) : 0
        var x = offset
        for (var k = 0; k < placed.items.length; ++k) {
          var placedItem = placed.items[k]
          placedItem.x = x
          placedItem.y = y
          x += placedItem.width + root.gap
        }
        y += placed.height
        if (r + 1 < rows.length)
          y += root.gap
      }

      contentWidth = maxRowWidth
      contentHeight = y
    }

    onChildrenChanged: {
      hookChildren()
      scheduleLayout()
    }
    onWidthChanged: scheduleLayout()
    Component.onCompleted: {
      hookChildren()
      scheduleLayout()
    }
    Component.onDestruction: clearWatchers()
  }

  onGapChanged: body.scheduleLayout()
}
