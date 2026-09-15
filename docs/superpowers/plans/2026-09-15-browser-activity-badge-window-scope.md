# Browser Activity Badge Window Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Display Chrome's browser-activity fallback count on the dock item whose represented window owns that activity.

**Architecture:** Reuse the existing address-filtered activity rows that already drive each item's hover card. Pass those rows into the shared badge tracker while keeping notification, SNI, urgency, and LauncherEntry counts app-wide; the existing primary-owner rule continues to own those app-wide sources. Extend the existing count-precedence helper so an authoritative LauncherEntry count suppresses browser fallback counts on secondary items as well as winning on the primary item.

**Tech Stack:** Quickshell, Qt 6/QML, JavaScript, Hyprland, QtTest/QML Test, Bash structural checks

**Spec:** `docs/superpowers/specs/2026-09-14-chrome-activity-hover-design.md`

## Global Constraints

- Work only in the source worktree; never edit the installed plugin checkout directly.
- Add no dependency, provider, configuration key, persistence format, or second badge renderer.
- Keep `DockBadgeTracker` as the single host-owned reducer for application badge tokens.
- Reuse `Dock.qml`'s existing `browserActivitiesFor(item)` address filtering; do not duplicate window-to-address matching.
- Preserve app-wide ownership for notification, SNI, urgency, and LauncherEntry sources.
- Preserve LauncherEntry precedence over the Chrome browser fallback across every item for the application.
- With `groupWindows: true`, one Chrome item aggregates activity from all represented windows.
- With `groupWindows: false`, each Chrome item counts only activity from its represented window.
- Preserve muted-service filtering, `dots-only`, `attentionBadgesEnabled`, `99+`, and provider-unavailable behavior.
- Do not change the browser-profile provider or its schema; the live snapshot already maps the activity to the correct Hyprland address.
- Do not start a source dock beside the production plugin. Run any source-host smoke test only in an isolated display and configuration context.
- Do not deploy, push, or create a pull request unless the user separately requests delivery.

---

### Task 1: Scope the Browser Fallback Count to Each Dock Item

**Files:**
- Modify: `tests/tst_launcherbadgemodel.qml`
- Modify: `tests/check_launcher_badge_counts.sh`
- Modify: `components/DockBadgeModel.js`
- Modify: `components/DockBadgeTracker.qml`
- Modify: `components/Dock.qml`
- Modify: `docs/browser-activity.md`

**Interfaces:**
- Consumes: `Dock.qml::browserActivitiesFor(item) -> array`, already filtered by every Hyprland address represented by `item.toplevels`.
- Changes: `DockBadgeTracker::badgeFor(desktopId, scope, browserRows) -> string`; `browserRows` is an optional array and omitted callers retain app-wide fallback behavior.
- Changes: `DockBadgeTracker::browserCountFor(desktopId, rows) -> countState`; an array counts only those rows, while an omitted value uses `service.allActivityRows()`.
- Changes: `DockBadgeModel::preferredCountState(launcherState, browserState, primaryOwner) -> countState`; `primaryOwner` defaults to true when omitted for compatibility.
- Preserves: badge tokens remain `none`, `attention`, `urgent`, or `count:<value>:<severity>`.

- [x] **Step 1: Add a failing precedence regression**

Extend `tests/tst_launcherbadgemodel.qml` with this test after `test_launcherCountWinsOverBrowserFallback`:

```qml
  function test_launcherPrecedenceAlsoSuppressesSecondaryBrowserCounts() {
    var launcher = { authoritative: true, count: 9, visible: true }
    var browser = { authoritative: true, count: 2, visible: true }

    compare(BadgeModel.preferredCountState(launcher, browser, true).count, 9)
    var secondary = BadgeModel.preferredCountState(launcher, browser, false)
    verify(secondary.authoritative)
    verify(!secondary.visible)
    compare(secondary.count, 0)

    var unavailableLauncher = {
      authoritative: false, count: 0, visible: false
    }
    compare(BadgeModel.preferredCountState(
      unavailableLauncher, browser, false).count, 2)
  }
```

