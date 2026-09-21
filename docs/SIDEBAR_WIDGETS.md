# SB-05 — Internal sidebar widget contract

**FDM-967: internal widget foundation; it is not a universal plugin ABI.**
Classic remains the default. `sidebarWidgets` defaults to `[]`; that starts no
provider, loads no widget view and reserves zero footer height. FDM-970 now
registers the source-owned `herdr.agents` adapter on top of this contract.
Clock/calendar (FDM-969) and Todoist (FDM-971) remain independent follow-ups.
No credential, stock topbar change, second host or notification daemon is needed.

## Registration and typed configuration

`DockHost.sidebarWidgetRegistry` is a source-owned dictionary of internal IDs to
trusted descriptors. Each new adapter must register there and add exactly the same
ID to `config/settings-schema.json` → `sidebarWidgets.registeredIds`, with tests.
Do not populate it from settings, paths, commands, URLs, credentials or arbitrary
third-party QML. Tests inject the controller's registry, never the production one.

IDs are case-sensitive ASCII strings, at most 64 characters, matching
`^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$`; `constructor`, `prototype` and `__proto__`
are forbidden. Explicit set/apply writes reject unknown IDs, duplicates, incorrect
types and invalid syntax atomically. Registration, **not transient readiness or
authentication**, determines whether an ID can be written. Ordered arrays replace
the entire key; preference reset clears it. The Python client preflights `set`
against the live schema; the existing host validates every write authoritatively.

Imported requested IDs remain saved, including unknown IDs. Unrelated writes do
not delete or execute them. Effective normalization removes invalid syntax and
duplicates; `effectiveSettings.sidebarWidgets` contains registered IDs only.
`data.presentation.widgets` explains unavailable requested IDs and live lifecycle
state separately. An unavailable provider can remain registered and requested.

## Descriptor and lease API

A trusted descriptor supplies:

```javascript
{
  id: "example.internal",             // Source example, NOT a registered provider.
  label: "Example",                   // Short non-sensitive label.
  available: true,                    // Static capability; not an auth gate.
  status: "loading",                  // Initial capability metadata.
  revision: 1,                        // Descriptor/view revision, not snapshot revision.
  expandedView: expandedComponent,    // QML Component or null.
  compactView: compactComponent,      // QML Component or null.
  popupView: popupComponent,          // QML Component or null.
  acquire: function(owner) { return sharedAdapter.acquire(owner); }
}
```

`acquire(owner)` returns one **initially inactive** lease:

```javascript
{
  provider: sharedProviderQObject,
  setActive: function(active, publish) { /* provider-owned subscription scope */ },
  release: function() { /* release THIS owner only, exactly once */ }
}
```

Acquisition must be atomic: an exception must leave no partially acquired work.
`release` must clean up even after partial activation failure. Adapters own backend
reference counts and notification event de-duplication. They must never stop work
held by the topbar or another owner. Host code calls only lease methods, never a
shared service's `stop()` or `destroy()`. There is one manager on the host-owned
`DockSidebarController`, no process/provider per screen, slot, loader or popup.

Enable acquires once; disable/removal or host destruction releases once. Classic
mode and no usable screen suspend via `setActive(false, null)` while retaining the
lease. Resume activates the same lease. Collapse, resize, fold, title refresh,
view creation/destruction and popup changes do not reacquire or resubscribe.
Replacing an adapter's acquisition function or static availability is a deliberate
registry replacement and releases the old lease first. Replace descriptor snapshots
when changing metadata so QML observes the update. View-factory/descriptor revision
changes alone never restart the backend.

Each `setActive(true, publish)` receives a **new generation callback**. The provider
must replace its old callback, cancel sidebar-only pending work on suspension and
publish snapshots through the current callback:

```javascript
publish({status: "ready", revision: 17, data: { /* view-only snapshot */ }});
```

Status is `loading`, `ready`, `unavailable` or `error`. Snapshot revisions are
nonnegative safe integers, strictly increasing within an activation. Resume may
restart revision numbering. Duplicate/out-of-order updates and callbacks from a
suspended, released or replaced instance are ignored. Only ready snapshots retain
data. Malformed updates, acquisition/activation exceptions and view failures become
isolated error states; later valid updates recover without restarting the lease.
A failed acquisition/activation is not retried in a polling loop: repair/re-register
the adapter or explicitly disable/re-enable the ID.

## View API and failure isolation

Each factory's root is an `Item` with **non-required**
`property var widgetContext: ({})` and a sensible finite `implicitHeight`.
`DockSidebarWidgetView` injects a live binding immediately after Loader creation:

```javascript
{ id, status, revision, data, provider, presentation, openPopup, closePopup }
```

Factories must tolerate the initial empty context. `presentation` is `expanded`,
`compact` or `popup`. `openPopup()` routes to the controller using the owning slot's
anchor; `closePopup()` closes the single host. Views consume snapshots, never
acquire leases, subscribe, poll, or emit background notifications. Compact views
are read-only inside a native activation button. Expanded/popup views may expose
explicit provider actions. User data must be rendered as plain text, not markup
or executable input. Views must fit assigned width; long popup content scrolls.

Missing factories fall back to a bounded status button/message. Loader/context
errors are converted to `view-error`; a deferred failure is accepted only for its
exact provider-instance token, activation generation and snapshot revision. An old
view therefore cannot poison a removed/re-enabled or already recovered widget.
Failure unloads that view, not the window list or other providers.

## Geometry, routing and diagnostics

The widget area is **outside** `DockSidebarViewport`, above the ordinary application
and Trash utilities, with its own Flickable. For available content height A and
actual font-aware window-row height R, the cap is:

```text
min(240, floor(0.30 * A), max(0, A - 2 * R))
```

Its actual height is at most that cap/content height. A cap under two rows uses
compact slots; under one row uses the existing header's overflow button and zero
footer height. That button shares the collapse row rather than adding a header
row and creating a geometry feedback loop. Empty configuration has neither gap
nor overflow. Widget error/data changes do not disable workspace/window controls.

The controller owns `{widgetPopupId, widgetPopupAnchor}`. `"*"` is an internal
overflow sentinel, never a valid configured ID. The one `PopupWindow` is reused
for direct and overflow selections; overflow selection retains its original
header anchor rather than anchoring a popup to itself. It opens inward on either
edge, clamps its size/position in logical pixels and uses native slide adjustment.
Vertical bounds use the panel's available height, respecting other reserved
surfaces without guessed topbar dimensions. `grabFocus` is false and no view open
calls `forceActiveFocus`. Close/Back controls provide non-grabbing dismissal.

Removal, destroyed/hidden/scrolled-out anchors, collapse/layout changes, host/edge
changes, unplug and teardown close safely. Width/anchor movement reanchors; resize
may safely close if its footer layout changes. No open widget freezes window-model
refresh or creates another writer/input surface for the window list.

`widgetManager.diagnostics()` and CLI `data.presentation.widgets` expose counts
and at most 32 rows: ID, registered/available/status, revision, active and a fixed
error code; `total`/`truncated` cover longer lists. Counters saturate at 1 billion.
They omit provider objects, snapshot payloads, task/window text, raw exceptions,
credentials and tokens. No widget data is logged by the foundation.

## Verification and SB-06 handoff

Source gates:

```sh
node tests/test_sidebar_widgets.mjs
python3 -m unittest discover -s tests -p 'test_sidebar_widget_config.py'
node tests/test_sidebar_host.mjs
python3 -m unittest discover -s tests -p 'test_cli_docs.py'
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components
```

Then run the complete current Headless CI matrix on the exact final head.
`tests/tst_sidebarwidgets.qml` uses the **production controller and view loader**
plus `tests/fixtures/SidebarWidgetFixture.qml`; it instruments acquire/release,
backend start/stop/subscription/notification counts, errors, stale callbacks,
mode/reflow cycles, popup routing/anchor destruction and an outside shared owner.
The `fixture.one` provider used by these SB-05 tests is synthetic and test-only.
Production registration of `herdr.agents` is covered by FDM-970 lifecycle/provider
tests; this foundation suite still does not count as live Herdr data evidence.

`tests/runtime/sidebar.qml` additionally uses the real host, `DockSidebarWidgetArea`,
native popup, footer/overflow, viewport/delegates and layers. It checks both edges,
bottom placement, independent scrolling, compact/expanded factories, tiny/large-row
bounds, failure recovery, one popup, provider/anchor removal and teardown. Its
snapshots and provider are test fixtures, not live-data evidence.

**Runtime execution is deferred to FDM-968 / SB-06, not counted as a remote pass.**
Use an isolated actual Omarchy/Quickshell session (see `DEV_SESSIONS.md`), stop that
guest's normal dock, and run:

```sh
SMARTDOCK_ISOLATED_RUNTIME=1 bash tests/runtime/check-sidebar.sh
```

SB-06 must also observe actual pointer/keyboard focus, both real monitor edges and
bottoms, hotplug, fractional scaling/real large-font settings, full-shell topbar
coexistence and integrated SB-03/SB-04 interactions on one final exact candidate.
No model/rectangle test, synthetic state or pure-Qt result substitutes for that.
