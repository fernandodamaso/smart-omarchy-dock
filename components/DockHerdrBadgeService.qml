pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "DockBadgeModel.js" as BadgeModel

Item {
  id: root

  property bool available: false
  property int revision: 0
  property var state: BadgeModel.herdrBadgeState([], false)
  readonly property string badgeDesktopId: "com.mitchellh.ghostty"

  visible: false
  width: 0
  height: 0

  function clearState() {
    var next = BadgeModel.herdrBadgeState([], false)
    if (!available && JSON.stringify(state) === JSON.stringify(next)) return
    available = false
    state = next
    revision++
  }

  function parseState(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (_) {
      clearState()
      return
    }

    var agents = parsed && parsed.result ? parsed.result.agents : null
    if (!Array.isArray(agents)) {
      clearState()
      return
    }

    var next = BadgeModel.herdrBadgeState(agents, true)
    if (available && JSON.stringify(state) === JSON.stringify(next)) return
    available = true
    state = next
    revision++
  }

  function refresh() {
    if (herdrProcess.running) return
    herdrProcess.running = true
  }

  function countStateFor(desktopId) {
    return BadgeModel.herdrCountStateFor(
      desktopId, badgeDesktopId, state)
  }

  function severityFor(desktopId) {
    if (BadgeModel.normalizeIdentity(desktopId)
        !== BadgeModel.normalizeIdentity(badgeDesktopId)) {
      return BadgeModel.BADGE_NONE
    }
    return state && state.severity ? state.severity : BadgeModel.BADGE_NONE
  }

  Process {
    id: herdrProcess

    command: ["timeout", "2s", "herdr", "agent", "list"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseState(text)
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) root.clearState()
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
