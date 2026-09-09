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
  property var groups: [
    { identity: "group-a", items: [{ identity: "group-a/app" }] },
    { identity: "group-b", items: [] }
  ]

  Components.DockPresentationModel {
    id: presentation
    sourceItems: root.sourceItems
    keyProperty: "identity"
    animationsEnabled: true
  }

  Components.DockPresentationModel {
    id: groupPresentation
    sourceItems: root.groups
    keyProperty: "identity"
    animationsEnabled: true
  }

  Item {
    visible: false

    Repeater {
      id: groupDelegates
      model: groupPresentation.model
      delegate: Item {
        required property var modelData
        readonly property var appModel: appPresentation
        readonly property var appRepeater: appDelegates

        Components.DockPresentationModel {
          id: appPresentation
          sourceItems: modelData.item.items
          keyProperty: "identity"
          animationsEnabled: true
        }

        Repeater {
          id: appDelegates
          model: appPresentation.model
          delegate: Components.DockAnimatedSlot {
            required property var modelData
            present: modelData.present
            animateEntrance: modelData.animateEntrance
            animationsEnabled: true
            exitRevision: modelData.exitRevision
            onExitFinished: revision => appPresentation.completeRemoval(modelData.token, revision)
            naturalWidth: 20
            naturalHeight: 20
          }
        }
      }
    }
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
      root.groups = [
        { identity: "group-a", items: [] },
        { identity: "group-b", items: [{ identity: "group-b/app" }] }
      ]
      moveCheck.start()
      root.stage = 1
      settle.start()
    }
  }

  Timer {
    id: settle
    interval: 500
    repeat: false
    onTriggered: {
      if (presentation.entries.length !== 2 || delegates.count !== 2)
        throw new Error("exit presentation was not removed after animation")
      if (delegates.itemAt(0) !== root.firstDelegate)
        throw new Error("ScriptModel recreated an unchanged delegate")
      if (groupDelegates.count !== 2 || groupDelegates.itemAt(0).appModel.entries.length !== 0
          || groupDelegates.itemAt(1).appModel.entries.length !== 1)
        throw new Error("nested app presentation did not retain the moved window")
      if (groupDelegates.itemAt(1).appRepeater.itemAt(0).opacity !== 1)
        throw new Error("nested app arrival did not finish")
      presentation.animationsEnabled = false
      root.sourceItems = []
      if (presentation.entries.length !== 0 || delegates.count !== 0)
        throw new Error("disabling animations did not settle removals")
      console.log("interface-animations: PASS")
      Qt.quit()
    }
  }

  Timer {
    id: moveCheck
    interval: 40
    repeat: false
    onTriggered: {
      var sourceSlot = groupDelegates.itemAt(0).appRepeater.itemAt(0)
      var destinationSlot = groupDelegates.itemAt(1).appRepeater.itemAt(0)
      if (!sourceSlot || sourceSlot.width <= 0 || sourceSlot.width >= 20)
        throw new Error("nested app departure was already collapsed")
      if (!destinationSlot || destinationSlot.opacity <= 0 || destinationSlot.opacity >= 1)
        throw new Error("nested app arrival skipped its entrance")
      console.log("interface-animations: mid-move", sourceSlot.width, destinationSlot.opacity)
      root.groups = [
        { identity: "group-a", items: [] },
        { identity: "group-b", items: [{ identity: "group-b/app" }] }
      ]
      if (groupDelegates.itemAt(0).appRepeater.itemAt(0) !== sourceSlot)
        throw new Error("refresh destroyed the outgoing delegate")
    }
  }
}
