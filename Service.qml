import QtQuick
import "components"

// Omarchy owns exactly one instance of this headless service for the plugin.
// Overlay.qml consumes it through shell.serviceFor(...); standalone shell.qml
// intentionally does not instantiate it and therefore keeps FDM-809 dots.
Item {
  id: root

  readonly property bool available: launcherProvider.available
  readonly property int revision: launcherProvider.revision + herdrProvider.revision
  readonly property var counts: launcherProvider.counts
  readonly property var herdrBadgeService: herdrProvider

  DockLauncherBadgeService {
    id: launcherProvider
  }

  DockHerdrBadgeService {
    id: herdrProvider
  }

  function herdrBadgeStateFor(desktopId) {
    return herdrProvider.countStateFor(desktopId)
  }

  function herdrBadgeSeverityFor(desktopId) {
    return herdrProvider.severityFor(desktopId)
  }
}
