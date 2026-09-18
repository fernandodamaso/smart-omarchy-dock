import assert from 'node:assert/strict';
import fs from 'node:fs';
import { loadModel, plain, hostHarness, read } from './host_harness.mjs';
assert.ok(fs.existsSync(new URL('../components/DockSidebarWidgetModel.js', import.meta.url)),
  'SB-05 must provide the production widget model');
const Model = loadModel('DockSidebarWidgetModel');

// Test adapters implement the documented lease API. All lifecycle decisions,
// generation checks, geometry, validation and snapshots are production code.
function adapter(id, shared = false) {
  const counts = {acquire:0, release:0, start:0, stop:0, subscriptions:0, notifications:0};
  const callbacks = [];
  let running = shared, active = false;
  const provider = {privateContent:'never put task titles or credentials in diagnostics'};
  const descriptor = {id, label:id, available:true, status:'loading', revision:1,
    expandedView:{}, compactView:{}, popupView:{},
    acquire(owner) {
      assert.ok(owner);
      counts.acquire++;
      let released = false;
      return {provider,
        setActive(value, publish) {
          assert.ok(!released);
          active = value;
          if (value) {
            callbacks.push(publish);
            if (!running) { running = true; counts.start++; counts.subscriptions++; }
            publish({status:'ready', revision:1, data:{text:provider.privateContent}});
          } else if (running && !shared) {running = false; counts.stop++;}
        },
        release() {
          assert.ok(!released, 'lease released twice'); released = true; counts.release++;
          if (running && !shared) {running = false; counts.stop++;}
        }};
    }};
  return {descriptor, counts, callbacks, emit(value) { callbacks.at(-1)(value); },
    get active() {return active;}, get running() {return running;}};
}
const a = adapter('fixture.one'), b = adapter('fixture.two');
const registry = {'fixture.one':a.descriptor, 'fixture.two':b.descriptor};
assert.equal(Model.idsError([], []), '');
assert.equal(Model.idsError(['fixture.two','fixture.one'], Object.keys(registry)), '');
for (const value of [null, {}, 'fixture.one', [1], ['fixture.one','fixture.one'],
  ['unknown'], ['../evil.qml'], ['sh -c whoami'], ['constructor'], [' fixture.one']]) {
  assert.notEqual(Model.idsError(value, Object.keys(registry)), '', JSON.stringify(value));
}
assert.deepEqual(plain(Model.requestedIds(['future.clock','future.clock',4,'../x','fixture.one'])), ['future.clock','fixture.one']);
assert.deepEqual(plain(Model.requestedIds({})), []);
// QML settings/property maps often expose arrays as array-like objects.
assert.deepEqual(plain(Model.requestedIds({0:'future.clock',1:'fixture.one',length:2})),
  ['future.clock','fixture.one']);
