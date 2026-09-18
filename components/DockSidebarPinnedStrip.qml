pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui

// Stable bottom pin shelf (Direction A). Settings.pinned order, including
// running apps (focus-or-launch). Icons wrap to additional rows when the shelf
// is too narrow for a single line. Strip-owned anchors for context.
//
// Projection rebuilds replace the launchers array, so GridView add/remove
// transitions never run. A local ListModel diffs keys and keeps exiting rows
// alive long enough for opacity/scale Behaviors (same idea as the + button).
Item {
  id: root
  required property var controller
  required property var panel
  required property var appearance
  readonly property var pins: controller.projection.launchers || []
  readonly property bool collapsed: panel && panel.panelCollapsed === true
  readonly property bool animationsEnabled:
    controller.settings.interfaceAnimationsEnabled !== false
  readonly property int animMs: animationsEnabled ? 180 : 0
  readonly property real iconSize: 26
  readonly property real cell: 36
  readonly property real pinGap: Style.space(6)
  readonly property real headingHeight: Style.space(28)
  readonly property real shelfPadX: Style.space(4)
  readonly property real shelfPadBottom: Style.space(5)
  // Rail hides the strip entirely — zero height and no residual gap.
  implicitHeight: collapsed ? 0 : (headingHeight + Style.space(3)
    + Math.max(0, flow.implicitHeight) + shelfPadBottom)
  height: implicitHeight
  visible: !collapsed
  enabled: !collapsed
  clip: true
  readonly property var addPinButton: addPin

  property var prevPins: []
  property var exitStash: ({})
  property bool stripReady: false

  ListModel {
    id: displayModel
  }

  function launcherFor(key) {
    var want = String(key || "")
    var list = root.pins || []
    for (var i = 0; i < list.length; ++i) {
      if (String(list[i].key || "") === want) return list[i]
    }
    return root.exitStash[want] || null
  }

  function copyStash(src) {
    var out = ({})
    var keys = Object.keys(src || ({}))
    for (var i = 0; i < keys.length; ++i) out[keys[i]] = src[keys[i]]
    return out
  }

  function finishExit(key) {
    var want = String(key || "")
    for (var i = displayModel.count - 1; i >= 0; --i) {
      if (String(displayModel.get(i).key) === want && displayModel.get(i).exiting === true)
        displayModel.remove(i)
    }
    var next = root.copyStash(root.exitStash)
    delete next[want]
    root.exitStash = next
  }

  function syncDisplay() {
    var list = []
    var raw = root.pins || []
    for (var i = 0; i < raw.length; ++i) list.push(raw[i])

    var nextByKey = Object.create(null)
    for (var n = 0; n < list.length; ++n)
      nextByKey[String(list[n].key || "")] = list[n]

    var prevByKey = Object.create(null)
    for (var p = 0; p < root.prevPins.length; ++p)
      prevByKey[String(root.prevPins[p].key || "")] = root.prevPins[p]

    for (var d = displayModel.count - 1; d >= 0; --d) {
      var row = displayModel.get(d)
      var key = String(row.key || "")
      if (!nextByKey[key] && row.exiting !== true) {
        var stash = root.copyStash(root.exitStash)
        stash[key] = prevByKey[key] || root.launcherFor(key) || stash[key] || null
        root.exitStash = stash
        displayModel.setProperty(d, "exiting", true)
        if (!root.animationsEnabled) root.finishExit(key)
      } else if (nextByKey[key] && row.exiting === true) {
        displayModel.setProperty(d, "exiting", false)
      }
    }

    var displayed = Object.create(null)
    for (var e = 0; e < displayModel.count; ++e)
      displayed[String(displayModel.get(e).key)] = true

    for (var a = 0; a < list.length; ++a) {
      var addKey = String(list[a].key || "")
      if (!addKey || displayed[addKey]) continue
      displayModel.append({
        key: addKey,
        exiting: false,
        // Animate only after the shelf has painted once (avoid boot fanfare).
        animateIn: root.stripReady && root.animationsEnabled
      })
      displayed[addKey] = true
    }

    // Reconcile order as well as membership. Move existing model rows instead
    // of resetting them; pending exits remain alive after the ordered live pins.
    for (var targetIndex = 0; targetIndex < list.length; ++targetIndex) {
      var targetKey = String(list[targetIndex].key || "")
      for (var currentIndex = targetIndex; currentIndex < displayModel.count; ++currentIndex) {
        if (String(displayModel.get(currentIndex).key) !== targetKey) continue
        if (currentIndex !== targetIndex) displayModel.move(currentIndex, targetIndex, 1)
        break
      }
    }

    var cleaned = root.copyStash(root.exitStash)
    var changed = false
    var stashKeys = Object.keys(cleaned)
    for (var s = 0; s < stashKeys.length; ++s) {
      if (nextByKey[stashKeys[s]]) {
        delete cleaned[stashKeys[s]]
        changed = true
      }
    }
    if (changed) root.exitStash = cleaned

    root.prevPins = list
  }

  onPinsChanged: syncDisplay()
  Component.onCompleted: {
    syncDisplay()
    root.stripReady = true
  }
  Connections {
    target: root.controller
    function onRefreshed() { root.syncDisplay() }
  }

  Ui.BorderSurface {
    anchors.fill: parent
    radius: root.appearance.cardRadius
    color: root.appearance.workspaceFill
    borderSpec: Border.none()
    enabled: false
  }

  Item {
    id: headingRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.shelfPadX
    anchors.rightMargin: root.shelfPadX
    height: root.headingHeight
    Text {
      id: caption
      anchors.left: parent.left
      anchors.leftMargin: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: addPin.left
      anchors.rightMargin: Style.space(6)
      text: "Pinned"
      textFormat: Text.PlainText
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      elide: Text.ElideRight
    }
    Ui.Button {
      id: addPin
      objectName: "sidebar-pin-strip-add"
      property bool pinStripOwned: true
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(24)
      height: Style.space(24)
      visible: !root.collapsed
      iconText: ""
      tooltipText: "Add a pinned application"
      Accessible.name: "Add pinned application"
      focusable: true
      enabled: !root.controller.interactionBusy
      onClicked: root.panel.openPinPicker(addPin)
      DockLucideIcon {
        anchors.centerIn: parent
        width: 13
        height: 13
        iconName: "plus"
        iconSize: 13
        tint: Color.foreground
      }
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: Util.alpha(Color.foreground, 0.08)
    }
  }

  Flow {
    id: flow
    objectName: "sidebar-pin-strip"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: headingRow.bottom
    anchors.topMargin: Style.space(3)
    anchors.leftMargin: Style.space(3)
    anchors.rightMargin: Style.space(3)
    spacing: root.pinGap
    flow: Flow.LeftToRight

    Repeater {
      model: displayModel
      delegate: Item {
        id: pinCell
        required property int index
        required property string key
        required property bool exiting
        required property bool animateIn
        readonly property var modelData: root.launcherFor(key)
        readonly property string rowKey: String(key || "")
        readonly property string desktopId: String((modelData && modelData.desktopId) || "")
        readonly property var entry: {
          var apps = DesktopEntries.applications.values || []
          var revision = apps.length
          if (modelData && modelData.item && modelData.item.entry) return modelData.item.entry
          if (!pinCell.desktopId) return null
          return DesktopEntries.byId(pinCell.desktopId)
        }
        readonly property bool pinStripOwned: true
        // Drive opacity/scale through a settled flag so Behaviors actually run
        // (a direct binding to exiting alone skips the "from" frame on insert).
        property bool settled: !animateIn
        width: root.cell
        height: root.cell
        transformOrigin: Item.Center
        opacity: exiting ? 0 : (settled ? 1 : 0)
        scale: exiting ? 0.55 : (settled ? 1 : 0.55)
        visible: !!modelData || exiting
        focus: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: String((modelData && (modelData.label || modelData.desktopId)) || "Pinned application")

        Behavior on opacity {
          enabled: root.animationsEnabled
          NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
          enabled: root.animationsEnabled
          NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic }
        }

        Component.onCompleted: {
          if (!pinCell.animateIn || !root.animationsEnabled) {
            pinCell.settled = true
            return
          }
          Qt.callLater(function() {
            if (!pinCell || pinCell.exiting) return
            pinCell.settled = true
            if (pinCell.index >= 0 && pinCell.index < displayModel.count)
              displayModel.setProperty(pinCell.index, "animateIn", false)
          })
        }

        onExitingChanged: {
          if (!exiting) return
          if (!root.animationsEnabled) {
            root.finishExit(pinCell.key)
            return
          }
          exitDelay.restart()
        }

        Timer {
          id: exitDelay
          interval: Math.max(root.animMs, 1)
          repeat: false
          onTriggered: root.finishExit(pinCell.key)
        }

        Keys.onPressed: function(event) {
          if (!pinCell.modelData || pinCell.exiting) return
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activatePin(pinCell.modelData)
            event.accepted = true
          } else if (event.key === Qt.Key_Menu) {
            root.panel.openContext(pinCell.modelData, pinCell)
            event.accepted = true
          }
        }

        // Shelf is the single block; cells only paint hover/press/focus fills.
        Rectangle {
          anchors.fill: parent
          radius: root.appearance.cardRadius
          color: pinPress.pressed ? Style.pressedFillFor(Color.foreground, Color.accent)
            : pinHover.hovered || pinCell.activeFocus ? root.appearance.workspaceHoverFill
            : "transparent"
        }

        DockAppIcon {
          id: pinIcon
          anchors.centerIn: parent
          width: root.iconSize
          height: root.iconSize
          desktopId: pinCell.desktopId
          desktopIcon: pinCell.entry ? String(pinCell.entry.icon || "") : ""
          iconOverrides: root.controller.settings.iconOverrides || ({})
          reloadRevision: root.controller.host.iconReloadRevision || 0
          profileBadgesEnabled: false
          opacity: pinCell.modelData && pinCell.modelData.running ? 1 : 0.92
        }

        HoverHandler { id: pinHover }
        TapHandler {
          id: pinPress
          acceptedButtons: Qt.LeftButton
          enabled: !!pinCell.modelData && !pinCell.exiting
          onTapped: {
            pinCell.forceActiveFocus(Qt.MouseFocusReason)
            root.activatePin(pinCell.modelData)
          }
        }
        TapHandler {
          acceptedButtons: Qt.RightButton
          enabled: !!pinCell.modelData && !pinCell.exiting
          onTapped: {
            pinCell.forceActiveFocus(Qt.MouseFocusReason)
            root.panel.openContext(pinCell.modelData, pinCell)
          }
        }
        DockToolTip {
          anchorItem: pinCell
          position: "bottom"
          requestedVisible: pinHover.hovered && !root.controller.rowDragActive
            && !!pinCell.modelData && !pinCell.exiting
          text: String((pinCell.modelData && (pinCell.modelData.label || pinCell.modelData.desktopId)) || "Pinned app")
            + (pinCell.modelData && pinCell.modelData.running ? " · Running" : "")
          fontFamily: Style.font.family
          fontSize: Style.font.bodySmall
        }
      }
    }
  }

  function activatePin(target) {
    if (!target) return false
    return root.controller.activateTarget({
      key: target.key,
      kind: "launcher",
      desktopId: target.desktopId || ""
    }, false, "")
  }
}
