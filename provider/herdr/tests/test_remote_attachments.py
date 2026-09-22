# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from attachments import (  # noqa: E402
    AttachmentSpec,
    classify_tui_attachment,
    parse_remote_bridge_executable,
)


class RemoteAttachmentClassifierTests(unittest.TestCase):
    def test_local_and_remote_tui_forms_are_distinct(self):
        self.assertEqual(classify_tui_attachment(["herdr"]), AttachmentSpec("local"))
        self.assertEqual(
            classify_tui_attachment(["herdr", "--session", "work"]),
            AttachmentSpec("local", "work", None),
        )
        self.assertEqual(
            classify_tui_attachment(["herdr", "session", "attach", "work"]),
            AttachmentSpec("local", "work", None),
        )
        self.assertEqual(
            classify_tui_attachment(["herdr", "--remote", "notebook"]),
            AttachmentSpec("remote", "default", "notebook"),
        )
        self.assertEqual(
            classify_tui_attachment([
                "herdr", "--remote=notebook", "--session=work",
                "--remote-keybindings", "server",
            ]),
            AttachmentSpec("remote", "work", "notebook"),
        )

    def test_controls_help_handoff_and_unsafe_targets_fail_closed(self):
        cases = [
            ["herdr", "--help"],
            ["herdr", "-V"],
            ["herdr", "server"],
            ["herdr", "client"],
            ["herdr", "status"],
            ["herdr", "--handoff"],
            ["herdr", "--remote-keybindings", "server"],
            ["herdr", "--remote", "-oProxyCommand=id"],
            ["herdr", "--remote", "host name"],
            ["herdr", "--remote", "host", "--remote", "other"],
            ["herdr", "--remote", "host", "--remote-keybindings", "invalid"],
        ]
        for argv in cases:
            self.assertIsNone(classify_tui_attachment(argv), argv)

    def test_remote_target_shell_metacharacters_stay_data(self):
        target = "host;$(echo-no)"
        self.assertEqual(
            classify_tui_attachment(["herdr", "--remote", target]),
            AttachmentSpec("remote", "default", target),
        )

    def test_bridge_executable_is_recovered_from_fixed_remote_bridge_shape(self):
        argv = [
            "ssh", "-S", "/tmp/control", "host",
            "printf '\\n%s\\n' marker\nexec '/opt/Herdr Bin/herdr' --session work remote-client-bridge",
        ]
        self.assertEqual(parse_remote_bridge_executable(argv), "/opt/Herdr Bin/herdr")
        self.assertEqual(
            parse_remote_bridge_executable([
                "ssh", "host", "exec \"$HOME/.local/bin/herdr\" remote-client-bridge"
            ]),
            "$HOME/.local/bin/herdr",
        )

    def test_bridge_executable_rejects_path_lookup_and_unrelated_ssh(self):
        self.assertIsNone(parse_remote_bridge_executable(
            ["ssh", "host", "exec herdr remote-client-bridge"]
        ))
        self.assertIsNone(parse_remote_bridge_executable(["ssh", "host", "uname", "-a"]))


if __name__ == "__main__":
    unittest.main()
