# Dock Settings Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Dock Settings to match the approved compact, icon-led, theme-aware mockup while preserving live previews, persistence, responsive behavior, and dock hover interaction.

**Architecture:** `DockSettings.qml` remains the full-monitor layer-shell controller and owns all settings interactions. Reusable Lucide rendering, compact toggle rows, and section cards move into focused components; the settings content becomes a responsive card grid with a sticky footer and a UI-only launcher disclosure. Surface selectors use one atomic settings-patch signal so choosing Theme default, a token, or a custom value never writes a half-updated configuration.

**Tech Stack:** Qt 6 QML, Quickshell, Omarchy `qs.Commons`/`qs.Ui`, Qt5Compat `ColorOverlay`, JavaScript helpers in `DockModel.js`, Bash static checks, Qt Quick Test.

**Spec:** Approved mockup at `/home/admin/.codex/generated_images/01a059ba-5163-7ee3-8508-96f9c38400bb/exec-3aebe57b-9173-4d19-93f3-584bd58f64c0.png`.

## Global Constraints

- Implement only in `/home/admin/Projects/smart-omarchy-dock`; never modify `/usr/share/omarchy`.
- Preserve the existing JSON schema and all current keys. Do not add a persisted key for disclosure state or visual layout state.
- Never overwrite `/home/admin/.config/smartdock/dock.json`; edits affect bundled defaults and UI code only.
- Preserve unknown JSON keys, `pinned`, `margin`, and stored override values when an override is disabled.
- Keep slider previews continuous and save only on release. Toggles, button groups, dropdown choices, Reset, and Close keep their current commit semantics.
- Preserve the full-screen input mask, dock-edge pointer passthrough, 75 ms focus prime, `WlrKeyboardFocus.OnDemand`, outside-click dismissal, Escape handling, and in-overlay color dialog.
- The dock must remain hoverable while Dock Settings is open; magnification, glow, and tooltips must continue to update live.
- Use `Color.menu.*`, `Color.accent`, `Color.urgent`, `Style.*`, `Border.*`, and `Util.alpha()` for styling. Do not hardcode section colors.
- Use locally bundled Lucide SVGs and tint them through QML; no runtime network dependency.
- Wide layout target: 980 px panel width, no vertical scrolling on the current desktop. Narrow layouts may scroll inside the content area while header and footer remain fixed.
- Reset continues to restore the existing displayed defaults and must not modify unrelated keys.
- Bump the plugin version from `2.0.0` to `2.1.0`.
- All implementation happens in `/home/admin/Projects/smart-omarchy-dock`; the installed plugin is read-only deployment state and receives changes only through Git push followed by `omarchy plugin update`. Each task ends with a test checkpoint instead of a commit.

---

## File Structure

**Create**

- `components/DockLucideIcon.qml` — render and theme-tint one bundled Lucide SVG.
- `components/DockSettingsSection.qml` — bordered settings card with icon badge, title, optional description/accessory, and default body content.
- `components/DockSettingsToggleRow.qml` — compact accessible label/description plus Omarchy `ToggleSwitch`.
- `assets/lucide/sparkles.svg`
- `assets/lucide/palette.svg`
- `assets/lucide/panel-bottom.svg`
- `assets/lucide/mouse-pointer-click.svg`
- `assets/lucide/terminal.svg`
- `assets/lucide/rotate-ccw.svg`
- `assets/lucide/chevron-right.svg`
- `tests/check_settings_visual_system.sh`

**Modify**

- `components/DockModel.js` — add pure surface-mode and atomic surface-patch helpers.
- `components/DockSettings.qml` — replace the Appearance block with the approved card grid, progressive surface controls, launcher disclosure, and sticky footer.
- `components/Dock.qml` — forward atomic settings patches from the panel.
- `DockHost.qml` — save atomic settings patches with the existing `saveSettings()` merge/write operation.
- `tests/tst_dockmodel.qml` — test surface modes and patches.
- `tests/check_settings_layout.sh` — assert the approved hierarchy and fixed footer structure.
- `tests/check_surface_overrides.sh` — assert default/token/custom controls and patch wiring instead of the removed “Use custom…” rows.
- `assets/lucide/ATTRIBUTIONS.md` — list the newly bundled icons.
- `README.md` — document the redesigned UI and progressive surface controls.
- `CHANGELOG.md` — add the `2.1.0` entry.
- `manifest.json` — bump the plugin version.

**Leave unchanged**

- `config/dock.json`, `shell.qml`, and existing fallback settings: the redesign introduces no settings keys or default changes.
- Dock application, Trash, workspace, fullscreen, minimize, context-menu, drag-reorder, and auto-hide behavior.

---

### Task 1: Add Atomic Surface Override Helpers and Patch Persistence

**Files:**

- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockModel.js:124-182`
- Modify: `/home/admin/Projects/smart-omarchy-dock/tests/tst_dockmodel.qml:54-111`
- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockSettings.qml:24-26,125-176`
- Modify: `/home/admin/Projects/smart-omarchy-dock/components/Dock.qml:17-24,520-536`
- Modify: `/home/admin/Projects/smart-omarchy-dock/DockHost.qml:92-103,168-186`

**Interfaces:**

- Produces: `DockModel.surfaceColorMode(enabled: bool, value: string) -> "default" | "token" | "custom"`.
- Produces: `DockModel.surfaceColorPatch(enabledKey: string, valueKey: string, value: string) -> object`.
- Produces: `DockSettings.settingsPatchCommitted(var patch)`.
- Produces: `Dock.settingsPatchRequested(var patch)`.
- Consumes: existing `DockHost.saveSettings(patch)` and `DockModel.mergeSettings(original, patch)`.

- [ ] **Step 1: Add failing unit coverage for surface modes and patches**

Add this test to `tests/tst_dockmodel.qml` after `test_normalizesOptionalSurfaceOverrides()`:

