import QtQuick
import "components"

// Omarchy owns exactly one instance of this headless service for the plugin.
// Overlay.qml consumes it through shell.serviceFor(...); standalone shell.qml
// intentionally does not instantiate it and therefore keeps FDM-809 dots.
DockLauncherBadgeService {
  id: root

  // Browser-window profile snapshots (FDM profile badges) ride the same
  // plugin-owned singleton so multi-screen overlays share one provider.
  property alias browserProfileService: browserProfiles

  DockBrowserProfileService {
    id: browserProfiles
  }
}
