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

    WidgetText {
      width: parent.width
      text: "Synthetic interactive form controls — edits are not persisted"
      role: "caption"
      muted: true
      maxLines: 2
    }

    WidgetFormField {
      width: parent.width
      label: "Search"
      helperText: "Search input"
      WidgetSearchInput { width: parent.width; text: String(root.snapshotData.search || ""); placeholderText: "Filter widgets" }
    }

    WidgetFormField {
      width: parent.width
      label: "Text"
      WidgetTextInput { width: parent.width; text: String(root.snapshotData.name || ""); placeholderText: "Widget name" }
    }

    WidgetFormField {
      width: parent.width
      label: "Number"
      WidgetNumberInput { width: parent.width; numericValue: Number(root.snapshotData.limit || 5); minimum: 1; maximum: 20 }
    }

    WidgetFormField {
      width: parent.width
      label: "Select"
      WidgetSelect { width: parent.width; model: root.snapshotData.refresh || ["Manual"]; accessibleName: "Refresh interval" }
    }

    WidgetFormField {
      width: parent.width
      label: "Text area"
      WidgetTextArea { width: parent.width; text: String(root.snapshotData.notes || ""); placeholderText: "Optional notes" }
    }

    WidgetCheckbox { text: "Show completed"; checked: true }
    WidgetToggle { text: "Notifications"; checked: true }

    WidgetRadioGroup {
      width: parent.width
      accessibleName: "Density"
      model: [{label:"Compact", value:"compact"}, {label:"Comfortable", value:"comfortable"}]
      selectedValue: "compact"
    }

    WidgetSegmentedControl {
      width: parent.width
      height: 32
      accessibleName: "Period"
      model: [{label:"Today", value:"today"}, {label:"Week", value:"week"}]
      selectedValue: "today"
    }
  }
}
