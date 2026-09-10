import QtQuick
import Quickshell

ShellRoot {
  DockHost {
    runtimeMode: "standalone"
    configPath: Quickshell.env("SMARTDOCK_CONFIG")
      || Quickshell.shellDir + "/config/dock.json"
  }
}
