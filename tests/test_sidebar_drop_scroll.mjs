import assert from 'node:assert/strict'
import {qmlMethods, interactionFixture} from './sidebar_interaction_fixture.mjs'
import {loadModel} from './host_harness.mjs'
const x=interactionFixture(), c=x.controller
const g=c.registerDropSurface('DP-1'), other=c.registerDropSurface('HDMI-A-1')
const target=c.captureTarget(c.projection.rows[0].key)
c.beginRowDrag(target,'DP-1',g); c.updateRowDrag('ws3'); c.finishRowDrag('ws3')
x.handles[0].lastIpcObject.workspace={id:3};x.handles[0].lastIpcObject.monitor=0;c.evaluateDropOperation()
const queue=[]
function panel(connector,generation,collapsed=false) {
  const rows=Array.from({length:20},(_,i)=>({kind:'window',key:'other:'+i,workspaceIdentity:'id:3',monitorIdentity:'0'}))
  rows[18]={...rows[18],key:target.key,toplevel:target.toplevel,address:target.address}
  const restoreTimer={restart(){}}
  const list={count:20,height:90,contentHeight:600,originY:0,contentY:0,
    forceLayout(){},itemAtIndex:i=>({y:i*30,height:30}),indexAt:(_x,y)=>Math.floor(y/30),
    positionViewAtIndex(i){this.contentY=Math.min(i*30,510)}}
  const view=qmlMethods('DockSidebarViewport.qml', {controller:c,Qt:{callLater:fn=>queue.push(fn)},
    DockModel:loadModel('DockModel'), SidebarModel:loadModel('DockSidebarModel'), InteractionModel:loadModel('DockSidebarInteractionModel'),
    ListView:{Contain:1,Beginning:2},list,panelConnector:connector,panelCollapsed:collapsed,
    presentationVisible:true,dropSurfaceGeneration:generation,queuedDropToken:0,presentedDropToken:0,
    visibleRows:rows,sectionSpans:[],previousKeys:rows.map(r=>r.key),previousRowHeight:30,previousCollapsed:collapsed,
    previousContentHeight:0,previousHeightMap:'',rowHeight:30,scrollModeCollapsed:collapsed,
    pendingRestore:false,restoring:false,width:200,height:90,dropFlashKey:'',restoreTimer})
  restoreTimer.restart=()=>queue.push(()=>view.restoreAnchor())
  view.heightMap=()=>JSON.stringify(rows.map(r=>[r.key,30]));view.estimatedRowHeight=()=>30
  view.rowYAtIndex=i=>i*30;view.bumpSectionChrome=()=>{}
  view.clearDropPresentation=()=>{};view.showDropFeedback=()=>{}
  view.showDropFlash=(token,key)=>{view.presentedDropToken=token;view.dropFlashKey=key}
  return view
}
c.scrollStates={}
const origin=panel('DP-1',g),mirror=panel('HDMI-A-1',other,true)
c.writeScrollState('DP-1',false,{key:origin.visibleRows[0].key,offset:0},origin.previousKeys)
c.writeScrollState('HDMI-A-1',true,{key:mirror.visibleRows[2].key,offset:4},mirror.previousKeys)
mirror.list.contentY=64
const mirrorState=JSON.stringify(c.readScrollState('HDMI-A-1',true))
assert.equal(typeof origin.queueDropPresentation,'function')
origin.requestRestore(); origin.queueDropPresentation();mirror.queueDropPresentation()
let calls=0
while(queue.length) {queue.shift()(); assert.ok(++calls<20,'deferred work is bounded')}
// Completion of restoration is a production event, not an arbitrary retry loop.
origin.queueDropPresentation();while(queue.length)queue.shift()()
assert.equal(origin.dropFlashKey,target.key)
assert.ok(origin.list.contentY>0,'current offscreen row is contained after old anchor restoration')
const finalY=origin.list.contentY
origin.restoreAnchor();assert.equal(origin.list.contentY,finalY,'late restore uses the success anchor')
assert.equal(mirror.dropFlashKey,'');assert.equal(mirror.list.contentY,64)
assert.equal(JSON.stringify(c.readScrollState('HDMI-A-1',true)),mirrorState)
// Destroying/recreating the same connector does not inherit old callbacks.
origin.presentedDropToken=0;origin.queueDropPresentation();c.releaseDropSurface(g)
c.registerDropSurface('DP-1');while(queue.length)queue.shift()()
assert.equal(c.dropOperation,null)
console.log('R1 production origin-only deferred scroll/anchor guards: PASS')
