pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel

// Destination silhouette for a background mode drag: an outline of the edge the
// other presentation would render on, drawn on the source monitor.
//
// It is deliberately inert. The window mask is an empty region, so the
// compositor keeps passing clicks through the band it covers; it reserves no
// exclusive zone, is not focusable and never takes keyboard focus. The window
// only exists while the source gesture is armed and is owned by the same
// Quickshell process as the dock.
//
// Anchors follow the destination renderer rather than a fixed full-screen
// layer: the classic dock owns the bottom edge (inset by its margin), the
// sidebar owns its configured left or right edge flush to the output.
PanelWindow {
  id: root

  property string edge: "bottom"
  property real bandExtent: 0
  property real edgeInset: 0
  property bool requestedVisible: false
  property bool animationsEnabled: true

  readonly property real band: Math.max(0, Number(bandExtent) || 0)
  readonly property bool shaped: root.band > 0
    && (root.edge === "left" || root.edge === "right" || root.edge === "bottom")

  visible: root.shaped && (root.requestedVisible || silhouette.opacity > 0)
  color: "transparent"
  // One axis comes from the anchors, the other from the destination's extent.
  implicitWidth: root.edge === "bottom" ? 0 : root.band
  implicitHeight: root.edge === "bottom" ? root.band : 0
  anchors.top: root.edge !== "bottom"
  anchors.bottom: true
  anchors.left: root.edge !== "right"
  anchors.right: root.edge !== "left"
  margins {
    bottom: root.edge === "bottom" ? Math.max(0, Number(root.edgeInset) || 0) : 0
    top: 0
    left: 0
    right: 0
  }
  exclusiveZone: 0
  exclusionMode: ExclusionMode.Ignore
  focusable: false
  mask: Region {}
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  Rectangle {
    id: silhouette

    anchors.fill: parent
    radius: root.edge === "bottom" ? Style.cornerRadius : 0
    color: Util.alpha(Color.accent, Style.selectedFillAlpha * 0.5)
    border.color: Util.alpha(Color.accent, Style.selectedBorderAlpha * 0.85)
    border.width: Math.max(1, Style.hoverBorderWidth)
    opacity: root.requestedVisible ? 1 : 0

    Behavior on opacity {
      enabled: root.animationsEnabled
      NumberAnimation {
        duration: 120
        easing.type: Easing.OutCubic
      }
    }
  }
}