assert.equal(Model.idsError({0:'fixture.one',length:1}, Object.keys(registry)), '');
let updates = 0;
const manager = Model.createManager(() => updates++);
const owner = {};
manager.reconcile([], registry, true, owner);
assert.deepEqual(plain(manager.ids()), []);
assert.equal(a.counts.acquire,0);
manager.reconcile(['future.clock','fixture.two','fixture.one'], registry, true, owner);
assert.deepEqual(plain(manager.ids()), ['future.clock','fixture.two','fixture.one']);
assert.equal(manager.view('future.clock').status,'unavailable');
assert.equal(manager.view('future.clock').available,false);
assert.equal(manager.view('fixture.one').status,'ready');
assert.equal(a.counts.acquire,1);
assert.equal(b.counts.acquire,1);
assert.equal(a.counts.subscriptions,1);
assert.equal(manager.view('fixture.one').data.text,'never put task titles or credentials in diagnostics');
const baseline = {...a.counts};
for (let i=0;i<40;i++) {
  // Reconcile the same enabled set as resize/collapse and host refresh would.
  manager.reconcile(['future.clock','fixture.two','fixture.one'], registry, true, owner);
  Model.footerLayout(300+i*9, 44+i%3, 3, i%2===0);
}
assert.deepEqual(a.counts,baseline,'presentation reflow must not restart providers');
const reordered = {'fixture.one':{...a.descriptor,revision:2},'fixture.two':b.descriptor};
manager.reconcile(['fixture.one','fixture.two','future.clock'],reordered,true,owner);
assert.equal(a.counts.acquire,1,'descriptor metadata refresh does not reacquire');
assert.deepEqual(plain(manager.ids()),['fixture.one','fixture.two','future.clock']);
a.emit({status:'error',revision:2,data:{token:'SECRET'},message:'SECRET'});
assert.equal(manager.view('fixture.one').status,'error');
assert.equal(manager.view('fixture.two').status,'ready');
a.emit({status:'ready',revision:3,data:{title:'PRIVATE WINDOW'}});
assert.equal(manager.view('fixture.one').status,'ready','provider recovers without restarting');
assert.equal(a.counts.acquire,1);
const beforeSuspend = a.callbacks.at(-1);
manager.reconcile(manager.ids(),registry,false,owner);
assert.equal(a.active,false);
assert.equal(a.counts.stop,1);
const suspendedUpdates = updates;
beforeSuspend({status:'ready',revision:900,data:{secret:'late while suspended'}});
assert.equal(updates,suspendedUpdates,'suspended callback cannot update views');
manager.reconcile(manager.ids(),registry,true,owner);
assert.equal(a.counts.acquire,1,'mode switch retains the enabled provider lease');
assert.equal(a.counts.subscriptions,2);
beforeSuspend({status:'error',revision:901});
assert.equal(manager.view('fixture.one').status,'ready','old activation callback is stale after resume');
const callback = a.callbacks.at(-1);
manager.reconcile(['fixture.two','future.clock'],registry,true,owner);
assert.equal(a.counts.release,1);
assert.equal(a.counts.stop,2);
assert.equal(manager.view('fixture.one'),null);
const afterRemoval = updates;
callback({status:'ready',revision:999,data:{secret:'late'}});
assert.equal(updates,afterRemoval);
manager.reconcile(['fixture.one','fixture.two'],registry,true,owner);
callback({status:'error',revision:1000});
assert.equal(manager.view('fixture.one').status,'ready','re-enabled ID is a new lifetime');
assert.equal(a.counts.acquire,2);
const d = plain(manager.diagnostics());
assert.ok(!JSON.stringify(d).match(/SECRET|PRIVATE|credentials|privateContent/));
assert.equal(d.rows.length,2);
assert.ok(d.counters.ignoredUpdates>=3);
manager.dispose();
manager.dispose();
assert.equal(a.counts.release,2);
assert.equal(b.counts.release,1);
assert.deepEqual(plain(manager.ids()),[]);

// Shared services belong to their owner. The sidebar may release its lease,
// never call stop/destroy on the provider or another consumer's subscription.
const shared = adapter('shared.provider',true);
const sharedManager = Model.createManager(() => {});
sharedManager.reconcile(['shared.provider'],{'shared.provider':shared.descriptor},true,owner);
sharedManager.reconcile([],{},false,owner);
assert.equal(shared.counts.release,1);
assert.equal(shared.counts.stop,0);
assert.ok(shared.running);

// Provider exceptions and malformed updates are contained without logging text.
let invalidRelease = 0;
const errors = Model.createManager(() => {});
const badRegistry = {
  broken:{id:'broken',available:true,acquire(){throw new Error('SECRET');}},
  invalid:{id:'invalid',available:true,acquire(){return {release(){invalidRelease++;}};}},
  'fixture.two':b.descriptor
};
errors.reconcile(['broken','invalid','fixture.two','unknown'],badRegistry,true,owner);
assert.equal(errors.view('broken').status,'error');
assert.equal(errors.view('invalid').status,'error');
assert.equal(invalidRelease,1);
assert.equal(errors.view('fixture.two').status,'ready');
assert.ok(!JSON.stringify(errors.diagnostics()).includes('SECRET'));
b.emit({status:'not-a-status',revision:Infinity,data:{}});
assert.equal(errors.view('fixture.two').status,'error');
b.emit({status:'ready',revision:4});
assert.equal(errors.view('fixture.two').status,'ready');
errors.viewFailed('fixture.two',errors.view('fixture.two'));
assert.equal(errors.view('fixture.two').status,'error');
errors.reconcile(['fixture.two'],{},true,owner);
assert.equal(errors.view('fixture.two').status,'unavailable');
assert.equal(b.counts.release,2,'registry removal releases once');
errors.dispose();
const many=Model.createManager(() => {});
many.reconcile(Array.from({length:100},(_,i)=>'unknown.'+i),{},true,owner);
assert.ok(many.diagnostics().rows.length<=32);
assert.equal(many.diagnostics().total,100);
many.dispose();