```qml
function test_buildsAtomicSurfaceOverridePatches() {
  compare(DockModel.surfaceColorMode(false, "@accent"), "default")
  compare(DockModel.surfaceColorMode(true, ""), "default")
  compare(DockModel.surfaceColorMode(true, "@accent"), "token")
  compare(DockModel.surfaceColorMode(true, "#aabbcc"), "custom")

  compare(JSON.stringify(DockModel.surfaceColorPatch(
    "backgroundColorEnabled", "backgroundColor", "")),
    JSON.stringify({ backgroundColorEnabled: false }))
  compare(JSON.stringify(DockModel.surfaceColorPatch(
    "backgroundColorEnabled", "backgroundColor", "@Accent")),
    JSON.stringify({
      backgroundColorEnabled: true,
      backgroundColor: "@accent"
    }))
  compare(JSON.stringify(DockModel.surfaceColorPatch(
    "borderColorEnabled", "borderColor", "#AABBCC")),
    JSON.stringify({
      borderColorEnabled: true,
      borderColor: "#aabbcc"
    }))
  compare(JSON.stringify(DockModel.surfaceColorPatch(
    "borderColorEnabled", "borderColor", "not-a-color")), "{}")
  compare(JSON.stringify(DockModel.surfaceColorPatch(
    "autoHide", "borderColor", "@accent")), "{}")
}
```

- [ ] **Step 2: Run the QML tests and confirm the new test fails**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
```

Expected: failure because `surfaceColorMode` and `surfaceColorPatch` are undefined.

- [ ] **Step 3: Implement the pure surface helpers**

Add to `components/DockModel.js` after `normalizeSetting()`:

```javascript
function surfaceColorMode(enabled, value) {
  var normalized = String(value || "").trim()
  if (!enabled || normalized === "") return "default"
  return normalized.indexOf("@") === 0 ? "token" : "custom"
}

function surfaceColorPatch(enabledKey, valueKey, value) {
  var validPair = (enabledKey === "backgroundColorEnabled"
      && valueKey === "backgroundColor")
    || (enabledKey === "borderColorEnabled"
      && valueKey === "borderColor")
  if (!validPair) return ({})

  var raw = String(value === undefined || value === null ? "" : value).trim()
  var patch = {}
  if (raw === "") {
    patch[enabledKey] = false
    return patch
  }

  var normalized = normalizeSetting(valueKey, raw)
  if (normalized === "") return ({})
  patch[enabledKey] = true
  patch[valueKey] = normalized
  return patch
}
```

Default selection deliberately emits only the enable flag, preserving the user’s previously stored token or hex value.

- [ ] **Step 4: Run the QML tests and confirm they pass**

Run the Step 2 command.

Expected: all DockModel tests pass, including `test_buildsAtomicSurfaceOverridePatches`.

- [ ] **Step 5: Add the atomic patch signal through the dock boundary**

In `DockSettings.qml`, add the signal and helper:

```qml
signal settingsPatchCommitted(var patch)

function commitPatch(patch) {
  if (!patch || Object.keys(patch).length === 0) return
  settingsPatchCommitted(patch)
}
```

In `Dock.qml`, add the public signal:

```qml
signal settingsPatchRequested(var patch)
```

Wire the `DockSettings` instance:

```qml
onSettingsPatchCommitted: patch => {
  root.settingsPatchRequested(patch)
  for (var key in patch) root.clearSettingPreview(key)
}
```

Wire the `Dock` delegate in `DockHost.qml`:

```qml
onSettingsPatchRequested: patch => root.saveSettings(patch)
```

Keep `settingChanged`, `resetSettingsRequested`, and their current handlers intact for single-value controls and Reset.

- [ ] **Step 6: Add a static wiring assertion**

Append to `tests/check_surface_overrides.sh`:

```bash
if ! rg -n 'settingsPatchCommitted|settingsPatchRequested|saveSettings\(patch\)' \
    "$settings_qml" "$dock_qml" "$plugin_root/DockHost.qml" >/dev/null; then
  printf 'Surface selectors must persist default/token/custom changes atomically\n' >&2
  exit 1
fi
```

- [ ] **Step 7: Run the focused checks**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_surface_overrides.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
```

Expected: both commands exit 0.

---

### Task 2: Add the Lucide Visual Primitives

**Files:**

- Create: `/home/admin/Projects/smart-omarchy-dock/components/DockLucideIcon.qml`
- Create: `/home/admin/Projects/smart-omarchy-dock/components/DockSettingsSection.qml`
- Create: `/home/admin/Projects/smart-omarchy-dock/components/DockSettingsToggleRow.qml`
- Create: seven SVG files listed in File Structure
- Create: `/home/admin/Projects/smart-omarchy-dock/tests/check_settings_visual_system.sh`
- Modify: `/home/admin/Projects/smart-omarchy-dock/assets/lucide/ATTRIBUTIONS.md`

**Interfaces:**

- Produces: `DockLucideIcon { iconName, tint, iconSize }`.
- Produces: `DockSettingsSection { title, description, iconName, headerAccessory, default body content }`.
- Produces: `DockSettingsToggleRow { label, description, checked, toggled() }`.
- Consumes: existing `Color`, `Style`, `Border`, `BorderSurface`, `ToggleSwitch`, and local Lucide asset directory.

- [ ] **Step 1: Write a failing visual-system static check**

Create `tests/check_settings_visual_system.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for component in \
  DockLucideIcon.qml \
  DockSettingsSection.qml \
  DockSettingsToggleRow.qml; do
  test -s "$plugin_root/components/$component" || {
    printf 'Missing Dock Settings visual component: %s\n' "$component" >&2
    exit 1
  }
done

for icon in \
  sparkles palette panel-bottom mouse-pointer-click terminal rotate-ccw chevron-right; do
  test -s "$plugin_root/assets/lucide/$icon.svg" || {
    printf 'Missing Dock Settings Lucide icon: %s\n' "$icon" >&2
    exit 1
  }
done

rg -n 'ColorOverlay' "$plugin_root/components/DockLucideIcon.qml" >/dev/null
rg -n 'Util\.alpha\(Color\.accent' \
  "$plugin_root/components/DockSettingsSection.qml" >/dev/null
rg -n 'ToggleSwitch' \
  "$plugin_root/components/DockSettingsToggleRow.qml" >/dev/null

printf 'Dock Settings visual primitives and Lucide assets are present\n'
```

- [ ] **Step 2: Run the new check and confirm it fails**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_settings_visual_system.sh
```

Expected: failure naming the first missing component.

- [ ] **Step 3: Bundle the exact Lucide SVGs**

Fetch the canonical source files into the existing local Lucide directory:

```bash
cd /home/admin/Projects/smart-omarchy-dock
for icon in sparkles palette panel-bottom mouse-pointer-click terminal rotate-ccw chevron-right; do
  curl -fsSL "https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/$icon.svg" \
    -o "assets/lucide/$icon.svg"
