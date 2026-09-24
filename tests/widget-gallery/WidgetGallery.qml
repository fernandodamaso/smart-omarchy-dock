pragma ComponentBehavior: Bound
import QtQuick
import "../../components"
import "../../components/widgets"
import qs.Commons

Flickable {
  id: root
  width: 420
  height: 760
  contentWidth: width
  contentHeight: galleryColumn.implicitHeight + Style.space(24)
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  property bool reducedMotion: false
  readonly property string rasterFixture:
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

  QtObject {
    id: galleryController
    function widgetView(id) {
      return {
        active: true,
        status: "ready",
        revision: 1,
        data: { count: id === "gallery.expanded" ? 3 : 0 },
        provider: null,
        descriptor: {
          id: id,
          label: id === "gallery.expanded" ? "Gallery widget" : "Collapsed widget",
          iconName: "layout-grid",
          expandedView: galleryBody
        }
      }
    }
    function openWidgetPopup(id, anchor) { return true }
    function closeWidgetPopup() {}
    function widgetViewFailed(id, expected) {}
  }

  Component {
    id: galleryBody
    Item {
      property var widgetContext: ({})
      implicitHeight: bodyColumn.implicitHeight + Style.space(8)

      Column {
        id: bodyColumn
        width: parent.width
        spacing: Style.space(6)

        WidgetListItem {
          width: parent.width
          iconName: "check"
          title: "Reusable body composition"
          subtitle: "The card shell stays framework-owned."
          trailing: "Ready"
        }
        WidgetProgressBar { width: parent.width; value: 0.62; semantic: "success" }
      }
    }
  }

  Column {
    id: galleryColumn
    x: Style.space(12)
    y: Style.space(12)
    width: Math.max(0, root.width - Style.space(24))
    spacing: Style.space(14)

    WidgetSection {
      width: parent.width
      title: "Card anatomy"
      subtitle: "Real FDM-973 shell, expanded and collapsed."

      DockWidgetCard {
        width: parent.width
        controller: galleryController
        widgetId: "gallery.expanded"
        collapsed: false
      }

      DockWidgetCard {
        width: parent.width
        controller: galleryController
        widgetId: "gallery.collapsed"
        collapsed: true
      }
    }

    WidgetDivider { width: parent.width }

    WidgetSection {
      width: parent.width
      title: "Icons"
      subtitle: "Lucide, SVG, raster, tint, brand preservation and fallback."

      Row {
        spacing: Style.space(8)
        WidgetIcon { iconName: "move"; containerVariant: "plain"; accessibleName: "Lucide" }
        WidgetIcon { iconName: "layout-grid"; containerVariant: "soft"; accessibleName: "Soft Lucide" }
        WidgetIcon {
          source: Qt.resolvedUrl("reference/fixture.svg")
          containerVariant: "outlined"
          themeTinted: true
          accessibleName: "SVG"
        }
        WidgetIcon {
          source: root.rasterFixture
          preserveBrand: true
          containerVariant: "tile"
          accessibleName: "Raster"
        }
        WidgetIcon {
          source: Qt.resolvedUrl("reference/missing-artwork.png")
          containerVariant: "soft"
          accessibleName: "Fallback"
        }
      }
    }

    WidgetSection {
      width: parent.width
      title: "Lists and status"

      WidgetList {
        width: parent.width
        WidgetListItem {
          width: parent.width
          iconName: "move"
          title: "Build the Widget UI kit"
          subtitle: "Reusable list anatomy at bounded width"
          reference: "#975"
          trailing: "Today"
          interactive: true
        }
        WidgetListItem {
          width: parent.width
          title: "Urgent review"
          subtitle: "Semantic attention, not provider colors"
          attention: "urgent"
          reference: "#86"
          trailing: "Urgent"
          reducedMotion: root.reducedMotion
        }
        WidgetStatus { label: "Healthy"; semantic: "success" }
        WidgetStatus { label: "Needs attention"; semantic: "danger"; reference: "#86" }
      }
    }

    WidgetSection {
      width: parent.width
      title: "Checklist"

      WidgetChecklist {
        width: parent.width
        reducedMotion: root.reducedMotion
        model: [
          {title: "Use synthetic fixture data", detail: "No external API", done: true},
          {title: "Qualify narrow layout", detail: "No horizontal overflow", reference: "#974", attention: "overdue"}
        ]
      }
    }

    WidgetSection {
      width: parent.width
      title: "Stats, key/value and meters"

      WidgetStatGrid {
        width: parent.width
        columnCount: 2
        model: [
          {label: "Agents", value: "4", helper: "3 active"},
          {label: "Coverage", value: "92%", helper: "Headless"}
        ]
      }
      WidgetKeyValue { width: parent.width; label: "Provider"; value: "Synthetic"; emphasized: true }
      WidgetMeter { width: parent.width; label: "CPU"; valueText: "42%"; value: 0.42; semantic: "info" }
      WidgetMeter { width: parent.width; label: "Memory"; valueText: "71%"; value: 0.71; semantic: "neutral" }
    }

    WidgetSection {
      width: parent.width
      title: "Activity"

      WidgetActivity {
        width: parent.width
        model: [
          {title: "Agent started", detail: "2 minutes ago", semantic: "info"},
          {title: "Checks passed", detail: "Headless CI", semantic: "success"},
          {title: "Follow-up required", detail: "Local qualification", semantic: "danger"}
        ]
      }
    }

    WidgetSection {
      width: parent.width
      title: "Progress and media"

      WidgetIconText {
        iconName: "layout-grid"
        text: "Synthetic media summary"
      }
      WidgetProgressBar { width: parent.width; value: 0.74; semantic: "success" }
      WidgetSparkline { width: parent.width; values: [4, 7, 5, 9, 8, 12, 11] }
    }

    WidgetSection {
      width: parent.width
      title: "Forms"

      WidgetFormField {
        width: parent.width
        label: "Search"
        helperText: "Leading icon stays subordinate."
        WidgetSearchInput { width: parent.width; placeholderText: "Filter widgets" }
      }
      WidgetFormField {
        width: parent.width
        label: "Name"
        WidgetTextInput { width: parent.width; text: "Widget example" }
      }
      WidgetFormField {
        width: parent.width
        label: "Notes"
        WidgetTextArea { width: parent.width; placeholderText: "Optional notes" }
      }
      WidgetFormField {
        width: parent.width
        label: "Limit"
        WidgetNumberInput { width: parent.width; numericValue: 5; minimum: 1; maximum: 20 }
      }
      WidgetFormField {
        width: parent.width
        label: "Refresh"
        WidgetSelect { width: parent.width; model: ["Manual", "5 minutes", "15 minutes"] }
      }
      WidgetCheckbox { text: "Show completed"; checked: true }
      WidgetToggle { text: "Notifications"; checked: true }
      WidgetRadioGroup {
        width: parent.width
        model: [{label: "Compact", value: "compact"}, {label: "Comfortable", value: "comfortable"}]
        selectedValue: "compact"
      }
      WidgetSegmentedControl {
        width: parent.width
        height: 32
        model: [{label: "Today", value: "today"}, {label: "Week", value: "week"}]
        selectedValue: "today"
      }
    }

    WidgetSection {
      width: parent.width
      title: "Actions"

      WidgetButtonGroup {
        width: parent.width
        WidgetButton { text: "Run"; iconName: "check"; variant: "primary" }
        WidgetButton { text: "Manage"; variant: "secondary" }
        WidgetButton { text: "Later"; variant: "ghost" }
      }
      Row {
        spacing: Style.space(6)
        WidgetButton { text: "Remove"; variant: "danger" }
        WidgetIconButton { iconName: "move"; variant: "secondary"; accessibleName: "Reorder" }
        WidgetButton { text: "Disabled"; variant: "primary"; enabled: false }
      }
    }

    WidgetSection {
      width: parent.width
      title: "Framework states"

      WidgetState {
        width: parent.width
        kind: "loading"
        message: "Loading synthetic data"
        reducedMotion: root.reducedMotion
      }
      WidgetState { width: parent.width; kind: "empty"; message: "No matching items" }
      WidgetState { width: parent.width; kind: "unavailable"; message: "Provider is not available" }
      WidgetState { width: parent.width; kind: "error"; message: "Fixture failed"; actionText: "Retry" }
      WidgetState { width: parent.width; kind: "stale"; message: "Last updated 18 minutes ago" }
    }

    WidgetSection {
      width: parent.width
      title: "Narrow width"
      subtitle: "Canonical body patterns remain usable without horizontal scrolling."

      Rectangle {
        width: Math.min(parent.width, 168)
        height: narrowColumn.implicitHeight + Style.space(12)
        radius: Math.min(7, Style.cornerRadius)
        color: Util.alpha(Color.foreground, 0.025)
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.10)

        Column {
          id: narrowColumn
          x: Style.space(6)
          y: Style.space(6)
          width: Math.max(0, parent.width - Style.space(12))
          spacing: Style.space(5)

          WidgetListItem {
            width: parent.width
            title: "A deliberately long item title"
            subtitle: "Elides safely"
            trailing: "Now"
          }
          WidgetSearchInput { width: parent.width; placeholderText: "Search" }
          WidgetButton { width: parent.width; text: "Primary action"; variant: "primary" }
        }
      }
    }
  }
}
