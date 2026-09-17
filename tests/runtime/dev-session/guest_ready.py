#!/usr/bin/env python3
"""Normalize guest Hyprland monitors into ready.json fields."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def ready_outputs(monitors: object) -> tuple[str, list[str]]:
    """Require two named Hyprland outputs and return (primary, all names).

    Primary is the leftmost monitor. Names stay in left-to-right order.
    """
    if not isinstance(monitors, list):
        raise ValueError(f"expected monitor list, got {monitors!r}")
    named = []
    for item in monitors:
        if not isinstance(item, dict):
            continue
        name = item.get("name")
        if not name:
            continue
        named.append(item)
    if len(named) < 2:
        raise ValueError(f"expected at least two monitors, got {monitors!r}")
    named.sort(key=lambda item: (int(item.get("x") or 0), str(item.get("name"))))
    names = [str(item["name"]) for item in named]
    return names[0], names


def main() -> int:
    raw = os.environ.get("MONITORS_JSON", "")
    try:
        monitors = json.loads(raw)
        primary, names = ready_outputs(monitors)
    except (json.JSONDecodeError, TypeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    if len(sys.argv) < 3:
        print(json.dumps({"output": primary, "outputs": names}, sort_keys=True))
        return 0
    ready_path = Path(sys.argv[1])
    runtime_dir = sys.argv[2]
    data = json.loads(ready_path.read_text(encoding="utf-8"))
    data["output"] = primary
    data["outputs"] = names
    data["xdg_runtime_dir"] = runtime_dir
    ready_path.write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(data, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
