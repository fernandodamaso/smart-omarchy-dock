import QtQuick
import QtTest
import "../components"

TestCase {
  name: "SidebarResize"
  when: windowShown
  width: 800; height: 500

  QtObject {
    id: writer
    property var writes: []
    property string mode: "accepted"
    function saveSettingIntent(key, value, expectedValue) {
      if (mode === "rejected")
        return {accepted:false,pending:false,reply:{ok:false,error:{code:"E_BUSY",message:"busy"},data:{applied:false,currentValue:expectedValue}}}
      writes = writes.concat([{key:key,value:value,expectedValue:expectedValue}])
      return {accepted:true,pending:mode === "pending",reply:{ok:mode !== "pending",
        error:mode === "pending" ? {code:"E_BUSY",message:"saving"} : null,
        data:{applied:true,persisted:mode !== "pending"}}}
    }
  }
  Component { id: factory; DockSidebarController { host: writer } }
  Component { id: handleFactory; DockSidebarResizeHandle { width: 8; height: 300 } }

  function makeController(edge) {
    return createTemporaryObject(factory, this, {
      settings:{presentationMode:"sidebar",sidebarEdge:edge || "left",sidebarMonitor:"",
        sidebarExpandedWidth:320,sidebarCollapsed:false,pinned:[],workspaceGroups:[]},
      screens:[{name:"DP-1",x:-1920,width:1920,height:1080}],
      monitors:[{id:0,name:"DP-1",x:-1920,y:0,activeWorkspace:{id:1}}],
      workspaces:[{id:1,monitorID:0}]
    })
  }
  function init() { writer.writes=[]; writer.mode="accepted" }

  function test_pointer_moves_are_preview_only_and_release_commits_once() {
    var c=makeController("left")
    verify(c.beginResize(-1600)); compare(c.resizeStartWidth,320)
    verify(c.updateResize(-1560)); compare(c.geometry.width,360); compare(writer.writes.length,0)
    verify(c.updateResize(-1540)); compare(c.geometry.width,380); compare(writer.writes.length,0)
    var result=c.finishResize(false)
    verify(result.accepted); compare(writer.writes.length,1)
    compare(writer.writes[0].key,"sidebarExpandedWidth")
    compare(writer.writes[0].value,380); compare(writer.writes[0].expectedValue,320)
    verify(!c.resizeActive)
  }

  function test_legacy_effective_width_keeps_exact_host_stale_token() {
    var c=makeController("left")
    c.settings=Object.assign({},c.settings,{sidebarExpandedWidth:"320"})
    compare(c.geometry.width,320)
    verify(c.beginResize(0)); c.updateResize(40); c.finishResize(false)
    compare(writer.writes.length,1)
    compare(writer.writes[0].value,360)
    compare(writer.writes[0].expectedValue,"320")
  }

  function test_right_edge_uses_stable_global_delta() {
    var c=makeController("right")
    verify(c.beginResize(-100)); verify(c.updateResize(-140)); compare(c.geometry.width,360)
    verify(c.updateResize(-160)); compare(c.geometry.width,380); compare(writer.writes.length,0)
    c.finishResize(false); compare(writer.writes.length,1); compare(writer.writes[0].value,380)
  }

  function test_noop_cancel_and_grab_loss_write_nothing() {
    var c=makeController("left")
    verify(c.beginResize(0)); c.updateResize(40); c.updateResize(0); c.finishResize(false)
    compare(writer.writes.length,0,"release at captured start is a no-op")
    verify(c.beginResize(0)); c.updateResize(60); c.cancelResize("escape")
    compare(c.geometry.width,320); compare(writer.writes.length,0)
    verify(c.beginResize(0)); c.updateResize(60)
    var handle=createTemporaryObject(handleFactory,this,{controller:c,panelWidth:c.geometry.width,
      screenX:-1920,screenWidth:1920})
    verify(handle !== null); handle.cancelActiveResize("grab-loss")
    compare(writer.writes.length,0); verify(!c.resizeActive)
    compare(handle.pointerTarget,null,"native handler must not move the handle target")
  }

  function test_conflicts_and_surface_changes_cancel_preview() {
    var c=makeController("left")
    verify(c.beginResize(0)); c.updateResize(80)
    c.settings=Object.assign({},c.settings,{sidebarCollapsed:true})
    tryCompare(c,"resizeActive",false); compare(writer.writes.length,0,"accepted collapse conflict cancels preview")

    c.settings=Object.assign({},c.settings,{sidebarCollapsed:false,sidebarExpandedWidth:320})
    tryCompare(c,"collapsed",false); verify(c.beginResize(0)); c.updateResize(80)
    c.settings=Object.assign({},c.settings,{sidebarExpandedWidth:340})
    tryCompare(c,"resizeActive",false); compare(writer.writes.length,0,"accepted width conflict cancels preview")

    c.settings=Object.assign({},c.settings,{sidebarExpandedWidth:320})
    verify(c.beginResize(0)); c.updateResize(40)
    c.settings=Object.assign({},c.settings,{sidebarEdge:"right"})
    tryCompare(c,"resizeActive",false); compare(writer.writes.length,0)

    c.settings=Object.assign({},c.settings,{sidebarEdge:"left"})
    c.screens=[{name:"DP-1",x:-1920,width:1920,height:1080},{name:"HDMI-A-1",x:0,width:1280,height:720}]
    c.monitors=[{id:0,name:"DP-1",x:-1920,y:0,activeWorkspace:{id:1}},
      {id:1,name:"HDMI-A-1",x:0,y:0,activeWorkspace:{id:2}}]
    c.refresh(); verify(c.beginResize(0)); c.updateResize(40)
    c.settings=Object.assign({},c.settings,{sidebarMonitor:"HDMI-A-1"})
    tryCompare(c,"resizeActive",false)
    tryCompare(c,"selectedConnector","HDMI-A-1")
    compare(writer.writes.length,0,"explicit host switch cancels instead of saving the preview")
  }

  function test_busy_rejection_reverts_to_host_preference() {
    var c=makeController("left"); writer.mode="rejected"
    verify(c.beginResize(0)); c.updateResize(60)
    var result=c.finishResize(false)
    verify(!result.accepted); compare(writer.writes.length,0); compare(c.geometry.width,320)
    verify(c.mutationFeedback.length>0)
  }

  function test_rail_and_overlapping_interaction_disable_handle() {
    var c=makeController("left")
    c.settings=Object.assign({},c.settings,{sidebarCollapsed:true}); tryCompare(c,"collapsed",true)
    verify(!c.beginResize(0))
    c.settings=Object.assign({},c.settings,{sidebarCollapsed:false}); c.interactionBusy=true
    verify(!c.beginResize(0),"resize cannot overlap another interaction")
  }
}
