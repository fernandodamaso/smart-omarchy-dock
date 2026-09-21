import QtQuick
import qs.Commons

Item {
  id: root
  property var widgetContext: ({})
  readonly property var snapshotData: widgetContext && widgetContext.data ? widgetContext.data : ({})
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(7)

    WidgetText { width: parent.width; text: "Synthetic lists, checklist and activity"; role: "caption"; muted: true }

    WidgetList {
      width: parent.width
      Repeater {
        model: root.snapshotData.rows || []
        delegate: WidgetListItem {
          required property var modelData
          width: parent ? parent.width : 0
          title: String(modelData.title || "")
          subtitle: String(modelData.subtitle || "")
          trailing: String(modelData.trailing || "")
          reference: String(modelData.reference || "")
          attention: String(modelData.attention || "none")
        }
      }
    }

    WidgetDivider { width: parent.width }

    WidgetChecklist {
      width: parent.width
      model: root.snapshotData.checklist || []
      reducedMotion: false
    }

    WidgetDivider { width: parent.width }

    WidgetActivity {
      width: parent.width
      model: root.snapshotData.activity || []
    }
  }
}
