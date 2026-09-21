#!/usr/bin/env python3
"""One-time branch-local seeding for SmartDock synthetic Demo Widgets."""
from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sys
import tempfile

DEMO_WIDGET_IDS = [
    "demo.display",
    "demo.lists",
    "demo.inputs",
    "demo.actions-states",
]


def seed_demo_widgets(config_path: Path, marker_path: Path) -> str:
    if marker_path.exists():
        return "already"

    try:
        raw = config_path.read_text(encoding="utf-8")
        data = json.loads(raw)
    except (OSError, json.JSONDecodeError):
        return "invalid"

    if not isinstance(data, dict):
        return "invalid"

    current = data.get("sidebarWidgets")
    if current is None:
        current = []
    if not isinstance(current, list):
        return "invalid"

    next_ids = list(current)
    for widget_id in DEMO_WIDGET_IDS:
        if widget_id not in next_ids:
            next_ids.append(widget_id)

    changed = next_ids != current
    if changed:
        data["sidebarWidgets"] = next_ids
        mode = stat.S_IMODE(config_path.stat().st_mode)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=config_path.parent, delete=False
        ) as handle:
            json.dump(data, handle, indent=2)
            handle.write("\n")
            temporary = Path(handle.name)
        os.chmod(temporary, mode)
        os.replace(temporary, config_path)

    marker_path.parent.mkdir(parents=True, exist_ok=True)
    marker_path.write_text("fdm-977 branch demo widgets seeded v2\n", encoding="utf-8")
    return "seeded" if changed else "preserved"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: smartdock_seed_demo_widgets.py CONFIG MARKER", file=sys.stderr)
        return 2
    print(seed_demo_widgets(Path(argv[1]), Path(argv[2])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