done
```

Verify each asset is an SVG using `currentColor` so QML can tint it:

```bash
for icon in assets/lucide/{sparkles,palette,panel-bottom,mouse-pointer-click,terminal,rotate-ccw,chevron-right}.svg; do
  rg -n '<svg|stroke="currentColor"' "$icon"
done
```

Expected: every file prints an `<svg` line and a `stroke="currentColor"` line. Add the seven icon names to `assets/lucide/ATTRIBUTIONS.md`; keep the existing Lucide source and ISC license links.

- [ ] **Step 4: Create the tintable icon component**

Create `components/DockLucideIcon.qml`:

```qml
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.Commons

Item {
  id: root

  required property string iconName
  property color tint: Color.menu.text
  property real iconSize: Style.font.icon

  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    id: sourceImage
    anchors.fill: parent
    source: Qt.resolvedUrl("../assets/lucide/" + root.iconName + ".svg")
    sourceSize: Qt.size(width * 2, height * 2)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    visible: false
    layer.enabled: true
  }

  ColorOverlay {
    anchors.fill: sourceImage
    source: sourceImage
    color: root.tint
  }
}
```

- [ ] **Step 5: Create the reusable section card**

Create `components/DockSettingsSection.qml` with one header accessory slot and default body content:

```qml
pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property string title
  required property string iconName
  property string description: ""
  property alias headerAccessory: headerAccessorySlot.data
  default property alias contentData: body.data

  implicitWidth: Style.space(360)
  implicitHeight: sectionColumn.implicitHeight + Style.spacing.huge * 2
  radius: Style.cornerRadius
  color: Util.alpha(Color.accent, 0.035)
  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

  Column {
    id: sectionColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.huge
    spacing: Style.spacing.md

    Item {
      width: parent.width
      height: Math.max(iconBadge.height, titleBlock.implicitHeight,
        headerAccessorySlot.implicitHeight)

      BorderSurface {
        id: iconBadge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(34)
        height: width
        radius: Style.cornerRadius
        color: Util.alpha(Color.accent, 0.12)
        borderSpec: Border.controlSpec("selected", Color.menu.text, Color.accent)

        DockLucideIcon {
          anchors.centerIn: parent
          iconName: root.iconName
          iconSize: Style.space(18)
          tint: Color.accent
        }
      }

      Column {
        id: titleBlock
        anchors.left: iconBadge.right
        anchors.right: headerAccessorySlot.left
        anchors.leftMargin: Style.spacing.md
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          width: parent.width
          text: root.title
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: root.description !== ""
          width: parent.width
          text: root.description
          color: Util.alpha(Color.menu.text, 0.56)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        id: headerAccessorySlot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Column {
      id: body
      width: parent.width
      spacing: Style.spacing.sm
    }
  }
}
```

- [ ] **Step 6: Create the compact toggle row**

Create `components/DockSettingsToggleRow.qml`:

```qml
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string label
  property string description: ""
  property bool checked: false
  property color foreground: Color.menu.text
  signal toggled()

  activeFocusOnTab: enabled
  implicitHeight: description === "" ? Style.spacing.controlHeight
    : Math.max(Style.spacing.controlHeight, labels.implicitHeight)

  Keys.onReturnPressed: root.toggled()
  Keys.onEnterPressed: root.toggled()
  Keys.onSpacePressed: root.toggled()

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: toggle.left
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      text: root.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      visible: root.description !== ""
      width: parent.width
      text: root.description
      color: Util.alpha(root.foreground, 0.56)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    foreground: root.foreground
    accent: Color.accent
    interactive: false
  }

  TapHandler {
    enabled: root.enabled
    onTapped: root.toggled()
  }
}
```

- [ ] **Step 7: Run visual primitive checks and lint**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_settings_visual_system.sh
/usr/lib/qt6/bin/qmllint \
  -I /usr/share/omarchy/shell \
  -I /home/admin/.cache/smartdock/qml-imports \
  components/DockLucideIcon.qml \
  components/DockSettingsSection.qml \
  components/DockSettingsToggleRow.qml
```

Expected: the shell check exits 0; `qmllint` exits 0 with only the repository’s existing incomplete-qmltypes warnings.

---

### Task 3: Build the Fixed Header, Scrollable Content Area, and Sticky Footer

**Files:**

- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockSettings.qml:28-39,287-363,919-928`
- Modify: `/home/admin/Projects/smart-omarchy-dock/tests/check_settings_layout.sh`

**Interfaces:**

- Consumes: existing `root.close()`, `root.resetRequested()`, `DockModel.resetSettingsPatch()`, mask, focus-prime, and color-dialog behavior.
- Produces: `settingsHeader`, `settingsContent`, `settingsFooter`, and `advancedExpanded` UI state.

- [ ] **Step 1: Replace the layout test with assertions for the approved shell**

Keep the existing 980 px and responsive `Flow` assertions, then add:

```bash
grep -Eq 'panelHeight: Math\.min\(820,' "$settings_qml" \
  || { echo "Dock Settings should leave the bottom dock visible" >&2; exit 1; }
grep -Eq 'id: settingsHeader' "$settings_qml" \
  || { echo "Dock Settings is missing its fixed header" >&2; exit 1; }
grep -Eq 'id: settingsContent' "$settings_qml" \
  || { echo "Dock Settings is missing its scrollable content area" >&2; exit 1; }
grep -Eq 'id: settingsFooter' "$settings_qml" \
  || { echo "Dock Settings is missing its sticky footer" >&2; exit 1; }
grep -Eq 'property bool advancedExpanded' "$settings_qml" \
  || { echo "Dock Settings is missing UI-only launcher disclosure state" >&2; exit 1; }
grep -Eq 'property bool compactControls' "$settings_qml" \
  || { echo "Dock Settings is missing its narrow control layout breakpoint" >&2; exit 1; }
```

- [ ] **Step 2: Run the layout test and confirm it fails**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_settings_layout.sh
```

Expected: failure because the fixed header/footer structure and 820 px height cap do not exist.

- [ ] **Step 3: Introduce compact panel geometry and UI-only disclosure state**

