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

  width: vertical ? slotSize + 6 : workspaceGrid.implicitWidth + 8
  height: vertical ? workspaceGrid.implicitHeight + 8 : slotSize + 6
  readonly property point workspaceGridOrigin: DockModel.workspaceGridPosition(
    position, width, height, iconSize,
    workspaceGrid.implicitWidth, workspaceGrid.implicitHeight)

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

        width: 30
        height: 30
        opacity: focused || occupied ? 1 : 0.5

        Button {
          anchors.fill: parent
          text: workspaceCell.modelData === 10 ? "0" : String(workspaceCell.modelData)
          tooltipText: "Workspace " + workspaceCell.modelData
            + (workspaceCell.count === 0
              ? " — empty"
              : " — " + workspaceCell.count
                + (workspaceCell.count === 1 ? " window" : " windows"))
          selected: workspaceCell.focused
          bordered: workspaceCell.focused
          foreground: Color.menu.text
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
