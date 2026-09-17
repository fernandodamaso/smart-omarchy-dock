import assert from 'node:assert/strict'
import {hostHarness, plain} from './host_harness.mjs'

const initial = {
  presentationMode:'sidebar', sidebarExpandedWidth:320, sidebarCollapsed:false,
  pinned:['org.keep.App'], hiddenApplications:['org.hidden.App'],
  iconOverrides:{'org.keep.App':'file:///icons/keep.svg'},
  browserActivityMutedServices:['gmail'], extensionData:{unknown:{keep:true}},
  position:'bottom', workspaceLayout:'grouped', workspaceGroups:[{desktopId:'org.keep.App',workspace:'id:2'}]
}
const h = hostHarness(initial)
const baselineUnknown = plain(h.host.settings.extensionData)

// A stale-field request is rejected before a write and reports the current
// host value so a view can revert without replaying its drag-start snapshot.
let intent = h.host.saveSettingIntent('sidebarExpandedWidth',360,300)
assert.equal(intent.accepted,false)
assert.equal(intent.pending,false)
assert.equal(intent.reply.error.code,'E_STALE')
assert.equal(intent.reply.data.currentValue,320)
assert.equal(h.writes.length,0)
assert.equal(h.host.settings.sidebarExpandedWidth,320)

// Preflight busy is also a rejection. It is different from an accepted write
// whose persistence is still in flight.
h.host.settingsWriteState='saving'
intent = h.host.saveSettingIntent('sidebarExpandedWidth',360,320)
assert.equal(intent.accepted,false)
assert.equal(intent.pending,false)
assert.equal(intent.reply.error.code,'E_BUSY')
assert.equal(intent.reply.data.applied,false)
assert.equal(h.writes.length,0)
h.host.settingsWriteState='idle'

h.fault.defer=true
intent = h.host.saveSettingIntent('sidebarExpandedWidth',360,320)
assert.equal(intent.accepted,true)
assert.equal(intent.pending,true)
assert.equal(intent.reply.error.code,'E_BUSY')
assert.equal(intent.reply.data.applied,true)
assert.equal(h.host.settings.sidebarExpandedWidth,360)
assert.equal(h.writes.length,1)

// Generic E_BUSY while that accepted write is saving must never cause replay.
const busyAgain = h.host.saveSettingIntent('sidebarExpandedWidth',380,360)
assert.equal(busyAgain.accepted,false)
assert.equal(busyAgain.reply.error.code,'E_BUSY')
assert.equal(h.writes.length,1)

h.fault.defer=false
h.host.settingsSaved()
assert.equal(h.host.settingsPersisted,true)

// Interleave an unrelated CLI patch after the resize commit. The sole writer
// must preserve both the resize and unrelated/unknown settings.
let cli = h.request('config.apply',{patch:{sidebarCollapsed:true}})
assert.equal(cli.ok,true)
assert.equal(h.host.settings.sidebarExpandedWidth,360)
assert.deepEqual(plain(h.host.settings.extensionData),baselineUnknown)
assert.deepEqual(plain(h.host.settings.pinned),initial.pinned)
assert.deepEqual(plain(h.host.settings.iconOverrides),initial.iconOverrides)
assert.deepEqual(plain(h.host.settings.browserActivityMutedServices),initial.browserActivityMutedServices)
assert.deepEqual(plain(h.host.settings.workspaceGroups),initial.workspaceGroups)

// Persistence failure still means the live intent was accepted. It stays live,
// is marked unsaved, and retry persists the latest snapshot rather than replaying
// the original patch.
h.fault.save=true
intent = h.host.saveSettingIntent('sidebarExpandedWidth',400,360)
assert.equal(intent.accepted,true)
assert.equal(intent.pending,false)
assert.equal(intent.reply.error.code,'E_PERSISTENCE')
assert.equal(intent.reply.data.applied,true)
assert.equal(h.host.settings.sidebarExpandedWidth,400)
assert.equal(h.host.settingsPersisted,false)

h.fault.save=false
const writesBeforeRetry = h.writes.length
const retry = h.host.retrySettings()
assert.equal(retry.ok,true)
assert.equal(h.writes.length,writesBeforeRetry+1,'explicit retry writes the current snapshot once')
assert.equal(h.host.settingsPersisted,true)
const retried = JSON.parse(h.host.settingsLoadedText)
assert.equal(retried.sidebarExpandedWidth,400)
assert.equal(retried.sidebarCollapsed,true)
assert.deepEqual(plain(retried.extensionData),baselineUnknown)

// A later accepted field is part of the same current snapshot; no stale width
// patch or unrelated-key rollback is allowed.
cli = h.request('config.apply',{patch:{sidebarCollapsed:false}})
assert.equal(cli.ok,true)
assert.equal(h.host.settings.sidebarExpandedWidth,400)
assert.equal(h.host.settings.sidebarCollapsed,false)
assert.deepEqual(plain(h.host.settings.extensionData),baselineUnknown)

// Failed readback must not manufacture durability or revert the live snapshot.
h.host.settingsReloadPending=true
h.host.settingsLoadFailed(5)
assert.equal(h.host.settingsPersisted,false)
assert.equal(h.host.settings.sidebarExpandedWidth,400)
assert.deepEqual(plain(h.host.settings.extensionData),baselineUnknown)

// Restart from the latest persisted text proves the writer stored the complete
// current snapshot, not a drag-start snapshot.
const persisted = JSON.parse(h.host.settingsLoadedText || h.writes.at(-1))
const restarted = hostHarness(persisted)
assert.equal(restarted.host.settings.sidebarExpandedWidth,400)
assert.equal(restarted.host.settings.sidebarCollapsed,false)
assert.deepEqual(plain(restarted.host.settings.extensionData),baselineUnknown)
assert.deepEqual(plain(restarted.host.settings.iconOverrides),initial.iconOverrides)

console.log('SB-03 conflict-safe host preference intents, retry and latest-snapshot persistence: PASS')
