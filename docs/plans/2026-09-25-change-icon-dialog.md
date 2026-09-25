# Change Icon Dialog Implementation Plan

**Goal:** Replace the two confusing icon paths (window-only "Change Icon" dialog
and the "Copy Icon Command" clipboard submenu) with one right-click entry and one
dialog that can set an icon for the whole app, one browser profile, or windows
whose title contains some text.

**Approved design:** Design canvas "Change Icon Workflow"
(https://claude.ai/artifact/UuYCi8jPbaJBKv2aX9U8Dw): boards *New: right-click
menu*, *New: Change Icon*, *New: browser profile window*, *New: window that
already has a custom icon*.

**Architecture:** No configuration format change. The dialog writes the existing
`iconOverrides` (app and `ID@profile:DIR` keys) and `windowIconOverrides` (title
rules) through the host's existing single FileView writer. Pure logic lives in
`components/DockIconModel.js` and is unit-tested; the QML dialog only composes it.

## Decisions

- **Images stay where they are.** The dialog references the chosen file in place,
  as today. A missing file shows as "Image missing" in the dialog and the dock
  falls back to the normal icon. Copying images into a SmartDock folder is out of
  scope.
- **`smartdock icons` terminal commands stay unchanged** for scripts and agents.
  Only the "Copy Icon Command" menu entry and its submenu go away.
- **Policy change.** AGENTS.md currently makes app/profile icon editing CLI-only
  and allows the dialog only as the FDM-927 exception. This work replaces that
  rule: icon editing through this one dialog is allowed. There is still no
  settings window and no second config writer.

## Slices

### 1. Pure model helpers (`components/DockIconModel.js`)

- [x] `containsToPattern(text)` → `*text*`. Reject empty text, control characters
  and a literal `*` in "contains" mode; enforce the 200-character limit.
- [x] `patternToContains(pattern)` → the inner text when the pattern is exactly
  `*text*` with no other `*`; otherwise `null`. Existing rules with other shapes
  stay editable through an "exact pattern" field. Never rewrite them silently.
- [x] `currentIconTarget({ desktopId, profileKey, appId, title, settings })` → which
  override currently applies (`window` rule, `profile`, `app`, or `none`), its
  source and its key. Uses the precedence the renderer already uses:
  window rule → profile → app.
- [x] `recentIconSources(settings, limit)` → distinct local sources already present
  in both collections, newest first (collection order reversed). Needs no new
  storage.
- [x] `previewMatches(windows, selection)` → one matched flag per window plus the
  count, for the dialog preview.
- [x] Tests: new `tests/test_icon_dialog_model.mjs`, covering pattern round-trips,
  precedence, recent-source ordering and de-duplication, and profile keys.

### 2. One-step save (`components/DockConfigModel.js`, `DockHost.qml`)

Changing scope, for example from a "solar" title rule to all Ghostty windows,
has to remove the old override and add the new one in one write, never two.

- [x] Add `ConfigModel.iconChangeIntent(settings, { remove, set })`. `remove` and
  `set` are each `{ kind: "app"|"profile"|"window", key/appId/titlePattern, source }`.
  It reuses the existing `iconIntent` and `windowIconIntent` validation and
  returns one combined settings result.
- [x] `DockHost.saveIconChange(args)`: one `commitSettings`, bumps
  `iconReloadRevision` like the existing save functions, and returns
  `iconResult`. Keep the captured-rule stale-edit protection (`expected` /
  `originalKey`) that the window dialog already uses.
- [x] Keep `saveIconOverride`, `saveWindowIconOverride` and `reloadIcon` for the CLI.
- [x] Tests (in `tests/test_icon_dialog_model.mjs`): scope changes,
  reset of each kind, a stale rule and an unchanged save (no write).

### 3. Dialog (`components/DockWindowIconDialog.qml` → `components/DockIconDialog.qml`)

First run the AGENTS.md UI refactor check: record the Omarchy revision, and
inspect `qs.Ui` Button, TextField and radio/choice primitives and one
first-party popup that uses them.

- [x] `openFor({ desktopId, appName, profileKey, profileName, targetContext })`.
  `targetContext` is optional: a pinned app with no windows has no title option
  and no preview.
- [x] Header: current icon (`DockAppIcon`), app name, profile badge.
- [x] Image row: current source selected, recent sources as tiles, "Choose file…"
  (out-of-process `omarchy-file-select` portal chooser, PNG/SVG). A tile whose file fails to load shows
  "Image missing".
- [x] "Use it for" radios:
  - "All ‹App› windows" (default for a new icon)
  - "Only the ‹Profile› profile" (only when the window has a profile)
  - "Only windows whose title contains…" with a text field (only when a live
    window with a raw Wayland app ID exists)
  - "exact pattern" field, only when editing a rule that isn't `*text*`
- [x] When the window already uses a custom icon, open with that override's
  image and scope preselected and show the notice
  ("This window uses solar.svg because its title contains 'solar'").
- [x] Preview strip: this app's open windows (same toplevel source the menu
  uses), matched ones showing the new image, with a count sentence.
