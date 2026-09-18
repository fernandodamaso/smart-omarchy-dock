pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "DockSidebarWidgetModel.js" as WidgetModel

// Sidebar-only composition. All snapshot/subscriptions survive in the host-owned
// controller. The footer and its popup never instantiate services or writers.
Item {
  id: root
  required property var controller
  required property var panel
  required property real availableContentHeight
  required property real windowRowHeight
  readonly property var layout: WidgetModel.footerLayout(availableContentHeight,
    windowRowHeight, controller.widgetIds.length, panel.panelCollapsed === true)
  readonly property bool overflowNeeded: layout.mode === "overflow"
  readonly property var popupWindow: popup
  readonly property var scrollView: footerScroll
  readonly property var slots: slotRepeater
  property int anchorRevision: 0
  property bool fromOverflow: false
  readonly property var popupGeometry: {
    var revision = root.anchorRevision
    var anchor = root.ownsPopupAnchor() ? controller.widgetPopupAnchor : null
    var point = anchor && panel.contentItem ? panel.contentItem.mapFromItem(anchor, 0, anchor.height / 2) : {y:0}
    // Panel height excludes other reserved surfaces (e.g. the untouched topbar).
    // Clamping within that height is stricter than screen-only vertical bounds.
    return WidgetModel.popupGeometry(panel.screen ? panel.screen.width : 1,
      Math.min(panel.height, panel.screen ? panel.screen.height : panel.height), panel.width,
      controller.edge, point.y, 320, 400)
  }
  implicitHeight: Math.min(layout.height, widgetColumn.implicitHeight)
  height: implicitHeight
  clip: true

  // The shared session has one anchor. Only the panel containing that anchor
  // may map, reposition or dismiss its popup, including during owner transfer.
  function ownsPopupAnchor() {
    var content = root.panel ? root.panel.contentItem : null
    if (!content) return false
    for (var item = root.controller.widgetPopupAnchor; item; item = item.parent) {
      if (item === content) return true
    }
    return false
  }
  function closePopup() {
    if (root.ownsPopupAnchor()) root.controller.closeWidgetPopup()
  }
  function statusText(view) {
    if (!view) return "Unavailable"
    return view.status === "ready" ? "Ready" : view.status === "loading" ? "Loading"
      : view.status === "error" ? "Error" : "Unavailable"
  }
  function labelFor(id, view) {
    return view && view.descriptor && view.descriptor.label ? String(view.descriptor.label) : id
  }
  function openWidget(id, anchor) {
    root.fromOverflow = false
    if (root.ownsPopupAnchor() && root.controller.widgetPopupId === id) root.closePopup()
    else root.controller.openWidgetPopup(id, anchor)
  }
  function openOverflow(anchor) {
    root.fromOverflow = true
    if (root.ownsPopupAnchor() && root.controller.widgetPopupId === "*") root.closePopup()
    else root.controller.openWidgetPopup("*", anchor)
  }
  function updatePopupAnchor() {
    if (!root.controller.widgetPopupId || !root.ownsPopupAnchor()) return
    var anchor = root.controller.widgetPopupAnchor
    if (!anchor || !anchor.visible || !root.panel.visible) { root.closePopup(); return }
    var ancestor = anchor
    while (ancestor && ancestor !== root) ancestor = ancestor.parent
    if (ancestor === root) {
      var point = root.mapFromItem(anchor, 0, 0)
      if (root.height <= 0 || point.y + anchor.height <= 0 || point.y >= root.height) {
        root.closePopup()
        return
      }
    }
    root.anchorRevision = (root.anchorRevision + 1) % 1000000000
    popup.anchor.updateAnchor()
  }

  Flickable {
    id: footerScroll
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    contentWidth: width
    contentHeight: widgetColumn.implicitHeight
    onContentYChanged: root.updatePopupAnchor()
    Column {
      id: widgetColumn
      width: footerScroll.width
      Repeater {
        id: slotRepeater
        model: root.controller.widgetIds
        delegate: Item {
          id: slot
          required property string modelData
          readonly property var snapshot: root.controller.widgetView(modelData)
          readonly property bool compact: root.layout.mode !== "expanded"
          readonly property var button: openButton
          readonly property var view: widgetView
          width: widgetColumn.width
          height: root.windowRowHeight + (compact ? 0 : Math.min(240, widgetView.implicitHeight))
          Ui.Button {
            id: openButton
            width: parent.width
            height: root.windowRowHeight
            text: slot.compact ? (widgetView.hasView ? "" : "…")
              : root.labelFor(slot.modelData,slot.snapshot) + " · " + root.statusText(slot.snapshot)
            tooltipText: root.labelFor(slot.modelData,slot.snapshot) + " · " + root.statusText(slot.snapshot)
            Accessible.role: Accessible.Button
            Accessible.name: tooltipText
            focusable: true
            enabled: !!slot.snapshot && slot.snapshot.registered && slot.snapshot.available
            onClicked: root.openWidget(slot.modelData, openButton)
          }
          DockSidebarWidgetView {
            id: widgetView
            controller: root.controller
            widgetId: slot.modelData
            presentation: slot.compact ? "compact" : "expanded"
            popupAnchor: openButton
            viewEnabled: root.layout.height > 0
            y: slot.compact ? 0 : openButton.height
            width: slot.width
            height: slot.compact ? root.windowRowHeight : Math.min(240, implicitHeight)
            // Compact views are read-only; the native button owns activation.
            enabled: !slot.compact
          }
          Component.onDestruction: {
            if (root.controller.widgetPopupAnchor === openButton) root.closePopup()
          }
        }
      }
    }
  }

  // One visible popup across mirrored panels, reused for slots and overflow.
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
      Row {
        id: popupHeader
        x: popupSurface.contentLeftInset
        y: popupSurface.contentTopInset
        width: Math.max(0, parent.width - popupSurface.contentLeftInset - popupSurface.contentRightInset)
        height: Math.min(root.windowRowHeight, popup.height)
        Ui.Button {
          visible: root.fromOverflow && root.controller.widgetPopupId !== "*"
          width: visible ? parent.width / 2 : 0
          height: parent.height
          text: "Back"
          focusable: false
          Accessible.role: Accessible.Button
          Accessible.name: "Back to widgets"
          onClicked: root.controller.openWidgetPopup("*", root.controller.widgetPopupAnchor)
        }
        Ui.Button {
          width: root.fromOverflow && root.controller.widgetPopupId !== "*" ? parent.width / 2 : parent.width
          height: parent.height
          text: "Close"
          focusable: false
          Accessible.role: Accessible.Button
          Accessible.name: "Close widget popup"
          onClicked: root.closePopup()
        }
      }
      Flickable {
        anchors.top: popupHeader.bottom
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
          Repeater {
            model: popup.visible && root.controller.widgetPopupId === "*" ? root.controller.widgetIds : []
            delegate: Ui.Button {
              required property string modelData
              readonly property var snapshot: root.controller.widgetView(modelData)
              width: popupContent.width
              height: root.windowRowHeight
              text: root.labelFor(modelData,snapshot) + " · " + root.statusText(snapshot)
              tooltipText: text
              enabled: !!snapshot && snapshot.registered && snapshot.available
              focusable: false
              Accessible.role: Accessible.Button
              Accessible.name: text
              onClicked: root.controller.openWidgetPopup(modelData,root.controller.widgetPopupAnchor)
            }
          }
          DockSidebarWidgetView {
            id: popupView
            controller: root.controller
            widgetId: root.controller.widgetPopupId
            presentation: "popup"
            popupAnchor: root.controller.widgetPopupAnchor
            viewEnabled: popup.visible && widgetId !== "*"
            width: parent.width
            height: implicitHeight
          }
          Text {
            visible: popup.visible && root.controller.widgetPopupId !== "*" && !popupView.hasView
            height: visible ? implicitHeight : 0
            width: parent.width
            text: root.statusText(popupView.snapshot)
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
    target: root.controller
    function onWidgetAnchorChanged() { Qt.callLater(root.updatePopupAnchor) }
    function onSurfaceInvalidated() { root.closePopup() }
  }
  Connections {
    target: root.panel
    function onWidthChanged() { Qt.callLater(root.updatePopupAnchor) }
    function onHeightChanged() { Qt.callLater(root.updatePopupAnchor) }
    function onVisibleChanged() { if (!root.panel.visible) root.closePopup() }
  }
  onHeightChanged: Qt.callLater(root.updatePopupAnchor)
  onLayoutChanged: root.closePopup()
  Component.onDestruction: root.closePopup()
}
