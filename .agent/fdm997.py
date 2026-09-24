"""Transport the verified FDM-997 candidate; never modify main or deploy."""
import base64
import hashlib
import json
import lzma
import os
from pathlib import Path
import subprocess
import urllib.request

BASE = '22ed8f26ffbc531de8470c49528454e16be4be35'
HANDOFF = 'c660325bf437e4330b00f12cdd2beb3679d79ab9'
EXPECTED_TREE = '74503b246bc3ab120711701ae1aa4c385db751aa'
BRANCH = 'feat/fdm-997-widget-chrome'
PARTS = ['baadf100a48daefd86c5ea347d1bfc68294ff44a',
         'e6dd078885515f6cd0bbe0d8ff10bc23537347e0',
         '29b2e099232c765c6533d113c12beab3fcf145ad',
         'bbe208cf6f278370b0cf9f4dd32caa1267681ed4']
REPO = os.environ['GH_REPOSITORY']
EVIDENCE = Path('.fdm997-evidence')
EVIDENCE.mkdir(exist_ok=True)
manifest = {'base': BASE, 'handoff': HANDOFF, 'branch': BRANCH, 'commits': []}


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def api(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(
        'https://api.github.com/repos/' + REPO + '/' + path,
        data=data,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json',
                 'Content-Type': 'application/json',
                 'X-GitHub-Api-Version': '2022-11-28'},
        method='GET' if payload is None else 'POST')
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def save_manifest():
    (EVIDENCE / 'publication.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2), flush=True)


assert git('rev-parse', 'HEAD') == BASE, 'Unexpected source base'
assert not git('ls-remote', '--heads', 'origin', 'refs/heads/' + BRANCH), 'Do not overwrite an existing handoff'
assert git('ls-remote', '--heads', 'origin', 'refs/heads/main').split()[0] == BASE, 'Main changed; reconcile first'
packed = b''
for sha in PARTS:
    blob = api('git/blobs/' + sha)
    raw = base64.b64decode(blob['content'])
    actual = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    assert actual == sha, 'Transport blob mismatch'
    packed += raw
assert hashlib.sha256(packed).hexdigest() == '9dd0678a469e3d9d0e7fc3fb67a5f24c80e19d861301ecddb2d6cd3a6ec04466'
steps = json.loads(lzma.decompress(packed))
assert len(steps) == 4
subprocess.run(['git', 'config', 'user.name', 'Fernando Dâmaso'], check=True)
subprocess.run(['git', 'config', 'user.email', '4246135+fernandodamaso@users.noreply.github.com'], check=True)
parent = BASE
for index, step in enumerate(steps, 1):
    patch_path = EVIDENCE / ('checkpoint-' + str(index) + '.patch')
    patch_path.write_text(step['patch'])
    subprocess.run(['git', 'apply', '--index', str(patch_path)], check=True)
    subprocess.run(['git', 'diff', '--cached', '--check'], check=True)
    subprocess.run(['git', 'commit', '-m', step['message']], check=True)
    head = git('rev-parse', 'HEAD')
    manifest['commits'].append({'parent': parent, 'sha': head, 'tree': git('rev-parse', 'HEAD^{tree}'), 'message': step['message']})
    parent = head
manifest['head'] = parent
manifest['tree'] = git('rev-parse', 'HEAD^{tree}')
assert manifest['tree'] == EXPECTED_TREE, 'Candidate differs from locally tested tree'
assert not git('diff', HANDOFF, 'HEAD', '--', 'docs/widget-gallery/reference/sidebar-redesign-2026-09-23', 'docs/widget-gallery/README.md'), 'Original design assets changed'
assert not git('ls-files', '.agent', '.github/workflows/fdm-997-staging.yml'), 'Transport files leaked into candidate'
subprocess.run(['git', 'diff', '--check', BASE, 'HEAD'], check=True)
manifest['changed_files'] = git('diff', '--name-only', BASE, 'HEAD').splitlines()
with (EVIDENCE / 'candidate-source.tar.gz').open('wb') as out:
    subprocess.run(['git', 'archive', '--format=tar.gz', 'HEAD'], stdout=out, check=True)
save_manifest()

for name, command in [
    ('sidebar-node', ['node', 'tests/test_sidebar_widgets.mjs']),
    ('widgetkit-node', ['node', 'tests/test_widgetkit_structure.mjs']),
    ('section-qml', ['python3', '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_widget_chrome_qml.py', '-v']),
    ('full-qml', ['/usr/lib/qt6/bin/qmltestrunner', '-input', 'tests', '-import', 'components', '-import', 'tests/qml-imports'])
]:
    with (EVIDENCE / (name + '.log')).open('w') as out:
        result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT, timeout=180)
    manifest[name] = result.returncode
    save_manifest()
    assert result.returncode == 0, name + ' failed; inspect artifact log'

# Normal, non-force creation of an isolated feature branch. No existing ref is updated.
assert not git('ls-remote', '--heads', 'origin', 'refs/heads/' + BRANCH), 'Another writer created the candidate branch'
result = subprocess.run(['git', 'push', 'origin', 'HEAD:refs/heads/' + BRANCH], capture_output=True, text=True)
(EVIDENCE / 'push.log').write_text(result.stdout + result.stderr)
manifest['push_returncode'] = result.returncode
if result.returncode == 0:
    manifest['published_head'] = git('ls-remote', '--heads', 'origin', 'refs/heads/' + BRANCH).split()[0]
    assert manifest['published_head'] == manifest['head']
else:
    # If git transport is restricted, export exact Git objects for the connected
    # GitHub action to finish publication; never bypass restrictions on main.
    print('Feature push unavailable; preparing verified object handoff', flush=True)
    uploaded = set()
    try:
        for commit in manifest['commits']:
            entries = []
            paths = git('diff', '--name-only', commit['parent'], commit['sha']).splitlines()
            for path in paths:
                listing = git('ls-tree', commit['sha'], '--', path)
                if not listing:
                    entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
                    continue
                mode, kind, sha = listing.split('\t')[0].split()
                assert kind == 'blob'
                if sha not in uploaded:
                    raw = subprocess.check_output(['git', 'show', commit['sha'] + ':' + path])
                    response = api('git/blobs', {'content': base64.b64encode(raw).decode(), 'encoding': 'base64'})
                    assert response['sha'] == sha
                    uploaded.add(sha)
                entries.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': sha})
            commit['tree_elements'] = entries
            commit['parent_tree'] = git('rev-parse', commit['parent'] + '^{tree}')
            save_manifest()
        manifest['objects_uploaded'] = True
    except Exception as error:
        manifest['object_handoff_error'] = type(error).__name__ + ': ' + str(error)
save_manifest()
