# SmartDock Widget gallery

This directory is the source-owned boilerplate for future SmartDock Widget bodies.

- `../../components/widgets/` contains the reusable body primitives, forms,
  actions, icon renderer and framework state surface.
- [`../WIDGET_COMPONENTS.md`](../WIDGET_COMPONENTS.md) is the coding-agent API
  reference for those primitives, including properties, signals, value contracts
  and model shapes.
- `../../components/DockWidgetCard.qml` remains the framework-owned card shell.
- `../../tests/widget-gallery/WidgetGallery.qml` is the executable synthetic-data
  gallery used by tests and coding agents.
- [`reference/approved-widget-mockup.html`](reference/approved-widget-mockup.html)
  is the preserved approved SmartDock `preview(2).html` visual contract (111,267 bytes).
- [`reference/sidebar-redesign-2026-09-23/`](reference/sidebar-redesign-2026-09-23/README.md)
  is the FDM-996 card-polish and split-scroll redesign reference (static HTML plus
  the design-canvas sources).

Do not copy provider lifecycle, settings writes or card chrome into a Widget body.
Start from a gallery composition and bind only view-safe `widgetContext` data.
