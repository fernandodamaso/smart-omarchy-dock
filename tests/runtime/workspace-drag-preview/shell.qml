import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "PreviewModel.js" as PreviewModel

ShellRoot {
  id: root

  property string scopeMode: "all"
  property bool animationsEnabled: true
  property bool autoHideEnabled: false
  property bool overflowScenario: false
  property bool emptyDestinationScenario: false
  property var committedFixtures: baselineFixtures()
  property var presentation: PreviewModel.project(committedFixtures, null)

  function iconItem(desktopId, badge, badgeText) {
    var item = { presentationId: desktopId, desktopId: desktopId }
    if (badge) {
      item.badge = true
      item.badgeText = badgeText || "3"
    }
    return item
  }

  function baselineFixtures() {
    return {
      monitors: [
        {
          identity: "id:0",
          connector: "DP-1",
          label: "Monitor A",
          activeWorkspace: "id:1",
          pinnedWorkspaces: []
        },
        {
          identity: "id:1",
          connector: "HDMI-A-1",
          label: "Monitor B",
          activeWorkspace: "id:4",
          pinnedWorkspaces: ["name:Work"]
        }
      ],
      workspaces: [
        {
          identity: "id:1",
          owner: "id:0",
          label: "1",
          showFullLabel: false,
          count: 1,
          items: [iconItem("preview.chrome")]
        },
        {
          identity: "id:2",
          owner: "id:0",
          label: "2",
          showFullLabel: false,
          count: 3,
          badge: true,
          items: [
            iconItem("preview.files"),
            iconItem("preview.terminal", true, "3"),
            iconItem("preview.chat")
          ]
        },
        {
          identity: "id:3",
          owner: "id:0",
          label: "3",
          showFullLabel: false,
          count: 0,
          items: []
        },
        {
          identity: "id:4",
          owner: "id:1",
          label: "4",
          showFullLabel: false,
          count: 2,
          items: [iconItem("preview.notes"), iconItem("preview.code")]
        },
        {
          identity: "name:Work",
          owner: "id:1",
          label: "Work",
          showFullLabel: true,
          count: 1,
          items: [iconItem("preview.mail")]
        }
      ]
    }
  }

  function overflowFixtures() {
    var fixtures = baselineFixtures()
    for (var i = 5; i <= 12; ++i) {
      fixtures.workspaces.push({
        identity: "id:" + i,
        owner: "id:0",
        label: String(i),
        showFullLabel: false,
        count: 1,
        items: [iconItem("preview.chrome")]
      })
    }
    return fixtures
  }

  function emptyDestinationFixtures() {
    var fixtures = baselineFixtures()
    fixtures.monitors[1].activeWorkspace = ""
    fixtures.monitors[1].pinnedWorkspaces = []
    fixtures.workspaces = fixtures.workspaces.filter(function (workspace) {
      return workspace.owner !== "id:1"
    })
    return fixtures
  }

  function cancelActiveGesture() {
    if (dragController.active)
      dragController.cancel("fixture replacement")
  }

  function replaceFixtures(next) {
    cancelActiveGesture()
    committedFixtures = next
    dragController.committedFixtures = next
    presentation = PreviewModel.project(committedFixtures, null)
  }

  function resetFixtures() {
    overflowScenario = false
    emptyDestinationScenario = false
    replaceFixtures(baselineFixtures())
  }

  function applyScenario() {
    if (overflowScenario)
      replaceFixtures(overflowFixtures())
    else if (emptyDestinationScenario)
      replaceFixtures(emptyDestinationFixtures())
    else
      replaceFixtures(baselineFixtures())
  }

  function syncDockRegistration() {
    dragController.registerDock(dockA)
    dragController.registerDock(dockB)
    dockA.sceneOrigin = dockA.mapToItem(null, 0, 0)
    dockB.sceneOrigin = dockB.mapToItem(null, 0, 0)
    dockA.monitorOrigin = dockA.sceneOrigin
    dockB.monitorOrigin = dockB.sceneOrigin
  }

  PreviewDrag {
    id: dragController
    committedFixtures: root.committedFixtures
    animationsEnabled: root.animationsEnabled
    accent: Color.accent
    background: Color.menu.background
    foreground: Color.menu.text
    fontFamily: Style.font.family
    fontSize: Style.font.bodySmall
    onFixturesCommitted: fixtures => {
      root.committedFixtures = fixtures
    }
    onPresentationChanged: next => {
      root.presentation = next
    }
  }

  FloatingWindow {
    id: previewWindow
    title: "SmartDock Workspace Drag Visual Preview"
    implicitWidth: 1280
    implicitHeight: 820
    color: Color.background

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(16)
      spacing: Style.space(12)

      Text {
        text: "Workspace drag visual gate — fixture preview"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        Layout.fillWidth: true
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Button {
          text: "Reset"
          bordered: true
          onClicked: root.resetFixtures()
        }
        Button {
          text: "Scope: " + (root.scopeMode === "all" ? "all monitors" : "current")
          bordered: true
          active: true
          onClicked: {
            root.cancelActiveGesture()
            root.scopeMode = root.scopeMode === "all" ? "current-monitor" : "all"
          }
        }
        Button {
          text: root.emptyDestinationScenario ? "Baseline destination" : "Empty destination"
          bordered: true
          onClicked: {
            root.emptyDestinationScenario = !root.emptyDestinationScenario
            root.overflowScenario = false
            root.applyScenario()
          }
        }
        Button {
          text: root.overflowScenario ? "Baseline width" : "Overflow"
          bordered: true
          onClicked: {
            root.overflowScenario = !root.overflowScenario
            root.emptyDestinationScenario = false
            root.applyScenario()
          }
        }
        Button {
          text: "Pinned Work stays rejected"
          bordered: true
          enabled: false
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(16)

        Toggle {
          Layout.fillWidth: true
          label: "Animations"
          description: "260 ms layout easing when enabled"
          checked: root.animationsEnabled
          onClicked: {
            root.cancelActiveGesture()
            root.animationsEnabled = !root.animationsEnabled
          }
        }
        Toggle {
          Layout.fillWidth: true
          label: "Destination auto-hide"
          description: "Reveal strip must open Monitor B"
          checked: root.autoHideEnabled
          onClicked: {
            root.cancelActiveGesture()
            root.autoHideEnabled = !root.autoHideEnabled
            dockB.dragRevealed = false
          }
        }
      }

      RowLayout {
        id: docksRow
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.space(16)

        PreviewDock {
          id: dockA
          Layout.fillWidth: true
          Layout.fillHeight: true
          monitorIdentity: "id:0"
          monitorLabel: "Simulated Monitor A"
          presentation: root.presentation
          committedFixtures: root.committedFixtures
          dragController: dragController
          scopeMode: root.scopeMode
          focusedMonitor: "id:0"
          animationsEnabled: root.animationsEnabled
          autoHideEnabled: false
        }

        PreviewDock {
          id: dockB
          Layout.fillWidth: true
          Layout.fillHeight: true
          monitorIdentity: "id:1"
          monitorLabel: "Simulated Monitor B"
          presentation: root.presentation
          committedFixtures: root.committedFixtures
          dragController: dragController
          scopeMode: root.scopeMode
          focusedMonitor: "id:0"
          animationsEnabled: root.animationsEnabled
          autoHideEnabled: root.autoHideEnabled
        }
      }
    }

    Image {
      id: ghost
      z: 1000
      source: dragController.ghostUrl
      width: dragController.ghostSize.width
      height: dragController.ghostSize.height
      x: {
        var origin = previewWindow.contentItem
          ? previewWindow.contentItem.mapToItem(null, 0, 0) : Qt.point(0, 0)
        return dragController.pointerScene.x - dragController.grabOffset.x - origin.x
      }
      y: {
        var origin = previewWindow.contentItem
          ? previewWindow.contentItem.mapToItem(null, 0, 0) : Qt.point(0, 0)
        return dragController.pointerScene.y - dragController.grabOffset.y - origin.y
      }
      asynchronous: false
      smooth: true
      opacity: 0.96
      enabled: false
      visible: dragController.active && dragController.captureReady
        && String(dragController.ghostUrl || "") !== ""
    }

    Timer {
      interval: 0
      running: true
      repeat: false
      onTriggered: root.syncDockRegistration()
    }

    onWidthChanged: root.syncDockRegistration()
    onHeightChanged: root.syncDockRegistration()
    onClosed: Qt.quit()
  }
}
