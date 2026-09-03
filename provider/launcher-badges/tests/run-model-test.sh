#!/usr/bin/env bash
set -euo pipefail

provider_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cxx="${CXX:-c++}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

"$cxx" -std=c++20 -Wall -Wextra -Wpedantic \
  -I"$provider_root" \
  "$provider_root/tests/test_provider_model.cpp" \
  "$provider_root/LauncherBadgeModel.cpp" \
  -o "$tmp_dir/test-provider-model"
"$tmp_dir/test-provider-model"
