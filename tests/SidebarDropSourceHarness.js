.pragma library

// Read trusted repository source only. Tests execute the production scheduling,
// restoration and containment methods inside a real Qt Quick ListView instead
// of maintaining a second implementation of their asynchronous ordering.
function viewport(parent, options) {
  var request = new XMLHttpRequest()
  request.open("GET", Qt.resolvedUrl("../components/DockSidebarViewport.qml"), false)
  request.send()
  if (!request.responseText) throw new Error("Source fixture requires QML_XHR_ALLOW_FILE_READ=1")
  var names = ["isOwnDrop", "queueDropPresentation", "presentDropOperation",
    "presentConfirmedDrop", "dropRowIndex", "dropWorkspaceSpan", "indexForKey",
    "captureAnchor", "requestRestore", "restoreAnchor"]
  var methods = request.responseText.match(/^  function [\s\S]*?^  }/gm) || []
  var selected = names.map(function(name) {
    var matches = methods.filter(function(method) { return method.indexOf("  function " + name + "(") === 0 })
    if (matches.length !== 1) throw new Error("Missing/ambiguous production method " + name)
    return matches[0]
  }).join("\n")
  var callbacks = ["onPendingRestoreChanged", "onRestoringChanged"].map(function(name) {
    var match = request.responseText.match(new RegExp("^  " + name + ":.*$", "m"))
    if (!match) throw new Error("Missing production callback " + name)
    return match[0]
  }).join("\n")
  var restoreTimer = request.responseText.match(
    /^  Timer \{\n    id: restoreTimer\n[\s\S]*?^  \}/m)
  if (!restoreTimer) throw new Error("Missing production owned restore timer")
  var source = 'import QtQuick\n'
    + 'import "' + Qt.resolvedUrl('../components/DockSidebarModel.js') + '" as SidebarModel\n'
    + 'import "' + Qt.resolvedUrl('../components/DockSidebarInteractionModel.js') + '" as InteractionModel\n'
    + 'import "' + Qt.resolvedUrl('../components/DockModel.js') + '" as DockModel\n'
    + 'Item { id: root; width: 200; height: 90; visible: true\n'
    + 'property var controller; property var visibleRows: []; property var sectionSpans: []\n'
    + 'property string panelConnector: ""; property bool panelCollapsed: false\n'
    + 'property bool presentationVisible: true; property double dropSurfaceGeneration: 0\n'
    + 'property double queuedDropToken: 0; property double presentedDropToken: 0\n'
    + 'property string dropFlashKey: ""; property string feedbackState: ""\n'
    + 'property bool pendingRestore: false; property bool restoring: false\n'
    + 'property bool scrollModeCollapsed: false; property bool previousCollapsed: false\n'
    + 'property var previousKeys: []; property real rowHeight: 30; property real previousRowHeight: 30\n'
    + 'property real previousContentHeight: 0; property string previousHeightMap: ""\n'
    + 'property alias listView: list\n'
    // Fixed-height layout inputs and visual outputs, not replacements for the
    // production queue/restore/Contain/anchor code under test.
    + 'function estimatedRowHeight(row) { return rowHeight }\n'
    + 'function rowYAtIndex(index) { return index * rowHeight }\n'
    + 'function heightMap() { return JSON.stringify(visibleRows.map(function(r) { return [r.key, 30] })) }\n'
    + 'function bumpSectionChrome() {}\n'
    + 'function sectionSpanRect(span) { return {y:indexForKey(span.firstKey)*rowHeight, height:rowHeight} }\n'
    + 'function clearDropPresentation() { dropFlashKey=""; queuedDropToken=0 }\n'
    + 'function showDropFeedback(op) { feedbackState=op.state }\n'
    + 'function showDropFlash(token,key) { presentedDropToken=token; dropFlashKey=key }\n'
    + selected + '\n' + callbacks + '\n' + restoreTimer[0] + '\n'
    + 'ListView { id:list; anchors.fill:parent; model:root.visibleRows; cacheBuffer:0\n'
    + ' delegate: Item { required property int index; width:list.width; height:root.rowHeight }\n'
    + '}\nConnections { target:root.controller\n'
    + 'function onDropOperationChanged() { root.queueDropPresentation() }\n'
    + 'function onRefreshed() { root.requestRestore(); root.queueDropPresentation() }\n'
    + '}\n}'
  var result = Qt.createQmlObject(source, parent, "SidebarDropSourceHarness")
  Object.keys(options).forEach(function(key) { result[key] = options[key] })
  return result
}
