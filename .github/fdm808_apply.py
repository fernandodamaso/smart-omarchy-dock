from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one anchor, found {count}: {old[:80]!r}")
    p.write_text(text.replace(old, new, 1))


def append_once(path, anchor, addition):
    replace_once(path, anchor, anchor + addition)


# Compatibility-safe scroll schema. Keep left/middle vocabulary unchanged.
replace_once(
    "components/DockModel.js",
    '''function applicationActionOptions() {
  return [
    { value: "none", label: "No action" },
    { value: "minimize-restore", label: "Minimize / restore" },
    { value: "previews", label: "Show previews" },
    { value: "close", label: "Close" },
    { value: "focus-or-launch", label: "Focus or launch" }
  ]
}

function normalizeApplicationActionConfig(settings) {''',
    '''function applicationActionOptions() {
  return [
    { value: "none", label: "No action" },
    { value: "minimize-restore", label: "Minimize / restore" },
    { value: "previews", label: "Show previews" },
    { value: "close", label: "Close" },
    { value: "focus-or-launch", label: "Focus or launch" }
  ]
}

function scrollActionOptions() {
  return [
    { value: "none", label: "No action" },
    { value: "cycle-windows", label: "Cycle windows" }
  ]
}

function normalizeApplicationActionConfig(settings) {''')

replace_once(
    "components/DockModel.js",
    '''  return {
    clickAction: normalizeSetting("clickAction", source.clickAction),
    middleClickAction: normalizeSetting(
      "middleClickAction", source.middleClickAction)
  }
}''',
    '''  return {
    clickAction: normalizeSetting("clickAction", source.clickAction),
    middleClickAction: normalizeSetting(
      "middleClickAction", source.middleClickAction),
    scrollAction: normalizeSetting("scrollAction", source.scrollAction)
  }
}''')

replace_once(
    "components/DockModel.js",
    '''  if (kind === "left")
    return shift ? "none" : actionConfig.clickAction
  if (kind === "middle")
    return shift ? "none" : actionConfig.middleClickAction
  return "none"
}''',
    '''  if (kind === "left")
    return shift ? "none" : actionConfig.clickAction
  if (kind === "middle")
    return shift ? "none" : actionConfig.middleClickAction
  if (kind === "scroll")
    return shift ? "none" : actionConfig.scrollAction
  return "none"
}''')

replace_once(
    "components/DockModel.js",
    '''function applicationActionCanRun(action, runningCount) {
  var value = String(action === undefined || action === null ? "" : action).trim()
  if (applicationActionValues().indexOf(value) < 0 || value === "none")
    return false
  if (value === "focus-or-launch") return true
  return Number(runningCount) > 0
}''',
    '''function applicationActionCanRun(action, runningCount) {
  var value = String(action === undefined || action === null ? "" : action).trim()
  if (value === "cycle-windows") return Number(runningCount) >= 2
  if (applicationActionValues().indexOf(value) < 0 || value === "none")
    return false
  if (value === "focus-or-launch") return true
  return Number(runningCount) > 0
}''')

replace_once(
    "components/DockModel.js",
    '''    clickAction: "focus-or-launch",
    middleClickAction: "none",
    controlCommand: "omarchy-menu toggle apps",''',
    '''    clickAction: "focus-or-launch",
    middleClickAction: "none",
    scrollAction: "none",
    controlCommand: "omarchy-menu toggle apps",''')

replace_once(
    "components/DockModel.js",
    '''  case "clickAction":
  case "middleClickAction": {
    var action = String(value === undefined || value === null ? "" : value).trim()
    // Older settings exposed Focus and Launch separately. Treat both legacy
    // values as the single combined action so existing files keep working.
    if (action === "focus" || action === "launch")
      return "focus-or-launch"
    return applicationActionValues().indexOf(action) >= 0 ? action : defaults[key]
  }
  case "controlCommand":''',
    '''  case "scrollAction": {
    var scrollAction = String(
      value === undefined || value === null ? "" : value).trim()
    return scrollAction === "cycle-windows" ? scrollAction : defaults.scrollAction
  }
  case "clickAction":
  case "middleClickAction": {
    var action = String(value === undefined || value === null ? "" : value).trim()
    // Older settings exposed Focus and Launch separately. Treat both legacy
    // values as the single combined action so existing files keep working.
    if (action === "focus" || action === "launch")
      return "focus-or-launch"
    return applicationActionValues().indexOf(action) >= 0 ? action : defaults[key]
  }
  case "controlCommand":''')

