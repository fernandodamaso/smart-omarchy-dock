#!/usr/bin/env python3
"""Journaled SmartDock -> Dockrail state migration.

This is the single migration policy used by plugin startup and standalone
installation/startup. It never edits live dock.json values; it only selects,
copies and aliases owned roots while preserving bytes and metadata.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Iterable, Mapping

from dockrail_paths import DockrailPaths, resolve_paths

MIGRATION_ID = "smartdock-to-dockrail-v1"
JOURNAL_SCHEMA = 1
SHARED_DATA_NAMES = ("widgets", "providers")
PLUGIN_ID = "io.github.fernandodamaso.smartdock"


class MigrationError(RuntimeError):
    def __init__(self, code: str, message: str, data=None):
        super().__init__(message)
        self.code = code
        self.data = {} if data is None else data


def _json_object(path: Path, label: str) -> dict:
    try:
        raw = path.read_text(encoding="utf-8")
        value = json.loads(raw)
    except FileNotFoundError as error:
        raise MigrationError("E_CONFIG_INVALID", f"{label} is missing: {path}") from error
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MigrationError("E_CONFIG_INVALID", f"{label} is unreadable or invalid JSON: {path}: {error}") from error
    if not isinstance(value, dict):
        raise MigrationError("E_CONFIG_INVALID", f"{label} must contain one JSON object: {path}")
    return value


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def _read_journal(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MigrationError("E_MIGRATION_STATE", f"Migration journal is invalid: {path}: {error}") from error
    if (
        not isinstance(value, dict)
        or value.get("schemaVersion") != JOURNAL_SCHEMA
        or value.get("migrationId") != MIGRATION_ID
        or value.get("phase") not in {"staged", "published", "aliased", "committed"}
    ):
        raise MigrationError("E_MIGRATION_STATE", f"Migration journal has an unsupported shape: {path}")
    return value


def _safe_relative_entries(root: Path) -> Iterable[tuple[str, Path]]:
    if not root.exists() and not root.is_symlink():
        return []
    if root.is_symlink():
        return [(".", root)]
    rows: list[tuple[str, Path]] = [(".", root)]
    for current, directories, files in os.walk(root, followlinks=False):
        base = Path(current)
        names = sorted(directories + files)
        for name in names:
            path = base / name
            rows.append((str(path.relative_to(root)), path))
    return rows


def _tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    if not root.exists() and not root.is_symlink():
        digest.update(b"ABSENT\0")
        return digest.hexdigest()
    for relative, path in _safe_relative_entries(root):
        stat = path.lstat()
        digest.update(relative.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        digest.update(oct(stat.st_mode & 0o7777).encode("ascii"))
        digest.update(b"\0")
        if path.is_symlink():
            digest.update(b"L\0")
            digest.update(os.readlink(path).encode("utf-8", "surrogateescape"))
        elif path.is_file():
            digest.update(b"F\0")
            with path.open("rb") as stream:
                while True:
                    chunk = stream.read(1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
        elif path.is_dir():
            digest.update(b"D\0")
        else:
            raise MigrationError("E_MIGRATION_STATE", f"Unsupported filesystem entry in managed state: {path}")
        digest.update(b"\0")
    return digest.hexdigest()


def _source_signature(paths: DockrailPaths) -> dict:
    signature = {"config": _tree_digest(paths.legacy_config_root)}
    for name in SHARED_DATA_NAMES:
        signature[name] = _tree_digest(paths.legacy_data_root / name)
    return signature


def _copy_tree(source: Path, destination: Path) -> None:
    if source.is_symlink():
        raise MigrationError("E_MIGRATION_STATE", f"Managed migration source must not be a symlink: {source}")
    if not source.is_dir():
        raise MigrationError("E_MIGRATION_STATE", f"Managed migration source is not a directory: {source}")
    shutil.copytree(source, destination, symlinks=True, copy_function=shutil.copy2)


def _empty_directory(path: Path) -> bool:
    return path.is_dir() and not path.is_symlink() and not any(path.iterdir())


def _validate_canonical(paths: DockrailPaths) -> str:
    root = paths.canonical_config_root
    config = root / "dock.json"
    if not root.exists() and not root.is_symlink():
        return "absent"
    if root.is_symlink():
        raise MigrationError("E_MIGRATION_CONFLICT", f"Canonical config root must not be a symlink: {root}")
    if config.is_file():
        _json_object(config, "Canonical Dockrail configuration")
        return "established"
    if _empty_directory(root):
        return "empty"
    raise MigrationError(
        "E_MIGRATION_CONFLICT",
        f"Canonical config root exists without a valid dock.json; refusing fallback or overwrite: {root}",
    )


def _validate_legacy(paths: DockrailPaths) -> str:
    root = paths.legacy_config_root
    config = root / "dock.json"
    if not root.exists() and not root.is_symlink():
        return "absent"
    if root.is_symlink():
        try:
            if root.resolve() == paths.canonical_config_root.resolve():
                return "alias"
        except OSError:
            pass
        raise MigrationError("E_MIGRATION_CONFLICT", f"Legacy config root is an unmanaged symlink: {root}")
    if not config.is_file():
        raise MigrationError(
            "E_CONFIG_INVALID",
            f"Legacy SmartDock config root exists without dock.json; source is preserved for repair: {root}",
        )
    _json_object(config, "Legacy SmartDock configuration")
    return "established"


def _plugin_development_active(paths: DockrailPaths) -> bool:
    plugins = paths.home / ".config" / "omarchy" / "plugins"
    active = plugins / PLUGIN_ID
    backup = plugins / ("." + PLUGIN_ID + ".smartdock-installed")
    return active.is_symlink() or backup.exists()


def _widget_development_active(paths: DockrailPaths) -> bool:
    return any((root / "widgets" / ".dev-state.json").is_file()
               for root in (paths.legacy_data_root, paths.canonical_data_root))


@contextlib.contextmanager
def _package_locks(paths: DockrailPaths):
    streams = []
    try:
        for root in (paths.legacy_data_root, paths.canonical_data_root):
            widget_root = root / "widgets"
            lock = widget_root / ".package.lock"
            if not widget_root.is_dir() or widget_root.is_symlink():
                continue
            stream = lock.open("a+", encoding="utf-8")
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                stream.close()
                raise MigrationError("E_BUSY", f"Widget package store is busy: {widget_root}") from error
            streams.append(stream)
        yield
    finally:
        for stream in reversed(streams):
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
            finally:
                stream.close()


def _standalone_instances(paths: DockrailPaths) -> list[dict]:
    try:
        result = subprocess.run(
            ["qs", "list", "--all", "--json"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=2,
            check=False,
        )
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return []
    if result.returncode != 0 or not result.stdout.strip() or result.stdout.strip() == "No running instances.":
        return []
    try:
        values = json.loads(result.stdout)
    except json.JSONDecodeError:
        return []
    if not isinstance(values, list):
        return []
    roots = {
        str((paths.legacy_data_root / "shell.qml").resolve(strict=False)),
        str((paths.canonical_data_root / "shell.qml").resolve(strict=False)),
    }
    matches = []
    for row in values:
        if not isinstance(row, dict) or not isinstance(row.get("config_path"), str):
            continue
        try:
            config_path = str(Path(row["config_path"]).resolve(strict=False))
        except OSError:
            continue
        if config_path in roots and isinstance(row.get("pid"), int):
            matches.append(row)
    return matches


def _handoff_standalone(paths: DockrailPaths, allowed: bool) -> bool:
    matches = _standalone_instances(paths)
    if not matches:
        return False
    if len(matches) != 1:
        raise MigrationError("E_BUSY", "More than one standalone SmartDock/Dockrail instance is running.")
    if not allowed:
        raise MigrationError("E_BUSY", "A standalone SmartDock/Dockrail host is still running; stop it before migration.")
    target = Path(matches[0]["config_path"]).resolve(strict=False).parent
    result = subprocess.run(
        ["qs", "kill", "-p", str(target), "--any-display"],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=5,
        check=False,
    )
    if result.returncode != 0:
        raise MigrationError("E_BUSY", "Could not stop the owned standalone host for migration handoff.")
    import time
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if not _standalone_instances(paths):
            return True
        time.sleep(0.1)
    raise MigrationError("E_BUSY", "Standalone host did not stop within the bounded migration handoff.")


def _recovery_copy(source: Path, destination: Path) -> None:
    if not source.exists() and not source.is_symlink():
        return
    if destination.exists() or destination.is_symlink():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(os.readlink(source), target_is_directory=True)
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True, copy_function=shutil.copy2)
    else:
        shutil.copy2(source, destination, follow_symlinks=False)


def _ensure_alias(legacy: Path, canonical: Path, recovery: Path, expected_digest: str) -> None:
    if legacy.is_symlink():
        try:
            if legacy.resolve() == canonical.resolve():
                return
        except OSError:
            pass
        raise MigrationError("E_MIGRATION_CONFLICT", f"Refusing to replace unmanaged legacy symlink: {legacy}")
    if _tree_digest(legacy) != expected_digest:
        raise MigrationError("E_BUSY", f"Legacy state changed before alias cutover: {legacy}")
    _recovery_copy(legacy, recovery)
    if legacy.exists():
        if legacy.is_dir():
            shutil.rmtree(legacy)
        else:
            legacy.unlink()
    legacy.parent.mkdir(parents=True, exist_ok=True)
    legacy.symlink_to(canonical, target_is_directory=True)


def _stage(paths: DockrailPaths, signature: dict) -> None:
    config_stage = paths.canonical_config_root.parent / ".dockrail-migrate-config-v1"
    data_stage = paths.canonical_data_root.parent / ".dockrail-migrate-data-v1"
    for stage in (config_stage, data_stage):
        if stage.exists() or stage.is_symlink():
            if stage.is_dir() and not stage.is_symlink():
                shutil.rmtree(stage)
            else:
                stage.unlink()
    _copy_tree(paths.legacy_config_root, config_stage)
    data_stage.mkdir(parents=True, exist_ok=False)
    for name in SHARED_DATA_NAMES:
        source = paths.legacy_data_root / name
        if source.exists() or source.is_symlink():
            _copy_tree(source, data_stage / name)
    if _source_signature(paths) != signature:
        shutil.rmtree(config_stage, ignore_errors=True)
        shutil.rmtree(data_stage, ignore_errors=True)
        raise MigrationError("E_BUSY", "Legacy state changed while migration staging was in progress; retry after writers stop.")


def _publish(paths: DockrailPaths, signature: dict) -> None:
    if _source_signature(paths) != signature:
        raise MigrationError("E_BUSY", "Legacy state changed after staging; refusing to publish a stale migration.")
    config_stage = paths.canonical_config_root.parent / ".dockrail-migrate-config-v1"
    data_stage = paths.canonical_data_root.parent / ".dockrail-migrate-data-v1"
    canonical_state = _validate_canonical(paths)
    if canonical_state == "empty":
        paths.canonical_config_root.rmdir()
        canonical_state = "absent"
    if canonical_state == "absent":
        if not config_stage.is_dir():
            raise MigrationError("E_MIGRATION_STATE", "Config staging directory is missing.")
        os.replace(config_stage, paths.canonical_config_root)
    else:
        staged_digest = _tree_digest(config_stage)
        if staged_digest != _tree_digest(paths.canonical_config_root):
            raise MigrationError("E_MIGRATION_CONFLICT", "Canonical config changed before publication.")
        shutil.rmtree(config_stage, ignore_errors=True)

    paths.canonical_data_root.mkdir(parents=True, exist_ok=True)
    for name in SHARED_DATA_NAMES:
        staged = data_stage / name
        if not staged.exists():
            continue
        target = paths.canonical_data_root / name
        if target.is_symlink():
            raise MigrationError("E_MIGRATION_CONFLICT", f"Canonical shared state is an unexpected symlink: {target}")
        if _empty_directory(target):
            target.rmdir()
        if not target.exists():
            os.replace(staged, target)
        elif _tree_digest(staged) == _tree_digest(target):
            shutil.rmtree(staged)
        else:
            raise MigrationError("E_MIGRATION_CONFLICT", f"Canonical shared state conflicts with legacy source: {target}")
    shutil.rmtree(data_stage, ignore_errors=True)


def _aliases_valid(paths: DockrailPaths) -> bool:
    try:
        if not paths.legacy_config_root.is_symlink() or paths.legacy_config_root.resolve() != paths.canonical_config_root.resolve():
            return False
        for name in SHARED_DATA_NAMES:
            legacy = paths.legacy_data_root / name
            canonical = paths.canonical_data_root / name
            if canonical.exists():
                if not legacy.is_symlink() or legacy.resolve() != canonical.resolve():
                    return False
        return True
    except OSError:
        return False


def _alias_legacy(paths: DockrailPaths, transaction: Path, signature: dict) -> None:
    recovery = transaction / "recovery"
    _ensure_alias(
        paths.legacy_config_root,
        paths.canonical_config_root,
        recovery / "config",
        signature["config"],
    )
    for name in SHARED_DATA_NAMES:
        source = paths.legacy_data_root / name
        target = paths.canonical_data_root / name
        if not target.exists():
            continue
        _ensure_alias(source, target, recovery / "data" / name, signature[name])


def _maybe_fail(point: str, fail_after: str | None) -> None:
    if fail_after == point:
        raise MigrationError("E_INJECTED", f"Injected migration failure after {point}.")


def _result(paths: DockrailPaths, provenance: str, *, migrated=False, was_running=False) -> dict:
    return {
        "migrationId": MIGRATION_ID,
        "ready": True,
        "configPath": str(paths.config_file if paths.config_source != "canonical-default"
                          else paths.canonical_config_root / "dock.json"),
        "dataRoot": str(paths.canonical_data_root),
        "clientRoot": str(paths.canonical_client_root),
        "cacheRoot": str(paths.canonical_cache_root),
        "configSource": paths.config_source,
        "selectionProvenance": provenance,
        "migrated": bool(migrated),
        "standaloneWasRunning": bool(was_running),
    }


def startup(
    *,
    env: Mapping[str, str] | None = None,
    runtime: str,
    handoff_standalone: bool = False,
    fail_after: str | None = None,
) -> dict:
    env = os.environ if env is None else env
    paths = resolve_paths(env)

    # Explicit config is an isolated contract. Never migrate production roots
    # merely because a source smoke test or terminal supplied an override.
    if paths.config_source in {"DOCKRAIL_CONFIG", "SMARTDOCK_CONFIG"}:
        return _result(paths, "explicit-config", migrated=False)

    paths.migration_root.mkdir(parents=True, exist_ok=True)
    lock_path = paths.migration_root / (MIGRATION_ID + ".lock")
    transaction = paths.migration_root / MIGRATION_ID
    journal_path = transaction / "journal.json"

    with lock_path.open("a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise MigrationError("E_BUSY", "Another Dockrail migration is already running.") from error

        journal = _read_journal(journal_path)
        if journal and journal["phase"] == "committed":
            if _validate_canonical(paths) != "established":
                raise MigrationError("E_MIGRATION_STATE", "Committed migration no longer has valid canonical configuration.")
            return _result(paths, "committed-migration", migrated=False)

        canonical_state = _validate_canonical(paths)
        if journal is None and canonical_state == "established":
            # A deliberately established canonical install wins. Legacy state is
            # retained rather than merged or replaced.
            return _result(paths, "canonical-existing", migrated=False)

        legacy_state = _validate_legacy(paths)
        if journal is None and legacy_state in {"absent", "alias"}:
            # Clean install/startup. Defaults may be created only by the full
            # installer; ordinary host bootstrap simply selects the canonical path.
            # A full standalone installer may still need to hand off an old
            # defaults-only process that never wrote dock.json.
            was_running = _handoff_standalone(paths, True) if handoff_standalone else False
            return _result(paths, "canonical-clean", migrated=False, was_running=was_running)

        if journal is None:
            if _plugin_development_active(paths):
                raise MigrationError(
                    "E_DEV_ACTIVE",
                    "Active SmartDock plugin development override blocks migration; run smartdock dev reset first.",
                )
            if _widget_development_active(paths):
                raise MigrationError(
                    "E_DEV_ACTIVE",
                    "Active Widget development override blocks migration; run smartdock widget dev reset first.",
                )

        with _package_locks(paths):
            was_running = _handoff_standalone(paths, handoff_standalone)
            if journal is None:
                signature = _source_signature(paths)
                transaction.mkdir(parents=True, exist_ok=True)
                _stage(paths, signature)
                journal = {
                    "schemaVersion": JOURNAL_SCHEMA,
                    "migrationId": MIGRATION_ID,
                    "phase": "staged",
                    "sourceSignature": signature,
                }
                _atomic_json(journal_path, journal)
                _maybe_fail("staged", fail_after)
            else:
                signature = journal.get("sourceSignature")
                if not isinstance(signature, dict):
                    raise MigrationError("E_MIGRATION_STATE", "Migration journal is missing its source signature.")

            if journal["phase"] == "staged":
                if _source_signature(paths) != signature:
                    raise MigrationError("E_BUSY", "Legacy state changed after staging; source is preserved and retry is blocked.")
                config_stage = paths.canonical_config_root.parent / ".dockrail-migrate-config-v1"
                data_stage = paths.canonical_data_root.parent / ".dockrail-migrate-data-v1"
                stage_missing = not config_stage.is_dir() or not data_stage.is_dir()
                for name in SHARED_DATA_NAMES:
                    source = paths.legacy_data_root / name
                    if (source.exists() or source.is_symlink()) and not (data_stage / name).exists():
                        stage_missing = True
                if stage_missing:
                    _stage(paths, signature)
                _publish(paths, signature)
                journal["phase"] = "published"
                _atomic_json(journal_path, journal)
                _maybe_fail("published", fail_after)

            if journal["phase"] == "published":
                _alias_legacy(paths, transaction, signature)
                journal["phase"] = "aliased"
                _atomic_json(journal_path, journal)
                _maybe_fail("aliased", fail_after)

            if journal["phase"] == "aliased":
                if not _aliases_valid(paths):
                    raise MigrationError("E_MIGRATION_STATE", "Migration aliases are incomplete or no longer target canonical state.")
                journal["phase"] = "committed"
                _atomic_json(journal_path, journal)
                _maybe_fail("committed", fail_after)

            return _result(paths, "migrated-legacy", migrated=True, was_running=was_running)


def envelope(data: dict) -> dict:
    return {"apiVersion": 1, "ok": True, "data": data, "warnings": []}


def error_envelope(error: MigrationError) -> dict:
    return {
        "apiVersion": 1,
        "ok": False,
        "error": {"code": error.code, "message": str(error)},
        "data": error.data,
        "warnings": [],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="dockrail-migrate")
    commands = parser.add_subparsers(dest="command", required=True)
    startup_parser = commands.add_parser("startup")
    startup_parser.add_argument("--runtime", choices=("plugin", "standalone", "source"), required=True)
    startup_parser.add_argument("--handoff-standalone", action="store_true")
    startup_parser.add_argument("--fail-after", choices=("staged", "published", "aliased", "committed"))
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        data = startup(
            runtime=args.runtime,
            handoff_standalone=args.handoff_standalone,
            fail_after=args.fail_after or os.environ.get("DOCKRAIL_MIGRATION_FAIL_AFTER") or None,
        )
        reply = envelope(data)
        status = 0
    except MigrationError as error:
        reply = error_envelope(error)
        status = 6 if error.code in {"E_BUSY", "E_DEV_ACTIVE"} else 1
    print(json.dumps(reply, ensure_ascii=False, allow_nan=False, separators=(",", ":")))
    return status


if __name__ == "__main__":
    sys.exit(main())
