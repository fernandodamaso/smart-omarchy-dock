import assert from 'node:assert/strict'
import {hostHarness, plain, read, loadModel} from './host_harness.mjs'
const initial = {position:'bottom', workspaceLayout:'grouped', workspaceMonitorScope:'current-monitor',
  workspaceGroups:[{desktopId:'chrome',workspace:'id:3'}], windowScope:'workspace-monitor',
  reserveSpace:false, autoHide:true, showPreviews:true, iconSize:64, magnification:1.5,
  pinned:['chrome'], extensionData:{keep:['opaque']}, clickAction:'launch', scrollAction:'cycle-windows'}
const h = hostHarness(initial)
const before = plain(h.host.settings)
const dry = h.request('config.apply',{patch:{presentationMode:'sidebar'},dryRun:true})
assert.equal(dry.ok,true)
assert.equal(dry.data.presentation.mode,'sidebar')
assert.equal(h.host.settings.presentationMode,'classic')
for (const [key, value] of Object.entries({presentationMode:'classic', sidebarEdge:'left',
  sidebarMonitor:'', sidebarExpandedWidth:320, sidebarCollapsed:false})) {
  assert.equal(h.defaults[key], value, 'sidebar defaults are bundled, not a second writer')
  assert.equal(h.request('config.schema',{key}).data.settings[key].default, value)
}
for (const patch of [{presentationMode:'other'}, {sidebarEdge:'top'}, {sidebarCollapsed:'true'},
    {sidebarExpandedWidth:239}, {sidebarExpandedWidth:481}, {sidebarExpandedWidth:320.5},
    {sidebarExpandedWidth:'320'}, {sidebarMonitor:3}, {sidebarMonitor:'DP-1\n'},
    {sidebarMonitor:'DP-1\u0085'}]) {
  assert.equal(h.request('config.apply',{patch}).ok, false, JSON.stringify(patch))
}
assert.equal(h.writes.length, 0)
h.host.connectedScreens = [{name:'DP-1',width:720,height:1280}]
h.host.hyprMonitors = [{name:'DP-1',id:1,lastIpcObject:{name:'DP-1',id:1,x:0,y:0,scale:1.5}}]
let reply = h.request('config.apply',{patch:{presentationMode:'sidebar',sidebarMonitor:'NOT-CONNECTED'}})
assert.equal(reply.ok,true)
assert.equal(reply.data.persisted,true)
let effective = h.request('config.get',{effective:true})
for (const key of Object.keys(initial)) assert.deepEqual(plain(h.host.settings[key]), initial[key])
assert.equal(effective.data.settings.windowScope,'all')
assert.equal(effective.data.settings.reserveSpace,true)
assert.equal(effective.data.settings.autoHide,false)
assert.equal(effective.data.settings.showPreviews,false)
assert.equal(effective.data.settings.sidebarExpandedWidth,288)
assert.equal(effective.data.settings.sidebarMonitor,'DP-1')
assert.equal(effective.data.settings.iconSize,32)
assert.equal(effective.data.settings.clickAction,null)
assert.equal(effective.data.settings.scrollAction,null)
assert.ok(effective.data.presentation.inactiveClassicSettings.includes('workspaceGroups'))
assert.equal(effective.data.presentation.width,288)
assert.equal(h.host.settings.sidebarExpandedWidth,320)
assert.equal(h.host.settings.sidebarMonitor,'NOT-CONNECTED')
reply = h.host.saveSetting('sidebarCollapsed',true)
assert.equal(reply.ok,true)
assert.deepEqual(Array.from(reply.data.changedKeys),['sidebarCollapsed'])
assert.equal(h.request('status').data.presentation.width,56)
assert.equal(h.host.settings.sidebarExpandedWidth,320)
const writes = h.writes.length
h.fault.defer = true
h.host.saveSetting('sidebarCollapsed',false)
assert.equal(h.host.settings.sidebarCollapsed,false, 'accepted-but-saving retains live intent')
reply = h.host.saveSetting('sidebarCollapsed',true)
assert.equal(reply.ok,false)
assert.equal(h.host.settings.sidebarCollapsed,false, 'preflight busy cannot replay a stale intent')
assert.equal(h.writes.length,writes+1)
h.fault.defer=false
h.host.settingsSaved()
h.request('config.reset',{key:'sidebarMonitor'})
h.request('config.apply',{patch:{presentationMode:'classic'}})
for (const key of Object.keys(initial)) assert.deepEqual(plain(h.host.settings[key]),initial[key])
const model=loadModel('DockSidebarModel')
assert.equal(model.geometry(720,320,false).width,288)
const host=read('DockHost.qml')
assert.equal((host.match(/\n  DockWindowActions \{/g)||[]).length,1)
assert.equal((host.match(/\n  DockSidebarController \{/g)||[]).length,1)
assert.match(host,/id: presentationLoader/)
assert.match(host,/active: root.rendererReady/)
assert.match(host,/sourceComponent: root.rendererMode === "sidebar"/)
// Execute the actual renderer switch functions, with the unavailable QML Loader
// represented by its state only. Actual surfaces/delegates are tested by runtime/sidebar.qml.
h.host.rendererInitialized = true
h.host.rendererReady = true
h.host.rendererMode = 'classic'
h.host.rendererEdge = 'left'
h.host.rendererScreen = null
h.host.sidebarState = {selectedScreen:h.host.connectedScreens[0]}
h.host.settings = {...h.host.settings, sidebarEdge:'right'}
h.host.syncRenderer()
assert.equal(h.host.rendererReady,true,'inactive sidebar edge must not recreate classic docks')
h.host.settings = {...h.host.settings,presentationMode:'sidebar'}
h.host.syncRenderer()
assert.equal(h.host.rendererReady,false,'old renderer unloads before deferred creation')
assert.equal(h.host.rendererMode,'sidebar')
h.host.activateRenderer()
assert.equal(h.host.rendererReady,true)
h.host.sidebarState.selectedScreen=null
h.host.syncRenderer(); h.host.activateRenderer()
assert.equal(h.host.rendererReady,false,'zero screens creates no sidebar branch')
console.log('SB-02 typed configuration, requested/effective diagnostics and sole writer: PASS')
