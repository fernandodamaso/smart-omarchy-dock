# SmartDock Widget component API

This is the coding-agent reference for the reusable SmartDock Widget UI kit in
`components/widgets/`. Read this after `docs/SIDEBAR_WIDGETS.md`: that document
owns provider registration, leases, snapshots, Widget-area layout, persistence and
failure isolation; this document owns **presentation component selection and API**.

The executable examples remain `tests/widget-gallery/WidgetGallery.qml` and the
four `components/widgets/DemoWidget*Body.qml` bodies. Prefer copying one of those
compositions over inventing parallel typography, controls, card chrome or state
surfaces.

## Usage rules

- A Widget body root stays an `Item` with non-required
  `property var widgetContext: ({})` and a finite `implicitHeight`.
- Widget bodies consume `widgetContext.data`; they do not acquire providers,
  subscribe, poll, write `sidebarWidgets`, or own card/popup lifecycle.
- `DockWidgetCard.qml` owns the card shell. Do not recreate its header, collapse,
  reorder or removal controls inside a Widget body.
- Render user/provider strings as plain text. The reusable text primitives already
  use `Text.PlainText`.
- Use the semantic vocabulary below instead of provider-supplied colors.
- Follow the sidebar surface-token contract: rectangular nested surfaces cap
  their radius at `Math.min(3, Style.cornerRadius)`; deliberately circular or
  pill-shaped indicators keep their geometry.
- Use hue for semantic state or attention, not as default decoration. Neutral
  content stays on neutral/sidebar roles; `danger` follows `Color.urgent`.
- Properties listed below are the SmartDock-owned API. Components that inherit a
  Qt Quick Control also retain the normal inherited Qt properties/signals noted in
  the table; inspect the component source before depending on less-common inherited
  behavior.
- Components under `components/` import the kit with `import "widgets"`.
  Components already under `components/widgets/` can reference sibling
  `Widget*` types directly.

## Shared value contracts

| Contract | Supported values | Notes |
| --- | --- | --- |
| semantic | `neutral`, `info`, `success`, `warning`, `danger` | Centralized by `WidgetSemanticPalette`. Unknown values fall back to neutral in palette consumers. |
| attention | `none`, `urgent`, `overdue` | `urgent` and `overdue` use danger treatment; `WidgetListItem` may animate unless `reducedMotion` is true. |
| button variant | `primary`, `secondary`, `ghost`, `danger` | Use `danger` only for destructive/error actions. |
| framework state | `loading`, `empty`, `unavailable`, `error`, `stale` | Render with `WidgetState`. |
| text role | `body`, `title`, `caption`, `label` | Controls SmartDock typography/weight. |
| icon size | `xs`, `sm`, `md`, `lg`, `xl` | Unrecognized values use the `md` glyph size. |
| icon container | `plain`, `soft`, `outlined`, `tile` | `plain` has no surrounding container. |
| validation state | `none`, `error` | Text input, text area and select currently give special treatment only to `error`. |

## Display and content primitives

### `WidgetText`

Theme-aware plain-text primitive. Inherits Qt `Text`, including `text`,
`horizontalAlignment` and related standard properties.

| Property | Type | Default | Purpose |
| --- | --- | --- | --- |
| `role` | string | `"body"` | `body | title | caption | label` typography. |
| `muted` | bool | `false` | Uses the centralized secondary-text role. The preferred sidebar token is `Color.muted`; see the FDM-998 contrast exception below. |
| `allowWrap` | bool | `true` | Wrap when true; single-line elide when false. |
| `maxLines` | int | `0` | `0` means effectively unlimited; positive values cap line count. |

### `WidgetBadge`

Compact semantic pill.

| Property | Type | Default |
| --- | --- | --- |
| `text` | string | `""` |
| `semantic` | string | `"neutral"` |
| `compact` | bool | `false` |

### `WidgetStatus`

Status dot + label, with an optional reference badge.

| Property | Type | Default |
| --- | --- | --- |
| `label` | string | `""` |
| `semantic` | string | `"neutral"` |
| `reference` | string | `""` |
| `referenceSemantic` | string | `""` |
| `compact` | bool | `true` |

When `referenceSemantic` is empty, the reference badge preserves the previous behavior and inherits `semantic`.

### `WidgetDivider`

One-pixel theme-aware separator. It has no SmartDock-specific properties; size it
with normal QML `width`/anchors.

### `WidgetSection`

Vertical section with optional title/subtitle and a default child slot.

| Property | Type | Default |
| --- | --- | --- |
| `title` | string | `""` |
| `subtitle` | string | `""` |
| default `content` | children | — |

### `WidgetList`

Simple vertical composition container. It does **not** own a model or scrolling;
use a `Repeater` when data-driven rows are needed.

