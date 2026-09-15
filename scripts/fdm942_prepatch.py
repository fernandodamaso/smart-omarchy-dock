from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one match in {path}, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "tests/test_session_pins.mjs",
    "assert.match(menuSource, /Pin Window to Workspace/)\n",
    "assert.match(menuSource, /windowPin \\? \\\"Unpin Window from \\\" : \\\"Pin Window to \\\"/)\n"
    "assert.match(menuSource, /windowPinWorkspaceLabel\\(reliableWorkspace\\)/)\n",
)

replace_once(
    "tests/test_session_pins.mjs",
    """// Reconciliation clears only confirmed changes; incomplete inventory is retained.\n""",
    """// Cycling and minimized activation share the same monitor-pin focus-only path.\n{
  const f = fixture(false)
  const { actions: a, A, C, handles, detached } = f
  assert.equal(a.pinWorkspaceToMonitor('id:3'), true)
  assert.equal(a.cycleToplevels([C, A], 1, C, true, 'id:1'), true)
  assert.doesNotMatch(detached.flat().join(' '),
    /movecurrentworkspacetomonitor|moveworkspacetomonitor/i,
    'window cycling must not pull a pinned workspace')

  detached.length = 0
  assert.equal(a.minimizeToplevel(A, true), true)
  handles[0].lastIpcObject.workspace = { name: 'special:smartdock-minimized' }
  assert.equal(a.activateToplevel(A, true, 'id:1', true), true)
  assert.doesNotMatch(detached.flat().join(' '),
    /movecurrentworkspacetomonitor|moveworkspacetomonitor/i,
    'minimized restore/focus must keep a pinned workspace on its monitor')
}

// Explicit compositor lifecycle signals clear exact pins without guessing from gaps.\n{
  const f = fixture()
  const { actions: a, A } = f
  assert.equal(a.pinWindowToWorkspace(A), true)
  assert.equal(a.confirmWindowClosed({ data: 'a1' }), true)
  assert.equal(a.windowWorkspacePins['0xa1'], undefined)

  assert.equal(a.pinWorkspaceToMonitor('id:3'), true)
  assert.equal(a.confirmMonitorRemoved({ data: 'DP-1' }), true)
  assert.equal(a.workspaceMonitorPins['id:3'], undefined)
}

// Reconciliation clears only confirmed changes; incomplete inventory is retained.\n""",
)

replace_once(
    "tests/test_session_pins.mjs",
    """const dragSource = read('DockWorkspaceDrag.qml')\n""",
    """const dockSource = read('Dock.qml')
const headerActivationBody = dockSource.match(
  /function focusWorkspaceOnDockMonitor\\([\\s\\S]*?\\n  }/)?.[0] || ''
assert.match(headerActivationBody, /windowActions\\.workspaceOnMonitorRequests/,
  'workspace-header activation must use the central monitor-pin policy')
assert.doesNotMatch(headerActivationBody, /moveWorkspaceToMonitorRequest|moveCurrentWorkspaceToMonitorRequest/,
  'workspace-header activation must not bypass the central monitor-pin policy')
assert.match(dockSource, /windowActions\\.activateToplevel/,
  'dock app/preview activation must retain the shared exact-window activation controller')

const dragSource = read('DockWorkspaceDrag.qml')\n""",
)

replace_once(
    "README.md",
    """On this source base, clicking a grouped workspace header uses the existing
central workspace-on-monitor path: it pulls that workspace onto the clicked dock
monitor and focuses it. A window icon inside a workspace card likewise uses the
card workspace as its activation target, so an ordinary card-window click pulls
that workspace before focusing the exact window. FDM-942/FDM-943 pin-aware
workspace activation and workspace-header context menus are not integrated in
this base; their focus-in-place/menu behavior remains an explicit integration
and real-host gate for WS-MON-04 rather than being duplicated in this layout.
""",
    """Clicking a grouped workspace header and activating a window both use one shared
workspace-on-monitor path. By default that keeps the existing pull-and-focus
behavior. SmartDock now also has **session-only movement pins** owned by the
shared window-action controller: an individual window can be pinned to its
current reliable workspace from its context menu, and a workspace can be pinned
to its current monitor through the shared API consumed by the workspace-header
menu added in FDM-943. These pins are deliberately not settings, Hyprland rules,
or persistent configuration; restarting the SmartDock host clears them.

A window workspace pin blocks SmartDock menu and drag relocations to another
workspace, including represented groups when any captured member is pinned.
SmartDock minimize/restore keeps the recorded origin and does not clear the pin.
A workspace monitor pin makes workspace-header, app-icon, preview, cycling and
restore activation focus the workspace where it already lives instead of
pulling it to the dock monitor. External Hyprland shortcuts/tools remain free to
move windows and workspaces; once SmartDock observes a confirmed external move,
close, or monitor disconnect it drops only the affected session pin. Transient
or incomplete refreshes do not by themselves clear pin state. Group/Ungroup
changes leave window pins untouched.
""",
)
