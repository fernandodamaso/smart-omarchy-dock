"""Documentation contracts: real CLI parsing + existing production-host harness.

Only transport/FileView services are substituted. No copied patch validator,
new runtime, or desktop session is involved. The marked guide blocks are inputs.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('docs_cli', ROOT / 'scripts/smartdock_cli.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)

# Replay into the existing harness so every request runs production QML method
# bodies and DockConfigModel/DockIconModel. Replaying keeps this fixture stateless
# between Python processes; it is not a second model implementation.
BRIDGE = """
import fs from 'node:fs';
import { hostHarness } from './tests/host_harness.mjs';
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const h = hostHarness(input.initial, [{id:'code',name:'Editor'},
  {id:'org.gnome.Nautilus',name:'Files'}, {id:'chatgpt',name:'ChatGPT'}]);
let reply;
for (const [command, args] of input.requests) reply = h.request(command, args);
console.log(JSON.stringify(reply));
"""


class ModelTransport:
    def __init__(self):
        self.initial = {
            'pinned': ['org.gnome.Nautilus', 'Missing.App', 'code', 'chatgpt'],
            'hiddenApplications': ['code', 'Missing.App'],
            'iconOverrides': {'other': '/tmp/keep.png', 'legacy': 'untouched-legacy'},
            'hoverGlowOpacity': 0.72, 'clickAction': 'launch',
            'extensionData': {'keep': ['opaque']},
        }
        self.requests = []

    def select(self, runtime='auto', instance_id=None):
        return {'id': 'docs-fixture', 'pid': 123}, self.request(None, 'status')

    def request(self, instance, command, arguments=None):
        self.requests.append([command, arguments or {}])
        result = subprocess.run(['node', '--input-type=module', '-e', BRIDGE],
                                cwd=ROOT, text=True, capture_output=True, timeout=10,
                                input=json.dumps({'initial': self.initial,
                                                  'requests': self.requests}))
        if result.returncode:
            raise AssertionError(result.stderr)
        return json.loads(result.stdout)


class CliDocumentationTests(unittest.TestCase):
    def setUp(self):
        self.guide = (ROOT / 'docs/AGENT_CONFIGURATION.md').read_text(encoding='utf-8')
        self.transport = ModelTransport()
        self.mock = patch.object(cli, 'Transport', return_value=self.transport)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def run_command(self, command):
        args = shlex.split(command)
        self.assertEqual(args.pop(0), 'smartdock')
        reply = cli.execute(cli.build_parser().parse_args(args))
        self.assertTrue(reply['ok'], reply)
        return reply['data']

    def block(self, name, language):
        match = re.search(r'<!-- recipe: ' + re.escape(name) + r' -->\s*```'
                          + language + r'\n(.*?)\n```', self.guide, re.S)
        self.assertIsNotNone(match, 'Missing executable guide recipe: ' + name)
        return match.group(1)

    def test_all_reference_defaults_commands_and_errors_match_implementation(self):
        inventory = ROOT / 'docs/CONFIGURATION.md'
        reference = ROOT / 'docs/CLI_REFERENCE.md'
        for path in (inventory, reference, ROOT / 'docs/CLI_RUNTIME_CHECKS.md',
                     ROOT / 'docs/plans/2026-09-10-cli-first-migration.md'):
            self.assertTrue(path.is_file(), 'Missing deliverable: ' + str(path))
        rows = re.findall(r'^\| `([^`]+)` \| `([^`]+)` \|', inventory.read_text(), re.M)
        defaults = json.loads((ROOT / 'config/dock.json').read_text())
        self.assertEqual(len(rows), len(defaults), 'Each setting has exactly one inventory row')
        self.assertEqual({key: json.loads(value) for key, value in rows}, defaults)
        metadata = cli.bundled_schema()['data']
        text = reference.read_text()
        for command in metadata['commands']:
            self.assertIn('`' + command.replace('.', ' ') + '`', text)
        for code in cli.EXIT_CODES:
            self.assertIn(code, text)
        self.assertEqual(metadata['settings']['controlCommand']['risk'], 'executes-on-use')
        self.assertIn('controlCommand', self.guide)
        self.assertIn('never execute it to validate', self.guide)

    def test_json_recipes_dry_run_apply_preserve_and_project(self):
        for name in ('theme', 'calmer-motion', 'workspace-cards'):
            payload = json.loads(self.block(name, 'json'))
            before = self.run_command('smartdock config get --json')['settings']
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / 'patch with spaces.json'
                path.write_text(json.dumps(payload), encoding='utf-8')
                command = 'smartdock config apply --file ' + shlex.quote(str(path))
                dry = self.run_command(command + ' --dry-run --json')
                self.assertFalse(dry['applied'])
                self.assertFalse(dry['persisted'])
                self.assertEqual(self.run_command('smartdock config get --json')['settings'], before)
                applied = self.run_command(command + ' --json')
                self.assertTrue(applied['persisted'])
            after = self.run_command('smartdock config get --json')['settings']
            self.assertEqual(after, dict(before, **payload))
        effective = self.run_command('smartdock config get --effective --json')['settings']
        self.assertEqual(effective['hoverGlowOpacity'], 0.70)
        self.assertEqual(effective['workspaceLayout'], 'grouped')
        self.assertEqual(effective['workspaceMonitorScope'], 'current-monitor')
        self.assertEqual(effective['magnification'], 1)
        self.assertIsNone(effective['backgroundColor'])
        self.assertEqual(after['backgroundColor'], '@menu.background')
        self.assertTrue(after['backgroundColorEnabled'])
        self.assertTrue(after['borderColorEnabled'])
        self.assertEqual(after['clickAction'], 'launch', 'Unrelated legacy intent is preserved')
        self.run_command('smartdock config set position left --json')
        self.assertEqual(self.run_command('smartdock config get workspaceLayout --effective --json')['settings'],
                         {'workspaceLayout': 'flat'})
        self.assertEqual(self.run_command('smartdock config get workspaceLayout --json')['settings'],
                         {'workspaceLayout': 'grouped'})

    def test_application_recipe_restores_and_orders_without_dropping_unknown_ids(self):
        for line in self.block('applications', 'sh').splitlines():
            self.run_command(line)
        settings = self.run_command('smartdock config get --json')['settings']
        self.assertEqual(settings['pinned'], ['code', 'org.gnome.Nautilus', 'Missing.App', 'chatgpt'])
        self.assertEqual(settings['hiddenApplications'], ['Missing.App'])
        self.assertEqual(settings['extensionData'], self.transport.initial['extensionData'])
        self.assertEqual(settings['iconOverrides'], self.transport.initial['iconOverrides'])

    def test_icon_recipe_updates_only_one_mapping_and_never_claims_rendering(self):
        pins = self.transport.initial['pinned']
        reload_revision = None
        for line in self.block('icons', 'sh').splitlines():
            data = self.run_command(line)
            self.assertFalse(data['renderVerified'])
            if 'icons set ' in line:
                self.assertTrue(data['persisted'])
                reload_revision = data['iconReloadRevision']
            if 'icons reload ' in line:
                self.assertFalse(data['applied'])
                self.assertTrue(data['reloaded'])
                self.assertGreater(data['iconReloadRevision'], reload_revision)
        settings = self.run_command('smartdock config get --json')['settings']
        self.assertEqual(settings['iconOverrides'], self.transport.initial['iconOverrides'])
        self.assertEqual(settings['pinned'], pins)
        self.assertEqual(settings['extensionData'], self.transport.initial['extensionData'])

    def test_installed_guide_and_reference_are_offline_and_match_source(self):
        with tempfile.TemporaryDirectory(prefix='smartdock docs ') as temporary:
            root = Path(temporary)
            tools = root / 'tools'
            tools.mkdir()
            sentinel = root / 'qs-was-called'
            (tools / 'qs').write_text('#!/bin/sh\ntouch "' + str(sentinel) + '"\nexit 99\n')
            (tools / 'qs').chmod(0o755)
            env = dict(os.environ, HOME=str(root / 'home'), XDG_DATA_HOME=str(root / 'data'),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_BIN_HOME=str(root / 'bin'),
                       XDG_CACHE_HOME=str(root / 'cache'), PATH=str(tools) + ':' + os.environ['PATH'])
            subprocess.run(['bash', str(ROOT / 'install.sh'), '--cli-only'], env=env,
                           check=True, capture_output=True, text=True, timeout=10)
            installed = root / 'data/smartdock-cli'
            for name in ('AGENT_CONFIGURATION.md', 'CLI_REFERENCE.md', 'CONFIGURATION.md'):
                self.assertTrue((installed / 'docs' / name).is_file(), name + ' must be installed')
                self.assertEqual((installed / 'docs' / name).read_bytes(), (ROOT / 'docs' / name).read_bytes())
            # A missing source checkout must not break the installed offline guide.
            (installed / '.source-dir').write_text('/nonexistent/source-checkout\n')
            result = subprocess.run([str(root / 'bin/smartdock'), 'agent-guide', '--json'], env=env,
                                    check=True, capture_output=True, text=True, timeout=10)
            self.assertEqual(json.loads(result.stdout)['data']['text'], self.guide)
            self.assertFalse(sentinel.exists())
            for path in ('config', 'cache', 'data/smartdock', 'data/applications', 'data/icons'):
                self.assertFalse((root / path).exists(), path)


if __name__ == '__main__':
    unittest.main()
