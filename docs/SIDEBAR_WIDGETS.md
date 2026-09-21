# SmartDock sidebar Widget contract

**FDM-967 owns provider lifecycle; FDM-973 owns the shared-scroll Widget area and management foundation; FDM-970 registers the source-owned `herdr.agents` provider.**
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

## Shared-scroll layout, management and persistence

The normal Widget section is a content tail of the existing
`DockSidebarViewport` hierarchy `ListView`. It does not own a second normal
Flickable, scrollbar, height cap, compact-footer mode or overflow mode. Hierarchy
rows remain Monitor/Workspace/Window domain rows; Widget cards are not injected
into `visibleRows` or section-span keys.

The expanded content order is hierarchy first, then the Widgets section. Pinned
and Applications stay fixed below that shared viewport. Rail mode gives the
Widget tail zero height. With zero enabled Widgets the section itself also has
zero height; the expanded SmartDock header still exposes Add/Manage so an empty
configuration is discoverable.

`sidebarWidgets` remains the canonical ordered list for both enabled state and
Widget order. Add/remove/reorder always go through the existing host settings
mutation path. Runtime schema readback injects IDs from the trusted source
registry; transient provider readiness does not decide whether an ID is writable.
Unknown imported IDs remain requested/unavailable according to the FDM-967 rules.

Per-card body state is stored independently:

```json
"sidebarWidgetCollapsed": {
  "example.internal": true
}
```

Keys use the same internal Widget-ID syntax and values are booleans. Missing keys
mean expanded. Removing a Widget intentionally leaves its collapse preference in
place, so re-adding the same ID restores it. A collapse map never enables or
executes a provider by itself.

`DockWidgetCard.qml` owns the common card header/chrome: icon, title, optional
count badge, drag affordance, collapse control, body clipping/status placement,
keyboard focus and the **Remove from Widgets** context action. The normal body
uses the existing descriptor `expandedView`. `compactView` remains in the
provider ABI for compatibility but is not used by the expanded sidebar area;
`popupView` remains available through the single host-owned Widget popup.

Drag starts from the card drag affordance, computes insertion boundaries only
among Widget cards and uses the hierarchy viewport's edge auto-scroll. It cannot
drop into Monitor/Workspace/Window rows or reorder with Pinned/Applications.
Reorder and collapse are presentation/settings changes only: the host-owned
provider manager keeps the same leases/subscriptions.

The controller still owns `{widgetPopupId, widgetPopupAnchor}` for
Widget-specific popup content. There is no normal-card overflow sentinel.
Destroyed/hidden/scrolled-out anchors, removal, collapse, host invalidation and
surface teardown close safely. The Add/Manage picker is a separate non-grabbing
popup that lists trusted source descriptors and routes add/remove back through
the controller.

`widgetManager.diagnostics()` and CLI `data.presentation.widgets` retain the
bounded, payload-free lifecycle diagnostics from FDM-967.

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

**Real compositor/pointer qualification remains a local follow-up (FDM-974), not a remote source pass.**
Use an isolated actual Omarchy/Quickshell session (see `DEV_SESSIONS.md`), stop that
guest's normal dock, and run:

```sh
SMARTDOCK_ISOLATED_RUNTIME=1 bash tests/runtime/check-sidebar.sh
```

SB-06 must also observe actual pointer/keyboard focus, both real monitor edges and
bottoms, hotplug, fractional scaling/real large-font settings, full-shell topbar
coexistence and integrated SB-03/SB-04 interactions on one final exact candidate.
No model/rectangle test, synthetic state or pure-Qt result substitutes for that.


## Reusable Widget UI kit and gallery (FDM-975)

FDM-975 adds a presentation-only UI kit under `components/widgets/`. It does
not add a registry, provider manager, provider process, settings writer or service
integration. Widget bodies continue to receive the existing FDM-967/FDM-973
`widgetContext`; the kit only standardizes how those bodies render and interact.

The approved visual contract is preserved verbatim in the repository at
[`docs/widget-gallery/reference/approved-widget-mockup.html`](widget-gallery/reference/approved-widget-mockup.html).
That HTML remains the design reference. The executable coding-agent boilerplate is
[`tests/widget-gallery/WidgetGallery.qml`](../tests/widget-gallery/WidgetGallery.qml)
and uses synthetic data only.

The canonical body primitives are:

- display: `WidgetText`, `WidgetBadge`, `WidgetStatus`, `WidgetDivider`,
  `WidgetSection`, `WidgetList`, `WidgetListItem`, `WidgetChecklist`,
  `WidgetKeyValue`, `WidgetStat`, `WidgetStatGrid`, `WidgetProgressBar`,
  `WidgetMeter`, `WidgetActivity`, `WidgetSparkline`, `WidgetIconText`;
- icons: one `WidgetIcon` for Lucide names or arbitrary SVG/raster sources,
  theme tint versus brand-preserved rendering, shared size tokens,
  `plain | soft | outlined | tile` containers and bounded fallback;
- forms: `WidgetFormField`, `WidgetTextInput`, `WidgetSearchInput`,
  `WidgetTextArea`, `WidgetNumberInput`, `WidgetSelect`, `WidgetCheckbox`,
  `WidgetToggle`, `WidgetRadioGroup`, `WidgetSegmentedControl`;
- actions: `WidgetButton`, `WidgetIconButton`, `WidgetButtonGroup`;
- framework states: `WidgetState` with `loading | empty | unavailable | error | stale`.

Use semantic values such as `success`, `warning`, `danger`, `urgent` and
`overdue` rather than service-provided colors. Widget bodies can pass
`reducedMotion: true` to `WidgetState` and attention rows; nonessential loading
or nudge animation then stops while the semantic state remains visible.

`DockWidgetCard.qml` remains the single card shell from FDM-973. Its header now
uses the same `WidgetIcon` primitive as bodies/actions/states, and its no-view
surface uses `WidgetState`; provider acquisition, collapse/reorder persistence,
Add/Manage ownership and shared-scroll ownership are unchanged.

For a new Widget body, copy a composition from the gallery instead of creating
parallel typography, icon, form, action or state controls. Keep the root as an
`Item` with non-required `property var widgetContext: ({})`, consume snapshot
data as plain text, and leave provider/settings ownership in the existing host.

Focused source checks:

```sh
node tests/test_widgetkit_structure.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import components
python3 -m unittest tests.test_sidebar_qml_syntax
```

Real compositor/pointer/theme/font qualification remains FDM-974 after this
source slice is accepted.
