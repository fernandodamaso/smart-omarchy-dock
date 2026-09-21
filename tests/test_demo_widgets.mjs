import assert from 'node:assert/strict'
import fs from 'node:fs'
import test from 'node:test'

const root = new URL('../', import.meta.url)
const ids = ['demo.display', 'demo.lists', 'demo.inputs', 'demo.actions-states']

const read = path => fs.readFileSync(new URL('../' + path, import.meta.url), 'utf8')

test('production host registers the four source-owned demo Widgets', () => {
  const host = read('DockHost.qml')
  assert.match(host, /DockDemoWidgetRegistry\s*\{/)
  assert.match(host, /sidebarWidgetRegistry:\s*demoWidgetRegistry\.descriptors/)

  const registry = read('components/DockDemoWidgetRegistry.qml')
  for (const id of ids) assert.match(registry, new RegExp('"' + id.replace(/[.-]/g, '\\$&') + '"'))
  assert.match(registry, /publish\(\{status:"ready", revision:1/)
  assert.doesNotMatch(registry, /\bProcess\s*\{|\bFileView\s*\{|https?:\/\//)
})

test('demo Widgets are canonical defaults and schema-registered', () => {
  const defaults = JSON.parse(read('config/dock.json'))
  const schema = JSON.parse(read('config/settings-schema.json'))
  assert.deepEqual(defaults.sidebarWidgets, ids)
  assert.deepEqual(schema.settings.sidebarWidgets.registeredIds, ids)
})

test('each demo body uses widgetContext and the shared UI kit', () => {
  const expected = {
    'components/widgets/DemoWidgetDisplayBody.qml': ['WidgetStatus', 'WidgetStatGrid', 'WidgetMeter', 'WidgetSparkline'],
    'components/widgets/DemoWidgetListsBody.qml': ['WidgetListItem', 'WidgetChecklist', 'WidgetActivity'],
    'components/widgets/DemoWidgetInputsBody.qml': ['WidgetSearchInput', 'WidgetTextInput', 'WidgetNumberInput', 'WidgetSelect', 'WidgetTextArea', 'WidgetCheckbox', 'WidgetToggle', 'WidgetRadioGroup', 'WidgetSegmentedControl'],
    'components/widgets/DemoWidgetActionsStatesBody.qml': ['WidgetButtonGroup', 'WidgetButton', 'WidgetIconButton', 'WidgetState'],
  }
  for (const [path, names] of Object.entries(expected)) {
    const source = read(path)
    assert.match(source, /property var widgetContext:\s*\(\{\}\)/)
    for (const name of names) assert.match(source, new RegExp(name + '\\s*\\{'), path + ' should use ' + name)
    assert.doesNotMatch(source, /\bProcess\s*\{|\bFileView\s*\{|https?:\/\//)
  }
})

test('installer seeds an empty Widget selection once', () => {
  const installer = read('install.sh')
  assert.match(installer, /\.demo-widgets-seeded-v1/)
  assert.match(installer, /smartdock_seed_demo_widgets\.py/)
  const seeder = read('scripts/smartdock_seed_demo_widgets.py')
  for (const id of ids) assert.match(seeder, new RegExp('"' + id.replace(/[.-]/g, '\\$&') + '"'))
  assert.match(seeder, /if marker_path\.exists\(\)/)
})

test('all Lucide assets used by demo and Widget state controls are bundled', () => {
  for (const name of ['search','check','chevron-down','circle-alert','cloud-off','inbox','loader-circle','clock-3'])
    assert.equal(fs.existsSync(new URL('../assets/lucide/' + name + '.svg', import.meta.url)), true, name)
})
