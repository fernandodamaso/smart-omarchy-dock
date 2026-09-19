import QtQuick
import qs.Commons

// Snapshot-only presentation. It never acquires a provider, starts a process,
// subscribes to Herdr or emits desktop notifications.
Item {
  id: root
  property var widgetContext: ({})

  readonly property var snapshot: widgetContext && widgetContext.data
    ? widgetContext.data : ({})
  readonly property string presentation: widgetContext && widgetContext.presentation
    ? String(widgetContext.presentation) : "expanded"
  readonly property bool compact: presentation === "compact"
  readonly property var servers: snapshot && Array.isArray(snapshot.servers)
    ? snapshot.servers : []
  readonly property var agents: snapshot && Array.isArray(snapshot.agents)
    ? snapshot.agents : []
  readonly property var counts: snapshot ? snapshot.liveCounts : null
  readonly property var rows: buildRows()

  implicitHeight: compact ? 44 : Math.min(240, Math.max(44, 34 + rows.length * 38))
  clip: true

  function buildRows() {
    var output = []
    var byServer = Object.create(null)
    root.agents.forEach(function(agent) {
      var id = String(agent.serverId || "")
      if (!byServer[id]) byServer[id] = []
      byServer[id].push(agent)
    })
    root.servers.forEach(function(server) {
      var id = String(server.id || "")
      output.push({
        kind: "session",
        key: "server:" + id,
        title: String(server.label || server.session || "Herdr"),
        detail: String(server.health || "unavailable"),
        status: String(server.health || "unavailable")
      })
      var items = byServer[id] || []
      items.forEach(function(agent) {
        output.push({
          kind: "agent",
          key: String(agent.id || id + ":agent"),
          title: String(agent.name || agent.label || agent.agent || "Coding agent"),
          detail: String(agent.agent || "agent") + " · " + String(agent.status || "unknown"),
          status: String(agent.status || "unknown")
        })
      })
      if (!items.length && server.health === "live") {
        output.push({
          kind: "empty",
          key: "empty:" + id,
          title: "No active coding agents",
          detail: "",
          status: "idle"
        })
      }
    })
    if (!output.length) {
      output.push({
        kind: "empty",
        key: "empty",
        title: "No local Herdr session",
        detail: "",
        status: "unknown"
      })
    }
    return output
  }

  function summary() {
    if (!root.counts) return "Herdr unavailable"
    var total = root.counts.agents || 0
    var text = String(total) + (total === 1 ? " agent" : " agents")
    if ((root.counts.blocked || 0) > 0)
      text += " · " + root.counts.blocked + " blocked"
    if (root.snapshot.completeness
        && root.snapshot.completeness.state === "partial")
      text += " · partial"
    return text
  }

  function dotOpacity(status) {
    return status === "working" || status === "blocked" || status === "live"
      ? 1.0 : status === "done" ? 0.75 : 0.45
  }

  Item {
    anchors.fill: parent
    visible: root.compact

    Rectangle {
      x: 12
      anchors.verticalCenter: parent.verticalCenter
      width: 8
      height: 8
      radius: 4
      color: Color.foreground
      opacity: root.counts && (root.counts.blocked || 0) > 0 ? 1.0 : 0.55
    }

    Text {
      x: 30
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - 42)
      text: root.summary()
      textFormat: Text.PlainText
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  Flickable {
    anchors.fill: parent
    visible: !root.compact
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    contentWidth: width
    contentHeight: detailColumn.implicitHeight

    Column {
      id: detailColumn
      width: parent.width

      Item {
        width: parent.width
        height: 34

        Text {
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(0, parent.width - 20)
          text: root.summary()
          textFormat: Text.PlainText
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
      }

      Repeater {
        model: root.rows

        delegate: Item {
          required property var modelData
          width: detailColumn.width
          height: 38

          Rectangle {
            x: modelData.kind === "agent" ? 20 : 10
            anchors.verticalCenter: parent.verticalCenter
            width: 7
            height: 7
            radius: 4
            color: Color.foreground
            opacity: root.dotOpacity(modelData.status)
          }

          Column {
            x: modelData.kind === "agent" ? 38 : 28
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - x - 10)
            spacing: 1

            Text {
              width: parent.width
              text: modelData.title
              textFormat: Text.PlainText
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: modelData.kind === "session"
                ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
            }

            Text {
              visible: modelData.detail.length > 0
              width: parent.width
              text: modelData.detail
              textFormat: Text.PlainText
              color: Color.foreground
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Math.max(10, Style.font.body - 2)
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