Change the height cap and add the disclosure property near the existing panel geometry:

```qml
property bool advancedExpanded: false

readonly property int panelHeight: Math.min(820,
  Math.max(360, panelScreenHeight - panelMargin * 2))
readonly property bool compactControls: panelWidth < 560
```

Keep `panelWidth`, `wideLayout`, `panelOrigin`, and the centered-monitor behavior unchanged.

- [ ] **Step 4: Replace the all-content Flickable with three anchored regions**

Inside `settingsCard`, retain `HoverHandler { id: panelHover }`, then use this structure:

```qml
Item {
  anchors.fill: parent
  anchors.margins: Style.spacing.lg

  Item {
    id: settingsHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Style.space(62)

    Column {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Text {
        text: "Dock Settings"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        text: "✓  Changes apply immediately"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    BorderSurface {
      anchors.right: parent.right
      anchors.top: parent.top
      width: Style.spacing.controlHeight
      height: width
      radius: Style.cornerRadius
      color: "transparent"
      borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

      DockLucideIcon {
        anchors.centerIn: parent
        iconName: "x"
        iconSize: Style.space(18)
        tint: Color.menu.text
      }

      TapHandler { onTapped: root.close() }
    }
  }

  Flickable {
    id: settingsContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: settingsHeader.bottom
    anchors.bottom: settingsFooter.top
    anchors.bottomMargin: Style.spacing.md
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    QQC.ScrollBar.vertical: QQC.ScrollBar {
      policy: settingsContent.contentHeight > settingsContent.height
        ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
    }

    Column {
      id: settingsColumn
      width: settingsContent.width
      spacing: Style.spacing.md
    }
  }

  Item {
    id: settingsFooter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(52)
  }
}
```

Move all setting cards into `settingsColumn`. The footer buttons are added in Task 6.

- [ ] **Step 5: Run the focused layout and popup tests**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_settings_layout.sh
bash tests/check_settings_popup_focus.sh
```

Expected: both tests exit 0. The popup-focus test confirms the structural rewrite did not remove pointer passthrough or focus settling.

---

### Task 4: Implement Icons, Hover Effect, Layout, and Behavior Cards

**Files:**

- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockSettings.qml:365-435,720-864`
- Modify: `/home/admin/Projects/smart-omarchy-dock/tests/check_settings_layout.sh`

**Interfaces:**

- Consumes: `DockSettingsSection`, `DockSettingsToggleRow`, `DockSettingSlider`, `ButtonGroup`, and existing `current`, `preview`, and `commit` functions.
- Produces: the top and lower two-column card rows shown in the approved mockup.

- [ ] **Step 1: Add failing hierarchy assertions**

Append to `tests/check_settings_layout.sh`:

```bash
for section in 'Icons' 'Hover effect' 'Dock surface' 'Layout' 'Behavior'; do
  rg -n "title: \"$section\"" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing section: %s\n' "$section" >&2
    exit 1
  }
done

for icon in maximize-2 sparkles palette panel-bottom mouse-pointer-click; do
  rg -n "iconName: \"$icon\"" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing section icon: %s\n' "$icon" >&2
    exit 1
  }
done

if rg -n 'text: ".*Appearance"' "$settings_qml" >/dev/null; then
  echo "The old mixed Appearance section should be removed" >&2
  exit 1
fi
```

- [ ] **Step 2: Run the layout test and confirm it fails on the new hierarchy**

Run `bash tests/check_settings_layout.sh` from the plugin root.

Expected: failure naming the first missing section.

- [ ] **Step 3: Build the Icons and Hover effect row**

Add a `Flow` as the first child of `settingsColumn`:

```qml
Flow {
  width: parent.width
  spacing: Style.spacing.md
  flow: Flow.LeftToRight

  DockSettingsSection {
    width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
    title: "Icons"
    iconName: "maximize-2"

    DockSettingSlider {
      width: parent.width
      label: "Icon size"
      value: root.current("iconSize")
      minimum: 24
      maximum: 96
      step: 1
      suffix: " px"
      onPreviewed: value => root.preview("iconSize", value)
      onCommitted: value => root.commit("iconSize", value)
    }

    DockSettingSlider {
      width: parent.width
      label: "Magnification"
      value: root.current("magnification")
      minimum: 1
      maximum: 2
      step: 0.05
      decimals: 2
      suffix: "x"
      onPreviewed: value => root.preview("magnification", value)
      onCommitted: value => root.commit("magnification", value)
    }

    DockSettingSlider {
      width: parent.width
      label: "Effect radius"
      value: root.current("magnificationRadius")
      minimum: 40
      maximum: 240
      step: 5
      suffix: " px"
      onPreviewed: value => root.preview("magnificationRadius", value)
      onCommitted: value => root.commit("magnificationRadius", value)
    }
  }

  DockSettingsSection {
    width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
    title: "Hover effect"
    description: "Accent glow behind icons under the pointer"
    iconName: "sparkles"

    headerAccessory: ToggleSwitch {
      checked: root.current("hoverGlowEnabled")
      foreground: Color.menu.text
      accent: Color.accent
      onToggled: root.commit("hoverGlowEnabled", !checked)
    }

    DockSettingSlider {
      width: parent.width
      enabled: root.current("hoverGlowEnabled")
      opacity: enabled ? 1 : 0.45
      label: "Glow intensity"
      value: root.current("hoverGlowOpacity") * 100
      minimum: 0
      maximum: 100
      step: 5
      suffix: "%"
      onPreviewed: value => root.preview("hoverGlowOpacity", value / 100)
      onCommitted: value => root.commit("hoverGlowOpacity", value / 100)
    }

    DockSettingSlider {
      width: parent.width
      enabled: root.current("hoverGlowEnabled")
      opacity: enabled ? 1 : 0.45
      label: "Glow radius"
      value: root.current("hoverGlowRadius")
      minimum: 0
      maximum: 100
      step: 5
      suffix: "%"
      onPreviewed: value => root.preview("hoverGlowRadius", value)
      onCommitted: value => root.commit("hoverGlowRadius", value)
    }
  }
}
```

Give the two top cards IDs `iconsSection` and `hoverSection` and use these
height bindings:

