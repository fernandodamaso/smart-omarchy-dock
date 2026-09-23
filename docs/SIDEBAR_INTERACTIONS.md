# SB-04 — Sidebar interactions

FDM-966 source candidate. Native integration and rendering remain FDM-968/SB-06
acceptance gates. This document does not report an unexecuted fixture as a pass.

## Source lineage and ownership

The candidate starts from accepted SB-03 `c6d9b0dcb8f96f6e61591996bcafc728ec022dfe`
and merges `main` at `86fb65893295c95df664e6f274b19375a50f088a`, which contains
FDM-954/PR #79 and the newer classic workspace-drag integration. The single
`Dock.qml` merge conflict preserves SB-01's shared `DockDesktopModel` builder and
the newer classic drag coordinator. The builder uses the current native
`monitorActiveWorkspace` helper. SB-05/PR #78 widget footer/lifecycle is folded into the FDM-968 integration candidate with this viewport/menu/resize composition.

No installed plugin, production configuration, topbar or compositor binding is
changed. No second action controller, writer, process, monitor watcher or saved
setting is added. PR-only delivery and fresh exact-head CI remain required by
`DELIVERY.md`. A local commit or source bundle alone is not remote Done.

## Exact activation

`DockSidebarController.captureTarget` captures the session key, native handle,
address and clicked connector before pointer focus changes. The row-input adapter
uses the same separate native Qt NoModifier/ControlModifier TapHandler pattern as
FDM-954. Only explicit boolean Control permits a pull; missing information stays
plain. Raw Qt modifiers are available in the viewport's activation signal.

Plain clicks and Enter activate the exact live window without requesting a
workspace move. Ctrl+left-click canonicalizes the captured host connector and
uses the shared `pullToplevelToMonitorWorkspace` route, moving just that window
to the clicked monitor's active workspace before focusing it. Window and workspace
pins, minimized origins, named workspaces, exact-handle liveness and same-monitor
behavior remain owned by that service. No focus-derived monitor or frozen card
workspace override is substituted. Enter remains plain even while Ctrl is held.

Unknown window locations remain reachable by their live native handles; actions
requiring a trustworthy location are disabled. Address reuse, hidden-app changes,
closure and a changed captured connector cannot retarget a delayed click.

Sidebar workspace headers focus in place on plain click and Enter through the
shared `focusWorkspaceInPlace` adapter. Ctrl+click validates the captured
connector and pulls the workspace onto that monitor through
`workspaceOnMonitorRequests`. Classic header, wheel, pointer action settings,
menus and cross-dock drag behavior are unchanged.

## Menus and keyboard

One existing `DockContextMenu` is composed by the sidebar. A captured window is a
single target, not whichever row is hovered or active later. The optional sidebar
mode disables saved Group/Ungroup actions, uses live named/numeric workspaces for
window moves and adds current-owner workspace pin/unpin and explicit monitor-move
menus. All dispatches, including app-level actions without a window target field,
revalidate the captured row. Removed move destinations are revalidated before
dispatch and are not silently recreated. Menus dismiss/reanchor on closure, owner changes,
visibility/clipping, viewport scrolling, mode/edge/host change and topology refresh.
The existing popup placement slides inward within screen bounds; sidebar width
and height additionally cap the popup, including bottom anchors.

`DockSidebarKeyboard` is a focus-neutral Qt event adapter. Rows forward explicit
key events to it; it installs no global keybind and takes no hover/map focus.
Tab/Shift+Tab, Up/Down, Home/End skip noninteractive section labels. Enter activates,
Space folds an application, Shift+F10 opens the selected row's menu and Escape
cancels input/dismisses menus. Navigation remembers an exact live application
handle for explicit Escape focus restoration. Pointer-selected rows are not
changed by a delayed keyboard-entry handler. ListView wheel/touchpad scrolling
stays ordinary scrolling; its competing built-in key navigation is disabled.

## Drag lifecycle and geometry

A captured individual window can move silently to a visible workspace region.
The shared service moves only that selected handle, updates minimized origins
without showing the window and applies current session pins. A workspace header
can move its entire workspace to a visible monitor heading through the existing
`canMoveWorkspaceToMonitor`/`moveWorkspaceToMonitor` policy. No fake per-monitor
dock is registered and classic coordinator checks are not relaxed.

