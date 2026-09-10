#!/usr/bin/env python3
"""SmartDock's stdlib-only IPC client. Never starts a host or edits its config."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

BUNDLE = Path(__file__).resolve().parents[1]
EXIT_CODES = {
    'E_USAGE': 2, 'E_VALIDATION': 2,
    'E_RUNTIME_NOT_FOUND': 3, 'E_RUNTIME_AMBIGUOUS': 3,
    'E_PERSISTENCE': 4, 'E_EXPORT': 4,
    'E_TRANSPORT': 5, 'E_PROTOCOL': 5, 'E_TIMEOUT': 5,
    'E_BUSY': 6, 'E_CONFIG_INVALID': 6,
}
HELP = '''Usage: smartdock [OPTIONS] COMMAND

Read-only commands (never launch or restart the dock):
  help                         Show this help
  agent-guide                  Print the bundled agent configuration guide
  status                       Show the selected host and persistence state
  doctor                       Check dependencies and selected host health
  config schema [KEY]          Describe settings; bundled fallback when offline
  config get [KEY] [--effective]
                               Read requested or normalized live settings

Options may appear before or after the command:
  --json                       Emit one versioned JSON object on stdout
  --runtime auto|plugin|standalone
                               Select the host kind (default: auto)
  --instance ID                Exact qs ID or host process ID; never newest

Standalone lifecycle (explicit; not plugin configuration):
  launch [--daemonize] | --daemonize
  restart | stop | update | uninstall | autostart enable|disable|status

Bare smartdock shows help. Unknown commands exit 2, without starting anything.
Install just this client with: bash ./install.sh --cli-only
'''


class CliError(Exception):
    def __init__(self, code, message, data=None):
        super().__init__(message)
        self.code = code
        self.data = {} if data is None else data


def envelope(data, warnings=None):
    return {'apiVersion': 1, 'ok': True, 'data': data,
            'warnings': [] if warnings is None else warnings}


def decode_json(text, origin):
    try:
        return json.loads(text, parse_constant=lambda value: (_ for _ in ()).throw(
            ValueError('Non-finite JSON number: ' + value)))
    except (ValueError, RecursionError) as error:
        raise CliError('E_PROTOCOL', origin + ' did not return valid JSON: ' + str(error)) from error


def validate_response(text):
    reply = decode_json(text, 'SmartDock IPC')
    if (not isinstance(reply, dict) or type(reply.get('apiVersion')) is not int
            or reply['apiVersion'] != 1 or type(reply.get('ok')) is not bool
            or not isinstance(reply.get('data'), dict)
            or not isinstance(reply.get('warnings'), list)):
        raise CliError('E_PROTOCOL', 'Expected a SmartDock apiVersion=1 response envelope.')
    if not reply['ok']:
        error = reply.get('error')
        if (not isinstance(error, dict) or error.get('code') not in EXIT_CODES
                or not isinstance(error.get('message'), str)):
            raise CliError('E_PROTOCOL', 'SmartDock returned an invalid error envelope.')
    return reply


def validate_status(reply, instance):
    data = reply['data']
    runtime = data.get('runtime')
    if (not isinstance(runtime, dict) or runtime.get('mode') not in ('plugin', 'standalone')
            or runtime.get('instanceId') != str(instance['pid'])
            or not isinstance(data.get('configPath'), str) or not data['configPath']
            or data.get('loadState') not in ('missing', 'loaded', 'invalid')
            or data.get('writeState') not in ('idle', 'saving', 'saved', 'error')
            or not isinstance(data.get('loadError'), str)
            or not isinstance(data.get('writeError'), str)
            or type(data.get('revision')) is not int or data['revision'] < 0
            or type(data.get('persisted')) is not bool
            or type(data.get('defaultsInUse')) is not bool):
        raise CliError('E_PROTOCOL', 'Host status is incomplete or does not match the selected process.')
    runtime['quickshellId'] = instance['id']


class Transport:
    """Bounded argv transport using upstream qs list JSON and explicit PID IPC.

    Omarchy's omarchy-shell wrapper selects the newest config instance. It cannot
    express --instance, so use qs's supported --pid selector for both host kinds.
    A single deadline bounds discovery even when several unrelated shells run.
    """
    def __init__(self, timeout=2.0, deadline=8.0):
        self.timeout = timeout
        self.deadline = time.monotonic() + deadline

    def run(self, argv):
        timeout = min(self.timeout, self.deadline - time.monotonic())
        if timeout <= 0:
            raise CliError('E_TIMEOUT', 'Discovery deadline exceeded. Read status before retrying.',
                           {'applied': None, 'persisted': None})
        try:
            result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                                    text=True, encoding='utf-8', timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise CliError('E_TIMEOUT', 'IPC timed out; outcome is unknown. Read status before retrying.',
                           {'applied': None, 'persisted': None}) from error
        except FileNotFoundError as error:
            raise CliError('E_RUNTIME_NOT_FOUND', 'qs is unavailable. Install Quickshell and enable the plugin explicitly.') from error
        except UnicodeError as error:
            raise CliError('E_PROTOCOL', 'qs returned invalid UTF-8.') from error
        except OSError as error:
            raise CliError('E_TRANSPORT', 'Could not execute qs: ' + str(error)) from error
        if result.stderr.strip():
            print(result.stderr.rstrip(), file=sys.stderr)
        if len(result.stdout.encode('utf-8')) > 1024 * 1024:
            raise CliError('E_PROTOCOL', 'qs response exceeds the 1 MiB response limit.')
        if result.returncode != 0:
            raise CliError('E_TRANSPORT', 'qs exited with status ' + str(result.returncode)
                           + '. Check the selected instance and installed qs CLI compatibility.',
                           {'applied': None, 'persisted': None})
        return result.stdout.strip()

    def instances(self):
        text = self.run(['qs', 'list', '--all', '--json'])
        # Upstream emits this diagnostic (or only stderr) rather than [] for zero.
        if text in ('', 'No running instances.'):
            return []
        values = decode_json(text, 'qs list --all --json')
        if not isinstance(values, list):
            raise CliError('E_PROTOCOL', 'qs list must return an array.')
        ids, pids = set(), set()
        for item in values:
            if (not isinstance(item, dict) or not isinstance(item.get('id'), str)
                    or not item['id'] or type(item.get('pid')) is not int or item['pid'] <= 0
                    or not isinstance(item.get('config_path'), str)
                    or item['id'] in ids or item['pid'] in pids):
                raise CliError('E_PROTOCOL', 'qs list contains an invalid or duplicate instance.')
            ids.add(item['id'])
            pids.add(item['pid'])
        return values

    def request(self, instance, command, arguments=None, probe=False):
        payload = json.dumps({'apiVersion': 1, 'command': command,
                              'arguments': {} if arguments is None else arguments},
                             ensure_ascii=False, allow_nan=False, separators=(',', ':'))
        if len(payload.encode('utf-8')) > 65536:
            raise CliError('E_VALIDATION', 'Request exceeds the 64 KiB IPC request limit.')
        text = self.run(['qs', 'ipc', '--pid', str(instance['pid']), 'call', '--',
                         'smartdock', 'request', payload])
        if probe and text == 'Target not found.':
            return None
        return validate_response(text)

    def select(self, runtime='auto', instance_id=None):
        instances = self.instances()
        if instance_id is not None:
            instances = [item for item in instances
                         if instance_id in (item['id'], str(item['pid']))]
        candidates = []
        for item in instances:
            reply = self.request(item, 'status', probe=True)
            if reply is None:
                continue
            if not reply['ok']:
                raise CliError(reply['error']['code'], reply['error']['message'], reply['data'])
            validate_status(reply, item)
            if runtime == 'auto' or reply['data']['runtime']['mode'] == runtime:
                candidates.append((item, reply))
        if not candidates:
            raise CliError('E_RUNTIME_NOT_FOUND',
                           'No matching SmartDock host. Enable the plugin explicitly or select the correct --runtime/--instance.')
        if len(candidates) != 1:
            raise CliError('E_RUNTIME_AMBIGUOUS',
                           'More than one SmartDock host. Repeat with an exact --instance ID.',
                           {'candidates': [reply['data']['runtime'] for _, reply in candidates]})
        return candidates[0]


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise CliError('E_USAGE', message + '. Run smartdock help.')


def add_globals(parser):
    parser.add_argument('--json', action='store_true', default=argparse.SUPPRESS)
    parser.add_argument('--runtime', choices=('auto', 'plugin', 'standalone'), default=argparse.SUPPRESS)
    parser.add_argument('--instance', default=argparse.SUPPRESS)
    parser.add_argument('-h', '--help', dest='help_requested', action='store_true', default=argparse.SUPPRESS)


def build_parser():
    parser = Parser(prog='smartdock', add_help=False, allow_abbrev=False)
    add_globals(parser)
    commands = parser.add_subparsers(dest='group')
    for name in ('help', 'agent-guide', 'status', 'doctor'):
        child = commands.add_parser(name, add_help=False, allow_abbrev=False)
        add_globals(child)
    config = commands.add_parser('config', add_help=False, allow_abbrev=False)
    add_globals(config)
    actions = config.add_subparsers(dest='action')
    for name in ('schema', 'get'):
        child = actions.add_parser(name, add_help=False, allow_abbrev=False)
        add_globals(child)
        child.add_argument('key', nargs='?')
        if name == 'get':
            child.add_argument('--effective', action='store_true')
    return parser


def bundled_schema(key=None):
    try:
        metadata = json.loads((BUNDLE / 'config/settings-schema.json').read_text(encoding='utf-8'))
        defaults = json.loads((BUNDLE / 'config/dock.json').read_text(encoding='utf-8'))
        settings = metadata['settings']
        if metadata['schemaVersion'] != 1 or set(settings) != set(defaults):
            raise ValueError('Schema/default key mismatch')
        if key is not None and key not in settings:
            raise CliError('E_VALIDATION', 'Unknown setting: ' + key)
        selected = settings if key is None else {key: settings[key]}
        return envelope({'source': 'bundled', 'schemaVersion': 1,
                         'commands': metadata['commands'],
                         'settings': {name: dict(spec, default=defaults[name]) for name, spec in selected.items()}},
                        ['Bundled metadata only; this is not the running configuration.'])
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise CliError('E_PROTOCOL', 'Bundled schema is unavailable or inconsistent: ' + str(error)) from error


def execute(args):
    if getattr(args, 'help_requested', False) or args.group in (None, 'help'):
        return envelope({'text': HELP})
    if args.group == 'agent-guide':
        try:
            return envelope({'text': (BUNDLE / 'docs/AGENT_CONFIGURATION.md').read_text(encoding='utf-8')})
        except (OSError, UnicodeError) as error:
            raise CliError('E_PROTOCOL', 'Bundled agent guide is unavailable: ' + str(error)) from error
    if args.group == 'config' and args.action is None:
        raise CliError('E_USAGE', 'config requires a subcommand. Run smartdock help.')
    runtime = getattr(args, 'runtime', 'auto')
    instance_id = getattr(args, 'instance', None)
    if instance_id == '':
        raise CliError('E_USAGE', '--instance requires a nonempty exact ID.')
    transport = Transport()
    checks = {'python': True, 'quickshell': shutil.which('qs') is not None,
              'omarchyShell': shutil.which('omarchy-shell') is not None, 'liveRuntime': False}
    try:
        instance, status = transport.select(runtime, instance_id)
    except CliError as error:
        if (error.code == 'E_RUNTIME_NOT_FOUND' and args.group == 'config'
                and args.action == 'schema' and runtime == 'auto' and instance_id is None):
            return bundled_schema(args.key)
        if args.group == 'doctor':
            error.data['checks'] = checks
        raise
    if args.group in ('status', 'doctor'):
        if args.group == 'doctor':
            checks['liveRuntime'] = True
            status['data']['checks'] = checks
            if status['data']['loadState'] == 'invalid':
                raise CliError('E_CONFIG_INVALID', status['data']['loadError'], status['data'])
            if status['data']['writeState'] == 'error':
                raise CliError('E_PERSISTENCE', status['data']['writeError'], status['data'])
        return status
    arguments = {} if args.key is None else {'key': args.key}
    if args.action == 'get':
        arguments['effective'] = args.effective
    reply = transport.request(instance, 'config.' + args.action, arguments)
    if reply['ok']:
        data = reply['data']
        if (not isinstance(data.get('settings'), dict)
                or (args.key is not None and set(data['settings']) != {args.key})):
            raise CliError('E_PROTOCOL', 'Expected a keyed settings object from the selected host.')
        if args.action == 'schema' and (data.get('schemaVersion') != 1
                                       or not isinstance(data.get('commands'), list)):
            raise CliError('E_PROTOCOL', 'Expected versioned schema and command metadata.')
    return reply


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    as_json = '--json' in argv
    try:
        reply = execute(build_parser().parse_args(argv))
    except CliError as error:
        reply = {'apiVersion': 1, 'ok': False,
                 'error': {'code': error.code, 'message': str(error)},
                 'data': error.data, 'warnings': []}
    if as_json:
        print(json.dumps(reply, ensure_ascii=False, allow_nan=False, separators=(',', ':')))
    elif reply['ok']:
        data = reply['data']
        print(data['text'] if 'text' in data else json.dumps(data, ensure_ascii=False, indent=2))
        for warning in reply['warnings']:
            print('smartdock: ' + str(warning), file=sys.stderr)
    else:
        print('smartdock: ' + reply['error']['code'] + ': ' + reply['error']['message'], file=sys.stderr)
        if reply['data']:
            print(json.dumps(reply['data'], ensure_ascii=False, indent=2), file=sys.stderr)
    return 0 if reply['ok'] else EXIT_CODES.get(reply['error']['code'], 5)


if __name__ == '__main__':
    sys.exit(main())