This locks the required distinction: LauncherEntry remains app-wide and primary-owned, while a browser fallback may render on the secondary item that owns its rows.

- [x] **Step 2: Add a failing production-wiring guard**

Add these checks to `tests/check_launcher_badge_counts.sh`:

```bash
badge_binding="$(sed -n '/function attentionBadgeFor(item, index)/,/^  }/p' components/Dock.qml)"
grep -Fq 'var browserRows = browserActivitiesFor(item)' <<<"$badge_binding" \
  || fail 'each dock item must derive its badge from its address-filtered browser rows'
grep -Fq 'return badgeTracker.badgeFor(item.desktopId, scope, browserRows)' <<<"$badge_binding" \
  || fail 'each dock item must pass its browser rows to the shared badge tracker'
grep -Fq 'function badgeFor(desktopId, scope, browserRows)' "$tracker" \
  || fail 'badge tracker must accept item-scoped browser rows'
```

- [x] **Step 3: Run both focused checks and verify the red state**

Run:

```bash
qmltestrunner -input tests/tst_launcherbadgemodel.qml -import components
bash tests/check_launcher_badge_counts.sh
```

Expected:

- The QML test fails because `preferredCountState()` ignores `primaryOwner` and returns the LauncherEntry count for a secondary item.
- The shell check fails because `attentionBadgeFor()` does not pass item-filtered activity rows into `badgeFor()`.

- [x] **Step 4: Extend the existing count-precedence helper**

Replace `preferredCountState()` in `components/DockBadgeModel.js` with:

```javascript
function preferredCountState(launcherState, browserState, primaryOwner) {
  var none = { authoritative: false, count: 0, visible: false }
  if (launcherState && launcherState.authoritative === true)
    return primaryOwner === false
      ? { authoritative: true, count: 0, visible: false }
      : launcherState
  if (browserState && browserState.authoritative === true) return browserState
  return none
}
```

The two-argument calls remain unchanged because an omitted `primaryOwner` is not `false`.

- [x] **Step 5: Let the badge tracker count supplied rows**

Change `browserCountFor()` in `components/DockBadgeTracker.qml` to accept optional rows and fall back to all provider rows only when the argument is not an array:

```qml
  function browserCountFor(desktopId, rows) {
    var service = root.browserProfileService
    var providerRevision = service ? Number(service.revision || 0) : 0
    if (!service || !service.available) return null
    var values = Array.isArray(rows)
      ? rows
      : typeof service.allActivityRows === "function"
        ? service.allActivityRows() : []
    var total = ActivityModel.presentation(
      values, root.browserActivityMutedServices).total
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    return BadgeModel.browserCountState(
      desktopId, entry, service.classes, total, service.available,
      identityAliases)
  }
```

Change `badgeFor()` to accept the rows, keep calculating LauncherEntry state for precedence, and avoid an app-wide browser fallback on secondary callers that omit rows:

```qml
  function badgeFor(desktopId, scope, browserRows) {
    var entry = BadgeModel.entryForDesktopId(desktopId, applications)
    var local = BadgeModel.localSeverity(
      persisted.localNotifications, desktopId, entry, identityAliases,
      Date.now(), BadgeModel.LOCAL_ATTENTION_TTL_MS)
    var severity = BadgeModel.scopedBadgeSeverity(
      sniNeedsAttentionFor(desktopId, entry),
      hyprUrgentFor(desktopId, entry), local, scope)
    var primaryOwner = !scope || scope.primaryOwner === true
    var launcher = launcherCountFor(desktopId)
    var browser = primaryOwner || Array.isArray(browserRows)
      ? browserCountFor(desktopId, browserRows) : null
    return BadgeModel.applicationBadgeToken(
      true, launcherBadgeMode,
      BadgeModel.preferredCountState(launcher, browser, primaryOwner), severity)
  }
```

