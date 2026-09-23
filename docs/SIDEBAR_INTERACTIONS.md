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

A captured individual window moves and follows to a visible workspace group,
new-workspace slot, or explicit monitor header. Workspace groups share their
painted inset/gap geometry with hit testing; the first hit is final even when
ineligible. Footer slots appear on every monitor while a window is dragged,
not only the hovered one. No predicted workspace number is displayed. Workspace
sources retain whole-monitor-card targets and sorted, view-only placeholders.

A header resolves its monitor's active workspace through the live workspace
inventory. Its owner must equal that monitor at hover, release, and immediately
before dispatch. Missing/changed identities or owner disagreement reject the
drop with zero dispatch; an existing workspace is never relocated to repair a
stale header. The shared `moveCapturedToplevels(..., true)` action preserves
captured member identity, pins, minimized restoration, named-workspace backend
eligibility and ordered follow behavior. Ctrl-click uses the extracted active
workspace lookup without changing its existing semantics.

**Provisional Draft policy:** dropping on the current monitor's header from a
different workspace moves to its active workspace (the R1 proposed default).
The internal `headerDropWithinMonitor` guard isolates this branch. Owner
acceptance is still required before Task 4 merges; source execution is not a
record of that product decision. Dropping into one's current workspace is a no-op.

Only header/top and unclaimed bottom padding are window-to-monitor targets.
Workspace content, separators, side gutters, Widget tail, footer extra height,
offscreen/clipped areas and gaps between cards cannot fall through to a header.
Window pins and workspace monitor pins have distinct rejection labels. A dimmed
source and clipped, theme-aware pill identify the source and destination without
creating another window. The collapsed rail shows artwork only. Edge scrolling
remains bounded to 12 logical pixels per 16 ms tick and stops outside the viewport;
hit testing is repeated after geometry/scroll changes and at release.

Presentation ordering freezes while dragging, not live action validity. Closure,
address reuse, source location changes, target-owner changes, topology changes,
mode/edge/host/collapse invalidation, Escape and native grab cancellation abort
without a partial move. Resize, menus and row drags share the existing busy
boundary. Qt `UngrabExclusive` is the successful release; becoming inactive alone
is not permission to commit. A completed or cancelled gesture consumes its click.

## Post-dispatch feedback

The gesture ends before submission and releases its busy boundary. A separately
bounded operation captures the exact toplevel/native handle/address (or workspace
identity), expected workspace and monitor, token, deadline, originating connector
and unique viewport generation. New-workspace identity comes from the shared
action's **single-submission receipt**, not a preview allocation. Existing boolean
callers remain strict booleans.

A transport acknowledgment means **pending**, not success. Confirmation requires
consistent live identity, workspace, window monitor and workspace owner readback.
Minimized storage, replacement handles and conflicting inventories do not confirm.
The initial wait bound is 1500 ms, driven by existing refresh signals plus one
single-shot deadline timer. Timeout/ambiguous submission means **Move not confirmed**;
there is no rollback, compensating move, retry or late feedback revival.

Only known pre-dispatch rejection/cancellation can animate the captured artwork
back to its still-exact, visible source (200 ms). An absent/offscreen source or
reduced-animation preference receives cleanup without a false return animation.
Confirmed feedback waits for projection and queued scroll restoration to settle,
resolves the current row, uses `ListView.Contain` and saves its resulting anchor
before the 400 ms accent flash. Folded/absent windows only permit a verified visible
workspace-group fallback, never unfolding, focus stealing or a different window.
Only the originating live viewport participates; mirrored panels keep independent
connector × expanded/rail anchors. New gestures, topology/surface changes and
teardown invalidate outstanding tokens, timers and queued callbacks.

### Native qualification matrix (FDM-995 — not yet qualified)

| Area | Cases to qualify in the exact-head, fresh two-output KVM guest |
| --- | --- |
| W1/W5/G1 source feedback | Window/workspace dimming, numeric/named labels, pins, rejected-to-valid transition, expanded and rail pills, clipping and closed-hand grab |
| W2/W4 geometry | Group fill without outline, final group, shared boundaries, autoscroll, all-monitor dashed slots, blocked slots, footer/header/Widget-tail exclusion |
| W3 header drop | Cross-monitor active workspace; same-monitor other-workspace provisional policy; stale/missing active owner; release revalidation; minimized/named sources; no workspace relocation |
| Workspace card drop | Card border/fill, numeric/named sorted placeholders, empty monitors, pin/same-monitor refusal |
| Confirmation | Existing/new workspace and workspace-source moves, delayed/inconsistent readback, timeout then late success, no rollback, captured-source closure/replacement |
| W6/W7 finish | Real `UngrabExclusive`, escape/grab cancellation, safe refusal snap, 400 ms confirmed flash, reduced animation, fresh drag/teardown during feedback |
| Scrolling and lifecycle | Offscreen success after queued restore, folded/absent fallback, two mirrored panels/mixed modes, origin destroy/recreate, topology change, live reload |

Inspect the exact candidate in a fresh named guest per `docs/DEV_SESSIONS.md`;
record captures/results and stopped-state evidence. No installed-plugin edit or
physical desktop preview is authorized by source execution.

### Native UI composition inspected

Omarchy `947e2fc002d6831c7888b29b5761d59d29e69727`: `shell/Ui/BorderSurface.qml`,
`PopupCard.qml`, `shell/Commons/Style.qml`, and first-party `shell/plugins/bar/widgets/Tray.qml`.
Inline ghosts compose `qs.Ui.BorderSurface` with popup colors, native border/font/
spacing/state tokens. `PopupCard` would add a window and is deliberately not used.
The domain-only `DockSidebarDropSlot` paints dashed decoration because BorderSurface
has no dashed-edge API; it owns no input, action, settings or window lifecycle.

## Source checks

`tst_sidebardropfeedback.qml` reads trusted repository methods into a real Qt Quick
ListView harness. `QML_XHR_ALLOW_FILE_READ=1` is test-only; file writes stay disabled.
This exercises real `Qt.callLater` callbacks, not compositor/native qualification.

```bash
node tests/test_sidebar_actions.mjs
node tests/test_sidebar_drag.mjs
node tests/test_sidebar_drop_confirmation.mjs
node tests/test_sidebar_drop_scroll.mjs
node tests/test_grouped_actions.mjs
node tests/test_session_pins.mjs
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_sidebarinteraction.qml -import components
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
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
