#!/usr/bin/env bash
# Guest-only preview qualification. Run via:
#   ./scripts/dev-session exec NAME -- \
#     /home/admin/smartdock-candidate/tests/runtime/workspace-drag-preview/qualify-guest.sh
set -euo pipefail

[[ -n "${SMARTDOCK_SESSION_NAME:-}" ]] || {
  echo "SMARTDOCK_SESSION_NAME is required" >&2
  exit 1
}

candidate="${SMARTDOCK_CANDIDATE:-/home/admin/smartdock-candidate}"
ready="${XDG_STATE_HOME:-$HOME/.local/state}/smartdock/dev-sessions/${SMARTDOCK_SESSION_NAME}/ready.json"
evidence="${XDG_STATE_HOME:-$HOME/.local/state}/smartdock/dev-sessions/${SMARTDOCK_SESSION_NAME}/evidence"
control="$candidate/tests/runtime/dev-session/guest-control.sh"
preview_run="$candidate/tests/runtime/workspace-drag-preview/run"

export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/smartdock-omarchy-test}"
export WAYLAND_DISPLAY
export HYPRLAND_INSTANCE_SIGNATURE
export XDG_RUNTIME_DIR

WAYLAND_DISPLAY=$(python3 -c "import json; print(json.load(open('$ready'))['wayland_display'])")
HYPRLAND_INSTANCE_SIGNATURE=$(python3 -c "import json; print(json.load(open('$ready'))['hyprland_instance_signature'])")
XDG_RUNTIME_DIR=$(python3 -c "import json; print(json.load(open('$ready')).get('xdg_runtime_dir') or '/run/user/1000')")

mkdir -p "$evidence"
"$control" stop-dock || true
"$preview_run" stop || true
"$preview_run" start
"$preview_run" status
sleep 1.2
grim -o Virtual-1 "$evidence/simulated-monitors-baseline.png"

# Optional single in-guest pointer exercise (never loop from the host).
if command -v ydotool >/dev/null && command -v sudo >/dev/null; then
  export YDOTOOL_SOCKET="${XDG_RUNTIME_DIR}/.ydotool_socket"
  sudo pkill ydotoold 2>/dev/null || true
  sudo ydotoold -p "$YDOTOOL_SOCKET" >/tmp/ydotoold-preview.log 2>&1 &
  sleep 0.5
  sudo chmod 666 "$YDOTOOL_SOCKET" 2>/dev/null || true
  # Relative nudge only — absolute coords are unreliable under pointer accel.
  ydotool mousemove -x 20 -y -40 || true
  grim -o Virtual-1 "$evidence/simulated-monitors-after-nudge.png" || true
  sudo pkill ydotoold 2>/dev/null || true
fi

python3 - <<PY
import json, hashlib, os
from pathlib import Path
evidence = Path(os.environ.get("EVIDENCE", "$evidence"))
files = sorted(evidence.glob("simulated-monitors-*.png"))
payload = {
  "session": os.environ["SMARTDOCK_SESSION_NAME"],
  "label": "simulated-monitor-evidence",
  "frames": [
    {
      "name": path.name,
      "bytes": path.stat().st_size,
      "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }
    for path in files
  ],
}
out = evidence / "simulated-monitors-qualify.json"
out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(payload, sort_keys=True))
PY

echo "qualify-guest: PASS"
