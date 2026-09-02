# Launcher badge count architecture

FDM-811 extends FDM-809's shared application-badge ownership with authoritative
numeric counts supplied by applications. It does **not** derive unread totals
from notifications, window titles, accessibility APIs, application databases,
or any polling loop.

## Decision

Use a small native QtDBus provider, owned once by the Omarchy SmartDock service,
and expose only a provider-neutral QML snapshot to the existing
`DockBadgeTracker`.

The resulting ownership chain is:

```text
Omarchy plugin registry
  -> Service.qml (one headless service instance)
    -> DockLauncherBadgeService.qml (one provider process owner)
      -> smartdock-launcher-badge-provider (QtDBus)
        -> atomic provider snapshot
  -> Overlay.qml
    -> shell.serviceFor("io.github.fernandodamaso.smartdock")
      -> DockHost.qml
        -> one DockBadgeTracker
          -> every per-screen Dock
```

Standalone `shell.qml` does not instantiate the provider service. It therefore
remains null-safe and uses the FDM-809 dot sources only.

## Source evidence

The architecture was selected from repository/source evidence rather than by
adding an ad-hoc shell parser.

### Omarchy service ownership is supported

Omarchy's shell plugin documentation describes `service` as a headless
singleton plugin kind and explicitly permits one plugin to declare multiple
kinds. The shell service registry exposes services through `serviceFor`, while
`firstPartyServiceFor` delegates to that registry for first-party callers.
Third-party plugins are cloned/validated as source; Omarchy does not execute an
install hook while adding a plugin. Relevant upstream source at the time of the
design:

- <https://github.com/omacom/omarchy/blob/d3d23fdddef846ebb98b52122a6ece66211c0daf/manual/32-shell-plugins.md>
- <https://github.com/omacom/omarchy/blob/d3d23fdddef846ebb98b52122a6ece66211c0daf/shell/shell.qml>

No existing Omarchy service providing application launcher badge counts was
found in the inspected source. SmartDock therefore cannot safely depend on an
upstream count service today.

### Quickshell does not currently supply the required public provider contract

The inspected Quickshell source uses Qt DBus internally for built-in services,
but no public generic LauncherEntry/QML provider contract was found that could
replace a dedicated adapter:

- <https://github.com/quickshell-mirror/quickshell/tree/2d3b3e9c70ef380dff751b61d334dc88df016c29>

A future supported Quickshell launcher-badge service can replace the native
adapter without changing `DockBadgeTracker`: the QML contract is deliberately
only `available`, `revision`, and `counts`.

### Unity LauncherEntry is an established application protocol

KDE Plasma's task manager listens for
`com.canonical.Unity.LauncherEntry.Update`, normalizes the `application://`
launcher identity, consumes `count` / `count-visible`, and clears state when a
sender disappears:

- <https://github.com/KDE/plasma-desktop/blob/6467f7988197b214aa7c7d7d8d2ba4a3f9ae7381/applets/taskmanager/smartlauncherbackend.cpp>

Electron's 2026 Linux launcher implementation emits the same interface/path,
uses the application's desktop ID as `application://<desktop-id>`, and sends an
`int64` `count` plus boolean `count-visible`:

- <https://github.com/electron/electron/blob/bd08e477fbb152387f7e35ba7ba9866b8003455f/shell/browser/linux/launcher_entry.cc>

That evidence supports a small typed QtDBus listener without polling or text
stream parsing.

## Provider contract

`DockLauncherBadgeService.qml` exposes:

```text
available: bool
revision: int
counts: {
  "canonical.desktop.id": {
    "count": non-negative integer,
    "visible": bool
  }
}
```

The native provider owns sender metadata internally; sender identities are not
part of the UI contract.

Launcher identities accept either a desktop-entry ID or an
`application://...desktop` URI. Normalization trims whitespace, decodes valid
percent escapes, strips one `.desktop` suffix, folds case, and rejects path
separators, other URI schemes, dot traversal, and malformed percent escapes.
There is no substring or fuzzy mapping.

Unknown but syntactically valid launcher IDs are retained as provider-neutral
state. They are harmless because the dock queries counts only for exact visible
desktop IDs. Malformed launcher identities are dropped.

## Update and reconnect semantics

