# Chrome Activity Hover Design

Date: 2026-09-14

Status: Approved in chat; awaiting written-spec review

## Summary

Extend SmartDock's existing Chrome window-preview popup with an activity section
that shows unread counts exposed by recognized browser tabs. The Chrome dock
icon shows the combined browser-derived count when no authoritative
LauncherEntry count exists. Clicking an activity row focuses the owning Chrome
window and activates that exact tab.

This design uses the existing Chrome DevTools Protocol (CDP) browser-profile
provider. It does not inspect page DOM, persist message content, add a browser
extension, or create another recurring process.

## Goals

- Show recognized unread web applications above Chrome's existing window
  previews.
- Show a combined numeric count on the Chrome dock icon.
- Activate the exact tab represented by a row.
- Preserve current behavior when CDP, the optional provider, or recognized
  unread state is unavailable.
- Keep the feature compatible with current browser-profile provider installs
  and SmartDock's standalone null-safe behavior.

## Non-Goals

- A generic notification parser for arbitrary websites.
- Message subjects, sender names, snippets, or page DOM scraping.
- A browser extension or authenticated Gmail/WhatsApp API integration.
- Managing, closing, pinning, or reordering browser tabs.
- A new configuration surface or a second popup.

## User Experience

Concept A, the Combined Activity Card, becomes Chrome's existing hover surface.
The header identifies Chrome and shows the combined unread total. Recognized
positive-count services appear first as clickable rows. Each row shows the
service icon, service name, browser profile name when available (otherwise its
domain), and unread count. Existing Chrome window preview tiles remain below a
separator when at least two Chrome windows are represented.

The popup opens when `showPreviews` is enabled and either recognized unread
activity exists or the Chrome item has at least two live windows. With one
window and unread activity, only the activity section is shown. With no unread
activity, existing grouped-window preview behavior is unchanged.

Rows are ordered by descending unread count, then stable service name. A click
focuses the owning Chrome window and selects the exact target. Zero-count rows
are omitted. The popup retains its current open delay, hover handoff, close
grace period, dock-relative anchoring, clipping checks, and screen-bounded
scrolling.

The Chrome icon badge displays the sum of the visible reduced activity rows and
uses the existing `99+` presentation. Count-only changes do not trigger urgent
motion. Existing attention or urgency severity continues to style a visible
count and remains eligible for current bounded motion.

## Count Semantics

The initial recognized services are:

| Service | Origin | Accepted title signal |
| --- | --- | --- |
| WhatsApp | `https://web.whatsapp.com` | A leading positive integer in the established `(10) WhatsApp` form |
| Instagram | `https://www.instagram.com` | A leading positive integer in the established `(4) Instagram` form |
| Gmail | `https://mail.google.com` | A positive integer in a supported English or Portuguese inbox-title form on the exact inbox route |

Parsing is origin-specific. Numbers in titles from unknown origins are never
treated as unread counts. Invalid, negative, zero, overflowed, or ambiguous
signals produce no activity row.

For duplicate tabs belonging to the same service and browser profile, only the
highest positive count contributes. This prevents two WhatsApp tabs showing the
same account count from doubling the badge. Supporting multiple independent
accounts of the same service inside one Chrome profile is deferred until a
non-sensitive account key can be derived and validated.

## Provider Data Flow

The existing `provider/browser-profiles/browser_profile_provider.py` polling
loop already retrieves CDP page targets, groups targets by Chrome browser window,
matches Chrome browser windows to Hyprland addresses, and resolves browser
profiles. The same pass will derive activity rows. No additional polling loop is
introduced.

The provider snapshot keeps schema version 1 and adds optional fields. Existing
QML consumers ignore those fields, while updated consumers interpret absence as
no browser activity. A representative additive contract is:

```json
{
  "schemaVersion": 1,
  "available": true,
  "classes": ["google-chrome"],
  "port": 9222,
  "windows": {
    "0x123": "Profile 1"
  },
  "profiles": {},
  "activities": {
    "0x123": [
      {
        "targetId": "30512CE29E2EAEB3E32228BBC7F6DE78",
        "serviceId": "whatsapp",
        "label": "WhatsApp",
        "profileKey": "Profile 1",
        "count": 10
      }
    ]
  }
}
```