| Property | Type | Default |
| --- | --- | --- |
| `itemSpacing` | int | `0` |
| default `content` | children | — |

### `WidgetListItem`

Standard Widget row with optional icon, secondary text, trailing text and reference.

| Property | Type | Default | Purpose |
| --- | --- | --- | --- |
| `iconName` | string | `""` | Lucide icon name. |
| `iconSource` | url | empty | Arbitrary SVG/raster source. |
| `preserveBrandIcon` | bool | `false` | Do not theme-tint supplied brand artwork. |
| `title` | string | `""` | Primary row text. |
| `subtitle` | string | `""` | Optional secondary text, max two lines. |
| `trailing` | string | `""` | Right-side text. |
| `attention` | string | `"none"` | `none | urgent | overdue`. |
| `reference` | string | `""` | Optional compact badge such as an issue ID. |
| `interactive` | bool | `false` | Enables pointer/keyboard activation. |
| `reducedMotion` | bool | `false` | Stops urgent/overdue nudge animation. |

Signal: `triggered()`.

### `WidgetChecklist`

Checklist rows backed by a simple array.

| Property | Type | Default |
| --- | --- | --- |
| `model` | array-like | `[]` |
| `reducedMotion` | bool | `false` |

Model entry:

```javascript
{
  title: "Task",
  detail: "Optional helper text",
  done: false,
  reference: "#123",
  attention: "urgent" // or "overdue" / omitted
}
```

Signal: `itemToggled(int index, bool checked)`.

`reducedMotion` is part of the component API for consistency; the current
checklist implementation itself has no animated child.

### `WidgetKeyValue`

Left label + right value row.

| Property | Type | Default |
| --- | --- | --- |
| `label` | string | `""` |
| `value` | string | `""` |
| `emphasized` | bool | `false` |

### `WidgetStat`

Small stat tile. Its nested rectangular surface uses the sidebar radius cap and
a foreground-at-4% fill with no independent border.

| Property | Type | Default |
| --- | --- | --- |
| `label` | string | `""` |
| `value` | string | `""` |
| `helper` | string | `""` |

### `WidgetStatGrid`

Grid of `WidgetStat` tiles.

| Property | Type | Default |
| --- | --- | --- |
| `model` | array-like | `[]` |
| `columnCount` | int | `2` |
| `gap` | int | `Style.space(6)` |

Model entry: `{ label, value, helper }`.

### `WidgetProgressBar`

Semantic progress bar. `value` is normalized/clamped to `0..1`.

| Property | Type | Default |
| --- | --- | --- |
| `value` | real | `0` |
| `semantic` | string | `"info"` |

### `WidgetMeter`

Label/value pair plus a `WidgetProgressBar`.

| Property | Type | Default |
| --- | --- | --- |
| `label` | string | `""` |
| `valueText` | string | `""` |
| `value` | real | `0` |
| `semantic` | string | `"info"` |

### `WidgetActivity`

Vertical activity/timeline list.

| Property | Type | Default |
| --- | --- | --- |
| `model` | array-like | `[]` |

Model entry:

```javascript
{ title: "Updated", detail: "Optional detail", semantic: "success" }
```

### `WidgetSparkline`

Small line chart for already-prepared numeric values.

| Property | Type | Default |
| --- | --- | --- |
| `values` | array-like | `[]` |
| `lineColor` | color | `Color.accent` |
| `lineWidth` | real | `2` |

At least two numeric values are required to draw a line. FDM-998 deliberately
does not add an area fill or `fillOpacity`; that visual feature remains deferred.

### `WidgetIconText`

Small icon + single-line text composition.

| Property | Type | Default |
| --- | --- | --- |
| `iconName` | string | `""` |
| `iconSource` | url | empty |
| `text` | string | `""` |
| `muted` | bool | `false` |
| `preserveBrand` | bool | `false` |

## Icon primitive

### `WidgetIcon`

The single flexible Widget icon renderer. Prefer this over direct Lucide/Image
composition inside Widget bodies.

| Property | Type | Default | Purpose |
| --- | --- | --- | --- |
| `iconName` | string | `""` | Lucide name resolved from `assets/lucide/`. |
| `source` | url | empty | Arbitrary SVG/raster source; takes precedence when present. |
| `preserveBrand` | bool | `false` | Preserve source artwork colors. |
| `themeTinted` | bool | `!preserveBrand` | Apply `tint` through the theme overlay. |
| `sizeToken` | string | `"md"` | `xs | sm | md | lg | xl`. |
| `containerVariant` | string | `"plain"` | `plain | soft | outlined | tile`. |
| `tint` | color | `Color.foreground` | Theme tint when enabled. |
| `accessibleName` | string | `""` | Accessible label. |
| `fallbackText` | string | `"?"` | Shown when the source cannot load. |

