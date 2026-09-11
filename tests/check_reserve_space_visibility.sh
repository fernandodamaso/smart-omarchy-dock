#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
model="$script_dir/../components/DockModel.js"
dock="$script_dir/../components/Dock.qml"

grep -Eq 'return Boolean\(reserveSpace\) && !Boolean\(autoHide\)' "$model" \
  || { echo "Reserved space must be disabled while auto-hide is enabled" >&2; exit 1; }
grep -Fq 'DockModel.shouldReserveSpace(' "$dock" \
  || { echo "Dock must project reserve-space through its live auto-hide state" >&2; exit 1; }
grep -Eq 'exclusionMode: reserveSpace \? ExclusionMode\.Normal : ExclusionMode\.Ignore' "$dock" \
  || { echo "Dock exclusion mode is not driven by the corrected reserve-space state" >&2; exit 1; }

echo "Reserve space follows visible (non-auto-hidden) dock state"
