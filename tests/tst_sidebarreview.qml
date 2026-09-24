import QtQuick
import QtTest
import "../components"
import "../components/DockSidebarInteractionModel.js" as InteractionModel

// Actual controller + QML geometry bindings, not compositor acceptance evidence.
TestCase {
  name: "SidebarReviewGeometry"
  when: windowShown
  width: 800; height: 500

  QtObject {
    id: writer
    property var writes: []
    function saveSettingIntent(key, value, expectedValue) {
      writes = writes.concat([{key:key, value:value, expectedValue:expectedValue}])
      return {accepted:true, pending:false, reply:{ok:true, data:{applied:true, persisted:true}}}
    }
  }
  Component { id: factory; DockSidebarController { host: writer } }
  Component {
    id: geometryConsumer
    Item {
      required property var controller
      required property var screen
      readonly property real reservedWidth: controller.geometryFor(screen).width
    }
  }

  function init() { writer.writes = [] }
  function test_monitor_map_tooltip() {
    compare(InteractionModel.monitorTopologyTooltip({connector:"DP-1", focused:true}),
      "Monitor DP-1 · focused")
    compare(InteractionModel.monitorTopologyTooltip({connector:"HDMI-A-1", focused:false}),
      "Monitor HDMI-A-1")
  }
  function test_resize_preserves_other_output_rail_data() {
    return [{tag:"left-override",edge:"left",fallback:false},
      {tag:"right-override",edge:"right",fallback:false},
      {tag:"left-default",edge:"left",fallback:true},
      {tag:"right-default",edge:"right",fallback:true}]
  }
  function test_resize_preserves_other_output_rail(data) {
    var expanded = {name:"DP-1",x:-1920,width:1920,height:1080}
    var rail = {name:"DP-2",x:0,width:1280,height:720}
    var c = createTemporaryObject(factory, this, {
      settings:{presentationMode:"sidebar", sidebarEdge:data.edge, sidebarExpandedWidth:320,
        sidebarCollapsed:data.fallback,
        sidebarCollapsedByMonitor:data.fallback ? {"DP-1":false} : {"DP-2":true},
        pinned:[], workspaceGroups:[]},
      screens:[expanded,rail],
      monitors:[{id:0,name:"DP-1",x:-1920,y:0,activeWorkspace:{id:1}},
        {id:1,name:"DP-2",x:0,y:0,activeWorkspace:{id:2}}],
      workspaces:[{id:1,monitorID:0},{id:2,monitorID:1}]
    })
    verify(c !== null)
    var a = createTemporaryObject(geometryConsumer, this, {controller:c, screen:expanded})
    var b = createTemporaryObject(geometryConsumer, this, {controller:c, screen:rail})
    verify(a !== null && b !== null)
    compare(a.reservedWidth,320); compare(b.reservedWidth,72)
    verify(c.beginResize(0, expanded))
    verify(c.updateResize(data.edge === "left" ? 80 : -80))
    compare(a.reservedWidth,400); compare(b.reservedWidth,72)
    compare(writer.writes.length,0)
    verify(c.finishResize(false).accepted)
    compare(writer.writes.length,1)
    compare(writer.writes[0].key,"sidebarExpandedWidth")
    compare(writer.writes[0].value,400)
    compare(b.reservedWidth,72)
    c.settings=Object.assign({},c.settings,{sidebarExpandedWidth:400})
    compare(a.reservedWidth,400); compare(b.reservedWidth,72)
    verify(c.beginResize(0, expanded))
    c.updateResize(data.edge === "left" ? -40 : 40)
    compare(a.reservedWidth,360); compare(b.reservedWidth,72)
    c.cancelResize("escape")
    compare(a.reservedWidth,400); compare(b.reservedWidth,72)
    compare(writer.writes.length,1)
  }
}
