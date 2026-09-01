pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui

PopupWindow {
  id: root

  required property Item anchorItem
  required property string position
  required property var pinned
  signal applicationSelected(string desktopId)

  readonly property var applications: DesktopEntries.applications.values || []
  readonly property var filteredApplications: filterApplications(searchInput.text)

  function open() {
    searchInput.text = ""
    visible = true
    Qt.callLater(() => searchInput.forceActiveFocus())
  }

  function matchScore(value, query) {
    var text = String(value || "").toLowerCase()
    var exactIndex = text.indexOf(query)
    if (exactIndex >= 0)
      return 1000 - exactIndex * 4 - text.length

    var queryIndex = 0
    var previousIndex = -2
    var score = 0
    for (var i = 0; i < text.length && queryIndex < query.length; ++i) {
      if (text[i] !== query[queryIndex]) continue
      score += i === previousIndex + 1 ? 8 : 2
      previousIndex = i
      ++queryIndex
    }
    return queryIndex === query.length ? score - text.length : -1
  }

  function filterApplications(rawQuery) {
    var query = String(rawQuery || "").trim().toLowerCase()
    var matches = []
    var modelRevision = applications.length

    for (var i = 0; i < applications.length; ++i) {
      var application = applications[i]
      if (!application || !application.id || application.noDisplay
          || pinned.indexOf(application.id) >= 0)
        continue

      var score = query
        ? Math.max(matchScore(application.name, query), matchScore(application.id, query))
        : 0
      if (score >= 0)
        matches.push({ application: application, score: score })
    }

    matches.sort((left, right) => right.score - left.score
      || String(left.application.name).localeCompare(String(right.application.name)))
    return matches.slice(0, 100).map(match => match.application)
  }

  function selectCurrent() {
    if (applicationList.currentIndex < 0 || applicationList.currentIndex >= filteredApplications.length)
      return
    var application = filteredApplications[applicationList.currentIndex]
    visible = false
    applicationSelected(application.id)
  }

  implicitWidth: 380
  implicitHeight: 420
  color: "transparent"
  grabFocus: true

  onFilteredApplicationsChanged: applicationList.currentIndex = filteredApplications.length ? 0 : -1

  anchor {
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.anchor.window) return

      var x = root.anchorItem.width / 2 - root.implicitWidth / 2
      var y = root.anchorItem.height + 8
      if (root.position === "bottom")
        y = -root.implicitHeight - 8
      else if (root.position === "left") {
        x = root.anchorItem.width + 8
        y = root.anchorItem.height / 2 - root.implicitHeight / 2
      } else if (root.position === "right") {
        x = -root.implicitWidth - 8
        y = root.anchorItem.height / 2 - root.implicitHeight / 2
      }

      var point = root.anchor.window.contentItem.mapFromItem(root.anchorItem, x, y)
      point.x = Math.max(8, Math.min(point.x, root.anchor.window.width - root.implicitWidth - 8))
      point.y = Math.max(8, Math.min(point.y, root.anchor.window.height - root.implicitHeight - 8))
      root.anchor.rect.x = Math.round(point.x)
      root.anchor.rect.y = Math.round(point.y)
    }
  }

  BorderSurface {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec(
      "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

    BorderSurface {
      id: searchField

      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        margins: 12
      }
      height: 42
      radius: Style.cornerRadius
      color: searchInput.activeFocus
        ? Style.focusFillFor(Color.menu.text, Color.accent)
        : Style.normalFillFor(Color.menu.text, Color.accent)
      borderSpec: Border.controlSpec(
        searchInput.activeFocus ? "focus" : "normal",
        Color.menu.text, Color.accent)

      Text {
        anchors {
          verticalCenter: parent.verticalCenter
          left: parent.left
          leftMargin: 12
        }
        visible: !searchInput.text
        text: "Search applications..."
        color: Util.alpha(Color.menu.text, 0.46)
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }

      TextInput {
        id: searchInput

        anchors {
          fill: parent
          leftMargin: 12
          rightMargin: 12
        }
        verticalAlignment: TextInput.AlignVCenter
        color: Color.menu.text
        selectionColor: Util.alpha(Color.menu.text, 0.25)
        selectedTextColor: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        clip: true

        Keys.onPressed: event => {
          if (event.key === Qt.Key_Down) {
            applicationList.currentIndex = Math.min(applicationList.count - 1, applicationList.currentIndex + 1)
            applicationList.positionViewAtIndex(applicationList.currentIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            applicationList.currentIndex = Math.max(0, applicationList.currentIndex - 1)
            applicationList.positionViewAtIndex(applicationList.currentIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.selectCurrent()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.visible = false
            event.accepted = true
          }
        }
      }
    }

    ListView {
      id: applicationList

      anchors {
        top: searchField.bottom
        bottom: parent.bottom
        left: parent.left
        right: parent.right
        topMargin: 8
        bottomMargin: 10
        leftMargin: 8
        rightMargin: 8
      }
      clip: true
      spacing: 2
      model: root.filteredApplications

      delegate: BorderSurface {
        id: applicationRow

        required property var modelData
        required property int index

        width: applicationList.width
        height: 52
        radius: Style.cornerRadius
        color: applicationList.currentIndex === index
          ? Color.menu.selectedBackground
          : "transparent"
        borderSpec: applicationList.currentIndex === index
          ? Border.controlSpec("selected", Color.menu.text, Color.accent)
          : Border.none()

        IconImage {
          anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            leftMargin: 10
          }
          width: 30
          height: 30
          source: applicationRow.modelData.icon
            ? Quickshell.iconPath(applicationRow.modelData.icon, true)
            : Quickshell.iconPath("application-x-executable", true)
          asynchronous: true
        }

        Column {
          anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: 52
            rightMargin: 10
          }

          Text {
            width: parent.width
            text: applicationRow.modelData.name || applicationRow.modelData.id
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: applicationRow.modelData.id
            color: Util.alpha(Color.menu.text, 0.48)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        HoverHandler {
          id: rowHover
          cursorShape: Qt.PointingHandCursor
          onHoveredChanged: if (hovered) applicationList.currentIndex = applicationRow.index
        }

        TapHandler {
          onTapped: {
            applicationList.currentIndex = applicationRow.index
            root.selectCurrent()
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: applicationList.count === 0
        text: "No matching applications"
        color: Util.alpha(Color.menu.text, 0.52)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
