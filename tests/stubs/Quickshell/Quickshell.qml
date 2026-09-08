pragma Singleton
import QtQuick

QtObject {
  function env(name) {
    if (name === "HOME")
      return "/home/admin"
    if (name === "XDG_CONFIG_HOME")
      return "/home/admin/.config"
    if (name === "OMARCHY_MENU_FONT")
      return ""
    return ""
  }

  function execDetached(argv) {
    // No-op for host qmltestrunner regressions.
  }
}
