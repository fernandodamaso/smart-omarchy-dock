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

    WidgetText {
      width: parent.width
      text: root.data.message || "Synthetic actions and framework states"
      role: "caption"
      muted: true
    }

    WidgetButtonGroup {
      width: parent.width
      WidgetButton { text: "Primary"; iconName: "check"; variant: "primary" }
      WidgetButton { text: "Secondary"; variant: "secondary" }
      WidgetButton { text: "Ghost"; variant: "ghost" }
      WidgetButton { text: "Danger"; variant: "danger" }
      WidgetIconButton { iconName: "settings-2"; variant: "secondary"; accessibleName: "Settings demo action" }
    }

    WidgetDivider { width: parent.width }

    WidgetState { width: parent.width; compact: true; kind: "loading"; message: "Synthetic loading state"; reducedMotion: false }
    WidgetState { width: parent.width; compact: true; kind: "empty"; message: "Synthetic empty state" }
    WidgetState { width: parent.width; compact: true; kind: "unavailable"; message: "Synthetic unavailable state" }
    WidgetState { width: parent.width; compact: true; kind: "error"; message: "Synthetic error state"; actionText: "Retry" }
    WidgetState { width: parent.width; compact: true; kind: "stale"; message: "Synthetic stale state" }
  }
}
