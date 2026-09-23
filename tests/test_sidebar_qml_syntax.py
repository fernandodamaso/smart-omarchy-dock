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
        names = ['DockHost.qml', 'components/DockSidebarController.qml',
                 'components/DockSidebar.qml','components/DockSidebarViewport.qml',
                 'components/DockSidebarRow.qml','components/DockSidebarRowInput.qml','components/DockSidebarKeyboard.qml',
                 'components/DockHerdrWorkingIndicator.qml',
                 'components/DockHerdrStatusColors.qml','components/DockHerdrStatusMark.qml',
                 'components/DockContextMenu.qml','components/DockSidebarWidgetArea.qml',
                 'components/DockSidebarWidgetManager.qml',
                 'components/DockSidebarWidgetView.qml','components/DockWidgetCard.qml',
                 'components/DockSidebarPinnedStrip.qml',
                 'tests/fixtures/SidebarWidgetFixture.qml',
                 'tests/tst_sidebarwidgets.qml','tests/tst_widgetkit.qml',
                 'tests/widget-gallery/WidgetGallery.qml',
                 'tests/runtime/sidebar.qml','tests/runtime/sidebar-native.qml']
        names.extend(sorted(str(path.relative_to(ROOT))
                            for path in (ROOT / 'components' / 'widgets').glob('*.qml')))
        for name in names:
            with self.subTest(file=name):
                result = subprocess.run([FORMATTER, str(ROOT / name)], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