# Pure grouped-window selection and high-resolution wheel helpers.
append_once(
    "components/DockWindowModel.js",
    '''function activeGroupMember(candidates, activeToplevel, liveToplevels) {
  var live = liveGroupMembers(candidates, liveToplevels)
  if (live.length === 0) return null
  if (activeToplevel && live.indexOf(activeToplevel) >= 0)
    return activeToplevel
  return live[0]
}
''',
    '''
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
''')

# Shared host-owned lifecycle action.
replace_once(
    "components/DockWindowActions.qml",
    '''  property var previewController: null

  function currentToplevels() {''',
    '''  property var previewController: null
  readonly property var activeToplevel: ToplevelManager.activeToplevel

  function currentToplevels() {''')

replace_once(
    "components/DockWindowActions.qml",
    '''  function activeMember(toplevels) {
    return DockWindowModel.activeGroupMember(
      toplevels, ToplevelManager.activeToplevel, currentToplevels())
  }''',
    '''  function activeMember(toplevels) {
    return DockWindowModel.activeGroupMember(
      toplevels, root.activeToplevel, currentToplevels())
  }''')

replace_once(
    "components/DockWindowActions.qml",
    '''  function focusToplevels(toplevels) {
    var member = activeMember(toplevels)
    return member ? activateToplevel(member) : false
  }

  function minimizeRestoreToplevels(toplevels) {''',
    '''  function focusToplevels(toplevels) {
    var member = activeMember(toplevels)
    return member ? activateToplevel(member) : false
  }

  function cycleToplevels(toplevels, direction, activeToplevel) {
    var members = liveMembers(toplevels)
    if (members.length < 2) return false

    var active = activeToplevel === undefined
      ? root.activeToplevel : activeToplevel
    var target = DockWindowModel.cycleGroupMember(
      members, active, currentToplevels(), direction)
    if (!target) return false

    var address = addressFor(target)
    if (!address) return false

    if (isMinimized(target)) {
      if (!restoreToplevel(target)) return false
      var focusRequest = DockModel.focusWindowRequest(address, Hyprland.usingLua)
      if (dispatchRequest(focusRequest)) return true
      if (typeof target.activate === "function") {
        target.activate()
        return true
      }
      return true
    }

    return activateToplevel(target)
  }

  function minimizeRestoreToplevels(toplevels) {''')

# Item-level transient wheel adapter; all window state remains shared.
replace_once(
    "components/DockItem.qml",
    '''import "DockModel.js" as DockModel
import "DockBadgeModel.js" as BadgeModel''',
    '''import "DockModel.js" as DockModel
import "DockBadgeModel.js" as BadgeModel
import "DockWindowModel.js" as DockWindowModel''')

replace_once(
    "components/DockItem.qml",
    '''  property real reorderOffset: 0
  property int lastActivatedToplevel: -1''',
    '''  property real reorderOffset: 0
  property int lastActivatedToplevel: -1
  property real wheelRemainder: 0
  property double lastWheelTimestamp: 0''')

replace_once(
    "components/DockItem.qml",
    '''  function dispatchApplicationAction(action) {
    if (!DockModel.applicationActionCanRun(action, runningCount)) return false

    switch (action) {
    case "minimize-restore":''',
    '''  function dispatchApplicationAction(action, options) {
    if (!DockModel.applicationActionCanRun(action, runningCount)) return false

    var request = options || ({})
    switch (action) {
    case "cycle-windows":
      return root.windowActions.cycleToplevels(
        root.runningToplevels, request.direction, root.windowActions.activeToplevel)
    case "minimize-restore":''')

replace_once(
    "components/DockItem.qml",
    '''  function dispatchPointerAction(input, modifiers) {
    return dispatchApplicationAction(DockModel.resolveApplicationPointerAction(
      applicationActions, input, modifiers))
  }

  onRunningToplevelsChanged: {
    lastActivatedToplevel = -1
    if (runningCount < 2) root.previewDismissRequested()
  }''',
    '''  function dispatchPointerAction(input, modifiers, options) {
    return dispatchApplicationAction(DockModel.resolveApplicationPointerAction(
      applicationActions, input, modifiers), options)
  }

  onRunningToplevelsChanged: {
    lastActivatedToplevel = -1
    wheelRemainder = 0
    lastWheelTimestamp = 0
    if (runningCount < 2) root.previewDismissRequested()
  }''')

