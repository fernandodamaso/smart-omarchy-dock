from pathlib import Path
import os
import subprocess


def edit(path, old, new):
    p=Path(path);s=p.read_text()
    if old not in s: raise RuntimeError('Missing source in '+path+': '+old[:80])
    p.write_text(s.replace(old,new))

p=Path('tests/tst_sidebarkeyboard.qml');s=p.read_text()
s=s.replace('    function focusRow(key)', '    function focusPaneBoundary(backwards) { events.push("boundary:"+backwards); return !backwards }\n    function focusRow(key)')
s=s[:s.rfind('}')]+'''
  function test_tab_leaves_last_row_after_alert_control() {
    actionController.projection={rows:[{key:"last",kind:"browser-tab"}]}
    actionController.focusedRowKey="last"
    keyClick(Qt.Key_Tab);compare(actionController.alertControlKey,"last")
    keyClick(Qt.Key_Tab);compare(events[events.length-1],"boundary:false")
    compare(actionController.alertControlKey,"")
  }
}
''';p.write_text(s)
p=Path('tests/tst_sidebarsplitscroll.qml');s=p.read_text()
s=s[:s.rfind('}')]+'''
  function test_header_font_reflow_updates_geometry_without_scroll() {
    var f=build();settle(f)
    var anchor=named(f.area.cards.itemAt(0),"widget-card-header")
    verify(f.controller.openWidgetPopup("fixture.one",anchor));wait(30)
    var revision=f.area.layoutRevision,updates=f.area.popupWindow.anchor.updates,y=f.area.scrollView.contentY
    named(f.area,"widget-section-label").font.pixelSize=40
    tryVerify(function(){return f.area.layoutRevision>revision})
    verify(f.area.popupWindow.anchor.updates>updates)
    compare(f.area.scrollView.contentY,y)
  }
}
''';p.write_text(s)
runner=os.environ.get('QMLTESTRUNNER','/usr/lib/qt6/bin/qmltestrunner')
evidence=Path(os.environ.get('RUNNER_TEMP','/tmp'))/'evidence';evidence.mkdir(exist_ok=True)
for file,case,diagnostic in [
    ('tst_sidebarkeyboard.qml','SidebarKeyboard::test_tab_leaves_last_row_after_alert_control','boundary:false'),
    ('tst_sidebarsplitscroll.qml','SidebarSplitScroll::test_header_font_reflow_updates_geometry_without_scroll','function returned false'),
]:
    result=subprocess.run([runner,'-input','tests/'+file,'-import','components','-import','tests/qml-imports',case],
                          capture_output=True,text=True,timeout=30)
    (evidence/(file+'.red.log')).write_text(result.stdout+result.stderr)
    if result.returncode==0 or diagnostic not in result.stdout:
        raise RuntimeError('Expected targeted failing regression for '+case+'\n'+result.stdout+result.stderr)
edit('components/DockSidebarKeyboard.qml', '      if (isTab && next === focusedKey) return\n\n', '')
edit('components/DockSidebarKeyboard.qml', '      if (isTab && next === focusedKey) {\n',
     '      if (isTab && next === focusedKey) {\n        controller.clearAlertControl()\n')
edit('components/DockSidebarWidgetArea.qml', '  onPanelOriginChanged: geometryTimer.restart()\n',
     '  onNaturalWidgetHeaderHeightChanged: root.requestLayout()\n  onPanelOriginChanged: geometryTimer.restart()\n')

# Backtab should enter the last inline alert stop, not skip it and jump to the
# underlying row. Execute the production boundary method with focus endpoints.
Path('tests/test_sidebar_split_focus.mjs').write_text('''import assert from 'node:assert/strict'
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
''')
r=subprocess.run(['node','tests/test_sidebar_split_focus.mjs'],capture_output=True,text=True)
(evidence/'reverse-boundary-red.log').write_text(r.stdout+r.stderr)
if r.returncode==0 or 'Backtab must enter the last alert stop' not in r.stderr:
    raise RuntimeError('Reverse boundary test did not reproduce the expected gap')
edit('components/DockSidebarViewport.qml', '''  function focusLastRow() {
    return root.focusRow(InteractionModel.nextKey(root.visibleRows, "", "end"))
  }''', '''  function focusLastRow() {
    var key = InteractionModel.nextKey(root.visibleRows, "", "end")
    if (!key) return false
    root.controller.clearAlertControl()
    var row = root.controller.rowsByKey[key]
    if (row && root.controller.rowHasAlertControl(row)) root.controller.alertControlKey = key
    return root.focusRow(key)
  }''')
edit('components/DockSidebar.qml', "  // the viewport surface owns only the list's blank tail. Only one can be\n",
     '  // the middle-region surface owns only residual blank space. Only one can be\n')
p=Path('docs/FDM-999-split-scroll-handoff.md');s=p.read_text()
s=s.replace('Review was inline;', '''Final review added direct key-event coverage for leaving the last hierarchy
alert stop: an old early return had bypassed the new pane handler. Removing it
and clearing the outgoing alert stop restores forward traversal; Backtab now
enters the last alert stop before the row. A targeted header-font reflow test
also reproduced a missing geometry notification while outer height/contentY
were unchanged; observing natural header demand now schedules restoration and
popup geometry. All three regressions fail before their corrections.

Review was inline;''');p.write_text(s)
