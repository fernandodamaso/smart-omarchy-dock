import QtQuick
import QtTest

TestCase {
  id: test
  name: "SidebarKeyboard"
  when: windowShown
  visible: true
  width: 400; height: 240
  property var keyboard: null
  property var events: []
  QtObject {
    id: actionController
    property bool interactionBusy: false
    property string focusedRowKey: "ws"
    property var projection: ({rows:[{key:"monitor",kind:"monitor"}, {key:"ws",kind:"workspace"},
      {key:"app",kind:"application"}, {key:"window",kind:"window"}, {key:"footer",kind:"section"}]})
    function captureTarget(key) { return {key:key,kind:"window"} }
    function toggleApplication(key) { if (key !== "app") return false; events.push("fold"); return true }
    function releaseNavigationFocus() { events.push("return-focus") }
  }
  QtObject {
    id: viewport
    property var controller: actionController
    property var visibleRows: actionController.projection.rows
    function focusRow(key) { actionController.focusedRowKey=key; events.push("focus:"+key); return true }
    function activate(target, control, connector, modifiers) {
      events.push({key:target.key,control:control,connector:connector}); return true
    }
    function cancelInputs(reason) { events.push("cancel:"+reason) }
    function dismissContextRequested() { events.push("dismiss") }
    function currentDelegate() { return {key:actionController.focusedRowKey} }
    function contextRequested(target,item) { events.push("menu:"+target.key) }
  }
  function init() {
    var factory=Qt.createComponent("../components/DockSidebarKeyboard.qml")
    compare(factory.status,Component.Ready,factory.errorString())
    keyboard=factory.createObject(test,{viewport:viewport})
    verify(keyboard !== null)
    actionController.interactionBusy=false; actionController.focusedRowKey="ws"; events=[]
    keyboard.forceActiveFocus(); verify(keyboard.activeFocus)
  }
  function cleanup() { if(keyboard) keyboard.destroy(); keyboard=null }
  function test_navigation_skips_noninteractive_sections() {
    keyClick(Qt.Key_Down); compare(actionController.focusedRowKey,"app")
    keyClick(Qt.Key_Tab); compare(actionController.focusedRowKey,"window")
    keyClick(Qt.Key_Backtab); compare(actionController.focusedRowKey,"app")
    keyClick(Qt.Key_Home); compare(actionController.focusedRowKey,"ws")
    keyClick(Qt.Key_End); compare(actionController.focusedRowKey,"window")
    keyClick(Qt.Key_Up); compare(actionController.focusedRowKey,"app")
    keyClick(Qt.Key_Space); compare(events[events.length-1],"fold")
  }
  function test_enter_is_plain_even_with_control_held() {
    actionController.focusedRowKey="window"
    keyClick(Qt.Key_Return,Qt.ControlModifier)
    compare(events.length,1); compare(events[0].key,"window")
    verify(!events[0].control); compare(events[0].connector,"")
  }
  function test_menu_and_escape_use_explicit_target_and_restore_focus() {
    actionController.focusedRowKey="window"
    keyClick(Qt.Key_F10,Qt.ShiftModifier); compare(events[0],"menu:window")
    actionController.interactionBusy=true
    keyClick(Qt.Key_Down); compare(events.length,1)
    keyClick(Qt.Key_Escape)
    compare(events.slice(1).join(","),"cancel:escape,dismiss,return-focus")
  }
}
