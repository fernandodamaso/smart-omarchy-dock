import QtQuick
import QtTest
import "../components"

TestCase {
  id: testCase
  name: "IconReloadScheduler"

  property int revision: 0

  // Mirrors DockHost: one watcher per path forwarding fileChanged. The real
  // host uses Quickshell FileView, which is not loadable in qmltestrunner.
  Instantiator {
    id: watchers
    model: scheduler.watchedPaths
    delegate: QtObject {
      required property string modelData
      readonly property string path: modelData
      signal fileChanged()
      onFileChanged: scheduler.noteFileChanged()
    }
  }

  DockIconReloadScheduler {
    id: scheduler
    debounceInterval: 60
    onReloadRequested: testCase.revision++
  }

  SignalSpy { id: pathsSpy; target: scheduler; signalName: "watchedPathsKeyChanged" }
  SignalSpy { id: reloadSpy; target: scheduler; signalName: "reloadRequested" }

  function init() {
    scheduler.iconOverrides = ({})
    scheduler.windowIconOverrides = []
    scheduler.debounce.stop()
    pathsSpy.clear()
    reloadSpy.clear()
    revision = 0
  }

  function watcherPaths() {
    var paths = []
    for (var i = 0; i < watchers.count; ++i) paths.push(watchers.objectAt(i).path)
    return paths
  }

  function test_noReloadAtStartup() {
    scheduler.iconOverrides = { "firefox": "file:///icons/fox.png" }
    wait(150)
    compare(watchers.count, 1)
    compare(reloadSpy.count, 0)
    compare(revision, 0)
  }

  function test_watchedSetFollowsBothCollections() {
    scheduler.iconOverrides = {
      "firefox": "file:///icons/fox.png",
      "code@profile:work": "file:///icons/My%20Code.svg",
      "kitty": "/icons/fox.png",
      "bad": "https://example.com/x.png",
      "notimage": "file:///icons/readme.txt"
    }
    scheduler.windowIconOverrides = [
      { appId: "chromium", titlePattern: "*Mail*", source: "file:///icons/mail.png" }
    ]
    compare(scheduler.watchedPaths, ["/icons/My Code.svg", "/icons/fox.png", "/icons/mail.png"])
    compare(watcherPaths(), ["/icons/My Code.svg", "/icons/fox.png", "/icons/mail.png"])

    scheduler.windowIconOverrides = []
    compare(watcherPaths(), ["/icons/My Code.svg", "/icons/fox.png"])
    scheduler.iconOverrides = ({})
    compare(watchers.count, 0)
  }

  function test_invalidWindowRulesAreNotWatched() {
    scheduler.windowIconOverrides = [{ appId: "x", source: "file:///icons/a.png" }]
    compare(watchers.count, 0)
    scheduler.windowIconOverrides = "nonsense"
    compare(watchers.count, 0)
  }

  function test_equivalentSettingsDoNotRebuildWatchers() {
    scheduler.iconOverrides = { "firefox": "file:///icons/fox.png" }
    var first = watchers.objectAt(0)
    pathsSpy.clear()
    scheduler.iconOverrides = { "firefox": "file:///icons/fox.png", "kitty": "/icons/fox.png" }
    compare(pathsSpy.count, 0)
    verify(watchers.objectAt(0) === first)
  }

  function test_changeBumpsRevisionOnceAfterDebounce() {
    scheduler.iconOverrides = { "firefox": "file:///icons/fox.png" }
    watchers.objectAt(0).fileChanged()
    compare(revision, 0)
    verify(scheduler.pending)
    tryCompare(testCase, "revision", 1, 1000)
    wait(150)
    compare(revision, 1)
    verify(!scheduler.pending)
  }

  function test_burstAcrossFilesCoalesces() {
    scheduler.iconOverrides = {
      "firefox": "file:///icons/fox.png",
      "code": "file:///icons/code.svg"
    }
    for (var i = 0; i < 5; ++i) {
      watchers.objectAt(i % 2).fileChanged()
      wait(20)
    }
    compare(revision, 0)
    tryCompare(testCase, "revision", 1, 1000)
    wait(150)
    compare(reloadSpy.count, 1)

    watchers.objectAt(0).fileChanged()
    tryCompare(testCase, "revision", 2, 1000)
  }

  function test_defaultDebounceIsAboutQuarterSecond() {
    var component = Qt.createComponent("../components/DockIconReloadScheduler.qml")
    var instance = component.createObject(testCase)
    compare(instance.debounceInterval, 250)
    compare(instance.watchedPaths, [])
    instance.destroy()
  }
}