// Exact parent formula, large type, low heights and no disabled footer gap.
for (const h of [0,20,80,120,180,240,360,720,1080,4096]) {
  for (const row of [44,60,96,160]) for (const collapsed of [false,true]) {
    const f=Model.footerLayout(h,row,3,collapsed);
    const cap=Math.min(240,Math.floor(.3*h),Math.max(0,h-2*row));
    assert.equal(f.cap,cap);
    assert.ok(f.height>=0 && f.height<=cap);
    if (cap<row) { assert.equal(f.mode,'overflow'); assert.equal(f.height,0); }
    else assert.equal(f.mode,collapsed || cap<2*row ? 'compact':'expanded');
    assert.equal(Model.footerLayout(h,row,0,collapsed).height,0);
    assert.equal(Model.footerLayout(h,row,0,collapsed).mode,'none');
  }
}
assert.equal(Model.footerLayout(1080,44,2,false).height,240);
for (const edge of ['left','right']) for (const screenW of [48,120,720,1920]) {
  for (const screenH of [80,300,1080]) for (const panelW of [56,320]) {
    const panel=Math.min(panelW,screenW);
    const g=Model.popupGeometry(screenW,screenH,panel,edge,screenH-5,320,400);
    assert.ok(g.width>0 && g.height>0);
    assert.ok(g.screenX>=0 && g.screenX+g.width<=screenW);
    assert.ok(g.y>=0 && g.y+g.height<=screenH);
    if (screenW>panel+8) {
      if (edge==='left') assert.ok(g.x>=panel);
      else assert.ok(g.x+g.width<=0);
    }
  }
}
// A deferred view error from an old instance/revision cannot poison recovery.
{
  const fixture=adapter("fixture.one");
  const manager=Model.createManager(()=>{});
  const descriptors={'fixture.one':fixture.descriptor};
  manager.reconcile(['fixture.one'],descriptors,true,{});
  const old=manager.view('fixture.one');
  manager.reconcile([],descriptors,true,{});
  manager.reconcile(['fixture.one'],descriptors,true,{});
  manager.viewFailed('fixture.one',old);
  assert.notEqual(manager.view('fixture.one').errorCode,'view-error');
  manager.dispose();
}
// Actual config/host command methods, not a reimplemented write transport.
const h=hostHarness({sidebarWidgets:['future.clock'],extensionData:{preserve:true}});
assert.deepEqual(h.request('config.get',{key:'sidebarWidgets'}).data.settings.sidebarWidgets,['future.clock']);
assert.equal(h.request('config.apply',{patch:{sidebarWidgets:['fixture.one']}}).ok,false);
assert.equal(h.request('config.apply',{patch:{sidebarWidgets:[]}}).ok,true);
assert.deepEqual(h.request('config.get',{key:'sidebarWidgets'}).data.settings.sidebarWidgets,[]);
const controllerSource=read('components/DockSidebarController.qml');
assert.match(controllerSource,/SidebarWidgetModel\.createManager/,'the actual host-owned controller must create the manager');
assert.match(controllerSource,/widgetManager\.dispose\(/,'the host must clean up leases');
assert.match(read('DockHost.qml'),/widgetRegistry: root\.sidebarWidgetRegistry/,'production registry supplied by host, not settings');
console.log('SB-05 registry, leases/generations, errors, bounded geometry and host config: PASS');