`DockSidebarInteractionModel` consumes the actual mapped ListView delegate
rectangles, clipped to the viewport. Offscreen rows, Unassigned locations,
separators, utilities and the SB-05 footer are not valid drop surfaces. Window
moves never target monitor headings. A passive native-artwork/label proxy follows
the pointer; it is not a separate window or screenshot preview. Edge scrolling
is bounded to at most 12 logical pixels per 16 ms tick and stops outside the
viewport. Hit testing is repeated after scrolling and again on release.

Presentation ordering freezes while dragging, not live action validity. Closure,
address reuse, source location changes, target-owner changes, topology changes,
mode/edge/host/collapse invalidation, Escape and native grab cancellation abort
without a partial move. Resize, menus and row drags share the existing busy
boundary. Qt `UngrabExclusive` is the successful release; becoming inactive alone
is not permission to commit. A completed or cancelled gesture consumes its click.

## Source checks

```bash
node tests/test_sidebar_actions.mjs
node tests/test_sidebar_drag.mjs
node tests/test_grouped_actions.mjs
node tests/test_session_pins.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_sidebarinteraction.qml -import components
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_sidebarkeyboard.qml -import components
```

Also run every current Headless CI gate. Model tests execute production QML
methods with compositor transport substituted; Qt input tests execute the actual
pointer/key adapters with QtTest events. These are not native Wayland modifier,
physical monitor, full-shell popup or typing-focus passes.

## FDM-968 native qualification

`check-sidebar.sh` retains its automated production host/controller/delegate/
reservation/writer fixture. Its injected desktop data remains explicitly
synthetic. SB-04 additionally checks that real pointer/key/menu adapters exist.

A separate live-data observer runs the real host without injected windows,
replaced dispatchers or a copied renderer. Stop the named guest's normal dock
first; never run this on the production display:

```bash
SMARTDOCK_ISOLATED_RUNTIME=1 SMARTDOCK_RUNTIME_LOG=/tmp/sidebar-native.jsonl \
  SMARTDOCK_NATIVE_SECONDS=120 bash tests/runtime/check-sidebar.sh --native
```

The observer uses disposable source/configuration, refuses an existing mapped
SmartDock layer and is bounded to 1..300 seconds. It logs real row press state,
raw activation modifiers, captured connector/address, accepted action, delayed
workspace-owner/focused-address readback and drag lifecycle observations. Window
titles are omitted. The output is prefixed diagnostic JSON, not a bare JSONL file.
A `ready` record or clean observer exit is **not** a matrix pass. Inspect and
sanitize the evidence; keyboard actions may have no press snapshot, and rapid
interactions may share a delayed readback. Record independent `hyprctl -j`
workspace/monitor/active-window snapshots before and after each isolated case.

SB-06 must run the following on the final combined SB-03/04/05 candidate:

1. Plain and Ctrl window navigation in both monitor directions, both Ctrl keys,
   Ctrl held before pointer entry/released before a subsequent plain click,
   same-monitor activation, named workspaces, folded application/rail members,
   pins, minimized origins and target closure/address reuse.
2. Plain header focus versus Ctrl whole-workspace moves; menu exact targeting,
   no hover retargeting, live owner invalidation, inward popup bounds on both
   edges/bottom rows, large fonts and fractional scaling.
3. Actual pointer window/workspace drags, clipped/scrolled destination rows,
   changed source/target/host topology, resize conflicts, successful release,
   Escape/grab loss, no release click and bounded edge autoscroll.
4. Keyboard entry/re-entry, focus indication, all supported keys, popup dismissal,
   empty-dock/utility interactions and typing remaining with the intended app.
5. Full Omarchy/topbar coexistence, plugin validation, shell-aware lint, physical
   output/hotplug/reservation checks and cleanup. Virtual outputs alone do not
   establish physical-output qualification.

Preserve attribution for FDM-954: PR #79 recorded user-observed native coverage,
with its final exact-head confirmation left pending in the review record. The
merge is present; this source slice neither recreates that fix nor upgrades its
historical evidence. SB-06 establishes fresh native evidence on the integrated
candidate and owns demonstrated runtime fixes. No human code-approval ritual is
required, and no deployment is implied by remote source acceptance.
