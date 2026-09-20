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

  const row = source('WidgetListItem')
  assert.match(row, /attention === "urgent"/)
  assert.match(row, /attention === "overdue"/)
  assert.match(row, /!root\.reducedMotion/)
  assert.match(row, /PauseAnimation/)
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
