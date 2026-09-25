#!/usr/bin/env python3
"""Side-effect-free Dockrail/SmartDock path resolution."""
from __future__ import annotations
from dataclasses import dataclass
import os
from pathlib import Path
from typing import Mapping

@dataclass(frozen=True)
class DockrailPaths:
    home: Path
    config_home: Path
    data_home: Path
    cache_home: Path
    state_home: Path
    config_file: Path
    config_source: str
    canonical_config_root: Path
    legacy_config_root: Path
    canonical_data_root: Path
    legacy_data_root: Path
    canonical_client_root: Path
    legacy_client_root: Path
    canonical_cache_root: Path
    legacy_cache_root: Path
    migration_root: Path
    bin_home: Path

def _base(env: Mapping[str, str], key: str, fallback: Path) -> Path:
    value = env.get(key, "")
    return Path(value).expanduser() if value else fallback

def resolve_paths(env: Mapping[str, str] | None = None) -> DockrailPaths:
    env = os.environ if env is None else env
    home = Path(env.get("HOME") or str(Path.home())).expanduser()
    config_home = _base(env, "XDG_CONFIG_HOME", home / ".config")
    data_home = _base(env, "XDG_DATA_HOME", home / ".local" / "share")
    cache_home = _base(env, "XDG_CACHE_HOME", home / ".cache")
    state_home = _base(env, "XDG_STATE_HOME", home / ".local" / "state")
    bin_home = _base(env, "XDG_BIN_HOME", home / ".local" / "bin")
    canonical_config_root = config_home / "dockrail"
    legacy_config_root = config_home / "smartdock"
    canonical_override = env.get("DOCKRAIL_CONFIG", "")
    legacy_override = env.get("SMARTDOCK_CONFIG", "")
    if canonical_override:
        config_file, source = Path(canonical_override).expanduser(), "DOCKRAIL_CONFIG"
    elif legacy_override:
        config_file, source = Path(legacy_override).expanduser(), "SMARTDOCK_CONFIG"
    else:
        config_file, source = canonical_config_root / "dock.json", "canonical-default"
    return DockrailPaths(
        home=home, config_home=config_home, data_home=data_home, cache_home=cache_home, state_home=state_home,
        config_file=config_file, config_source=source,
        canonical_config_root=canonical_config_root, legacy_config_root=legacy_config_root,
        canonical_data_root=data_home / "dockrail", legacy_data_root=data_home / "smartdock",
        canonical_client_root=data_home / "dockrail-cli", legacy_client_root=data_home / "smartdock-cli",
        canonical_cache_root=cache_home / "dockrail", legacy_cache_root=cache_home / "smartdock",
        migration_root=state_home / "dockrail" / "migrations", bin_home=bin_home)
