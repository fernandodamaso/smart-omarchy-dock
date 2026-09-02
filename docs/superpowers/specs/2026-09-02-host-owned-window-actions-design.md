# Host-Owned Window Actions Foundation Design

## Goal

Centralize SmartDock window lifecycle actions and minimized-origin state in one controller owned by `DockHost.qml`, shared by every monitor, without changing visible behavior.

This is foundation work for FDM-808, FDM-810, FDM-812, FDM-815, and later window-related features. It deliberately does not implement wheel cycling, configurable pointer actions, previews, workspace/monitor filtering, badges, urgency motion, or intelligent hide.

## Current State

SmartDock currently splits window lifecycle behavior across per-screen and per-menu objects:

- `DockContextMenu.qml` owns `minimizedOrigins` and contains handle lookup, address lookup, minimized detection, minimize, restore, activation, and dispatch helpers.
- `DockItem.qml` owns `lastActivatedToplevel` for repeated left-click grouped cycling and calls context-menu activation.
- `Dock.qml` is instantiated once per screen, so any lifecycle state owned below `DockHost.qml` is duplicated per monitor.
- `DockHost.qml` is already the project-level owner of shared state and is the correct location for a single controller.

The refactor must preserve the existing fullscreen-focus fix: activating a dock window should prefer Hyprland address-based dispatch and only fall back to `Toplevel.activate()` when an address cannot be resolved.

## Architecture

Create `components/DockWindowActions.qml` and instantiate it exactly once in `DockHost.qml`.

Pass the same object through:

`DockHost.qml -> Dock.qml -> DockItem.qml / DockContextMenu.qml`

The controller owns mutable minimized-origin state and exposes narrow methods. Consumers must not mutate its maps directly.

### Controller responsibilities

`DockWindowActions.qml` owns:

- Hyprland handle lookup for Wayland toplevels.
- normalized address resolution through `DockModel.normalizeWindowAddress(...)`.
- liveness checks based on current `ToplevelManager.toplevels` and `Hyprland.toplevels` membership.
- minimized-origin storage keyed by normalized address.
- minimize, restore, activate/focus, and close request methods.
- active-member and live-member group helpers needed by future work.
- pruning origins for windows that no longer exist.

The controller must not persist window addresses, workspace origins, or monitor identities to disk.

## Minimized Origin Model

Store each origin as an object keyed by normalized window address:

```js
{
  "0xabc": {
    workspace: "3",
    monitor: "DP-1"
  }
}
```

`workspace` is a Hyprland workspace target suitable for `DockModel.restoreWindowRequest(...)`, such as a positive numeric workspace string or `name:<workspace>`.

`monitor` is an ephemeral monitor identity when it can be resolved reliably from the Hyprland IPC record. It exists for future FDM-812 scope filtering. It is not persisted and is not required for restore in this foundation.

Expose a copied snapshot, not the mutable internal map.

## Identity and Liveness

The canonical public methods should include equivalents of:

```qml
handleFor(toplevel)
addressFor(toplevel)
isAlive(toplevel)
isMinimized(toplevel)
windowState(toplevel)
originFor(toplevelOrAddress)
liveMembers(toplevels)
activeMember(toplevels, activeToplevel)
```

A toplevel is considered actionable only when it is still present in the current Wayland toplevel model. Handle-based actions additionally require a current matching Hyprland handle/address.

No window-title parsing or fuzzy identity matching is allowed.

## Activation

`activateToplevel(toplevel)` must:

1. reject null or stale toplevels;
2. restore SmartDock-minimized windows first;
3. otherwise prefer `DockModel.focusWindowRequest(address, Hyprland.usingLua)` and `Hyprland.dispatch(...)`;
4. fall back to `toplevel.activate()` only when the address-based request cannot be produced.

This preserves current behavior when switching focus away from another fullscreen window.

For minimized windows, restore remains a dispatch operation; activation does not assume the compositor completes the workspace move synchronously.

## Minimize

Before moving a window to `special:smartdock-minimized`, resolve a safe origin using refreshed/authoritative IPC workspace data first, then the object relationship, then `Hyprland.focusedWorkspace` as fallback.

If no valid restore target can be resolved, do not minimize the window. This prevents stranding it without a usable restore target.

Record the origin immediately before dispatching the minimize request.

## Restore

Restore to the recorded workspace target. If no stored target exists, resolve the current focused workspace as a safe fallback.

Only clear the stored origin after a valid restore request has been constructed and dispatched. This preserves the restore affordance when target resolution fails.

Monitor identity is metadata for future filtering; restore in this foundation remains workspace-based to preserve current behavior.

## Close

`closeToplevel(toplevel)` should safely request closure only for live toplevels. It must not assume synchronous disappearance and must tolerate applications refusing the request.

No controller state should require the object to disappear immediately.

## Group Helpers

Future FDM-808/FDM-815 work needs stable group semantics without a local cycling index.

Add pure helpers in `DockModel.js` where possible:

- return the index/member corresponding to the actual `ToplevelManager.activeToplevel` when it belongs to the group;
- ignore null/stale candidates supplied by a caller;
- choose the first valid live member deterministically when no member is active.

The foundation does not change repeated left-click semantics. `DockItem.qml` may keep its existing local compatibility index temporarily, but activation and minimized handling must route through the shared controller.

## Refactor Boundaries

### `DockHost.qml`

- instantiate one `DockWindowActions`;
- pass it to every `Dock.qml` variant;
- host lifecycle cleanup through the controller rather than per-screen state.

### `components/Dock.qml`

- require/receive the shared controller;
- pass it to application delegates.

### `components/DockItem.qml`

- receive the controller;
- route current activation through it;
- pass it to `DockContextMenu.qml`;
- preserve current left-click, drag, tooltip, fullscreen, grouping, and context-menu behavior.

### `components/DockContextMenu.qml`

Remove ownership of:

- `minimizedOrigins`;
- Hyprland handle lookup;
- address lookup;
- minimize/restore/activation implementation.

Use the controller for those operations while preserving current menu UI and actions.

### `components/DockModel.js`

Add only pure helpers required to make group selection and origin/state normalization testable. Do not move mutable lifecycle state into JavaScript.

## Testing

Add model tests for active-member selection, null/stale candidates, deterministic fallback, and minimized-origin-compatible pure helpers.

Add `tests/check_window_actions.sh` to enforce architecture:

- `DockWindowActions.qml` exists;
- `DockHost.qml` instantiates it once;
- `Dock.qml` receives and passes the same controller;
- `DockContextMenu.qml` requires the controller and no longer owns `minimizedOrigins`;
- no per-item or per-monitor controller instances exist.

The chat/GitHub phase cannot execute local Quickshell or Omarchy commands. A later local agent must run the project validation gate and runtime matrix before merge.

## Compatibility and Non-Goals

Preserve:

- normal and repeated grouped left click;
- context-menu window selection;
- Move to Workspace;
- Fullscreen (Keep Bars);
- minimize/restore;
- close;
- drag reorder;
- pinned launchers;
- tooltips;
- auto-hide;
- fullscreen emphasis;
- workspace strip;
- grouped/ungrouped mode;
- standalone and Omarchy plugin entry points.

Do not introduce polling, subprocess-based lifecycle actions, persisted origins, new settings, new UI, or changes to installed Omarchy/user configuration.

## Handoff Requirement

The branch may contain implementation and static tests produced through GitHub, but it must remain explicitly unverified for local/runtime behavior until an Omarchy-capable local coding agent runs the full validation matrix.