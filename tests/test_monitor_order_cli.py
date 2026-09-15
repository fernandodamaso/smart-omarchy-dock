"""FDM-947 CLI/schema/docs coverage for workspaceMonitorOrder."""
import json
from pathlib import Path
import sys
import unittest

import test_cli
import test_cli_mutations

ROOT = test_cli.ROOT


class MonitorOrderCliTests(unittest.TestCase):
    set_hosts = test_cli.CliTests.set_hosts
    run_cli = test_cli.CliTests.run_cli
    response = test_cli.CliTests.response

    def setUp(self):
        test_cli.CliTests.setUp(self)
        self.set_hosts('plugin')
        self.env['SMARTDOCK_TEST_ROOT'] = str(ROOT)
        (self.bin / 'qs').write_text('#!' + sys.executable + '\n' + test_cli_mutations.FAKE_QS)

    def requests(self, command):
        if not self.calls.exists():
            return []
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        requests = [json.loads(call[-1]) for call in calls if call[:1] == ['ipc']]
        return [item['arguments'] for item in requests if item['command'] == command]

    def test_schema_set_get_reset_and_dry_run_use_existing_typed_cli(self):
        schema = self.response(('config', 'schema', 'workspaceMonitorOrder', '--json'))
        setting = schema['data']['settings']['workspaceMonitorOrder']
        self.assertEqual(setting['type'], 'array')
        self.assertEqual(setting['format'], 'monitor-connectors')
        self.assertEqual(setting['default'], [])

        self.response(('config', 'set', 'workspaceMonitorOrder',
                       '["HDMI-A-1","DP-1"]', '--json'))
        self.assertEqual(self.requests('config.apply')[-1], {
            'patch': {'workspaceMonitorOrder': ['HDMI-A-1', 'DP-1']},
            'dryRun': False,
        })

        patch = self.tmp / 'monitor-order.json'
        patch.write_text('{"workspaceMonitorOrder":["DP-1","HDMI-A-1"]}', encoding='utf-8')
        self.response(('config', 'apply', '--file', str(patch), '--dry-run', '--json'))
        self.assertEqual(self.requests('config.apply')[-1], {
            'patch': {'workspaceMonitorOrder': ['DP-1', 'HDMI-A-1']},
            'dryRun': True,
        })

        requested = self.response(('config', 'get', 'workspaceMonitorOrder', '--json'))
        self.assertEqual(requested['data']['settings']['workspaceMonitorOrder'], [])
        self.response(('config', 'get', 'workspaceMonitorOrder', '--effective', '--json'))
        self.assertEqual(self.requests('config.get')[-1], {
            'key': 'workspaceMonitorOrder', 'effective': True,
        })

        self.response(('config', 'reset', 'workspaceMonitorOrder', '--json'))
        self.assertEqual(self.requests('config.reset')[-1], {'key': 'workspaceMonitorOrder'})

    def test_bad_json_array_text_is_rejected_before_host_mutation(self):
        before = len(self.requests('config.apply'))
        result = self.response(('config', 'set', 'workspaceMonitorOrder', 'not-json', '--json'), 2)
        self.assertEqual(result['error']['code'], 'E_VALIDATION')
        self.assertEqual(len(self.requests('config.apply')), before)

    def test_monitor_order_is_in_offline_docs_with_connected_and_offline_example(self):
        sources = {
            'README.md': (ROOT / 'README.md').read_text(encoding='utf-8'),
            'docs/CONFIGURATION.md': (ROOT / 'docs/CONFIGURATION.md').read_text(encoding='utf-8'),
            'docs/CLI_REFERENCE.md': (ROOT / 'docs/CLI_REFERENCE.md').read_text(encoding='utf-8'),
        }
        for name, text in sources.items():
            self.assertIn('workspaceMonitorOrder', text, name)
        combined = '\n'.join(sources.values())
        self.assertIn('HDMI-A-1', combined)
        self.assertIn('DP-1', combined)
        self.assertIn('disconnected', combined.lower(),
                      'docs explain that saved disconnected connector names are retained')
        self.assertIn('automatic', combined.lower(),
                      'docs explain that [] means automatic physical ordering')


if __name__ == '__main__':
    unittest.main()
