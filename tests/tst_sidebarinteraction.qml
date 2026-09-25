import QtQuick
import QtTest
import "../components"

TestCase {
  id: test
  name: "SidebarInteraction"
  when: windowShown
  width: 640; height: 480
  visible: true
  property var input: null
  property var activations: []
  property var menus: []
  QtObject {
    id: controller
    property string selectedConnector: "DP-1"
    property bool interactionBusy: false
    property bool resizeActive: false
    property bool rowDragActive: false
    property var target: ({key:"window:1",kind:"window",address:"0xa"})
    function captureTarget(key) { return key === target.key ? target : null }
    function rememberNavigationFocus() {}
    function beginRowDrag(target) {
      if (interactionBusy || resizeActive || !target) return false
      rowDragActive=true; interactionBusy=true; return true
    }
    function cancelRowDrag(reason) { rowDragActive=false; interactionBusy=false }
  }
  function init() {
    var component=Qt.createComponent("../components/DockSidebarRowInput.qml")
    compare(component.status,Component.Ready,component.errorString())
    input=component.createObject(test,{controller:controller,rowKey:"window:1",x:20,y:20,width:200,height:80})
    verify(input !== null)
    input.activated.connect(function(target,control,monitor,modifiers) {
      activations.push({target:target,control:control,monitor:monitor,modifiers:modifiers})
    })
    input.contextRequested.connect(function(target) {menus.push(target)})
    input.dragReleased.connect(function(point) {controller.cancelRowDrag("release")})
    activations=[]; menus=[]
    controller.selectedConnector="DP-1";controller.resizeActive=false
    controller.target={key:"window:1",kind:"window",address:"0xa"}
    controller.cancelRowDrag("init")
  }
  function cleanup() { if(input) input.destroy(); input=null;controller.cancelRowDrag("cleanup") }
  function test_plain_and_control_use_distinct_native_handlers() {
    mouseClick(input,30,30,Qt.LeftButton,Qt.NoModifier)
    compare(activations.length,1);verify(!activations[0].control)
    mouseClick(input,30,30,Qt.LeftButton,Qt.ControlModifier)
    compare(activations.length,2);verify(activations[1].control)
    verify((activations[1].modifiers & Qt.ControlModifier) !== 0)
    mouseClick(input,30,30,Qt.RightButton,Qt.NoModifier)
    compare(menus.length,1);compare(activations.length,2)
    mouseClick(input,30,30,Qt.MiddleButton,Qt.NoModifier)
    compare(activations.length,2)
  }
  function test_workspace_rows_forward_control_and_connector() {
    input.destroy(); input = null
    controller.target = {key:"ws:1",kind:"workspace",workspaceIdentity:"id:1"}
    var component = Qt.createComponent("../components/DockSidebarRowInput.qml")
    compare(component.status, Component.Ready, component.errorString())
    input = component.createObject(test, {controller:controller,rowKey:"ws:1",x:20,y:20,width:200,height:80})
    verify(input !== null)
    input.activated.connect(function(target,control,monitor,modifiers) {
      activations.push({target:target,control:control,monitor:monitor,modifiers:modifiers})
    })
    input.contextRequested.connect(function(target) {menus.push(target)})
    activations=[]; menus=[]
    controller.selectedConnector="DP-1"
    mouseClick(input,30,30,Qt.LeftButton,Qt.NoModifier)
    compare(activations.length,1); verify(!activations[0].control)
    compare(activations[0].monitor,"DP-1")
    compare(activations[0].target.workspaceIdentity,"id:1")
    mouseClick(input,30,30,Qt.LeftButton,Qt.ControlModifier)
    compare(activations.length,2); verify(activations[1].control)
    verify((activations[1].modifiers & Qt.ControlModifier) !== 0)
    compare(activations[1].monitor,"DP-1")
    compare(activations[1].target.workspaceIdentity,"id:1")
  }
  function test_press_captures_target_and_host_before_transition() {
    var original=controller.target
    mousePress(input,30,30,Qt.LeftButton,Qt.ControlModifier)
    controller.target={key:"window:1",kind:"window",address:"0xb"}
    controller.selectedConnector="HDMI-A-1"
    mouseRelease(input,30,30,Qt.LeftButton,Qt.ControlModifier)
    compare(activations.length,1);compare(activations[0].target.address,original.address)
    compare(activations[0].monitor,"DP-1")
  }
  function test_cancelled_drag_never_becomes_click() {
    mousePress(input,20,30,Qt.LeftButton,Qt.ControlModifier)
    mouseMove(input,70,35,30,Qt.LeftButton)
    input.cancelGesture("escape")
    mouseRelease(input,70,35,Qt.LeftButton,Qt.ControlModifier)
    compare(activations.length,0);verify(!controller.rowDragActive)
    mouseClick(input,30,30,Qt.LeftButton,Qt.NoModifier)
    compare(activations.length,1)
  }
  function test_drag_release_commits_once_without_activation() {
    var releases=0
    input.dragReleased.connect(function(){++releases})
    mousePress(input,20,30,Qt.LeftButton,Qt.NoModifier)
    mouseMove(input,85,35,30,Qt.LeftButton)
    verify(controller.rowDragActive)
    verify(input.dragOwned)
    verify(!input.hovered, "source hover styling is suppressed during a window drag")
    mouseRelease(input,85,35,Qt.LeftButton,Qt.NoModifier)
    compare(releases,1);compare(activations.length,0)
    verify(!controller.rowDragActive)
  }
  function test_resize_excludes_window_drag() {
    controller.resizeActive=true;controller.interactionBusy=true
    mousePress(input,20,30,Qt.LeftButton)
    mouseMove(input,85,35,30,Qt.LeftButton)
    mouseRelease(input,85,35,Qt.LeftButton)
    verify(!controller.rowDragActive);compare(activations.length,0)
  }
}
