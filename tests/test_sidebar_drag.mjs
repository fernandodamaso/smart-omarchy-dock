import assert from 'node:assert/strict'
import { loadModel } from './host_harness.mjs'
import { interactionFixture } from './sidebar_interaction_fixture.mjs'
const f=interactionFixture(),c=f.controller
assert.equal(typeof c.beginRowDrag,'function','SB-04 must own one live, cancellable sidebar drag session')
const target=c.captureTarget(c.projection.rows[0].key)
assert.equal(c.beginRowDrag(target),true)
assert.equal(c.interactionBusy,true)
assert.equal(c.beginRowDrag(target),false)
assert.equal(c.updateRowDrag('ws3'),true)
assert.equal(f.requests.length+f.batches.length,0,'hover has no dispatch')
assert.equal(c.finishRowDrag('ws3'),true)
assert.deepEqual(f.requests,['movetoworkspacesilent 3,address:0x1'])
assert.equal(c.interactionBusy,false);assert.equal(c.finishRowDrag('ws3'),false,'release is consumed once')
f.clear();c.beginRowDrag(target);c.updateRowDrag('ws3');c.cancelRowDrag('escape');c.finishRowDrag('ws3')
assert.equal(f.requests.length,0)
f.clear();c.beginRowDrag(target);f.actions.pinWindowToWorkspace(f.windows[0]);assert.equal(c.finishRowDrag('ws3'),false)
assert.equal(f.requests.length,0);f.actions.unpinWindowFromWorkspace(f.windows[0])
c.beginRowDrag(target);f.handles[0].lastIpcObject.workspace={id:3};assert.equal(c.finishRowDrag('ws3'),false,'source move cancels frozen drag')
f.handles[0].lastIpcObject.workspace={name:'Design work'}
c.beginRowDrag(target);c.updateRowDrag('ws3');f.workspaces[2].monitorID=1
assert.equal(c.finishRowDrag('ws3'),false,'hover target ownership is revalidated');f.workspaces[2].monitorID=0
f.Hyprland.usingLua=true
c.beginRowDrag(c.captureTarget('ws'));assert.equal(c.finishRowDrag('mon'),true)
assert.deepEqual(f.requests,['hl.dsp.workspace.move({ workspace = "name:Design work", monitor = "0" })'])
f.clear();c.beginRowDrag(c.captureTarget('ws'));f.actions.pinWorkspaceToMonitor('name:Design work')
assert.equal(c.finishRowDrag('mon'),false);assert.equal(f.requests.length,0)
// Geometry helper consumes actual mapped/clipped row rectangles, not index guesses.
const model=loadModel('DockSidebarInteractionModel')
const viewport={x:0,y:0,width:100,height:100}
const hits=[{key:'off',kind:'workspace',workspaceIdentity:'id:9',x:0,y:-50,width:100,height:25},
 {key:'workspace',kind:'window',workspaceIdentity:'id:3',x:0,y:-10,width:100,height:40},
 {key:'monitor',kind:'monitor',monitorIdentity:'0',x:0,y:30,width:100,height:30},
 {key:'unknown',kind:'window',workspaceIdentity:'',x:0,y:60,width:100,height:40}]
assert.equal(model.hitTarget({x:2,y:2},hits,viewport,'window'),'workspace')
for(const point of [{x:2,y:-1},{x:2,y:31},{x:2,y:70},{x:2,y:101},{x:101,y:2}])
 assert.equal(model.hitTarget(point,hits,viewport,'window'),'')
assert.equal(model.hitTarget({x:2,y:31},hits,viewport,'workspace'),'monitor')
assert.equal(model.hitTarget({x:2,y:2},hits,viewport,'workspace'),'')
assert.equal(model.autoScrollStep(-1,100),0);assert.equal(model.autoScrollStep(101,100),0)
assert.ok(model.autoScrollStep(2,100)<0);assert.ok(model.autoScrollStep(98,100)>0)
assert.equal(model.autoScrollStep(50,100),0)
console.log('SB-04 production drag policy and clipped hit geometry: PASS')

// Source validity remains live while visual projection order is frozen.
for (const invalidate of [
  f=>f.windows.splice(0,1),
  f=>{f.handles[0].address='0x9'},
  f=>{f.monitors.pop()},
  f=>{f.controller.selectedConnector='HDMI-A-1'},
  f=>{f.controller.mode='classic'}
]) {
  const x=interactionFixture(),xc=x.controller
  assert.equal(xc.beginRowDrag(xc.captureTarget(xc.projection.rows[0].key)),true)
  xc.updateRowDrag('ws3');invalidate(x)
  assert.equal(xc.finishRowDrag('ws3'),false)
  assert.equal(x.requests.length+x.batches.length,0)
  assert.equal(xc.interactionBusy,false)
}
const busy=interactionFixture();busy.controller.resizeActive=true
assert.equal(busy.controller.beginRowDrag(busy.controller.captureTarget(busy.controller.projection.rows[0].key)),false)
const mf=interactionFixture(),mc=mf.controller
mf.actions.minimizedOrigins={'0x1':{workspace:'name:Design work',monitor:'id:1'}}
mf.handles[0].lastIpcObject.workspace={name:'special:smartdock-minimized'}
assert.equal(mc.beginRowDrag(mc.captureTarget(mc.projection.rows[0].key)),true)
assert.equal(mc.finishRowDrag('ws3'),true)
assert.equal(mf.requests.length,0,'moving a minimized window updates its origin without showing it')
assert.equal(mf.actions.minimizedOrigins['0x1'].workspace,'3')
console.log('SB-04 drag closure/address/topology/mode/resize/minimized regressions: PASS')