- [x] Footer: "Reset to default" (enabled only when an override applies; removes
  exactly that override), Cancel, Save. Save calls `saveIconChange` once.
  Escape cancels, Enter saves, and errors show inline.
- [x] Carry both identities: the desktop ID for app and profile keys, and the raw
  Wayland app ID for title rules. They differ, for example
  `com.mitchellh.ghostty`.

### 4. Menu (`components/DockContextMenu.qml`, `components/DockMenuModel.js`)

- [x] One "Change Icon…" record on window pages, app pages and the pin strip.
  Sidebar rows share this menu, so they get it automatically.
- [x] Remove "Reset Icon", the "Copy Icon Command" submenu, the `copy-command`
  page, `copyProfileDirectory`, `copyIconCommand`, the clipboard process and
  `DockMenuModel.iconCommandSpec`.
- [x] Update `tests/test_context_menu_regressions.mjs`,
  `tests/test_contextual_actions.mjs` and `tests/check_contextual_actions.sh`.

### 5. Automatic refresh when an image file changes (`DockHost.qml`)

- [x] Spike first: confirm that a Quickshell `FileView { watchChanges: true }`
  reports changes to a PNG/SVG without loading large files badly. Add support to
  `tests/stubs/Quickshell/Io/FileView.qml` if needed.
  Result (Quickshell 0.3.1): with `preload: false` the file is never read and no
  signal fires on creation; `fileChanged` fires for in-place writes,
  rename-saves, deletes, re-creation (twice) and files that appear later.
- [x] `Instantiator` of one watcher per distinct local source across both
  collections. Changes bump `iconReloadRevision` after a short debounce
  (about 250 ms). Paths/debounce live in `components/DockIconReloadScheduler.qml`
  (`tests/tst_iconreloadscheduler.qml`).
- [x] (Not needed: spike passed.) If the spike fails, keep the CLI `reload` and note the limitation. The
  dialog still works.

### 6. Docs and policy

- [x] AGENTS.md: replace the CLI-only icon rule and the FDM-927 exception with
  the one-dialog rule.
- [x] `docs/CONFIGURATION.md`, `docs/AGENT_CONFIGURATION.md`,
  `docs/CLI_REFERENCE.md` and README: describe the dialog, remove Copy Icon
  Command, and keep the CLI sections.
- [x] Remove the "FDM-927 narrow UI exception" comment from the dialog.

### 7. Validation and delivery

- [ ] Full local gate from AGENTS.md: run, `bash -n`, qmltestrunner,
  `omarchy plugin validate .`, qmllint on the touched files including the new
  dialog, and `git diff --check`.
- [ ] KVM guest (`docs/DEV_SESSIONS.md`) screenshots of: menu, new icon, profile
  window, customized window, reset, missing image, pinned app with no windows,
  in light and dark themes.
  Partial (session `icondlg-qa-a`, standalone, `QT_QPA_PLATFORMTHEME=gtk3`):
  everything except the browser profile window, which needs a guest browser.
- [ ] Your desktop preview with `smartdock dev use icons-improvements`, then
  `smartdock dev reset`.
- [ ] PR per `docs/DELIVERY.md`.

## Risks

- **Two app identities.** Title rules key on the raw Wayland app ID; app and
  profile icons key on the desktop ID. Mixing them up saves a rule that never
  matches. The model tests cover this.
- **Existing hand-written rules** with complex patterns must stay intact. The
  dialog only shows them in the exact-pattern field.
- **Grouping.** A new title rule splits dock groups (existing behavior). The
  preview shows which windows are affected, so the split is expected.
