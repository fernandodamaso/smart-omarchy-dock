import QtQuick
import QtTest
import "SidebarDropSourceHarness.js" as Harness
import "../components/DockSidebarModel.js" as SidebarModel

TestCase {
  id: test
  name: "SidebarDropQueuedFeedback"
  when: windowShown
  visible: true
  width: 600; height: 400
  property var origin: null
  property var mirror: null
  QtObject { id: capturedWindow }
  QtObject {
    id: actions
    function canonicalMonitorIdentity(value) { return value === "0" ? "id:0" : value }
  }
  QtObject {
    id: controller
    property var dropOperation: null
    property bool projecting: false
    property bool refreshPending: false
    property var rowsByKey: ({})
    property var states: ({})
    property bool originAlive: true
    property bool entityAlive: true
    property bool locationMatches: true
    property var windowActions: actions
    signal refreshed()
    function dropOriginIsCurrent(op) { return originAlive && !!op && op === dropOperation }
    function dropEntityAlive(op) { return entityAlive }
    function dropLocationMatches(op) { return locationMatches }
    function endDropOperation(token) { if(dropOperation && dropOperation.token===token) dropOperation=null }
    function readScrollState(connector,collapsed) { return SidebarModel.readScrollState(states,connector,collapsed) }
    function writeScrollState(connector,collapsed,anchor,keys) {
      states=SidebarModel.writeScrollState(states,connector,collapsed,anchor,keys)
    }
  }
  function operation(state) {
    return {token:19,state:state || "confirmed",sourceKind:"window",sourceKey:"destination",
      toplevel:capturedWindow,address:"0xa",expectedWorkspace:"id:3",expectedMonitor:"id:0",
      originConnector:"DP-1",originSurfaceGeneration:1}
  }
  function init() {
    controller.dropOperation=null; controller.originAlive=true;controller.entityAlive=true
    controller.locationMatches=true;controller.projecting=false;controller.refreshPending=false
    controller.states=({})
    var rows=[]
    for(var i=0;i<24;++i) rows.push({kind:"window",key:"r"+i,workspaceIdentity:"id:3",monitorIdentity:"0"})
    rows[20]={kind:"window",key:"destination",workspaceIdentity:"id:3",monitorIdentity:"0",toplevel:capturedWindow,address:"0xa"}
    controller.rowsByKey=({})
    rows.forEach(function(row) { controller.rowsByKey[row.key]=row })
    origin=Harness.viewport(test,{controller:controller,panelConnector:"DP-1",dropSurfaceGeneration:1,visibleRows:rows})
    mirror=Harness.viewport(test,{controller:controller,panelConnector:"HDMI-A-1",dropSurfaceGeneration:2,
      panelCollapsed:true,scrollModeCollapsed:true,previousCollapsed:true,visibleRows:rows,x:250})
    tryCompare(origin.listView,"count",24);tryCompare(mirror.listView,"count",24)
    origin.listView.forceLayout();mirror.listView.forceLayout()
    var keys=rows.map(function(row) { return row.key })
    controller.writeScrollState("DP-1",false,{key:"r0",offset:0},keys)
    controller.writeScrollState("HDMI-A-1",true,{key:"r2",offset:4},keys)
    origin.restoreAnchor();mirror.restoreAnchor()
    compare(mirror.listView.contentY,64)
  }
  function cleanup() {
    controller.dropOperation=null
    if(origin)origin.destroy();if(mirror)mirror.destroy()
    origin=null;mirror=null
    wait(0)
  }
  function test_queued_restore_then_offscreen_contain_is_origin_only() {
    var before=JSON.stringify(controller.readScrollState("HDMI-A-1",true))
    origin.previousHeightMap="old-layout"
    origin.requestRestore() // genuine Qt.callLater restoration already queued
    verify(origin.pendingRestore)
    controller.dropOperation=operation()
    tryCompare(origin,"dropFlashKey","destination")
    verify(!origin.pendingRestore && !origin.restoring)
    verify(origin.listView.contentY>0)
    var index=origin.indexForKey("destination")
    var item=origin.listView.itemAtIndex(index)
    verify(item !== null)
    verify(item.y>=origin.listView.contentY && item.y+item.height<=origin.listView.contentY+origin.listView.height)
    var destinationY=origin.listView.contentY
    Qt.callLater(origin.restoreAnchor) // a late queued restore must read the new anchor
    wait(30)
    compare(origin.listView.contentY,destinationY)
    compare(mirror.listView.contentY,64)
    compare(mirror.dropFlashKey,"")
    compare(JSON.stringify(controller.readScrollState("HDMI-A-1",true)),before)
  }
  function test_recreated_origin_rejects_already_queued_callback() {
    controller.dropOperation=operation()
    origin.dropSurfaceGeneration=3
    wait(30)
    compare(origin.dropFlashKey,"");compare(origin.listView.contentY,0)
  }
  function test_changed_entity_never_positions_or_flashes() {
    controller.dropOperation=operation();controller.entityAlive=false
    wait(30)
    compare(origin.dropFlashKey,"");compare(origin.listView.contentY,0)
    compare(controller.dropOperation,null)
  }
  function test_unconfirmed_and_missing_folded_row_do_not_scroll() {
    controller.dropOperation=operation("unconfirmed")
    tryCompare(origin,"feedbackState","unconfirmed")
    compare(origin.dropFlashKey,"");compare(origin.listView.contentY,0)
    controller.dropOperation=null
    origin.visibleRows=origin.visibleRows.filter(function(row) { return row.key!=="destination" })
    controller.dropOperation=operation()
    wait(30)
    compare(origin.dropFlashKey,"");compare(origin.listView.contentY,0)
    compare(controller.dropOperation,null)
  }
}
