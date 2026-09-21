#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'check_herdr_data_access: %s\n' "$*" >&2; exit 1; }
helper=provider/herdr/bin/smartdock-herdr-helper
for file in "$helper" provider/herdr/UPSTREAM.md provider/herdr/LICENSE.omaherdr \
  provider/herdr/tests/test_events.py provider/herdr/tests/test_protocol.py \
  docs/HERDR_DATA_ACCESS.md; do
  [[ -f "$file" ]] || fail "missing $file"
done
[[ -x "$helper" ]] || fail 'helper must be executable'
[[ "$(git hash-object provider/herdr/LICENSE.omaherdr)" == d645695673349e3947e8e5ae42332d0ac3164cd7 ]] \
  || fail 'upstream license text changed'
grep -Fq 'c20d9b0db3a65b5a7590876c56026bc906306e04' provider/herdr/UPSTREAM.md \
  || fail 'pinned provenance missing'
grep -Fq 'SPDX-License-Identifier: Apache-2.0' "$helper" || fail 'derived-code notice missing'
grep -Fq "discover -s provider/herdr/tests" .github/workflows/ci.yml \
  || fail 'nested transport suite is missing from CI'
if grep -Eq 'subprocess|execDetached|org\.omarchy\.Omaherdr|omaherdr-notify' "$helper"; then
  fail 'transport must not acquire an omaherdr or subprocess dependency'
fi
# Step-1 boundary: source extraction must not activate a provider on import.
# Replace this guard with tested demand-driven ownership when step 3 wires it.
for file in Service.qml Overlay.qml DockHost.qml shell.qml; do
  [[ -f "$file" ]] || continue
  if grep -Eq 'smartdock-herdr-helper|DockHerdrService[[:space:]]*\{' "$file"; then
    fail 'step-1 scaffold must not add runtime activation'
  fi
done
printf 'check_herdr_data_access: PASS\n'
