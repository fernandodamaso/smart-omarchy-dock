"""Parse actual production QML. This is syntax evidence, not compositor rendering."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
FORMATTER = shutil.which('qmlformat') or '/usr/lib/qt6/bin/qmlformat'

class SidebarQmlSyntaxTests(unittest.TestCase):
    @unittest.skipUnless(Path(FORMATTER).is_file(), 'Qt declarative tools unavailable locally; installed in Headless CI')
    def test_production_qml_parses(self):
        for name in ['DockHost.qml', 'components/DockSidebarController.qml',
                     'components/DockSidebar.qml','components/DockSidebarViewport.qml',
                     'components/DockSidebarRow.qml','components/DockSidebarRowInput.qml','components/DockSidebarKeyboard.qml',
                     'components/DockContextMenu.qml','components/DockSidebarWidgetArea.qml',
                     'components/DockSidebarWidgetView.qml','components/DockWidgetCard.qml',
                     'components/DockSidebarPinnedStrip.qml',
                     'tests/fixtures/SidebarWidgetFixture.qml',
                     'tests/tst_sidebarwidgets.qml','tests/runtime/sidebar.qml','tests/runtime/sidebar-native.qml']:
            with self.subTest(file=name):
                result = subprocess.run([FORMATTER, str(ROOT / name)], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
