import QtQuick
import "DockIconModel.js" as DockIconModel

// Owns which custom icon files the host watches and coalesces their change
// notifications into one reload request. The host binds one Quickshell
// FileView (preload: false, watchChanges: true) per `watchedPaths` entry and
// forwards its fileChanged signal to noteFileChanged(); FileView never reads
// the image bytes and does not report a change on creation.
QtObject {
  id: root

  property var iconOverrides: ({})
  property var windowIconOverrides: []
  property int debounceInterval: 250

  // Stable, sorted and distinct so unrelated settings reloads do not rebuild
  // the watchers: a string property only notifies when its value changes.
  readonly property string watchedPathsKey: JSON.stringify(
    root.localPaths(root.iconOverrides, root.windowIconOverrides))
  readonly property var watchedPaths: JSON.parse(root.watchedPathsKey)
  readonly property bool pending: root.debounce.running

  signal reloadRequested()

  function localPath(source) {
    // normalizeSource yields only file:/// URLs with encoded segments.
    if (typeof source !== "string" || source.indexOf("file://") !== 0) return ""
    try {
      return decodeURIComponent(source.slice(7))
    } catch (error) {
      return ""
    }
  }

  function localPaths(overrides, windowRules) {
    var seen = Object.create(null)
    var sources = []
    var normalized = DockIconModel.normalizeOverrides(overrides)
    Object.keys(normalized).forEach(function(key) { sources.push(normalized[key]) })
    DockIconModel.normalizeWindowRules(windowRules).forEach(function(rule) {
      sources.push(rule.source)
    })
    sources.forEach(function(source) {
      var path = root.localPath(source)
      if (path) seen[path] = true
    })
    return Object.keys(seen).sort()
  }

  // Editors often write, truncate and rename in quick succession; each event
  // restarts the timer so one burst yields one renderer revision.
  function noteFileChanged() {
    root.debounce.restart()
  }

  property Timer debounce: Timer {
    interval: root.debounceInterval
    repeat: false
    onTriggered: root.reloadRequested()
  }
}
