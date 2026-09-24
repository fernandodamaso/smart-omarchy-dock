import QtQuick
import QtTest
import qs.Commons
import "../components"

TestCase {
  id: testCase
  name: "DockWidgetCard"
  when: windowShown
  visible: true
  width: 360
  height: 240

  property int toggleCount: 0

  QtObject {
    id: testAppearance
    property color monitorFill: "#343747"
    property color workspaceHoverFill: "#484c60"
    property real cardRadius: 2
  }

  function init() {
    testAppearance.monitorFill = "#343747"
    testAppearance.workspaceHoverFill = "#484c60"
    testAppearance.cardRadius = 2
    mouseMove(testCase, 350, 230)
  }


  QtObject {
    id: mockController
    property var herdrAssociations: ({})
    function widgetView(id) {
      return {
        descriptor: { id: id, label: "Demo Widget", iconName: "layout-grid" },
        data: { count: 0 },
        status: "unavailable",
        active: false,
        revision: 0,
        provider: null
      }
    }
    function openWidgetPopup() { return false }
    function closeWidgetPopup() {}
  }

  Component {
    id: cardFactory
    DockWidgetCard {
      width: 280
      controller: mockController
      widgetId: "demo.widget"
      collapsed: false
      onToggleRequested: testCase.toggleCount += 1
    }
  }

  function findByName(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    if (node.children) {
      for (var i = 0; i < node.children.length; ++i) {
        var hit = findByName(node.children[i], name)
        if (hit) return hit
      }
    }
    return null
  }

  // Qt Quick Text quantizes alpha to 8 bits; JS colors may retain 16-bit precision.
  function compareColor(actual, expected) {
    for (var channel of ["r", "g", "b", "a"])
      fuzzyCompare(actual[channel], expected[channel], 1 / 255)
  }

  function makeCard() {
    testCase.toggleCount = 0
    var card = createTemporaryObject(cardFactory, testCase)
    verify(card !== null)
    waitForRendering(card)
    return card
  }

  function test_optional_appearance_matches_sidebar_fallback() {
    var card = makeCard()
    compare(card.appearance, null)
    var surface = findByName(card, "widget-card-surface")
    compare(surface.color, Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035)))
    compare(surface.radius, Math.min(3, Style.cornerRadius))
  }

  function test_appearance_fill_and_radius_remain_live_on_hover_and_focus() {
    var card = makeCard()
    card.appearance = testAppearance
    var surface = findByName(card, "widget-card-surface")
    compare(surface.color, testAppearance.monitorFill)
    compare(surface.radius, 2)
    mouseMove(card, 20, 15)
    compare(surface.color, testAppearance.monitorFill)
    card.forceActiveFocus()
    compare(surface.color, testAppearance.monitorFill)
    verify(surface.border.width > 0)
    testAppearance.monitorFill = "#a2b3c4"
    testAppearance.cardRadius = 0
    compare(surface.color, testAppearance.monitorFill)
    compare(surface.radius, 0)
    card.appearance = null
    compare(surface.color, Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035)))
    compare(surface.radius, Math.min(3, Style.cornerRadius))
  }

  function test_title_matches_monitor_hierarchy_and_divider_is_subtle() {
    var card = makeCard()
    var title = findByName(card, "widget-card-title")
    compare(title.font.pixelSize, Style.font.body)
    compare(title.font.weight, Font.DemiBold)
    compare(title.color, Color.foreground)
    card.collapsed = true
    compareColor(title.color, Util.alpha(Color.foreground, 0.85))
    card.forceActiveFocus()
    compare(title.color, Color.foreground)
    var divider = findByName(card, "widget-card-divider")
    verify(divider !== null)
    compare(divider.height, 1)
    compareColor(divider.color, Util.alpha(Color.foreground, 0.07))
  }

  function test_idle_wrapper_has_no_border_and_focus_restores_feedback() {
    var card = makeCard()
    var surface = findByName(card, "widget-card-surface")
    verify(surface !== null)
    compare(surface.border.width, 0)

    card.forceActiveFocus()
    verify(card.activeFocus)
    verify(surface.border.width > 0)
  }

  function test_title_single_click_does_not_toggle() {
    var card = makeCard()
    var title = findByName(card, "widget-card-title")
    verify(title !== null)
    mouseClick(title, title.width / 2, title.height / 2, Qt.LeftButton)
    compare(testCase.toggleCount, 0)
  }

  function test_title_double_click_toggles_exactly_once() {
    var card = makeCard()
    var title = findByName(card, "widget-card-title")
    verify(title !== null)
    mouseDoubleClickSequence(title, title.width / 2, title.height / 2, Qt.LeftButton)
    compare(testCase.toggleCount, 1)
  }

  function test_title_drag_past_threshold_does_not_start_reorder() {
    var card = makeCard()
    var title = findByName(card, "widget-card-title")
    verify(title !== null)
    var started = 0
    card.dragStarted.connect(function() { started += 1 })
    mousePress(title, title.width / 2, title.height / 2, Qt.LeftButton)
    mouseMove(title, title.width / 2, title.height / 2 + card.dragThreshold + 8, Qt.LeftButton)
    mouseRelease(title, title.width / 2, title.height / 2 + card.dragThreshold + 8, Qt.LeftButton)
    compare(started, 0)
    compare(card.dragActive, false)
    compare(testCase.toggleCount, 0)
  }

  function test_drag_handle_past_threshold_starts_without_toggle() {
    var card = makeCard()
    var handle = findByName(card, "widget-card-drag-handle")
    verify(handle !== null)
    var started = 0
    card.dragStarted.connect(function() { started += 1 })
    mousePress(handle, 8, handle.height / 2, Qt.LeftButton)
    mouseMove(handle, 8, handle.height / 2 + 2, Qt.LeftButton)
    compare(started, 0)
    compare(card.dragActive, false)
    mouseMove(handle, 8, handle.height / 2 + card.dragThreshold + 1, Qt.LeftButton)
    compare(started, 1)
    compare(card.dragActive, true)
    compare(testCase.toggleCount, 0)
    mouseRelease(handle, 8, handle.height / 2 + card.dragThreshold + 1, Qt.LeftButton)
    compare(card.dragActive, false)
    compare(testCase.toggleCount, 0)
  }

  function test_rejected_drag_start_clears_drag_active() {
    var card = makeCard()
    var handle = findByName(card, "widget-card-drag-handle")
    verify(handle !== null)
    card.dragStarted.connect(function() { card.dragActive = false })
    mousePress(handle, 8, handle.height / 2, Qt.LeftButton)
    mouseMove(handle, 8, handle.height / 2 + card.dragThreshold + 2, Qt.LeftButton)
    compare(card.dragActive, false)
    mouseRelease(handle, 8, handle.height / 2 + card.dragThreshold + 2, Qt.LeftButton)
    compare(testCase.toggleCount, 0)
  }

  function test_chevron_single_click_still_toggles() {
    var card = makeCard()
    var chevron = findByName(card, "widget-card-collapse")
    verify(chevron !== null)
    mouseClick(chevron, chevron.width / 2, chevron.height / 2, Qt.LeftButton)
    compare(testCase.toggleCount, 1)
  }

  function test_keyboard_return_enter_space_still_toggle() {
    var card = makeCard()
    card.forceActiveFocus()
    verify(card.activeFocus)
    keyClick(Qt.Key_Space)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Enter)
    compare(testCase.toggleCount, 3)
  }
}
