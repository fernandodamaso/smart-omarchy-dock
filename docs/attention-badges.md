# SmartDock attention badges

FDM-809 adds application attention indicators without pretending SmartDock
owns unread-message counts. The badge is always a dot: ordinary attention uses
Omarchy's accent color and urgent/critical attention uses the urgent color.
FDM-811 remains the owner of any future application-provided numeric badge.

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
