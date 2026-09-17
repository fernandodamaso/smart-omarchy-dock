.pragma library

// Geometry is supplied by the actual clipped ListView delegates. Indices are
// never action identities, and offscreen/utility/footer rectangles are not hits.
function contains(rect, point) {
  return !!rect && !!point && isFinite(point.x) && isFinite(point.y)
    && rect.width > 0 && rect.height > 0
    && point.x >= rect.x && point.x < rect.x + rect.width
    && point.y >= rect.y && point.y < rect.y + rect.height
}

function hitTarget(point, hits, viewport, sourceKind) {
  if (!contains(viewport, point)) return ""
  for (var i = 0; i < (hits || []).length; ++i) {
    var hit = hits[i]
    if (!contains(hit, point)) continue
    if (sourceKind === "workspace")
      return hit.kind === "monitor" && hit.monitorIdentity ? hit.key : ""
    return ["workspace", "application", "window"].indexOf(hit.kind) >= 0
      && hit.workspaceIdentity ? hit.key : ""
  }
  return ""
}

function autoScrollStep(y, height) {
  if (!isFinite(y) || height <= 0 || y < 0 || y >= height) return 0
  var band = Math.min(32, height / 3)
  if (y < band) return -Math.ceil(12 * (1 - y / band))
  if (y > height - band) return Math.ceil(12 * (1 - (height - y) / band))
  return 0
}

function focusable(row) {
  return !!row && ["workspace", "application", "window", "launcher"].indexOf(row.kind) >= 0
}

function nextKey(rows, key, direction) {
  var keys = (rows || []).filter(focusable).map(function(row) { return row.key })
  if (!keys.length) return ""
  if (direction === "home") return keys[0]
  if (direction === "end") return keys[keys.length - 1]
  var index = keys.indexOf(key)
  if (index < 0) return direction < 0 ? keys[keys.length - 1] : keys[0]
  return keys[Math.max(0, Math.min(keys.length - 1, index + (direction < 0 ? -1 : 1)))]
}
