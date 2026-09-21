pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Grid {
  id: root
  property var model: []
  property int columnCount: 2
  property int gap: Style.space(6)
  columns: Math.max(1, root.columnCount)
  columnSpacing: root.gap
  rowSpacing: root.gap
  width: parent ? parent.width : implicitWidth

  Repeater {
    model: root.model
    delegate: WidgetStat {
      required property var modelData
      width: Math.max(0, (root.width - root.gap * (root.columns - 1)) / root.columns)
      label: modelData && modelData.label ? String(modelData.label) : ""
      value: modelData && modelData.value !== undefined ? String(modelData.value) : ""
      helper: modelData && modelData.helper ? String(modelData.helper) : ""
    }
  }
}