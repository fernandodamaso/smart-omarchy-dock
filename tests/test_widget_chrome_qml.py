"""Execute production chrome blocks without constructing a Quickshell host.

Only host/popup endpoints are fixtures. Header/label/button QML and manager
routing methods are read from the current production files on every run.
This does not qualify compositor focus, tooltip placement, or a full shell.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = os.environ.get('QMLTESTRUNNER') or shutil.which('qmltestrunner') or '/usr/lib/qt6/bin/qmltestrunner'


def block(source, marker):
    """Extract a QML object/function, ignoring braces in strings and comments."""
    pos = source.index(marker)
    start = source.rfind('\n', 0, pos) + 1
    if marker.startswith('id:'):
        start = source.rfind('\n', 0, source.rfind('{', 0, pos)) + 1
    opening = source.index('{', start)
    tokens = re.finditer(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', source[opening:])
    depth = 0
    for token in tokens:
        if token.group() == '{':
            depth += 1
        elif token.group() == '}':
            depth -= 1
            if depth == 0:
                return source[start:opening + token.end()]
    raise ValueError(f'Unbalanced QML block: {marker}')


def chrome_fixture():
    area = (ROOT / 'components/DockSidebarWidgetArea.qml').read_text()
    pinned = (ROOT / 'components/DockSidebarPinnedStrip.qml').read_text()
    sidebar = (ROOT / 'components/DockSidebar.qml').read_text()
    # Missing declaration is deliberately not replaced with the desired geometry.
    inset = re.search(r'  readonly property real contentInset:[\s\S]*?(?=\n\n)', area)
    template = (ROOT / 'tests/fixtures/widget_section_chrome.qml.in').read_text()
    substitutions = {
        'COMPONENTS': (ROOT / 'components').as_uri(),
        'AREA_HEADER': block(area, 'id: sectionHeader'),
        'AREA_INSET': inset.group() if inset else 'property real contentInset: 0',
        'AREA_OPEN': block(area, 'function openManager('),
        'PINNED_LABEL': block(pinned, 'id: sectionLabel'),
        'MAIN_BUTTON': block(sidebar, 'id: widgetManage'),
        'MAIN_OPEN': block(sidebar, 'function openWidgetManager('),
        'SCREENSHOT': os.environ.get('WIDGET_CHROME_SCREENSHOT', '').replace('\\', '/'),
    }
    for name, value in substitutions.items():
        template = template.replace('@@' + name + '@@', value)
    return template


class WidgetChromeQmlTests(unittest.TestCase):
    @unittest.skipUnless(Path(RUNNER).is_file(), 'Qt test runner unavailable; installed by Headless CI')
    def test_production_section_chrome_and_manager_routes(self):
        with tempfile.TemporaryDirectory(prefix='smartdock-chrome-') as tmp:
            fixture = Path(tmp) / 'tst_widgetsectionchrome.qml'
            fixture.write_text(chrome_fixture())
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            imports = os.environ.get('WIDGET_CHROME_IMPORTS', str(ROOT / 'tests/qml-imports'))
            result = subprocess.run([RUNNER, '-input', str(fixture), '-import', str(ROOT / 'components'),
                                     '-import', imports], capture_output=True, text=True, env=env, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('0 failed', result.stdout)
            # Unlike the broad legacy fixtures, this focused harness must load cleanly.
            self.assertNotIn('QWARN', result.stdout)
            self.assertNotIn('QFATAL', result.stdout)
            print(result.stdout.strip().splitlines()[-2])