Only rows associated unambiguously with a mapped Hyprland Chrome window are
published. `classes` contains the exact browser window classes configured for
that provider process and lets QML match the browser desktop entry without a
hardcoded desktop ID. Full target URLs and titles are used transiently for
recognition but are not written to the snapshot. Snapshot change detection
includes activity records so title-count changes publish within the provider's
existing interval.

`DockBrowserProfileService.qml` validates and exposes activity rows by window
address, an ordered reduced list for a dock item, and its aggregate count.
Invalid optional activity fields are ignored without invalidating otherwise
usable profile state.

## Badge Integration

`DockBadgeTracker.qml` receives the existing browser service and asks it for a
Chrome item's reduced count. Badge count precedence is:

1. An authoritative Unity LauncherEntry record owns the numeric decision. A
   positive visible value renders; explicit zero or hidden state suppresses the
   browser-derived fallback.
2. With no authoritative LauncherEntry record, a positive browser-derived count
   may render for a recognized Chrome desktop ID.
3. The existing attention or urgent dot.
4. No badge.

`launcherBadgeMode="dots-only"` suppresses both numeric sources while retaining
the activity rows. `attentionBadgesEnabled=false` suppresses icon badges while
retaining activity rows. `browserProfileBadgesEnabled` continues to control only
profile artwork and does not disable activity discovery. No new setting is
added.

Chrome identity matching remains strict and uses the existing configured
browser desktop IDs/aliases. Browser activity must never badge another
application merely because its title or desktop-entry name contains Chrome.

## Exact-Tab Activation

The provider executable gains a one-shot
`--activate-target <target-id> --port <port>` mode. It validates the target ID
as a bounded hexadecimal CDP identifier, accepts only a valid local TCP port,
connects to the loopback DevTools endpoint recorded in the current snapshot,
invokes `Target.activateTarget`, and exits. It does not navigate, create, close,
or inspect a page.

`DockBrowserProfileService` owns one bounded activation `Process`. The QML
command is an argument array, not shell text. On row click, SmartDock first uses
the shared host-owned `DockWindowActions` instance to activate the mapped Chrome
window, then runs the one-shot target activation. If the target disappeared,
the Chrome window may still receive focus but no replacement tab is opened.

The activity record is revalidated against current provider state before the
action. Concurrent clicks while one activation is in flight are ignored; this
is a human-scale hover action and does not need a command queue.

## Popup Composition

The activity section is added to `DockWindowPreview.qml`; the component retains
its dock-specific popup ownership, grouped-member lifecycle, clipping, hover
handoff, and orientation-aware anchoring. The row composition stays local to
that popup.

The popup's desired size becomes the bounded size of the activity section plus
the existing preview flow. The activity list and preview flow share one
scrollable viewport. Horizontal docks keep preview tiles in a row; vertical
docks keep them in a column. Activity rows remain a vertical list in both
orientations.

Service icons use known local/themed artwork or a deterministic text fallback.
The feature does not fetch remote favicons. All labels are plain text and
elided. Rows expose button role, a name such as `Open WhatsApp tab, 10 unread`,
an accessible press action, and visible pointer hover. The passive hover popup
retains `grabFocus: false` and does not add a separate keyboard-focus model.

## Native Omarchy UI Audit

Inspected installed Omarchy package revision `4.0.3-1` under
`/usr/share/omarchy/shell` on 2026-09-14.

Inspected primitives:

- `shell/Ui/PopupCard.qml`
- `shell/Ui/BorderSurface.qml`
- `shell/Ui/Button.qml`
- `shell/Commons/Color.qml`
- `shell/Commons/Style.qml`
- `shell/Commons/Border.qml`
- `shell/Commons/Util.qml`

Inspected representative first-party uses:

- `shell/plugins/services/media/BarWidget.qml` for `PopupCard`, semantic
  spacing, typography, separators, and `Button` controls.
- `shell/plugins/bar/widgets/Tray.qml` for popup list-row composition and
  compact `Button` actions.
