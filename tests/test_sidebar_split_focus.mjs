import assert from 'node:assert/strict'
import {loadModel} from './host_harness.mjs'
import {qmlMethods} from './sidebar_interaction_fixture.mjs'
const last={key:'last',kind:'browser-tab'}
const state=qmlMethods('DockSidebarViewport.qml',{
  InteractionModel:loadModel('DockSidebarInteractionModel'),visibleRows:[last],
  controller:{rowsByKey:{last},alertControlKey:'',clearAlertControl(){this.alertControlKey=''},
    rowHasAlertControl(row){return row.kind==='browser-tab'}},
})
let focused=''
state.focusRow=key=>{focused=key;return Boolean(key)}
assert.equal(state.focusLastRow(),true)
assert.equal(focused,'last')
assert.equal(state.controller.alertControlKey,'last','Backtab must enter the last alert stop')
last.kind='window'
state.focusLastRow()
assert.equal(state.controller.alertControlKey,'')
state.visibleRows=[]
assert.equal(state.focusLastRow(),false)
console.log('FDM-999 reverse pane boundary retains inline alert order: PASS')
