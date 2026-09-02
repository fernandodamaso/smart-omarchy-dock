pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string label
  required property string value
  required property var options
  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color popupBorder: Color.menu.border
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight

  signal changed(string value)

  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", popupBorder, Color.popups.border,
    Style.normalBorderWidth)

  function optionValue(option) {
    return option && typeof option === "object"
      ? String(option.value) : String(option)
  }

  function optionLabel(option) {
    return option && typeof option === "object"
      ? String(option.label) : String(option)
  }

  function selectedLabel() {
    for (var i = 0; i < options.length; ++i) {
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    }
    return value
  }

  implicitHeight: actionLabel.implicitHeight + Style.spacing.xs + rowHeight

  Text {
    id: actionLabel

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.label
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  BorderSurface {
    id: trigger

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: actionLabel.bottom
    anchors.topMargin: Style.spacing.xs
    height: root.rowHeight
    radius: Style.cornerRadius
    activeFocusOnTab: true

    readonly property bool hot: triggerHover.hovered
    readonly property var stateBorder: Border.controlSpec(
      trigger.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
      root.foreground, root.accent)

    color: Style.controlFill(trigger.activeFocus, hot,
      root.foreground, root.accent)
    borderSpec: stateBorder

    HoverHandler { id: triggerHover }

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

    Text {
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.md
      text: root.selectedLabel()
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
        optionList.currentIndex = Math.max(0, optionList.indexOfValue(root.value))
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
          for (var i = 0; i < root.options.length; ++i) {
            if (root.optionValue(root.options[i]) === v) return i
          }
          return -1
        }

        function selectCurrent() {
          if (currentIndex < 0 || currentIndex >= root.options.length) return
          var selected = root.optionValue(root.options[currentIndex])
          root.changed(selected)
          popup.close()
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            popup.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.text === "j") {
            currentIndex = Math.min(root.options.length - 1, currentIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            currentIndex = Math.max(0, currentIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            selectCurrent()
            event.accepted = true
          }
        }

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: optionList.width
          height: root.popupRowHeight
          color: index === optionList.currentIndex
            ? Style.hoverFillFor(root.foreground, root.accent)
            : "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
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
