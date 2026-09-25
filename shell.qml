import QtQuick
import Quickshell
import "components"

ShellRoot {
  DockMigrationBootstrap {
    id: migration
    runtimeMode: "standalone"
  }

  Loader {
    id: herdrLoader
    active: migration.ready
    sourceComponent: Component {
      DockHerdrService {}
    }
  }

  Loader {
    id: dockLoader
    active: migration.ready
    sourceComponent: Component {
      DockHost {
        runtimeMode: "standalone"
        configPath: migration.configPath
        dataRoot: migration.dataRoot
        herdrService: herdrLoader.item
      }
    }
  }
}
