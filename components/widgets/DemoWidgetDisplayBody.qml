import QtQuick
import qs.Commons

Item {
  id: root
  property var widgetContext: ({})
  readonly property var data: widgetContext && widgetContext.data ? widgetContext.data : ({})
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(7)

    WidgetText { width: parent.width; text: "Synthetic display primitives"; role: "caption"; muted: true }

    WidgetStatus { label: root.data.status || "Healthy"; semantic: "success"; reference: "DEMO" }

    WidgetStatGrid {
      width: parent.width
      columnCount: 2
      model: root.data.stats || []
    }

    WidgetKeyValue {
      width: parent.width
      label: "Provider"
      value: root.data.provider || "Synthetic"
      emphasized: true
    }

    WidgetMeter {
      width: parent.width
      label: "CPU"
      valueText: Math.round(Number(root.data.cpu || 0) * 100) + "%"
      value: Number(root.data.cpu || 0)
      semantic: "info"
    }

    WidgetMeter {
      width: parent.width
      label: "Memory"
      valueText: Math.round(Number(root.data.memory || 0) * 100) + "%"
      value: Number(root.data.memory || 0)
      semantic: "warning"
    }

    WidgetText { width: parent.width; text: "Synthetic trend"; role: "caption"; muted: true }
    WidgetSparkline { width: parent.width; values: root.data.trend || [] }
  }
}
