# Focused application indicator

SmartDock distinguishes a running application from the application that owns the compositor's active toplevel without adding a user setting.

## State semantics

- A closed pinned application has no application-state marker.
- A running, non-focused application uses a compact dot/square marker.
- A focused application uses a visibly longer capsule marker.
- Running uses the Omarchy `Color.foreground` theme role; focused uses `Color.accent`.
- Shape and length carry the state difference, so focus does not depend on color perception alone.

The marker remains present when all windows in an application group are minimized because running state comes from group membership, not visible-window count.

## Focus source

`Dock.qml` reads the existing `ToplevelManager.activeToplevel` and compares that exact toplevel identity against each dock item's current group. The comparison stays directly in the QML binding so active-object changes trigger live updates; no focus cache, polling loop, duplicate window store, or additional Hyprland query is introduced.

This keeps focus identity tied to the compositor toplevel object while the existing item model continues to own grouping, hidden-application filtering, workspace sorting, and pinned order.

## Geometry

`DockModel.applicationStateIndicatorGeometry()` owns marker geometry for all dock edges. At the default 42 px icon size, a running marker is 4×4 px and a focused marker is 12×4 px on top/bottom docks or 4×12 px on left/right docks. Thickness and focused length are bounded for supported icon-size changes.

The reusable `DockApplicationStateIndicator.qml` lives inside the icon container, so existing fullscreen presentation, hover magnification, drag transforms, and reorder transforms move the marker with the application icon instead of maintaining separate screen coordinates.

## Regression expectations

Repository and local validation should confirm that:

- grouped and ungrouped applications identify focus by active-member identity;
- minimized windows keep the running marker while compositor focus moves normally;
- fullscreen emphasis remains independent from the application-state marker;
- theme changes preserve legibility and the shape difference remains sufficient without color;
- hidden applications render no marker while hidden and resume normal state when restored;
- top, bottom, left, and right dock positions keep the marker on the outward icon edge;
- workspace and monitor changes follow `ToplevelManager.activeToplevel` without stale focus state;
- the existing shared `DockWindowActions` owner and application badges are unchanged.
