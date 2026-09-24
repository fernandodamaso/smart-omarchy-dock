import QtQuick

// A view consumes a snapshot, never a provider lease. The reusable loader also
// gives pure-Qt tests a real production component without mocking an Omarchy UI.
Item {
  id: root
  required property var controller
  required property string widgetId
  property string presentation: "expanded"
  property bool viewEnabled: true
  property bool interfaceAnimationsEnabled: true
  property bool presentationVisible: true
  property Item presentationClipItem: null
  property real presentationRevision: 0
  property Item popupAnchor: root
  readonly property var snapshot: controller.widgetView(widgetId)
  readonly property var factory: {
    if (!viewEnabled || !snapshot || !snapshot.active || snapshot.status !== "ready" || !snapshot.descriptor) return null
    return snapshot.descriptor[presentation + "View"] || null
  }
  readonly property url sourceUrl: {
    if (!viewEnabled || !snapshot || !snapshot.active || snapshot.status !== "ready" || !snapshot.descriptor) return ""
    return snapshot.descriptor[presentation + "Source"] || ""
  }
  readonly property bool hasView: loader.status === Loader.Ready && loader.item !== null
  readonly property var loadedItem: loader.item
  readonly property var widgetContext: ({
    id: widgetId,
    status: snapshot ? snapshot.status : "unavailable",
    revision: snapshot ? snapshot.revision : 0,
    data: snapshot ? snapshot.data : null,
    provider: snapshot ? snapshot.provider : null,
    presentation: presentation,
    // Internal presentation metadata only: views may stop visual timers when
    // animations are disabled or their rendered rows are clipped/offscreen.
    interfaceAnimationsEnabled: root.interfaceAnimationsEnabled,
    presentationVisible: root.presentationVisible && root.visible && root.viewEnabled,
    presentationClipItem: root.presentationClipItem,
    presentationRevision: root.presentationRevision,
    // Host-owned association map for filtering matched sessions out of the
    // Herdr fallback view. Delegates must not acquire a second lease.
    herdrAssociations: controller.herdrAssociations,
    openPopup: function() { return root.controller.openWidgetPopup(root.widgetId, root.popupAnchor) },
    closePopup: function() { root.controller.closeWidgetPopup() }
  })
  implicitHeight: hasView && isFinite(loader.item.implicitHeight) ? Math.max(0, loader.item.implicitHeight) : 0
  clip: true

  Loader {
    id: loader
    anchors.fill: parent
    sourceComponent: root.sourceUrl.toString() === "" ? root.factory : null
    source: root.factory ? "" : root.sourceUrl
    onLoaded: {
      try {
        if (typeof item.widgetContext === "undefined") throw new Error("Missing widgetContext")
        item.widgetContext = Qt.binding(function() { return root.widgetContext })
      } catch (error) {
        // Do not log provider exceptions or view data; defer unloading the item
        // until its creation signal returns, and capture this exact widget ID.
        var id = root.widgetId
        var expected = root.snapshot
        var owner = root.controller
        Qt.callLater(function() {
          if (owner && typeof owner.widgetViewFailed === "function") owner.widgetViewFailed(id, expected)
        })
      }
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        var id = root.widgetId
        var expected = root.snapshot
        var owner = root.controller
        Qt.callLater(function() {
          if (owner && typeof owner.widgetViewFailed === "function") owner.widgetViewFailed(id, expected)
        })
      }
    }
  }
}
