.pragma library

function normalizeShowTrash(value) {
  return typeof value === "boolean" ? value : true
}

function nonNegativeExtent(value) {
  var extent = Number(value)
  return isFinite(extent) ? Math.max(0, extent) : 0
}

function sectionMainExtent(showTrash, itemSize, separatorExtent) {
  if (!normalizeShowTrash(showTrash)) return 0
  return nonNegativeExtent(itemSize) + nonNegativeExtent(separatorExtent)
}

function shouldRefresh(showTrash, processRunning) {
  return normalizeShowTrash(showTrash) && processRunning !== true
}

function shouldDismissMenu(showTrash, menuVisible) {
  return !normalizeShowTrash(showTrash) && menuVisible === true
}
