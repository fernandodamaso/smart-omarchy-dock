pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "DockSidebarWidgetModel.js" as WidgetModel
import "DockSidebarModel.js" as SidebarModel

// Shared-scroll Widget section. Provider leases remain owned by the host controller;
// this item owns only card composition, picker state, drag targeting and popup views.
Item {
  id: root
  property var appearance: null
  required property var controller
  required property var panel
  required property var viewport
  required property real windowRowHeight

  // Keep the Herdr provider lease active while suppressing its fallback card
  // whenever live agents are already represented under associated window rows.
  readonly property var presentationWidgetIds: {
    var revision = root.controller.widgetRevision
    var ids = root.controller.widgetIds || []
    var view = root.controller.widgetView("herdr.agents")
    var snap = view && view.status === "ready" && view.data ? view.data : null
    var showHerdr = SidebarModel.herdrFallbackVisible(snap, root.controller.herdrAssociations)
    var out = []
    for (var i = 0; i < ids.length; ++i) {
      if (ids[i] === "herdr.agents" && !showHerdr) continue
      out.push(ids[i])
    }
    return out
  }

  readonly property bool sectionVisible: !panel.panelCollapsed && root.presentationWidgetIds.length > 0
  readonly property var popupWindow: popup
  readonly property var managerWindow: root.panel && root.panel.widgetManager
    ? root.panel.widgetManager.popupWindow : null
  readonly property var cards: cardRepeater
  property int anchorRevision: 0
  property string dragWidgetId: ""
  property int dragTargetSlot: -1
  property real dragSceneX: 0
  property real dragSceneY: 0

  implicitHeight: root.sectionVisible ? sectionColumn.implicitHeight + Style.space(8) : 0
  height: implicitHeight

  function ownsPopupAnchor() {
    var content = root.panel ? root.panel.contentItem : null
    if (!content) return false
    for (var item = root.controller.widgetPopupAnchor; item; item = item.parent) {
      if (item === content) return true
    }
    return false
  }

  function itemIntersectsViewport(item) {
    if (!item || !root.viewport || !root.viewport.visible || item.height <= 0) return false
    // Reading contentY makes this binding update while the shared sidebar scrolls.
    var scrollRevision = root.viewport.listView ? root.viewport.listView.contentY : 0
    var point = root.viewport.mapFromItem(item, 0, 0)
    return point.x + item.width > 0 && point.x < root.viewport.width
      && point.y + item.height > 0 && point.y < root.viewport.height
  }

  function anchorInsideViewport(anchor) {
    for (var item = anchor; item; item = item.parent) {
      if (item === root.viewport) return true
    }
    return false
  }

  function anchorOutsideViewport(anchor) {
    if (!root.anchorInsideViewport(anchor)) return false
    var point = root.viewport.mapFromItem(anchor, 0, 0)
    return point.y + anchor.height <= 0 || point.y >= root.viewport.height
  }

  function popupGeometryFor(anchor, wantedWidth, wantedHeight) {
    var point = anchor && panel.contentItem
      ? panel.contentItem.mapFromItem(anchor, 0, anchor.height / 2) : {y:0}
    return WidgetModel.popupGeometry(panel.screen ? panel.screen.width : 1,
      Math.min(panel.height, panel.screen ? panel.screen.height : panel.height), panel.width,
      controller.edge, point.y, wantedWidth, wantedHeight)
  }

  readonly property var popupGeometry: {
    var revision = root.anchorRevision
    return root.popupGeometryFor(root.ownsPopupAnchor()
      ? root.controller.widgetPopupAnchor : null, 320, 400)
  }

  function closePopup() {
    if (root.ownsPopupAnchor()) root.controller.closeWidgetPopup()
  }

  function openWidget(id, anchor) {
    root.closeManager()
    if (root.ownsPopupAnchor() && root.controller.widgetPopupId === id)
      root.closePopup()
    else
      root.controller.openWidgetPopup(id, anchor)
  }

  function openManager(anchor) {
    root.closePopup()
    if (!root.panel || typeof root.panel.openWidgetManager !== "function") return false
    return root.panel.openWidgetManager(anchor)
  }

  function closeManager() {
    if (root.panel && root.panel.widgetManager
        && typeof root.panel.widgetManager.close === "function")
      root.panel.widgetManager.close()
  }

  function updatePopupAnchor() {
    if (!root.controller.widgetPopupId || !root.ownsPopupAnchor()) return
    var anchor = root.controller.widgetPopupAnchor
    if (!anchor || !anchor.visible || !root.panel.visible) {
      root.closePopup()
      return
    }
    if (root.anchorOutsideViewport(anchor)) {
      root.closePopup()
      return
    }
    root.anchorRevision = (root.anchorRevision + 1) % 1000000000
    popup.anchor.updateAnchor()
  }

  function slotForSceneY(sceneY) {
    var point = cardColumn.mapFromItem(null, root.dragSceneX, sceneY)
    var count = root.presentationWidgetIds.length
    for (var i = 0; i < count; ++i) {
      var card = cardRepeater.itemAt(i)
      if (card && point.y < card.y + card.height / 2) return i
    }
    return count
  }

  function fullReorderSlot(presentationSlot) {
    var visibleIds = root.presentationWidgetIds || []
    var fullIds = root.controller.widgetIds || []
    if (visibleIds.length === fullIds.length) return presentationSlot
    if (presentationSlot >= visibleIds.length) {
      if (!visibleIds.length) return fullIds.length
      var last = fullIds.indexOf(visibleIds[visibleIds.length - 1])
      return last < 0 ? fullIds.length : last + 1
    }
    var target = fullIds.indexOf(visibleIds[presentationSlot])
    return target < 0 ? fullIds.length : target
  }

  function beginDrag(id, sceneX, sceneY) {
    root.closeManager()
    if (!root.controller.beginWidgetReorder(id)) return false
    root.dragWidgetId = id
    root.dragSceneX = sceneX
    root.dragSceneY = sceneY
    root.dragTargetSlot = root.slotForSceneY(sceneY)
    root.viewport.beginContentTailDrag(sceneX, sceneY)
    return true
  }

  function updateDrag(sceneX, sceneY) {
    if (!root.dragWidgetId) return
    root.dragSceneX = sceneX
    root.dragSceneY = sceneY
    root.viewport.updateContentTailDrag(sceneX, sceneY)
    root.dragTargetSlot = root.slotForSceneY(sceneY)
  }

  // Controller may cancel underneath us (surface/collapse). Clear local + autoscroll.
  function syncDragFromController() {
    if (root.controller.widgetDragId) return
    if (!root.dragWidgetId && root.viewport.contentTailDragPoint === null) return
    root.viewport.endContentTailDrag()
    root.dragWidgetId = ""
    root.dragTargetSlot = -1
  }

  function finishDrag(sceneX, sceneY, cancelled) {
    if (!root.dragWidgetId && !root.controller.widgetDragId) {
      root.viewport.endContentTailDrag()
      root.dragTargetSlot = -1
      return
    }
    if (!cancelled && root.dragWidgetId)
      root.updateDrag(sceneX, sceneY)
    var slot = root.dragTargetSlot
    root.dragWidgetId = ""
    root.dragTargetSlot = -1
    root.viewport.endContentTailDrag()
    root.controller.finishWidgetReorder(root.fullReorderSlot(slot), cancelled === true)
  }

  Column {
    id: sectionColumn
    visible: root.sectionVisible
    width: parent.width
    spacing: Style.space(6)

    Item {
      id: sectionHeader
      width: parent.width
      height: Style.space(32)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(5)
        anchors.verticalCenter: parent.verticalCenter
        text: "Widgets"
        textFormat: Text.PlainText
        color: Util.alpha(Color.foreground, 0.76)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Ui.Button {
        id: manageButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(28)
        text: "Add/Manage"
        tooltipText: "Add or manage Widgets"
        Accessible.role: Accessible.Button
        Accessible.name: tooltipText
        focusable: true
        onClicked: root.openManager(manageButton)
      }
    }

    Column {
      id: cardColumn
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        id: cardRepeater
        model: root.presentationWidgetIds

        delegate: DockWidgetCard {
          appearance: root.appearance
          id: widgetCard
          required property string modelData
          required property int index
          width: cardColumn.width
          controller: root.controller
          widgetId: modelData
          collapsed: root.controller.widgetCollapsedFor(modelData)
          interfaceAnimationsEnabled: root.controller.settings
            && root.controller.settings.interfaceAnimationsEnabled !== false
          presentationVisible: root.sectionVisible && root.panel.visible
            && root.itemIntersectsViewport(widgetCard)
          presentationClipItem: root.viewport
          presentationRevision: root.viewport && root.viewport.listView
            ? root.viewport.listView.contentY : 0
          dropBefore: root.dragWidgetId !== "" && root.dragTargetSlot === index
          dropAfter: root.dragWidgetId !== ""
            && root.dragTargetSlot === root.presentationWidgetIds.length
            && index === root.presentationWidgetIds.length - 1
          onToggleRequested: root.controller.toggleWidgetCollapsed(modelData)
          onRemoveRequested: root.controller.setWidgetEnabled(modelData, false)
          onDragStarted: function(sceneX, sceneY) {
            if (!root.beginDrag(modelData, sceneX, sceneY))
              dragActive = false
          }
          onDragMoved: function(sceneX, sceneY) { root.updateDrag(sceneX, sceneY) }
          onDragFinished: function(sceneX, sceneY, cancelled) {
            root.finishDrag(sceneX, sceneY, cancelled)
          }
        }
      }
    }
  }

  // Existing host-owned single Widget-specific popup. The retired overflow
  // sentinel is not used by the shared-scroll area.
  PopupWindow {
    id: popup
    visible: root.ownsPopupAnchor() && root.controller.widgetPopupId !== "" && root.panel.visible
    color: "transparent"
    grabFocus: false
    implicitWidth: root.popupGeometry.width
    implicitHeight: root.popupGeometry.height

    anchor {
      window: root.panel
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1
      onAnchoring: {
        popup.anchor.rect.x = Math.round(root.popupGeometry.x)
        popup.anchor.rect.y = Math.round(root.popupGeometry.y)
      }
    }

    onVisibleChanged: {
      if (!visible) root.closePopup()
      else Qt.callLater(root.updatePopupAnchor)
    }

    Ui.BorderSurface {
      id: popupSurface
      anchors.fill: parent
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
      clip: true

      Ui.Button {
        id: popupClose
        x: popupSurface.contentLeftInset
        y: popupSurface.contentTopInset
        width: Math.max(0, parent.width - popupSurface.contentLeftInset - popupSurface.contentRightInset)
        height: Math.min(root.windowRowHeight, popup.height)
        text: "Close"
        focusable: false
        Accessible.role: Accessible.Button
        Accessible.name: "Close Widget popup"
        onClicked: root.closePopup()
      }

      Flickable {
        id: popupScroll
        anchors.top: popupClose.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: popupSurface.contentLeftInset
        anchors.rightMargin: popupSurface.contentRightInset
        anchors.bottomMargin: popupSurface.contentBottomInset
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: popupContent.implicitHeight

        Column {
          id: popupContent
          width: parent.width

          DockSidebarWidgetView {
            id: popupView
            controller: root.controller
            widgetId: root.controller.widgetPopupId
            presentation: "popup"
            popupAnchor: root.controller.widgetPopupAnchor
            viewEnabled: popup.visible
            interfaceAnimationsEnabled: root.controller.settings
              && root.controller.settings.interfaceAnimationsEnabled !== false
            presentationVisible: popup.visible
            presentationClipItem: popupScroll
            presentationRevision: popupScroll.contentY
            width: parent.width
            height: implicitHeight
          }

          Text {
            visible: popup.visible && !popupView.hasView
            height: visible ? implicitHeight : 0
            width: parent.width
            text: popupView.snapshot ? String(popupView.snapshot.status || "unavailable") : "Unavailable"
            textFormat: Text.PlainText
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }

  Connections {
    target: root.viewport
    function onContentTailAutoScrolled() {
      if (root.dragWidgetId) root.updateDrag(root.dragSceneX, root.dragSceneY)
    }
  }

  Connections {
    target: root.viewport.listView
    function onContentYChanged() {
      Qt.callLater(root.updatePopupAnchor)
    }
  }

  Connections {
    target: root.controller
    function onWidgetAnchorChanged() { Qt.callLater(root.updatePopupAnchor) }
    function onWidgetDragIdChanged() { root.syncDragFromController() }
    function onSurfaceInvalidated() {
      root.closePopup()
      root.closeManager()
      if (root.dragWidgetId || root.controller.widgetDragId)
        root.finishDrag(0, 0, true)
    }
  }

  Connections {
    target: root.panel
    function onWidthChanged() {
      Qt.callLater(root.updatePopupAnchor)
    }
    function onHeightChanged() {
      Qt.callLater(root.updatePopupAnchor)
    }
    function onVisibleChanged() {
      if (!root.panel.visible) {
        root.closePopup()
        root.closeManager()
        if (root.dragWidgetId || root.controller.widgetDragId)
          root.finishDrag(0, 0, true)
      }
    }
    function onPanelCollapsedChanged() {
      if (root.panel.panelCollapsed) {
        root.closePopup()
        root.closeManager()
        if (root.dragWidgetId) root.finishDrag(0, 0, true)
      }
    }
  }

  onImplicitHeightChanged: {
    Qt.callLater(root.updatePopupAnchor)
  }

  Component.onDestruction: {
    if (root.dragWidgetId) root.finishDrag(0, 0, true)
    else root.viewport.endContentTailDrag()
    root.closePopup()
  }
}
