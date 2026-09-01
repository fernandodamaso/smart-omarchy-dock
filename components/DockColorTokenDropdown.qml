pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// A compact themed selector for Omarchy color tokens. Unlike the generic
// Dropdown, every option carries a live color square so the palette can be
// recognized visually before it is selected.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property color fallbackColor: Color.menu.background
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true
  property bool hasCursor: false

  readonly property bool popupOpen: popup.opened

  signal changed(string value)
  signal hovered(bool isHovered)

  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", popupBorder, Color.popups.border,
    Style.normalBorderWidth)

  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  function optionValue(option) {
    return (option && typeof option === "object")
      ? String(option.value) : String(option)
  }

  function optionLabel(option) {
    return (option && typeof option === "object")
      ? String(option.label) : String(option)
  }

  function optionColor(option) {
    return option && typeof option === "object" && option.color !== undefined
      ? option.color : root.foreground
  }

  function selectedOption() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return options[i]
    }
    return null
  }

  function currentLabel() {
    var selected = selectedOption()
    return selected ? optionLabel(selected)
      : value === "" ? "Use Omarchy default" : value
  }

  function currentColor() {
    var selected = selectedOption()
    if (selected) return optionColor(selected)
    return value === "" ? root.fallbackColor : value
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: showLabel && label !== ""
    ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger

      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius
      activeFocusOnTab: true

      readonly property bool hot: triggerHover.hovered || root.hasCursor
      readonly property var stateBorder: Border.controlSpec(
        trigger.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
        root.foreground, root.accent)

      color: Style.controlFill(trigger.activeFocus, hot,
        root.foreground, root.accent)
      borderSpec: stateBorder

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close()
          event.accepted = true
        }
      }

      Rectangle {
        id: currentSwatch

        anchors.left: parent.left
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        height: width
        radius: Style.cornerRadius / 2
        color: root.currentColor()
        border.width: Style.normalBorderWidth
        border.color: root.foreground
        opacity: root.enabled ? 1 : 0.55
      }

      Text {
        anchors.left: currentSwatch.right
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.controlGap
        anchors.rightMargin: Style.spacing.md
        text: root.currentLabel()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      Popup {
        id: popup

        x: 0
        y: trigger.height + Style.spacing.xxs
        width: trigger.width
        implicitHeight: Math.min(
          root.options.length * root.popupRowHeight
            + Math.max(0, root.options.length - 1) * Style.spacing.labelGap
            + Style.spacing.xxs,
          root.popupRowHeight * 8 + 7 * Style.spacing.labelGap
            + Style.spacing.xxs)
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          optionList.currentIndex = Math.max(0,
            optionList.indexOfValue(root.value))
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList

          spacing: Style.spacing.labelGap
          Keys.priority: Keys.BeforeItem
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: -1

          function indexOfValue(v) {
            for (var i = 0; i < root.options.length; i++) {
              if (root.optionValue(root.options[i]) === v) return i
            }
            return -1
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              popup.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.currentIndex = Math.min(root.options.length - 1,
                optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.currentIndex = Math.max(0,
                optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter) {
              optionList.selectCurrent()
              event.accepted = true
            }
          }

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.options.length)
              return
            var selected = root.optionValue(root.options[currentIndex])
            root.value = selected
            root.changed(selected)
            popup.close()
          }

          delegate: Rectangle {
            required property var modelData
            required property int index

            width: optionList.width
            height: root.popupRowHeight
            color: index === optionList.currentIndex
              ? Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"

            Rectangle {
              id: optionSwatch

              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: width
              radius: Style.cornerRadius / 2
              color: root.optionColor(modelData)
              border.width: Style.normalBorderWidth
              border.color: root.foreground
            }

            Text {
              anchors.left: optionSwatch.right
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.controlGap
              anchors.rightMargin: Style.spacing.controlPaddingX
              text: root.optionLabel(modelData)
              color: index === optionList.currentIndex
                ? Style.hoverStateColor(root.foreground, root.accent)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              enabled: root.enabled
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: optionList.currentIndex = parent.index
              onClicked: optionList.selectCurrent()
            }
          }
        }
      }
    }
  }
}
