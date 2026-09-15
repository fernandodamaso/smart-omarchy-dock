#!/usr/bin/env python3
from pathlib import Path


def replace_one(path, old, new, label):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    p.write_text(text.replace(old, new, 1))

replace_one(
    'tests/test_config_model.mjs',
'''assert.equal(result.error.code, 'E_VALIDATION');
assert.match(result.error.message, /workspaceGroups|Group Windows/i);
assert.equal(writes, legacyEnableWrites);''',
'''assert.equal(result.error.code, 'E_VALIDATION');
assert.match(result.data.validationErrors.map(error => error.message).join(' '),
  /workspaceGroups|Group Windows/i);
assert.equal(writes, legacyEnableWrites);''',
    'structured legacy validation assertion')

replace_one(
    'tests/test_context_menu_model.mjs',
'''assert.equal(scope.initialPage(false, 3, true), 'window')
assert.equal(scope.initialPage(true, 0, false), 'controls')''',
'''assert.equal(scope.initialPage(false, 3, true), 'window')
assert.equal(scope.initialPage(false, 1, true, false), 'window')
assert.equal(scope.initialPage(false, 1, true, true), 'app',
  'a saved local group remains a group menu even with one represented window')
assert.equal(scope.initialPage(true, 0, false, true), 'controls')''',
    'one-member saved group initial page contract')

print('FDM-941 final red assertions applied')