Read-only state useful for diagnostics/composition: `glyphSize`,
`containerSize`, `usesLucide`, `resolvedSource`, `failed`, `ready`.

## Form and input primitives

### `WidgetFormField`

Label/helper/error wrapper with a default child slot.

| Property | Type | Default |
| --- | --- | --- |
| `label` | string | `""` |
| `helperText` | string | `""` |
| `errorText` | string | `""` |
| `requiredField` | bool | `false` |
| default `content` | child control | — |

When `errorText` is non-empty it replaces helper text and uses the danger tone.

### `WidgetTextInput`

Styled `Controls.TextField`. Its rectangular background uses the sidebar radius
cap. Standard inherited properties/signals include
`text`, `placeholderText`, `editingFinished`, `accepted`, `enabled` and
focus behavior.

| Property | Type | Default |
| --- | --- | --- |
| `validationState` | string | `"none"` |
| `accessibleName` | string | `placeholderText` |

### `WidgetSearchInput`

`WidgetTextInput` with a leading search icon.

| Property | Type | Default |
| --- | --- | --- |
| `searchIconName` | string | `"search"` |

It inherits all `WidgetTextInput` and `TextField` API.

### `WidgetTextArea`

Styled `Controls.TextArea`. Standard inherited properties/signals include
`text`, `placeholderText`, cursor/selection and focus behavior.

| Property | Type | Default |
| --- | --- | --- |
| `validationState` | string | `"none"` |
| `accessibleName` | string | `placeholderText` |

### `WidgetNumberInput`

Numeric `WidgetTextInput`. Editing commits into `numericValue`; Up/Down nudges
by `step` and the result is clamped.

| Property | Type | Default |
| --- | --- | --- |
| `minimum` | real | `-999999` |
| `maximum` | real | `999999` |
| `step` | real | `1` |
| `numericValue` | real | `0` |

### `WidgetSelect`

Styled `Controls.ComboBox`. Use normal inherited ComboBox API such as `model`,
`currentIndex`, `currentValue`, `currentText` and activation signals.

| Property | Type | Default |
| --- | --- | --- |
| `accessibleName` | string | `""` |
| `validationState` | string | `"none"` |

### `WidgetCheckbox`

Keyboard-accessible `Controls.AbstractButton` configured as checkable. Use
inherited `text`, `checked`, `toggled`, `clicked`, and `enabled`.

| Property | Type | Default |
| --- | --- | --- |
| `accessibleName` | string | `text` |

Return, Enter and Space toggle it.

### `WidgetToggle`

Switch-style checkable `Controls.AbstractButton`. Use inherited `text`,
`checked`, `toggled`, `clicked`, and `enabled`.

| Property | Type | Default |
| --- | --- | --- |
| `accessibleName` | string | `text` |

Return, Enter and Space toggle it.

### `WidgetRadioGroup`

Vertical single-selection group.

| Property | Type | Default |
| --- | --- | --- |
| `model` | array-like | `[]` |
| `selectedValue` | var | `""` |
| `requiredSingleSelect` | bool | `true` |
| `accessibleName` | string | `"Options"` |

Model entries may be primitives or `{ label, value }` objects. With
`requiredSingleSelect: true`, an invalid/missing selection normalizes to the
first model entry.

Signal: `selectionChanged(var value)`.

### `WidgetSegmentedControl`

Horizontal equal-width single-selection group.

| Property | Type | Default |
| --- | --- | --- |
| `model` | array-like | `[]` |
| `selectedValue` | var | `""` |
| `requiredSingleSelect` | bool | `true` |
| `accessibleName` | string | `"View"` |
| `gap` | int | `Style.space(3)` |

Model entries and normalization follow `WidgetRadioGroup`.

Signal: `selectionChanged(var value)`.

## Action primitives

### `WidgetButton`

Styled `Controls.AbstractButton`. Use inherited `text`, `clicked`,
`enabled`, `down`, `hovered` and focus behavior.

| Property | Type | Default |
| --- | --- | --- |
| `variant` | string | `"secondary"` |
| `iconName` | string | `""` |
| `iconSource` | url | empty |
| `preserveBrandIcon` | bool | `false` |
| `accessibleName` | string | `text` |

Read-only `visualState` is one of `disabled | pressed | focus | hover | idle`.

### `WidgetIconButton`

Square icon-only `WidgetButton`.

| Property | Type | Default |
| --- | --- | --- |
| `tooltipText` | string | `accessibleName` |

It inherits `iconName`, `iconSource`, `variant`, `accessibleName`,
`clicked`, `enabled`, etc. The component currently exposes `tooltipText` as
metadata; it does not create a tooltip surface itself.

### `WidgetButtonGroup`

Default child container for actions. It wraps buttons to available width and
centers each wrapped row.

