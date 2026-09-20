# SmartDock Widget gallery

This directory is the source-owned boilerplate for future SmartDock Widget bodies.

- `../../components/widgets/` contains the reusable body primitives, forms,
  actions, icon renderer and framework state surface.
- `../../components/DockWidgetCard.qml` remains the framework-owned card shell.
- `../../tests/widget-gallery/WidgetGallery.qml` is the executable synthetic-data
  gallery used by tests and coding agents.
- [`reference/approved-widget-mockup.html`](reference/approved-widget-mockup.html)
  is the preserved approved HTML visual contract (111,267 bytes).

Do not copy provider lifecycle, settings writes or card chrome into a Widget body.
Start from a gallery composition and bind only view-safe `widgetContext` data.
