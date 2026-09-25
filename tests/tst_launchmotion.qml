import QtQuick
import QtTest
import "../components" as Components

TestCase {
  id: testCase
  name: "LaunchMotion"
  when: windowShown
  visible: true
  width: 320
  height: 160

  Component {
    id: motionComponent
    Components.DockLaunchMotion {
      position: "bottom"
      animationsEnabled: true
    }
  }

  function test_orientationVectors() {
    var motion = createTemporaryObject(motionComponent, testCase)
    compare(JSON.stringify(motion.vectorFor("bottom", 6)),
      JSON.stringify({ x: 0, y: -6 }))
    compare(JSON.stringify(motion.vectorFor("top", 6)),
      JSON.stringify({ x: 0, y: 6 }))
    compare(JSON.stringify(motion.vectorFor("left", 6)),
      JSON.stringify({ x: 6, y: 0 }))
    compare(JSON.stringify(motion.vectorFor("right", 6)),
      JSON.stringify({ x: -6, y: 0 }))
  }

  function test_activeStateStartsAndStopsMotion() {
    var motion = createTemporaryObject(motionComponent, testCase)
    compare(motion.running, false)
    motion.active = true
    tryCompare(motion, "running", true, 100)
    motion.active = false
    compare(motion.running, false)
    compare(motion.xOffset, 0)
    compare(motion.yOffset, 0)
  }

  function test_disablingAnimationsStopsMotion() {
    var motion = createTemporaryObject(motionComponent, testCase, {
      active: true
    })
    tryCompare(motion, "running", true, 100)
    motion.animationsEnabled = false
    compare(motion.running, false)
    compare(motion.xOffset, 0)
    compare(motion.yOffset, 0)
  }
}
