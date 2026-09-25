# Change Icon Dialog Review Fixes Plan

**Goal:** Fix the confirmed review findings on PR #117 (`icons-improvements`, head
`2bad3b6`) before it leaves draft review: save-time conflict checks, preview
accuracy, and the dialog's lifecycle. No configuration format change.

**Source findings:** two from the GPT review, plus the independent review's #1, #2,
#3, #4, #5 (lifecycle part only) and #6. Withdrawn and not in scope: the sidebar
profile claim, the auto-hide blip and Enter on a focused button.

**Architecture:** Keep the current split. Pure logic stays in
`components/DockIconModel.js` and `components/DockConfigModel.js` and is covered by
`tests/test_icon_dialog_model.mjs`. `DockHost.saveIconChange` stays the only save
path through the host FileView writer. The dialog composes the model; menus and
the sidebar own when it closes.

## Decisions

- **The destination snapshot comes from the settings seen when the dialog opened,**
  not from live settings at save time. Taking it at save time would hide the race
  it exists to catch.
- **Renaming title rule A to the text of an existing rule B is refused** with a
  clear message, not merged. Merging would silently delete A and replace B's
  image. The refusal is `E_VALIDATION`, not `E_CONFLICT`, because reopening the
  dialog does not fix it. The maintainer authorized following this plan on
  2026-09-25; retain the nondestructive refusal rather than merging rules.
- **Choosing an existing rule's text from the app page, or from a window that
  rule doesn't match, edits that rule in place.** It no longer tries to create
  a duplicate.
- **A file chooser still running when the dialog reopens is ignored, not killed.**
  `omarchy-file-select` drives a portal dialog, and terminating the process can
  orphan it. "Choose file…" stays disabled until the old process exits, which is
  the current `!fileChooser.running` behavior.
- **"Single host-owned dialog" becomes one editing session at a time.** Each menu
  keeps its own lazily loaded dialog, because a `PopupWindow` is anchored to one
  window and moving one instance between docks on different screens is untested.
  `DockHost` tracks the active dialog and closes the previous one when another
  opens. AGENTS.md is reworded to match.

## Slices

### 1. Save-time destination checks (`DockIconModel.js`, `DockConfigModel.js`)

Fixes the GPT concurrent-overwrite finding and review #1.

- [x] `DockIconDialog.openFor` keeps `openedSettings`, a snapshot of
  `{ iconOverrides, windowIconOverrides }` taken with `current`.
- [x] `DockIconModel.iconChangeArguments(current, choice, openedSettings)` attaches
  `expected` to every `set`:
  - app/profile: the normalized source at that key in `openedSettings`, or `""` for
    absent;
  - window: the matching rule `{ key, appId, titlePattern, source }` in
    `openedSettings`, or `null` for absent.
- [x] In the same function, when `current` is a window rule and the chosen pattern
  belongs to a *different* existing rule, return `ok: false` with "Another title
  rule already uses “‹text›”. Change that rule's icon from one of its windows
  instead."
- [x] `DockConfigModel.setIconTarget` requires `"expected" in target` and rejects
  otherwise, because only the dialog calls it:
  - app/profile: live normalized source `!== expected` → `iconTargetConflict`;
  - window with an `expected` rule: `windowIconIntent(... "set",
    windowTargetArguments(target, expected.key, expected))`, an in-place edit that
    keeps the list order;
  - window with `expected === null`: today's `originalKey: ""` path, which already
    refuses a rule created meanwhile.
- [x] `iconChangeIntent` checks `remove` and `set.expected` against the same live
  settings before applying either. The same-key app/profile special case at
  `DockConfigModel.js:490-496` then goes away because `set.expected` covers it.
  Keep the window→window in-place branch, and feed it from `set.expected` when
  that is present.
- [x] `windowIconIntent` dialog mode: "Another rule already uses this application ID
  and title pattern" becomes `rejectedIntent` (`E_VALIDATION`). The CLI path
  doesn't reach it.
- [x] `DockIconDialog.commit`: for anything other than `E_CONFLICT`, show
  `reply.data.validationErrors[0].message` when present, instead of the generic
  "Patch rejected; no values were changed."
- [x] Tests (`tests/test_icon_dialog_model.mjs`):
  - app key absent at open → created before save → `E_CONFLICT`; same for a
    profile key;
  - scope change from a title rule to the whole app, with the app key created
    before save → `E_CONFLICT`;
  - scope change from a profile to the whole app, with the app icon present at
    open and unchanged → saves (positive control);
  - existing `*solar*` rule, opened from the app page, choose "contains solar"
    → edits that rule in place and keeps its list position;
  - same case with the rule deleted or changed before save → `E_CONFLICT`;
  - rename A → B where B exists → `ok: false` from `iconChangeArguments`, and
    `E_VALIDATION` if forced through `iconChangeIntent`;
  - `set` without `expected` → rejected;
  - update the existing `iconChangeIntent` cases (`:109-162`) to pass `expected`.

