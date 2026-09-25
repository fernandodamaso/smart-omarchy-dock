#!/usr/bin/env python3
"""Select a local source for the existing Omarchy plugin; never start a dock."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from smartdock_cli import BUNDLE, CliError, Transport

PLUGIN_ID = 'io.github.fernandodamaso.smartdock'


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()


def worktrees(repo):
    rows = []
    for block in git(repo, 'worktree', 'list', '--porcelain').split('\n\n'):
        row = dict(line.split(' ', 1) if ' ' in line else (line, '')
                   for line in block.splitlines())
        rows.append(row)
    return rows


def resolve_source(target, repo, cache):
    path = Path(target).expanduser()
    if path.is_dir():
        return path.resolve()
    # Resolve an exact local branch; never checkout/reset an agent's branch.
    ref = 'refs/heads/' + target
    sha = git(repo, 'rev-parse', '--verify', ref + '^{commit}')
    for row in worktrees(repo):
        if row.get('branch') == ref:
            return Path(row['worktree'])
    path = cache / sha
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        git(repo, 'worktree', 'add', '--detach', str(path), sha)
    elif git(path, 'rev-parse', 'HEAD') != sha:
        raise ValueError('Cached checkout changed; use an explicit worktree path.')
    return path


def validate_source(source):
    manifest = json.loads((source / 'manifest.json').read_text())
    if manifest.get('id') != PLUGIN_ID:
        raise ValueError('Source is not a SmartDock plugin.')
    entries = manifest.get('entryPoints', {})
    if not entries.get('overlay'):
        raise ValueError('Source has no overlay entry point.')
    for entry in entries.values():
        path = (source / entry).resolve()
        if not path.is_relative_to(source) or not path.is_file():
            raise ValueError('Invalid or missing plugin entry point: ' + str(entry))


class Switcher:
    def __init__(self, plugins, reload):
        self.active = plugins / PLUGIN_ID
        self.backup = plugins / ('.' + PLUGIN_ID + '.smartdock-installed')
        self.reload = reload

    def link(self, source):
        temporary = self.active.with_name('.' + PLUGIN_ID + '.smartdock-next')
        temporary.symlink_to(source, target_is_directory=True)
        try:
            temporary.replace(self.active)
        finally:
            temporary.unlink(missing_ok=True)

    def use(self, source):
        validate_source(source)
        if source == self.active or source == self.backup or source.is_relative_to(self.backup):
            raise ValueError('Choose a source checkout outside the installed plugin.')
        previous = None
        if self.backup.exists():
            if not self.active.is_symlink():
                raise ValueError('Backup exists but active plugin is not a dev link; refusing to overwrite it.')
            previous = self.active.readlink()
        else:
            if not self.active.is_dir() or self.active.is_symlink():
                raise ValueError('An installed SmartDock directory is required before the first switch.')
            self.active.rename(self.backup)
        try:
            self.link(source)
            self.reload()
        except BaseException:
            if previous is not None:
                self.link(previous)
            else:
                self.active.unlink(missing_ok=True)
                self.backup.rename(self.active)
            try:
                self.reload()
            except Exception as error:
                print('Previous source restored on disk; reload failed: ' + str(error), file=sys.stderr)
            raise

    def reset(self):
        if not self.backup.exists():
            if self.active.is_symlink():
                raise ValueError('No saved installed copy; refusing to remove an unmanaged link.')
            if not self.active.is_dir():
                raise ValueError('Installed plugin directory is missing.')
            return
        if self.active.exists() and not self.active.is_symlink():
            raise ValueError('Active plugin is not a dev link; refusing to overwrite it.')
        self.active.unlink(missing_ok=True)
        self.backup.rename(self.active)
        # Restore the files even when the desktop host is unavailable.
        self.reload()


def shell_instance():
    config = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell/shell.qml'
    matches = [row for row in Transport().instances()
               if Path(row['config_path']).resolve() == config.resolve()]
    if len(matches) != 1:
        raise ValueError('Expected exactly one running Omarchy shell; found ' + str(len(matches)))
    return matches[0]


def reload_shell():
    shell_instance()  # Reject ambiguous hosts before the native restart.
    # Omarchy's plugin rescan retains compiled QML at the same URL. A native
    # restart is necessary when repointing a source link or reloading its edits.
    subprocess.run(['omarchy', 'restart', 'shell'], check=True, timeout=45)
    instance = shell_instance()
    transport = Transport(deadline=12)
    # Plugin startup is asynchronous. Wait for the dock IPC to come back.
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        try:
            reply = transport.request(instance, 'status', probe=True)
            if reply and reply['ok'] and reply['data'].get('runtime', {}).get('mode') == 'plugin':
                return
            if reply is None:
                # Older branches predate the control IPC. Require an actual
                # dock surface belonging to this new shell, not another dock.
                layers = json.loads(transport.run(['hyprctl', 'layers', '-j']))
                if any(layer.get('namespace') == 'smartdock' and layer.get('pid') == instance['pid']
                       for monitor in layers.values() for level in monitor.get('levels', {}).values()
                       for layer in level):
                    return
        except CliError:
            pass
        time.sleep(0.2)
    raise ValueError('Dock did not return after reload. Check the candidate QML; use smartdock dev reset to recover.')


def describe(path):
    try:
        branch = git(path, 'branch', '--show-current') or 'detached'
        sha = git(path, 'rev-parse', '--short', 'HEAD')
        dirty = ' (uncommitted edits)' if git(path, 'status', '--porcelain') else ''
        return f'{branch} @ {sha}{dirty}\n  {path}'
    except subprocess.CalledProcessError:
        return str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, prog='smartdock dev')
    commands = parser.add_subparsers(dest='command', required=True)
    use = commands.add_parser('use', help='Run a worktree or local branch on this desktop')
    use.add_argument('source', help='Checkout directory or local branch name')
    for name, help_text in [('list', 'List local worktrees and branches'),
                            ('status', 'Show the selected source'),
                            ('reload', 'Reload edits from the selected source'),
                            ('reset', 'Return to the saved installed copy')]:
        commands.add_parser(name, help=help_text)
    args = parser.parse_args()
    # Omarchy itself discovers plugins under HOME/.config, independently of XDG.
    plugins = Path.home() / '.config/omarchy/plugins'
    switcher = Switcher(plugins, reload_shell)
    if args.command == 'status':
        mode = 'Local source' if switcher.active.is_symlink() else 'Installed copy'
        print(mode + ':\n' + describe(switcher.active.resolve()))
        return
    repo = BUNDLE
    if (BUNDLE / '.source-dir').is_file():
        repo = Path((BUNDLE / '.source-dir').read_text().strip())
    if args.command == 'list':
        print('Worktrees:')
        for row in worktrees(repo):
            print(describe(Path(row['worktree'])))
        print('\nLocal branches:\n' + git(repo, 'branch', '--format=%(refname:short)'))
        return
    with (plugins / ('.' + PLUGIN_ID + '.smartdock-lock')).open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == 'use':
            cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'dockrail/dev-worktrees'
            source = resolve_source(args.source, repo, cache)
            instance = shell_instance()
            rows = json.loads(Transport().run(['qs', 'ipc', '--pid', str(instance['pid']),
                                              'call', '--', 'shell', 'listPlugins']))
            if not any(row['id'] == PLUGIN_ID and row.get('enabled') for row in rows):
                raise ValueError('Enable the installed SmartDock plugin before selecting a local source.')
            switcher.use(source)
            print('Running local source:\n' + describe(source))
        elif args.command == 'reset':
            switcher.reset()
            print('Restored installed copy:\n' + describe(switcher.active))
        else:
            switcher.reload()
            print('Reloaded:\n' + describe(switcher.active.resolve()))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError, CliError) as error:
        print('smartdock dev: ' + str(error), file=sys.stderr)
        sys.exit(1)
