import QtQuick
import Quickshell
import "components" as Components

ShellRoot {
  id: root

  Item { id: anchorItem }

  QtObject {
    id: windowActions

    property var minimizedOriginsSnapshot: ({})
    function handleFor() { return null }
    function isMinimized() { return false }
    function windowState() { return ({}) }
  }

  Component {
    Components.DockContextMenu {
      anchorItem: anchorItem
      position: "bottom"
      autoHide: false
      pinnedItem: false
      runningToplevels: []
      windowActions: windowActions
      controlItem: true
    }
  }

  Timer {
    interval: 50
    running: true
    onTriggered: {
      console.log("context-menu-load: PASS")
      Qt.quit()
    }
  }
}
