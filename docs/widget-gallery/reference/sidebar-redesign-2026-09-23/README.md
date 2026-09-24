# Sidebar Widgets redesign reference (2026-09-23)

Visual reference for the Linear plan **FDM-996** and its slices FDM-997
(WIDGET-05), FDM-998 (WIDGET-06), FDM-999 (WIDGET-07), FDM-1000 (WIDGET-08)
and FDM-1001 (WIDGET-09). The execution plan is
[`docs/plans/2026-09-23-sidebar-widget-split-scroll.md`](../../../plans/2026-09-23-sidebar-widget-split-scroll.md).

This is a mockup, not a pixel contract. Its hex colors were sampled from a
Tokyo Night screenshot. The QML implementation must use Omarchy `qs.Commons`
tokens and the sidebar `appearance` values named in the plan.

| File | Board | What it shows |
|---|---|---|
| `index.html` | all | The three boards side by side, plus the canvas notes. Open it in a browser. |
| `Current.html` | Current | A recreation of the shipped sidebar (before). |
| `Main.html` | Proposed | Card and section styling from WIDGET-05/06. |
| `Split.html` | Proposed · split scroll | The WIDGET-07 layout, with the monitors part capped and the Widgets scrolling on their own. |
| `source/*.dc.html`, `source/canvas.json` | | The exact design-canvas sources. They include the interactive behavior: collapse, the hover grip, the draggable split (WIDGET-08), and Tweaks for accent, memory and many windows. |

The `*.html` files are static renders of each source's default state.
Interactive behavior (collapse, draggable split, Tweaks) exists only in the
sources. The sources need the design-canvas runtime (`support.js`), so the
static renders are the ones to open in a plain browser.

Canonical canvas: <https://claude.ai/artifact/YC9jCxfufqhtYxYDFzGpnS>. It is
private to its owner.
