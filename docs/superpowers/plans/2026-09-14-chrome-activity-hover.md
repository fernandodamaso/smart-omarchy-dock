# Chrome Activity Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved Combined Activity Card to Chrome dock items, validate its real QML layout with mocked WhatsApp/Gmail data first, then connect it to live CDP tabs, Chrome windows, exact-tab activation, and the existing numeric badge.

**Architecture:** A focused JavaScript model normalizes activity records for both the QML service and popup. Phase 1 builds the production QML popup against an injected `previewActivities` property and stops for visual approval using a source-only mock harness. Phase 2 extends the existing browser-profile provider's additive snapshot, wires live rows through `DockBrowserProfileService`, activates exact tabs with a one-shot provider command, and supplies a Chrome-only fallback count to the existing badge tracker.

**Tech Stack:** Quickshell, Qt 6/QML, JavaScript, Python 3 standard library, Chrome DevTools Protocol, Hyprland, QtTest/QML Test, Python `unittest`

**Spec:** `docs/superpowers/specs/2026-09-14-chrome-activity-hover-design.md`

## Global Constraints

- Before Task 1, use `superpowers:using-git-worktrees` to create an isolated source worktree; never edit a deployed Omarchy plugin checkout.
- Inspect and preserve the current Omarchy `4.0.3-1` visual contracts documented in the spec.
- Keep `DockWindowPreview` custom because its dock-relative anchoring, clipping, hover handoff, and window lifecycle do not match Omarchy `PopupCard`.
- Reuse `BorderSurface`, `Color`, `Style`, `Border`, and `Util`; do not add a generic SmartDock surface or control library.
- Add no dependency, browser extension, DOM selector, authenticated website API, configuration key, or second recurring provider.
- Keep the snapshot at schema version 1 with additive optional `classes` and `activities` fields.
- Persist no full target URL, page title, account email, sender, message body, or notification content.
- Keep standalone mode and provider-unavailable behavior null-safe.
- Preserve the single host-owned `DockWindowActions` instance for all window focus actions.
- Do not start a second dock beside the production plugin. Use only the isolated mock surface for Phase 1 visual review.
- Keep deterministic mock records in tests after live integration; remove them only from runtime data flow.
- Do not commit, push, or create a PR unless the user explicitly requests delivery actions.

---

## Phase 1: Production Frontend With Mocked Data

### Task 1: Browser Activity Presentation Model

**Files:**
- Create: `components/DockBrowserActivityModel.js`
- Create: `tests/tst_browseractivitymodel.qml`

**Interfaces:**
- Consumes: Untrusted arrays of records shaped as `{targetId, serviceId, label, profileKey, domain, count, windowAddress}`.
- Produces: `normalizeRow(value) -> object|null`.
- Produces: `presentation(values) -> {rows: array, total: int}` with strict validation, service/profile deduplication, and deterministic ordering.
- Produces: `rowsForAddresses(recordsByAddress, addresses) -> array`.
- Produces: `accessibleName(row) -> string`.

- [ ] **Step 1: Write the failing model tests**

Create `tests/tst_browseractivitymodel.qml` with focused checks:

```qml
import QtQuick
import QtTest
import "../components/DockBrowserActivityModel.js" as ActivityModel

TestCase {
  name: "DockBrowserActivityModel"

  readonly property var whatsapp: ({
    targetId: "30512CE29E2EAEB3E32228BBC7F6DE78",
    serviceId: "whatsapp",
    label: "WhatsApp",
    profileKey: "Default",
    domain: "web.whatsapp.com",
    count: 10,
    windowAddress: "0x1"
  })

  function test_reducesDuplicatesAndOrdersRows() {
    var duplicate = Object.assign({}, whatsapp, {
      targetId: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      count: 7,
      windowAddress: "0x2"
    })
    var gmail = {
      targetId: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
      serviceId: "gmail",
      label: "Gmail",
      profileKey: "Profile 1",
      domain: "mail.google.com",
      count: 13,
      windowAddress: "0x2"
    }
    var result = ActivityModel.presentation([duplicate, whatsapp, gmail])
    compare(result.rows.length, 2)
    compare(result.rows[0].serviceId, "gmail")
    compare(result.rows[1].count, 10)
    compare(result.total, 23)
  }

  function test_rejectsInvalidAndZeroRows() {
    compare(ActivityModel.presentation([
      Object.assign({}, whatsapp, { count: 0 }),
      Object.assign({}, whatsapp, { count: -1 }),
      Object.assign({}, whatsapp, { targetId: "not-a-target" }),
      Object.assign({}, whatsapp, { serviceId: "" })
    ]).rows.length, 0)
  }

  function test_selectsOnlyRequestedWindowAddresses() {
    var records = {
      "0x1": [whatsapp],
      "0x2": [Object.assign({}, whatsapp, {
        targetId: "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC",
        serviceId: "gmail",
        label: "Gmail",
        profileKey: "Profile 1",
        domain: "mail.google.com",
        count: 13
      })]
    }
    var rows = ActivityModel.rowsForAddresses(records, ["0x2"])
    compare(rows.length, 1)
    compare(rows[0].windowAddress, "0x2")
  }

  function test_buildsAccessibleName() {
    compare(ActivityModel.accessibleName(whatsapp),
      "Open WhatsApp tab, 10 unread")
  }
}
```

- [ ] **Step 2: Run the new test and verify the red state**

Run:

