.pragma library

// Only compositor popup endpoints are replaced. Area/manager logic, bindings,
// input, timers and helpers are executed from current production source.
function source(name) {
  var request = new XMLHttpRequest()
  request.open("GET", Qt.resolvedUrl("../components/" + name + ".qml"), false)
  request.send()
  if (!request.responseText) throw new Error("QML_XHR_ALLOW_FILE_READ=1 is required")
  return request.responseText
}
function makeArea(parent, properties) {
  var code = source("DockSidebarWidgetArea")
  code = code.replace("import Quickshell\n", "")
  code = code.replace(/^  PopupWindow \{[\s\S]*?^  \}/m,
    '  Item { id:popup; visible:root.ownsPopupAnchor() && root.controller.widgetPopupId !== "" && root.panel.visible\n'
    + 'property QtObject anchor: QtObject { property int updates:0; function updateAnchor(){updates++} }\n'
    + 'onVisibleChanged: geometryTimer.restart()\n  }')
  code = code.replace('import "widgets"', 'import "' + Qt.resolvedUrl('../components/widgets') + '"')
  code = code.replace(/import "(Dock[^"/]+\.js)"/g, function(_,name) { return 'import "' + Qt.resolvedUrl('../components/'+name) + '"' })
  code = code.replace('import QtQuick\n','import QtQuick\nimport "' + Qt.resolvedUrl('../components') + '"\n')
  // Inject required endpoints before bindings evaluate.
  code = code.replace('required property var controller','property var controller: parent.controller')
    .replace('required property var panel','property var panel: parent')
    .replace('required property var viewport','property var viewport: parent.viewport')
    .replace('required property real windowRowHeight','property real windowRowHeight: 34')
  var item = Qt.createQmlObject(code, parent, Qt.resolvedUrl("SplitAreaFixture.qml"))
  Object.keys(properties || {}).forEach(function(key){item[key]=properties[key]})
  return item
}
function makeManager(parent) {
  var code = source("DockSidebarWidgetManager")
  code = code.replace(/^  Ui\.PopupCard \{[\s\S]*?^  \}/m,
    '  Item { id:managerPopup; property QtObject anchor: QtObject { property int updates:0; function updateAnchor(){updates++} } }')
  code = code.replace(/import "(Dock[^"/]+\.js)"/g, function(_,name) { return 'import "'+Qt.resolvedUrl('../components/'+name)+'"' })
  code = code.replace('required property var controller','property var controller: parent.controller')
    .replace('required property var panel','property var panel: parent')
    .replace('required property var viewport','property var viewport: parent.viewport')
  return Qt.createQmlObject(code, parent, Qt.resolvedUrl("SplitManagerFixture.qml"))
}
