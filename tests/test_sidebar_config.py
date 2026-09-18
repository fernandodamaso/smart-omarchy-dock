"""Actual CLI parser and host methods; only transport/storage use existing fixtures."""
import json
import shlex
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
from test_cli_docs import cli, ModelTransport

class SidebarConfigTests(unittest.TestCase):
    def setUp(self):
        self.transport = ModelTransport()
        self.mock = patch.object(cli, 'Transport', return_value=self.transport)
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def command(self, value):
        return cli.execute(cli.build_parser().parse_args(shlex.split(value)))

    def test_sidebar_cli_roundtrip_preserves_classic_and_unknown_data(self):
        before = self.command('config get --json')['data']['settings']
        for command in ['config set presentationMode sidebar', 'config set sidebarEdge right',
                        'config set sidebarExpandedWidth 480', 'config set sidebarCollapsed true',
                        'config set sidebarMonitor DISCONNECTED-DP-2']:
            result = self.command(command + ' --json')
            self.assertTrue(result['ok'], result)
            self.assertTrue(result['data']['persisted'])
        after = self.command('config get --json')['data']['settings']
        for key in before.keys() - {'presentationMode', 'sidebarEdge', 'sidebarExpandedWidth',
                                   'sidebarCollapsed', 'sidebarMonitor'}:
            self.assertEqual(after[key], before[key], key)
        self.assertEqual(after['sidebarExpandedWidth'], 480)
        self.assertTrue(after['sidebarCollapsed'])
        self.assertEqual(after['sidebarMonitor'], 'DISCONNECTED-DP-2')
        effective = self.command('config get --effective --json')['data']
        self.assertEqual(effective['settings']['windowScope'], 'all')
        self.assertTrue(effective['settings']['reserveSpace'])
        self.assertFalse(effective['presentation']['mapped'], 'No connected screen is not a mapped panel')
        self.assertEqual(effective['presentation']['width'], 0)
        for key in ['presentationMode','sidebarEdge','sidebarExpandedWidth','sidebarCollapsed','sidebarMonitor']:
            result = self.command('config reset ' + key + ' --json')
            self.assertTrue(result['ok'], result)
        self.assertEqual(self.command('config get --json')['data']['settings'], before)

    def test_atomic_invalid_sidebar_apply_and_dry_run(self):
        before = self.command('config get --json')['data']['settings']
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'sidebar.json'
            for value in [{'sidebarExpandedWidth':239}, {'sidebarExpandedWidth':481},
                          {'sidebarExpandedWidth':240.5}, {'sidebarExpandedWidth':'320'},
                          {'sidebarCollapsed':1}, {'sidebarEdge':'top'},
                          {'sidebarMonitor':'DP-1\n'}, {'presentationMode':'SideBar'}]:
                path.write_text(json.dumps(dict(value, iconSize=48)))
                result = self.command('config apply --file ' + shlex.quote(str(path)) + ' --json')
                self.assertFalse(result['ok'], value)
            path.write_text(json.dumps({'presentationMode':'sidebar','sidebarMonitor':'DP-9'}))
            result = self.command('config apply --file ' + shlex.quote(str(path)) + ' --dry-run --json')
            self.assertTrue(result['ok'], result)
            self.assertFalse(result['data']['applied'])
            self.assertFalse(result['data']['persisted'])
        self.assertEqual(self.command('config get --json')['data']['settings'], before)
