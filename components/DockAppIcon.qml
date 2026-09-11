import QtQuick
import Quickshell
import Quickshell.Widgets
import "DockIconModel.js" as DockIconModel

Item {
  id: root

  property string desktopId: ""
  property string desktopIcon: ""
  property var iconOverrides: ({})
  property int reloadRevision: 0
  property string profileKey: ""
  property string profileName: ""
  property string profileAvatarPath: ""
  property bool profileBadgesEnabled: true

  readonly property string overrideKey: DockIconModel.normalizeOverrideKey(profileKey
    ? DockIconModel.profileOverrideKey(desktopId, profileKey) : "")
  readonly property string overrideSource: DockIconModel.normalizeOverrides(iconOverrides)[
    DockIconModel.normalizeOverrideKey(desktopId)] || ""
  readonly property string profileOverrideSource: overrideKey
    ? (DockIconModel.normalizeOverrides(iconOverrides)[overrideKey] || "") : ""
  readonly property string desktopSource: resolveDesktopIcon(desktopIcon)
  readonly property var sourceCandidates: DockIconModel.candidates(profileOverrideSource,
    overrideSource, desktopSource, String(Quickshell.iconPath("application-x-executable", true) || ""))

  // Diagnostics describe this attempt, never mutate the configured mapping.
  readonly property bool usingOverride: !reloadPending && attemptedOverride !== ""
    && String(artwork.source) === attemptedOverride && artwork.status === Image.Ready
  readonly property bool overrideFailed: !reloadPending && customFailed
  readonly property string renderedSource: terminalFallback
    ? String(Qt.resolvedUrl("../assets/lucide/app-window.svg"))
    : artwork.status === Image.Ready ? String(artwork.source) : ""

  readonly property bool profileBadgeVisible: profileBadgesEnabled && !!profileKey
    && !profileBadgeActive && artwork.status === Image.Ready
  readonly property bool profileBadgeAvatarVisible: profileBadgeVisible
    && profileAvatarPath !== ""
  readonly property bool profileBadgeActive: overrideKey && profileOverrideSource !== ""

  property bool componentReady: false
  property bool reloadPending: false
  property var attemptSources: []
  property int attemptIndex: 0
  property string attemptedOverride: ""
  property bool customFailed: false
  property bool terminalFallback: false

  function resolveDesktopIcon(value) {
    if (typeof value !== "string" || !value) return ""
    // Desktop artwork transport is not restricted to override PNG/SVG policy.
    var local = DockIconModel.localFileUrl(value)
    if (local) return local
    if (value[0] === "/" || /^[a-z][a-z0-9+.-]*:/i.test(value)) return ""
    return String(Quickshell.iconPath(value, true) || "")
  }

  function requestReload() {
    if (!componentReady) return
    reloadPending = true
    terminalFallback = false
    // A real source reset is required even when Apply selects the same URL.
    // Coalesce settings/revision changes and discard the previous image load.
    artwork.source = ""
    Qt.callLater(root.loadNext)
  }

  function loadNext() {
    if (!componentReady) return
    if (reloadPending) {
      attemptSources = sourceCandidates.slice()
      attemptedOverride = overrideSource || profileOverrideSource
      attemptIndex = 0
      customFailed = false
      reloadPending = false
    }
    if (attemptIndex >= attemptSources.length) {
      artwork.source = ""
      terminalFallback = true
      return
    }
    var source = attemptSources[attemptIndex]
    // A late/coalesced callback must not decode the same candidate twice.
    if (String(artwork.source) === source) return
    terminalFallback = false
    // Bypass stale bytes only for custom files. System icons remain cached.
    artwork.backer.cache = source !== attemptedOverride
    artwork.source = source
  }

  function rejectSource(source) {
    if (reloadPending || terminalFallback || !source
        || artwork.status !== Image.Error || source !== String(artwork.source)
        || source !== attemptSources[attemptIndex]) return
    if (source === attemptedOverride) customFailed = true
    attemptIndex++
    artwork.source = ""
    // Advance once outside the status callback, including synchronous errors.
    Qt.callLater(root.loadNext)
  }

  onSourceCandidatesChanged: requestReload()
  onDesktopIdChanged: requestReload()
  onReloadRevisionChanged: requestReload()
  Component.onCompleted: {
    componentReady = true
    requestReload()
  }
  Component.onDestruction: componentReady = false

  IconImage {
    id: artwork

    anchors.fill: parent
    asynchronous: true
    // Fixed decoding budget: caller geometry and magnification only scale paint.
    backer.sourceSize: Qt.size(512, 512)
    backer.fillMode: Image.PreserveAspectFit
    visible: status === Image.Ready && !root.terminalFallback
    onStatusChanged: if (status === Image.Error) root.rejectSource(String(source))
  }

  // Profile badge: the profile's own photo, or an initial circle when the
  // profile has none. Hidden while a profile-specific icon override renders.
  Rectangle {
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.margins: Math.max(1, parent.width * 0.04)
    width: Math.max(8, parent.width * 0.34)
    height: width
    radius: width / 2
    visible: root.profileBadgeVisible
    clip: true
    border.width: Math.max(1, width * 0.09)
    border.color: "white"
    color: root.profileBadgeAvatarVisible ? "#ffffff"
      : DockIconModel.badgeColor(root.profileName || root.profileKey)

    Image {
      id: profileAvatar

      anchors.fill: parent
      visible: root.profileBadgeAvatarVisible
      asynchronous: true
      source: root.profileBadgeAvatarVisible
        ? DockIconModel.localFileUrl(root.profileAvatarPath) : ""
      fillMode: Image.PreserveAspectCrop
      cache: false
    }

    Text {
      anchors.centerIn: parent
      visible: !root.profileBadgeAvatarVisible
      text: String(root.profileName || root.profileKey || "").trim().charAt(0)
        .toUpperCase()
      color: "#ffffff"
      font.pixelSize: parent.width * 0.6
      font.weight: Font.DemiBold
    }
  }

  DockLucideIcon {
    anchors.fill: parent
    iconName: "app-window"
    visible: root.terminalFallback
    // Keep the existing theme tint here only; application artwork is untinted.
  }
}
