# SPDX-License-Identifier: Apache-2.0
"""Focus-agent transport: parsers, allowlist, reconciliation reject."""
from __future__ import annotations

import json
import runpy
import sys
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "smartdock-herdr-helper"
PROVIDER = ROOT / "bin" / "smartdock-herdr-provider"
sys.path.insert(0, str(ROOT))

from attachments import (  # noqa: E402
    parse_helper_focus_agent_command,
    parse_provider_focus_agent_command,
)
from model import ServerState  # noqa: E402


class FocusParseTests(unittest.TestCase):
    def test_provider_focus_command_accepts_exact_shape(self):
        raw = json.dumps({
            "kind": "focus-agent",
            "requestId": "focus-1",
            "providerEpoch": "epoch",
            "serverId": "srv",
            "connectionGeneration": 2,
            "agentId": "srv:2:p1",
            "paneId": "p1",
            "terminalId": "t1",
        }).encode()
        self.assertEqual(parse_provider_focus_agent_command(raw), {
            "requestId": "focus-1",
            "providerEpoch": "epoch",
            "serverId": "srv",
            "connectionGeneration": 2,
            "agentId": "srv:2:p1",
            "paneId": "p1",
            "terminalId": "t1",
        })

    def test_provider_focus_command_rejects_extra_fields_and_bad_generation(self):
        base = {
            "kind": "focus-agent",
            "requestId": "focus-1",
            "providerEpoch": "epoch",
            "serverId": "srv",
            "connectionGeneration": 1,
            "agentId": "a",
            "paneId": "p",
            "terminalId": "",
        }
        self.assertIsNone(parse_provider_focus_agent_command(
            json.dumps({**base, "method": "agent.focus"}).encode()))
        self.assertIsNone(parse_provider_focus_agent_command(
            json.dumps({**base, "socket": "/tmp/x"}).encode()))
        self.assertIsNone(parse_provider_focus_agent_command(
            json.dumps({**base, "connectionGeneration": 0}).encode()))
        self.assertIsNone(parse_provider_focus_agent_command(
            json.dumps({**base, "connectionGeneration": 1.5}).encode()))

    def test_helper_focus_command_accepts_pane_only(self):
        raw = b'{"kind":"focus-agent","requestId":"r1","pane_id":"w1:p1"}'
        self.assertEqual(parse_helper_focus_agent_command(raw), {
            "requestId": "r1",
            "pane_id": "w1:p1",
        })
        self.assertIsNone(parse_helper_focus_agent_command(
            b'{"kind":"focus-agent","requestId":"r1","pane_id":"w1:p1","extra":1}'))


class HelperFocusTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(HELPER))

    def test_sanitize_maps_unknown_to_unsupported(self):
        sanitize = self.module["sanitize_focus_error"]
        self.assertEqual(sanitize("timeout"), "timeout")
        self.assertEqual(sanitize("agent_gone"), "agent_gone")
        self.assertEqual(sanitize("raw herdr text"), "unsupported")

    def test_request_allowlist_includes_agent_focus_only(self):
        with patch("socket.socket", side_effect=AssertionError("opened")):
            with self.assertRaises(self.module["ProtocolError"]):
                self.module["request"]("pane.focus", {"target": "p1"})
        self.module["SOCK"] = "/tmp/missing-herdr-sock"
        with self.assertRaises(self.module["ProtocolError"]):
            self.module["request"]("agent.focus", {"target": "p1"})

    def test_run_focus_agent_emits_fixed_action_result(self):
        emitted = []
        globals_dict = self.module["run_focus_agent"].__globals__
        original_emit = globals_dict["emit"]
        original_request = globals_dict["request"]

        def fake_emit(value):
            emitted.append(value)

        try:
            globals_dict["emit"] = fake_emit
            globals_dict["request"] = lambda *a, **k: {"id": "smartdock", "result": {}}
            self.module["run_focus_agent"]({"requestId": "r1", "pane_id": "p1"})
            self.assertEqual(emitted, [{
                "kind": "action-result",
                "requestId": "r1",
                "ok": True,
                "error": "",
            }])

            emitted.clear()
            globals_dict["request"] = lambda *a, **k: (_ for _ in ()).throw(
                self.module["ProtocolError"]("agent_gone"))
            self.module["run_focus_agent"]({"requestId": "r2", "pane_id": "p1"})
            self.assertEqual(emitted[0]["ok"], False)
            self.assertEqual(emitted[0]["error"], "agent_gone")
        finally:
            globals_dict["emit"] = original_emit
            globals_dict["request"] = original_request


class ProviderFocusValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.provider_mod = SourceFileLoader(
            "smartdock_herdr_provider_focus", str(PROVIDER)
        ).load_module()

    def _stub(self):
        class FakeHelper:
            def __init__(self):
                self.commands = []

            def send(self, command):
                self.commands.append(command)
                return True

        class Stub:
            def __init__(inner):
                inner.epoch = "epoch-live"
                inner.results = []
                inner.helpers = {"srv": FakeHelper()}
                inner.states = {
                    "srv": ServerState({
                        "id": "srv",
                        "label": "default",
                        "socket": "/tmp/x",
                        "session": "default",
                        "kind": "default",
                        "capabilities": {"focusAgent": True},
                    })
                }
                state = inner.states["srv"]
                state.connected = True
                state.generation = 3
                state.snapshot = {
                    "panes": [{"pane_id": "p1", "terminal_id": "t1"}],
                    "agents": [{
                        "pane_id": "p1",
                        "terminal_id": "t1",
                        "agent": "codex",
                        "agent_status": "idle",
                    }],
                }
                state.error = ""

            def emit_action_result(inner, request_id, ok, error=""):
                inner.results.append((request_id, ok, error))

        stub = Stub()
        stub.apply_focus_agent = self.provider_mod.Provider.apply_focus_agent.__get__(
            stub, Stub)
        return stub

    def test_apply_focus_rejects_reconciling_and_stale_identity(self):
        stub = self._stub()
        agent_id = "srv:3:p1"
        base = {
            "providerEpoch": "epoch-live",
            "serverId": "srv",
            "connectionGeneration": 3,
            "agentId": agent_id,
            "paneId": "p1",
            "terminalId": "t1",
        }

        stub.apply_focus_agent({**base, "requestId": "r1", "providerEpoch": "other"})
        self.assertEqual(stub.results[-1], ("r1", False, "identity_mismatch"))

        stub.states["srv"].snapshot_due = 999.0
        stub.apply_focus_agent({**base, "requestId": "r2"})
        # snapshot_due no longer blocks; agent still validates and routes to helper.
        self.assertEqual(stub.helpers["srv"].commands[-1], json.dumps({
            "kind": "focus-agent",
            "requestId": "r2",
            "pane_id": "p1",
        }, separators=(",", ":")))
        stub.states["srv"].snapshot_due = None
        stub.helpers["srv"].commands.clear()

        stub.apply_focus_agent({**base, "requestId": "r3", "connectionGeneration": 99})
        self.assertEqual(stub.results[-1], ("r3", False, "identity_mismatch"))

        stub.apply_focus_agent({**base, "requestId": "r4", "agentId": "missing"})
        self.assertEqual(stub.results[-1], ("r4", False, "agent_gone"))

        stub.apply_focus_agent({**base, "requestId": "r5"})
        self.assertEqual(stub.helpers["srv"].commands[-1], json.dumps({
            "kind": "focus-agent",
            "requestId": "r5",
            "pane_id": "p1",
        }, separators=(",", ":")))
        self.assertFalse(any(r[0] == "r5" for r in stub.results))

    def test_apply_focus_rejects_missing_capability_before_forwarding(self):
        stub = self._stub()
        stub.states["srv"].info.pop("capabilities", None)
        stub.apply_focus_agent({
            "requestId": "missing-capability",
            "providerEpoch": "epoch-live",
            "serverId": "srv",
            "connectionGeneration": 3,
            "agentId": "srv:3:p1",
            "paneId": "p1",
            "terminalId": "t1",
        })
        self.assertEqual(
            stub.results[-1], ("missing-capability", False, "unsupported")
        )
        self.assertEqual(stub.helpers["srv"].commands, [])

    def test_supported_remote_fixture_preserves_exact_focus_identity(self):
        stub = self._stub()
        stub.states["srv"].info["transport"] = "remote"
        stub.states["srv"].info["host"] = "devbox"
        stub.states["srv"].info["capabilities"] = {"focusAgent": True}
        stub.apply_focus_agent({
            "requestId": "remote-supported",
            "providerEpoch": "epoch-live",
            "serverId": "srv",
            "connectionGeneration": 3,
            "agentId": "srv:3:p1",
            "paneId": "p1",
            "terminalId": "t1",
        })
        self.assertEqual(stub.helpers["srv"].commands[-1], json.dumps({
            "kind": "focus-agent",
            "requestId": "remote-supported",
            "pane_id": "p1",
        }, separators=(",", ":")))
        self.assertFalse(any(r[0] == "remote-supported" for r in stub.results))


if __name__ == "__main__":
    unittest.main()