```bash
qmltestrunner -input tests/tst_browseractivitymodel.qml -import components
```

Expected: FAIL because `DockBrowserActivityModel.js` does not exist.

- [ ] **Step 3: Implement the minimal pure model**

Create `components/DockBrowserActivityModel.js` with no QML or service dependency. Use these exact rules:

```javascript
.pragma library

var MAX_UNREAD_COUNT = 999999

function validTargetId(value) {
  return /^[0-9a-f]{1,64}$/i.test(String(value || ""))
}

function normalizeRow(value) {
  var source = value && typeof value === "object" ? value : null
  if (!source || !validTargetId(source.targetId)) return null
  var serviceId = String(source.serviceId || "").trim().toLowerCase()
  var label = String(source.label || "").trim()
  var count = Number(source.count)
  if (!serviceId || !label || !isFinite(count)
      || count <= 0 || count > MAX_UNREAD_COUNT) return null
  count = Math.floor(count)
  return {
    targetId: String(source.targetId),
    serviceId: serviceId,
    label: label,
    profileKey: String(source.profileKey || "").trim(),
    domain: String(source.domain || "").trim(),
    count: count,
    windowAddress: String(source.windowAddress || "").trim().toLowerCase()
  }
}

function presentation(values) {
  var byOwner = Object.create(null)
  var source = Array.isArray(values) ? values : []
  for (var i = 0; i < source.length; ++i) {
    var row = normalizeRow(source[i])
    if (!row) continue
    var key = JSON.stringify([row.serviceId, row.profileKey])
    var current = byOwner[key]
    if (!current || row.count > current.count
        || (row.count === current.count && row.targetId < current.targetId))
      byOwner[key] = row
  }
  var rows = Object.keys(byOwner).map(function(key) { return byOwner[key] })
  rows.sort(function(a, b) {
    return b.count - a.count || a.label.localeCompare(b.label)
      || a.targetId.localeCompare(b.targetId)
  })
  var total = 0
  for (var n = 0; n < rows.length; ++n) total += rows[n].count
  return { rows: rows, total: total }
}

function rowsForAddresses(recordsByAddress, addresses) {
  var records = recordsByAddress && typeof recordsByAddress === "object"
    ? recordsByAddress : ({})
  var wanted = Array.isArray(addresses) ? addresses : []
  var normalizedRecords = Object.create(null)
  Object.keys(records).forEach(function(key) {
    normalizedRecords[String(key).trim().toLowerCase()] = records[key]
  })
  var rows = []
  for (var i = 0; i < wanted.length; ++i) {
    var address = String(wanted[i] || "").trim().toLowerCase()
    var values = Array.isArray(normalizedRecords[address])
      ? normalizedRecords[address] : []
    for (var n = 0; n < values.length; ++n)
      rows.push(Object.assign({}, values[n], { windowAddress: address }))
  }
  return presentation(rows).rows
}

function accessibleName(row) {
  var value = normalizeRow(row)
  return value ? "Open " + value.label + " tab, " + value.count + " unread" : ""
}
```

- [ ] **Step 4: Run the focused test and verify green**

Run:

```bash
qmltestrunner -input tests/tst_browseractivitymodel.qml -import components
```

Expected: all `DockBrowserActivityModel` tests PASS.

- [ ] **Step 5: Run the existing model tests**

Run:

```bash
qmltestrunner -input tests -import components
```

Expected: all existing and new QML tests PASS.

- [ ] **Step 6: Review the Task 1 diff**

Run `git diff --check` and inspect only the two Task 1 files. If the user has explicitly requested commits, use:

```bash
git add components/DockBrowserActivityModel.js tests/tst_browseractivitymodel.qml
git commit -m "test: define browser activity presentation"
```

Otherwise leave the verified changes uncommitted.

### Task 2: Combined Activity Card And Mock Preview Harness

**Files:**
- Modify: `components/DockWindowPreviewModel.js`
- Modify: `components/DockWindowPreview.qml`
- Modify: `tests/tst_windowpreviews.qml`
- Create: `tests/runtime/browser-activity-preview.qml`
- Create: `tests/runtime/preview-browser-activity.sh`

**Interfaces:**
- Consumes: `anchorItem.previewActivities`, using the final activity record shape from Task 1.
- Produces: `PreviewModel.livePreviewMembers(candidates, liveToplevels) -> array`.
- Produces: `PreviewModel.hasPreviewContent(memberCount, activityCount) -> bool`.
- Produces: `DockWindowPreview.activityRows`, `activityTotal`, and `activityRequested(activity)`.
- Keeps: `requestPreview(anchorItem, desktopId, toplevels, applicationEntry)` unchanged for callers.

- [ ] **Step 1: Add failing popup eligibility tests**

Extend `tests/tst_windowpreviews.qml`:

```qml
function test_activityCanOpenAOneWindowPreview() {
  verify(PreviewModel.hasPreviewContent(1, 1))
  verify(PreviewModel.hasPreviewContent(2, 0))
  verify(!PreviewModel.hasPreviewContent(1, 0))
  verify(!PreviewModel.hasPreviewContent(0, 1))
}

function test_livePreviewMembersRetainsOneWindowForActivityCard() {
  var first = { title: "First" }
  var stale = { title: "Stale" }
  compare(PreviewModel.livePreviewMembers([first, stale], [first]).length, 1)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
qmltestrunner -input tests/tst_windowpreviews.qml -import components
```