| Property | Type | Default |
| --- | --- | --- |
| `gap` | int | `Style.space(5)` |
| default `content` | child controls | — |

## Framework state

### `WidgetState`

Standard loading/empty/unavailable/error/stale state surface.

| Property | Type | Default | Purpose |
| --- | --- | --- | --- |
| `kind` | string | `"empty"` | `loading | empty | unavailable | error | stale`. |
| `title` | string | `""` | Override the built-in title. |
| `message` | string | `""` | Optional detail. |
| `reducedMotion` | bool | `false` | Stops loading rotation. |
| `compact` | bool | `false` | Uses compact sizing. |
| `actionText` | string | `""` | Shows an action button when non-empty. |
| `verticalPadding` | int | `-1` | `-1` uses the component default; otherwise total vertical inset. |

Signal: `actionTriggered()`.

## Framework support component

### `WidgetSemanticPalette`

Central theme-aware semantic palette used by the primitives. Most Widget bodies
should pass semantic names to the public components instead of instantiating this
directly.

It exposes read-only `danger`, `warning`, `success`, `info`, `neutral`,
`mutedTextBase`, and `mutedText` colors plus the helper `tone(semantic)`. At the Omarchy revision audited by
FDM-998, `danger` maps directly to `Color.urgent`; `warning` and `success`
retain their existing background-aware HSL implementation because that exact
revision has no foundational warning/success token.

Secondary normal text is centralized here as well. `mutedTextBase` follows the
sidebar-preferred `Color.muted` token. The audited Tokyo Night and Catppuccin
Latte normal-text samples did not reach the required 4.5:1 contrast with either
`Color.muted` or the previous 0.62-alpha foreground, so `mutedText` uses
`Color.foreground` as the documented passing fallback. Do not reintroduce
scattered muted-alpha literals. Exact colors, composited surfaces and ratios are
recorded in [the FDM-998 token audit](FDM-998-widgetkit-token-audit.md).

## Recommended composition

A new expanded body should stay thin and bind snapshot data into the kit:

```qml
import QtQuick
import qs.Commons
import "widgets"

Item {
  id: root
  property var widgetContext: ({})
  readonly property var data: widgetContext && widgetContext.data
    ? widgetContext.data : ({})
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: parent.width
    spacing: Style.space(7)

    WidgetStatus {
      label: root.data.status || "Unknown"
      semantic: root.data.ok === true ? "success" : "warning"
    }

    WidgetList {
      width: parent.width
      Repeater {
        model: root.data.rows || []
        delegate: WidgetListItem {
          required property var modelData
          width: parent ? parent.width : 0
          title: String(modelData.title || "")
          subtitle: String(modelData.subtitle || "")
        }
      }
    }

    WidgetButton {
      text: "Details"
      variant: "secondary"
      onClicked: if (root.widgetContext && root.widgetContext.openPopup)
        root.widgetContext.openPopup()
    }
  }
}
```

If the view needs a provider action, call an explicit method exposed through
`widgetContext.provider`; do not create a second provider/subscription inside the
view.

## Coding-agent checklist for a custom Widget

1. Keep custom Widget source in a **separate directory/repository**. Do not add it
   to SmartDock core or an installed Omarchy SmartDock plugin checkout.
2. Read `docs/WIDGET_PACKAGES.md` and create the package with
   `smartdock widget create <stable-id>`.
3. Import `SmartDock.WidgetKit 1.0` and choose existing `Widget*` primitives
   before writing custom presentation controls.
4. Keep `widgetContext` non-required and tolerate `({})` / missing data.
5. Install the explicit source with `smartdock widget install <source>`, then use
   `smartdock widget dev use <source>` and `smartdock widget dev reload` while
   developing. `dev reset` returns to the installed snapshot without deleting
   developer source.
6. Keep `dock.json` ID-only. Do not add QML paths, commands, URLs, provider
   lifecycle, settings writers, card chrome, or popup ownership to configuration.
7. Add package-specific tests in the package repository and validate the package
   through the CLI before enabling its ID.

When work is intentionally a **SmartDock source-owned integration** rather than a
custom package, follow `AGENTS.md` and this repository's normal branch/worktree
workflow. Source-owned integrations may register a descriptor directly in
`DockHost.sidebarWidgetRegistry`; that is not the workflow for external custom
Widgets.

## External package import surface

Widget package API v1 exposes this kit to separately owned external packages as
a versioned QML module:

```qml
import SmartDock.WidgetKit 1.0
```

External packages should compose the exported `Widget*` primitives rather than
importing SmartDock implementation files by relative path. The module is shipped
with standalone SmartDock installations and is resolved by the host when an
external package entry is loaded. Package manifests, source/deployment
boundaries, and CLI workflow are documented in `docs/WIDGET_PACKAGES.md`.
