import QtQuick
import QtTest
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

  function makeCard() {
    testCase.toggleCount = 0
    var card = createTemporaryObject(cardFactory, testCase)
    verify(card !== null)
    waitForRendering(card)
    return card
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

  function test_header_drag_past_threshold_starts_without_toggle() {
    var card = makeCard()
    var header = findByName(card, "widget-card-header-drag")
    verify(header !== null)
    var started = 0
    card.dragStarted.connect(function() { started += 1 })
    mousePress(header, 8, header.height / 2, Qt.LeftButton)
    mouseMove(header, 8, header.height / 2 + 2, Qt.LeftButton)
    compare(started, 0)
    compare(card.dragActive, false)
    mouseMove(header, 8, header.height / 2 + card.dragThreshold + 1, Qt.LeftButton)
    compare(started, 1)
    compare(card.dragActive, true)
    compare(testCase.toggleCount, 0)
    mouseRelease(header, 8, header.height / 2 + card.dragThreshold + 1, Qt.LeftButton)
    compare(card.dragActive, false)
    compare(testCase.toggleCount, 0)
  }

  function test_rejected_drag_start_clears_drag_active() {
    var card = makeCard()
    var header = findByName(card, "widget-card-header-drag")
    verify(header !== null)
    card.dragStarted.connect(function() { card.dragActive = false })
    mousePress(header, 8, header.height / 2, Qt.LeftButton)
    mouseMove(header, 8, header.height / 2 + card.dragThreshold + 2, Qt.LeftButton)
    compare(card.dragActive, false)
    mouseRelease(header, 8, header.height / 2 + card.dragThreshold + 2, Qt.LeftButton)
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