Expected: FAIL because `hasPreviewContent` and `livePreviewMembers` are undefined.

- [ ] **Step 3: Add the minimal preview helpers**

In `components/DockWindowPreviewModel.js`, preserve `groupedPreviewMembers` for current callers and add:

```javascript
function livePreviewMembers(candidates, liveToplevels) {
  return DockWindowModel.liveGroupMembers(candidates, liveToplevels)
}

function hasPreviewContent(memberCount, activityCount) {
  return Number(memberCount) >= 2
    || (Number(memberCount) >= 1 && Number(activityCount) > 0)
}
```

- [ ] **Step 4: Run the focused model test and verify green**

Run:

```bash
qmltestrunner -input tests/tst_windowpreviews.qml -import components
```

Expected: all `WindowPreviews` tests PASS.

- [ ] **Step 5: Add activity state to the production popup**

In `components/DockWindowPreview.qml`:

- Import `DockBrowserActivityModel.js` as `ActivityModel`.
- Add `property bool previewCaptureEnabled: true` for the source-only visual harness.
- Derive `activityPresentation` from `anchorItem.previewActivities || []`.
- Expose `readonly property var activityRows` and `readonly property int activityTotal`.
- Add `signal activityRequested(var activity)`.
- Change `liveMembers()` to call `PreviewModel.livePreviewMembers`.
- Replace every `members.length < 2` dismissal/open check with `PreviewModel.hasPreviewContent(members.length, activityRows.length)`.
- Keep `captureEnabled: root.visible && root.previewCaptureEnabled` on `DockWindowPreviewTile`.
- Clear/dismiss when the last activity disappears and fewer than two live members remain.

Use this state shape:

```qml
readonly property var activityPresentation: ActivityModel.presentation(
  root.anchorItem && Array.isArray(root.anchorItem.previewActivities)
    ? root.anchorItem.previewActivities : [])
readonly property var activityRows: activityPresentation.rows
readonly property int activityTotal: activityPresentation.total
signal activityRequested(var activity)
```

- [ ] **Step 6: Build the approved layout with native Omarchy tokens**

Restructure the existing popup viewport into one vertical content flow:

```text
Chrome header + aggregate total
activity row repeater
separator when activities and previews coexist
existing preview tile flow when members.length >= 2
```

Each activity delegate must use `BorderSurface` for hover fill/border behavior, `DockAppIcon` or local service artwork with a text fallback, plain-text labels, `Style.space(...)` spacing, `Color.menu.*`/`Color.muted` colors, and a trailing accent count pill. Add:

```qml
Accessible.role: Accessible.Button
Accessible.name: ActivityModel.accessibleName(modelData)
Accessible.onPressAction: root.activityRequested(modelData)
```

The row pointer handler emits `activityRequested(modelData)`. Do not add focus grabbing, remote favicon downloads, message text, a segmented control, or a second popup.
The secondary label is exactly `profileKey` when non-empty and otherwise the
static recognized service `domain`; never derive it from a persisted full URL.

Set desired dimensions from the larger of the activity width and existing preview width, and from the sum of header, activity list, optional separator, and preview flow heights. Continue passing those desired dimensions through `PreviewModel.previewViewport` so all four dock edges remain screen-bounded.

- [ ] **Step 7: Create the source-only visual harness**

Create `tests/runtime/browser-activity-preview.qml` as a `ShellRoot` with one small anchor `PanelWindow`, an anchor item carrying:

```qml
property var previewActivities: [
  {
    targetId: "30512CE29E2EAEB3E32228BBC7F6DE78",
    serviceId: "whatsapp", label: "WhatsApp",
    profileKey: "Default", domain: "web.whatsapp.com",
    count: 10, windowAddress: "0x1"
  },
  {
    targetId: "055FDF733D6876A727CB8B094DDC277C",
    serviceId: "gmail", label: "Gmail",
    profileKey: "Profile 1", domain: "mail.google.com",
    count: 13, windowAddress: "0x2"
  }
]
```

Instantiate the production `DockWindowPreview`, set `previewCaptureEnabled: false`, and supply two fake titled members so the real activity section and preview-tile geometry render together without screencopy. The harness must log clicked activity IDs and exit on destruction; it must not read or write user configuration.

Use this structure, filling only the ordinary required visual properties already
present on `DockWindowPreview`:

```qml
import QtQuick
import Quickshell
import qs.Commons
import "components" as Components

ShellRoot {
  QtObject {
    id: actions
    function windowState(toplevel) { return { workspace: "name:Work" } }
    function activateToplevel(toplevel, originOnly) { return true }
    function closeToplevel(toplevel) { return true }
  }

  QtObject { id: firstWindow; property string title: "Chat"; property string appId: "google-chrome" }
  QtObject { id: secondWindow; property string title: "Themes"; property string appId: "google-chrome" }

  PanelWindow {
    id: anchorWindow
    screen: Quickshell.screens[0]
    anchors { bottom: true }
    implicitWidth: 64
    implicitHeight: 64
    exclusiveZone: 0
    color: "transparent"

    Item {
      id: anchorItem
      anchors.fill: parent
      property string presentationId: "mock/chrome"
      property var identityToplevel: null
      property var previewActivities: [
        {
          targetId: "30512CE29E2EAEB3E32228BBC7F6DE78",
          serviceId: "whatsapp", label: "WhatsApp",
          profileKey: "Default", domain: "web.whatsapp.com",
          count: 10, windowAddress: "0x1"
        },
        {
          targetId: "055FDF733D6876A727CB8B094DDC277C",
          serviceId: "gmail", label: "Gmail",
          profileKey: "Profile 1", domain: "mail.google.com",
          count: 13, windowAddress: "0x2"
        }
      ]
      Rectangle { anchors.fill: parent; radius: 16; color: Color.menu.background }
    }
  }

  Components.DockWindowPreview {
    id: preview
    windowActions: actions
    position: "bottom"
    visibleItems: []
    previewCaptureEnabled: false
    onActivityRequested: activity => console.log(
      "browser-activity-preview: clicked", activity.serviceId)
  }

  Component.onCompleted: {
    preview.anchorItem = anchorItem
    preview.desktopId = "google-chrome"
    preview.applicationEntry = { name: "Google Chrome", icon: "google-chrome" }
    preview.members = [firstWindow, secondWindow]
    preview.anchorHovered = true
    preview.visible = true
    Qt.callLater(preview.reanchor)
  }
}
```

