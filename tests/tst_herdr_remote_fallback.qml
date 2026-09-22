import QtQuick
import QtTest
import "../components"

// Production fallback component, not a mirrored visual harness.
TestCase {
  id: test
  name: "HerdrRemoteFallback"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Component { id: factory; DockHerdrAgentsView {} }

  function server(id, host, session, health, transport) {
    return {
      id: id, host: host, label: host, session: session,
      transport: transport || "remote", health: health || "live",
      connectionGeneration: 1, capabilities: { focusAgent: false }
    }
  }

  function context(servers, agents, associations) {
    return {
      presentation: "expanded",
      interfaceAnimationsEnabled: true,
      presentationVisible: true,
      herdrAssociations: associations || { byWindowKey: {}, unmatchedServerIds: [] },
      data: {
        providerEpoch: "fallback-epoch", revision: 1, servers: servers, agents: agents || [],
        liveCounts: { agents: (agents || []).length, complete: true },
        completeness: { state: "complete" }
      }
    }
  }

  function findAll(node, name) {
    var found = node.objectName === name ? [node] : []
    var children = node.children || []
    for (var i = 0; i < children.length; i++)
      found = found.concat(findAll(children[i], name))
    return found
  }

  function test_default_named_and_local_labels_data() {
    return [{ tag: "narrow", width: 240 }, { tag: "wide", width: 480 }]
  }

  function test_default_named_and_local_labels(data) {
    var view = createTemporaryObject(factory, test, {
      width: data.width,
      widgetContext: context([
        server("default", "devbox", "default"),
        server("named", "devbox", "review"),
        server("other", "buildbox", "review"),
        server("local", "Local label", "review", "live", "local")
      ])
    })
    verify(view !== null)
    verify(waitForRendering(view))
    compare(view.visible, true)
    var sessions = view.rows.filter(function(row) { return row.kind === "session" })
    compare(sessions.length, 4)
    compare(sessions[0].title, "devbox")
    compare(sessions[1].title, "devbox · review")
    compare(sessions[2].title, "buildbox · review")
    compare(sessions[3].title, "Local label")
    compare(sessions[3].detail, "live")
    compare(sessions[0].detail, "No active agents")
    verify(view.implicitHeight > 0 && view.implicitHeight <= 240)
  }

  function test_reconnecting_unavailable_never_healthy_empty_or_working() {
    var view = createTemporaryObject(factory, test, {
      width: 280,
      widgetContext: context([
        server("connecting", "devbox", "review", "connecting"),
        server("unavailable", "buildbox", "default", "unavailable")
      ])
    })
    verify(view !== null)
    verify(waitForRendering(view))
    var sessions = view.rows.filter(function(row) { return row.kind === "session" })
    compare(sessions[0].detail, "Reconnecting")
    compare(sessions[1].detail, "Herdr unavailable")
    verify(view.rows.every(function(row) {
      return row.title !== "No active agents" && row.detail !== "No active agents"
        && row.status !== "working"
    }))
    verify(view.rows.every(function(row) { return !view.workingAnimationActive(view, row) }))
    compare(view.visible, true)
  }

  function test_matched_filter_and_ambiguous_fallback() {
    var remote = server("remote", "devbox", "review")
    var view = createTemporaryObject(factory, test, {
      width: 280,
      widgetContext: context([remote], [], { byWindowKey: { "window:1": "remote" }, unmatchedServerIds: [] })
    })
    verify(view !== null)
    compare(view.rows.length, 0)
    compare(view.visible, false)
    view.widgetContext = context([remote], [], { byWindowKey: {}, unmatchedServerIds: ["remote"] })
    compare(view.visible, true)
    compare(view.rows[0].title, "devbox · review")
    verify(waitForRendering(view))
  }

  function test_working_agent_survives_unsupported_focus_and_stops_with_motion_disabled() {
    var remote = server("remote", "devbox", "default")
    var agent = {
      id: "remote:1:pane", serverId: "remote", connectionGeneration: 1,
      paneId: "pane", title: "Remote worker", status: "working", agent: "codex"
    }
    var view = createTemporaryObject(factory, test, {
      width: 280, widgetContext: context([remote], [agent])
    })
    verify(view !== null)
    verify(waitForRendering(view))
    compare(view.rows[0].detail, "Live")
    compare(view.rows[0].focusAgentSupported, false)
    compare(view.rows[1].status, "working")
    // Every delegate owns a marker, including the hidden session-row marker.
    // Exactly the working agent may animate; do not pick the first named child.
    var indicators = findAll(view, "herdr-unmatched-working-indicator")
    compare(indicators.length, view.rows.length)
    tryVerify(function() {
      return indicators.filter(function(item) { return item.active }).length === 1
    })
    var indicator = indicators.filter(function(item) { return item.active })[0]
    compare(indicator.visible, true)
    var next = context([remote], [agent])
    next.interfaceAnimationsEnabled = false
    view.widgetContext = next
    // Replacing the snapshot can recreate the delegates; inspect current items.
    tryVerify(function() {
      var current = findAll(view, "herdr-unmatched-working-indicator")
      return current.length === view.rows.length
        && current.every(function(item) { return !item.active })
    })
    compare(view.rows[1].status, "working")
  }
}
