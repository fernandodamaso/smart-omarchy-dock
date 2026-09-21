import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'

const root = new URL('../', import.meta.url)
const widgetDir = new URL('../components/widgets/', import.meta.url)

const display = [
  'WidgetText', 'WidgetBadge', 'WidgetStatus', 'WidgetDivider', 'WidgetSection',
  'WidgetList', 'WidgetListItem', 'WidgetChecklist', 'WidgetKeyValue', 'WidgetStat',
  'WidgetStatGrid', 'WidgetProgressBar', 'WidgetMeter', 'WidgetActivity',
  'WidgetSparkline', 'WidgetIconText',
]
const forms = [
  'WidgetFormField', 'WidgetTextInput', 'WidgetSearchInput', 'WidgetTextArea',
  'WidgetNumberInput', 'WidgetSelect', 'WidgetCheckbox', 'WidgetToggle',
  'WidgetRadioGroup', 'WidgetSegmentedControl',
]
const actions = ['WidgetButton', 'WidgetIconButton', 'WidgetButtonGroup']
const all = [...display, 'WidgetIcon', ...forms, ...actions, 'WidgetState']

function source(name) {
  return fs.readFileSync(new URL(`${name}.qml`, widgetDir), 'utf8')
}

test('complete reusable Widget kit is repository-owned', () => {
  for (const name of all) {
    const path = new URL(`${name}.qml`, widgetDir)
    assert.equal(fs.existsSync(path), true, `${name}.qml missing`)
    assert.ok(fs.statSync(path).size > 20, `${name}.qml unexpectedly empty`)
  }
})