```qml
// Icons card
height: root.wideLayout
  ? Math.max(iconsSection.implicitHeight, hoverSection.implicitHeight)
  : iconsSection.implicitHeight

// Hover effect card
height: root.wideLayout
  ? Math.max(iconsSection.implicitHeight, hoverSection.implicitHeight)
  : hoverSection.implicitHeight
```

This keeps the approved equal card edges without forcing extra height after
the cards stack.

- [ ] **Step 4: Build the Layout and Behavior row**

Add another responsive `Flow` immediately after the top card row with two
`DockSettingsSection` children. Task 5 inserts the full-width Dock surface card
between these two flows without changing either flow’s contents.

The Layout card must contain:

```qml
DockSettingsSection {
  width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
  title: "Layout"
  iconName: "panel-bottom"

  Item {
    readonly property bool stacked: root.compactControls
    width: parent.width
    height: stacked
      ? positionLabel.implicitHeight + Style.spacing.sm
        + positionGroup.implicitHeight
      : Math.max(positionLabel.implicitHeight, positionGroup.implicitHeight)

    Text {
      id: positionLabel
      anchors.left: parent.left
      anchors.top: parent.stacked ? parent.top : undefined
      anchors.verticalCenter: parent.stacked ? undefined : parent.verticalCenter
      text: "Position"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    ButtonGroup {
      id: positionGroup
      anchors.left: parent.stacked ? parent.left : undefined
      anchors.right: parent.stacked ? undefined : parent.right
      anchors.top: parent.stacked ? positionLabel.bottom : undefined
      anchors.topMargin: parent.stacked ? Style.spacing.sm : 0
      anchors.verticalCenter: parent.stacked ? undefined : parent.verticalCenter
      spacing: 2
      options: [
        { value: "top", label: "Top" },
        { value: "bottom", label: "Bottom" },
        { value: "left", label: "Left" },
        { value: "right", label: "Right" }
      ]
      value: root.current("position")
      foreground: Color.menu.text
      background: Color.menu.background
      onChanged: value => root.commit("position", value)
    }
  }

  DockSettingsToggleRow {
    width: parent.width
    label: "Full length"
    checked: root.current("fullLength")
    onToggled: root.commit("fullLength", !checked)
  }
}
```

The Behavior card must contain:

```qml
DockSettingsSection {
  width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
  title: "Behavior"
  iconName: "mouse-pointer-click"

  DockSettingsToggleRow {
    width: parent.width
    label: "Auto-hide"
    checked: root.current("autoHide")
    onToggled: root.commit("autoHide", !checked)
  }

  DockSettingsToggleRow {
    width: parent.width
    label: "Reserve space"
    description: root.current("autoHide")
      ? "Unavailable while Auto-hide is enabled" : ""
    enabled: !root.current("autoHide")
    opacity: enabled ? 1 : 0.45
    checked: DockModel.shouldReserveSpace(
      root.current("reserveSpace"), root.current("autoHide"))
    onToggled: root.commit("reserveSpace", !checked)
  }

  Item {
    readonly property bool stacked: root.compactControls
    width: parent.width
    height: stacked
      ? clickLabel.implicitHeight + Style.spacing.sm
        + clickActionGroup.implicitHeight
      : Math.max(clickLabel.implicitHeight, clickActionGroup.implicitHeight)

    Text {
      id: clickLabel
      anchors.left: parent.left
      anchors.top: parent.stacked ? parent.top : undefined
      anchors.verticalCenter: parent.stacked ? undefined : parent.verticalCenter
      text: "Click action"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    ButtonGroup {
      id: clickActionGroup
      anchors.left: parent.stacked ? parent.left : undefined
      anchors.right: parent.stacked ? undefined : parent.right
      anchors.top: parent.stacked ? clickLabel.bottom : undefined
      anchors.topMargin: parent.stacked ? Style.spacing.sm : 0
      anchors.verticalCenter: parent.stacked ? undefined : parent.verticalCenter
      spacing: 2
      options: [
        { value: "focus-or-launch", label: "Focus or launch" },
        { value: "launch", label: "Always launch" }
      ]
      value: root.current("clickAction")
      foreground: Color.menu.text
      background: Color.menu.background
      onChanged: value => root.commit("clickAction", value)
    }
  }
}
```

Give the lower cards IDs `layoutSection` and `behaviorSection` and use:

```qml
// Layout card
height: root.wideLayout
  ? Math.max(layoutSection.implicitHeight, behaviorSection.implicitHeight)
  : layoutSection.implicitHeight

// Behavior card
height: root.wideLayout
  ? Math.max(layoutSection.implicitHeight, behaviorSection.implicitHeight)
  : behaviorSection.implicitHeight
```

The Behavior card is taller by content, so this supplies the matching bottom
edge for Layout without introducing fixed pixel heights.

- [ ] **Step 5: Run the hierarchy, reserve-space, and QML tests**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_settings_layout.sh
bash tests/check_reserve_space_visibility.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
```

Expected: all commands exit 0.

---

### Task 5: Implement the Progressive Dock Surface Card

**Files:**

- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockSettings.qml:43-176,428-718`
- Modify: `/home/admin/Projects/smart-omarchy-dock/tests/check_surface_overrides.sh`
- Modify: `/home/admin/Projects/smart-omarchy-dock/tests/check_color_picker.sh`

**Interfaces:**

- Consumes: `DockModel.surfaceColorMode`, `DockModel.surfaceColorPatch`, `root.commitPatch`, `DockColorTokenDropdown`, `DockColorSwatch`, and existing `ColorDialog` functions.
- Produces: Theme default/token/custom color modes without permanently visible disabled fields.

- [ ] **Step 1: Update the static override expectations and confirm failure**

Replace the old text assertion for `Use custom background color`, `Use custom border color`, and `Use custom border width` in `tests/check_surface_overrides.sh` with:

```bash
for label in 'Dock surface' 'Background opacity' 'Theme default' \
  'Custom hex' 'Custom width'; do
  rg -n "$label" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing progressive surface control: %s\n' "$label" >&2
    exit 1
  }
done

if rg -n 'Use custom background color|Use custom border color|Use custom border width' \
    "$settings_qml" >/dev/null; then
  printf 'Dock Settings still exposes the old always-expanded override rows\n' >&2
  exit 1
fi
```

Run `bash tests/check_surface_overrides.sh`.

Expected: failure because the new surface hierarchy is not present.

- [ ] **Step 2: Add mode helpers local to Dock Settings**

