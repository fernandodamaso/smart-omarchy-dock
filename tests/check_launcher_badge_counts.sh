#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'check_launcher_badge_counts: %s\n' "$*" >&2
  exit 1
}

model=components/DockBadgeModel.js
tracker=components/DockBadgeTracker.qml
service=components/DockLauncherBadgeService.qml
herdr_service=components/DockHerdrBadgeService.qml
badge=components/DockApplicationBadge.qml
provider=provider/launcher-badges/LauncherBadgeProvider.cpp
provider_main=provider/launcher-badges/main.cpp

for path in \
  "$model" "$tracker" "$service" "$herdr_service" "$badge" Service.qml \
  provider/launcher-badges/LauncherBadgeModel.h \
  provider/launcher-badges/LauncherBadgeModel.cpp \
  provider/launcher-badges/LauncherBadgeProvider.h \
  "$provider" provider/launcher-badges/main.cpp \
  provider/launcher-badges/CMakeLists.txt \
  tests/test_launcher_badge_model.mjs tests/tst_launcherbadgemodel.qml; do
  [[ -f "$path" ]] || fail "missing $path"
done

lock_line="$(grep -n 'QLockFile lock' "$provider_main" | cut -d: -f1 || true)"
mkdir_line="$(grep -n 'mkpath' "$provider_main" | head -1 | cut -d: -f1 || true)"
[[ -n "$lock_line" && -n "$mkdir_line" && "$mkdir_line" -lt "$lock_line" ]] \
  || fail 'provider must create the state directory before acquiring its lock'

for fixture in initial partial hide clear reconnect malformed unknown; do
  [[ -f "provider/launcher-badges/fixtures/$fixture.json" ]] \
    || fail "missing provider fixture: $fixture"
done

service_owners="$(grep -R -F 'DockLauncherBadgeService {' Service.qml components \
  --include='*.qml' | wc -l | tr -d ' ')"
[[ "$service_owners" == "1" ]] \
  || fail "expected exactly one launcher badge service owner, found $service_owners"
grep -Fq '"service"' manifest.json \
  || fail 'manifest service kind missing'
grep -Fq '"service": "Service.qml"' manifest.json \
  || fail 'manifest service entry point missing'
grep -Fq 'shell.serviceFor("io.github.fernandodamaso.smartdock")' Overlay.qml \
  || fail 'overlay must consume the host-owned SmartDock service'
grep -Fq 'launcherBadgeService: root.launcherBadgeService' DockHost.qml \
  || fail 'DockHost must inject one provider service into the shared tracker'
if grep -Fq 'DockLauncherBadgeService' shell.qml; then
  fail 'standalone shell must remain provider-null and fall back to FDM-809 dots'
fi

grep -Fq '"launcherBadgeMode": "automatic"' config/dock.json \
  || fail 'automatic count mode config default missing'
grep -Fq 'launcherBadgeMode: "automatic"' DockHost.qml \
  || fail 'automatic count mode host fallback missing'
grep -q 'function normalizeLauncherIdentity' "$model" \
  || fail 'launcher URI/desktop-id normalization missing'
grep -q 'function launcherCountState' "$model" \
  || fail 'provider-neutral launcher count state missing'
grep -q 'function applicationBadgePresentation' "$model" \
  || fail 'count/dot precedence model missing'
grep -q 'function applicationBadgeToken' "$model" \
  || fail 'shared badge rendering token missing'
grep -q 'function herdrBadgeState' "$model" \
  || fail 'Herdr badge state reduction missing'
grep -Fq 'var count = counts.blocked + counts.done' "$model" \
  || fail 'Herdr badges must count only blocked and unseen done agents'
grep -Fq 'launcherCountFor(desktopId)' "$tracker" \
  || fail 'shared tracker count lookup missing'
grep -Fq 'applicationBadgeToken(' "$tracker" \
  || fail 'shared tracker must combine authoritative count and FDM-809 severity'
grep -Fq 'herdrBadgeStateFor' "$tracker" Service.qml \
  || fail 'Herdr badge count wiring missing'
grep -Fq 'herdrBadgeSeverityFor' "$tracker" Service.qml \
  || fail 'Herdr badge severity wiring missing'
grep -Fq 'DockHerdrBadgeService {' Service.qml \
  || fail 'Omarchy service must own one Herdr badge adapter'
grep -Fq 'clearMatchingNotifications' "$tracker" \
  || fail 'FDM-809 local focus clear missing'
if grep -A12 -F 'function clearFocusedLocal()' "$tracker" | grep -Fq 'launcherBadge'; then
  fail 'focus must not clear authoritative provider counts'
fi

grep -Fq 'root.count > 99 ? "99+"' "$badge" \
  || fail '99+ rendering cap missing'
grep -Fq 'color: urgent ? Color.urgent : Color.accent' "$badge" \
  || fail 'urgent count styling missing'
if grep -Eq '(Animation|Behavior)[[:space:]]' "$badge"; then
  fail 'badge motion belongs to FDM-814'
fi

grep -Fq 'com.canonical.Unity.LauncherEntry' "$provider" \
  || fail 'Unity LauncherEntry typed provider missing'
grep -Fq '#include <QDBusMessage>' "$provider" \
  || fail 'provider must directly include QDBusMessage for message().service()'
grep -Fq 'QDBusServiceWatcher' provider/launcher-badges/LauncherBadgeProvider.h \
  || fail 'sender disconnect reconciliation missing'
grep -Fq 'QSaveFile' "$provider" \
  || fail 'provider snapshot must be atomic'
grep -Fq 'QLockFile' provider/launcher-badges/main.cpp \
  || fail 'provider process single-owner lock missing'
grep -Fq 'herdr", "agent", "list' "$herdr_service" \
  || fail 'Herdr adapter must consume the local agent list contract'
grep -Fq 'com.mitchellh.ghostty' "$herdr_service" \
  || fail 'Herdr adapter must target the Ghostty desktop entry'

if grep -REiq 'dbus-monitor|gdbus[[:space:]].*monitor|while[[:space:]]+true' \
    components/DockLauncherBadgeService.qml components/DockHerdrBadgeService.qml \
    provider/launcher-badges scripts/build-launcher-badge-provider; then
  fail 'polling or long-running text parser detected'
fi
if grep -Fq 'StdioCollector' "$service"; then
  fail 'QML provider adapter must not parse a long-running stdout stream'
fi
if grep -Eiq 'notification.*(count|total)|unread.*notification' \
    "$provider" provider/launcher-badges/LauncherBadgeModel.cpp; then
  fail 'notification events must never manufacture launcher counts'
fi
if grep -Eiq 'accessibility|window[ _-]*title|sqlite|database' \
    "$provider" provider/launcher-badges/LauncherBadgeModel.cpp; then
  fail 'launcher counts must not scrape accessibility, titles, or app databases'
fi

echo 'check_launcher_badge_counts: PASS'
