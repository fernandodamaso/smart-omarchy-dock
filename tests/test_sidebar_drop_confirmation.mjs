import assert from 'node:assert/strict'
import {interactionFixture} from './sidebar_interaction_fixture.mjs'

function begin(x, workspace=false) {
  const c=x.controller
  const generation=c.registerDropSurface('DP-1')
  c.dropClock=()=>1000
  const target=c.captureTarget(workspace?'ws':c.projection.rows[0].key)
  assert.equal(c.beginRowDrag(target,'DP-1',generation),true)
  return generation
}
function readback(x, identity='id:3', monitor=0) {
  x.handles[0].lastIpcObject.workspace=identity.startsWith('id:')?{id:Number(identity.slice(3))}:{name:identity.slice(5)}
  x.handles[0].lastIpcObject.monitor=monitor
}
for(const lua of [false,true]) {
  const x=interactionFixture(); x.Hyprland.usingLua=lua
  const target=x.controller.captureTarget(x.controller.projection.rows[0].key)
  assert.equal(typeof x.actions.moveCapturedWindowToNewWorkspaceResult,'function')
  const receipt=x.actions.moveCapturedWindowToNewWorkspaceResult(target,'DP-1')
  assert.equal(receipt.accepted,true)
  assert.equal(receipt.expectedWorkspace,'id:2')
  assert.equal(receipt.expectedMonitor,'id:0')
  assert.equal(receipt.members[0].toplevel,target.toplevel)
  assert.equal(receipt.members[0].address,'0x1')
  assert.equal(x.batches.length+x.requests.length,1,'receipt and dispatch share one allocation/submission')
  x.clear(); assert.equal(x.actions.moveCapturedWindowToNewWorkspace(target,'MISSING'),false)
  assert.equal(x.requests.length+x.batches.length,0)
  assert.equal(x.actions.moveCapturedWindowToNewWorkspace(target,'DP-1'),true)
  assert.equal(x.requests.length+x.batches.length,1,'legacy wrapper is boolean and delegates once')
}
{
  const x=interactionFixture(), c=x.controller; begin(x)
  c.updateRowDrag('ws3'); assert.equal(c.finishRowDrag('ws3'),true)
  assert.equal(c.dropOperation.state,'pending','dispatch is not confirmation')
  assert.equal(c.interactionBusy,false); assert.equal(c.dragSession,null)
  assert.equal(c.dropOperation.expectedMonitor,'id:0')
  readback(x,'id:3',1); c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'pending','workspace arrives before monitor readback')
  readback(x); c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'confirmed')
  const token=c.dropOperation.token; c.evaluateDropOperation()
  assert.equal(c.dropOperation.token,token)
  assert.equal(x.batches.length,1)
}
{
  const x=interactionFixture(), c=x.controller; begin(x)
  c.updateRowDrag('ws3'); c.finishRowDrag('ws3')
  const token=c.dropOperation.token
  c.dropClock=()=>2501; c.expireDropOperation(token)
  assert.equal(c.dropOperation.state,'unconfirmed')
  readback(x); c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'unconfirmed','late success cannot revive expired feedback')
  assert.equal(x.batches.length,1,'no retry or rollback')
  c.endDropOperation(token); assert.equal(c.dropOperation,null)
  c.evaluateDropOperation(); assert.equal(c.dropOperation,null)
}
for (const invalidate of [
  (x,g)=>x.controller.releaseDropSurface(g),
  x=>x.monitors.pop(),
  x=>x.windows.splice(0,1),
  x=>{const replacement={appId:'editor',title:'replacement'}; x.windows[0]=replacement; x.handles[0].wayland=replacement},
  x=>{x.handles[0].address='0x99'},
  x=>x.controller.invalidateDropOperation()
]) {
  const x=interactionFixture(), c=x.controller, g=begin(x)
  c.updateRowDrag('ws3'); c.finishRowDrag('ws3')
  const token=c.dropOperation.token; invalidate(x,g); readback(x); c.evaluateDropOperation()
  assert.equal(c.dropOperation,null,'invalid entity, token, origin or topology cannot confirm')
  c.expireDropOperation(token); assert.equal(c.dropOperation,null)
}
for(const invalidateDuringSubmission of [false,true]) {
  const x=interactionFixture(), c=x.controller, g=begin(x)
  const send=x.actions.dispatchRequests
  x.actions.dispatchRequests=requests=>{
    const result=send(requests); readback(x)
    if(invalidateDuringSubmission)c.releaseDropSurface(g)
    return result
  }
  c.updateRowDrag('ws3'); c.finishRowDrag('ws3')
  assert.equal(c.dropOperation?.state??null,invalidateDuringSubmission?null:'confirmed',
    'immediate readback catches synchronous submission without recreating an invalidated operation')
}
{
  const x=interactionFixture(), c=x.controller; begin(x)
  const key=c.InteractionModel.newWorkspaceFooterKey('id:0')
  c.updateRowDrag(key); c.finishRowDrag(key)
  assert.equal(c.dropOperation.expectedWorkspace,'id:2')
  readback(x,'id:2',0); x.workspaces.push({id:2,monitorID:1}); c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'pending')
  x.workspaces[x.workspaces.length-1].monitorID=0; c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'confirmed')
}
{
  const x=interactionFixture(), c=x.controller; x.Hyprland.usingLua=true; begin(x,true)
  c.updateRowDrag('mon'); c.finishRowDrag('mon')
  assert.equal(c.dropOperation.state,'pending')
  assert.equal(c.dropOperation.address,undefined)
  x.workspaces[1].monitorID=0; c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'confirmed')
}
{
  const x=interactionFixture(), c=x.controller; begin(x)
  x.actions.pinWindowToWorkspace(x.windows[0]); c.updateRowDrag('ws3')
  assert.equal(c.finishRowDrag('ws3'),false)
  assert.equal(c.dropOperation.state,'rejected'); assert.equal(x.batches.length,0)
  x.actions.unpinWindowFromWorkspace(x.windows[0]); begin(x); c.cancelRowDrag('escape')
  assert.equal(c.dropOperation.state,'cancelled'); assert.equal(x.batches.length,0)
}
{
  const x=interactionFixture(), c=x.controller; begin(x)
  x.actions.dispatchRequests=()=>{x.batches.push(['submitted-before-error']); throw Error('ambiguous transport')}
  c.updateRowDrag('ws3'); assert.equal(c.finishRowDrag('ws3'),false)
  assert.equal(c.dropOperation.state,'unconfirmed','an exception after possible submission never snaps back')
}
console.log('R1 exact-entity receipts, confirmation, deadline and operation lifecycle: PASS')