Add these functions beside the existing color helpers in `DockSettings.qml`:

```qml
function surfaceMode(enabledKey, valueKey) {
  return DockModel.surfaceColorMode(current(enabledKey), current(valueKey))
}

function defaultTokenOptions(label, color) {
  return [{ value: "", label: label, color: color }].concat(themeColorOptions)
}

function selectSurfaceColor(enabledKey, valueKey, value) {
  commitPatch(DockModel.surfaceColorPatch(enabledKey, valueKey, value))
}

function enableCustomSurfaceColor(enabledKey, valueKey) {
  var currentValue = current(valueKey)
  if (String(currentValue).indexOf("#") === 0) {
    selectSurfaceColor(enabledKey, valueKey, currentValue)
    return
  }

  var resolved = colorForSetting(valueKey)
  selectSurfaceColor(enabledKey, valueKey, DockModel.colorToHex(resolved))
}
```

Update `colorForSetting()` so both `backgroundColor` and `borderColor` continue resolving against their respective Omarchy fallback tokens.

- [ ] **Step 3: Build the full-width Dock surface card**

Insert between the top and lower card flows:

```qml
DockSettingsSection {
  width: parent.width
  title: "Dock surface"
  iconName: "palette"

  DockSettingSlider {
    width: parent.width
    label: "Background opacity"
    value: root.current("backgroundOpacity") * 100
    minimum: 0
    maximum: 100
    step: 5
    suffix: "%"
    onPreviewed: value => root.preview("backgroundOpacity", value / 100)
    onCommitted: value => root.commit("backgroundOpacity", value / 100)
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.md
    flow: Flow.LeftToRight

    Column {
      width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
      spacing: Style.spacing.sm

      Text {
        text: "Background"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      DockColorTokenDropdown {
        width: parent.width
        showLabel: false
        enabled: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
          !== "custom"
        opacity: enabled ? 1 : 0.45
        value: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
          === "token" ? root.current("backgroundColor") : ""
        options: root.defaultTokenOptions("Theme default", Color.menu.background)
        fallbackColor: Color.menu.background
        foreground: Color.menu.text
        background: Color.menu.background
        popupBorder: Color.menu.border
        accent: Color.accent
        onChanged: value => root.selectSurfaceColor(
          "backgroundColorEnabled", "backgroundColor", value)
      }

      DockSettingsToggleRow {
        width: parent.width
        label: "Custom hex"
        checked: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
          === "custom"
        onToggled: checked
          ? root.commitPatch({ backgroundColorEnabled: false })
          : root.enableCustomSurfaceColor(
            "backgroundColorEnabled", "backgroundColor")
      }

      Item {
        width: parent.width
        height: root.surfaceMode("backgroundColorEnabled", "backgroundColor")
          === "custom" ? Style.spacing.controlHeight : 0
        visible: height > 0

        TextField {
          id: backgroundColorInput
          anchors.left: parent.left
          anchors.right: backgroundColorSwatch.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          placeholderText: "#RRGGBB or #AARRGGBB"
          text: root.current("backgroundColor")
          foreground: Color.menu.text
          accent: Color.accent
          onEditingFinished: root.commitColor(
            "backgroundColor", backgroundColorInput)
        }

        DockColorSwatch {
          id: backgroundColorSwatch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          value: root.current("backgroundColor")
          fallbackColor: Color.menu.background
          displayColor: root.colorForSetting("backgroundColor")
          onClicked: root.openColorPicker("backgroundColor")
        }
      }
    }

    Column {
      width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
      spacing: Style.spacing.sm

      Text {
        text: "Border"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      DockColorTokenDropdown {
        width: parent.width
        showLabel: false
        enabled: root.surfaceMode("borderColorEnabled", "borderColor")
          !== "custom"
        opacity: enabled ? 1 : 0.45
        value: root.surfaceMode("borderColorEnabled", "borderColor")
          === "token" ? root.current("borderColor") : ""
        options: root.defaultTokenOptions("Theme default", Color.menu.border)
        fallbackColor: Color.menu.border
        foreground: Color.menu.text
        background: Color.menu.background
        popupBorder: Color.menu.border
        accent: Color.accent
        onChanged: value => root.selectSurfaceColor(
          "borderColorEnabled", "borderColor", value)
      }

      DockSettingsToggleRow {
        width: parent.width
        label: "Custom hex"
        checked: root.surfaceMode("borderColorEnabled", "borderColor")
          === "custom"
        onToggled: checked
          ? root.commitPatch({ borderColorEnabled: false })
          : root.enableCustomSurfaceColor("borderColorEnabled", "borderColor")
      }

      Item {
        width: parent.width
        height: root.surfaceMode("borderColorEnabled", "borderColor")
          === "custom" ? Style.spacing.controlHeight : 0
        visible: height > 0

        TextField {
          id: borderColorInput
          anchors.left: parent.left
          anchors.right: borderColorSwatch.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          placeholderText: "#RRGGBB or #AARRGGBB"
          text: root.current("borderColor")
          foreground: Color.menu.text
          accent: Color.accent
          onEditingFinished: root.commitColor(
            "borderColor", borderColorInput)
        }

        DockColorSwatch {
          id: borderColorSwatch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          value: root.current("borderColor")
          fallbackColor: Color.menu.border
          displayColor: root.colorForSetting("borderColor")
          onClicked: root.openColorPicker("borderColor")
        }
      }

      Item {
        width: parent.width
        height: Style.spacing.controlHeight

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.current("borderWidthEnabled")
          text: "Width"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.current("borderWidthEnabled")
          text: "Theme default"
          color: Util.alpha(Color.menu.text, 0.56)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        DockSettingSlider {
          anchors.fill: parent
          visible: root.current("borderWidthEnabled")
          label: "Width"
          value: root.current("borderWidth")
          minimum: 0
          maximum: 8
          step: 1
          suffix: " px"
          onPreviewed: value => root.preview("borderWidth", value)
          onCommitted: value => root.commit("borderWidth", value)
        }
      }

      DockSettingsToggleRow {
        width: parent.width
        label: "Custom width"
        checked: root.current("borderWidthEnabled")
        onToggled: root.commit("borderWidthEnabled", !checked)
      }
    }
  }
}
```

