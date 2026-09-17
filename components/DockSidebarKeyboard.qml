import QtQuick
import "DockSidebarInteractionModel.js" as InteractionModel

// A focus-neutral key event adapter. Only explicit navigation is forwarded here;
// it never registers global shortcuts or takes focus when mapped/hovered.
Item {
  id: root
  required property var viewport
  function keyPressed(event) {
    if (event.key === Qt.Key_Escape) {
      root.viewport.cancelInputs("escape")
      root.viewport.dismissContextRequested()
      root.viewport.controller.releaseNavigationFocus()
      event.accepted = true
      return
    }
    if (root.viewport.controller.interactionBusy) return
    var direction = event.key === Qt.Key_Down ? 1 : event.key === Qt.Key_Up ? -1
      : event.key === Qt.Key_Home ? "home" : event.key === Qt.Key_End ? "end"
      : event.key === Qt.Key_Backtab ? -1 : event.key === Qt.Key_Tab
        ? ((event.modifiers & Qt.ShiftModifier) ? -1 : 1) : 0
    if (direction) {
      var next = InteractionModel.nextKey(root.viewport.controller.projection.rows,
        root.viewport.controller.focusedRowKey, direction)
      if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
          && next === root.viewport.controller.focusedRowKey) return
      event.accepted = root.viewport.focusRow(next)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      event.accepted = root.viewport.activate(root.viewport.controller.captureTarget(root.viewport.controller.focusedRowKey),
        false, "", Number(event.modifiers))
    } else if (event.key === Qt.Key_Space) {
      event.accepted = root.viewport.controller.toggleApplication(root.viewport.controller.focusedRowKey)
    } else if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
      var target = root.viewport.controller.captureTarget(root.viewport.controller.focusedRowKey)
      var item = root.viewport.currentDelegate()
      if (target && item) { root.viewport.contextRequested(target, item); event.accepted = true }
    }
  }

  Keys.onPressed: event => root.keyPressed(event)
}
