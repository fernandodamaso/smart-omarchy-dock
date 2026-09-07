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

function cycleTargetIndex(count, originIndex, direction) {
  var size = Math.floor(Number(count))
  var value = Number(originIndex)
  var delta = Number(direction)
  if (!isFinite(size) || size < 2 || !isFinite(delta) || delta === 0)
    return -1

  var step = delta > 0 ? 1 : -1
  if (!Number.isInteger(value) || value < 0 || value >= size)
    return step > 0 ? 0 : size - 1
  return (value + step + size) % size
}

function cycleGroupMember(candidates, activeToplevel, liveToplevels, direction) {
  var live = liveGroupMembers(candidates, liveToplevels)
  if (live.length < 2) return null

  var originIndex = activeToplevel ? live.indexOf(activeToplevel) : -1
  var targetIndex = cycleTargetIndex(live.length, originIndex, direction)
  return targetIndex >= 0 ? live[targetIndex] : null
}

function dominantVerticalWheelDelta(horizontalDelta, verticalDelta) {
  var horizontal = Number(horizontalDelta)
  var vertical = Number(verticalDelta)
  if (!isFinite(horizontal)) horizontal = 0
  if (!isFinite(vertical)) vertical = 0
  if (vertical === 0 || Math.abs(vertical) <= Math.abs(horizontal)) return 0
  return vertical
}

function accumulateWheelSteps(remainder, delta, stepSize) {
  var carried = Number(remainder)
  var input = Number(delta)
  var unit = Number(stepSize)
  if (!isFinite(carried)) carried = 0
  if (!isFinite(input)) input = 0
  if (!isFinite(unit) || unit <= 0) unit = 120

  var total = carried + input
  var steps = total < 0 ? Math.ceil(total / unit) : Math.floor(total / unit)
  return {
    steps: steps,
    remainder: total - steps * unit
  }
}

function wheelStepDirection(steps) {
  var value = Number(steps)
  if (!isFinite(value) || value === 0) return 0
  return value > 0 ? 1 : -1
}

function wheelRemainderForTimestamp(remainder, previousTimestamp,
                                    currentTimestamp, resetAfterMs) {
  var carried = Number(remainder)
  var previous = Number(previousTimestamp)
  var current = Number(currentTimestamp)
  var timeout = Number(resetAfterMs)
  if (!isFinite(carried)) carried = 0
  if (!isFinite(timeout) || timeout < 0) timeout = 220
  if (!isFinite(previous) || previous <= 0 || !isFinite(current)) return carried
  if (current < previous || current - previous > timeout) return 0
  return carried
}
