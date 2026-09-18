# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model import MAX_AGENTS, ServerState, normalized_snapshot


def state(name="default"):
    return ServerState({
        "id": "local-test",
        "session": name,
        "sessions": [name],
        "label": name,
        "socket": "/tmp/private.sock",
    })


def connect(server, agents, now=10.0):
    server.apply_status({"connected": True})
    server.apply_snapshot({
        "ok": True,
        "snapshot": {"panes": [], "agents": agents},
    }, now)
    server.apply_status({"connected": True})


class ModelTests(unittest.TestCase):
    def test_all_statuses_and_attention_share_one_live_inventory(self):
        server = state()
        statuses = ("blocked", "done", "working", "idle", "unknown")
        connect(server, [
            {"pane_id": f"p{i}", "agent": "codex", "agent_status": status}
            for i, status in enumerate(statuses)
        ])
        snap = normalized_snapshot("epoch", 1, [server], now=12)
        self.assertEqual(snap["liveCounts"]["agents"], 5)
        for status in statuses:
            self.assertEqual(snap["liveCounts"][status], 1)
        self.assertEqual(
            [row["status"] for row in snap["attention"]],
            ["blocked", "done"],
        )
        self.assertEqual(snap["completeness"]["state"], "complete")

    def test_connected_empty_is_zero_but_disconnected_is_unknown(self):
        server = state()
        connect(server, [])
        snap = normalized_snapshot("e", 1, [server], now=11)
        self.assertEqual(snap["liveCounts"]["agents"], 0)
        server.apply_status({"connected": False})
        snap = normalized_snapshot("e", 2, [server], now=12)
        self.assertIsNone(snap["liveCounts"])
        self.assertEqual(snap["agents"], [])
        self.assertEqual(snap["completeness"]["state"], "unknown")

    def test_partial_server_set_never_claims_exact_overall_totals(self):
        live = state("one")
        missing = ServerState({
            "id": "local-two", "session": "two",
            "sessions": ["two"], "socket": "/tmp/two",
        })
        connect(live, [{"pane_id": "p1", "agent_status": "working"}])
        snap = normalized_snapshot("e", 1, [live, missing], now=12)
        self.assertEqual(snap["liveCounts"]["agents"], 1)
        self.assertFalse(snap["liveCounts"]["complete"])
        self.assertEqual(snap["completeness"]["state"], "partial")

    def test_status_event_updates_immediately_and_disconnect_kills_stale_counts(self):
        server = state()
        connect(server, [{"pane_id": "p1", "agent_status": "blocked"}], now=10)
        server.apply_event({
            "event": "pane.agent_status_changed",
            "data": {"pane_id": "p1", "agent_status": "working"},
        }, 11)
        snap = normalized_snapshot("e", 1, [server], now=12)
        self.assertEqual(snap["agents"][0]["status"], "working")
        self.assertAlmostEqual(server.snapshot_due, 11.25)
        server.apply_status({"connected": False})
        self.assertIsNone(normalized_snapshot("e", 2, [server], now=13)["liveCounts"])

    def test_disconnect_scopes_reused_pane_to_new_connection_generation(self):
        server = state()
        connect(server, [{"pane_id": "p1", "agent_status": "done"}], now=10)
        first = normalized_snapshot("e", 1, [server], now=10)["agents"][0]["id"]
        server.apply_status({"connected": False})
        self.assertEqual(server.generation, 2)
        connect(server, [{"pane_id": "p1", "agent_status": "blocked"}], now=20)
        second = normalized_snapshot("e", 2, [server], now=20)["agents"][0]["id"]
        self.assertNotEqual(first, second)
        self.assertTrue(second.endswith(":2:p1"))

    def test_sequence_is_lossless_and_private_socket_is_not_published(self):
        server = state()
        connect(server, [{
            "pane_id": "p1",
            "terminal_id": "t1",
            "state_change_seq": str(2 ** 64 - 1),
            "agent_status": "idle",
        }])
        snap = normalized_snapshot("e", 1, [server], now=11)
        self.assertEqual(snap["agents"][0]["stateChangeSeq"], str(2 ** 64 - 1))
        self.assertEqual(snap["agents"][0]["terminalId"], "t1")
        self.assertNotIn("socket", str(snap))

    def test_agent_cap_is_explicit(self):
        server = state()
        connect(server, [
            {"pane_id": f"p{i}", "agent_status": "working"}
            for i in range(MAX_AGENTS + 10)
        ])
        snap = normalized_snapshot("e", 1, [server], now=11)
        self.assertEqual(len(snap["agents"]), MAX_AGENTS)
        self.assertTrue(snap["completeness"]["truncated"])
        self.assertFalse(snap["liveCounts"]["complete"])

    def test_missing_agents_collection_is_unknown_not_observed_empty(self):
        server = state()
        server.apply_status({"connected": True})
        server.apply_snapshot({"ok": True, "snapshot": {"panes": []}}, 10)
        server.apply_status({"connected": True})
        snap = normalized_snapshot("e", 1, [server], now=11)
        self.assertIsNone(snap["liveCounts"])
        self.assertEqual(snap["completeness"]["state"], "partial")


if __name__ == "__main__":
    unittest.main()
