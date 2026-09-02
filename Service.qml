import QtQuick
import "components"

// Omarchy owns exactly one instance of this headless service for the plugin.
// Overlay.qml consumes it through shell.serviceFor(...); standalone shell.qml
// intentionally does not instantiate it and therefore keeps FDM-809 dots.
DockLauncherBadgeService {}
