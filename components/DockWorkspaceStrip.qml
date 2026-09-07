pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: root

  required property var workspaceIds
  required property var workspaces
  required property var hyprToplevels
  required property var workspaceWindowCounts
  required property bool workspaceCountsReady
  required property int workspaceStateRevision
  required property int focusedWorkspaceId
  required property bool vertical
  required property int slotSize
  required property int iconSize
  required property string position
  signal workspaceRequested(int workspaceId)

  function workspaceForId(id) {
    var values = workspaces || []
    for (var i = 0; i < values.length; ++i) {
      if (Number(values[i] ? values[i].id : -1) === Number(id))
        return values[i]
    }
    return null
  }

  readonly property int cellSize: Math.max(32, Math.round(iconSize * 0.75))

  width: vertical ? slotSize + 6 : workspaceGrid.implicitWidth + 8
  height: vertical ? workspaceGrid.implicitHeight + 8 : slotSize + 6
  readonly property point workspaceGridOrigin: DockModel.workspaceGridPosition(
    position, width, height, iconSize,
    workspaceGrid.implicitWidth, workspaceGrid.implicitHeight)

  Rectangle {
    x: workspaceGrid.x - 4
    y: workspaceGrid.y - 4
    width: workspaceGrid.implicitWidth + 8
    height: workspaceGrid.implicitHeight + 8
    radius: Math.max(12, Style.cornerRadius)
    color: Util.alpha(Color.background, 0.5)
    border.width: 1
    border.color: Util.alpha(Color.foreground, 0.14)
  }

  Grid {
    id: workspaceGrid

    x: root.workspaceGridOrigin.x
    y: root.workspaceGridOrigin.y
    columns: root.vertical ? 1 : Math.max(1, root.workspaceIds.length)
    rows: root.vertical ? Math.max(1, root.workspaceIds.length) : 1
    spacing: 2

    Repeater {
      model: root.workspaceIds

      Item {
        id: workspaceCell

        required property int modelData
        readonly property var workspace: root.workspaceForId(modelData)
        readonly property int count: {
          var revision = root.workspaceStateRevision
          return DockModel.workspaceWindowCount(
            modelData, root.hyprToplevels, root.workspaces,
            root.workspaceWindowCounts, root.workspaceCountsReady)
        }
        readonly property bool occupied: count > 0
        readonly property bool focused: root.focusedWorkspaceId === modelData

        width: root.cellSize
        height: root.cellSize
        opacity: focused || occupied ? 1 : 0.5

        Rectangle {
          anchors.fill: parent
          radius: Math.max(9, Style.cornerRadius)
          visible: workspaceCell.focused
          color: Util.alpha(Color.accent, 0.18)
        }

        Button {
          anchors.fill: parent
          radius: Math.max(9, Style.cornerRadius)
          focusable: true
          fontSize: Math.max(Style.font.body, root.iconSize * 0.32)
          text: workspaceCell.modelData === 10 ? "0" : String(workspaceCell.modelData)
          tooltipText: "Workspace " + workspaceCell.modelData
            + (workspaceCell.count === 0
              ? " — empty"
              : " — " + workspaceCell.count
                + (workspaceCell.count === 1 ? " window" : " windows"))
          selected: false
          bordered: false
          foreground: workspaceCell.focused ? Color.accent : Color.menu.text
          background: "transparent"
          accent: Color.accent
          horizontalPadding: 4
          verticalPadding: 3
          onClicked: root.workspaceRequested(workspaceCell.modelData)
        }

        Rectangle {
          visible: workspaceCell.focused
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 1
          width: 4
          height: 4
          radius: 2
          color: Color.accent
        }
      }
    }
  }
}
