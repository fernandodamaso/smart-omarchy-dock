#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
settings_qml="$plugin_root/components/DockSettings.qml"
context_menu_qml="$plugin_root/components/DockContextMenu.qml"

if ! rg -n '^PanelWindow \{' "$settings_qml" >/dev/null; then
  printf 'DockSettings must use a full-monitor panel surface\n' >&2
  exit 1
fi

if ! rg -n 'WlrLayershell\.keyboardFocus' "$settings_qml" >/dev/null; then
  printf 'DockSettings must explicitly own keyboard focus while open\n' >&2
  exit 1
fi

if rg -n 'HyprlandFocusGrab|grabFocus:' "$settings_qml" >/dev/null; then
  printf 'DockSettings must not depend on an xdg-popup focus grab\n' >&2
  exit 1
fi

if ! rg -n 'mask: Region' "$settings_qml" >/dev/null; then
  printf 'DockSettings must define a pointer input mask\n' >&2
  exit 1
fi

if ! rg -n 'dockHitThickness|pointerDismissRegion' "$settings_qml" >/dev/null; then
  printf 'DockSettings must leave the dock hit area available for hover effects\n' >&2
  exit 1
fi

if ! rg -n 'focusPrimed|WlrKeyboardFocus\.OnDemand' "$settings_qml" >/dev/null; then
  printf 'DockSettings must release compositor-wide pointer routing after focus prime\n' >&2
  exit 1
fi

if ! rg -U -n 'root\.dismiss\(\)\s*\n\s*Qt\.callLater\(\(\) => root\.openSettings\(\)\)' \
    "$context_menu_qml" >/dev/null; then
  printf 'Dock Settings must open after the context menu dismisses\n' >&2
  exit 1
fi
