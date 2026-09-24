import QtQml
import qs.Commons
import "DockHerdrModel.js" as HerdrModel

// Single status-to-theme mapping for every Herdr presentation surface.
QtObject {
  function color(status) {
    var role = HerdrModel.statusColorRole(status)
    if (role === "accent") return Color.accent
    if (role === "idle") return Util.alpha(Color.foreground, 0.78)
    if (role === "muted") return Color.muted
    if (role === "done") return Color.flatColor("#9ece6a", Color.accent)
    if (role === "blocked") return Color.flatColor("#e0af68", Color.urgent)
    return Color.muted
  }

  function hollow(status) {
    return HerdrModel.statusColorRole(status) === "hollow"
  }
}
