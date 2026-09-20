import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HerdrLifecycleContractTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text(encoding="utf-8")

    def test_shared_service_is_demand_driven_in_both_runtime_modes(self):
        service = self.read("components/DockHerdrService.qml")
        self.assertIn("function acquire(owner)", service)
        self.assertIn("function setWindowProcesses(revision, pids)", service)
        self.assertIn("property int activeCount: 0", service)
        self.assertIn("if (root.activeCount === 1) root.startProvider()", service)
        self.assertIn("if (root.activeCount === 0) root.stopProvider()", service)
        self.assertIn("running: false", service)
        self.assertNotIn("running: true", service)

        plugin = self.read("Service.qml")
        overlay = self.read("Overlay.qml")
        standalone = self.read("shell.qml")
        self.assertIn("property alias herdrService: herdr", plugin)
        self.assertIn("DockHerdrService {", plugin)
        self.assertIn("herdrService: pluginService ? pluginService.herdrService : null", overlay)
        self.assertIn("DockHerdrService {", standalone)
        self.assertIn("herdrService: herdrService", standalone)

    def test_sidebar_registry_delegates_to_the_shared_service(self):
        host = self.read("DockHost.qml")
        self.assertIn('"herdr.agents"', host)
        self.assertIn("root.herdrService.acquire(owner)", host)
        self.assertIn("DockHerdrAgentsView", host)
        view = self.read("components/DockHerdrAgentsView.qml")
        self.assertIn("property var widgetContext", view)
        self.assertNotIn("Process {", view)

    def test_schema_registers_only_the_real_internal_widget(self):
        schema = json.loads(self.read("config/settings-schema.json"))
        self.assertIn(
            "herdr.agents",
            schema["settings"]["sidebarWidgets"]["registeredIds"],
        )

    def test_standalone_install_copies_provider_source(self):
        install = self.read("install.sh")
        self.assertIn('"$source_dir/provider/herdr"', install)
        self.assertIn('"$app_dir/provider/herdr"', install)
        self.assertIn("smartdock-herdr-provider", install)

    def test_old_badge_polling_path_remains_forbidden(self):
        self.assertFalse((ROOT / "components/DockHerdrBadgeService.qml").exists())
        active = "\n".join(
            self.read(path)
            for path in (
                "Service.qml",
                "Overlay.qml",
                "DockHost.qml",
                "shell.qml",
                "components/DockHerdrService.qml",
                "components/DockHerdrAgentsView.qml",
            )
        )
        self.assertNotIn("herdr agent list", active)
        self.assertNotIn("org.omarchy.Omaherdr", active)
        self.assertNotIn("omaherdr-notify", active)


if __name__ == "__main__":
    unittest.main()