// Review regressions: replacement native handle, competing inventories and stale timers.
{
  const x=interactionFixture(),c=x.controller;begin(x);c.updateRowDrag('ws3');c.finishRowDrag('ws3')
  x.handles[0]={...x.handles[0],lastIpcObject:{workspace:{id:3},monitor:0}}
  c.evaluateDropOperation();assert.equal(c.dropOperation,null,'a replacement native handle does not inherit confirmation')
}
{
  const x=interactionFixture(),c=x.controller;begin(x);c.updateRowDrag('ws3');c.finishRowDrag('ws3')
  readback(x);x.workspaces.push({id:3,monitorID:1});c.evaluateDropOperation()
  assert.equal(c.dropOperation.state,'pending','conflicting workspace owners are unknown')
  x.workspaces.pop();x.handles.push({...x.handles[0],lastIpcObject:{workspace:{id:1},monitor:0}})
  c.evaluateDropOperation();assert.equal(c.dropOperation.state,'pending','inconsistent duplicate handle data is unknown')
}
{
  const x=interactionFixture(),c=x.controller;begin(x);c.updateRowDrag('ws3');c.finishRowDrag('ws3')
  const old=c.dropOperation.token;begin(x);c.updateRowDrag('ws3');c.finishRowDrag('ws3')
  const fresh=c.dropOperation.token;assert.notEqual(fresh,old)
  c.dropClock=()=>4000;c.expireDropOperation(old)
  assert.equal(c.dropOperation.token,fresh);assert.equal(c.dropOperation.state,'pending')
}
{
  const x=interactionFixture(),c=x.controller;begin(x)
  const key=c.InteractionModel.newWorkspaceFooterKey('id:0')
  c.updateRowDrag(key);x.workspaces.push({id:2,monitorID:0});c.finishRowDrag(key)
  assert.equal(c.dropOperation.expectedWorkspace,'id:4','receipt uses allocation at dispatch, not hover time')
}
{
  const x=interactionFixture(),c=x.controller;begin(x)
  x.actions.dispatchRequests=()=>{x.windows.splice(0,1);return true}
  c.updateRowDrag('ws3');c.finishRowDrag('ws3')
  assert.equal(c.dropOperation,null,'no submitting record survives synchronous source destruction')
}
