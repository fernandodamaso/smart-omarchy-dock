# SPDX-License-Identifier: Apache-2.0
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from discovery import Discovery, RunResult, endpoint_id, parse_session_list


class DiscoveryTests(unittest.TestCase):
    def test_aliases_are_deduplicated_by_resolved_socket(self):
        with tempfile.TemporaryDirectory() as home:
            sock = os.path.join(home, ".config/herdr/shared.sock")
            text = (
                "NAME  STATUS  PID  SOCKET\n"
                f"default  running  1  {sock}\n"
                f"work  running  2  {sock}\n"
            )
            discovery = Discovery(
                runner=lambda *_: RunResult(True, text),
                home=home,
                exists=lambda _: False,
            )
            servers, error = discovery.scan()
            self.assertEqual(error, "")
            self.assertEqual(len(servers), 1)
            self.assertEqual(servers[0]["sessions"], ["default", "work"])
            self.assertEqual(servers[0]["id"], endpoint_id(os.path.realpath(sock)))

    def test_documented_named_socket_is_visible_without_cli_metadata(self):
        with tempfile.TemporaryDirectory() as home:
            path = Path(home, ".config/herdr/sessions/work/herdr.sock")
            path.parent.mkdir(parents=True)
            path.touch()
            discovery = Discovery(
                runner=lambda *_: RunResult(False, error="command_unavailable"),
                home=home,
            )
            servers, error = discovery.scan()
            self.assertEqual(error, "")
            self.assertEqual(len(servers), 1)
            self.assertEqual(servers[0]["sessions"], ["work"])
            self.assertEqual(servers[0]["socket"], os.path.realpath(path))

    def test_failed_metadata_can_use_default_socket_only(self):
        with tempfile.TemporaryDirectory() as home:
            default = os.path.realpath(os.path.join(home, ".config/herdr/herdr.sock"))
            discovery = Discovery(
                runner=lambda *_: RunResult(False, error="command_unavailable"),
                home=home,
                exists=lambda path: path == default,
            )
            servers, error = discovery.scan()
            self.assertEqual(error, "")
            self.assertEqual([row["session"] for row in servers], ["default"])

    def test_unresolved_named_session_never_falls_back_to_default(self):
        with tempfile.TemporaryDirectory() as home:
            default = os.path.realpath(os.path.join(home, ".config/herdr/herdr.sock"))
            missing = os.path.join(home, ".config/herdr/sessions/named/herdr.sock")
            text = f"NAME  STATUS  PID  SOCKET\nnamed  stopped  -  {missing}\n"
            discovery = Discovery(
                runner=lambda *_: RunResult(True, text),
                home=home,
                exists=lambda path: path == default,
            )
            servers, _ = discovery.scan()
            self.assertEqual(servers[0]["sessions"], ["default"])
            self.assertNotIn("named", servers[0]["sessions"])

    def test_bad_session_or_relative_socket_is_rejected(self):
        text = (
            "NAME  STATUS  PID  SOCKET\n"
            "bad name  running  1  /tmp/a.sock\n"
            "relative  running  2  relative.sock\n"
        )
        self.assertEqual(parse_session_list(text), {})

    def test_fingerprint_detects_new_named_socket_without_running_metadata(self):
        with tempfile.TemporaryDirectory() as home:
            calls = []
            sessions = Path(home, ".config/herdr/sessions")
            sessions.mkdir(parents=True)
            discovery = Discovery(
                runner=lambda *args: calls.append(args) or RunResult(True, ""),
                home=home,
            )
            self.assertFalse(discovery.changed())
            named = sessions / "work"
            named.mkdir()
            discovery.last_fingerprint = discovery.fingerprint()
            (named / "herdr.sock").touch()
            self.assertTrue(discovery.changed())
            self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
