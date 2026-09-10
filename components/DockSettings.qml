pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Dialogs
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel
import "DockIconModel.js" as DockIconModel
import "DockWindowModel.js" as DockWindowModel
import "DockTrashModel.js" as TrashModel

PanelWindow {
  id: root

  required property Item anchorItem
  required property string position
  required property var settings
  property var iconOverrides: ({})
  property int iconReloadRevision: 0
  property string settingsWriteState: "idle"
  property string settingsWriteError: ""
  property string iconEditorDesktopId: ""
  property bool outsideClickDismissal: true
  // Prime layer-shell focus briefly on open so keyboard navigation works, then
  // settle on OnDemand so Hyprland does not route every pointer event to this
  // full-screen settings surface.
  property bool focusPrimed: false
  signal settingPreviewed(string key, var value)
  signal settingCommitted(string key, var value)
  signal settingsPatchCommitted(var patch)
  signal iconOverrideRequested(string desktopId, string sourceUrl)
  signal settingsWriteRetryRequested()
  signal resetRequested()

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property int panelMargin: 12
  readonly property real panelScreenWidth: width > 0
    ? width : popupScreen ? popupScreen.width : 460
  readonly property real panelScreenHeight: height > 0
    ? height : popupScreen ? popupScreen.height : 760
  readonly property int panelWidth: Math.min(980,
    Math.max(320, panelScreenWidth - panelMargin * 2))
  readonly property int panelHeight: Math.min(820,
    Math.max(360, panelScreenHeight - panelMargin * 2))
  readonly property bool wideLayout: panelWidth >= 720
  readonly property bool compactControls: panelWidth < 560
  property bool advancedExpanded: false
  readonly property bool groupedEffective: current("workspaceLayout") === "grouped"
    && position !== "left" && position !== "right"
  // Theme token map is owned live by Dock; this binding keeps symbolic
  // references synchronized when the active theme changes.
  required property var themeColorTokens
  readonly property var themeColorOptions: [
    { value: "@background", label: "Omarchy · Background", color: Color.background },
    { value: "@foreground", label: "Omarchy · Foreground", color: Color.foreground },
    { value: "@accent", label: "Omarchy · Accent", color: Color.accent },
    { value: "@muted", label: "Omarchy · Muted", color: Color.muted },
    { value: "@urgent", label: "Omarchy · Urgent", color: Color.urgent },
    { value: "@bar.background", label: "Omarchy · Bar background", color: Color.bar.background },
    { value: "@bar.text", label: "Omarchy · Bar text", color: Color.bar.text },
    { value: "@bar.active", label: "Omarchy · Bar active", color: Color.bar.active },
    { value: "@popups.background", label: "Omarchy · Popup background", color: Color.popups.background },
    { value: "@popups.text", label: "Omarchy · Popup text", color: Color.popups.text },
    { value: "@popups.border", label: "Omarchy · Popup border", color: Color.popups.border },
    { value: "@tooltip.background", label: "Omarchy · Tooltip background", color: Color.tooltip.background },
    { value: "@tooltip.text", label: "Omarchy · Tooltip text", color: Color.tooltip.text },
    { value: "@tooltip.border", label: "Omarchy · Tooltip border", color: Color.tooltip.border },
    { value: "@menu.background", label: "Omarchy · Menu background", color: Color.menu.background },
    { value: "@menu.text", label: "Omarchy · Menu text", color: Color.menu.text },
    { value: "@menu.border", label: "Omarchy · Menu border", color: Color.menu.border },
    { value: "@menu.selected-background", label: "Omarchy · Menu selected background", color: Color.menu.selectedBackground },
    { value: "@menu.selected-text", label: "Omarchy · Menu selected text", color: Color.menu.selectedText },
    { value: "@menu.selected-border", label: "Omarchy · Menu selected border", color: Color.menu.selectedBorder },
    { value: "@notifications.background", label: "Omarchy · Notification background", color: Color.notifications.background },
    { value: "@notifications.text", label: "Omarchy · Notification text", color: Color.notifications.text },
    { value: "@notifications.border", label: "Omarchy · Notification border", color: Color.notifications.border },
    { value: "@notifications.countdown", label: "Omarchy · Notification countdown", color: Color.notifications.countdown }
  ]
  readonly property var applicationEntries: DesktopEntries.applications.values || []
  readonly property var hiddenApplicationRows: DockModel.hiddenApplicationRows(
    current("hiddenApplications"), applicationEntries)
  readonly property var iconOverrideRows: buildIconOverrideRows()
  readonly property string iconEditorApplicationName:
    applicationNameForId(iconEditorDesktopId)
  readonly property point panelOrigin: DockModel.centeredPopupAnchor(
    position,
    panelScreenWidth,
    panelScreenHeight,
    panelScreenWidth,
    panelScreenHeight,
    panelWidth,
    panelHeight,
    panelMargin)
  // This panel is full-screen so it can dismiss on outside clicks. Exclude
  // the dock's edge strip from its input region, however, so the dock keeps
  // receiving pointer motion and can preview magnification/glow changes while
  // Settings is open.
  readonly property real dockHitThickness: anchorWindow
    ? (position === "top" || position === "bottom"
      ? anchorWindow.height : anchorWindow.width)
    : 120
  readonly property real dockEdgePassthrough: Math.max(1, dockHitThickness)

  function current(key) {
    if (key === "showTrash")
      return TrashModel.normalizeShowTrash(settings ? settings[key] : undefined)
    return DockModel.normalizeSetting(key, settings ? settings[key] : undefined)
  }

  function applicationEntryForId(desktopId) {
    var key = DockIconModel.normalizeKey(desktopId)
    if (!key) return null
    var entries = root.applicationEntries || []
    for (var i = 0; i < entries.length; ++i) {
      var entry = entries[i]
      if (entry && DockIconModel.normalizeKey(String(entry.id || "")) === key)
        return entry
    }
    return null
  }

  function applicationNameForId(desktopId) {
    var key = DockIconModel.normalizeKey(desktopId)
    if (!key) return ""
    var entry = applicationEntryForId(key)
    var name = entry ? String(entry.name || "").trim() : ""
    return name || key
  }

  function currentIconSource(desktopId) {
    var key = DockIconModel.normalizeKey(desktopId)
    if (!key) return ""
    var overrides = root.iconOverrides || ({})
    return DockIconModel.normalizeSource(overrides[key])
  }

  function buildIconOverrideRows() {
    var overrides = root.iconOverrides || ({})
    return Object.keys(overrides).sort().map(function(rawKey) {
      var key = DockIconModel.normalizeKey(rawKey)
      var source = key ? DockIconModel.normalizeSource(overrides[rawKey]) : ""
      if (!key || !source) return null
      var entry = root.applicationEntryForId(key)
      var name = entry ? String(entry.name || "").trim() : ""
      var icon = entry ? String(entry.icon || "").trim() : ""
      return {
        id: key,
        name: name || key,
        icon: icon || "application-x-executable",
        source: source
      }
    }).filter(function(row) { return row !== null })
  }

  function focusIconEditorSection() {
    if (!root.visible || root.iconEditorDesktopId === "") return
    var maximum = Math.max(0,
      settingsContent.contentHeight - settingsContent.height)
    settingsContent.contentY = Math.max(0, Math.min(
      applicationIconsSection.y - Style.spacing.md, maximum))
    applicationIconsSection.forceActiveFocus()
  }

  function openIconEditor(desktopId) {
    var key = DockIconModel.normalizeKey(desktopId)
    if (!key) return false
    if (iconFileDialog.visible) iconFileDialog.close()
    iconOverrideEditor.cancelDraft()
    iconEditorDesktopId = key
    open()
    return true
  }

  function chooseIconFile() {
    var key = DockIconModel.normalizeKey(iconEditorDesktopId)
    if (!key) return
    iconFileDialog.capturedDesktopId = key
    iconFileDialog.capturedCurrentSource = currentIconSource(key)
    iconFileDialog.open()
  }

  function colorForSetting(key) {
    var fallback = key === "workspaceBadgeBackgroundColor"
      ? Color.accent
      : key === "workspaceBadgeTextColor" ? Qt.color("#ffffff")
      : key === "backgroundColor" ? Color.menu.background : Color.menu.border
    return DockModel.resolveColorValue(
      current(key),
      themeColorTokens,
      fallback)
  }

  function preview(key, value) {
    settingPreviewed(key, DockModel.normalizeSetting(key, value))
  }

  function commit(key, value) {
    settingCommitted(key, DockModel.normalizeSetting(key, value))
  }

  function commitPatch(patch) {
    if (!patch || Object.keys(patch).length === 0) return
    settingsPatchCommitted(patch)
  }

  function commitControlCommand() {
    var command = DockModel.normalizeSetting("controlCommand", commandInput.text)
    commandInput.text = command
    if (command !== current("controlCommand")) settingCommitted("controlCommand", command)
  }

  function syncAppearanceInputs() {
    if (!backgroundColorInput.activeFocus)
      backgroundColorInput.text = current("backgroundColor")
    if (!borderColorInput.activeFocus)
      borderColorInput.text = current("borderColor")
    if (!workspaceBadgeBackgroundColorInput.activeFocus)
      workspaceBadgeBackgroundColorInput.text = current(
        "workspaceBadgeBackgroundColor")
    if (!workspaceBadgeTextColorInput.activeFocus)
      workspaceBadgeTextColorInput.text = current("workspaceBadgeTextColor")
  }

  function commitColor(key, field) {
    var raw = String(field.text || "").trim()
    var normalized = DockModel.normalizeSetting(key, raw)
    if (raw !== "" && normalized === "") {
      field.text = current(key)
      return
    }

    field.text = normalized
    if (normalized !== current(key)) settingCommitted(key, normalized)
  }

  function openColorPicker(key) {
    colorDialog.settingKey = key
    colorDialog.selectedColor = colorForSetting(key)
    colorDialog.title = key === "backgroundColor"
      ? "Dock background color"
      : key === "borderColor" ? "Dock border color"
      : key === "workspaceBadgeBackgroundColor"
        ? "Workspace badge background color"
        : "Workspace badge text color"
    colorDialog.open()
  }

  function commitColorValue(key, color) {
    var normalized = DockModel.normalizeSetting(key,
      DockModel.colorToHex(color))
    if (normalized === "") return

    if (key === "backgroundColor")
      backgroundColorInput.text = normalized
    else if (key === "borderColor")
      borderColorInput.text = normalized
    else if (key === "workspaceBadgeBackgroundColor")
      workspaceBadgeBackgroundColorInput.text = normalized
    else if (key === "workspaceBadgeTextColor")
      workspaceBadgeTextColorInput.text = normalized
    if (normalized !== current(key)) settingCommitted(key, normalized)
  }

  function surfaceMode(enabledKey, valueKey) {
    return DockModel.surfaceColorMode(current(enabledKey), current(valueKey))
  }

  function defaultTokenOptions(label, color) {
    return [{ value: "", label: label, color: color }].concat(themeColorOptions)
  }

  function selectSurfaceColor(enabledKey, valueKey, value) {
    commitPatch(DockModel.surfaceColorPatch(enabledKey, valueKey, value))
  }

  function enableCustomSurfaceColor(enabledKey, valueKey) {
    var currentValue = current(valueKey)
    if (String(currentValue).indexOf("#") === 0) {
      selectSurfaceColor(enabledKey, valueKey, currentValue)
      return
    }

    var resolved = colorForSetting(valueKey)
    selectSurfaceColor(enabledKey, valueKey, DockModel.colorToHex(resolved))
  }

  function open() {
    commandInput.text = current("controlCommand")
    syncAppearanceInputs()
    visible = true
    Qt.callLater(function() {
      if (root.iconEditorDesktopId !== "") root.focusIconEditorSection()
      else positionGroup.forceActiveFocus()
    })
  }

  function beginFocusPrime() {
    if (visible && backingWindowVisible) focusPrimeTimer.restart()
  }

  function close() {
    if (commandInput.activeFocus) commitControlCommand()
    if (iconFileDialog.visible) iconFileDialog.close()
    if (colorDialog.visible) colorDialog.close()
    iconOverrideEditor.cancelDraft()
    iconEditorDesktopId = ""
    visible = false
  }

  visible: false
  color: "transparent"
  screen: popupScreen
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "smartdock-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()
  onPopupScreenChanged: if (visible && !popupScreen) root.close()

  onVisibleChanged: {
    if (visible) {
      focusPrimed = false
      beginFocusPrime()
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
      if (iconFileDialog.visible) iconFileDialog.close()
      if (colorDialog.visible) colorDialog.close()
      iconOverrideEditor.cancelDraft()
      iconEditorDesktopId = ""
    }
  }

  Timer {
    id: focusPrimeTimer

    interval: 75
    onTriggered: if (root.visible) root.focusPrimed = true
  }

  ColorDialog {
    id: colorDialog

    property string settingKey: ""
    // Keep the picker in the same overlay window as Dock Settings. A separate
    // native dialog window can be placed below the layer-shell settings panel.
    parentWindow: root.QsWindow.contentItem
      ? root.QsWindow.contentItem.window : null
    popupType: QQC.Popup.Item
    // Omarchy runs with the GTK platform theme on Linux, where ColorDialog
    // otherwise chooses a native window that can sit below this layer-shell
    // overlay. Keep the themed quick implementation inside the panel window.
    options: ColorDialog.ShowAlphaChannel | ColorDialog.DontUseNativeDialog
    onAccepted: root.commitColorValue(settingKey, selectedColor)
  }

  FileDialog {
    id: iconFileDialog

    property string capturedDesktopId: ""
    property string capturedCurrentSource: ""
    title: "Choose application icon"
    fileMode: FileDialog.OpenFile
    nameFilters: [
      "PNG and SVG images (*.png *.svg)",
      "PNG images (*.png)",
      "SVG images (*.svg)"
    ]
    parentWindow: root.QsWindow.contentItem
      ? root.QsWindow.contentItem.window : null
    popupType: QQC.Popup.Item
    options: FileDialog.DontUseNativeDialog | FileDialog.ReadOnly
    onAccepted: {
      var targetId = capturedDesktopId
      var targetSource = capturedCurrentSource
      capturedDesktopId = ""
      capturedCurrentSource = ""
      if (!targetId
          || targetId !== DockIconModel.normalizeKey(root.iconEditorDesktopId)
          || targetSource !== root.currentIconSource(targetId))
        return
      iconOverrideEditor.selectFile(selectedFile)
    }
    onRejected: {
      capturedDesktopId = ""
      capturedCurrentSource = ""
    }
  }

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  onSettingsChanged: {
    if (!commandInput.activeFocus)
      commandInput.text = current("controlCommand")
    syncAppearanceInputs()
  }

  Shortcut {
    sequence: "Esc"
    enabled: root.visible && !colorDialog.visible && !iconFileDialog.visible
    onActivated: root.close()
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.visible && root.outsideClickDismissal
      && !colorDialog.visible && !iconFileDialog.visible
    onClicked: if (!panelHover.hovered) root.close()
  }

  Item {
    id: pointerDismissRegion

    x: root.position === "left" ? root.dockEdgePassthrough : 0
    y: root.position === "top" ? root.dockEdgePassthrough : 0
    width: root.position === "left" || root.position === "right"
      ? Math.max(0, root.width - root.dockEdgePassthrough)
      : root.width
    height: root.position === "top" || root.position === "bottom"
      ? Math.max(0, root.height - root.dockEdgePassthrough)
      : root.height
  }

  // Restrict pointer ownership to the centered card plus the area outside the
  // dock edge. Pointer motion over the excluded dock strip reaches Dock.qml.
  mask: Region {
    regions: [
      Region { item: settingsCard },
      Region { item: pointerDismissRegion }
    ]
  }

  BorderSurface {
    id: settingsCard

    x: root.panelOrigin.x
    y: root.panelOrigin.y
    width: root.panelWidth
    height: root.panelHeight
    // Keep the card on the normal content stack so Qt Quick popup overlays
    // (including the in-window color picker) can render above it.
    z: 0
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec(
      "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

    HoverHandler {
      id: panelHover
    }

    Item {
      anchors.fill: parent
      anchors.margins: Style.spacing.lg

      Item {
        id: settingsHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(62)

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          Text {
            text: "Dock Settings"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            text: "✓  Most changes apply immediately · icon previews require Apply"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        BorderSurface {
          anchors.right: parent.right
          anchors.top: parent.top
          width: Style.spacing.controlHeight
          height: width
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

          DockLucideIcon {
            anchors.centerIn: parent
            iconName: "x"
            iconSize: Style.space(18)
            tint: Color.menu.text
          }

          TapHandler { onTapped: root.close() }
        }
      }

      Flickable {
        id: settingsContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: settingsHeader.bottom
        anchors.bottom: settingsFooter.top
        anchors.bottomMargin: Style.spacing.md
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: settingsContent.contentHeight > settingsContent.height
            ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
        }

        Column {
          id: settingsColumn
          width: settingsContent.width
          spacing: Style.spacing.md

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            flow: Flow.LeftToRight

            DockSettingsSection {
              id: iconsSection
              width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
              height: root.wideLayout
                ? Math.max(iconsSection.implicitHeight, hoverSection.implicitHeight)
                : iconsSection.implicitHeight
              title: "Icons"
              iconName: "maximize-2"

              DockSettingSlider {
                width: parent.width
                label: "Icon size"
                value: root.current("iconSize")
                minimum: 24
                maximum: 96
                step: 1
                suffix: " px"
                onPreviewed: value => root.preview("iconSize", value)
                onCommitted: value => root.commit("iconSize", value)
              }

              DockSettingSlider {
                width: parent.width
                label: "Magnification"
                value: root.current("magnification")
                minimum: 1
                maximum: 2
                step: 0.05
                decimals: 2
                suffix: "x"
                onPreviewed: value => root.preview("magnification", value)
                onCommitted: value => root.commit("magnification", value)
              }

              DockSettingSlider {
                width: parent.width
                label: "Effect radius"
                value: root.current("magnificationRadius")
                minimum: 40
                maximum: 240
                step: 5
                suffix: " px"
                onPreviewed: value => root.preview("magnificationRadius", value)
                onCommitted: value => root.commit("magnificationRadius", value)
              }
            }

            DockSettingsSection {
              id: hoverSection
              width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
              height: root.wideLayout
                ? Math.max(iconsSection.implicitHeight, hoverSection.implicitHeight)
                : hoverSection.implicitHeight
              title: "Hover effect"
              description: "Accent glow behind icons under the pointer"
              iconName: "sparkles"

              headerAccessory: ToggleSwitch {
                checked: root.current("hoverGlowEnabled")
                foreground: Color.menu.text
                accent: Color.accent
                onToggled: root.commit("hoverGlowEnabled", !checked)
              }

              DockSettingSlider {
                width: parent.width
                enabled: root.current("hoverGlowEnabled")
                opacity: enabled ? 1 : 0.45
                label: "Glow intensity"
                value: root.current("hoverGlowOpacity") * 100
                minimum: 0
                maximum: 100
                step: 5
                suffix: "%"
                onPreviewed: value => root.preview("hoverGlowOpacity", value / 100)
                onCommitted: value => root.commit("hoverGlowOpacity", value / 100)
              }

              DockSettingSlider {
                width: parent.width
                enabled: root.current("hoverGlowEnabled")
                opacity: enabled ? 1 : 0.45
                label: "Glow radius"
                value: root.current("hoverGlowRadius")
                minimum: 0
                maximum: 100
                step: 5
                suffix: "%"
                onPreviewed: value => root.preview("hoverGlowRadius", value)
                onCommitted: value => root.commit("hoverGlowRadius", value)
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            flow: Flow.LeftToRight

            DockSettingsSection {
            width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
            title: "Dock surface"
            iconName: "palette"

            DockSettingSlider {
              width: parent.width
              label: "Background opacity"
              value: root.current("backgroundOpacity") * 100
              minimum: 0
              maximum: 100
              step: 5
              suffix: "%"
              onPreviewed: value => root.preview("backgroundOpacity", value / 100)
              onCommitted: value => root.commit("backgroundOpacity", value / 100)
            }

            Flow {
              width: parent.width
              spacing: Style.spacing.md
              flow: Flow.LeftToRight

              Column {
                width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
                spacing: Style.spacing.sm

                Text {
                  text: "Background"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                DockColorTokenDropdown {
                  width: parent.width
                  showLabel: false
                  enabled: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
                    !== "custom"
                  opacity: enabled ? 1 : 0.45
                  value: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
                    === "token" ? root.current("backgroundColor") : ""
                  options: root.defaultTokenOptions("Theme default", Color.menu.background)
                  fallbackColor: Color.menu.background
                  foreground: Color.menu.text
                  background: Color.menu.background
                  popupBorder: Color.menu.border
                  accent: Color.accent
                  onChanged: value => root.selectSurfaceColor(
                    "backgroundColorEnabled", "backgroundColor", value)
                }

                DockSettingsToggleRow {
                  width: parent.width
                  label: "Custom hex"
                  checked: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
                    === "custom"
                  onToggled: checked
                    ? root.commitPatch({ backgroundColorEnabled: false })
                    : root.enableCustomSurfaceColor(
                      "backgroundColorEnabled", "backgroundColor")
                }

                Item {
                  width: parent.width
                  height: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
                    === "custom" ? Style.spacing.controlHeight : 0
                  visible: height > 0

                  TextField {
                    id: backgroundColorInput
                    anchors.left: parent.left
                    anchors.right: backgroundColorSwatch.left
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "#RRGGBB or #AARRGGBB"
                    text: root.current("backgroundColor")
                    foreground: Color.menu.text
                    accent: Color.accent
                    onEditingFinished: root.commitColor(
                      "backgroundColor", backgroundColorInput)
                  }

                  DockColorSwatch {
                    id: backgroundColorSwatch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.current("backgroundColor")
                    fallbackColor: Color.menu.background
                    displayColor: root.colorForSetting("backgroundColor")
                    onClicked: root.openColorPicker("backgroundColor")
                  }
                }
              }

              Column {
                width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
                spacing: Style.spacing.sm

                Text {
                  text: "Border"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                DockColorTokenDropdown {
                  width: parent.width
                  showLabel: false
                  enabled: root.surfaceMode("borderColorEnabled", "borderColor")
                    !== "custom"
                  opacity: enabled ? 1 : 0.45
                  value: root.surfaceMode("borderColorEnabled", "borderColor")
                    === "token" ? root.current("borderColor") : ""
                  options: root.defaultTokenOptions("Theme default", Color.menu.border)
                  fallbackColor: Color.menu.border
                  foreground: Color.menu.text
                  background: Color.menu.background
                  popupBorder: Color.menu.border
                  accent: Color.accent
                  onChanged: value => root.selectSurfaceColor(
                    "borderColorEnabled", "borderColor", value)
                }

                DockSettingsToggleRow {
                  width: parent.width
                  label: "Custom hex"
                  checked: root.surfaceMode("borderColorEnabled", "borderColor")
                    === "custom"
                  onToggled: checked
                    ? root.commitPatch({ borderColorEnabled: false })
                    : root.enableCustomSurfaceColor("borderColorEnabled", "borderColor")
                }

                Item {
                  width: parent.width
                  height: root.surfaceMode("borderColorEnabled", "borderColor")
                    === "custom" ? Style.spacing.controlHeight : 0
                  visible: height > 0

                  TextField {
                    id: borderColorInput
                    anchors.left: parent.left
                    anchors.right: borderColorSwatch.left
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "#RRGGBB or #AARRGGBB"
                    text: root.current("borderColor")
                    foreground: Color.menu.text
                    accent: Color.accent
                    onEditingFinished: root.commitColor(
                      "borderColor", borderColorInput)
                  }

                  DockColorSwatch {
                    id: borderColorSwatch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.current("borderColor")
                    fallbackColor: Color.menu.border
                    displayColor: root.colorForSetting("borderColor")
                    onClicked: root.openColorPicker("borderColor")
                  }
                }

                Item {
                  width: parent.width
                  height: Style.spacing.controlHeight

                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.current("borderWidthEnabled")
                    text: "Width"
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.current("borderWidthEnabled")
                    text: "Theme default"
                    color: Util.alpha(Color.menu.text, 0.56)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  DockSettingSlider {
                    anchors.fill: parent
                    visible: root.current("borderWidthEnabled")
                    label: "Width"
                    value: root.current("borderWidth")
                    minimum: 0
                    maximum: 8
                    step: 1
                    suffix: " px"
                    onPreviewed: value => root.preview("borderWidth", value)
                    onCommitted: value => root.commit("borderWidth", value)
                  }
                }

                DockSettingsToggleRow {
                  width: parent.width
                  label: "Custom width"
                  checked: root.current("borderWidthEnabled")
                  onToggled: root.commit("borderWidthEnabled", !checked)
                }
              }
            }
          }

            DockSettingsSection {
            id: workspaceBadgeSection
            width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
            title: "Workspace badge"
            description: "Colors for workspace numbers on running app icons"
            iconName: "layout-grid"

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Column {
                width: parent.width
                spacing: Style.spacing.sm

                Text {
                  text: "Background"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                DockColorTokenDropdown {
                  width: parent.width
                  showLabel: false
                  enabled: root.surfaceMode(
                    "workspaceBadgeBackgroundColorEnabled",
                    "workspaceBadgeBackgroundColor") !== "custom"
                  opacity: enabled ? 1 : 0.45
                  value: root.surfaceMode(
                    "workspaceBadgeBackgroundColorEnabled",
                    "workspaceBadgeBackgroundColor") === "token"
                    ? root.current("workspaceBadgeBackgroundColor") : ""
                  options: root.defaultTokenOptions(
                    "Theme default", Color.accent)
                  fallbackColor: Color.accent
                  foreground: Color.menu.text
                  background: Color.menu.background
                  popupBorder: Color.menu.border
                  accent: Color.accent
                  onChanged: value => root.selectSurfaceColor(
                    "workspaceBadgeBackgroundColorEnabled",
                    "workspaceBadgeBackgroundColor", value)
                }

                DockSettingsToggleRow {
                  width: parent.width
                  label: "Custom hex"
                  checked: root.surfaceMode(
                    "workspaceBadgeBackgroundColorEnabled",
                    "workspaceBadgeBackgroundColor") === "custom"
                  onToggled: checked
                    ? root.commitPatch({
                      workspaceBadgeBackgroundColorEnabled: false
                    })
                    : root.enableCustomSurfaceColor(
                      "workspaceBadgeBackgroundColorEnabled",
                      "workspaceBadgeBackgroundColor")
                }

                Item {
                  width: parent.width
                  height: root.surfaceMode(
                    "workspaceBadgeBackgroundColorEnabled",
                    "workspaceBadgeBackgroundColor") === "custom"
                    ? Style.spacing.controlHeight : 0
                  visible: height > 0

                  TextField {
                    id: workspaceBadgeBackgroundColorInput
                    anchors.left: parent.left
                    anchors.right: workspaceBadgeBackgroundColorSwatch.left
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "#RRGGBB or #AARRGGBB"
                    text: root.current("workspaceBadgeBackgroundColor")
                    foreground: Color.menu.text
                    accent: Color.accent
                    onEditingFinished: root.commitColor(
                      "workspaceBadgeBackgroundColor",
                      workspaceBadgeBackgroundColorInput)
                  }

                  DockColorSwatch {
                    id: workspaceBadgeBackgroundColorSwatch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.current("workspaceBadgeBackgroundColor")
                    fallbackColor: Color.accent
                    displayColor: root.colorForSetting(
                      "workspaceBadgeBackgroundColor")
                    onClicked: root.openColorPicker("workspaceBadgeBackgroundColor")
                  }
                }
              }

              Column {
                width: parent.width
                spacing: Style.spacing.sm

                Text {
                  text: "Text"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                DockColorTokenDropdown {
                  width: parent.width
                  showLabel: false
                  enabled: root.surfaceMode(
                    "workspaceBadgeTextColorEnabled",
                    "workspaceBadgeTextColor") !== "custom"
                  opacity: enabled ? 1 : 0.45
                  value: root.surfaceMode(
                    "workspaceBadgeTextColorEnabled",
                    "workspaceBadgeTextColor") === "token"
                    ? root.current("workspaceBadgeTextColor") : ""
                  options: root.defaultTokenOptions(
                    "Theme default", "#ffffff")
                  fallbackColor: "#ffffff"
                  foreground: Color.menu.text
                  background: Color.menu.background
                  popupBorder: Color.menu.border
                  accent: Color.accent
                  onChanged: value => root.selectSurfaceColor(
                    "workspaceBadgeTextColorEnabled",
                    "workspaceBadgeTextColor", value)
                }

                DockSettingsToggleRow {
                  width: parent.width
                  label: "Custom hex"
                  checked: root.surfaceMode(
                    "workspaceBadgeTextColorEnabled",
                    "workspaceBadgeTextColor") === "custom"
                  onToggled: checked
                    ? root.commitPatch({ workspaceBadgeTextColorEnabled: false })
                    : root.enableCustomSurfaceColor(
                      "workspaceBadgeTextColorEnabled",
                      "workspaceBadgeTextColor")
                }

                Item {
                  width: parent.width
                  height: root.surfaceMode(
                    "workspaceBadgeTextColorEnabled",
                    "workspaceBadgeTextColor") === "custom"
                    ? Style.spacing.controlHeight : 0
                  visible: height > 0

                  TextField {
                    id: workspaceBadgeTextColorInput
                    anchors.left: parent.left
                    anchors.right: workspaceBadgeTextColorSwatch.left
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: "#RRGGBB or #AARRGGBB"
                    text: root.current("workspaceBadgeTextColor")
                    foreground: Color.menu.text
                    accent: Color.accent
                    onEditingFinished: root.commitColor(
                      "workspaceBadgeTextColor", workspaceBadgeTextColorInput)
                  }

                  DockColorSwatch {
                    id: workspaceBadgeTextColorSwatch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    value: root.current("workspaceBadgeTextColor")
                    fallbackColor: "#ffffff"
                    displayColor: root.colorForSetting(
                      "workspaceBadgeTextColor")
                    onClicked: root.openColorPicker("workspaceBadgeTextColor")
                  }
                }
              }
            }
          }

          }

          Flow {
            width: parent.width
            spacing: Style.spacing.md
            flow: Flow.LeftToRight

            DockSettingsSection {
              id: layoutSection
              width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
              height: root.wideLayout
                ? Math.max(layoutSection.implicitHeight, behaviorSection.implicitHeight)
                : layoutSection.implicitHeight
              title: "Layout"
              iconName: "panel-bottom"

              Item {
                readonly property bool stacked: root.compactControls
                width: parent.width
                height: stacked
                  ? positionLabel.implicitHeight + Style.spacing.sm
                    + positionGroup.implicitHeight
                  : Math.max(positionLabel.implicitHeight, positionGroup.implicitHeight)

                Text {
                  id: positionLabel
                  anchors.left: parent.left
                  anchors.top: parent.stacked ? parent.top : undefined
                  anchors.verticalCenter: parent.stacked ? undefined : parent.verticalCenter
                  text: "Position"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                ButtonGroup {
                  id: positionGroup
                  anchors.left: parent.stacked ? parent.left : undefined
                  anchors.right: parent.stacked ? undefined : parent.right
                  anchors.top: parent.stacked ? positionLabel.bottom : undefined
                  anchors.topMargin: parent.stacked ? Style.spacing.sm : 0
                  anchors.verticalCenter: parent.stacked ? undefined : parent.verticalCenter
                  spacing: 2
                  options: [
                    { value: "top", label: "Top" },
                    { value: "bottom", label: "Bottom" },
                    { value: "left", label: "Left" },
                    { value: "right", label: "Right" }
                  ]
                  value: root.current("position")
                  foreground: Color.menu.text
                  background: Color.menu.background
                  onChanged: value => root.commit("position", value)
                }
              }

              DockActionDropdown {
                width: parent.width
                label: "Workspace layout (top / bottom only)"
                value: root.current("workspaceLayout")
                options: [
                  { value: "flat", label: "Flat" },
                  { value: "grouped", label: "Workspace cards" }
                ]
                onChanged: value => {
                  root.preview("workspaceLayout", value)
                  root.commit("workspaceLayout", value)
                }
              }

              DockActionDropdown {
                width: parent.width
                label: "Workspaces from"
                value: root.current("workspaceMonitorScope")
                enabled: root.groupedEffective
                opacity: enabled ? 1 : 0.45
                options: [
                  { value: "all", label: "All monitors" },
                  { value: "current-monitor", label: "This monitor only" }
                ]
                onChanged: value => {
                  root.preview("workspaceMonitorScope", value)
                  root.commit("workspaceMonitorScope", value)
                }
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Full length"
                checked: root.current("fullLength")
                onToggled: root.commit("fullLength", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Show Trash"
                description: "Show the Trash shortcut and item count"
                checked: root.current("showTrash")
                onToggled: root.commit("showTrash", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Sort by workspace"
                description: root.groupedEffective ? "Flat layout only" : "Group open apps by workspace; closed pinned apps stay first"
                enabled: !root.groupedEffective
                opacity: enabled ? 1 : 0.45
                checked: root.current("sortByWorkspace")
                onToggled: root.commit("sortByWorkspace", !checked)
              }
            }

            DockSettingsSection {
              id: behaviorSection
              width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
              height: root.wideLayout
                ? Math.max(layoutSection.implicitHeight, behaviorSection.implicitHeight)
                : behaviorSection.implicitHeight
              title: "Behavior"
              iconName: "mouse-pointer-click"

              DockActionDropdown {
                width: parent.width
                label: root.groupedEffective ? "Window scope (flat layout only)" : "Window scope"
                enabled: !root.groupedEffective
                opacity: enabled ? 1 : 0.45
                value: DockWindowModel.normalizeWindowScope(
                  root.current("windowScope"))
                options: DockWindowModel.windowScopeOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("windowScope", value)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Show urgent outside scope"
                description: root.groupedEffective ? "Flat layout only"
                  : root.current("windowScope") === "all"
                    ? "All windows are already visible" : "Include truly urgent Hyprland windows from elsewhere"
                enabled: !root.groupedEffective && root.current("windowScope") !== "all"
                opacity: enabled ? 1 : 0.45
                checked: root.current("showUrgentOutsideScope") !== false
                onToggled: root.commit("showUrgentOutsideScope", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Group windows"
                description: "Show one icon per app; turn off for a separate icon per window"
                checked: root.current("groupWindows")
                onToggled: root.commit("groupWindows", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Show previews"
                description: "Show grouped window previews when hovering app icons"
                checked: root.current("showPreviews")
                onToggled: root.commit("showPreviews", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Interface animations"
                description: "Animate workspace changes and context menu opening"
                checked: root.current("interfaceAnimationsEnabled") !== false
                onToggled: root.commit("interfaceAnimationsEnabled", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Auto-hide"
                checked: root.current("autoHide")
                onToggled: root.commit("autoHide", !checked)
              }

              DockSettingsToggleRow {
                width: parent.width
                label: "Reserve space"
                description: root.current("autoHide")
                  ? "Unavailable while Auto-hide is enabled" : ""
                enabled: !root.current("autoHide")
                opacity: enabled ? 1 : 0.45
                checked: DockModel.shouldReserveSpace(
                  root.current("reserveSpace"), root.current("autoHide"))
                onToggled: root.commit("reserveSpace", !checked)
              }

              DockActionDropdown {
                width: parent.width
                label: "Left click"
                value: root.current("clickAction")
                options: DockModel.applicationActionOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("clickAction", value)
              }

              DockActionDropdown {
                width: parent.width
                label: "Middle click"
                value: root.current("middleClickAction")
                options: DockModel.applicationActionOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("middleClickAction", value)
              }

              DockActionDropdown {
                width: parent.width
                label: "Scroll"
                value: root.current("scrollAction")
                options: DockModel.scrollActionOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("scrollAction", value)
              }

            }
          }

          DockSettingsSection {
            width: parent.width
            title: "Application Badges"
            description: "Persistent badge state and reduced-motion controls"
            iconName: "sparkles"

            DockSettingsToggleRow {
              width: parent.width
              label: "Attention badges"
              description: "Show dot-first application attention and urgency indicators"
              checked: root.current("attentionBadgesEnabled") !== false
              onToggled: root.commit("attentionBadgesEnabled", !checked)
            }

            DockSettingsToggleRow {
              width: parent.width
              label: "Urgent window animation"
              description: "Nudge newly urgent windows once; disabling motion keeps the urgent badge"
              enabled: root.current("attentionBadgesEnabled") !== false
              opacity: enabled ? 1 : 0.45
              checked: root.current("urgentWindowAnimationEnabled") !== false
              onToggled: root.commit("urgentWindowAnimationEnabled", !checked)
            }
          }

          DockSettingsSection {
            id: applicationIconsSection
            objectName: "applicationIconsSection"
            width: parent.width
            activeFocusOnTab: true
            title: "Application icons"
            description: "Custom PNG/SVG artwork used throughout SmartDock"
            iconName: "app-window"

            Column {
              width: parent.width
              spacing: Style.spacing.sm
              visible: root.settingsWriteState !== "idle"

              Text {
                width: parent.width
                visible: root.settingsWriteState === "saving"
                text: "Saving settings…"
                color: Util.alpha(Color.menu.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                visible: root.settingsWriteState === "saved"
                text: "Settings saved."
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                visible: root.settingsWriteState === "error"
                text: root.settingsWriteError
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Button {
                visible: root.settingsWriteState === "error"
                text: "Retry save"
                focusable: true
                bordered: true
                foreground: Color.menu.text
                background: "transparent"
                accent: Color.accent
                onClicked: root.settingsWriteRetryRequested()
              }
            }

            Text {
              width: parent.width
              visible: root.iconOverrideRows.length === 0
                && root.iconEditorDesktopId === ""
              text: "Right-click an app in the dock to change its icon."
              color: Util.alpha(Color.menu.text, 0.52)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              id: applicationIconsList

              width: parent.width
              visible: root.iconOverrideRows.length > 0
              spacing: Style.spacing.xs

              Repeater {
                model: root.iconOverrideRows

                delegate: BorderSurface {
                  required property var modelData

                  width: applicationIconsList.width
                  implicitHeight: iconOverrideRowContent.implicitHeight
                    + Style.spacing.md * 2
                  height: implicitHeight
                  radius: Style.cornerRadius
                  color: Util.alpha(Color.menu.text, 0.02)
                  borderSpec: Border.controlSpec(
                    "normal", Color.menu.text, Color.accent)

                  Column {
                    id: iconOverrideRowContent

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.spacing.md
                    spacing: Style.spacing.xs

                    Text {
                      width: parent.width
                      text: modelData.name
                      color: Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: modelData.id
                      color: Util.alpha(Color.menu.text, 0.52)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideMiddle
                    }

                    Flow {
                      width: parent.width
                      spacing: Style.spacing.sm

                      Button {
                        text: "Change"
                        focusable: true
                        bordered: true
                        foreground: Color.menu.text
                        background: "transparent"
                        accent: Color.accent
                        onClicked: root.openIconEditor(modelData.id)
                      }

                      Button {
                        text: "Restore"
                        focusable: true
                        bordered: true
                        foreground: Color.urgent
                        background: "transparent"
                        accent: Color.urgent
                        onClicked: root.iconOverrideRequested(modelData.id, "")
                      }
                    }
                  }
                }
              }
            }

            DockIconOverrideEditor {
              id: iconOverrideEditor
              objectName: "iconOverrideEditor"

              width: parent.width
              visible: root.iconEditorDesktopId !== ""
              desktopId: root.iconEditorDesktopId
              applicationName: root.iconEditorApplicationName
              currentSource: root.currentIconSource(root.iconEditorDesktopId)
              onChooseFileRequested: root.chooseIconFile()
              onApplyRequested: (desktopId, sourceUrl) => {
                root.iconOverrideRequested(desktopId, sourceUrl)
              }
              onRestoreRequested: desktopId => root.iconOverrideRequested(desktopId, "")
            }
          }

          DockSettingsSection {
            id: hiddenApplicationsSection
            width: parent.width
            title: "Hidden Applications"
            description: "Applications hidden from the dock remain running"
            iconName: "eye-off"

            headerAccessory: Button {
              visible: root.hiddenApplicationRows.length > 0
              text: "Show All"
              focusable: true
              bordered: true
              foreground: Color.menu.text
              background: "transparent"
              accent: Color.accent
              onClicked: root.commitPatch({ hiddenApplications: [] })
            }

            Text {
              width: parent.width
              visible: root.hiddenApplicationRows.length === 0
              text: "No hidden applications"
              color: Util.alpha(Color.menu.text, 0.52)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            ListView {
              id: hiddenApplicationsList

              width: parent.width
              height: visible ? count * (Style.space(56) + spacing) - spacing : 0
              visible: count > 0
              model: root.hiddenApplicationRows
              interactive: false
              spacing: Style.spacing.xs
              clip: false

              delegate: DockHiddenApplicationRow {
                required property var modelData

                width: hiddenApplicationsList.width
                desktopId: modelData.id
                applicationName: modelData.name
                applicationIcon: modelData.icon
                iconOverrides: root.iconOverrides
                iconReloadRevision: root.iconReloadRevision
                onShowRequested: root.commitPatch({
                  hiddenApplications: DockModel.removeHiddenApplication(
                    root.current("hiddenApplications"), desktopId)
                })
              }
            }
          }

          BorderSurface {
            width: parent.width
            height: launcherDisclosureColumn.implicitHeight + Style.spacing.huge * 2
            radius: Style.cornerRadius
            color: Util.alpha(Color.accent, 0.025)
            borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)
            activeFocusOnTab: true

            Keys.onReturnPressed: root.advancedExpanded = !root.advancedExpanded
            Keys.onEnterPressed: root.advancedExpanded = !root.advancedExpanded
            Keys.onSpacePressed: root.advancedExpanded = !root.advancedExpanded

            Column {
              id: launcherDisclosureColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.spacing.huge
              spacing: Style.spacing.sm

              Item {
                width: parent.width
                height: Style.spacing.controlHeight

                DockLucideIcon {
                  id: launcherIcon
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconName: "terminal"
                  iconSize: Style.space(20)
                  tint: Color.accent
                }

                Text {
                  anchors.left: launcherIcon.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.right: launcherChevron.left
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Advanced launcher settings"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                DockLucideIcon {
                  id: launcherChevron
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconName: "chevron-right"
                  iconSize: Style.space(18)
                  tint: Color.menu.text
                  rotation: root.advancedExpanded ? 90 : 0
                  Behavior on rotation { NumberAnimation { duration: 120 } }
                }

                TapHandler {
                  onTapped: root.advancedExpanded = !root.advancedExpanded
                }
              }

              Column {
                visible: root.advancedExpanded
                width: parent.width
                spacing: Style.spacing.xs

                Text {
                  text: "Command run when Open App Launcher is selected"
                  color: Util.alpha(Color.menu.text, 0.56)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                TextField {
                  id: commandInput
                  width: parent.width
                  placeholderText: "omarchy-menu toggle apps"
                  foreground: Color.menu.text
                  onEditingFinished: root.commitControlCommand()
                  Keys.onEscapePressed: {
                    text = root.current("controlCommand")
                    focus = false
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: settingsFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(52)

        BorderSurface {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(168)
          height: Style.spacing.controlHeight
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)

          DockLucideIcon {
            id: resetIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            iconName: "rotate-ccw"
            iconSize: Style.space(18)
            tint: Color.urgent
          }

          Text {
            anchors.left: resetIcon.right
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            text: "Reset to defaults"
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          TapHandler {
            onTapped: {
              commandInput.text = DockModel.resetSettingsPatch().controlCommand
              root.resetRequested()
            }
          }
        }

        BorderSurface {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(112)
          height: Style.spacing.controlHeight
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

          Text {
            anchors.centerIn: parent
            text: "Close"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          TapHandler { onTapped: root.close() }
        }
      }
    }
  }
}
