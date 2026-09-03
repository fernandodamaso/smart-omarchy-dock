#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$script_dir/.."
settings="$plugin_dir/components/DockSettings.qml"
swatch="$plugin_dir/components/DockColorSwatch.qml"
token_picker="$plugin_dir/components/DockColorTokenDropdown.qml"

test -s "$swatch" \
  || { echo "Missing reusable DockColorSwatch component" >&2; exit 1; }
test -s "$token_picker" \
  || { echo "Missing themed DockColorTokenDropdown component" >&2; exit 1; }
grep -Eq '^import QtQuick\.Dialogs[[:space:]]*$' "$settings" \
  || { echo "Dock Settings must use QtQuick.Dialogs for color picking" >&2; exit 1; }
grep -Eq '^[[:space:]]*ColorDialog \{' "$settings" \
  || { echo "Dock Settings is missing its color dialog" >&2; exit 1; }
grep -Eq 'options: ColorDialog\.ShowAlphaChannel' "$settings" \
  || { echo "Color picker must preserve alpha-capable color settings" >&2; exit 1; }
grep -Eq 'ColorDialog\.DontUseNativeDialog' "$settings" \
  || { echo "Color picker must avoid a native dialog window below the overlay" >&2; exit 1; }
grep -Eq 'onAccepted: root\.commitColorValue\(' "$settings" \
  || { echo "Color dialog is not wired to commit picked colors" >&2; exit 1; }
grep -Eq 'parentWindow: root\.QsWindow\.contentItem' "$settings" \
  || { echo "Color dialog must stay attached to the Dock Settings overlay window" >&2; exit 1; }
grep -Eq 'popupType: QQC\.Popup\.Item' "$settings" \
  || { echo "Color dialog must render above the settings card inside the overlay" >&2; exit 1; }
grep -Eq 'id: settingsCard[[:space:]]*$' "$settings" \
  || { echo "Dock Settings card anchor is missing" >&2; exit 1; }
grep -Eq '^[[:space:]]*z: 0[[:space:]]*$' "$settings" \
  || { echo "Dock Settings card must not outrank the in-window color dialog overlay" >&2; exit 1; }
grep -Eq 'DockColorSwatch \{' "$settings" \
  || { echo "Dock Settings is missing color swatches" >&2; exit 1; }
grep -Eq 'property color fallbackColor' "$swatch" \
  || { echo "Color swatches must fall back to the active theme" >&2; exit 1; }
grep -Eq 'Border\.controlSpec' "$swatch" \
  || { echo "Color swatches must use themed borders" >&2; exit 1; }
grep -Eq 'openColorPicker\("backgroundColor"\)' "$settings" \
  || { echo "Background color swatch is not wired" >&2; exit 1; }
grep -Eq 'openColorPicker\("borderColor"\)' "$settings" \
  || { echo "Border color swatch is not wired" >&2; exit 1; }
grep -Eq 'openColorPicker\("workspaceBadgeBackgroundColor"\)' "$settings" \
  || { echo "Workspace badge background color swatch is not wired" >&2; exit 1; }
grep -Eq 'openColorPicker\("workspaceBadgeTextColor"\)' "$settings" \
  || { echo "Workspace badge text color swatch is not wired" >&2; exit 1; }
grep -Eq 'themeColorOptions' "$settings" \
  || { echo "Dock Settings is missing its Omarchy theme token options" >&2; exit 1; }
grep -Eq 'DockColorTokenDropdown \{' "$settings" \
  || { echo "Dock Settings is missing themed token selectors" >&2; exit 1; }
grep -Eq '@accent' "$settings" \
  || { echo "Dock Settings token selector must expose the accent token" >&2; exit 1; }
grep -Eq '@menu\.background' "$settings" \
  || { echo "Dock Settings token selector must expose a menu surface token" >&2; exit 1; }
grep -Eq 'colorForSetting' "$settings" \
  || { echo "Dock Settings must resolve symbolic token values for previews" >&2; exit 1; }
grep -Eq 'displayColor' "$swatch" \
  || { echo "Color swatches must render resolved symbolic token colors" >&2; exit 1; }
grep -Eq 'optionColor|colorForOption' "$token_picker" \
  || { echo "Theme token selector must resolve option colors" >&2; exit 1; }
grep -Eq 'Rectangle \{' "$token_picker" \
  || { echo "Theme token selector must render color squares" >&2; exit 1; }

echo "Dock color pickers are wired for dock surface and workspace badge colors"
