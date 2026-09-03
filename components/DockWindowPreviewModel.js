.pragma library

function groupedPreviewMembers(candidates, liveToplevels) {
  var values = candidates || []
  var live = liveToplevels || []
  var members = []

  for (var i = 0; i < values.length; ++i) {
    var candidate = values[i]
    if (candidate && live.indexOf(candidate) >= 0)
      members.push(candidate)
  }

  return members.length >= 2 ? members : []
}

function previewViewport(screenWidth, screenHeight,
                         desiredWidth, desiredHeight, margin) {
  var width = Math.max(1, Number(screenWidth) || 1)
  var height = Math.max(1, Number(screenHeight) || 1)
  var inset = Math.max(0, Number(margin) || 0)
  var requestedWidth = Math.max(1, Number(desiredWidth) || 1)
  var requestedHeight = Math.max(1, Number(desiredHeight) || 1)

  return {
    width: Math.min(requestedWidth, Math.max(1, width - inset * 2)),
    height: Math.min(requestedHeight, Math.max(1, height - inset * 2))
  }
}

function previewAnchorOffset(position, anchorWidth, anchorHeight,
                             popupWidth, popupHeight, gap) {
  var side = String(position || "bottom")
  var anchorW = Math.max(0, Number(anchorWidth) || 0)
  var anchorH = Math.max(0, Number(anchorHeight) || 0)
  var popupW = Math.max(1, Number(popupWidth) || 1)
  var popupH = Math.max(1, Number(popupHeight) || 1)
  var spacing = Math.max(0, Number(gap) || 0)

  if (side === "top") {
    return {
      x: (anchorW - popupW) / 2,
      y: anchorH + spacing
    }
  }
  if (side === "left") {
    return {
      x: anchorW + spacing,
      y: (anchorH - popupH) / 2
    }
  }
  if (side === "right") {
    return {
      x: -popupW - spacing,
      y: (anchorH - popupH) / 2
    }
  }
  return {
    x: (anchorW - popupW) / 2,
    y: -popupH - spacing
  }
}

function orientationHorizontal(position) {
  return position === "top" || position === "bottom"
}

function previewStatus(state) {
  var value = state || ({})
  if (value.minimized === true) return "Minimized"

  var workspace = String(value.workspace || "").trim()
  if (!workspace) return "Workspace unknown"
  if (workspace.indexOf("name:") === 0) workspace = workspace.slice(5)
  return "Workspace " + workspace
}
