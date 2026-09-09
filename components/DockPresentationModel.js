.pragma library

function keyFor(item, keyProperty, index) {
  var value = item && item[keyProperty]
  return value === undefined || value === null || value === ""
    ? "index:" + index : String(value)
}

function copyEntry(entry, item, present, animateEntrance, exitRevision) {
  return {
    token: entry.token,
    key: entry.key,
    item: item === undefined ? entry.item : item,
    present: present,
    animateEntrance: animateEntrance,
    exitRevision: exitRevision === undefined ? entry.exitRevision : exitRevision
  }
}

function reconcile(previous, values, keyProperty, animationsEnabled) {
  var oldState = previous || ({ entries: [], nextToken: 1, initialized: false })
  var nextToken = oldState.nextToken
  var incoming = values || []
  var oldByKey = Object.create(null)
  for (var i = 0; i < oldState.entries.length; ++i) {
    var old = oldState.entries[i]
    oldByKey[old.key] = old
  }

  var used = Object.create(null)
  var nextEntries = []
  for (var n = 0; n < incoming.length; ++n) {
    var value = incoming[n]
    var key = keyFor(value, keyProperty, n)
    var existing = oldByKey[key]
    if (existing) {
      used[key] = true
      nextEntries.push(copyEntry(existing, value, true,
        Boolean(animationsEnabled) && !existing.present, existing.exitRevision))
    } else {
      nextEntries.push({
        token: nextToken++, key: key, item: value, present: true,
        animateEntrance: oldState.initialized && Boolean(animationsEnabled),
        exitRevision: 0
      })
    }
  }

  if (Boolean(animationsEnabled)) {
    for (var o = 0; o < oldState.entries.length; ++o) {
      var departed = oldState.entries[o]
      if (used[departed.key]) continue
      var retained = copyEntry(departed, undefined, false, false,
        departed.exitRevision + (departed.present ? 1 : 0))
      var insertAt = Math.min(o, nextEntries.length)
      nextEntries.splice(insertAt, 0, retained)
    }
  }

  return { entries: nextEntries, nextToken: nextToken, initialized: true }
}

function completeRemoval(state, token, exitRevision) {
  if (!state) return state
  var entries = state.entries || []
  var next = []
  for (var i = 0; i < entries.length; ++i) {
    var entry = entries[i]
    if (entry.token === token && !entry.present
        && entry.exitRevision === exitRevision)
      continue
    next.push(entry)
  }
  return { entries: next, nextToken: state.nextToken, initialized: state.initialized }
}
