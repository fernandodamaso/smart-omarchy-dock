# SmartDock attention badges

FDM-809 adds application attention indicators without pretending SmartDock
owns unread-message counts. The badge is always a dot: ordinary attention uses
Omarchy's accent color and urgent/critical attention uses the urgent color.
FDM-811 owns application-provided numeric badge counts and their provider.

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

Set `attentionBadgesEnabled` to `false` to hide attention dots without deleting
local attention state. Re-enabling the setting resumes rendering from the
current live/local state.

## Urgent-window motion

FDM-814 adds a reduced-motion-friendly, one-shot nudge only when a previously
absent **Hyprland urgent window address** enters an application's urgent-address
set. Notification events, SNI attention, FDM-811 numeric counts, titles,
notification bodies, terminal/editor output, sender data, and window content do
not trigger the animation and are not logged or persisted for motion decisions.

The animation is bounded and never loops: the application artwork moves toward
the desktop `0 -> 5 -> 0 -> 3 -> 0` pixels over about 520 ms with OutCubic
easing. Bottom docks move upward, top docks downward, left docks rightward, and
right docks leftward. The persistent running indicator remains anchored.

Motion has a three-second per-application cooldown. Repeated urgency for an
address that is already urgent does not increment the motion revision. Closing
one urgent grouped member removes only that address; another urgent member can
keep the application's static urgent state active. Clearing an address and
later receiving urgency for it again creates a new revision.

Hover, drag, an open context menu, or preview interaction suppresses the nudge
without clearing the urgent badge. An auto-hidden dock does not reveal because
of urgency; one eligible revision can remain pending and is consumed on the
next ordinary reveal only if the application is still urgent. Hidden
applications never animate, and showing one again primes motion at the current
revision so old urgency is not replayed. Startup and QML reload use the same
current-revision priming rule.

`urgentWindowAnimationEnabled` defaults to `true`. It is effective only while
`attentionBadgesEnabled` is also enabled. Turning it off disables motion while
leaving the static urgent indicator and FDM-811 numeric count state unchanged.
