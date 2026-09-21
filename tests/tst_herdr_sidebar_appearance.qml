import QtQuick
import QtTest
import "../components"
import "../components/DockSidebarInteractionModel.js" as InteractionModel
import "../components/DockHerdrModel.js" as HerdrModel

// Production-faithful Herdr compact chrome harness.
//
// Blocker: host qmltestrunner cannot load components/DockSidebarRow.qml because
// `import Quickshell.Widgets` requires native plugin `quickshell-widgetsplugin`
// (system qmldir linktarget), which is unavailable outside a Quickshell host.
// Live/isolated Quickshell validation (checkpoint C) remains coordinator-owned.
//
// This harness mirrors production layout equations byte-for-byte:
// - InteractionModel.sidebarTreeIconX (24px depthStep)
// - parent label after 18px icon + Style-equivalent 8px gap
// - workspace-card right inset in fold/counter chrome
// - herdrCompactLabelWidths for name reservation
// - right-anchored full-width counters (no clip)
TestCase {
  id: test
  name: "HerdrSidebarAppearance"
  when: windowShown
  visible: true
  width: 480
  height: 400

  property int herdrToggleCount: 0
  property int acquireCount: 0
  property int subscriptionCount: 0

  function findByName(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; ++i) {
      var hit = findByName(kids[i], name)
      if (hit) return hit
    }
    return null
  }

  function counterDelegates(counters) {
    var out = []
    if (!counters || !counters.children) return out
    for (var i = 0; i < counters.children.length; ++i) {
      var child = counters.children[i]
      if (child && child.objectName === "sidebar-herdr-counter")
        out.push(child)
    }
    return out
  }

  Component {
    id: chromeFactory
    Item {
      id: chrome
      // Match DockSidebarRow.workspaceCardInset default Style.space(5) ≈ 10 in tests
      // when viewport supplies 10; production helper uses the numeric inset.
      property real workspaceCardInset: 10
      property bool insideWorkspaceCard: true
      property bool forceStateIcons: true
      property bool interfaceAnimationsEnabled: true
      property bool animationEligible: true
      property bool herdrFolded: false
      property var herdrStatusCounters: []
      property string liveTitle: "Herdr"
      property string agentKindLabel: ""
      property var agentStatus: ""
      property bool agentMode: false
      property int treeDepth: 2
      property real iconSize: 18
      property real gap: 8
      width: 240
      height: 40
      visible: true

      readonly property real padding: 8
      readonly property real artX: InteractionModel.sidebarTreeIconX(
        workspaceCardInset, Math.max(1, treeDepth))
      readonly property real labelX: agentMode
        ? artX + 14 + gap
        : artX + iconSize + gap
      // Production herdrFold rightMargin = card inset (+ tabs); no left padding.
      readonly property real herdrRightChromeWidth: {
        var w = insideWorkspaceCard ? workspaceCardInset : 0
        if (!agentMode) w += fold.width
        return w
      }
      readonly property real herdrFoldLeft: Math.max(0, width - herdrRightChromeWidth)
      readonly property bool herdrCountersVisible: !agentMode && herdrStatusCounters.length > 0
      readonly property real herdrCountersNaturalWidth: herdrCountersVisible
        ? counters.implicitWidth : 0
      readonly property bool herdrStateStripFits: {
        if (!herdrCountersVisible || !forceStateIcons) return true
        var stripW = 12 + 4 + 12
        var labelRight = labelX + label.width
        var countersLeft = herdrFoldLeft - herdrCountersNaturalWidth
        return labelRight + gap + stripW + gap <= countersLeft
      }
      readonly property string accessibleLabel: {
        if (agentMode) {
          return "Herdr agent: " + liveTitle
            + (agentKindLabel ? " · " + agentKindLabel : "")
            + " · " + HerdrModel.statusLabel(agentStatus)
        }
        var text = "Herdr"
        for (var i = 0; i < herdrStatusCounters.length; ++i) {
          var c = herdrStatusCounters[i]
          text += " · " + HerdrModel.statusLabel(c.status) + " " + String(c.count)
        }
        return text
      }

      // No acquire/subscribe APIs — harness must not invent leases.
      function acquire() { test.acquireCount += 1 }
      function subscribe() { test.subscriptionCount += 1 }

      Item {
        id: content
        anchors.fill: parent
        visible: true

        // Production window artwork slot (18×18) for parent rows.
        Rectangle {
          id: artwork
          visible: !chrome.agentMode
          x: chrome.artX
          width: chrome.iconSize
          height: chrome.iconSize
          anchors.verticalCenter: parent.verticalCenter
          color: "#666"
        }

        Text {
          id: label
          objectName: "sidebar-label"
          visible: true
          anchors.verticalCenter: parent.verticalCenter
          x: chrome.labelX
          width: {
            var available = Math.max(0, content.width - x - chrome.herdrRightChromeWidth)
            return InteractionModel.herdrCompactLabelWidths({
              availableWidth: available,
              kindWidth: kindLabel.visible ? kindLabel.implicitWidth : 0,
              countersWidth: counters.visible ? counters.implicitWidth : 0,
              controlsWidth: 0,
              gap: chrome.gap
            }).nameWidth
          }
          textFormat: Text.PlainText
          text: chrome.liveTitle
          elide: Text.ElideRight
          wrapMode: Text.NoWrap
          maximumLineCount: 1
          font.pixelSize: 12
        }

        Row {
          id: stateStrip
          objectName: "sidebar-state-strip"
          visible: !chrome.agentMode && chrome.forceStateIcons && chrome.herdrStateStripFits
          spacing: 4
          anchors.verticalCenter: parent.verticalCenter
          x: label.x + Math.min(label.implicitWidth, label.width) + chrome.gap
          height: 14
          Repeater {
            model: stateStrip.visible ? 2 : 0
            Rectangle { width: 12; height: 12; color: "#888" }
          }
        }

        Text {
          id: kindLabel
          objectName: "sidebar-herdr-kind"
          visible: chrome.agentMode && chrome.agentKindLabel !== ""
          anchors.verticalCenter: parent.verticalCenter
          x: label.x + Math.min(label.implicitWidth, label.width) + chrome.gap
          width: Math.min(implicitWidth, Math.max(0,
            content.width - x - chrome.herdrRightChromeWidth - chrome.padding))
          textFormat: Text.PlainText
          text: chrome.agentKindLabel
          font.pixelSize: 11
          color: "#888"
        }

        Row {
          id: counters
          objectName: "sidebar-herdr-counters"
          visible: chrome.herdrCountersVisible
          spacing: 4
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: fold.left
          height: 14
          // Natural width only — never clip nonzero buckets.
          Repeater {
            model: chrome.herdrStatusCounters
            delegate: Item {
              id: counterItem
              objectName: "sidebar-herdr-counter"
              required property var modelData
              readonly property string normalizedStatus: HerdrModel.normalizeStatus(modelData.status)
              readonly property bool working: normalizedStatus === "working"
              readonly property bool workingAnimationActive: working
                && chrome.interfaceAnimationsEnabled && chrome.animationEligible
              width: counterRow.width
              height: counters.height
              Row {
                id: counterRow
                spacing: 2
                height: parent.height
                Item {
                  objectName: "sidebar-herdr-counter-marker"
                  width: counterItem.working ? 10 : 7
                  height: counterItem.working ? 10 : 7
                  anchors.verticalCenter: parent.verticalCenter
                  DockHerdrWorkingIndicator {
                    objectName: "sidebar-herdr-counter-working-indicator"
                    anchors.centerIn: parent
                    visible: counterItem.workingAnimationActive
                    active: visible
                    tint: "#7aa2f7"
                  }
                  Rectangle {
                    objectName: "sidebar-herdr-counter-static-dot"
                    visible: !counterItem.workingAnimationActive
                    anchors.centerIn: parent
                    width: 7; height: 7; radius: 4
                    color: counterItem.modelData.status === "unknown" ? "transparent" : "#7aa2f7"
                    border.width: counterItem.modelData.status === "unknown" ? 1 : 0
                    border.color: "#888"
                  }
                }
                Text {
                  objectName: "sidebar-herdr-counter-text"
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(counterItem.modelData.count)
                  textFormat: Text.PlainText
                  font.pixelSize: 10
                }
              }
            }
          }
        }

        Rectangle {
          id: fold
          objectName: "sidebar-herdr-fold"
          visible: !chrome.agentMode
          anchors.right: parent.right
          anchors.rightMargin: chrome.insideWorkspaceCard ? chrome.workspaceCardInset : 0
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(content.height, 28)
          height: content.height
          color: "#444"
          MouseArea {
            id: foldHit
            objectName: "sidebar-herdr-fold-hit"
            anchors.fill: parent
            onClicked: {
              chrome.herdrFolded = !chrome.herdrFolded
              test.herdrToggleCount += 1
            }
          }
        }
      }
    }
  }

  function assertAllCountersPainted(chrome, counters, fold) {
    verify(counters.visible)
    verify(fold.visible)
    compare(counters.width, counters.implicitWidth)
    verify(counters.x + counters.width <= fold.x + 0.5)
    var delegates = counterDelegates(counters)
    compare(delegates.length, chrome.herdrStatusCounters.length)
    for (var i = 0; i < delegates.length; ++i) {
      var d = delegates[i]
      verify(d.visible)
      verify(d.x >= 0)
      verify(d.x + d.width <= counters.width + 0.5)
      var text = findByName(d, "sidebar-herdr-counter-text")
      verify(text !== null)
      compare(text.text, String(chrome.herdrStatusCounters[i].count))
      verify(text.contentWidth <= text.width + 0.5 || text.width >= text.contentWidth)
    }
  }

  function test_narrow_parent_all_counters_visible_expanded_and_folded() {
    test.herdrToggleCount = 0
    test.acquireCount = 0
    test.subscriptionCount = 0
    var chrome = createTemporaryObject(chromeFactory, test, {
      width: 240,
      treeDepth: 2,
      insideWorkspaceCard: true,
      workspaceCardInset: 10,
      forceStateIcons: true,
      visible: true,
      herdrStatusCounters: [
        { status: "working", count: 12 },
        { status: "idle", count: 3 },
        { status: "done", count: 1 },
        { status: "blocked", count: 10 },
        { status: "unknown", count: 2 }
      ]
    })
    verify(chrome !== null)
    verify(chrome.visible)
    waitForRendering(chrome)
    var counters = findByName(chrome, "sidebar-herdr-counters")
    var fold = findByName(chrome, "sidebar-herdr-fold")
    var label = findByName(chrome, "sidebar-label")
    var hit = findByName(chrome, "sidebar-herdr-fold-hit")
    verify(counters !== null && fold !== null && label !== null && hit !== null)
    verify(counters.visible && fold.visible)
    compare(label.textFormat, Text.PlainText)
    // Production depth-2 icon x with inset 10: guide0=30, artX=30+12+24=66.
    compare(Math.round(chrome.artX), 66)
    assertAllCountersPainted(chrome, counters, fold)

    // Real click on the chevron MouseArea (not a local helper).
    mouseClick(hit, hit.width / 2, hit.height / 2)
    compare(test.herdrToggleCount, 1)
    verify(chrome.herdrFolded)
    // Counts remain fully visible while folded.
    assertAllCountersPainted(chrome, counters, fold)
    compare(test.acquireCount, 0)
    compare(test.subscriptionCount, 0)
  }

  function test_working_counter_reserves_slot_and_static_fallback() {
    var chrome = createTemporaryObject(chromeFactory, test, {
      width: 240,
      visible: true,
      interfaceAnimationsEnabled: false,
      animationEligible: true,
      herdrStatusCounters: [{ status: "working", count: 2 }]
    })
    verify(chrome !== null)
    waitForRendering(chrome)
    var counters = findByName(chrome, "sidebar-herdr-counters")
    var delegates = counterDelegates(counters)
    compare(delegates.length, 1)
    var marker = findByName(delegates[0], "sidebar-herdr-counter-marker")
    var indicator = findByName(delegates[0], "sidebar-herdr-counter-working-indicator")
    var staticDot = findByName(delegates[0], "sidebar-herdr-counter-static-dot")
    verify(marker !== null && indicator !== null && staticDot !== null)
    compare(marker.width, 10)
    compare(staticDot.visible, true)
    compare(indicator.visible, false)
    verify(chrome.accessibleLabel.indexOf("Working 2") >= 0)

    chrome.interfaceAnimationsEnabled = true
    wait(0)
    compare(indicator.visible, true)
    compare(indicator.active, true)
    compare(staticDot.visible, false)

    chrome.animationEligible = false
    wait(0)
    compare(indicator.visible, false)
    compare(staticDot.visible, true)
  }

  function test_agent_plain_text_kind_and_unknown_status() {
    var chrome = createTemporaryObject(chromeFactory, test, {
      width: 240,
      visible: true,
      agentMode: true,
      treeDepth: 3,
      liveTitle: "<b>Long markup-like agent name that must stay plain text</b>",
      agentKindLabel: "",
      agentStatus: null
    })
    verify(chrome !== null)
    verify(chrome.visible)
    waitForRendering(chrome)
    var label = findByName(chrome, "sidebar-label")
    verify(label !== null)
    verify(label.visible)
    compare(label.textFormat, Text.PlainText)
    compare(label.text, "<b>Long markup-like agent name that must stay plain text</b>")
    verify(chrome.accessibleLabel.indexOf("Unknown") >= 0)
    var kind = findByName(chrome, "sidebar-herdr-kind")
    verify(kind === null || kind.visible === false)
  }

  function test_agent_kind_capitalization_bounds() {
    var chrome = createTemporaryObject(chromeFactory, test, {
      width: 240,
      visible: true,
      agentMode: true,
      treeDepth: 3,
      liveTitle: "<i>Codex Review with a very long plain-text title</i>",
      agentKindLabel: HerdrModel.displayAgentKind("codex"),
      agentStatus: "working"
    })
    verify(chrome !== null)
    waitForRendering(chrome)
    var label = findByName(chrome, "sidebar-label")
    var kind = findByName(chrome, "sidebar-herdr-kind")
    verify(label !== null && kind !== null)
    compare(label.textFormat, Text.PlainText)
    compare(kind.textFormat, Text.PlainText)
    compare(kind.text, "Codex")
    verify(chrome.accessibleLabel.indexOf("Working") >= 0)
    verify(kind.x + kind.width <= chrome.width + 0.5)
    verify(label.x + label.width <= kind.x + 0.5 || label.width === 0)
  }
}