When Custom width is off, the muted, right-aligned `Theme default` value is
display-only. Preserve `borderWidth` in JSON while `borderWidthEnabled` is false.

- [ ] **Step 4: Preserve color-picker and input synchronization behavior**

Keep these invariants in the rewritten file:

```qml
options: ColorDialog.ShowAlphaChannel | ColorDialog.DontUseNativeDialog
popupType: QQC.Popup.Item
onAccepted: root.commitColorValue(settingKey, selectedColor)
```

`syncAppearanceInputs()` must continue updating `backgroundColorInput` and `borderColorInput` only when those fields do not have active focus. `commitColorValue()` must update the matching field before emitting the setting commit.

- [ ] **Step 5: Run surface, picker, and model tests**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_surface_overrides.sh
bash tests/check_color_picker.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
```

Expected: all commands exit 0.

---

### Task 6: Add the Advanced Launcher Disclosure and Footer Actions

**Files:**

- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockSettings.qml:178-193,866-928`
- Modify: `/home/admin/Projects/smart-omarchy-dock/tests/check_settings_layout.sh`

**Interfaces:**

- Consumes: `advancedExpanded`, `commandInput`, `commitControlCommand()`, `root.resetRequested()`, `root.close()`, `DockLucideIcon`, `Color.urgent`.
- Produces: keyboard-accessible disclosure row, conditional launcher field, urgent Reset action, neutral Close action.

- [ ] **Step 1: Add failing disclosure/footer assertions**

Append to `tests/check_settings_layout.sh`:

```bash
for text in 'Advanced launcher settings' 'Reset to defaults' 'Close'; do
  rg -n "$text" "$settings_qml" >/dev/null || {
    printf 'Dock Settings is missing action: %s\n' "$text" >&2
    exit 1
  }
done

rg -n 'iconName: "terminal"' "$settings_qml" >/dev/null \
  || { echo "Launcher disclosure is missing its Lucide icon" >&2; exit 1; }
rg -n 'iconName: "rotate-ccw"' "$settings_qml" >/dev/null \
  || { echo "Reset action is missing its Lucide icon" >&2; exit 1; }
rg -n 'Color\.urgent' "$settings_qml" >/dev/null \
  || { echo "Reset action must use the Omarchy urgent token" >&2; exit 1; }
```

Run `bash tests/check_settings_layout.sh` and confirm it fails.

- [ ] **Step 2: Add the launcher disclosure below the card rows**

Add a bordered disclosure surface to `settingsColumn`:

```qml
BorderSurface {
  width: parent.width
  height: launcherDisclosureColumn.implicitHeight + Style.spacing.huge * 2
  radius: Style.cornerRadius
  color: Util.alpha(Color.accent, 0.025)
  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)
  activeFocusOnTab: true

  Keys.onReturnPressed: root.advancedExpanded = !root.advancedExpanded
  Keys.onEnterPressed: root.advancedExpanded = !root.advancedExpanded
  Keys.onSpacePressed: root.advancedExpanded = !root.advancedExpanded

  Column {
    id: launcherDisclosureColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.huge
    spacing: Style.spacing.sm

    Item {
      width: parent.width
      height: Style.spacing.controlHeight

      DockLucideIcon {
        id: launcherIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconName: "terminal"
        iconSize: Style.space(20)
        tint: Color.accent
      }

      Text {
        anchors.left: launcherIcon.right
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: "Advanced launcher settings"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      DockLucideIcon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconName: "chevron-right"
        iconSize: Style.space(18)
        tint: Color.menu.text
        rotation: root.advancedExpanded ? 90 : 0
        Behavior on rotation { NumberAnimation { duration: 120 } }
      }

      TapHandler {
        onTapped: root.advancedExpanded = !root.advancedExpanded
      }
    }

    Column {
      visible: root.advancedExpanded
      width: parent.width
      spacing: Style.spacing.xs

      Text {
        text: "Command run when Open App Launcher is selected"
        color: Util.alpha(Color.menu.text, 0.56)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      TextField {
        id: commandInput
        width: parent.width
        placeholderText: "omarchy-menu toggle apps"
        foreground: Color.menu.text
        onEditingFinished: root.commitControlCommand()
        Keys.onEscapePressed: {
          text = root.current("controlCommand")
          focus = false
        }
      }
    }
  }
}
```

Keep `commandInput` instantiated while collapsed by using `visible`, not a `Loader`; `open()`, `close()`, reset, and settings synchronization can continue referencing the ID.

- [ ] **Step 3: Build the sticky Reset and Close actions**

Inside `settingsFooter`, add two bordered actions. The Reset action is left-aligned:

```qml
BorderSurface {
  anchors.left: parent.left
  anchors.verticalCenter: parent.verticalCenter
  width: Style.space(168)
  height: Style.spacing.controlHeight
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.controlSpec("normal", Color.urgent, Color.urgent)

  DockLucideIcon {
    id: resetIcon
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    iconName: "rotate-ccw"
    iconSize: Style.space(18)
    tint: Color.urgent
  }

  Text {
    anchors.left: resetIcon.right
    anchors.leftMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    text: "Reset to defaults"
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  TapHandler {
    onTapped: {
      commandInput.text = DockModel.resetSettingsPatch().controlCommand
      root.resetRequested()
    }
  }
}
```

Add the right-aligned Close action:

```qml
BorderSurface {
  anchors.right: parent.right
  anchors.verticalCenter: parent.verticalCenter
  width: Style.space(112)
  height: Style.spacing.controlHeight
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

  Text {
    anchors.centerIn: parent
    text: "Close"
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  TapHandler { onTapped: root.close() }
}
```