replace_once(
    "components/DockItem.qml",
    '''  DragHandler {
    id: dragHandler''',
    '''  WheelHandler {
    id: wheelHandler

    enabled: root.runningCount >= 2
      && root.applicationActions.scrollAction === "cycle-windows"
    target: null
    onWheel: event => {
      event.accepted = false

      var verticalDelta = DockWindowModel.dominantVerticalWheelDelta(
        event.angleDelta.x, event.angleDelta.y)
      if (verticalDelta === 0) return

      var now = Date.now()
      root.wheelRemainder = DockWindowModel.wheelRemainderForTimestamp(
        root.wheelRemainder, root.lastWheelTimestamp, now, 220)
      root.lastWheelTimestamp = now

      var accumulated = DockWindowModel.accumulateWheelSteps(
        root.wheelRemainder, verticalDelta, 120)
      root.wheelRemainder = accumulated.remainder
      var direction = DockWindowModel.wheelStepDirection(accumulated.steps)
      if (direction === 0) return

      var cycled = root.dispatchPointerAction(
        "scroll", {}, { direction: direction })
      event.accepted = cycled
    }
  }

  DragHandler {
    id: dragHandler''')

# Flow scroll setting through host/dock/config/settings UI.
replace_once(
    "components/Dock.qml",
    '''  readonly property var applicationActions: DockModel.normalizeApplicationActionConfig({
    clickAction: effectiveSetting("clickAction"),
    middleClickAction: effectiveSetting("middleClickAction")
  })''',
    '''  readonly property var applicationActions: DockModel.normalizeApplicationActionConfig({
    clickAction: effectiveSetting("clickAction"),
    middleClickAction: effectiveSetting("middleClickAction"),
    scrollAction: effectiveSetting("scrollAction")
  })''')

replace_once(
    "DockHost.qml",
    '''    clickAction: "focus-or-launch",
    middleClickAction: "none",
    controlCommand: "omarchy-menu toggle apps",''',
    '''    clickAction: "focus-or-launch",
    middleClickAction: "none",
    scrollAction: "none",
    controlCommand: "omarchy-menu toggle apps",''')

replace_once(
    "config/dock.json",
    '''  "clickAction": "focus-or-launch",
  "middleClickAction": "none",
  "controlCommand": "omarchy-menu toggle apps",''',
    '''  "clickAction": "focus-or-launch",
  "middleClickAction": "none",
  "scrollAction": "none",
  "controlCommand": "omarchy-menu toggle apps",''')

replace_once(
    "components/DockSettings.qml",
    '''              DockActionDropdown {
                width: parent.width
                label: "Middle click"
                value: root.current("middleClickAction")
                options: DockModel.applicationActionOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("middleClickAction", value)
              }

            }''',
    '''              DockActionDropdown {
                width: parent.width
                label: "Middle click"
                value: root.current("middleClickAction")
                options: DockModel.applicationActionOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("middleClickAction", value)
              }

              DockActionDropdown {
                width: parent.width
                label: "Scroll"
                value: root.current("scrollAction")
                options: DockModel.scrollActionOptions()
                foreground: Color.menu.text
                background: Color.menu.background
                popupBorder: Color.menu.border
                accent: Color.accent
                onChanged: value => root.commit("scrollAction", value)
              }

            }''')

# FDM-815 structural guard now permits the FDM-808-owned wheel runtime.
replace_once(
    "tests/check_pointer_actions.sh",
    '''reject_pattern 'WheelHandler[[:space:]]*\\{' components/DockItem.qml
reject_pattern 'wheelRemainder|lastWheelTimestamp|accumulateWheelSteps|wheelStepDirection|scrollAction' components/DockItem.qml
reject_pattern 'pointerModifierState|eventPoint\\.modifiers|ShiftModifier' components/DockItem.qml
reject_pattern 'cycleToplevels|cycle-windows' components/DockItem.qml
reject_pattern 'cycleToplevels|cycle-windows' components/DockWindowActions.qml
reject_pattern 'cycleTargetIndex|cycleGroupMember|dominantVerticalWheelDelta|wheelRemainderForTimestamp' components/DockWindowModel.js
''',
    '''reject_pattern 'pointerModifierState|eventPoint\\.modifiers|ShiftModifier' components/DockItem.qml
''')