Create `tests/runtime/preview-browser-activity.sh` following the existing isolated runtime scripts: copy `components/` and `assets/` into a `mktemp` directory, symlink `${OMARCHY_PATH:-/usr/share/omarchy}/shell` as `imports/qs`, copy the harness as `shell.qml`, run `qs -p "$test_dir" --no-color`, and remove the temporary directory on exit.

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d -t smartdock-browser-activity.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
cp -R "$repo_root/components" "$test_dir/components"
ln -s "$repo_root/assets" "$test_dir/assets"
cp "$repo_root/tests/runtime/browser-activity-preview.qml" "$test_dir/shell.qml"
mkdir "$test_dir/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$test_dir/imports/qs"
QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$test_dir/imports" \
  qs -p "$test_dir" --no-color
```

- [ ] **Step 8: Verify Phase 1 mechanically**

Run:

```bash
bash -n tests/runtime/preview-browser-activity.sh
qmltestrunner -input tests -import components
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  components/DockWindowPreview.qml tests/runtime/browser-activity-preview.qml
git diff --check
```

Expected: shell syntax PASS, QML tests PASS, `qmllint` has no errors, and diff check is clean.

- [ ] **Step 9: Open the mocked QML surface for visual acceptance**

Launch `bash tests/runtime/preview-browser-activity.sh` on the coding agent's current Hyprland workspace using silent placement and no initial focus. Verify the new window address with `hyprctl clients -j`; do not move or reuse an existing user window.

Review these exact states in the real QML component:

- WhatsApp 10 and Gmail 13 rows render above two preview tiles.
- Header total is 23.
- Hover treatment, text elision, count pills, separator, and popup border follow Omarchy tokens.
- Bottom, top, left, and right anchoring remain on-screen.
- One-window mode hides the window section but retains activities.
- Empty activity mode retains current two-window previews.
- Overflow scrolls without escaping screen bounds.

**Mandatory checkpoint:** Stop here and obtain explicit user approval of the Phase 1 QML layout. Do not start Task 3 until that approval is recorded.

- [ ] **Step 10: Review the Task 2 diff**

If the user has explicitly requested commits, use:

```bash
git add components/DockWindowPreviewModel.js components/DockWindowPreview.qml \
  tests/tst_windowpreviews.qml tests/runtime/browser-activity-preview.qml \
  tests/runtime/preview-browser-activity.sh
git commit -m "feat: prototype Chrome activity hover card"
```

Otherwise leave the visually approved Phase 1 changes uncommitted.

---

## Phase 2: Live Browser And Window Integration

### Task 3: Browser Provider Activity Snapshot

**Files:**
- Modify: `provider/browser-profiles/browser_profile_provider.py`
- Create: `provider/browser-profiles/tests/test_browser_profile_provider.py`

**Interfaces:**
- Produces: `activity_for_target(target, profile_key, window_address) -> dict|None`.
- Produces: `reduce_activities(rows) -> list[dict]`.
- Changes: `match_window_contexts(client, windows, pages)` returns `{contexts, windowIds, targetWindows}`.
- Changes: `build_snapshot(matches, context_profiles, pages, port, classes) -> dict` with additive `classes` and `activities`.
- Produces: `activate_target(port, target_id, client_factory=CdpClient) -> bool`.

- [ ] **Step 1: Write failing Python provider tests**

Create standard-library `unittest` coverage that imports the provider by path. Include these exact cases:

```python
def test_recognizes_whatsapp_and_gmail_titles(self):
    whatsapp = provider.activity_for_target(
        {"targetId": "A" * 32, "url": "https://web.whatsapp.com/", "title": "(10) WhatsApp"},
        "Default", "0x1")
    gmail = provider.activity_for_target(
        {"targetId": "B" * 32, "url": "https://mail.google.com/mail/u/0/#inbox",
         "title": "Inbox (13) - person@example.test - Gmail"},
        "Profile 1", "0x2")
    self.assertEqual(whatsapp["count"], 10)
    self.assertEqual(gmail["count"], 13)

def test_rejects_unknown_and_ambiguous_titles(self):
    self.assertIsNone(provider.activity_for_target(
        {"targetId": "C" * 32, "url": "https://example.test/", "title": "(99) Example"},
        "Default", "0x1"))
    self.assertIsNone(provider.activity_for_target(
        {"targetId": "D" * 32, "url": "https://web.whatsapp.com/", "title": "WhatsApp"},
        "Default", "0x1"))