- [ ] **Step 4: Verify launcher persistence and fixed footer behavior**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
bash tests/check_settings_layout.sh
bash tests/check_settings_popup_focus.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
```

Expected: all commands exit 0.

---

### Task 7: Responsive Polish, Documentation, Version, and Full Verification

**Files:**

- Modify: `/home/admin/Projects/smart-omarchy-dock/components/DockSettings.qml`
- Modify: `/home/admin/Projects/smart-omarchy-dock/README.md:141-161`
- Modify: `/home/admin/Projects/smart-omarchy-dock/CHANGELOG.md:1-38`
- Modify: `/home/admin/Projects/smart-omarchy-dock/manifest.json:5`

**Interfaces:**

- Consumes: all components and signals from Tasks 1-6.
- Produces: release `2.1.0` with documented wide/narrow layouts and verified runtime behavior.

- [ ] **Step 1: Complete responsive width and height bindings**

For every paired section and Dock surface inner column, use:

```qml
width: root.wideLayout ? (parent.width - parent.spacing) / 2 : parent.width
```

Keep all containing `Flow` objects on:

```qml
flow: Flow.LeftToRight
```

Do not use `Flow.TopToBottom`. Ensure hidden custom inputs contribute `height: 0`, and ensure the expanded launcher contributes its actual implicit height to `settingsColumn`. On the current desktop, `settingsContent.contentHeight <= settingsContent.height`; on narrow screens, only `settingsContent` scrolls.

Below the 560 px `compactControls` breakpoint, keep the Position and Click
action label-above-group anchor bindings from Task 4. At and above the
breakpoint, keep the approved single-row presentation. Add this assertion to
`tests/check_settings_layout.sh`:

```bash
rg -n 'compactControls: panelWidth < 560' "$settings_qml" >/dev/null \
  || { echo "Narrow settings controls must stack below 560 px" >&2; exit 1; }
```

- [ ] **Step 2: Verify keyboard and pointer interactions manually before documentation**

Run the active shell and perform this exact checklist:

1. Open Dock Controls and select Dock Settings.
2. Confirm the settings panel is centered and the bottom dock is fully visible.
3. Move the pointer across dock icons while the panel is open; verify magnification, glow, and tooltips update.
4. Tab through close, sliders, token dropdowns, toggles, button groups, launcher disclosure, Reset, and Close.
5. Press Escape from the panel; verify it closes and slider previews clear.
6. Reopen, expand Advanced launcher settings, edit the command, press Enter, close, reopen, and verify persistence.
7. Select Theme default, `@accent`, and a custom hex for both Background and Border; verify each applies live and survives reopen.
8. Open both color swatches; verify the dialog appears above Dock Settings and accepts alpha values.
9. Enable Custom width, change it, disable it, and verify the dock returns to the theme width without deleting the stored custom width.
10. Enable Auto-hide; verify Reserve space becomes unavailable and the hidden dock does not reserve space. Disable Auto-hide and verify the stored Reserve space choice returns.
11. Change the active Omarchy theme; verify card, text, icon badge, control, Reset, token swatch, dock background, and dock border colors update from theme tokens.
12. Temporarily set the panel width below 560 px; verify cards stack, Position
    and Click action labels move above their option groups, header/footer stay
    fixed, and only the middle content scrolls. Restore the 980 px cap before
    the final smoke test.

- [ ] **Step 3: Update documentation and release metadata**

In `README.md`, replace the old “wide two-column Appearance panel” description with:

```markdown
Dock Settings uses an icon-led responsive card layout. Icon geometry and hover
effects sit side by side, Dock surface exposes Theme default, Omarchy token,
and custom hex modes without leaving disabled inputs visible, and Layout and
Behavior share a compact row. Advanced launcher settings expand on demand;
Reset and Close remain fixed at the bottom. On narrow screens the card grid
stacks and the middle content area scrolls while the header and footer remain
visible.
```

Add a `2.1.0 - 2026-09-01` entry at the top of `CHANGELOG.md`:

```markdown
## 2.1.0 - 2026-09-01

### Changed

- Reorganized Dock Settings into icon-led Icons, Hover effect, Dock surface,
  Layout, and Behavior cards matching the approved compact layout.
- Added progressive Theme default, Omarchy token, custom hex, and custom border
  width controls while preserving the existing JSON schema.
- Added a collapsible launcher section and fixed Reset/Close footer.
- Added theme-tinted Lucide section and action icons using Omarchy accent and
  urgent tokens.
```

Set `manifest.json` version to:

```json
"version": "2.1.0"
```

- [ ] **Step 4: Run the full automated suite**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -import .
for test in tests/*.sh; do bash "$test"; done
bash -n install.sh uninstall.sh scripts/smartdock scripts/run
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint \
  -I /usr/share/omarchy/shell \
  -I /home/admin/.cache/smartdock/qml-imports \
  DockHost.qml Overlay.qml components/*.qml shell.qml
```

Expected:

- Qt Quick Test reports zero failed tests.
- Every shell test exits 0.
- Shell syntax validation exits 0.
- `omarchy plugin validate .` exits 0.
- `qmllint` exits 0; incomplete external qmltypes warnings are acceptable, QML syntax/type errors are not.

- [ ] **Step 5: Run the standalone smoke test**

Run:

```bash
cd /home/admin/Projects/smart-omarchy-dock
set +e
timeout 8s ./scripts/run --no-color > /tmp/smartdock-settings-redesign.log 2>&1
smoke_status=$?
set -e
test "$smoke_status" -eq 124
rg -n 'INFO: Configuration Loaded' /tmp/smartdock-settings-redesign.log
if rg -n 'TypeError|ReferenceError|Cannot assign|QQmlApplicationEngine failed|fatal|Error:' \
    /tmp/smartdock-settings-redesign.log; then
  exit 1
fi
```

Expected: timeout status 124 after successful startup, `Configuration Loaded` present, and no QML runtime error pattern. The known portal application-ID warning is acceptable.

- [ ] **Step 6: Reload the user shell and inspect the active log**

Run:

```bash
omarchy restart shell
latest_log="$(find /run/user/1000/quickshell/by-id \
  -mindepth 2 -maxdepth 2 -type f -name log.log \
  -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
rg -n 'Configuration Loaded|TypeError|ReferenceError|Cannot assign|QQmlApplicationEngine failed|fatal|Error:' \
  "$latest_log"
```

Expected: `Configuration Loaded` appears and no runtime error pattern appears.

---

## Completion Criteria

- The running panel matches the approved mockup’s hierarchy, spacing, icons, restrained theme coloring, progressive controls, disclosure, and footer.
- The bottom dock remains visible and responds to hover while settings are open.
- No new JSON keys exist; all prior configuration values and unknown keys survive edits and Reset semantics remain scoped.
- Theme default, token, custom hex, opacity, border width, layout, behavior, launcher, live preview, color dialog, keyboard, dismissal, and persistence flows pass the manual checklist.
- Automated tests, plugin validation, lint, standalone smoke, and active-shell log checks pass.
