import QtQuick
import QtQuick.Controls as Controls
import QtTest

// Sidebar list scrollbar placement. Host qmltestrunner cannot load
// components/DockSidebarViewport.qml (Quickshell native plugin), so this
// fixture mirrors its scrollbar block; check_sidebar_scrollbar.sh pins the
// production source to the same shape.
//
// Why no anchors: under pragma ComponentBehavior: Bound, an inline ScrollBar
// assigned to ScrollBar.vertical evaluates anchor bindings without a valid
// parent/sibling context, so Qt drops them ("Cannot anchor to an item that
// isn't a parent or sibling") and the bar parks at x=0 — the LEFT edge of the
// sidebar. Geometry must be bound explicitly (x/y/width/height) instead.
TestCase {
  id: testCase
  name: "SidebarScrollbarSide"
  when: windowShown
  visible: true
  width: 320
  height: 240

  Component {
    id: delegateRect
    Rectangle {
      required property int index
      width: ListView.view ? ListView.view.width : 0
      height: 40
      color: index % 2 ? "#222222" : "#333333"
    }
  }

  // Mirrors components/DockSidebarViewport.qml: full-width list (no reserved
  // gutter) plus an attached vertical ScrollBar reparented to the viewport
  // root with explicit geometry, nudged scrollBarOutset past its right edge.
  Component {
    id: viewportScene
    FocusScope {
      id: root
      width: 292
      height: 600
      property bool panelCollapsed: false
      property string sidebarEdge: "left"
      readonly property real scrollGutter: 6
      readonly property real scrollBarOutset: panelCollapsed ? 4 : (sidebarEdge === "left" ? 4 : 10)
      property alias listAlias: list
      property alias barAlias: verticalScrollBar

      ListView {
        id: list
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        model: 100
        delegate: delegateRect

        Controls.ScrollBar.horizontal: Controls.ScrollBar {
          policy: Controls.ScrollBar.AlwaysOff
        }
        Controls.ScrollBar.vertical: Controls.ScrollBar {
          id: verticalScrollBar
          parent: root
          x: root.width - width + root.scrollBarOutset
          y: list.y
          width: root.scrollGutter
          height: list.height
          padding: 0
          policy: list.contentHeight > list.height
            ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff
          contentItem: Rectangle {
            implicitWidth: root.scrollGutter
            implicitHeight: 40
            radius: width / 2
            color: "white"
          }
          background: Item {
            implicitWidth: root.scrollGutter
          }
        }
      }
    }
  }

  function test_expandedLeftScrollbarClearsResizeHandle() {
    var scene = createTemporaryObject(viewportScene, testCase, {
      width: 292, panelCollapsed: false, sidebarEdge: "left"
    })
    verify(scene)
    waitForRendering(scene)
    // 320px panel - 14px symmetric viewport insets; the inner 8px is resize.
    var barRightInPanel = 14 + scene.barAlias.x + scene.barAlias.width
    compare(barRightInPanel <= 320 - 8, true,
      "left-sidebar scrollbar must not enter the resize hit area")
  }

  function test_collapsedScrollbarStaysInsidePanel() {
    var scene = createTemporaryObject(viewportScene, testCase, {
      width: 60, panelCollapsed: true, sidebarEdge: "left"
    })
    verify(scene)
    waitForRendering(scene)
    // 72px rail - 6px insets. The complete 6px bar must remain visible.
    var barRightInPanel = 6 + scene.barAlias.x + scene.barAlias.width
    compare(barRightInPanel <= 72, true,
      "collapsed scrollbar must not be clipped past the panel edge")
  }

  function test_rightSidebarUsesOuterEdgeRoom() {
    var scene = createTemporaryObject(viewportScene, testCase, {
      width: 292, panelCollapsed: false, sidebarEdge: "right"
    })
    verify(scene)
    waitForRendering(scene)
    compare(scene.scrollBarOutset, 10,
      "right sidebar keeps the larger nudge because its resize handle is on the left")
    compare(14 + scene.barAlias.x + scene.barAlias.width <= 320, true)
  }

  function test_scrollbarSitsPastTheRightEdge() {
    var scene = createTemporaryObject(viewportScene, testCase)
    verify(scene)
    waitForRendering(scene)
    var bar = scene.barAlias
    compare(bar.parent, scene, "bar is reparented out of the clipping list")
    compare(bar.x + bar.width, scene.width + scene.scrollBarOutset,
      "bar's right edge sits scrollBarOutset past the viewport's right edge")
    compare(bar.x, scene.listAlias.width - scene.scrollGutter + scene.scrollBarOutset,
      "full-width list keeps its content clear of the bar")
    compare(bar.y, 0)
    compare(bar.height, scene.listAlias.height)
    compare(bar.width, scene.scrollGutter)
  }

  function test_scrollbarFollowsViewportResize() {
    var scene = createTemporaryObject(viewportScene, testCase)
    verify(scene)
    waitForRendering(scene)
    scene.width = 200
    waitForRendering(scene)
    compare(scene.barAlias.x + scene.barAlias.width, 200 + scene.scrollBarOutset,
      "explicit geometry keeps the bar on the right after a sidebar resize")
  }
}