### 2. Preview from the saved result (`DockIconModel.js`, `DockIconDialog.qml`, `DockContextMenu.qml`)

Fixes the GPT preview-precedence finding and review #6.

- [x] `DockContextMenu.iconDialogOptions` adds `appId: root.toplevelAppId(...)` to
  each preview window, both in the `targetContexts` loop and in the
  `currentToplevels()` loop.
- [x] New `DockIconModel.previewIconChanges(beforeSettings, afterSettings, windows,
  desktopId, selection)`. It resolves each window through
  `currentIconTarget({ settings, desktopId, profileKey, appId, title })` before
  and after, and returns:
  - `rows`: `{ before, after, changed, inScope }` per window;
  - `changed`: the count of windows whose resolved source differs;
  - `shadowed`: in-scope windows whose `after.source` isn't the chosen image
    because a narrower override wins.
- [x] `previewMatches` compares `selection.appId` with `window.appId` for the
  window kind. App and profile kinds stay keyed by desktop ID and profile, and
  must not be narrowed to one raw app ID.
- [x] `DockIconDialog`: `previewDraft` = `ConfigModel.iconChangeIntent(openedSettings,
  built.args).settings` when the arguments build, otherwise `openedSettings`.
  Each preview `DockAppIcon` renders `after` exactly as the dock would:
  `iconOverrides: previewDraft.iconOverrides`, `windowOverrideSource` = the
  window-rule source from `after` (or `""`), and `profileKey` = the window's
  profile. The dimmed state follows `changed`.
- [x] `previewSummary` takes `{ changed, shadowed, total, resetting, afterKind }`.
  Default says what the windows go back to: "the app's own icon", or
  "‹App›'s custom icon" when an app or profile override remains. A shadowed
  count adds "N keep their own title-rule/profile icon."
- [x] Tests:
  - app A + rule B, Default from the window → preview resolves to A, and the
    text doesn't say "own icon";
  - app scope while another window has its own rule → that window is shadowed and
    unchanged;
  - app scope with a profile override on one window → shadowed;
  - profile scope where a title rule also matches → shadowed;
  - two raw app IDs with matching titles, window scope → only the saved rule's
    app ID counts (reproduces 2 → 1);
  - the counts equal what a real `iconChangeIntent` save produces, checked by
    resolving the saved settings.

### 3. Dialog lifecycle (`DockIconDialog.qml`, `DockContextMenu.qml`, `DockItem.qml`, `DockSidebar.qml`)

Fixes review #2, #3 and #5 (lifecycle part).

- [x] `DockIconDialog.openFor` starts with `root.chooserSerial++` and
  `root.picking = false`, so a result from the previous session is ignored.
- [x] `DockContextMenu`: add `closeAll()` = `dismiss()` plus
  `iconDialogLoader.item.closeDialog()` when loaded. `dismiss()` stays menu-only,
  so the menu→dialog handoff in `openIconDialog` is unchanged.
- [x] `DockItem.dismissPopups()` calls `contextMenu.closeAll()`. Its five callers
  (workspace drag start at `:115` and `:783`, `presentationVisible`,
  `presentationActive`, and `Dock.qml:1760`) all mean "this item is going
  away or busy", so closing the dialog is correct for each.
- [x] `DockSidebar`:
  - `closeSurfaces()` calls `sidebarContext.closeAll()`;
  - fold the three duplicated `interactionBusy` expressions (`:674`, `:693`,
    `:709`) into one `syncInteractionBusy()` that includes
    `sidebarContext.iconDialogOpen`, and call it from `onIconDialogOpenChanged`.
    `DockSidebarController.qml` also clears `interactionBusy` when a widget
    reorder or widget popup ends. The popup refuses to open while busy; check
    whether a reorder can start with the dialog open, and if so re-sync after
    it;
  - `refreshContext()`: when the menu is hidden but `sidebarContext.iconDialogOpen`,
    run the same anchor-validity checks and call `closeAll()` if the row was
    recycled, is no longer current, or scrolled out. Otherwise update the
    dialog anchor.
