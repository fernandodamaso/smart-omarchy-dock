import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "InterfaceAnimations"
  when: windowShown
  visible: true
  width: 400
  height: 200

  Component {
    id: slotComponent
    Components.DockAnimatedSlot {
      naturalWidth: 40
      naturalHeight: 20
      trailingGap: 8
      Rectangle { width: 40; height: 20 }
    }
  }

  function test_slotEntranceAndExit() {
    var slot = createTemporaryObject(slotComponent, testCase, {
      present: true, animateEntrance: true, animationsEnabled: true
    })
    tryCompare(slot, "opacityProgress", 1, 500)
    tryCompare(slot, "occupiedProgress", 1, 500)
    slot.exitRevision = 4
    slot.present = false
    tryCompare(slot, "opacityProgress", 0, 500)
    tryCompare(slot, "occupiedProgress", 0, 500)
    tryCompare(slot, "width", 0, 500)
  }

  function test_slotCreatedForExitAnimatesOut() {
    var slot = createTemporaryObject(slotComponent, testCase, {
      present: false, exitRevision: 1, animationsEnabled: true
    })
    wait(40)
    verify(slot.width > 0)
    tryCompare(slot, "width", 0, 500)
    compare(slot.opacityProgress, 0)
  }

  function test_slotDisablingMotionSettlesImmediately() {
    var slot = createTemporaryObject(slotComponent, testCase, {
      present: true, animateEntrance: true, animationsEnabled: true
    })
    slot.animationsEnabled = false
    compare(slot.opacityProgress, 1)
    compare(slot.occupiedProgress, 1)
    slot.present = false
    compare(slot.opacityProgress, 0)
    compare(slot.occupiedProgress, 0)
    compare(slot.width, 0)
  }

}
