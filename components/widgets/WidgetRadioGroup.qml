pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Column {
  id: root
  property var model: []
  property var selectedValue: ""
  property bool requiredSingleSelect: true
  property string accessibleName: "Options"
  signal selectionChanged(var value)
  width: parent ? parent.width : implicitWidth
  spacing: Style.space(4)

  function valueOf(entry) {
    return entry && typeof entry === "object" && entry.value !== undefined ? entry.value : entry
  }

  function labelOf(entry) {
    return entry && typeof entry === "object" && entry.label !== undefined
      ? String(entry.label) : String(root.valueOf(entry))
  }

  function containsValue(value) {
    for (var i = 0; i < root.model.length; ++i)
      if (root.valueOf(root.model[i]) === value) return true
    return false
  }

  function normalizeSelection() {
    if (!root.requiredSingleSelect || !root.model || !root.model.length) return
    if (!root.containsValue(root.selectedValue)) root.selectedValue = root.valueOf(root.model[0])
  }

  function selectValue(value) {
    if (!root.containsValue(value)) return false
    if (root.selectedValue === value) return true
    root.selectedValue = value
    root.selectionChanged(value)
    return true
  }

  Component.onCompleted: normalizeSelection()
  onModelChanged: normalizeSelection()
  onSelectedValueChanged: if (root.requiredSingleSelect && root.model.length) normalizeSelection()

  Repeater {
    model: root.model
    delegate: WidgetButton {
      required property var modelData
      width: root.width
      text: root.labelOf(modelData)
      variant: root.selectedValue === root.valueOf(modelData) ? "primary" : "secondary"
      onClicked: root.selectValue(root.valueOf(modelData))
    }
  }

  Accessible.role: Accessible.Grouping
  Accessible.name: root.accessibleName
}