- `shell/plugins/notifications/components/NotificationCard.qml` for clickable
  icon/text card composition using `BorderSurface`, semantic tokens, plain-text
  labels, and accessibility-aware pointer behavior.

`PopupCard` is not adopted because it requires Omarchy bar ownership and
`requestPopout` coordination and does not provide SmartDock's clip-item checks,
grouped-window refresh contract, four-edge geometry, or hover-preview session
lifecycle. `Button` is not used as the whole activity row because its fixed
single-line icon/text content contract cannot express the required service
icon, secondary profile label, trailing count, and target-specific accessible
name without replacing its internals.

The existing custom `PopupWindow` and domain row are retained. They compose
Omarchy `BorderSurface`, `Color`, `Style`, `Border`, and `Util` tokens and follow
the first-party notification/list-row patterns. No parallel generic surface or
button library is added.

## Failure And Privacy Behavior

- Provider absent or executable unavailable: no activity rows or browser count;
  current behavior remains.
- CDP unavailable: clear browser activity and profile state using the current
  provider failure path.
- Unknown title form: ignore the target rather than infer a count.
- Ambiguous browser-window mapping: omit that target from activity state.
- Malformed optional snapshot data: ignore malformed rows and keep valid profile
  data.
- Closed target during activation: fail quietly and do not open another tab.
- Profile unavailable: show the service domain as secondary text.

The runtime snapshot contains no full URL, page title, account email, message
content, sender, or notification body. It is written atomically to the existing
owner-scoped XDG runtime/cache location.

## Delivery Sequence

Implementation is split by a mandatory frontend review checkpoint.

### Phase 1: Frontend With Mocked Activity

Implement the Combined Activity Card layout and its presentation model before
changing the browser provider. `DockWindowPreview` consumes an injected activity
list with the final record shape. A focused QML test/demo harness supplies the
approved WhatsApp `10` and Gmail `13` records, profile labels, one-window and
multi-window states, overflow, hover, and empty-state cases.

The production host must not gain a permanent mock setting or write mock records
to user configuration. If a temporary source-only runtime binding is needed for
visual inspection, it is isolated from normal plugin and standalone entry
points. Phase 1 stops for visual acceptance of the real QML surface before CDP,
snapshot, badge-source, or activation work begins.

### Phase 2: Live Browser And Window Integration

Extend the existing browser provider snapshot, connect
`DockBrowserProfileService`, add Chrome badge precedence, and implement exact-tab
activation through the owning Chrome window. Replace any temporary source-only
mock binding with live service data. Keep deterministic mock records only in the
test/demo fixture so the approved frontend remains independently testable.

Phase 2 then performs provider, QML, repository-gate, and real-browser runtime
validation. Documentation is updated only after the live integration behavior
is validated.

## Validation

Provider checks cover strict WhatsApp and Gmail title parsing, unknown origins,
invalid counts, duplicate reduction, aggregation, browser-window association,
snapshot change detection, target-ID validation, successful activation, and
stale-target failure.

QML/model checks cover popup eligibility with one window, current two-window
fallback, descending row order, zero-count omission, aggregate badge count,
`99+`, LauncherEntry precedence, dots-only mode, disabled attention badges,
provider loss, malformed optional rows, and accessible row labels.

The normal repository validation gate remains required. Runtime acceptance also
requires real background WhatsApp and Gmail tabs, a count changing while the tab
is inactive, two Chrome windows, exact-tab activation in each window, duplicate
tabs, profile labels and fallback labels, provider restart, CDP loss, and no
count leakage to non-Chrome dock items.

## Expected Source Scope

- `provider/browser-profiles/browser_profile_provider.py`
- Browser-provider tests under `provider/browser-profiles/`
- `components/DockBrowserActivityModel.js`
- `components/DockBrowserProfileService.qml`
- `components/DockBadgeTracker.qml`
- `components/Dock.qml`
- `components/DockItem.qml`
- `components/DockWindowPreview.qml`
- Focused QML/model tests under `tests/`
- A source-only mocked visual harness under `tests/runtime/`
- `README.md` and the relevant provider/feature documentation

No configuration key, browser extension, new native provider, or new generic UI
component is expected.
