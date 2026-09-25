import QtQuick

// Paint-only dashed slot. Colors and geometry are supplied from Omarchy tokens
// by the owning row. No hit testing, pointer handlers, or action state here.
Item {
  id: root
  property color lineColor: "transparent"
  property color fillColor: "transparent"
  property real badgeX: 7
  property real badgeSize: 22
  property bool showBadge: true
  Rectangle { anchors.fill: parent; color: root.fillColor }
  Canvas {
    id: outline
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.strokeStyle = root.lineColor
      ctx.lineWidth = 1
      function edge(x1, y1, x2, y2) {
        var length = Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1))
        if (length <= 0) return
        for (var p = 0; p < length; p += 7) {
          var end = Math.min(length, p + 4)
          ctx.moveTo(x1 + (x2 - x1) * p / length, y1 + (y2 - y1) * p / length)
          ctx.lineTo(x1 + (x2 - x1) * end / length, y1 + (y2 - y1) * end / length)
        }
      }
      function box(x, y, w, h) {
        edge(x, y, x + w, y); edge(x + w, y, x + w, y + h)
        edge(x + w, y + h, x, y + h); edge(x, y + h, x, y)
      }
      ctx.beginPath()
      box(0.5, 0.5, Math.max(0,width - 1), Math.max(0,height - 1))
      if (root.showBadge) box(root.badgeX + 0.5, (height - root.badgeSize) / 2 + 0.5,
        Math.max(0,root.badgeSize - 1), Math.max(0,root.badgeSize - 1))
      ctx.stroke()
    }
  }
  onLineColorChanged: outline.requestPaint()
  onWidthChanged: outline.requestPaint()
  onHeightChanged: outline.requestPaint()
  onBadgeXChanged: outline.requestPaint()
  onBadgeSizeChanged: outline.requestPaint()
  onShowBadgeChanged: outline.requestPaint()
}
