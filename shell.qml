import QtQuick
import Quickshell

ShellRoot {
  DockHost {
    configPath: Quickshell.env("SMARTDOCK_CONFIG")
      || Quickshell.shellDir + "/config/dock.json"
  }
}
