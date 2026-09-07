# SmartDock attention badges

FDM-809 adds application attention indicators without pretending SmartDock
owns unread-message counts. Ordinary attention uses Omarchy's accent color and urgent/critical attention
uses the urgent color. Application-provided numeric badges take precedence
over dots in automatic count mode; dots-only mode keeps severity indicators.

## Sources and reduction

SmartDock reduces three sources into one application badge:

1. A live StatusNotifierItem whose status is `NeedsAttention` contributes
   ordinary attention.
2. A live Hyprland toplevel whose `urgent` property is true contributes urgent
   attention.
3. An event observed from Omarchy's `omarchy.notifications` service contributes
   ordinary attention, or urgent attention when notification urgency is
   critical.

Severity wins during reduction: urgent beats ordinary attention. Live SNI and
Hyprland state is read directly and is never cleared from SmartDock's local
notification state. The Omarchy notification service is optional; standalone
SmartDock continues with SNI and Hyprland sources and never creates its own
notification server.

The Omarchy integration observes the service's popup model when notifications
arrive or are updated. Removing, expiring, or dismissing a popup is not treated
as reading the application, so the local dot remains until focus dwell or TTL
clears it. Notifications that Omarchy does not expose through that live model
cannot be inferred by SmartDock.

## Identity matching

Attention identity is intentionally stricter than SmartDock's existing window
association logic. Badge matching only compares normalized exact values from:

- the dock desktop-entry ID;
- the desktop entry's `id`;
- the desktop entry's `startupClass`;
- the desktop entry's display `name`; and
- aliases explicitly listed in `DockBadgeTracker.identityAliases`.

Normalization trims whitespace, lowercases, and removes a final `.desktop`.
It does not remove punctuation, perform substring matching, derive browser app
IDs from URLs, or otherwise guess that two applications are the same. This is
why FDM-809 does not reuse the existing fuzzy web-app window-grouping matcher.

## Local lifetime and focus

Omarchy notification attention is kept in `PersistentProperties` so a QML
reload inside the same process does not immediately erase a dot. SmartDock does
not write this state to disk.

- A replacement with the same notification `originalId` replaces the previous
  local record rather than creating another badge source.
- Local notification attention expires after 24 hours.
- Local notification attention clears only after the matching application has
  remained focused for 800 ms.
- Focus clearing does not override a live SNI `NeedsAttention` item or a still
  urgent Hyprland toplevel.
- Hidden applications keep their local records in memory. Showing the app in
  the dock again can therefore restore its dot while that record remains live.

## Grouped and ungrouped rendering

Grouped applications render one dot on their one dock item. When window
grouping is disabled, SmartDock renders the application badge only on the first
visible item with that exact desktop-entry identity. Other per-window items do
not duplicate the dot.

With `workspaceLayout: "grouped"`, window urgency comes only from each item's
actual members. A known live handle urgency value wins over IPC data, including
live false overriding stale true. Collapsed cards show static urgency; their
application delegates and reminder timers do not exist.

Application notifications, SNI attention, and launcher counts remain app-wide.
`isPrimaryVisibleItem()` selects one owner from actual rendered items, with the
active workspace before global launchers and fallback items. Every urgent local
member remains marked even when another item owns the app-wide badge. A launcher
count of 7 does not change a workspace's count of two windows. Clearing either
notification attention or window urgency leaves the other source intact.

Sticky windows appear once on their monitor's active normal workspace with a
small outlined marker and tooltip. Minimized windows instead use their validated
saved origin, retaining a card when its compositor descriptor disappears. Live
workspace ownership takes precedence over saved monitor metadata, with connector
names and IPC ids joined against the current monitor inventory. Unresolved
monitor membership stays in Other windows and never contributes to normal counts.

Set `attentionBadgesEnabled` to `false` to hide attention dots without deleting
local attention state. Re-enabling the setting resumes rendering from the
current live/local state.

## Urgent-window motion

Motion eligibility is reduced from the attention sources independently of the rendered badge token. SNI
`NeedsAttention`, critical local-notification attention, and Hyprland urgent
window state can trigger the nudge. A positive launcher count without attention
never triggers it; a count coexisting with attention still does. A previously
absent **Hyprland urgent window address** entering an application's
urgent-address set creates a motion revision, while duplicate urgency for an
address that remains urgent does not. Titles, notification bodies,
terminal/editor output, sender data, and window content do not trigger motion
and are not logged or persisted for motion decisions.

Each play is bounded: application artwork moves toward the desktop
`0 -> 5 -> 0 -> 3 -> 0` pixels over about 520 ms with OutCubic easing. Bottom
docks move upward, top docks downward, left docks rightward, and right docks
leftward. The persistent running indicator remains anchored. While any active
attention severity remains, the primary visible item may receive a reminder no
more than once every three seconds; the shared tracker keeps grouped and
multi-screen items from duplicating that motion.

Closing one urgent grouped member removes only that address; another urgent
member can keep the application's static urgent state active. Clearing all
badge severity stops motion and removes pending retries. Hover, drag, an open
context menu, or preview interaction suppresses the nudge without clearing the
badge, and later timer or reveal requests can retry it. An auto-hidden dock
does not reveal because of attention. Hidden applications never animate, and
showing one again primes motion at the current revision so old urgency is not
replayed. Startup and QML reload use the same current-revision priming rule.

`urgentWindowAnimationEnabled` defaults to `true`. It is effective only while
`attentionBadgesEnabled` is also enabled. Turning it off disables motion while
leaving the static urgent indicator and FDM-811 numeric count state unchanged.

Grouped motion reuses the shared tracker's urgency and motion reducers, keyed by
monitor and logical item identity. Existing state survives collapse/expansion;
recreating a delegate does not itself request a reminder or reset its cooldown.
Items removed by close, hiding, or relocation are pruned on presentation refresh.
The motion regression reproduces both delegate-reset replay and cross-workspace
revision consumption before checking independent retained state. Clipped items
dismiss popups and suppress tooltips and motion; hidden docks run no item reminder
timers. Flat items retain their application-wide source behavior.

Model checks: `node tests/test_workspace_model.mjs`,
`node tests/test_badge_model.mjs`, and `node tests/test_attention_motion_model.mjs`.
These synthetic cases do not certify physical monitor reconnect or real
application urgency delivery. Local checks should use a disposable window that
sets the Wayland urgent hint and the existing launcher-count provider test input;
notification attention must not be treated as proof of window-local urgency.
