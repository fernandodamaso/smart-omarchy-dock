# FDM-997 — native Widget chrome audit and source handoff

## Revision and evidence boundary

Source baseline: `22ed8f26ffbc531de8470c49528454e16be4be35` (main).
Original design handoff: `c660325bf437e4330b00f12cdd2beb3679d79ab9`
on `feat/sidebar-widget-split-scroll`. All original design files are retained.
The R1 parent/children/routing reconciliation is in
`docs/plans/2026-09-23-sidebar-widget-split-scroll.md`; its recovered original
proposal is retained as a clearly superseded appendix.

**Exact native source inspected:** `omacom/omarchy` commit
`28ceaae70ebac3a0edcc21f2faa77a90dc6d404c`. Its `version` file says
`4.0.0.alpha`; the commit and actual source files, not that version string,
identify this audit. `DockSidebar.qml` separately records an earlier installed
`omarchy 4.0.3-1` inspection. These are not interchangeable evidence: the current
installed package, Qt and Quickshell combination must be rechecked under FDM-1001.

**Remote test runtime:** Qt 6.4.2, `libqt6core6t64 6.4.2+dfsg-21.1build5`,
`qt6-declarative-dev-tools 6.4.2+dfsg-4build3`, exported from an isolated Ubuntu
24.04 Actions job. Quickshell and Hyprland are not installed in this remote
runtime. No Quickshell version, full-shell acceptance or KVM result is claimed.
The final PR records the exact candidate head and fresh Headless CI results.

## Native code inspected

All native paths below are relative to that exact Omarchy revision:

| Primitive / caller | Observed contract and composition decision |
| --- | --- |
| `shell/Ui/PanelSectionHeader.qml` | `Text`, inherited `text`, optional `foreground`, `fontFamily`, `fontSize`. Native defaults: caption, bold, `Qt.darker(foreground, 1.4)`, PlainText and `ceil(fontSize * .15)` top padding for glyph overshoot. No horizontal inset is imposed. Use the primitive for both WIDGETS and PINNED with no duplicated type/color recipe. |
| `shell/plugins/panels/monitor/Panel.qml`, `brightnessHeader` (around line 596) | First-party `PanelSectionHeader` labelled BRIGHTNESS, parent reserves the maximum implicit label/value height; overrides bar font and foreground when appropriate. SmartDock similarly respects the native label's implicit height. |
| `shell/Ui/Button.qml` | `iconText`, `text`, `tooltipText`, `focusable`, `foreground`, `accent`, `background`, padding and inherited Item `enabled` are supported. Default focusable is false. Explicit Return/Enter/Space handlers emit `clicked` on press when focusable. Mouse click takes focus only when focusable. Empty text/iconText permits a centered child WidgetIcon. |
| `shell/plugins/panels/monitor/Panel.qml`, `ScalePill: Button` (around line 833) | First-party composition binds text, caption font, foreground, padding, selected/cursor state and `onClicked`. Native Button's largest-state border reservation prevents control reflow on focus/hover. |
| `shell/Ui/BorderSurface.qml` | Surface exposes contentLeft/Right/Top/BottomInset, derived from border widths plus padding; use these to keep the transient header fill inside the card's focus strokes. |
| `shell/Commons/Style.qml`, `Color.qml`, `Border.qml`, `Util.qml` | Existing theme-driven space/font/radius, background/foreground/accent, state fills and border helpers. No new generic palette or WidgetKit semantic changes are introduced. Card fallbacks duplicate only the existing sidebar formulas when appearance is omitted. |

Native Button creates its tooltip with `tooltipText`, native tooltip colors,
400 ms delay and theme padding. It does not provide a separate accessible-label
property; the caller retains attached `Accessible.name` and Button role.
Qt's inherited disabled state blocks actual pointer/key activation. The section
plus explicitly keeps `focusable: true`, 28 logical-pixel dimensions and the
same accessible name, “Add or manage Widgets”. Collapse remains 24 logical pixels.

Both standalone `shell.qml` and plugin `Overlay.qml` compose the shared
`DockHost`/sidebar source. This change introduces no process, host, popup,
provider or settings owner. Source compatibility with both paths was inspected;
loading/rendering in both real host modes is still a local acceptance gate.
No production native-primitive fallback/replacement library was introduced.

## Implementation decisions

