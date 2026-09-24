import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../components" as Components

ShellRoot {
  PanelWindow {
    id: stage

    visible: true
    implicitWidth: 700
    implicitHeight: 700
    color: "#0b0e1a"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors {
      top: true
      left: true
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_M) {
          menu.open()
          event.accepted = true
        }
      }
    }

    Item {
      id: anchorItem

      property string desktopId: "com.mitchellh.ghostty"
      property var entry: ({ name: "Ghostty" })
      property bool pinStripOwned: false
      property var browserProfileService: null
      property string browserProfileKey: ""
      property string previewHerdrLabel: "worktree-herdr-dock"
      property var previewAgents: [
        { id: "blocked", serverId: "local", status: "blocked",
          title: "Execute sidebar layout fix…", agent: "codex",
          focusAgentSupported: true, toplevel: stage },
        { id: "working", serverId: "local", status: "working",
          title: "Sidebar presentation design", agent: "claude",
          focusAgentSupported: true, toplevel: stage },
        { id: "done", serverId: "local", status: "done",
          title: "Claude Code", agent: "claude",
          focusAgentSupported: true, toplevel: stage },
        { id: "remote", serverId: "remote", status: "idle",
          title: "Remote session agent", agent: "claude",
          focusAgentSupported: false, toplevel: stage }
      ]

      width: 52
      height: 52
      x: Math.round((stage.width - width) / 2)
      y: stage.height - 90

      Rectangle {
        anchors.fill: parent
        radius: 12
        color: "#161a28"
        border.width: 1
        border.color: "#3b4261"
      }

      Text {
        anchors.centerIn: parent
        text: ">_"
        color: "#7aa2f7"
        font.pixelSize: 18
        font.bold: true
      }

      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: menu.open()
      }
    }

    QtObject {
      id: windowActions

      property var minimizedOriginsSnapshot: ({})
      function addressFor() { return "" }
      function handleFor() { return null }
      function isMinimized() { return false }
      function windowState() { return ({}) }
      function currentToplevels() { return [] }
    }

    QtObject {
      id: herdrAgentActions

      function captureAgentTarget(toplevel, agent) {
        return agent.focusAgentSupported === true
          ? { toplevel: toplevel, agentId: agent.id } : null
      }
      function activateHerdrTarget() { return true }
    }

    Components.DockContextMenu {
      id: menu

      anchorItem: anchorItem
      position: "bottom"
      autoHide: false
      pinnedItem: true
      runningToplevels: []
      windowActions: windowActions
      herdrAgentActions: herdrAgentActions
      interfaceAnimationsEnabled: false
    }
  }
}
