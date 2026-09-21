pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Column {
  id: root
  property var model: []
  property bool reducedMotion: false
  signal itemToggled(int index, bool checked)
  width: parent ? parent.width : implicitWidth
  spacing: 0

  Repeater {
    model: root.model
    delegate: Item {
      required property var modelData
      required property int index
      width: root.width
      height: Math.max(38, row.implicitHeight + Style.space(8))

      Row {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(7)

        WidgetCheckbox {
          id: check
          checked: modelData && modelData.done === true
          accessibleName: modelData && modelData.title ? String(modelData.title) : "Checklist item"
          onToggled: root.itemToggled(index, checked)
        }

        Column {
          width: Math.max(0, row.width - check.width - status.width - row.spacing * 2)
          WidgetText {
            width: parent.width
            text: modelData && modelData.title ? String(modelData.title) : ""
            allowWrap: false
          }
          WidgetText {
            visible: !!(modelData && modelData.detail)
            width: parent.width
            text: modelData && modelData.detail ? String(modelData.detail) : ""
            role: "caption"
            muted: true
            allowWrap: false
          }
        }

        WidgetBadge {
          id: status
          visible: !!(modelData && modelData.reference)
          text: modelData && modelData.reference ? String(modelData.reference) : ""
          semantic: modelData && (modelData.attention === "urgent" || modelData.attention === "overdue")
            ? "danger" : "neutral"
          compact: true
        }
      }
    }
  }
}