- [x] Tests:
  - extend the chooser harness in `tests/test_icon_dialog_model.mjs`: open
    session A → `chooseFile` → `openFor` session B → chooser A returns →
    B's `selectedSource` and `imageSources` are unchanged and `picking` is
    false;
  - in `tests/test_context_menu_regressions.mjs`, `dismissPopups()` closes an
    open dialog and `menuOpen` becomes false, and `openIconDialog` still leaves
    the dialog open after its own `dismiss()`;
  - a static check in `tests/check_contextual_actions.sh` that
    `DockSidebar.closeSurfaces` calls `closeAll` and that `syncInteractionBusy`
    reads `iconDialogOpen`.

### 4. One editing session and records (`DockHost.qml`, `AGENTS.md`, plan doc)

Covers review #4 and the minor items.

- [x] `DockHost`: `property var activeIconDialog: null` and
  `claimIconDialog(dialog)`, which closes the previous one if it's a different
  dialog and still active. `DockIconDialog.openFor` calls it through
  `mutationController`. Clear it on close.
- [x] Test: a second `openFor` on another dialog closes the first and invalidates
  its chooser.
- [x] AGENTS.md: "the single host-owned **Change Icon** dialog" becomes "the
  **Change Icon** dialog (one editing session at a time, saved through the
  host-owned `saveIconChange`)". The rest of the policy text stays.
- [ ] Record the Omarchy revision inspected in
  `docs/plans/2026-09-25-change-icon-dialog.md` slice 3:
  `git -C "$OMARCHY_PATH" rev-parse HEAD` on the maintainer desktop. This is a
  local step; the cloud checkout has no Omarchy tree.
- [ ] Optional: add `TextField` and `PanelSeparator` stubs under
  `tests/qml-imports/qs/Ui/` so a `qmltestrunner` case can instantiate
  `DockIconDialog`.
- [ ] Not in scope: a per-file icon reload revision. The global revision is the
  documented design; the reload-cost note stays open.

## Order and delivery

1. Slices 1 and 2 together: they share `iconChangeArguments` and the
   `expected`-carrying arguments, and the preview draft uses the new save path.
2. Slice 3.
3. Slice 4.

One commit per slice on `icons-improvements`, pushed after each slice passes
validation. Then update the PR description: "Concurrent edits are refused"
becomes accurate, list the new regression cases, and add the Omarchy revision.

## Validation

Per slice (cloud container, host-independent):

```bash
for t in tests/test_*.mjs; do node "$t" || exit 1; done
for t in tests/check_*.sh; do bash "$t" || exit 1; done
python3 -m unittest discover -s tests
QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests -import components -import tests/qml-imports   # if Qt is available
git diff --check
```

The four `tst_herdr_remote_fallback.qml` failures also fail on `main` and don't
block this PR.

On the maintainer desktop, via `smartdock dev use icons-improvements`, then
`smartdock dev reset`:

- a CLI `smartdock icons set` while the dialog is open → Save shows the conflict
  message;
- an existing title rule from the app page saves;
- Default on a window with app A + rule B previews A, and saving shows A;
- Choose file…, then right-click → Change Icon again: the old pick doesn't land
  in the new dialog;
- start a workspace drag, and hide the sidebar, with the dialog open: it
  closes;
- opening a second item's dialog closes the first;
- `omarchy plugin validate .` and the AGENTS.md `qmllint` set, plus
  `DockIconDialog.qml`.

## Review-fix implementation record (2026-09-25)

- Save/preview: `072d45d11c9fc9ce7875cdf982f3569da2c6c5db`.
  Isolated exact-tree validation run `36178250242` passed the complete
  JavaScript, shell, Python, provider and offscreen QML gate.
- Lifecycle: `a6783a97dc708e9dffaa708fe242bb8ad08cf75e`.
  New tests first reproduced the stale chooser and missing cleanup paths;
  the corrected tree passes all JavaScript files and shell guards locally.
  Isolated full validation run `36178893540` also passed, including QML.
- Single-session ownership: implemented with identity-checked release,
  native-dismissal cleanup, and a host-visible active-session flag so one
  sidebar cannot clear another editor's busy reservation. Tests cover second
  dialog takeover, ignored old chooser results, reopening the same dialog,
  native dismissal versus temporary picker hiding, and non-owner teardown.
- Runtime evidence is not implied by the source/test checkboxes above. The
  cloud container has no Omarchy checkout, Quickshell desktop, or KVM display;
  the exact maintainer Omarchy revision, desktop scenarios and native
  plugin/qmllint qualification below remain **unverified**. The original PR's
  older desktop evidence does not qualify these new commits.
- The optional new UI stubs are not added. Production JavaScript and extracted
  QML methods are exercised by the regression tests; existing offscreen QML
  tests do not instantiate the complete native Change Icon popup.
- Per-file reload invalidation stays out of scope.

Final exact-SHA CI and delivery status are recorded in the PR conversation.
