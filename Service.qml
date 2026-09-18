import QtQuick
import "components"

// Omarchy owns exactly one instance of this headless service for the plugin.
// Overlay.qml consumes it through shell.serviceFor(...). The launcher-badge,
// browser-profile and demand-driven Herdr services remain shared per plugin.
DockLauncherBadgeService {
  id: root

  // Browser-window profile snapshots (FDM profile badges) ride the same
  // plugin-owned singleton so multi-screen overlays share one provider.
  property alias browserProfileService: browserProfiles
  property alias herdrService: herdr

  DockBrowserProfileService {
    id: browserProfiles
  }

  DockHerdrService {
    id: herdr
  }
}