The protocol is partial-update based. `count` and `count-visible` are applied
independently and omitted properties preserve the current field for the same
D-Bus sender.

A different sender updating the same launcher establishes fresh ownership. Its
record starts empty before that sender's supplied fields are applied, so stale
fields cannot leak across an application restart. When a watched sender
unregisters, all records still owned by that sender are removed.

The provider registers the established `com.canonical.Unity` well-known name
when it is available. Existing desktop implementations use that name to make
the launcher service discoverable. The LauncherEntry protocol itself is
signal-based and has no generic initial-query method, so a real application's
startup/reconnect re-publication behavior must be validated on the pinned
Omarchy runtime. SmartDock does not compensate for a non-republishing
application by polling or scraping it.

Provider state is written with `QSaveFile` to an XDG runtime/cache path as one
atomic JSON snapshot. The QML service reads that finite snapshot with
`FileView`; it never parses a long-running stdout stream. Provider exit clears
QML availability immediately and schedules a bounded event-driven restart.

## Rendering rules

`Dock.qml` retains FDM-809's `isPrimaryVisibleItem()` ownership gate. FDM-811
therefore cannot double-render a badge when window grouping is disabled.

With `attentionBadgesEnabled=true`:

- `launcherBadgeMode="automatic"`: a positive authoritative count with
  `visible=true` replaces the dot; values over 99 render as `99+`.
- Explicit zero or `visible=false`: no number is rendered; a current FDM-809
  attention/urgent dot may still render.
- `launcherBadgeMode="dots-only"`: provider counts are ignored and FDM-809
  behavior is preserved.
- Provider unavailable: equivalent to no authoritative count; FDM-809 remains
  the fallback.

Existing severity still styles the badge. If the application is urgent while a
number is visible, the numeric badge uses the urgent treatment. FDM-811 does
not consume the protocol's optional `urgent` property because this issue owns
numeric counts only.

Focusing an application may clear only FDM-809's local notification-derived
attention after its existing dwell. Focus never changes authoritative provider
count state.

Hidden applications are absent from the dock's visible-item model, so they do
not render a count or dot. Provider state can remain alive while the application
is hidden and is queried again if the item becomes visible. Configuration
reloads normalize an invalid `launcherBadgeMode` back to `automatic`.

## Build and packaging

Omarchy plugin installation does not compile native code. The optional provider
must be built explicitly from a trusted SmartDock source checkout:

```bash
bash ./scripts/build-launcher-badge-provider
```

The build uses an XDG cache directory instead of creating a repository-local
build tree, runs CTest, then installs the provider executable to:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/smartdock/providers/
```

The QML service probes that exact executable path once. If it is absent,
SmartDock remains in dot fallback mode. No failed-provider fallback launches a
shell parser or polling process.

Build requirements are CMake, a C++20 compiler, and Qt 6.6+ Core, DBus, and Test
development files. The pure provider state model can be tested without Qt:

```bash
bash provider/launcher-badges/tests/run-model-test.sh
```

## Local continuation checklist

Repository-only work cannot prove the target Omarchy runtime or a real
supporting application's behavior. Before merging, validate on the pinned local
Omarchy/Quickshell/Qt environment:

1. Build the provider and run CTest; record exact Omarchy, Quickshell, Qt, and
   provider build versions.
2. Start with no prior state and verify an application publishes its initial
   `count`/`count-visible` after `com.canonical.Unity` becomes available.
3. Verify partial count update, hide (`count-visible=false`), explicit clear
   (`count=0`), and re-show behavior.
4. Kill/restart the supporting application and provider independently; verify
   sender cleanup, fresh ownership, and count re-publication without stale
   fields.
5. Inject the malformed and unknown launcher fixtures; malformed input must be
   ignored, while unknown valid IDs must not badge unrelated dock items.
6. Leave the provider idle and inspect CPU usage and wakeups; there must be no
   periodic provider polling.
7. Run standalone SmartDock with no provider service and confirm the FDM-809 dot
   fallback remains null-safe.
8. Validate one real supporting application when available. Record the exact
   desktop ID and whether its initial/reconnect publication semantics match the
   protocol assumption.

Do not mark real provider/runtime validation complete based only on repository
or fixture tests.
