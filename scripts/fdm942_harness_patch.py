from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one match in {path}, found {count}")
    p.write_text(text.replace(old, new, 1))


replace_once(
    "tests/test_workspace_drag.mjs",
    """    minimizedWorkspace: 'special:smartdock-minimized', minimizedOrigins: {},
    ToplevelManager: { toplevels: { values: windows } },
""",
    """    minimizedWorkspace: 'special:smartdock-minimized', minimizedOrigins: {},
    windowWorkspacePins: {}, workspaceMonitorPins: {},
    ToplevelManager: { toplevels: { values: windows } },
""",
)

replace_once(
    "tests/test_grouped_actions.mjs",
    """  minimizedOrigins: {}, minimizedWorkspace: 'special:smartdock-minimized',
  activeToplevel: windows[0],
""",
    """  minimizedOrigins: {}, minimizedWorkspace: 'special:smartdock-minimized',
  windowWorkspacePins: {}, workspaceMonitorPins: {},
  activeToplevel: windows[0],
""",
)
