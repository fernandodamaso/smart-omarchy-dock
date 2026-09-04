import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// FDM-816 geometry-freshness research probe. Never imported by production QML.
// Mode is selected with the FDM816_MODE environment variable:
//
// - "oneshot" (default): explicit-refresh fixture snapshot. Refreshes before
//   logging, so its output is explicit-refresh evidence only and MUST NOT be
//   used to claim passive freshness.
// - "passive": bounded live logger. NEVER calls Hyprland.refresh*(); it only
//   records raw events and model changes as delivered by the protocol.
// - "centralized": bounded live logger with ONE host-equivalent coalesced
//   refresh per event burst (debounced). All refresh work stays in the single
//   performCentralizedRefresh() function; there are no per-screen pollers.
//
// Duration is bounded with FDM816_DURATION_S (seconds, clamped to 1..120).
// The capture script additionally kills the probe with `timeout`.
ShellRoot {
  id: root

  readonly property string mode: Quickshell.env("FDM816_MODE") || "oneshot"
  readonly property int durationS: {
    var parsed = parseInt(Quickshell.env("FDM816_DURATION_S") || "20", 10)
    if (isNaN(parsed))
      parsed = 20
    return Math.min(120, Math.max(1, parsed))
  }
  readonly property string targetAddress: Quickshell.env("FDM816_TARGET") || ""

  property int refreshCount: 0
  property int eventCount: 0
  property bool done: false
  property bool refreshPending: false
  property bool refreshInFlight: false
  property bool refreshQueued: false
  property var refreshRequestedMs: 0
  property var refreshCompletedMs: 0

  function waylandToplevel(value) {
    return {
      appId: value ? value.appId : undefined,
      title: value ? value.title : undefined,
      activated: value ? value.activated : undefined,
      maximized: value ? value.maximized : undefined,
      fullscreen: value ? value.fullscreen : undefined,
      minimized: value ? value.minimized : undefined
    }
  }

  function hyprToplevel(value) {
    var workspace = value && value.workspace
    return {
      address: value ? value.address : undefined,
      workspace: workspace ? { id: workspace.id, name: workspace.name } : null,
      wayland: value && value.wayland ? waylandToplevel(value.wayland) : null,
      lastIpcObject: value && value.lastIpcObject ? value.lastIpcObject : null
    }
  }

  function hyprObject(value) {
    return {
      id: value ? value.id : undefined,
      name: value ? value.name : undefined,
      lastIpcObject: value && value.lastIpcObject ? value.lastIpcObject : null
    }
  }

  function values(model) {
    return model && model.values ? model.values : []
  }

  function targetLastIpc(toplevels) {
    if (!root.targetAddress)
      return null
    // Hyprland toplevel addresses may drop the "0x" prefix in Quickshell.
    var wanted = root.targetAddress.replace(/^0x/, "")
    for (var i = 0; i < toplevels.length; i++) {
      var address = toplevels[i] ? toplevels[i].address : ""
      if (address && address.replace(/^0x/, "") === wanted)
        return toplevels[i].lastIpcObject ? toplevels[i].lastIpcObject : null
    }
    return null
  }

  function snapshot(trigger) {
    var wayland = values(ToplevelManager.toplevels)
    var hyprToplevels = values(Hyprland.toplevels)
    var mapped = hyprToplevels.map(root.hyprToplevel)
    return {
      mode: root.mode,
      tMs: Date.now(),
      trigger: trigger,
      targetAddress: root.targetAddress,
      targetLastIpc: root.targetLastIpc(mapped),
      activeToplevel: ToplevelManager.activeToplevel
        ? root.waylandToplevel(ToplevelManager.activeToplevel) : null,
      waylandToplevels: wayland.map(root.waylandToplevel),
      hyprlandToplevels: mapped,
      hyprlandMonitors: values(Hyprland.monitors).map(root.hyprObject),
      hyprlandWorkspaces: values(Hyprland.workspaces).map(root.hyprObject),
      refreshCount: root.refreshCount,
      refreshRequestedMs: root.refreshRequestedMs,
      refreshCompletedMs: root.refreshCompletedMs
    }
  }

  function logRecord(trigger) {
    if (root.done || (root.mode !== "passive" && root.mode !== "centralized"))
      return
    root.eventCount++
    console.log("FDM816_MODEL " + JSON.stringify(root.snapshot(trigger)))
  }

  // Single host-owned coalesced refresh. This is the ONLY place that performs
  // refresh work in centralized mode; passive mode never reaches it.
  function performCentralizedRefresh() {
    if (root.mode !== "centralized" || root.done || root.refreshInFlight)
      return
    root.refreshPending = false
    root.refreshInFlight = true
    root.refreshRequestedMs = Date.now()
    root.refreshCompletedMs = 0
    root.refreshCount++
    root.logRecord("centralized-refresh-requested")
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    centralizedCompletion.restart()
  }

  function completeCentralizedRefresh(source) {
    if (!root.refreshInFlight)
      return
    root.refreshCompletedMs = Date.now()
    root.refreshInFlight = false
    root.logRecord("centralized-refresh-complete:" + source)
    if (root.refreshQueued && !root.done) {
      root.refreshQueued = false
      root.refreshPending = true
      centralizedDebounce.restart()
    }
  }

  function noteModelChange(source) {
    if (root.mode === "centralized" && root.refreshInFlight) {
      root.completeCentralizedRefresh("model:" + source)
      return
    }
    root.logRecord("model:" + source)
  }

  function centralizedEventIsRelevant(name) {
    var normalized = (name || "").replace(/v2$/, "")
    return [
      "openwindow", "closewindow", "movewindow", "changefloatingmode",
      "fullscreen", "workspace", "focusedmon", "activespecial",
      "createworkspace", "destroyworkspace", "moveworkspace",
      "monitoradded", "monitorremoved", "configreloaded"
    ].indexOf(normalized) !== -1
  }

  function requestCentralizedRefresh() {
    if (root.mode !== "centralized" || root.done)
      return
    if (root.refreshInFlight) {
      root.refreshQueued = true
      return
    }
    root.refreshPending = true
    centralizedDebounce.restart()
  }

  Component.onCompleted: {
    // The one-shot fixture snapshot refreshes before logging: explicit-refresh
    // evidence only, never passive-freshness evidence.
    if (root.mode === "oneshot" || root.mode === "") {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()
    } else {
      // Passive and centralized modes observe protocol/model updates only.
      // No Hyprland.refresh*() call happens here by design.
      stopTimer.interval = root.durationS * 1000
      stopTimer.running = true
      root.logRecord("logger-start")
    }
  }

  Timer {
    id: centralizedDebounce
    interval: 150
    running: false
    repeat: false
    onTriggered: root.performCentralizedRefresh()
  }

  Timer {
    id: centralizedCompletion
    interval: 0
    running: false
    repeat: false
    onTriggered: root.completeCentralizedRefresh("calls-returned")
  }

  Timer {
    id: stopTimer
    interval: 20000
    running: false
    repeat: false
    onTriggered: {
      root.done = true
      console.log("FDM816_MODEL_DONE " + JSON.stringify({
        mode: root.mode,
        tMs: Date.now(),
        refreshCount: root.refreshCount,
        eventCount: root.eventCount,
        reason: "duration-elapsed"
      }))
      Qt.quit()
    }
  }

  Timer {
    id: oneshotTimer
    interval: 400
    running: root.mode === "oneshot" || root.mode === ""
    repeat: false
    onTriggered: {
      var wayland = root.values(ToplevelManager.toplevels)
      var hyprToplevels = root.values(Hyprland.toplevels)
      var hyprMonitors = root.values(Hyprland.monitors)
      var hyprWorkspaces = root.values(Hyprland.workspaces)
      var fixture = {
        mode: "oneshot-explicit-refresh",
        explicitRefresh: true,
        timestampMs: Date.now(),
        activeToplevel: ToplevelManager.activeToplevel
          ? root.waylandToplevel(ToplevelManager.activeToplevel) : null,
        waylandToplevels: wayland.map(root.waylandToplevel),
        hyprlandToplevels: hyprToplevels.map(root.hyprToplevel),
        hyprlandMonitors: hyprMonitors.map(root.hyprObject),
        hyprlandWorkspaces: hyprWorkspaces.map(root.hyprObject)
      }
      console.log("FDM816_FIXTURE " + JSON.stringify(fixture))
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? event.name : ""
      root.logRecord("rawevent:" + name)
      if (root.centralizedEventIsRelevant(name))
        root.requestCentralizedRefresh()
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      root.noteModelChange("toplevels")
    }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() {
      root.noteModelChange("workspaces")
    }
  }

  Connections {
    target: Hyprland.monitors
    function onValuesChanged() {
      root.noteModelChange("monitors")
    }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      root.logRecord("wayland:active-toplevel")
    }
  }
}