- [x] **Step 6: Pass each item's existing activity rows into the tracker**

Replace `attentionBadgeFor()` in `components/Dock.qml` with:

```qml
  function attentionBadgeFor(item, index) {
    var badgeRevision = badgeStateRevision
    if (!attentionBadgesEnabled || !badgeTracker || !item) return "none"
    var owner = primaryBadgeOwnerFor(index)
    var browserRows = browserActivitiesFor(item)
    var scope = grouped || !owner
      ? ({ localUrgent: item.localUrgent === true, primaryOwner: owner })
      : null
    return badgeTracker.badgeFor(item.desktopId, scope, browserRows)
  }
```

For grouped workspace cards this preserves the existing member-scoped urgency object. For a flat primary item, `scope` stays null so app-wide urgency behaves exactly as before. A flat secondary item receives a non-primary scope, allowing only its browser fallback count to render.

- [x] **Step 7: Run the focused regression checks**

Run:

```bash
qmltestrunner -input tests/tst_launcherbadgemodel.qml -import components
qmltestrunner -input tests/tst_browseractivitymodel.qml -import components
qmltestrunner -input tests/tst_windowpreviews.qml -import components
bash tests/check_launcher_badge_counts.sh
bash tests/check_attention_badges.sh
```

Expected: all five commands pass.

- [x] **Step 8: Document count ownership**

Add this paragraph after the badge-fallback description in `docs/browser-activity.md`:

```markdown
When one dock item represents multiple Chrome windows, its fallback count is the
reduced total for those represented windows. When window grouping is disabled,
each Chrome item shows only the fallback count owned by its represented window.
Application-wide LauncherEntry counts retain precedence and render only on the
primary visible item.
```

- [x] **Step 9: Run repository validation**

Run the host-independent and installed-shell-aware checks:

```bash
bash -n install.sh uninstall.sh scripts/smartdock scripts/run tests/check_window_actions.sh
for check in tests/check_*.sh; do bash "$check" || exit; done
for test in tests/test_*.mjs; do node "$test" || exit; done
python3 -m unittest discover -s provider/browser-profiles/tests -p 'test_*.py'
qmltestrunner -input tests -import components
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml shell.qml
git diff --check
```

Expected: every command passes. Do not run `./scripts/run` in the production display while the installed plugin is active.

- [ ] **Step 10: Perform live acceptance only after an exact SHA is authorized for deployment**

Use the installed plugin update path from `docs/DELIVERY.md`; never copy files into the deployed checkout. On one workspace, create two separate Chrome windows with `groupWindows: false`:

1. Keep a recognized unread activity, such as WhatsApp `2`, in only one window.
2. Confirm only that window's dock icon displays `2`.
3. Hover both icons and confirm the activity card appears only on the same icon.
4. Focus and reorder the two Chrome windows; confirm the badge remains tied to the owning window rather than the first rendered Chrome item.
5. Enable `groupWindows: true` through the documented CLI workflow, confirm the single Chrome icon shows the reduced total for both represented windows, then restore the original requested value with a touched-key rollback.
6. Confirm an authoritative LauncherEntry test source, when available, suppresses Chrome fallback counts on secondary items and renders its value on the primary item.

Record the exact base and head SHAs and distinguish saved configuration from verified rendering. If an authoritative LauncherEntry source is unavailable, leave step 6 as an explicit physical gate; the QML regression still covers its reducer semantics.

- [ ] **Step 11: Commit when delivery is authorized**

```bash
git add components/Dock.qml components/DockBadgeModel.js \
  components/DockBadgeTracker.qml tests/tst_launcherbadgemodel.qml \
  tests/check_launcher_badge_counts.sh docs/browser-activity.md \
  docs/superpowers/plans/2026-09-15-browser-activity-badge-window-scope.md
git commit -m "fix: scope Chrome activity badges to owning windows"
```

Keep the pull request Draft until `Headless CI` and required physical evidence apply to the exact current head SHA.
