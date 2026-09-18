# SB-03 — Sidebar resize and preference commits

**FDM-965, unreleased Draft source slice.** This extends the SB-02 global sidebar
with persistent expanded geometry, an inner-edge resize gesture and conflict-safe
preference commits. It does not install or switch the production plugin. Physical
Omarchy/Hyprland qualification remains owned by FDM-968/SB-06.

## Requested and effective width

`sidebarExpandedWidth` remains the requested expanded width and accepts integer
logical pixels from 240 through 480. Runtime geometry never rewrites it merely
because a screen is smaller, disconnected, rotated or scaled.

For the selected screen's **unreserved logical width** `W`:

```text
railWidth      = min(72, W)
expandedMax    = min(W, max(72, min(480, floor(0.40 * W))))
expandedMin    = min(240, expandedMax)
effectiveWidth = clamp(sidebarExpandedWidth, expandedMin, expandedMax)
```

Qt/Quickshell screen geometry is already logical. SmartDock does not divide it by
scale/device-pixel ratio again and does not use a workarea already reduced by its
own exclusive zone. `W <= 0` maps no sidebar. Collapse uses the bounded rail width
and preserves `sidebarExpandedWidth`.

The panel anchors top + bottom + the configured left/right edge and reserves exactly
its current total persistent width once. The eight-pixel resize handle is inside
that width, on the inner desktop-facing edge, and is disabled in rail mode. The
stock topbar is not disabled or assigned guessed dimensions.

## Resize lifecycle

`DockSidebarResizeHandle` uses a targetless native `DragHandler`. The controller
captures the starting effective width and the pointer's screen-global logical X.
Left-edge resize adds pointer delta; right-edge resize subtracts it. Because the
origin is captured in screen-global space, a changing right-anchored panel origin
cannot accumulate into the delta.

Pointer motion updates only temporary controller width and the live reservation.
It performs **zero settings writes** and dispatches no compositor commands. A
changed successful release sends exactly one `sidebarExpandedWidth` intent. A
release at the captured width is a no-op. Collapse remains its own
`sidebarCollapsed` intent and never overwrites expanded width.

Escape, exclusive-grab cancellation, mode/edge/host removal, current-screen loss,
or an externally accepted width/collapse change discards the resize preview. A
preferred monitor reconnect waits while an interaction is active; loss of the
current host screen cancels immediately. Resize cannot overlap another sidebar
interaction.

## Conflict-safe persistence

`DockHost.saveSettingIntent(key, value, expectedValue)` is a small adapter around
the existing sole FileView writer. It does not create a queue or second persistence
path.

- A preflight busy state is rejected with `accepted: false` and no write.
- If the host value no longer equals `expectedValue`, the intent is rejected as
  `E_STALE`, includes the current value, and no stale drag-start patch is replayed.
- Once a change has updated live host settings, `data.applied: true` means the
  intent is accepted even if the generic reply is temporarily `E_BUSY` while the
  FileView save/readback is pending. The adapter reports `pending: true` in that
  case.
- A persistence failure after acceptance keeps the live intent and host error state.
  Retry uses the existing current-snapshot path; it never replays the old resize
  patch.
- Each resize/collapse commit contains only its changed field. Unknown keys, pins,
  artwork, hidden applications, profile/mute preferences and inactive classic
  settings remain owned by the latest host snapshot.

Durability is not claimed until the existing writer confirms readback. The sidebar
surfaces host `saving`/unsaved/error feedback rather than inventing a second status.

## Source validation

Focused source gates:

```bash
node tests/test_sidebar_geometry.mjs
node tests/test_sidebar_mutations.mjs
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_sidebarresize.qml -import components
```

Then run the complete current `.github/workflows/ci.yml` matrix and
`git diff --check`. The focused tests cover scale metadata, portrait/narrow/negative
origin geometry, workarea-feedback avoidance, left/right delta signs, fallback and
reconnect, pointer-write counts, no-op/cancel, stale/busy/pending/error semantics,
unrelated/unknown-key preservation and restart from the latest snapshot.

## Runtime fixture and deferred physical gates

`tests/runtime/sidebar.qml` instantiates the production host, FileView writer,
controller, panel, viewport, delegates and resize handle. It verifies that live
right-edge preview changes reservation without changing the settings revision or
writer text, changed release creates one settings revision, grab-loss cancellation
creates none, an accepted external width cancels the preview, and source teardown
releases the sidebar layer. `check-sidebar.sh` reads the final real fixture config
back and checks that requested width plus unknown/classic keys survived.

Run only inside the disposable isolated Omarchy session described by
`DEV_SESSIONS.md`, after stopping that guest's ordinary dock:

```bash
SMARTDOCK_ISOLATED_RUNTIME=1 SMARTDOCK_RUNTIME_LOG=/tmp/sidebar-runtime.log \
  bash tests/runtime/check-sidebar.sh
```

The remote SB-03 handoff does **not** count this command as executed. FDM-968/SB-06
must run the real fixture and additionally qualify physical multi-monitor/hotplug,
fractional scale, portrait/negative-coordinate topology, both creation orders with
the stock topbar, fullscreen on another monitor, pointer/grab behavior, input masks,
plugin validation and shell-aware lint on the integrated candidate.
