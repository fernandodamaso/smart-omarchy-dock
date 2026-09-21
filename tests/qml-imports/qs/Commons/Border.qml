pragma Singleton
import QtQuick

QtObject {
  function none() {
    return { kind: "none", color: "transparent", width: 0 }
  }

  function controlSpec(kind, foreground, accent) {
    return { kind: kind, color: accent, width: 1 }
  }

  function surfaceSpec(name, role, color, width) {
    return { name: name, role: role, color: color, width: width || 1 }
  }
}
