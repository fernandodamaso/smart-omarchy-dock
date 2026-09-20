pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../components/widgets"
import "widget-gallery" as Gallery

TestCase {
  id: testCase
  name: "WidgetKit"
  when: windowShown
  visible: true
  width: 640
  height: 900

  function make(name, properties) {
    var component = Qt.createComponent(Qt.resolvedUrl("../components/widgets/" + name + ".qml"))
    compare(component.status, Component.Ready, component.errorString())
    var props = Object.assign({width: 140}, properties || {})
    var item = createTemporaryObject(component, testCase, props)
    verify(item !== null, name + " should create")
    verify(isFinite(item.width), name + " width must stay finite")
    verify(isFinite(item.implicitHeight), name + " implicit height must stay finite")
    return item
  }

  function test_every_primitive_loads_at_bounded_width() {
    var names = [
      "WidgetText", "WidgetBadge", "WidgetStatus", "WidgetIcon", "WidgetDivider",
      "WidgetSection", "WidgetList", "WidgetListItem", "WidgetChecklist",
      "WidgetKeyValue", "WidgetStat", "WidgetStatGrid", "WidgetProgressBar",
      "WidgetMeter", "WidgetActivity", "WidgetSparkline", "WidgetIconText",
      "WidgetFormField", "WidgetTextInput", "WidgetSearchInput", "WidgetTextArea",
      "WidgetNumberInput", "WidgetSelect", "WidgetCheckbox", "WidgetToggle",
      "WidgetRadioGroup", "WidgetSegmentedControl", "WidgetButton",
      "WidgetIconButton", "WidgetButtonGroup", "WidgetState"
    ]
    for (var i = 0; i < names.length; ++i) {
      var item = make(names[i], {width: 136})
      compare(item.width, 136)
    }
  }

  function test_icon_lucide_svg_raster_brand_and_fallback_paths() {
    var icon = make("WidgetIcon", {iconName: "move", width: 30, height: 30})
    compare(icon.usesLucide, true)
    tryVerify(function() { return icon.ready }, 2000)

    icon.iconName = ""
    icon.source = Qt.resolvedUrl("widget-gallery/reference/fixture.svg")
    tryVerify(function() { return icon.ready }, 2000)
    compare(icon.failed, false)

    icon.preserveBrand = true
    compare(icon.themeTinted, false)
    icon.source = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    tryVerify(function() { return icon.ready }, 2000)
    compare(icon.preserveBrand, true)

    icon.source = Qt.resolvedUrl("widget-gallery/reference/definitely-missing.png")
    tryVerify(function() { return icon.failed }, 2000)
  }

  function test_toggle_pointer_and_keyboard_contract() {
    var toggle = make("WidgetToggle", {x: 16, y: 16, width: 140, height: 30, checked: false})
    mouseClick(toggle, 12, 12, Qt.LeftButton)
    compare(toggle.checked, true)

    toggle.forceActiveFocus()
    verify(toggle.activeFocus)
    keyClick(Qt.Key_Space)
    compare(toggle.checked, false)
    keyClick(Qt.Key_Return)
    compare(toggle.checked, true)
  }

  function test_required_segmented_control_always_has_one_value() {
    var segmented = make("WidgetSegmentedControl", {
      width: 220,
      height: 32,
      model: ["today", "week"],
      selectedValue: ""
    })
    wait(0)
    compare(segmented.selectedValue, "today")
    verify(segmented.selectValue("week"))
    compare(segmented.selectedValue, "week")
    segmented.selectedValue = "missing"
    wait(0)
    compare(segmented.selectedValue, "today")
  }

  function test_button_states_include_focus_press_and_disabled() {
    var button = make("WidgetButton", {x: 16, y: 70, width: 120, height: 32, text: "Run", variant: "primary"})
    button.enabled = false
    compare(button.visualState, "disabled")
    button.enabled = true
    button.forceActiveFocus()
    compare(button.visualState, "focus")

    mousePress(button, 10, 10, Qt.LeftButton)
    compare(button.visualState, "pressed")
    mouseRelease(button, 10, 10, Qt.LeftButton)
    verify(button.visualState === "focus" || button.visualState === "hover" || button.visualState === "idle")
  }

  function test_states_and_attention_disable_nonessential_motion() {
    var state = make("WidgetState", {width: 180, kind: "loading", reducedMotion: false})
    compare(state.motionActive, true)
    state.reducedMotion = true
    compare(state.motionActive, false)

    var row = make("WidgetListItem", {
      width: 180,
      attention: "urgent",
      title: "Urgent item",
      reducedMotion: false
    })
    compare(row.motionActive, true)
    row.reducedMotion = true
    compare(row.motionActive, false)
    compare(row.attentionOffset, 0)
  }

  function test_gallery_loads_with_synthetic_data_only() {
    var component = Qt.createComponent(Qt.resolvedUrl("widget-gallery/WidgetGallery.qml"))
    compare(component.status, Component.Ready, component.errorString())
    var gallery = createTemporaryObject(component, testCase, {width: 360, height: 700})
    verify(gallery !== null)
    verify(gallery.contentHeight > gallery.height)
    gallery.reducedMotion = true
    compare(gallery.reducedMotion, true)
  }
}
