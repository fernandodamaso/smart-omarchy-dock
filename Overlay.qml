import QtQuick
import Quickshell

DockHost {
  // Properties injected by the Omarchy shell plugin host.
  property var shell: null
  property var manifest: null

  // Use the host-owned first-party service when Omarchy provides it. The
  // standalone shell leaves notificationService null and does not create a
  // competing NotificationServer.
  notificationService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("omarchy.notifications") : null
  configPath: Quickshell.env("HOME") + "/.config/smartdock/dock.json"
}
