import QtQuick
import QtTest
import "../components"
import "../components/DockHerdrModel.js" as HerdrModel

TestCase {
  id: testCase
  name: "HerdrDockIndicators"
  when: windowShown
  visible: true
  width: 420
  height: 320
  property bool imageSaved: false

  function findByName(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var children = node.children || []
    for (var i = 0; i < children.length; ++i) {
      var found = findByName(children[i], name)
      if (found) return found
    }
    return null
  }

  function summary(statuses) {
    var counters = ({ blocked: 0, working: 0, done: 0 })
    statuses.forEach(function(status) {
      if (counters[status] !== undefined) counters[status]++
    })
    var rows = []
    ;["blocked", "working", "done"].forEach(function(status) {
      if (counters[status]) rows.push({ status: status, count: counters[status] })
    })
    var indicator = counters.blocked ? "blocked"
      : counters.working ? "working" : counters.done ? "done" : ""
    return {
      count: statuses.length,
      indicatorStatus: indicator,
      counters: rows,
      rows: [],
      blockedTransitionRevision: 0
    }
  }

  Component {
    id: windowFactory
    QtObject { property string title: "Terminal" }
  }

  Component {
    id: dockItemFactory
    Item {
      id: indicator
      property var runningToplevels: []
      property var herdrSummary: summary([])
      property string attentionBadge: "none"
      property bool herdrReplacesAttention: false
      readonly property int runningCount: runningToplevels.length
      readonly property int herdrAgentCount: Number(herdrSummary.count || 0)
      width: 74
      height: 74
      visible: true

      function accessibleLabel() {
        var name = "org.test.Terminal"
        if (runningCount > 0)
          name += " · " + runningCount + (runningCount === 1 ? " window" : " windows")
        if (herdrAgentCount > 0)
          name += " · " + herdrAgentCount + (herdrAgentCount === 1 ? " agent" : " agents")
        var counters = herdrSummary.counters || []
        for (var i = 0; i < counters.length; ++i) {
          if (counters[i].status === "blocked")
            name += " · " + counters[i].count + " needs input"
          else if (counters[i].status === "working")
            name += " · " + counters[i].count + " working"
          else if (counters[i].status === "done")
            name += " · " + counters[i].count + " done"
        }
        return name
      }

      Accessible.role: Accessible.Button
      Accessible.name: accessibleLabel()

      Item {
        id: icon
        width: 52
        height: 52
        anchors.centerIn: parent

        Rectangle {
          id: countBadge
          objectName: "dock-corner-count-badge"
          visible: indicator.runningCount > 1
            || indicator.runningCount <= 1 && indicator.herdrAgentCount >= 2
          width: Math.max(16, countText.implicitWidth + 8)
          height: 16
          radius: height / 2
          x: icon.width - width + 5
          y: -5
          color: "#7d8cff"

          Text {
            id: countText
            objectName: "dock-corner-count-text"
            anchors.centerIn: parent
            readonly property int displayedCount: indicator.runningCount > 1
              ? indicator.runningCount : indicator.herdrAgentCount
            text: displayedCount > 99 ? "99+" : String(displayedCount)
          }
        }

        DockApplicationBadge {
          objectName: "dock-attention-badge"
          severity: indicator.herdrReplacesAttention ? "none" : indicator.attentionBadge
          x: icon.width - width + 3
          y: countBadge.visible ? 13 : -3
        }

        DockHerdrStatusMark {
          objectName: "dock-herdr-status-mark"
          status: indicator.herdrSummary.indicatorStatus
          size: 24
          animationsEnabled: false
          x: icon.width - width + 7
          y: icon.height - height + 7
        }
      }
    }
  }

  Component {
    id: bridgeSceneFactory
    Item {
      id: scene
      property alias service: service
      property alias bridge: bridge

      QtObject {
        id: service
        property string sourceEpoch: "epoch-1"
        property int sourceRevision: 0
        property bool running: true
        property int activeCount: 0
        property var publish: null
        property var writes: []

        function acquire() {
          var lease = {
            active: false,
            released: false,
            setActive: function(active, callback) {
              active = active === true
              service.publish = active ? callback : null
              if (lease.active === active) return
              lease.active = active
              service.activeCount += active ? 1 : -1
            },
            release: function() {
              if (lease.released) return
              if (lease.active) service.activeCount--
              lease.active = false
              lease.released = true
              service.publish = null
            }
          }
          return lease
        }
        function setWindowProcesses(revision, pids) {
          service.writes = service.writes.concat([{ revision: revision, pids: pids }])
          return true
        }
        function send(view) {
          if (service.publish) service.publish(view)
        }
      }

      DockHerdrWindowAgents {
        id: bridge
        herdrService: service
      }
    }
  }

  function snapshot(bridge, status, revision, health) {
    return {
      schemaVersion: 1,
      providerEpoch: "epoch-1",
      revision: revision,
      servers: [{
        id: "srv",
        health: health || "live",
        capabilities: { focusAgent: true },
        clients: [{ pid: 41, startTime: 41,
          ancestors: [{ pid: 40, startTime: 40 }] }]
      }],
      agents: [{
        id: "agent-a", serverId: "srv", connectionGeneration: 1,
        paneId: "pane-a", status: status, title: "Agent"
      }],
      windowProcesses: {
        revision: bridge.windowProcessRevision,
        identities: [{ pid: 40, startTime: 40 }]
      }
    }
  }

  function readyBridge(status) {
    var scene = createTemporaryObject(bridgeSceneFactory, testCase)
    verify(scene !== null)
    var win = createTemporaryObject(windowFactory, scene)
    scene.bridge.toplevels = [win]
    scene.bridge.hyprToplevels = [{
      wayland: win, address: "0xabc", lastIpcObject: { pid: 40 }
    }]
    scene.bridge.dockConsumerActive = true
    scene.bridge.syncHerdrWindowProcesses()
    scene.service.send({
      status: "ready", revision: 1,
      data: snapshot(scene.bridge, status || "working", 1)
    })
    tryCompare(scene.bridge, "snapshotReady", true)
    return { scene: scene, win: win }
  }

  function sendSnapshot(value, status, revision, health) {
    value.scene.service.send({
      status: "ready", revision: revision,
      data: snapshot(value.scene.bridge, status, revision, health)
    })
  }

  function test_canvasStatesAndBadgeOwnership() {
    var item = createTemporaryObject(dockItemFactory, testCase)
    verify(item !== null)
    var mark = findByName(item, "dock-herdr-status-mark")
    var badge = findByName(item, "dock-corner-count-badge")
    var badgeText = findByName(item, "dock-corner-count-text")
    verify(mark !== null)
    verify(badge !== null)

    item.herdrSummary = summary([])
    compare(mark.visible, false, "no agents has no mark")
    compare(badge.visible, false)

    item.herdrSummary = summary(["working"])
    wait(0)
    compare(mark.visible, true)
    compare(HerdrModel.statusColorRole(mark.status), "accent")
    compare(badge.visible, false)

    item.herdrSummary = summary(["blocked"])
    wait(0)
    compare(mark.visible, true)
    compare(HerdrModel.statusColorRole(mark.status), "blocked")

    item.herdrSummary = summary(["done"])
    wait(0)
    compare(mark.visible, true)
    compare(HerdrModel.statusColorRole(mark.status), "done")

    item.herdrSummary = summary(["blocked", "working", "done"])
    wait(0)
    compare(HerdrModel.statusColorRole(mark.status), "blocked")
    compare(badge.visible, true)
    compare(badgeText.text, "3")

    // A stale/reconnecting projection is deliberately an empty summary.
    item.herdrSummary = summary([])
    wait(0)
    compare(mark.visible, false)
    compare(badge.visible, false)

    var one = createTemporaryObject(windowFactory, item)
    var two = createTemporaryObject(windowFactory, item)
    item.runningToplevels = [one, two]
    item.herdrSummary = summary(["blocked", "working", "done"])
    wait(0)
    compare(badgeText.text, "2", "window count owns the corner for grouped windows")
    verify(item.Accessible.name.indexOf("2 windows · 3 agents") >= 0)
    verify(item.Accessible.name.indexOf("1 needs input") >= 0)
    verify(item.Accessible.name.indexOf("1 working") >= 0)
    verify(item.Accessible.name.indexOf("1 done") >= 0)
  }

  function test_mixedUrgencyKeepsAttentionBadge() {
    var item = createTemporaryObject(dockItemFactory, testCase)
    var attention = findByName(item, "dock-attention-badge")
    verify(attention !== null)
    item.herdrSummary = summary(["blocked"])
    item.attentionBadge = "urgent"
    item.herdrReplacesAttention = false
    wait(0)
    compare(attention.visible, true, "non-Herdr urgency remains visible")
    item.herdrReplacesAttention = true
    wait(0)
    compare(attention.visible, false, "same blocked Herdr window owns the mark")
  }

  function test_representativeVisualCapture() {
    var item = createTemporaryObject(dockItemFactory, testCase, {
      x: 160,
      y: 110,
      herdrSummary: summary(["blocked", "working", "done"])
    })
    verify(item !== null)
    wait(0)
    testCase.imageSaved = false
    item.grabToImage(function(result) {
      testCase.imageSaved = result.saveToFile("/tmp/herdr-dock-indicator.png")
    }, Qt.size(item.width * 4, item.height * 4))
    tryCompare(testCase, "imageSaved", true)
  }

  function test_completionAcknowledgmentAndFreshCompletion() {
    var value = readyBridge("working")
    sendSnapshot(value, "done", 2)
    var done = value.scene.bridge.summaryForToplevels([value.win])
    compare(done.indicatorStatus, "done")
    compare(done.counters[0].status, "done", "raw state remains done")

    value.scene.bridge.focusedToplevel = value.win
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "")
    compare(value.scene.bridge.summaryForToplevels([value.win]).counters[0].status, "done")

    // A completion received while already focused is acknowledged atomically.
    sendSnapshot(value, "working", 3)
    sendSnapshot(value, "done", 4)
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "")

    value.scene.bridge.focusedToplevel = null
    sendSnapshot(value, "working", 5)
    sendSnapshot(value, "done", 6)
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "done")
  }

  function test_eachAgentCompletionIsIndependent() {
    var value = readyBridge("working")
    sendSnapshot(value, "done", 2)
    value.scene.bridge.focusedToplevel = value.win
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "")
    value.scene.bridge.focusedToplevel = null

    var withSecond = snapshot(value.scene.bridge, "done", 3)
    withSecond.agents.push({
      id: "agent-b", serverId: "srv", connectionGeneration: 1,
      paneId: "pane-b", status: "working", title: "Second agent"
    })
    value.scene.service.send({ status: "ready", revision: 3, data: withSecond })
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "working")

    withSecond = snapshot(value.scene.bridge, "done", 4)
    withSecond.agents.push({
      id: "agent-b", serverId: "srv", connectionGeneration: 1,
      paneId: "pane-b", status: "done", title: "Second agent"
    })
    value.scene.service.send({ status: "ready", revision: 4, data: withSecond })
    var summary = value.scene.bridge.summaryForToplevels([value.win])
    compare(summary.indicatorStatus, "done",
      "another agent completion is not covered by the first acknowledgment")
    compare(summary.count, 2)
  }

  function test_gapReplayAndBlockedBounceRevision() {
    var value = readyBridge("working")
    sendSnapshot(value, "blocked", 2)
    var blocked = value.scene.bridge.summaryForToplevels([value.win])
    compare(blocked.indicatorStatus, "blocked")
    verify(blocked.blockedTransitionRevision > 0)
    var transition = blocked.blockedTransitionRevision

    value.scene.service.send({ status: "loading", revision: 3, data: null })
    compare(value.scene.bridge.summaryForToplevels([value.win]).count, 0)
    sendSnapshot(value, "blocked", 4, "connecting")
    compare(value.scene.bridge.summaryForToplevels([value.win]).count, 0,
      "reconnecting snapshots never render retained state")
    sendSnapshot(value, "blocked", 5)
    blocked = value.scene.bridge.summaryForToplevels([value.win])
    compare(blocked.blockedTransitionRevision, transition,
      "replayed blocked state does not bounce again")

    sendSnapshot(value, "working", 6)
    sendSnapshot(value, "done", 7)
    value.scene.bridge.focusedToplevel = value.win
    value.scene.service.send({ status: "loading", revision: 8, data: null })
    sendSnapshot(value, "done", 9)
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "",
      "replayed completion retains acknowledgment")
  }

  function test_replacementAndSettingOff() {
    var scene = createTemporaryObject(bridgeSceneFactory, testCase)
    compare(scene.service.activeCount, 0, "setting off takes no active lease")
    compare(scene.bridge.summaryForToplevels([]).count, 0)

    var value = readyBridge("working")
    sendSnapshot(value, "done", 2)
    compare(value.scene.bridge.summaryForToplevels([value.win]).indicatorStatus, "done")
    var replacement = createTemporaryObject(windowFactory, value.scene)
    value.scene.bridge.toplevels = [replacement]
    value.scene.bridge.hyprToplevels = [{
      wayland: replacement, address: "0xabc", lastIpcObject: { pid: 40 }
    }]
    value.scene.bridge.syncHerdrWindowProcesses()
    sendSnapshot({ scene: value.scene, win: replacement }, "done", 3)
    compare(value.scene.bridge.summaryForToplevels([replacement]).indicatorStatus, "",
      "replacement bootstrap is not a synthetic completion")
    sendSnapshot({ scene: value.scene, win: replacement }, "working", 4)
    sendSnapshot({ scene: value.scene, win: replacement }, "done", 5)
    compare(value.scene.bridge.summaryForToplevels([replacement]).indicatorStatus, "done",
      "replacement does not inherit the old window acknowledgment")
  }
}
