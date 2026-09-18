import QtQuick
import "DockSidebarInteractionModel.js" as InteractionModel

// A focus-neutral key event adapter. Only explicit navigation is forwarded here;
// it never registers global shortcuts or takes focus when mapped/hovered.
Item {
  id: root
  required property var viewport

  function focusedRow() {
    var key = root.viewport.controller.focusedRowKey
    return key ? root.viewport.controller.rowsByKey[key] : null
  }

  function keyPressed(event) {
    if (event.key === Qt.Key_Escape) {
      root.viewport.cancelInputs("escape")
      root.viewport.dismissContextRequested()
      root.viewport.controller.clearAlertControl()
      root.viewport.controller.releaseNavigationFocus()
      event.accepted = true
      return
    }
    if (root.viewport.controller.interactionBusy) return

    var controller = root.viewport.controller
    var focusedKey = controller.focusedRowKey
    var alertOn = controller.alertControlKey !== ""
      && controller.alertControlKey === focusedKey

    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space) && alertOn) {
      event.accepted = controller.toggleRowActivityMute(focusedKey)
      return
    }

    var direction = event.key === Qt.Key_Down ? 1 : event.key === Qt.Key_Up ? -1
      : event.key === Qt.Key_Home ? "home" : event.key === Qt.Key_End ? "end"
      : event.key === Qt.Key_Backtab ? -1 : event.key === Qt.Key_Tab
        ? ((event.modifiers & Qt.ShiftModifier) ? -1 : 1) : 0

    if (direction === 1 || direction === -1) {
      var isTab = event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
      var row = root.focusedRow()
      if (isTab && direction === 1 && row && controller.rowHasAlertControl(row)
          && !alertOn) {
        controller.alertControlKey = focusedKey
        event.accepted = true
        return
      }
      if (isTab && direction === -1 && alertOn) {
        controller.clearAlertControl()
        event.accepted = true
        return
      }

      var next = InteractionModel.nextKey(root.viewport.visibleRows,
        focusedKey, direction)
      if (isTab && next === focusedKey) return

      controller.clearAlertControl()
      if (isTab && direction === -1 && next && next !== focusedKey) {
        var prevRow = controller.rowsByKey[next]
        if (prevRow && controller.rowHasAlertControl(prevRow))
          controller.alertControlKey = next
      }
      event.accepted = root.viewport.focusRow(next)
      return
    }

    if (direction === "home" || direction === "end") {
      controller.clearAlertControl()
      var jump = InteractionModel.nextKey(root.viewport.visibleRows,
        focusedKey, direction)
      event.accepted = root.viewport.focusRow(jump)
      return
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      event.accepted = root.viewport.activate(
        controller.captureTarget(focusedKey), false, "", Number(event.modifiers))
    } else if (event.key === Qt.Key_Space) {
      event.accepted = controller.toggleApplication(focusedKey)
    } else if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
      var target = controller.captureTarget(focusedKey)
      var item = root.viewport.currentDelegate()
      if (target && item) { root.viewport.contextRequested(target, item); event.accepted = true }
    }
  }

  Keys.onPressed: event => root.keyPressed(event)
}
