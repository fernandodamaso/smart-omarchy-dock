import assert from 'node:assert/strict'
import { interactionFixture } from './sidebar_interaction_fixture.mjs'
const f=interactionFixture(),c=f.controller,a=f.actions
assert.equal(typeof c.captureTarget,'function','SB-04 must capture exact live targets before focus transitions')
let target=c.captureTarget(c.projection.rows[0].key)
assert.equal(target.toplevel,f.windows[0])
assert.equal(c.activateTarget(target,false,'DP-1'),true)
assert.deepEqual(f.requests,['focuswindow address:0x1'])
assert.equal(f.batches.length,0,'plain click cannot request a whole-workspace move')
f.clear();assert.equal(c.activateTarget(target,undefined,'DP-1'),true);assert.equal(f.batches.length,0)
f.clear();assert.equal(c.activateTarget(target,'true','DP-1'),true);assert.equal(f.batches.length,0)
f.clear();assert.equal(c.activateTarget(target,true,'DP-1'),true)
assert.match(JSON.stringify(f.batches),/movecurrentworkspacetomonitor 0/)
assert.match(JSON.stringify(f.batches),/focuswindow address:0x1/)
f.clear();c.selectedConnector='HDMI-A-1';c.activateTarget(target,true,'HDMI-A-1')
assert.equal(f.batches.length,1);assert.doesNotMatch(JSON.stringify(f.batches),/move(?:current)?workspace/)
f.clear();c.selectedConnector='DP-1';a.pinWorkspaceToMonitor('name:Design work');c.activateTarget(target,true,'DP-1')
assert.doesNotMatch(JSON.stringify(f.batches),/move(?:current)?workspace/,'Ctrl never overrides session pins')
a.unpinWorkspaceFromMonitor('name:Design work')
f.clear();assert.equal(c.activateTarget(target,true,'removed-connector'),false);assert.equal(f.requests.length+f.batches.length,0)
f.clear();c.activateTarget(c.captureTarget('ws'),true,'DP-1')
assert.deepEqual(f.requests,['workspace name:Design work']);assert.equal(f.batches.length,0,'header ignores pull intent')
f.clear();a.minimizedOrigins={'0x1':{workspace:'name:Design work',monitor:'1'}}
f.handles[0].lastIpcObject.workspace={name:'special:smartdock-minimized'}
assert.equal(c.activateTarget(target,false,'DP-1'),true)
assert.deepEqual(f.requests,['movetoworkspace name:Design work,address:0x1'])
f.clear();a.minimizedOrigins={'0x1':{workspace:'name:Design work',monitor:'1'}}
c.activateTarget(target,true,'DP-1');assert.match(JSON.stringify(f.batches),/movecurrentworkspacetomonitor/)
f.clear();a.minimizedOrigins={};assert.equal(c.activateTarget(target,false,'DP-1'),false,'missing minimized origin fails closed')
f.handles[0].lastIpcObject.workspace={name:'Design work'}
f.clear();f.windows.splice(0,1,{appId:'editor',title:'replacement'})
f.handles[0].wayland=f.windows[0]
assert.equal(c.activateTarget(target,true,'DP-1'),false,'same address on a new handle cannot inherit target')
assert.equal(f.requests.length+f.batches.length,0)
const p=interactionFixture(),pc=p.controller
p.handles[0].address='';p.windows[0].activate=()=>p.requests.push('native-activate')
const pending=pc.captureTarget(pc.projection.rows[0].key)
assert.equal(pc.activateTarget(pending,false,'DP-1'),true)
assert.deepEqual(p.requests,['native-activate'],'unknown location stays reachable through exact live handle')
assert.equal(pc.captureTarget('missing'),null)
pc.interactionBusy=true;assert.equal(pc.activateTarget(pending,true,'DP-1'),false)
console.log('SB-04 production controller/shared activation: PASS')

