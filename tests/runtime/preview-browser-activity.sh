#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
harness_qml="$repo_root/tests/runtime/browser-activity-preview.qml"

if [[ "${1:-}" == "--check" ]]; then
  if rg -q '^[[:space:]]*FloatingWindow[[:space:]]*\{' "$harness_qml" \
    && rg -q 'title:[[:space:]]*"SmartDock Browser Activity Preview Harness"' "$harness_qml" \
    && rg -q '^[[:space:]]*desktopId:[[:space:]]*""[[:space:]]*$' "$harness_qml" \
    && ! rg -q 'preview\.desktopId[[:space:]]*=' "$harness_qml" \
    && rg -q 'anchorWindow\.contentItem\.Window\.window' "$harness_qml" \
    && rg -q 'function onFrameSwapped\(\)' "$harness_qml" \
    && rg -q 'previewShown \|\| !previewStaged \|\| !parentFrameSwapped' "$harness_qml" \
    && rg -q 'anchorSize \+ preview\.popupGap \+ preview\.implicitWidth' "$harness_qml" \
    && rg -q 'anchorSize \+ preview\.popupGap \+ preview\.implicitHeight' "$harness_qml" \
    && ! rg -q 'backingWindowVisible|DIAGNOSTIC|diagnosticTimer' "$harness_qml" \
    && rg -q 'onClosed:[[:space:]]*Qt\.quit\(\)' "$harness_qml"; then
    echo "browser activity preview harness check: PASS"
    exit 0
  fi
  echo "browser activity preview harness check: FAIL" >&2
  exit 1
fi

state="${1:-default}"
position="${2:-bottom}"

case "$state" in
  default|one-window|no-activity|overflow) ;;
  *)
    echo "usage: $0 [default|one-window|no-activity|overflow] [bottom|top|left|right]" >&2
    exit 2
    ;;
esac

case "$position" in
  bottom|top|left|right) ;;
  *)
    echo "usage: $0 [default|one-window|no-activity|overflow] [bottom|top|left|right]" >&2
    exit 2
    ;;
esac

test_dir="$(mktemp -d -t smartdock-browser-activity.XXXXXX)"
trap 'rm -rf -- "$test_dir"' EXIT
cp -R "$repo_root/components" "$test_dir/components"
mkdir "$test_dir/assets"
ln -s "$repo_root/assets/services" "$test_dir/assets/services"
ln -s "$repo_root/assets/lucide" "$test_dir/assets/lucide"
ln -s "$repo_root/tests/runtime/assets/chat-preview.svg" "$test_dir/assets/chat-preview.svg"
ln -s "$repo_root/tests/runtime/assets/themes-preview.svg" "$test_dir/assets/themes-preview.svg"
cp "$harness_qml" "$test_dir/shell.qml"
mkdir "$test_dir/imports"
ln -s "${OMARCHY_PATH:-/usr/share/omarchy}/shell" "$test_dir/imports/qs"
SMARTDOCK_PREVIEW_STATE="$state" SMARTDOCK_PREVIEW_POSITION="$position" \
  QT_QPA_PLATFORM=wayland QML2_IMPORT_PATH="$test_dir/imports" \
  qs -p "$test_dir" --no-color
