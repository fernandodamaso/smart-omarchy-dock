import QtQuick
import qs.Commons

Item {
  id: root
  property var widgetContext: ({})
  readonly property var snapshotData: widgetContext && widgetContext.data ? widgetContext.data : ({})
  readonly property real memoryValue: Number(root.snapshotData.memory || 0)
  readonly property string memorySemantic: root.memoryValue >= 0.85 ? "warning" : "neutral"
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(7)

    WidgetText { width: parent.width; text: "Synthetic display primitives"; role: "caption"; muted: true }

    WidgetStatus { label: root.snapshotData.status || "Healthy"; semantic: "info"; reference: "DEMO"; referenceSemantic: "neutral" }

    WidgetStatGrid {
      width: parent.width
      columnCount: 2
      model: root.snapshotData.stats || []
    }

    WidgetKeyValue {
      width: parent.width
      label: "Provider"
      value: root.snapshotData.provider || "Synthetic"
      emphasized: true
    }

    WidgetMeter {
      width: parent.width
      label: "CPU"
      valueText: Math.round(Number(root.snapshotData.cpu || 0) * 100) + "%"
      value: Number(root.snapshotData.cpu || 0)
      semantic: "info"
    }

    WidgetMeter {
      width: parent.width
      label: "Memory"
      valueText: Math.round(root.memoryValue * 100) + "%"
      value: root.memoryValue
      semantic: root.memorySemantic
    }

    WidgetText { width: parent.width; text: "Synthetic trend"; role: "caption"; muted: true }
    WidgetSparkline { width: parent.width; values: root.snapshotData.trend || [] }
  }
}
