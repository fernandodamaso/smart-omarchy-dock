.pragma library

function liveGroupMembers(candidates, liveToplevels) {
  var values = candidates || []
  var live = liveToplevels || []
  var result = []

  for (var i = 0; i < values.length; ++i) {
    var candidate = values[i]
    if (candidate && live.indexOf(candidate) >= 0)
      result.push(candidate)
  }

  return result
}

function activeGroupMember(candidates, activeToplevel, liveToplevels) {
  var live = liveGroupMembers(candidates, liveToplevels)
  if (live.length === 0) return null
  if (activeToplevel && live.indexOf(activeToplevel) >= 0)
    return activeToplevel
  return live[0]
}
