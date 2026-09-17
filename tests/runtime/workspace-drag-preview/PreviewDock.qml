pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "components" as Components
import "PreviewModel.js" as PreviewModel

Item {
  id: root

  required property string monitorIdentity
  required property string monitorLabel
  required property var presentation
  property var committedFixtures: null
  property var dragController: null
  property string scopeMode: "all"
  property string focusedMonitor: ""
  property bool animationsEnabled: true
  property bool autoHideEnabled: false
  property bool dragRevealed: false
  property bool workspaceMonitorDropHighlighted: false
  property int slotSize: 36
  property int iconSize: 28
  property point monitorOrigin: Qt.point(0, 0)
  property point sceneOrigin: Qt.point(0, 0)
  readonly property bool dockShown: !autoHideEnabled || dragRevealed || dockHover.hovered
  readonly property bool workspaceMonitorDragAvailable: true
  readonly property color workspaceMonitorDragAccent: Color.accent
  readonly property color workspaceMonitorDragBackground: Color.menu.background
  readonly property color workspaceMonitorDragForeground: Color.menu.text
  readonly property string workspaceMonitorDragFontFamily: Style.font.family
  readonly property int workspaceMonitorDragFontSize: Style.font.bodySmall
  readonly property bool dragActive: !!(dragController && dragController.active)
  readonly property string dragSourceWorkspace: dragActive
    ? String(dragController.sourceWorkspace || "") : ""
  readonly property string dragSourceMonitor: dragActive
    ? String(dragController.sourceMonitor || "") : ""
  readonly property string dragTargetMonitor: dragActive
    ? String(dragController.targetMonitor || "") : ""
  readonly property bool foreignTargetActive: dragActive && dragTargetMonitor !== ""
  readonly property size dragGhostSize: dragActive && dragController.ghostSize
    ? dragController.ghostSize : Qt.size(slotSize + 40, slotSize + 10)

  readonly property var visibleMonitors: {
    var monitors = presentation && presentation.monitors ? presentation.monitors : []
    if (scopeMode === "current-monitor")
      return monitors.filter(function (monitor) {
        return monitor && monitor.identity === root.monitorIdentity
      })
    return monitors.slice()
  }

  // DockIconModel.normalizeSource only accepts strings; QUrl objects are dropped
  // and every fixture icon silently falls back to app-window.svg.
  readonly property var iconOverrides: ({
    "preview.chrome": String(Qt.resolvedUrl("assets/lucide/rocket.svg")),
    "preview.files": String(Qt.resolvedUrl("assets/lucide/folder-open.svg")),
    "preview.terminal": String(Qt.resolvedUrl("assets/lucide/terminal.svg")),
    "preview.chat": String(Qt.resolvedUrl("assets/lucide/sparkles.svg")),
    "preview.notes": String(Qt.resolvedUrl("assets/lucide/layout-grid.svg")),
    "preview.code": String(Qt.resolvedUrl("assets/lucide/settings-2.svg")),
    "preview.mail": String(Qt.resolvedUrl("assets/services/gmail.svg"))
  })

  property var sectionHitRects: []

  function committedWorkspace(identity) {
    var workspaces = committedFixtures && committedFixtures.workspaces
      ? committedFixtures.workspaces : []
    for (var i = 0; i < workspaces.length; ++i) {
      if (workspaces[i] && workspaces[i].identity === identity)
        return workspaces[i]
    }
    return null
  }

  function sectionWorkspaces(monitor) {
    var list = (monitor.workspaces || []).slice()
    if (!root.dragActive || monitor.identity !== root.dragSourceMonitor)
      return list
    for (var i = 0; i < list.length; ++i) {
      if (list[i] && list[i].identity === root.dragSourceWorkspace)
        return list
    }
    var source = committedWorkspace(root.dragSourceWorkspace)
    if (!source) return list
    list = list.concat([source])
    list.sort(PreviewModel.workspaceCompare)
    return list
  }

  function cardFor(workspaceIdentity) {
    return findCard(dockRow, String(workspaceIdentity || ""))
  }

  function findCard(item, workspaceIdentity) {
    if (!item) return null
    if (item.workspaceIdentity === workspaceIdentity && item.card)
      return item.card
    var children = item.children || []
    for (var i = 0; i < children.length; ++i) {
      var found = findCard(children[i], workspaceIdentity)
      if (found) return found
    }
    return null
  }

  function snapshotSectionHits() {
    var hits = []
    for (var i = 0; i < sectionRepeater.count; ++i) {
      var section = sectionRepeater.itemAt(i)
      if (!section) continue
      var topLeft = section.mapToItem(root, 0, 0)
      hits.push({
        identity: section.sectionIdentity,
        rect: Qt.rect(topLeft.x, topLeft.y, section.width, section.height)
      })
    }
    sectionHitRects = hits
    return hits
  }

  function sectionAt(scenePoint) {
    var local = mapFromItem(null, scenePoint.x, scenePoint.y)
    var hits = sectionHitRects.length ? sectionHitRects : snapshotSectionHits()
    for (var i = 0; i < hits.length; ++i) {
      var hit = hits[i]
      var rect = hit.rect
      if (local.x >= rect.x && local.x < rect.x + rect.width
          && local.y >= rect.y && local.y < rect.y + rect.height)
        return hit.identity
    }
    if (local.x >= 0 && local.x < width && local.y >= 0 && local.y < height)
      return root.monitorIdentity
    return ""
  }

  readonly property rect monitorRect: Qt.rect(monitorOrigin.x, monitorOrigin.y, width, height)
  readonly property rect revealRect: Qt.rect(monitorOrigin.x, monitorOrigin.y + height - 8, width, 8)
  readonly property rect dropRect: dockShown
    ? Qt.rect(monitorOrigin.x + dockFrame.x, monitorOrigin.y + dockFrame.y,
      dockFrame.width, dockFrame.height)
    : Qt.rect(0, 0, 0, 0)

  Rectangle {
    anchors.fill: parent
    radius: Style.space(12)
    color: Util.alpha(Color.background, 0.55)
    border.width: root.workspaceMonitorDropHighlighted ? 2 : 1
    border.color: root.workspaceMonitorDropHighlighted ? Color.accent
      : Util.alpha(Color.foreground, 0.12)
  }

  Text {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: Style.space(12)
    text: root.monitorLabel + " · " + root.monitorIdentity
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 8
    visible: root.autoHideEnabled && !root.dockShown
    color: Util.alpha(Color.accent, 0.35)
  }

  Rectangle {
    id: dockFrame
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(12)
    height: root.slotSize + 28
    radius: Style.space(16)
    visible: root.dockShown
    color: Util.alpha(Color.menu.background, 0.92)
    border.width: 1
    border.color: Util.alpha(Color.menu.border, 0.8)
    clip: true

    Flickable {
      id: dockViewport
      anchors.fill: parent
      anchors.margins: Style.space(8)
      contentWidth: Math.max(width, dockRow.implicitWidth)
      contentHeight: height
      flickableDirection: Flickable.HorizontalFlick
      interactive: contentWidth > width && !root.dragActive
      boundsBehavior: Flickable.StopAtBounds
      onContentXChanged: {
        if (root.dragActive && root.dragController)
          root.dragController.baselineHits = root.dragController.snapshotBaselines()
        root.snapshotSectionHits()
      }

      Row {
        id: dockRow
        height: parent.height
        spacing: Style.space(8)

        Repeater {
          id: sectionRepeater
          model: root.visibleMonitors
          delegate: Row {
            id: sectionRow
            required property var modelData
            required property int index
            readonly property string sectionIdentity: String(modelData.identity || "")
            readonly property var sectionCards: root.sectionWorkspaces(modelData)
            height: dockRow.height
            spacing: Style.space(6)

            Components.DockSeparator {
              visible: root.scopeMode === "all" && sectionRow.index > 0
              vertical: false
              slotSize: root.slotSize
              iconSize: root.iconSize
            }

            Components.DockMonitorLabel {
              visible: root.scopeMode === "all"
              label: String(modelData.label || modelData.connector || "")
              description: String(modelData.label || "")
              connector: String(modelData.connector || "")
              focused: sectionRow.sectionIdentity === root.focusedMonitor
              position: "bottom"
              slotSize: root.slotSize
            }

            Repeater {
              model: sectionRow.sectionCards
              delegate: Components.DockAnimatedSlot {
                id: cardSlot
                required property var modelData
                required property int index
                property string workspaceIdentity: String(modelData.identity || "")
                property alias card: workspaceCard
                readonly property bool isDragged: root.dragActive
                  && workspaceIdentity === root.dragSourceWorkspace
                readonly property bool isSourceGrab: isDragged
                  && sectionRow.sectionIdentity === root.dragSourceMonitor
                readonly property bool isDestinationPlaceholder: isDragged
                  && sectionRow.sectionIdentity === root.dragTargetMonitor
                // Source gap stays open until a foreign target is active, then closes.
                present: isSourceGrab ? !root.foreignTargetActive : true
                animateEntrance: isDestinationPlaceholder
                animationsEnabled: root.animationsEnabled
                naturalWidth: (isSourceGrab || isDestinationPlaceholder)
                  ? root.dragGhostSize.width
                  : Math.max(workspaceCard.width, root.slotSize + 24)
                naturalHeight: (isSourceGrab || isDestinationPlaceholder)
                  ? root.dragGhostSize.height
                  : Math.max(workspaceCard.height, root.slotSize + 10)

                Rectangle {
                  visible: cardSlot.isSourceGrab || cardSlot.isDestinationPlaceholder
                  width: root.dragGhostSize.width
                  height: root.dragGhostSize.height
                  radius: Math.max(12, Style.cornerRadius - 4)
                  color: cardSlot.isDestinationPlaceholder
                    ? Util.alpha(Color.accent, 0.14)
                    : Util.alpha(Color.foreground, 0.08)
                  border.width: 1
                  border.color: cardSlot.isDestinationPlaceholder
                    ? Util.alpha(Color.accent, 0.4)
                    : Util.alpha(Color.foreground, 0.16)
                  enabled: false
                }

                // Destination placeholders are inert; only the source grab card
                // keeps a live DockWorkspaceGroup / DragHandler.
                Components.DockWorkspaceGroup {
                  id: workspaceCard
                  visible: !cardSlot.isDestinationPlaceholder
                  opacity: cardSlot.isSourceGrab ? 0 : 1
                  label: String(modelData.label || "")
                  showFullLabel: modelData.showFullLabel === true
                  count: Number(modelData.count || 0)
                  active: String(modelData.identity || "")
                    === String(sectionRow.modelData.activeWorkspace || "")
                  urgent: modelData.badge === true
                  slotSize: root.slotSize
                  position: "bottom"
                  animationsEnabled: root.animationsEnabled
                  workspaceIdentity: cardSlot.isDestinationPlaceholder
                    ? "" : cardSlot.workspaceIdentity
                  workspaceOwnerMonitor: String(modelData.owner
                    || sectionRow.sectionIdentity)
                  workspaceMonitorDrag: cardSlot.isDestinationPlaceholder
                    ? null : root.dragController
                  workspaceMonitorDragDock: cardSlot.isDestinationPlaceholder
                    ? null : root
                  applicationModel: modelData.items || []
                  applicationDelegate: Component {
                    Item {
                      required property var modelData
                      required property int index
                      width: root.iconSize + 6
                      height: root.slotSize + 6

                      Components.DockAppIcon {
                        anchors.centerIn: parent
                        width: root.iconSize
                        height: root.iconSize
                        desktopId: String(modelData.desktopId || "")
                        iconOverrides: root.iconOverrides
                      }

                      Rectangle {
                        visible: modelData.badge === true
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 2
                        width: Math.max(14, badgeLabel.implicitWidth + 6)
                        height: 14
                        radius: 7
                        color: Color.urgent
                        Text {
                          id: badgeLabel
                          anchors.centerIn: parent
                          text: String(modelData.badgeText || "3")
                          color: Color.foreground
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }
                    }
                  }
                  onActivated: console.log("preview-activate", workspaceIdentity)
                }
              }
            }

            Text {
              visible: sectionRow.sectionCards.length === 0
              anchors.verticalCenter: parent.verticalCenter
              text: "Empty"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  HoverHandler {
    id: dockHover
  }

  onPresentationChanged: Qt.callLater(root.snapshotSectionHits)
  onVisibleMonitorsChanged: Qt.callLater(root.snapshotSectionHits)
  onWidthChanged: Qt.callLater(root.snapshotSectionHits)
  onHeightChanged: Qt.callLater(root.snapshotSectionHits)
  Component.onCompleted: Qt.callLater(root.snapshotSectionHits)
}