replace_once(
    "tests/check_pointer_actions.sh",
    '''[[ "$selector_count" -eq 2 ]] \\
  || fail "Dock Settings must expose exactly two application action selectors (found $selector_count)"''',
    '''[[ "$selector_count" -eq 3 ]] \\
  || fail "Dock Settings must expose Left, Middle, and Scroll selectors (found $selector_count)"''')

replace_once(
    "tests/check_pointer_actions.sh",
    '''require_pattern 'label:[[:space:]]*"Middle click"' components/DockSettings.qml
reject_pattern 'label:[[:space:]]*"Shift \\+ left click"' components/DockSettings.qml
reject_pattern 'label:[[:space:]]*"Scroll"' components/DockSettings.qml''',
    '''require_pattern 'label:[[:space:]]*"Middle click"' components/DockSettings.qml
require_pattern 'label:[[:space:]]*"Scroll"' components/DockSettings.qml
reject_pattern 'label:[[:space:]]*"Shift \\+ left click"' components/DockSettings.qml''')

replace_once(
    "tests/check_pointer_actions.sh",
    '''reject_pattern 'Shift\\+left|scrollAction|cycle-windows|Shift\\+middle' README.md''',
    '''reject_pattern 'Shift\\+left|Shift\\+middle' README.md''')

# Concise user-facing docs; retain the recovered two-click action vocabulary.
replace_once(
    "README.md",
    '''- Configurable application-icon left and middle click actions''',
    '''- Configurable application-icon left, middle, and grouped-window scroll actions''')

replace_once(
    "README.md",
    '''  "clickAction": "focus-or-launch",
  "middleClickAction": "none",
  "controlCommand": "omarchy-menu toggle apps",''',
    '''  "clickAction": "focus-or-launch",
  "middleClickAction": "none",
  "scrollAction": "none",
  "controlCommand": "omarchy-menu toggle apps",''')

replace_once(
    "README.md",
    '''| `middleClickAction` | Action for an unmodified Middle click; defaults to `none` |
| `controlCommand` |''',
    '''| `middleClickAction` | Action for an unmodified Middle click; defaults to `none` |
| `scrollAction` | Vertical scroll action; `cycle-windows` cycles grouped live windows, while `none` preserves pass-through |
| `controlCommand` |''')

replace_once(
    "README.md",
    '''The two action keys accept the same vocabulary: `none`, `minimize-restore`,
`previews`, `close`, and `focus-or-launch`.

Input precedence is intentionally strict:

- Right click always opens the existing application context menu.
- Left click with no modifier uses `clickAction`.
- Middle click with no modifier uses `middleClickAction`.
- Ctrl, Alt, Meta, and mixed modifier combinations perform no application action.''',
    '''The Left and Middle click keys accept the same vocabulary: `none`,
`minimize-restore`, `previews`, `close`, and `focus-or-launch`. `scrollAction`
is intentionally narrower: `none` or `cycle-windows`.

Input precedence is intentionally strict:

- Right click always opens the existing application context menu.
- Left click with no modifier uses `clickAction`.
- Middle click with no modifier uses `middleClickAction`.
- Vertical-dominant scrolling uses `scrollAction`; horizontal/tied gestures pass through.
- Ctrl, Alt, Meta, Shift, and mixed modifier combinations do not trigger scroll actions.''')

replace_once(
    "README.md",
    '''Invalid values for `middleClickAction` normalize to `none`.

Attention dots deliberately represent''',
    '''Invalid values for `middleClickAction` normalize to `none`. Missing or invalid
`scrollAction` values also normalize to `none`, so existing configurations keep
their current behavior. When set to `cycle-windows`, scroll input is consumed
only for a grouped icon with at least two live windows. High-resolution vertical
deltas accumulate in 120-unit steps, residual input resets after about 220 ms,
and minimized targets restore through the shared host-owned window controller
before focus.

Attention dots deliberately represent''')

print("FDM-808 recovery patch applied")