- Optional `appearance: null` remains compatible with gallery/internal callers.
  Main passes the existing sidebar appearance through the Widget area to cards.
  Idle fill is monitorFill; a header-only transient uses workspaceHoverFill.
  Without appearance, both formulas and `min(3, Style.cornerRadius)` match the
  existing sidebar. Expanded title is body/DemiBold; collapsed title is 85%
  foreground except while focus is inside the card.
- The body tint rectangle was removed. The 1-pixel divider uses foreground at
  7% alpha. WidgetKit body/state/tile surfaces are intentionally unchanged;
  FDM-998 owns their separate visual work.
- Header order is icon → title → grip → badge → collapse. The badge stays next
  to collapse independently of grip opacity. Only the grip glyph becomes
  invisible; its 22-pixel pointer target remains present and is not a Tab stop.
  Focus tracks the actual window focus item's ancestry, including body inputs,
  without moving focus. Drag threshold, event handlers and controller behavior
  remain unchanged. Collapse uses chevron-down at 0/180 degrees.
- The previously absent `assets/lucide/grip-vertical.svg` is the unchanged
  upstream Lucide asset, blob `2cbd8aa425950d822c2cf5d9e5b161bd05b5cb41`.
  Image-ready assertions prevent silently rendering a missing-icon fallback.
- Section labels, card icon and body use workspaceCardInset + Style.space(4).
  The pin shelf has a different existing outer inset; only its label offsets
  to the viewport's content origin. Pin cells/hit targets are not shifted.
  Header heights accommodate native label overshoot; default shelf height is
  unchanged. No split-scroll allocation or ownership change is included.

## Executable evidence and limitations

The card QML tests exercise production DockWidgetCard with the existing narrow
qs fixtures. They cover optional/live appearance, 0/1/99+ badges and long titles
at 240 px, hover/focus/drag visibility, actual input focus/editing, hidden-grip
press/move/release/cancel, arrow rotation, title double-click, key activation,
context-menu removal and a rendered top-border pixel under the focus fill.
The pixel test initially failed: the transient rectangle painted over the top
focus stroke. Insetting that fill by BorderSurface's content insets fixes it.

`tests/test_widget_chrome_qml.py` extracts the actual section header, PINNED
label, main-header Button and manager-routing methods into an isolated Qt test
host at run time. It executes 8 cases, including left/right translated geometry,
minimum/default/wide widths, plus tooltip/accessibility and keyboard/mouse/
disabled behavior, and main-header management with no Widget tail. It rejects
QWARN/QFATAL output. Its endpoint/Commons/Ui fixtures are not a full shell.
The normal QML suite and Python discovery include these checks in Headless CI.
The Button fixture was corrected to reflect the audited native press handlers;
Qt Quick Controls.Button's default Enter behavior is different.

A supplementary sandbox render used Xvfb/Mesa OpenGL to show tinted SVGs (the
Qt Quick software scenegraph does not render the existing ColorOverlay path).
The exact native PanelSectionHeader and native Button were also investigated
against this older Qt runtime with fixture Commons/BorderSurface dependencies.
Unmodified native Button produced an unqualified `Color` name collision with
QtQuick.Controls.impl/Color in Qt 6.4.2. A sandbox-only Commons namespace alias
resolved those warnings and the same 8 cases passed. That adapted render is
**diagnostic evidence, not an exact native/full-shell qualification**. Neither
the native source nor production SmartDock was modified to work around the
remote runtime. Recheck the unmodified primitive on the installed Qt/Quickshell
pair; do not infer support from this adaptation or from stubs.

## Required local continuation — FDM-1001

Status after a green remote handoff is **remote-complete / local-validation-required**.
FDM-1001 starts on the integrated accepted FDM-997/998/999 candidate, not by
reimplementing these source changes. Preserve FDM-995's separate drag acceptance.
Only one worker writes to the candidate branch at a time.

Still unrun here: isolated Quickshell standalone smoke, `omarchy plugin validate`,
Omarchy-aware lint/load, full-shell plugin mode, KVM screenshots on both edges,
real input/compositor grabs and tooltip placement, actual dark/light themes,
large native fonts, scales and animations on/off. The local owner must record
installed Omarchy SHA/package and Qt/Quickshell/Hyprland versions and qualify the
final exact integrated head. Any demonstrated fix requires new source tests,
exact-head CI and rerun native evidence. No automatic merge, deployment,
installed-plugin edit or production-desktop preview is authorized.