// Shared menu adapter suppresses only sidebar saved grouping, never classic.
const { qmlMethods } = await import('./sidebar_interaction_fixture.mjs')
const { loadModel } = await import('./host_harness.mjs')
const m=interactionFixture(),mt=m.controller.captureTarget('ws')
const menu=qmlMethods('DockContextMenu.qml',{
  sidebarMode:true,workspaceContext:mt,windowActions:m.actions,
  DockMenuModel:loadModel('DockMenuModel'),DockModel:loadModel('DockModel'),
  WorkspaceGroupModel:loadModel('DockWorkspaceGroupModel'),
  externalTargetValidator:()=>m.controller.targetIsCurrent(mt)
})
assert.equal(typeof menu.workspaceContextIsCurrent,'function','sidebar workspace menus require live owner guards')
assert.equal(menu.workspaceContextIsCurrent(),true)
assert.equal(menu.representedWorkspaceGrouped(),false)
assert.equal(menu.canGroupTarget({}),false)
const records=menu.sidebarWorkspaceActions()
assert.ok(records.some(r=>r.command==='sidebar-pin-workspace'))
assert.ok(records.some(r=>r.command==='sidebar-open-monitors'))
m.workspaces[1].monitorID=0
assert.equal(menu.workspaceContextIsCurrent(),false,'workspace ownership changes invalidate the captured menu target')
console.log('SB-04 shared menu adapter: PASS')

// A menu action without a window target (e.g. Open New Window) still belongs to
// the originally captured row. Deletion/address reuse must veto it at dispatch.
let opened=0,dismissed=0
const staleMenu=qmlMethods('DockContextMenu.qml',{
  sidebarMode:true,externalTargetValidator:()=>false,
  menuSurface:null,interfaceAnimationsEnabled:false,Qt:{callLater(){}},
  visible:true,openNewWindow(){++opened}
})
staleMenu.setActiveMenuIndex=()=>{}
staleMenu.dismiss=()=>{++dismissed}
assert.equal(staleMenu.dispatchAction({kind:'action',enabled:true,command:'open-new'},0),false,
  'sidebar app-level actions must revalidate their captured row even without targetContext')
assert.equal(opened,0);assert.equal(dismissed,1)

// Focus dismissal targets a live captured handle, not whatever becomes focused
// later. Address reuse must not resurrect the old recipient.
const focus=interactionFixture(),fc=focus.controller
fc.rememberNavigationFocus();assert.equal(fc.focusReturnTarget.toplevel,focus.windows[1])
focus.actions.activeToplevel=focus.windows[0]
assert.equal(fc.releaseNavigationFocus(),true)
assert.deepEqual(focus.requests,['focuswindow address:0x2'])
focus.clear();fc.rememberNavigationFocus();focus.handles[0].address='0x77'
assert.equal(fc.releaseNavigationFocus(),false);assert.equal(focus.requests.length,0)
const hidden=interactionFixture(),hc=hidden.controller
hc.projection.rows[0].desktopId='editor'
const hiddenTarget=hc.captureTarget(hc.projection.rows[0].key)
hc.settings.hiddenApplications=['editor']
assert.equal(hc.activateTarget(hiddenTarget,true,'DP-1'),false)
assert.equal(hidden.requests.length+hidden.batches.length,0)
console.log('SB-04 stale menu, hidden app and exact focus-return guards: PASS')

// Entering the viewport by Tab restores the remembered row, but an already
// focused pointer-selected row and a popup must not be redirected.
const entryController={interactionBusy:false,focusedRowKey:'remembered',projection:{rows:[{key:'first',kind:'window'}]}}
let entryItem={activeFocus:false},entered=[]
const entryView=qmlMethods('DockSidebarViewport.qml',{controller:entryController,
  InteractionModel:loadModel('DockSidebarInteractionModel'),activeFocus:true})
entryView.currentDelegate=()=>entryItem
entryView.focusRow=key=>{entered.push(key);return true}
assert.equal(typeof entryView.enterNavigation,'function','keyboard re-entry must restore a focused row')
entryView.enterNavigation();assert.deepEqual(entered,['remembered'])
entered=[];entryItem.activeFocus=true;entryView.enterNavigation();assert.equal(entered.length,0)
entryItem=null;entryController.interactionBusy=true;entryView.enterNavigation();assert.equal(entered.length,0)

// Sidebar move destinations come from live native descriptors. An old menu
// record must not create a workspace that disappeared after the page opened.
const destination=interactionFixture(), dc=destination.controller
const moveMenu=qmlMethods('DockContextMenu.qml',{sidebarMode:true,windowActions:destination.actions,
  externalTargetValidator:()=>true,DockMenuModel:loadModel('DockMenuModel')})
moveMenu.targetIsValid=()=>true;moveMenu.dismiss=()=>{}
const moving=dc.captureTarget(dc.projection.rows[0].key)
destination.workspaces.splice(2,1)
assert.equal(moveMenu.moveTargetToWorkspace(moving,'id:3'),false,
  'a disappeared sidebar menu destination cannot be recreated by dispatch')
assert.equal(destination.requests.length+destination.batches.length,0)
