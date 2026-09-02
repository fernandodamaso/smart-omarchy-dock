import QtQuick
import Quickshell

DockHost {
  // Properties injected by the Omarchy shell plugin host.
  property var shell: null
  property var manifest: null

  // Reuse the host-owned notification service when Omarchy exposes it. Older
  // or standalone hosts can leave this null; SmartDock never starts a second
  // notification daemon just to power attention dots.
  notificationService: shell && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.notifications")
    : shell && typeof shell.serviceFor === "function"
      ? shell.serviceFor("omarchy.notifications") : null

  // FDM-811 is a multi-kind plugin. Omarchy owns one headless service instance
  // and the overlay only consumes its provider-neutral count snapshot.
  launcherBadgeService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("io.github.fernandodamaso.smartdock") : null

  configPath: Quickshell.env("HOME") + "/.config/smartdock/dock.json"
}
