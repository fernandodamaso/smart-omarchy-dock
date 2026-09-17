"""Local source switching: real filesystem/git, stub only desktop IPC."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('dev', ROOT / 'scripts/smartdock_dev.py')
assert spec.origin and Path(spec.origin).exists(), 'smartdock dev switcher is missing'
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


def check():
    with tempfile.TemporaryDirectory(prefix='dock switch ') as directory:
        root = Path(directory)
        plugins = root / 'plugins'
        plugins.mkdir()
        installed = plugins / dev.PLUGIN_ID
        installed.mkdir()
        (installed / 'marker').write_text('installed')
        source = root / 'source with spaces'
        source.mkdir()
        (source / 'manifest.json').write_text(json.dumps({
            'id': dev.PLUGIN_ID, 'entryPoints': {'overlay': 'Overlay.qml', 'service': 'Service.qml'}}))
        for name in ('Overlay.qml', 'Service.qml'):
            (source / name).touch()
        calls = []
        switcher = dev.Switcher(plugins, lambda: calls.append('reload'))
        switcher.use(source)
        assert installed.is_symlink() and installed.resolve() == source
        assert (switcher.backup / 'marker').read_text() == 'installed'
        other = root / 'other'
        other.mkdir()
        for path in source.iterdir():
            (other / path.name).write_bytes(path.read_bytes())
        switcher.use(other)
        assert installed.resolve() == other
        def fail():
            raise RuntimeError('bad QML')
        switcher.reload = fail
        try:
            switcher.use(source)
            assert False, 'failed reload must fail the switch'
        except RuntimeError:
            pass
        assert installed.resolve() == other, 'failed switch must restore previous source'
        switcher.reload = lambda: calls.append('reload')
        switcher.reset()
        switcher.reset()
        assert not installed.is_symlink()
        assert (installed / 'marker').read_text() == 'installed'
        assert not switcher.backup.exists()
        switcher.reload = fail
        try:
            switcher.use(source)
            assert False
        except RuntimeError:
            pass
        assert not installed.is_symlink() and (installed / 'marker').exists()
        assert not switcher.backup.exists()
        # A missing target can always be recovered without reading its manifest.
        switcher.reload = lambda: None
        switcher.use(source)
        installed.unlink()
        installed.symlink_to(root / 'deleted worktree')
        switcher.reset()
        assert (installed / 'marker').exists()
        subprocess.run(['git', 'init', '-q', str(source)], check=True)
        def git(*args):
            return subprocess.check_output(['git', '-C', str(source), *args], text=True).strip()
        git('add', '.')
        git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'init')
        git('branch', 'candidate')
        linked = root / 'linked worktree'
        git('worktree', 'add', '-q', str(linked), 'candidate')
        assert dev.resolve_source('candidate', source, root / 'cache') == linked
        git('branch', 'unopened')
        detached = dev.resolve_source('unopened', source, root / 'cache')
        assert detached != source and (detached / 'Overlay.qml').exists()
        assert dev.resolve_source('unopened', source, root / 'cache') == detached
        assert dev.resolve_source(str(source), source, root / 'cache') == source
    print('dev switch checks passed')


class DevSwitchTests(unittest.TestCase):
    def test_switch_and_recovery(self):
        check()

    def test_older_dock_without_control_ipc(self):
        with patch.object(dev, 'shell_instance', return_value={'pid': 123}), \
                patch.object(dev.subprocess, 'run') as restart, \
                patch.object(dev, 'Transport') as transport:
            transport.return_value.request.return_value = None
            transport.return_value.run.return_value = json.dumps({'DP-1': {'levels': {'2': [
                {'namespace': 'smartdock', 'pid': 123}]}}})
            dev.reload_shell()
            restart.assert_called_once_with(['omarchy', 'restart', 'shell'], check=True, timeout=45)
            transport.return_value.run.assert_called_once_with(['hyprctl', 'layers', '-j'])


if __name__ == '__main__':
    unittest.main()