def test_reduces_duplicate_service_profile_to_highest_count(self):
    rows = [
        {"targetId": "A" * 32, "serviceId": "whatsapp", "label": "WhatsApp",
         "profileKey": "Default", "domain": "web.whatsapp.com", "count": 10,
         "windowAddress": "0x1"},
        {"targetId": "B" * 32, "serviceId": "whatsapp", "label": "WhatsApp",
         "profileKey": "Default", "domain": "web.whatsapp.com", "count": 7,
         "windowAddress": "0x2"},
    ]
    self.assertEqual(provider.reduce_activities(rows), [rows[0]])
```

Also test malformed target IDs, zero/negative/overlarge counts, mixed profiles, window assignment, additive snapshot fields, and snapshot fingerprint changes when only a count changes.

- [ ] **Step 2: Run Python tests and verify failure**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s provider/browser-profiles/tests -p 'test_*.py' -v
```

Expected: FAIL because the activity functions and fields are absent.

- [ ] **Step 3: Implement strict site recognition**

Use only `urllib.parse.urlsplit` and compiled regular expressions:

```python
WHATSAPP_TITLE = re.compile(r"^\((\d+)\)\s+WhatsApp$")
GMAIL_TITLE = re.compile(r"\((\d+)\).*\s-\sGmail$")
MAX_UNREAD_COUNT = 999999
```

Require HTTPS and exact host equality. Return the approved record fields only. Do not persist the title, URL, email address, or browser context ID. Reject counts outside `1..MAX_UNREAD_COUNT`.

- [ ] **Step 4: Preserve browser-window mapping for every target**

Refactor `match_window_contexts` to retain its current conservative title/geometry matching while returning:

```python
{
    "contexts": {"0xaddress": "browser-context-id"},
    "windowIds": {"0xaddress": 1440015230},
    "targetWindows": {"target-id": 1440015230},
}
```

Update profile resolution to read `matches["contexts"]`. In `build_snapshot`, invert `windowIds`, attach only targets whose browser window maps to exactly one Hyprland address, resolve `profileKey` when known, reduce duplicates globally by `(serviceId, profileKey)`, then group retained rows under their selected `windowAddress`.

- [ ] **Step 5: Publish all relevant snapshot changes**

Add `classes`, `port`, and `activities` to the schema-version-1 snapshot. Replace the current windows-only change check with a fingerprint containing `available`, `classes`, `port`, `windows`, `profiles`, and `activities`; exclude only `revision` and transient error text. A background title-count change must increment the revision within the existing polling interval.

- [ ] **Step 6: Add one-shot exact-target activation**

Add:

```python
def valid_target_id(value):
    return re.fullmatch(r"[0-9A-Fa-f]{1,64}", str(value or "")) is not None

def activate_target(port, target_id, client_factory=CdpClient):
    if not valid_target_id(target_id) or not 1 <= int(port) <= 65535:
        return False
    client = client_factory(int(port))
    try:
        client.call("Target.activateTarget", {"targetId": target_id})
        return True
    except (CdpError, OSError, ValueError):
        return False
    finally:
        client.close()
```

Make `--state-file` conditionally required only for long-running mode. Add `--activate-target`; when present, call `activate_target`, return `0` on success and nonzero on failure, and never enter `run()`.

- [ ] **Step 7: Run the provider tests and compile check**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s provider/browser-profiles/tests -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile \
  provider/browser-profiles/browser_profile_provider.py
```

Expected: all provider tests PASS and byte compilation exits 0.

- [ ] **Step 8: Review the Task 3 diff**

Run `git diff --check`. If commits were explicitly requested, use:

```bash
git add provider/browser-profiles/browser_profile_provider.py \
  provider/browser-profiles/tests/test_browser_profile_provider.py
git commit -m "feat: publish browser unread activity"
```

Otherwise leave the verified provider changes uncommitted.

### Task 4: QML Browser Activity Service And Activation Command

**Files:**
- Modify: `components/DockBrowserActivityModel.js`
- Modify: `components/DockBrowserProfileService.qml`
- Modify: `tests/tst_browseractivitymodel.qml`
- Modify: `tests/stubs/Quickshell/Io/Process.qml` only if the existing stub cannot expose the command assertions without changing production behavior

**Interfaces:**
- Produces: `ActivityModel.normalizeClasses(values) -> array<string>`.
- Produces: `ActivityModel.normalizePort(value) -> int` or `0`.
- Produces: `ActivityModel.activationCommand(providerPath, targetId, port) -> array` or `[]`.
- Produces: `DockBrowserProfileService.classes`, `port`, and `activities`.
- Produces: `activityRowsForAddresses(addresses)`, `allActivityRows()`, and `activateTarget(targetId)`.

- [ ] **Step 1: Add failing service-contract model tests**

Extend `tests/tst_browseractivitymodel.qml`:

```qml
function test_normalizesProviderMetadata() {
  compare(JSON.stringify(ActivityModel.normalizeClasses(
    ["google-chrome", "", "google-chrome", 4])),
    JSON.stringify(["google-chrome"]))
  compare(ActivityModel.normalizePort(9222), 9222)
  compare(ActivityModel.normalizePort(70000), 0)
}

