import QtQuick
import Quickshell
import "components" as Components

ShellRoot {
  id: root

  property var sourceItems: [
    { identity: "a", value: 1 },
    { identity: "b", value: 2 }
  ]
  property int stage: 0
  property var firstDelegate: null

  Components.DockPresentationModel {
    id: presentation
    sourceItems: root.sourceItems
    keyProperty: "identity"
    animationsEnabled: true
  }

  Item {
    width: 300
    height: 30

    Repeater {
      id: delegates
      model: presentation.model
      delegate: Components.DockAnimatedSlot {
        required property var modelData
        required property int index
        present: modelData.present
        animateEntrance: modelData.animateEntrance
        animationsEnabled: presentation.animationsEnabled
        exitRevision: modelData.exitRevision
        naturalWidth: 40
        naturalHeight: 20
        trailingGap: 4
        onExitFinished: revision => presentation.completeRemoval(
          modelData.token, revision)
        Rectangle { width: 40; height: 20 }
      }
    }
  }

  Timer {
    interval: 150
    running: true
    repeat: false
    onTriggered: {
      if (delegates.count !== 2 || presentation.entries.length !== 2)
        throw new Error("initial presentation did not create two delegates")
      root.firstDelegate = delegates.itemAt(0)
      root.sourceItems = [{ identity: "a", value: 3 }, { identity: "c", value: 4 }]
      root.stage = 1
      settle.start()
    }
  }

  Timer {
    id: settle
    interval: 260
    repeat: false
    onTriggered: {
      if (presentation.entries.length !== 3 || delegates.count !== 3)
        throw new Error("exit presentation was not retained")
      if (delegates.itemAt(0) !== root.firstDelegate)
        throw new Error("ScriptModel recreated an unchanged delegate")
      presentation.animationsEnabled = false
      root.sourceItems = []
      if (presentation.entries.length !== 0 || delegates.count !== 0)
        throw new Error("disabling animations did not settle removals")
      console.log("interface-animations: PASS")
      Qt.quit()
    }
  }
}
