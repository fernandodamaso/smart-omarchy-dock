.pragma library

function headerRecord(id, text, subtitle) {
  return {
    kind: "header",
    id: String(id || ""),
    text: String(text || ""),
    subtitle: String(subtitle || "")
  }
}

function separatorRecord(id) {
  return { kind: "separator", id: String(id || "") }
}

function actionRecord(id, text, iconName, enabled, command, targetContext, extra) {
  var record = {
    kind: "action",
    id: String(id || ""),
    text: String(text || ""),
    iconName: String(iconName || ""),
    enabled: enabled !== false,
    command: String(command || ""),
    targetContext: targetContext || null,
    checked: false,
    submenu: false
  }

  var options = extra || ({})
  for (var key in options)
    record[key] = options[key]
  return record
}

function isFocusable(record) {
  return !!record && record.kind === "action" && record.enabled !== false
}

function firstEnabledIndex(records) {
  var values = records || []
  for (var i = 0; i < values.length; ++i) {
    if (isFocusable(values[i])) return i
  }
  return -1
}

function nextEnabledIndex(records, currentIndex, delta) {
  var values = records || []
  if (values.length === 0) return -1

  var direction = delta < 0 ? -1 : 1
  var start = Number.isInteger(currentIndex) ? currentIndex : -1
  if (start < 0 || start >= values.length)
    return direction > 0 ? firstEnabledIndex(values) : lastEnabledIndex(values)

  for (var i = start + direction;
       i >= 0 && i < values.length;
       i += direction) {
    if (isFocusable(values[i])) return i
  }
  return start
}

function lastEnabledIndex(records) {
  var values = records || []
  for (var i = values.length - 1; i >= 0; --i) {
    if (isFocusable(values[i])) return i
  }
  return -1
}

function cursorStep(records, currentIndex, delta, targetContext) {
  return {
    index: nextEnabledIndex(records, currentIndex, delta),
    targetContext: targetContext || null
  }
}

function targetIsCurrent(targetContext, currentToplevels, addressFor) {
  if (!targetContext || !targetContext.toplevel) return false

  var current = currentToplevels || []
  if (current.indexOf(targetContext.toplevel) < 0) return false

  var capturedAddress = String(targetContext.address || "")
  if (capturedAddress === "") return true
  if (typeof addressFor !== "function") return false

  return String(addressFor(targetContext.toplevel) || "") === capturedAddress
}

function initialPage(controlItem, targetCount, preferredTargetValid) {
  if (controlItem) return "controls"
  if (preferredTargetValid || Number(targetCount) === 1) return "window"
  return "app"
}

function contentYForRow(contentY, viewportHeight, rowY, rowHeight, contentHeight) {
  var current = Math.max(0, Number(contentY) || 0)
  var viewport = Math.max(0, Number(viewportHeight) || 0)
  var top = Math.max(0, Number(rowY) || 0)
  var height = Math.max(0, Number(rowHeight) || 0)
  var total = Math.max(0, Number(contentHeight) || 0)
  var maximum = Math.max(0, total - viewport)

  if (top < current)
    return Math.min(maximum, top)

  var bottom = top + height
  if (bottom > current + viewport)
    return Math.min(maximum, Math.max(0, bottom - viewport))

  return Math.min(maximum, current)
}