test('WidgetIcon is the single flexible icon primitive', () => {
  const icon = source('WidgetIcon')
  assert.match(icon, /assets\/lucide\//)
  assert.match(icon, /property url source/)
  assert.match(icon, /preserveBrand/)
  assert.match(icon, /themeTinted/)
  for (const variant of ['plain', 'soft', 'outlined', 'tile'])
    assert.match(icon, new RegExp(`"${variant}"`))
  for (const token of ['xs', 'sm', 'lg', 'xl'])
    assert.match(icon, new RegExp(`"${token}"`))
  assert.match(icon, /Image\.Error/)
  assert.match(icon, /visible: root\.failed/)
})

test('forms own required keyboard and bounded interaction contracts', () => {
  assert.match(source('WidgetTextInput'), /echoMode: TextInput\.Normal/)
  assert.match(source('WidgetSearchInput'), /opacity: 0\.72/)
  assert.match(source('WidgetSelect'), /rightPadding: Style\.space\(32\)/)

  const toggle = source('WidgetToggle')
  assert.match(toggle, /Qt\.Key_Return/)
  assert.match(toggle, /Qt\.Key_Enter/)
  assert.match(toggle, /Qt\.Key_Space/)
  assert.match(toggle, /checkable: true/)

  const segmented = source('WidgetSegmentedControl')
  assert.match(segmented, /requiredSingleSelect/)
  assert.match(segmented, /normalizeSelection/)
  assert.match(segmented, /selectedValue = root\.valueOf\(root\.model\[0\]\)/)
})

test('buttons expose semantic variants and consistent state language', () => {
  const button = source('WidgetButton')
  for (const variant of ['primary', 'secondary', 'ghost', 'danger'])
    assert.match(button, new RegExp(`"${variant}"`))
  for (const state of ['disabled', 'pressed', 'focus', 'hover', 'idle'])
    assert.match(button, new RegExp(`"${state}"`))
  assert.match(button, /contentItem:\s*Item\s*\{[\s\S]*?implicitWidth:\s*content\.implicitWidth/,
    'button content keeps its natural size inside the control-managed content box')
  assert.match(button, /id:\s*content[\s\S]*?anchors\.centerIn:\s*parent/,
    'button labels and icons center inside their button by default')
  assert.match(button, /Qt\.darker\(root\.baseTone, 1\.14\)/)
  assert.match(button, /Qt\.darker\(root\.baseTone, 1\.28\)/)
  assert.match(button, /WidgetIcon/)
})

test('state and attention surfaces are semantic and reduced-motion safe', () => {
  const state = source('WidgetState')
  for (const kind of ['loading', 'empty', 'unavailable', 'error', 'stale'])
    assert.match(state, new RegExp(`"${kind}"`))
  assert.match(state, /!root\.reducedMotion/)
  assert.match(state, /RotationAnimation/)
  assert.match(state, /property int verticalPadding/)
  assert.match(state, /resolvedVerticalPadding/)
  assert.match(state, /Style\.space\(root\.compact \? 8 : 16\)/)

  const row = source('WidgetListItem')
  assert.match(row, /attention === "urgent"/)
  assert.match(row, /attention === "overdue"/)
  assert.match(row, /!root\.reducedMotion/)
  assert.match(row, /PauseAnimation/)
})

test('Demo actions-states opts compact WidgetState into larger vertical padding', () => {
  const demo = fs.readFileSync(
    new URL('../components/widgets/DemoWidgetActionsStatesBody.qml', import.meta.url), 'utf8')
  const states = [...demo.matchAll(/WidgetState\s*\{([^}]*)\}/g)].map(m => m[1])
  assert.equal(states.length, 5, 'demo exposes five framework state cards')
  for (const body of states) {
    assert.match(body, /compact:\s*true/)
    assert.match(body, /verticalPadding:\s*Style\.space\(16\)/)
  }
  const card = fs.readFileSync(new URL('../components/DockWidgetCard.qml', import.meta.url), 'utf8')
  assert.doesNotMatch(card, /verticalPadding/,
    'card framework state keeps WidgetState default padding')
})

test('Widget UI kit cannot acquire providers or write settings', () => {
  const forbidden = [
    /\bacquire\s*\(/, /IpcHandler/, /FileView/, /saveSetting\s*\(/,
    /sidebarWidgets/, /sidebarWidgetCollapsed/, /Process\s*\{/,
  ]
  for (const name of all) {
    const text = source(name)
    for (const pattern of forbidden)
      assert.doesNotMatch(text, pattern, `${name} crosses the presentation-only boundary: ${pattern}`)
  }
})

test('real FDM-973 card shell consumes the shared icon and state primitives', () => {
  const card = fs.readFileSync(new URL('../components/DockWidgetCard.qml', import.meta.url), 'utf8')
  assert.match(card, /import "widgets"/)
  assert.match(card, /WidgetIcon \{/)
  assert.match(card, /WidgetState \{/)
  assert.doesNotMatch(card, /DockLucideIcon \{/)
})

test('gallery is synthetic boilerplate and reuses DockWidgetCard', () => {
  const gallery = fs.readFileSync(new URL('./widget-gallery/WidgetGallery.qml', import.meta.url), 'utf8')
  assert.match(gallery, /DockWidgetCard \{/)
  assert.match(gallery, /galleryController/)
  assert.match(gallery, /data:image\/png;base64/)
  for (const kind of ['loading', 'empty', 'unavailable', 'error', 'stale'])
    assert.match(gallery, new RegExp(`kind: "${kind}"`))
  assert.match(gallery, /title: "Narrow width"/)
  assert.doesNotMatch(gallery, /https?:\/\//)
})

test('approved HTML design reference is preserved and linked', () => {
  const html = new URL('../docs/widget-gallery/reference/approved-widget-mockup.html', import.meta.url)
  assert.equal(fs.existsSync(html), true)
  assert.equal(fs.statSync(html).size, 111267)
  const htmlSource = fs.readFileSync(html, 'utf8')
  assert.match(htmlSource, /id="dock-directions"/)
  assert.match(htmlSource, /SmartDock direction A/)
  assert.match(htmlSource, /class="widgets-panel"/)
  assert.match(htmlSource, /class="widget-card"/)
  const docs = fs.readFileSync(new URL('../docs/SIDEBAR_WIDGETS.md', import.meta.url), 'utf8')
  assert.match(docs, /widget-gallery\/reference\/approved-widget-mockup\.html/)
  assert.match(docs, /tests\/widget-gallery\/WidgetGallery\.qml/)
})


test('expanded Widget cards do not retain the legacy 240px body cap', () => {
  const card = fs.readFileSync(new URL('../components/DockWidgetCard.qml', import.meta.url), 'utf8')
  assert.doesNotMatch(card, /Math\.min\(240,\s*implicitHeight\)/)
  assert.match(card, /height:\s*implicitHeight/)
})

test('Widget accordion cards drop the idle wrapper border and keep focus feedback', () => {
  const card = fs.readFileSync(new URL('../components/DockWidgetCard.qml', import.meta.url), 'utf8')
  assert.match(card, /Border\.none\(\)/)
  assert.match(card, /Border\.controlSpec\(\s*"focus"/)
  assert.doesNotMatch(card, /Border\.surfaceSpec\(\s*"widget-card"/)
  assert.match(card, /id:\s*collapseButton[\s\S]*?onClicked:\s*root\.toggleRequested\(\)/)
})

test('Widget card header drag starts after a threshold without single-click toggle', () => {
  const card = fs.readFileSync(new URL('../components/DockWidgetCard.qml', import.meta.url), 'utf8')
  assert.match(card, /id:\s*headerDrag/)
  assert.match(card, /objectName:\s*"widget-card-header-drag"/)
  assert.match(card, /preventStealing:\s*true/)
  assert.match(card, /dragThreshold/)
  assert.match(card, /onDoubleClicked:[\s\S]*toggleRequested/)
  assert.match(card, /property bool dragActive/)
  assert.doesNotMatch(card, /id:\s*headerToggle/)
  assert.doesNotMatch(card, /id:\s*dragMouse/)
  const area = fs.readFileSync(new URL('../components/DockSidebarWidgetArea.qml', import.meta.url), 'utf8')
  assert.match(area, /function syncDragFromController\(/)
  assert.match(area, /function onSurfaceInvalidated\(\)[\s\S]*finishDrag\(0,\s*0,\s*true\)/)
  assert.match(area, /if\s*\(!root\.beginDrag\([\s\S]*?dragActive\s*=\s*false/)
})

test('Widget semantic colors are centralized and theme-aware', () => {
  const palette = source('WidgetSemanticPalette')
  assert.match(palette, /Color\.background/)
  assert.match(palette, /Color\.accent/)
  assert.match(palette, /backgroundLuminance/)
  for (const semantic of ['danger', 'warning', 'success', 'info'])
    assert.match(palette, new RegExp('property color ' + semantic))

  const consumers = [
    'WidgetButton', 'WidgetBadge', 'WidgetStatus', 'WidgetProgressBar',
    'WidgetTextInput', 'WidgetTextArea', 'WidgetSelect', 'WidgetFormField',
    'WidgetActivity', 'WidgetListItem', 'WidgetState',
  ]
  const fixtureHex = /#(?:ff6b7a|f5bd36|48d5a4|ff5b6c|16ff6b7a|10ff6b7a|10f5bd36)/i
  for (const name of consumers) {
    const text = source(name)
    assert.match(text, /WidgetSemanticPalette/, name + ' must consume the shared semantic palette')
    assert.doesNotMatch(text, fixtureHex, name + ' must not embed fixture semantic colors')
  }
})

test('WidgetButtonGroup fills width and avoids non-wrapping Row/Flow shells', () => {
  const group = source('WidgetButtonGroup')
  assert.match(group, /width:\s*root\.width/)
  assert.match(group, /default property alias content:/)
  assert.match(group, /property int gap:/)
  assert.doesNotMatch(group, /\bRow\s*\{/)
  assert.doesNotMatch(group, /\bFlow\s*\{/)
})
