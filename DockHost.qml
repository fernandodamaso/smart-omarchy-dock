pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "components"
import "components/DockModel.js" as DockModel

Item {
  id: root

  required property string configPath

  property int trashItemCount: 0
  property bool trashStateKnown: false

  property var settings: ({
    iconSize: 42,
    magnification: 1.2,
    magnificationRadius: 95,
    hoverGlowEnabled: true,
    hoverGlowOpacity: 0.72,
    hoverGlowRadius: 28,
    margin: 10,
    backgroundOpacity: 0.88,
    backgroundColorEnabled: false,
    backgroundColor: "",
    borderColorEnabled: false,
    borderColor: "",
    borderWidthEnabled: false,
    borderWidth: 2,
    position: "bottom",
    fullLength: false,
    reserveSpace: true,
    autoHide: false,
    clickAction: "focus-or-launch",
    controlCommand: "omarchy-menu toggle apps",
    pinned: [
      "org.gnome.Nautilus",
      "com.mitchellh.ghostty",
      "com.google.Chrome",
      "code",
      "obsidian",
      "chatgpt"
    ]
  })

  function loadSettings(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed.pinned || !Array.isArray(parsed.pinned))
        throw new Error("'pinned' must be an array")
      settings = parsed
    } catch (error) {
      console.warn("Dock: could not load " + configPath + ":", error)
    }
  }

  function reorderPinned(from, to) {
    if (from === to || from < 0 || to < 0
        || from >= settings.pinned.length || to >= settings.pinned.length)
      return

    var pinned = settings.pinned.slice()
    var moved = pinned.splice(from, 1)[0]
    pinned.splice(to, 0, moved)

    savePinned(pinned)
  }

  function pinApplication(desktopId) {
    if (!desktopId || settings.pinned.indexOf(desktopId) >= 0) return

    var pinned = settings.pinned.slice()
    pinned.push(desktopId)
    savePinned(pinned)
  }

  function unpinApplication(desktopId) {
    var index = settings.pinned.indexOf(desktopId)
    if (index < 0) return

    var pinned = settings.pinned.slice()
    pinned.splice(index, 1)
    savePinned(pinned)
  }

  function savePinned(pinned) {
    saveSetting("pinned", pinned)
  }

  function saveSetting(key, value) {
    var patch = {}
    patch[key] = value
    saveSettings(patch)
  }

  function saveSettings(patch) {
    var updated = DockModel.mergeSettings(settings, patch)

    settings = updated
    configFile.setText(JSON.stringify(updated, null, 2) + "\n")
  }

  function refreshTrash() {
    if (!trashListProcess.running) trashListProcess.running = true
  }

  function openTrash() {
    Quickshell.execDetached(["gio", "open", "trash:///"])
  }

  function emptyTrash() {
    if (!trashEmptyProcess.running) trashEmptyProcess.running = true
  }

  Component.onCompleted: refreshTrash()

  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: root.refreshTrash()
  }

  Process {
    id: trashListProcess

    command: ["gio", "trash", "--list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.trashItemCount = DockModel.trashItemCount(text)
        root.trashStateKnown = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("Dock: could not inspect Trash (gio exited " + exitCode + ")")
    }
  }

  Process {
    id: trashEmptyProcess

    command: ["gio", "trash", "--empty"]
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("Dock: could not empty Trash (gio exited " + exitCode + ")")
      root.refreshTrash()
    }
  }

  FileView {
    id: configFile

    path: root.configPath
    watchChanges: true
    printErrors: false
    blockWrites: true
    onLoaded: root.loadSettings(text())
    // FileView.text() is still stale inside onFileChanged. Reload first and
    // parse the fresh contents when onLoaded fires.
    onFileChanged: reload()
    onSaveFailed: error => console.warn("Dock: could not save " + root.configPath + ":", error)
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Dock {
        required property var modelData
        screen: modelData
        settings: root.settings
        trashItemCount: root.trashItemCount
        trashStateKnown: root.trashStateKnown
        onReorderRequested: (from, to) => root.reorderPinned(from, to)
        onPinRequested: desktopId => root.pinApplication(desktopId)
        onUnpinRequested: desktopId => root.unpinApplication(desktopId)
        onAutoHideRequested: enabled => root.saveSetting("autoHide", enabled)
        onSettingChanged: (key, value) => root.saveSetting(key, value)
        onResetSettingsRequested: root.saveSettings(DockModel.resetSettingsPatch())
        onOpenTrashRequested: root.openTrash()
        onEmptyTrashRequested: root.emptyTrash()
      }
    }
  }
}
