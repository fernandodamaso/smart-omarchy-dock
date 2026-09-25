#!/usr/bin/env python3
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DockrailBrandingTests(unittest.TestCase):
    def read(self, path):
        return (ROOT / path).read_text(encoding="utf-8")

    def test_manifest_uses_dockrail_display_identity_but_keeps_plugin_id(self):
        manifest = json.loads(self.read("manifest.json"))
        self.assertEqual(manifest["id"], "io.github.fernandodamaso.smartdock")
        self.assertEqual(manifest["name"], "Dockrail")
        self.assertEqual(manifest["author"], "Dockrail contributors")
        self.assertIn("developer-focused workspace rail", manifest["description"])

    def test_canonical_cli_is_dockrail_while_ipc_target_stays_smartdock(self):
        cli = self.read("scripts/smartdock_cli.py")
        launcher = self.read("scripts/dockrail")
        compat = self.read("scripts/smartdock")
        self.assertIn("Usage: dockrail [OPTIONS] COMMAND", cli)
        self.assertIn("prog='dockrail'", cli)
        self.assertIn("'smartdock', 'request'", cli)
        self.assertIn("Name=Dockrail", launcher)
        self.assertIn("Comment=Developer workspace rail for Hyprland", launcher)
        self.assertIn('exec bash "$script_dir/dockrail" "$@"', compat)

    def test_installer_and_uninstaller_are_product_branded(self):
        install = self.read("install.sh")
        uninstall = self.read("uninstall.sh")
        self.assertIn("Dockrail installed successfully.", install)
        self.assertIn("Name=Dockrail", install)
        self.assertIn("Comment=Developer workspace rail for Hyprland", install)
        self.assertNotIn("SmartDock for Omarchy installed successfully.", install)
        self.assertIn("Remove standalone Dockrail", uninstall)

    def test_current_docs_use_canonical_product_and_cli(self):
        current_docs = [
            "README.md", "AGENTS.md",
            "docs/AGENT_CONFIGURATION.md", "docs/CLI_REFERENCE.md",
            "docs/CONFIGURATION.md", "docs/DEV_SWITCH.md",
            "docs/HERDR_DATA_ACCESS.md", "docs/SIDEBAR_WIDGETS.md",
            "docs/WIDGET_COMPONENTS.md", "docs/WIDGET_PACKAGES.md",
            "docs/CLI_RUNTIME_CHECKS.md", "docs/DELIVERY.md",
            "docs/DEV_SESSIONS.md", "docs/launcher-badge-counts.md",
            "docs/browser-activity.md", "docs/browser-tabs.md",
        ]
        for path in current_docs:
            text = self.read(path)
            with self.subTest(path=path):
                self.assertNotIn("SmartDock for Omarchy", text)
        self.assertTrue(self.read("README.md").startswith("# Dockrail\n"))
        self.assertIn("dockrail status --json", self.read("README.md"))
        self.assertIn("import Dockrail.WidgetKit 1.0", self.read("docs/WIDGET_PACKAGES.md"))

    def test_retained_compatibility_contracts_remain_literal(self):
        migration = self.read("docs/DOCKRAIL_MIGRATION.md")
        install = self.read("install.sh")
        window_actions = self.read("components/DockWindowActions.qml")
        legacy_qmldir = self.read("SmartDock/WidgetKit/qmldir")
        self.assertIn("io.github.fernandodamaso.smartdock", migration)
        self.assertIn("smartdock-herdr-helper", install)
        self.assertIn("smartdock-herdr-provider", install)
        self.assertIn("special:smartdock-minimized", window_actions)
        self.assertIn("module SmartDock.WidgetKit", legacy_qmldir)

    def test_optional_provider_installers_match_canonical_consumers(self):
        launcher = self.read("scripts/build-launcher-badge-provider")
        browser = self.read("scripts/install-browser-profile-provider")
        self.assertIn('install_dir="$data_home/dockrail/providers"', launcher)
        self.assertIn('install_dir="$data_home/dockrail/providers"', browser)
        self.assertIn("smartdock-launcher-badge-provider", launcher)
        self.assertIn("smartdock-browser-profile-provider", browser)

if __name__ == "__main__":
    unittest.main()
