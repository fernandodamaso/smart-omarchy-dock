#!/usr/bin/env python3
import fcntl
import json
from pathlib import Path
import os
import stat
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import dockrail_migrate as migration


class MigrationTests(unittest.TestCase):
    def env(self, root: Path):
        home = root / "home with spaces"
        return {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(root / "cfg with spaces"),
            "XDG_DATA_HOME": str(root / "data with spaces"),
            "XDG_CACHE_HOME": str(root / "cache with spaces"),
            "XDG_STATE_HOME": str(root / "state with spaces"),
            "XDG_BIN_HOME": str(root / "bin with spaces"),
        }

    def paths(self, env):
        return migration.resolve_paths(env)

    def legacy_config(self, paths, raw='{\n  "unknownFutureKey": {"b": 2, "a": 1},\n  "sidebarWidgets": ["b", "a"]\n}\n'):
        paths.legacy_config_root.mkdir(parents=True, exist_ok=True)
        target = paths.legacy_config_root / "dock.json"
        target.write_text(raw, encoding="utf-8")
        target.chmod(0o640)
        return target, raw

    def run_startup(self, env, **kwargs):
        with mock.patch.object(migration, "_standalone_instances", return_value=[]):
            return migration.startup(env=env, runtime=kwargs.pop("runtime", "plugin"), **kwargs)

    def test_clean_start_selects_canonical_without_writing_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            result = self.run_startup(env)
            self.assertEqual(result["selectionProvenance"], "canonical-clean")
            self.assertEqual(result["configPath"], str(paths.canonical_config_root / "dock.json"))
            self.assertFalse(paths.canonical_config_root.exists())
            self.assertFalse((paths.migration_root / migration.MIGRATION_ID / "journal.json").exists())

    def test_explicit_config_is_isolated_and_does_not_touch_migration_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            env["DOCKRAIL_CONFIG"] = str(Path(tmp) / "isolated" / "dock.json")
            paths = self.paths(env)
            result = self.run_startup(env, runtime="source")
            self.assertEqual(result["selectionProvenance"], "explicit-config")
            self.assertEqual(result["configPath"], env["DOCKRAIL_CONFIG"])
            self.assertFalse(paths.migration_root.exists())

    def test_legacy_state_migrates_byte_for_byte_and_aliases_owned_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            old_config, raw = self.legacy_config(paths)
            widgets = paths.legacy_data_root / "widgets"
            providers = paths.legacy_data_root / "providers"
            widgets.mkdir(parents=True)
            providers.mkdir(parents=True)
            (widgets / "registry.json").write_text('{"packages":[]}\n', encoding="utf-8")
            provider = providers / "smartdock-launcher-badge-provider"
            provider.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            provider.chmod(0o755)

            result = self.run_startup(env)
            self.assertTrue(result["migrated"])
            self.assertEqual(result["selectionProvenance"], "migrated-legacy")
            new_config = paths.canonical_config_root / "dock.json"
            self.assertEqual(new_config.read_text(encoding="utf-8"), raw)
            self.assertEqual(stat.S_IMODE(new_config.stat().st_mode), 0o640)
            self.assertTrue(paths.legacy_config_root.is_symlink())
            self.assertEqual(paths.legacy_config_root.resolve(), paths.canonical_config_root.resolve())
            self.assertTrue((paths.legacy_data_root / "widgets").is_symlink())
            self.assertTrue((paths.legacy_data_root / "providers").is_symlink())
            self.assertEqual(
                stat.S_IMODE((paths.canonical_data_root / "providers" / provider.name).stat().st_mode),
                0o755,
            )
            journal = json.loads((paths.migration_root / migration.MIGRATION_ID / "journal.json").read_text())
            self.assertEqual(journal["phase"], "committed")
            recovery = paths.migration_root / migration.MIGRATION_ID / "recovery"
            self.assertEqual((recovery / "config" / "dock.json").read_text(), raw)
            self.assertTrue((recovery / "data" / "widgets" / "registry.json").is_file())

    def test_valid_canonical_state_wins_without_merging_legacy(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            paths.canonical_config_root.mkdir(parents=True)
            (paths.canonical_config_root / "dock.json").write_text('{"canonical":true}\n')
            old, _ = self.legacy_config(paths, '{"legacy":true}\n')
            result = self.run_startup(env)
            self.assertFalse(result["migrated"])
            self.assertEqual(result["selectionProvenance"], "canonical-existing")
            self.assertFalse(paths.legacy_config_root.is_symlink())
            self.assertEqual(old.read_text(), '{"legacy":true}\n')

    def test_invalid_canonical_never_falls_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            paths.canonical_config_root.mkdir(parents=True)
            (paths.canonical_config_root / "unexpected.txt").write_text("do not overwrite")
            self.legacy_config(paths)
            with self.assertRaises(migration.MigrationError) as raised:
                self.run_startup(env)
            self.assertEqual(raised.exception.code, "E_MIGRATION_CONFLICT")

    def test_invalid_legacy_is_preserved_and_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            paths.legacy_config_root.mkdir(parents=True)
            bad = paths.legacy_config_root / "dock.json"
            bad.write_text("{not-json", encoding="utf-8")
            with self.assertRaises(migration.MigrationError) as raised:
                self.run_startup(env)
            self.assertEqual(raised.exception.code, "E_CONFIG_INVALID")
            self.assertEqual(bad.read_text(), "{not-json")

    def test_pending_migration_refuses_plugin_and_widget_dev_overrides(self):
        for kind in ("plugin", "widget"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                env = self.env(Path(tmp))
                paths = self.paths(env)
                self.legacy_config(paths)
                if kind == "plugin":
                    plugins = paths.config_home / "omarchy/plugins"
                    plugins.mkdir(parents=True)
                    target = Path(tmp) / "source"
                    target.mkdir()
                    (plugins / migration.PLUGIN_ID).symlink_to(target, target_is_directory=True)
                else:
                    dev_state = paths.legacy_data_root / "widgets/.dev-state.json"
                    dev_state.parent.mkdir(parents=True)
                    dev_state.write_text('{"schemaVersion":1}\n')
                with self.assertRaises(migration.MigrationError) as raised:
                    self.run_startup(env)
                self.assertEqual(raised.exception.code, "E_DEV_ACTIVE")
                self.assertFalse(paths.canonical_config_root.exists())

    def test_committed_canonical_state_does_not_block_on_later_dev_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            self.legacy_config(paths)
            self.run_startup(env)
            plugins = paths.config_home / "omarchy/plugins"
            plugins.mkdir(parents=True, exist_ok=True)
            target = Path(tmp) / "source"
            target.mkdir()
            active = plugins / migration.PLUGIN_ID
            active.symlink_to(target, target_is_directory=True)
            result = self.run_startup(env)
            self.assertEqual(result["selectionProvenance"], "committed-migration")

    def test_interrupted_publish_recovers_idempotently(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            self.legacy_config(paths)
            with self.assertRaises(migration.MigrationError) as raised:
                self.run_startup(env, fail_after="published")
            self.assertEqual(raised.exception.code, "E_INJECTED")
            self.assertTrue((paths.canonical_config_root / "dock.json").is_file())
            self.assertFalse(paths.legacy_config_root.is_symlink())
            recovered = self.run_startup(env)
            self.assertTrue(recovered["migrated"])
            self.assertTrue(paths.legacy_config_root.is_symlink())
            journal = json.loads((paths.migration_root / migration.MIGRATION_ID / "journal.json").read_text())
            self.assertEqual(journal["phase"], "committed")

    def test_source_change_after_staging_blocks_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            old, _ = self.legacy_config(paths)
            with self.assertRaises(migration.MigrationError) as raised:
                self.run_startup(env, fail_after="staged")
            self.assertEqual(raised.exception.code, "E_INJECTED")
            old.write_text('{"changed":true}\n', encoding="utf-8")
            with self.assertRaises(migration.MigrationError) as retry:
                self.run_startup(env)
            self.assertEqual(retry.exception.code, "E_BUSY")
            self.assertFalse(paths.canonical_config_root.exists())

    def test_package_lock_contention_refuses_without_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            self.legacy_config(paths)
            widgets = paths.legacy_data_root / "widgets"
            widgets.mkdir(parents=True)
            lock_path = widgets / ".package.lock"
            with lock_path.open("a+") as stream:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaises(migration.MigrationError) as raised:
                    self.run_startup(env)
                self.assertEqual(raised.exception.code, "E_BUSY")
                self.assertFalse(paths.canonical_config_root.exists())

    def test_unmanaged_legacy_symlink_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = self.env(Path(tmp))
            paths = self.paths(env)
            other = Path(tmp) / "other"
            other.mkdir()
            (other / "dock.json").write_text("{}\n")
            paths.legacy_config_root.parent.mkdir(parents=True)
            paths.legacy_config_root.symlink_to(other, target_is_directory=True)
            with self.assertRaises(migration.MigrationError) as raised:
                self.run_startup(env)
            self.assertEqual(raised.exception.code, "E_MIGRATION_CONFLICT")
            self.assertEqual(paths.legacy_config_root.resolve(), other.resolve())


if __name__ == "__main__":
    unittest.main()
