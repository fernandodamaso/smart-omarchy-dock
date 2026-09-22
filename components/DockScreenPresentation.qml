pragma ComponentBehavior: Bound

import QtQuick
import "DockScreenPresentationModel.js" as ScreenPresentationModel

// One stable owner for one connected output, and nothing else: surface content
// comes from the host-injected surfaceComponent, so this file owns only the
// lifecycle contract both presentations share.
//
// The contract is teardown-first. syncSurface() drops the current surface
// synchronously and defers creation of the replacement, so an old surface's
// input region, exclusive zone and popups are gone before the new one exists,
// and two surfaces for one output can never overlap. Each output has its own
// owner, so switching one screen never touches another screen's surface
// instance — and destroying the owner (output disconnect) destroys its surface,
// which closes that surface's menus, previews and gestures.
Item {
  id: root

  property string connector: ""
  property var screenObject: null
  property string mode: "classic"
  property string source: "inherited"
  property bool mapped: true
  // Desired-surface identity beyond its Component (the sidebar re-anchors when
  // its configured edge moves, which must recreate its surface).
  property string surfaceKey: mode
  property var presentation: null
  property Component surfaceComponent: null

  readonly property var surface: surfaceLoader.item
  readonly property var panels: surfaceLoader.item && surfaceLoader.item.panels
    ? surfaceLoader.item.panels : []
  readonly property bool surfaceReady: surfaceLoader.active && surfaceLoader.item !== null
  // Press-time mode-switch state for this connector. The panel hands this to
  // its drag surface, which captures it when the pointer goes down.
  readonly property var gestureToken: ScreenPresentationModel.modeGestureToken(
    presentation, connector)

  function syncSurface() {
    if (!root.mapped || !root.surfaceComponent) {
      surfaceLoader.active = false
      return
    }
    // Synchronous teardown precedes deferred creation: the old Dock/Sidebar
    // owns its popup, drag and badge-scope destruction before the replacement
    // reserves any geometry.
    surfaceLoader.active = false
    surfaceLoader.sourceComponent = root.surfaceComponent
    Qt.callLater(root.activateSurface)
  }

  function activateSurface() {
    if (!root.mapped || !root.surfaceComponent) return
    surfaceLoader.active = true
  }

  // Forced recreate when the desired surface changed without a Component
  // change (surfaceKey covers the sidebar edge). Still teardown-first.
  function invalidateSurface() {
    surfaceLoader.active = false
    root.syncSurface()
  }

  Component.onCompleted: root.syncSurface()
  onSurfaceComponentChanged: root.syncSurface()
  onSurfaceKeyChanged: root.invalidateSurface()
  onMappedChanged: root.syncSurface()

  Loader {
    id: surfaceLoader
    active: false
    onLoaded: {
      if (surfaceLoader.item && surfaceLoader.item.owner !== undefined)
        surfaceLoader.item.owner = root
    }
  }
}
