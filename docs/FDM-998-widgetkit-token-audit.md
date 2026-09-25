# FDM-998 — WidgetKit token alignment audit

## Evidence boundary

FDM-998 aligns the public `SmartDock.WidgetKit 1.0` visuals with the sidebar
without removing or renaming public properties/signals/imports.

**Exact Omarchy source inspected:** `omacom/omarchy@28ceaae70ebac3a0edcc21f2faa77a90dc6d404c`.
The source `version` file reports `4.0.0.alpha`; the Git SHA is the audit
identity. FDM-997 separately recorded an installed `4.0.3-1` package, which is
not treated as source-equivalent evidence.

Remote source/headless work does not prove the user's installed full-shell
theme/font/compositor rendering. FDM-1001 retains that integrated native gate.

## Native token inventory at the inspected revision

`shell/Commons/Color.qml` exposes the foundational theme roles
`foreground`, `background`, `accent`, `urgent` and `muted`.
`Color.urgent` is populated from the theme red/color1 source and
`Color.muted` from the theme muted/color8 source. This exact revision does
**not** expose foundational `success` or `warning` properties.

`shell/Commons/Style.qml` exposes the live `cornerRadius` token plus
theme-driven spacing/font/control-state tokens.

Decision:

- WidgetKit `danger` maps directly to `Color.urgent`.
- Existing `success` and `warning` API values remain theme-derived HSL
  calculations in `WidgetSemanticPalette`; they are not replaced by invented
  native tokens.
- Rectangular nested Widget surfaces cap radius at
  `Math.min(3, Style.cornerRadius)`, matching the sidebar card contract.
- Pills/circles (badge/status/progress geometry) keep their deliberate shape.

This inventory is revision-specific and must not be generalized to future
Omarchy versions.

## Normal-text contrast audit

The requested source-level contrast check uses the exact production surface
formulas and exact theme colors from the inspected Omarchy revision.

Surfaces:

- monitor/card: `Qt.tint(Color.background, Util.alpha(Color.foreground, 0.035))`
- stat tile: foreground at 0.04 alpha composited over the monitor/card surface
- input: `Qt.darker(Color.background, 1.03)`

WCAG relative-luminance contrast is measured after alpha compositing. The
minimum required ratio for the in-scope normal text is **4.5:1**.

### Tokyo Night (dark)

Theme colors: background `#1a1b26`, foreground `#a9b1d6`, muted
`#414868`.

| Surface | Composited surface | Color.muted | Previous 0.62 foreground | Color.foreground |
| --- | --- | ---: | ---: | ---: |
| monitor/card | `#1f202c` | 1.80:1 | 3.81:1 (`#757a95`) | **7.63:1** |
| stat tile | `#252633` | 1.68:1 | 3.66:1 (`#777c98`) | **7.09:1** |
| input | `#191a25` | 1.93:1 | 3.95:1 (`#727893`) | **8.17:1** |

### Catppuccin Latte (light)

Theme colors: background `#eff1f5`, foreground `#4c4f69`, muted
`#acb0be`.

| Surface | Composited surface | Color.muted | Previous 0.62 foreground | Color.foreground |
| --- | --- | ---: | ---: | ---: |
| monitor/card | `#e9ebf0` | 1.82:1 | 2.85:1 (`#888a9c`) | **6.71:1** |
| stat tile | `#e3e5eb` | 1.72:1 | 2.78:1 (`#85889a`) | **6.34:1** |
| input | `#e8eaee` | 1.80:1 | 2.84:1 (`#878a9b`) | **6.63:1** |

Both `Color.muted` and the previous 0.62-alpha foreground fail the requested
normal-text contrast gate in both target themes. `Color.foreground` passes all
six samples. Therefore the Widget normal secondary/caption role keeps
`Color.muted` as its audited preferred sidebar token
(`WidgetSemanticPalette.mutedTextBase`) but uses one centralized documented
contrast exception, `WidgetSemanticPalette.mutedText = Color.foreground`.
Widget primitives consume that role instead of scattering opacity literals.

This exception applies to in-scope normal secondary/caption/placeholder text; it
does not reclassify decorative or disabled content.

## Demo semantic convention

The Display demo uses an `info` status with a neutral reference badge. Memory
is neutral below 85% and warning at 85% or above. This threshold is demo/gallery
presentation only; it is not a provider rule or a ban on genuine success,
warning, danger, error or urgent states.

## Compatibility and deferred work

- `SmartDock.WidgetKit 1.0` remains the import surface.
- `WidgetStatus.referenceSemantic` is additive; an empty value preserves the
  previous behavior of inheriting the status semantic.
- `WidgetSparkline` is unchanged. Area fill remains explicitly deferred.
- The existing external-package fixture remains unchanged and must pass the
  repository package/runtime tests against this updated kit.
- Full-shell installed-theme/font/contrast screenshots, real Quickshell plugin
  mode and compositor/input qualification remain FDM-1001 gates.