function test_buildsSafeActivationCommand() {
  compare(JSON.stringify(ActivityModel.activationCommand(
    "/tmp/provider", "AABBCCDD", 9222)),
    JSON.stringify(["/tmp/provider", "--activate-target", "AABBCCDD",
      "--port", "9222"]))
  compare(ActivityModel.activationCommand(
    "/tmp/provider", "$(touch /tmp/no)", 9222).length, 0)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
qmltestrunner -input tests/tst_browseractivitymodel.qml -import components
```

Expected: FAIL because the metadata and command helpers are absent.

- [ ] **Step 3: Implement strict metadata and command helpers**

Add the named functions to `DockBrowserActivityModel.js`. Accept only trimmed unique non-empty string classes, ports `1..65535`, executable paths that are non-empty strings, and target IDs accepted by `validTargetId`. Return an argument array exactly matching the test; never return shell text.

- [ ] **Step 4: Extend snapshot state without weakening current validation**

In `DockBrowserProfileService.qml`, add:

```qml
property var activities: ({})
property var classes: []
property int port: 0
```

On a valid running-provider schema-version-1 snapshot, normalize optional fields independently. Invalid `activities`, `classes`, or `port` values become `{}`, `[]`, or `0` without discarding valid `windows`/`profiles`. `clearSnapshot()` clears all six public state values and bumps `revision` once.

Add:

```qml
function activityRowsForAddresses(addresses) {
  var stateRevision = revision
  return ActivityModel.rowsForAddresses(activities, addresses)
}

function allActivityRows() {
  return ActivityModel.rowsForAddresses(activities, Object.keys(activities || ({})))
}
```

- [ ] **Step 5: Add the bounded activation process**

Add one `Process { id: activationProcess }`. `activateTarget(targetId)` returns false when the provider is unavailable, metadata is invalid, or the process is running. Otherwise it sets `activationProcess.command` from `ActivityModel.activationCommand`, starts it, and returns true. Log only a generic nonzero exit code; do not log target IDs, titles, or URLs.

- [ ] **Step 6: Run focused and complete QML tests**

Run:

```bash
qmltestrunner -input tests/tst_browseractivitymodel.qml -import components
qmltestrunner -input tests -import components
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  components/DockBrowserProfileService.qml
```

Expected: all QML tests PASS and `qmllint` reports no errors.

- [ ] **Step 7: Review the Task 4 diff**

If commits were explicitly requested, use:

```bash
git add components/DockBrowserActivityModel.js \
  components/DockBrowserProfileService.qml tests/tst_browseractivitymodel.qml
git commit -m "feat: expose browser activity service"
```

Otherwise leave the verified service changes uncommitted.

### Task 5: Live Popup Eligibility, Refresh, And Exact-Tab Action

**Files:**
- Modify: `components/Dock.qml`
- Modify: `components/DockItem.qml`
- Modify: `components/DockWindowPreview.qml`
- Modify: `tests/tst_windowpreviews.qml`

**Interfaces:**
- Produces: `Dock.addressesForItem(item) -> array<string>`.
- Produces: `Dock.browserActivitiesFor(item) -> array`.
- Produces: `Dock.activateBrowserActivity(activity, members) -> bool`.
- Adds: `DockItem.previewActivities`, a live normalized array.
- Consumes: `DockWindowPreview.activityRequested(activity)` from Phase 1.

- [ ] **Step 1: Add failing address/activity selection tests**

Add pure helpers to `DockWindowPreviewModel.js` rather than embedding untestable loops in QML:

```javascript
function memberForAddress(members, address, addressForMember) {
  var wanted = String(address || "").trim().toLowerCase()
  if (!wanted || typeof addressForMember !== "function") return null
  var values = members || []
  for (var i = 0; i < values.length; ++i) {
    if (String(addressForMember(values[i]) || "").trim().toLowerCase() === wanted)
      return values[i]
  }
  return null
}
```

Test matching, mismatching, and empty addresses in `tests/tst_windowpreviews.qml`, then run the focused test and verify it fails before adding the helper.

- [ ] **Step 2: Implement item-address and live-activity bindings**

In `Dock.qml`, reuse `hyprAddressFor(toplevel)` and add `addressesForItem(item)` with unique non-empty addresses. Add `browserActivitiesFor(item)` that reads `browserProfileService.revision`, returns `[]` when unavailable, and calls `activityRowsForAddresses(addressesForItem(item))`.

Bind the `AppIcon` delegate:

```qml
previewActivities: root.browserActivitiesFor(modelData)
```

In `DockItem.qml`, add `property var previewActivities: []`. Change hover and the configured `previews` action eligibility from only `runningCount >= 2` to:

```qml
root.showPreviews && root.runningCount > 0
  && (root.runningCount >= 2 || root.previewActivities.length > 0)
```

The existing `previewRequested` signature remains unchanged because the popup reads `anchorItem.previewActivities` reactively.

- [ ] **Step 3: Connect exact-tab activation through the shared controller**

In `Dock.qml`, implement `activateBrowserActivity(activity, members)`:

1. Revalidate the target against `browserProfileService.allActivityRows()` by exact `targetId` and `windowAddress`.
2. Find the owning member with `PreviewModel.memberForAddress(members, activity.windowAddress, root.hyprAddressFor)`.
3. Call the shared `windowActions.activateToplevel(member, windowPreview.originOnly)`.
4. Call `browserProfileService.activateTarget(activity.targetId)`.
5. Dismiss the popup after the request.
6. Return false and do not open anything when validation or mapping fails.

Wire `DockWindowPreview.onActivityRequested` to that function. Do not call `gtk-launch`, Chrome with a URL, or any `controlCommand`.

- [ ] **Step 4: Keep the open popup live**

Because `activityPresentation` binds to `anchorItem.previewActivities`, provider revisions update rows and totals without reopening the popup. Add an `onActivityRowsChanged` guard in `DockWindowPreview`: if the popup has fewer than two live members and the list becomes empty, dismiss it; otherwise recalculate/reanchor on the next event loop turn.

- [ ] **Step 5: Run focused and full QML tests**

Run:

```bash
qmltestrunner -input tests/tst_windowpreviews.qml -import components
qmltestrunner -input tests -import components
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  components/Dock.qml components/DockItem.qml components/DockWindowPreview.qml
git diff --check
```

Expected: all tests PASS, lint has no errors, and diff check is clean.

- [ ] **Step 6: Review the Task 5 diff**

If commits were explicitly requested, use:

```bash
git add components/Dock.qml components/DockItem.qml \
  components/DockWindowPreview.qml components/DockWindowPreviewModel.js \
  tests/tst_windowpreviews.qml
git commit -m "feat: connect Chrome activity rows to windows"
```

Otherwise leave the verified integration changes uncommitted.

### Task 6: Chrome-Only Numeric Badge Fallback

**Files:**
- Modify: `components/DockBadgeModel.js`
- Modify: `components/DockBadgeTracker.qml`
- Modify: `DockHost.qml`
- Modify: `tests/tst_launcherbadgemodel.qml`

**Interfaces:**
- Produces: `BadgeModel.browserCountState(desktopId, entry, classes, count, available, aliases) -> count state`.
- Produces: `BadgeModel.preferredCountState(launcherState, browserState) -> count state`.
- Adds: `DockBadgeTracker.browserProfileService`.
- Keeps: Existing `badgeFor(desktopId, scope)` return token contract.

- [ ] **Step 1: Write failing badge precedence tests**

Extend `tests/tst_launcherbadgemodel.qml`:

```qml
function test_browserCountIsStrictChromeFallback() {
  var chrome = { id: "com.google.Chrome", startupClass: "google-chrome", name: "Google Chrome" }
  var browser = BadgeModel.browserCountState(
    chrome.id, chrome, ["google-chrome"], 23, true, {})
  compare(browser.count, 23)
  verify(browser.visible)
  verify(!BadgeModel.browserCountState(
    "org.mozilla.firefox", { id: "org.mozilla.firefox", startupClass: "firefox" },
    ["google-chrome"], 23, true, {}).visible)
}

function test_launcherCountWinsOverBrowserFallback() {
  var launcher = { authoritative: true, count: 4, visible: true }
  var browser = { authoritative: true, count: 23, visible: true }
  compare(BadgeModel.preferredCountState(launcher, browser).count, 4)
  compare(BadgeModel.preferredCountState(
    { authoritative: false, count: 0, visible: false }, browser).count, 23)
}
```

- [ ] **Step 2: Run the focused badge test and verify failure**

Run:

```bash
qmltestrunner -input tests/tst_launcherbadgemodel.qml -import components
```

Expected: FAIL because both helpers are undefined.

- [ ] **Step 3: Implement strict browser count state and precedence**

Use existing `strictIdentityMatches` and `normalizeLauncherCount`. Return the same narrow count-state shape consumed by `applicationBadgePresentation`. The browser state may set `authoritative: true` only after strict browser identity matching so the existing renderer can consume the already-selected fallback without a second token format. `preferredCountState` always returns a valid authoritative launcher record first, even when its count is zero or hidden; this preserves the application's explicit clear/hide authority.

- [ ] **Step 4: Connect the browser service to the shared badge tracker**

In `DockHost.qml`, pass `browserProfileService: root.browserProfileService` into the single `DockBadgeTracker`.

In `DockBadgeTracker.qml`:

- Add `property var browserProfileService: null`.
- Add `browserCountFor(desktopId)` that reads service revision, classes, availability, and `ActivityModel.presentation(service.allActivityRows()).total`.
- Select `preferredCountState(launcherCountFor(desktopId), browserCountFor(desktopId))` before `applicationBadgeToken`.
- Add null-safe `Connections` for browser service revision/availability/activity changes that bump the tracker revision.
- Do not make browser counts eligible for motion; leave `motionAttentionFor` unchanged.

- [ ] **Step 5: Verify badge behavior**

Run:

```bash
qmltestrunner -input tests/tst_launcherbadgemodel.qml -import components
qmltestrunner -input tests/tst_badgemodel.qml -import components
qmltestrunner -input tests -import components
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  DockHost.qml components/DockBadgeTracker.qml
git diff --check
```

Expected: launcher counts win, Chrome receives browser fallback 23, non-Chrome apps do not, dots-only and disabled badges retain current behavior, and all tests PASS.

- [ ] **Step 6: Review the Task 6 diff**

If commits were explicitly requested, use:

```bash
git add DockHost.qml components/DockBadgeModel.js \
  components/DockBadgeTracker.qml tests/tst_launcherbadgemodel.qml
git commit -m "feat: badge Chrome with browser unread total"
```

Otherwise leave the verified badge changes uncommitted.

### Task 7: Live Runtime Acceptance And Documentation

**Files:**
- Modify: `README.md`
- Create: `docs/browser-activity.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Completed Phase 2 implementation.
- Produces: User-facing setup, privacy, fallback, supported-site, and validation documentation.

- [ ] **Step 1: Run provider installation in an isolated XDG data directory**

Run:

```bash
test_data="$(mktemp -d -t smartdock-browser-provider.XXXXXX)"
XDG_DATA_HOME="$test_data" bash scripts/install-browser-profile-provider
"$test_data/smartdock/providers/smartdock-browser-profile-provider" --help
rm -rf -- "$test_data"
```

Expected: installation succeeds, the installed executable exposes both long-running state mode and `--activate-target`, and no user installation is overwritten.

- [ ] **Step 2: Run the complete repository validation gate**

Run the standalone smoke only in the owning isolated display/config context,
with no production plugin dock on that display. Then run the remaining gate:

```bash
# Isolated-context-only smoke:
timeout 6s ./scripts/run --no-color

# Host-independent and plugin checks:
bash -n install.sh uninstall.sh scripts/smartdock scripts/run \
  scripts/install-browser-profile-provider tests/check_window_actions.sh \
  tests/runtime/preview-browser-activity.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s provider/browser-profiles/tests -p 'test_*.py' -v
qmltestrunner -input tests -import components
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Overlay.qml DockHost.qml components/Dock.qml components/DockItem.qml \
  components/DockContextMenu.qml components/DockControlItem.qml \
  components/DockWindowActions.qml components/DockWindowPreview.qml \
  components/DockBrowserProfileService.qml shell.qml
git diff --check
```

Expected: every command exits 0. Record the standalone smoke warning separately if another Quickshell application ID is already registered; do not treat that warning alone as failure.

- [ ] **Step 3: Perform live Chrome acceptance without a second dock**

Use the owning issue's isolated runtime/config context and the production plugin's single service instance. Do not install source over an unrelated deployed checkout. Validate:

- Open background WhatsApp with a positive unread title and confirm its row/count update within the existing provider interval.
- Open Gmail and record its exact live title format before claiming Gmail support.
- Change both counts while tabs remain inactive and verify header/icon totals.
- Open duplicate WhatsApp tabs in one profile and verify only the highest count contributes.
- Open two Chrome windows and verify each row activates its exact tab and owning window.
- Close a target immediately before clicking its row and verify no replacement tab opens.
- Disable/restart CDP and provider independently and verify rows/counts clear while previews/dots remain.
- Verify `launcherBadgeMode="dots-only"`, `attentionBadgesEnabled=false`, and an authoritative LauncherEntry clear/hide all preserve the specified precedence.
- Verify no Chrome-derived badge appears on Chromium, Firefox, or another application unless its exact class is published by that provider process.

Record any unavailable physical/runtime case as NOT RUN rather than simulated PASS.

- [ ] **Step 4: Update user-facing documentation from verified facts**

In `README.md`, extend Browser Profile Badges into Browser Profile And Activity support. Document:

- Optional provider installation remains `bash ./scripts/install-browser-profile-provider`.
- WhatsApp and Gmail are the initial recognized origins.
- Counts come from strict tab-title signals, not notifications or message inspection.
- The hover card lists service/profile/count and activates exact tabs.
- Chrome icon count is a fallback behind authoritative LauncherEntry state and obeys dots-only/disabled badge settings.
- Provider/CDP/title mismatch falls back to current previews and dots.

Create `docs/browser-activity.md` for the provider contract, supported title forms,
privacy boundary, duplicate reduction, exact-tab action, fallback behavior, and
runtime acceptance evidence. Link it from the README. Keep these details out of
the CLI preference docs because no setting is added. Add one concise unreleased
feature entry to `CHANGELOG.md`.

- [ ] **Step 5: Re-run checks affected by documentation or installer edits**

Run:

```bash
bash -n scripts/install-browser-profile-provider
git diff --check
git status --short
```

Expected: syntax and whitespace checks pass; status lists only intended feature, test, spec, plan, mock-harness, and documentation files plus any pre-existing unrelated files.

- [ ] **Step 6: Final review and optional delivery commit**

Inspect `git diff`, confirm mock values exist only under tests/runtime or test files, and verify no target URL/title/account data enters runtime snapshots. If the user explicitly requests commits and the repository delivery workflow is active, create the final docs commit:

```bash
git add README.md CHANGELOG.md \
  docs/browser-activity.md \
  docs/superpowers/specs/2026-09-14-chrome-activity-hover-design.md \
  docs/superpowers/plans/2026-09-14-chrome-activity-hover.md \
  components/DockBrowserActivityModel.js \
  components/DockBrowserProfileService.qml components/DockBadgeModel.js \
  components/DockBadgeTracker.qml components/DockWindowPreviewModel.js \
  components/DockWindowPreview.qml components/DockItem.qml components/Dock.qml \
  DockHost.qml provider/browser-profiles/browser_profile_provider.py \
  provider/browser-profiles/tests/test_browser_profile_provider.py \
  tests/tst_browseractivitymodel.qml tests/tst_windowpreviews.qml \
  tests/tst_launcherbadgemodel.qml tests/runtime/browser-activity-preview.qml \
  tests/runtime/preview-browser-activity.sh scripts/install-browser-profile-provider
git commit -m "feat: add Chrome activity hover"
```

Do not merge locally to `main`, push, or create a PR without an explicit delivery request and the exact-SHA evidence required by `docs/DELIVERY.md`.
