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

PanelWindow {
  id: root

  required property Item anchorItem
  required property string position
  required property var settings
  property bool outsideClickDismissal: true
  // Prime layer-shell focus briefly on open so keyboard navigation works, then
  // settle on OnDemand so Hyprland does not route every pointer event to this
  // full-screen settings surface.
  property bool focusPrimed: false
  signal settingPreviewed(string key, var value)
  signal settingCommitted(string key, var value)
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
  readonly property int panelHeight: Math.min(900,
    Math.max(360, panelScreenHeight - panelMargin * 2))
  readonly property bool wideLayout: panelWidth >= 720
  // The values are symbolic references to Omarchy's live Color singleton.
  // Persisting the reference (rather than a snapshot hex value) keeps a
  // selected preset synchronized when the active theme changes.
  readonly property var themeColorTokens: ({
    "background": Color.background,
    "foreground": Color.foreground,
    "accent": Color.accent,
    "muted": Color.muted,
    "urgent": Color.urgent,
    "bar.background": Color.bar.background,
    "bar.text": Color.bar.text,
    "bar.active": Color.bar.active,
    "popups.background": Color.popups.background,
    "popups.text": Color.popups.text,
    "popups.border": Color.popups.border,
    "tooltip.background": Color.tooltip.background,
    "tooltip.text": Color.tooltip.text,
    "tooltip.border": Color.tooltip.border,
    "menu.background": Color.menu.background,
    "menu.text": Color.menu.text,
    "menu.border": Color.menu.border,
    "menu.selected-background": Color.menu.selectedBackground,
    "menu.selected-text": Color.menu.selectedText,
    "menu.selected-border": Color.menu.selectedBorder,
    "notifications.background": Color.notifications.background,
    "notifications.text": Color.notifications.text,
    "notifications.border": Color.notifications.border,
    "notifications.countdown": Color.notifications.countdown
  })
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
    return DockModel.normalizeSetting(key, settings ? settings[key] : undefined)
  }

  function colorForSetting(key) {
    return DockModel.resolveColorValue(
      current(key),
      themeColorTokens,
      key === "backgroundColor" ? Color.menu.background : Color.menu.border)
  }

  function preview(key, value) {
    settingPreviewed(key, DockModel.normalizeSetting(key, value))
  }

  function commit(key, value) {
    settingCommitted(key, DockModel.normalizeSetting(key, value))
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
      ? "Dock background color" : "Dock border color"
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
    if (normalized !== current(key)) settingCommitted(key, normalized)
  }

  function open() {
    commandInput.text = current("controlCommand")
    syncAppearanceInputs()
    visible = true
    Qt.callLater(() => positionGroup.forceActiveFocus())
  }

  function beginFocusPrime() {
    if (visible && backingWindowVisible) focusPrimeTimer.restart()
  }

  function close() {
    if (commandInput.activeFocus) commitControlCommand()
    if (colorDialog.visible) colorDialog.close()
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

  onVisibleChanged: {
    if (visible) {
      focusPrimed = false
      beginFocusPrime()
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
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
    onActivated: root.close()
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.visible && root.outsideClickDismissal
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

    Flickable {
      id: scrollView

      anchors.fill: parent
      anchors.margins: 16
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick

      QQC.ScrollBar.vertical: QQC.ScrollBar {
        policy: scrollView.contentHeight > scrollView.height
          ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
      }

      Column {
        id: contentColumn

        width: scrollView.width
        spacing: 8

        Item {
          width: parent.width
          height: 70

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text {
              text: "Dock Settings"
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true
            }

            Text {
              text: "✓  Changes apply immediately"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          Button {
            anchors.right: parent.right
            anchors.top: parent.top
            iconText: "󰅖"
            tooltipText: "Close"
            bordered: true
            foreground: Color.menu.text
            background: Color.menu.background
            onClicked: root.close()
          }
        }

        BorderSurface {
          width: parent.width
          height: appearanceContent.implicitHeight + 24
          radius: Style.cornerRadius
          color: Util.alpha(Color.menu.text, 0.035)
          borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

          Column {
            id: appearanceContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 5

            Text {
              text: "󰏘  Appearance"
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Flow {
              width: parent.width
              spacing: 8
              flow: Flow.LeftToRight

              Item {
                width: root.wideLayout ? (parent.width - 8) / 2 : parent.width
                height: appearancePrimary.implicitHeight

                Column {
                  id: appearancePrimary
                  width: parent.width
                  spacing: 5

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

                  Toggle {
                    width: parent.width
                    label: "Use custom background color"
                    description: "Override Omarchy's menu background token"
                    checked: root.current("backgroundColorEnabled")
                    foreground: Color.menu.text
                    onClicked: root.commit("backgroundColorEnabled", !checked)
                  }

                  Item {
                    width: parent.width
                    height: 38

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Background hex"
                      color: Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      opacity: backgroundColorInput.enabled ? 1 : 0.5
                    }

                    TextField {
                      id: backgroundColorInput

                      anchors.right: backgroundColorSwatch.left
                      anchors.rightMargin: 6
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(190, parent.width * 0.5)
                      placeholderText: "#RRGGBB or @token"
                      text: root.current("backgroundColor")
                      enabled: root.current("backgroundColorEnabled")
                      foreground: Color.menu.text
                      accent: Color.accent
                      opacity: enabled ? 1 : 0.5
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
                      enabled: root.current("backgroundColorEnabled")
                      onClicked: root.openColorPicker("backgroundColor")
                    }
                  }

                  Item {
                    width: parent.width
                    height: 38

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Theme token"
                      color: Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      opacity: backgroundColorTokenPicker.enabled ? 1 : 0.5
                    }

                    DockColorTokenDropdown {
                      id: backgroundColorTokenPicker

                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(250, parent.width * 0.58)
                      showLabel: false
                      value: root.current("backgroundColor")
                      options: root.themeColorOptions
                      fallbackColor: Color.menu.background
                      foreground: Color.menu.text
                      background: Color.menu.background
                      popupBorder: Color.menu.border
                      accent: Color.accent
                      enabled: root.current("backgroundColorEnabled")
                      opacity: enabled ? 1 : 0.5
                      onChanged: value => root.commit("backgroundColor", value)
                    }
                  }
                }
              }

              Item {
                width: root.wideLayout ? (parent.width - 8) / 2 : parent.width
                height: appearanceSecondary.implicitHeight

                Column {
                  id: appearanceSecondary
                  width: parent.width
                  spacing: 5

                  DockSettingSlider {
                    width: parent.width
                    label: "Magnification radius"
                    value: root.current("magnificationRadius")
                    minimum: 40
                    maximum: 240
                    step: 5
                    suffix: " px"
                    onPreviewed: value => root.preview("magnificationRadius", value)
                    onCommitted: value => root.commit("magnificationRadius", value)
                  }

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

                  Toggle {
                    width: parent.width
                    label: "Hover glow"
                    description: "Show an accent glow behind icons under the pointer"
                    checked: root.current("hoverGlowEnabled")
                    foreground: Color.menu.text
                    onClicked: root.commit("hoverGlowEnabled", !checked)
                  }

                  DockSettingSlider {
                    width: parent.width
                    enabled: root.current("hoverGlowEnabled")
                    opacity: enabled ? 1 : 0.5
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
                    opacity: enabled ? 1 : 0.5
                    label: "Glow radius"
                    value: root.current("hoverGlowRadius")
                    minimum: 0
                    maximum: 100
                    step: 5
                    suffix: "%"
                    onPreviewed: value => root.preview("hoverGlowRadius", value)
                    onCommitted: value => root.commit("hoverGlowRadius", value)
                  }

                  Toggle {
                    width: parent.width
                    label: "Use custom border color"
                    description: "Override Omarchy's menu border token"
                    checked: root.current("borderColorEnabled")
                    foreground: Color.menu.text
                    onClicked: root.commit("borderColorEnabled", !checked)
                  }

                  Item {
                    width: parent.width
                    height: 38

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Border hex"
                      color: Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      opacity: borderColorInput.enabled ? 1 : 0.5
                    }

                    TextField {
                      id: borderColorInput

                      anchors.right: borderColorSwatch.left
                      anchors.rightMargin: 6
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(190, parent.width * 0.5)
                      placeholderText: "#RRGGBB or @token"
                      text: root.current("borderColor")
                      enabled: root.current("borderColorEnabled")
                      foreground: Color.menu.text
                      accent: Color.accent
                      opacity: enabled ? 1 : 0.5
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
                      enabled: root.current("borderColorEnabled")
                      onClicked: root.openColorPicker("borderColor")
                    }
                  }

                  Item {
                    width: parent.width
                    height: 38

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Theme token"
                      color: Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      opacity: borderColorTokenPicker.enabled ? 1 : 0.5
                    }

                    DockColorTokenDropdown {
                      id: borderColorTokenPicker

                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(250, parent.width * 0.58)
                      showLabel: false
                      value: root.current("borderColor")
                      options: root.themeColorOptions
                      fallbackColor: Color.menu.border
                      foreground: Color.menu.text
                      background: Color.menu.background
                      popupBorder: Color.menu.border
                      accent: Color.accent
                      enabled: root.current("borderColorEnabled")
                      opacity: enabled ? 1 : 0.5
                      onChanged: value => root.commit("borderColor", value)
                    }
                  }
                }
              }
            }

            Flow {
              width: parent.width
              spacing: 8
              flow: Flow.LeftToRight

              Toggle {
                id: borderWidthToggle
                width: root.wideLayout ? (parent.width - 8) / 2 : parent.width
                label: "Use custom border width"
                description: "Override the theme border thickness"
                checked: root.current("borderWidthEnabled")
                foreground: Color.menu.text
                onClicked: root.commit("borderWidthEnabled", !checked)
              }

              Item {
                width: root.wideLayout ? (parent.width - 8) / 2 : parent.width
                height: borderWidthToggle.implicitHeight

                DockSettingSlider {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: root.current("borderWidthEnabled")
                  opacity: enabled ? 1 : 0.5
                  label: "Border width"
                  value: root.current("borderWidth")
                  minimum: 0
                  maximum: 8
                  step: 1
                  suffix: " px"
                  onPreviewed: value => root.preview("borderWidth", value)
                  onCommitted: value => root.commit("borderWidth", value)
                }
              }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: 8
          flow: Flow.LeftToRight

          BorderSurface {
            width: root.wideLayout ? (parent.width - 8) / 2 : parent.width
            height: layoutContent.implicitHeight + 24
            radius: Style.cornerRadius
            color: Util.alpha(Color.menu.text, 0.035)
            borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

            Column {
              id: layoutContent

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 5

              Text {
                text: "󰕰  Layout"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Item {
                width: parent.width
                height: Math.max(positionLabel.implicitHeight, positionGroup.implicitHeight)

                Text {
                  id: positionLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Position"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                ButtonGroup {
                  id: positionGroup
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
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

              Toggle {
                width: parent.width
                label: "Full length"
                description: "Extend the dock across the entire screen"
                checked: root.current("fullLength")
                foreground: Color.menu.text
                onClicked: root.commit("fullLength", !checked)
              }

              Toggle {
                width: parent.width
                label: "Reserve space"
                description: "Keep windows from overlapping the dock while it is visible"
                enabled: !root.current("autoHide")
                opacity: enabled ? 1 : 0.5
                checked: DockModel.shouldReserveSpace(
                  root.current("reserveSpace"), root.current("autoHide"))
                foreground: Color.menu.text
                onClicked: root.commit("reserveSpace", !checked)
              }
            }
          }

          BorderSurface {
            width: root.wideLayout ? (parent.width - 8) / 2 : parent.width
            height: behaviorContent.implicitHeight + 24
            radius: Style.cornerRadius
            color: Util.alpha(Color.menu.text, 0.035)
            borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

            Column {
              id: behaviorContent

              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 12
              spacing: 5

              Text {
                text: "󰒓  Behavior"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Toggle {
                width: parent.width
                label: "Auto-hide"
                description: "Hide the dock when it is not in use; hidden docks do not reserve space"
                checked: root.current("autoHide")
                foreground: Color.menu.text
                onClicked: root.commit("autoHide", !checked)
              }

              Item {
                width: parent.width
                height: Math.max(clickLabel.implicitHeight, clickActionGroup.implicitHeight)

                Text {
                  id: clickLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Click action"
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                ButtonGroup {
                  id: clickActionGroup
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2
                  options: [
                    { value: "focus-or-launch", label: "Focus or launch" },
                    { value: "launch", label: "Always launch" }
                  ]
                  value: root.current("clickAction")
                  foreground: Color.menu.text
                  background: Color.menu.background
                  onChanged: value => root.commit("clickAction", value)
                }
              }
            }
          }
        }

        BorderSurface {
          width: parent.width
          height: launcherContent.implicitHeight + 24
          radius: Style.cornerRadius
          color: Util.alpha(Color.menu.text, 0.035)
          borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

          Column {
            id: launcherContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 5

            Text {
              text: "󰑮  Launcher"
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: "Control command"
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              text: "Command run when the first dock icon is clicked"
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

        Button {
          text: "Reset to defaults"
          iconText: "󰑐"
          foreground: Color.accent
          leftAlign: true
          onClicked: {
            commandInput.text = DockModel.resetSettingsPatch().controlCommand
            root.resetRequested()
          }
        }
      }
    }
  }
}
