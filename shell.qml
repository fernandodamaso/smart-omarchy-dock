import QtQuick
import Quickshell
import "components"

ShellRoot {
  DockHerdrService {
    id: herdrService
  }

  DockHost {
    runtimeMode: "standalone"
    herdrService: herdrService
    // Source launches must not write the bundled defaults used by CLI reset.
    // Explicit isolated configurations still take precedence.
    configPath: Quickshell.env("SMARTDOCK_CONFIG")
      || (Quickshell.env("XDG_CONFIG_HOME")
        || Quickshell.env("HOME") + "/.config") + "/smartdock/dock.json"
  }
}
