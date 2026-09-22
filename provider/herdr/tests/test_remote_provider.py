# SPDX-License-Identifier: Apache-2.0
from importlib.machinery import SourceFileLoader
from pathlib import Path
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / "bin" / "smartdock-herdr-provider"
import sys
sys.path.insert(0, str(ROOT))

from model import ServerState, normalized_snapshot  # noqa: E402
from remote import RemoteResolution, attachment_key  # noqa: E402


class FakePool:
    def __init__(self):
        self.submitted = []
        self.results = []
        self.closed = False

    def submit(self, *args):
        self.submitted.append(args)
        return True

    def poll(self):
        rows, self.results = self.results, []
        return rows

    def close(self):
        self.closed = True


class RemoteProviderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = SourceFileLoader("smartdock_herdr_provider_remote", str(PROVIDER)).load_module()

    def provider(self):
        pool = FakePool()
        provider = self.mod.Provider(Path("/tmp/helper"), remote_pool=pool)
        return provider, pool

    @staticmethod
    def group(target, session="default", pid=10, executable="/opt/herdr"):
        key = attachment_key(target, session)
        return key, {
            "target": target,
            "session": session,
            "herdrExecutable": executable,
            "clients": [{"pid": pid, "startTime": pid + 100, "ancestors": []}],
        }

    def test_pending_attachment_removal_obsoletes_late_resolution(self):
        provider, pool = self.provider()
        key, spec = self.group("remote-a")
        provider.reconcile_remote_attachments({key: spec})
        self.assertEqual(len(pool.submitted), 1)
        token = provider.remote_tokens[key]
        pending = provider.remote_pending_ids[key]
        self.assertIn(pending, provider.states)

        provider.reconcile_remote_attachments({})
        self.assertNotIn(key, provider.remote_specs)
        self.assertNotIn(pending, provider.states)
        provider.apply_remote_resolution(
            key,
            token,
            RemoteResolution(
                True,
                socket="/home/u/.config/herdr/herdr.sock",
                executable="/opt/herdr",
                authority="0123456789abcdef0123456789abcdef",
            ),
        )
        self.assertFalse(provider.remote_bindings)
        self.assertFalse(any(
            state.info.get("transport") == "remote" for state in provider.states.values()
        ))
        provider.shutdown()

    def test_aliases_proven_same_remote_socket_dedupe_to_one_helper_state(self):
        provider, pool = self.provider()
        provider.start_helper = lambda *_args, **_kwargs: None
        key_a, spec_a = self.group("alias-a", pid=10)
        key_b, spec_b = self.group("alias-b", pid=20)
        provider.reconcile_remote_attachments({key_a: spec_a, key_b: spec_b})
        tokens = dict(provider.remote_tokens)
        resolution = RemoteResolution(
            True,
            socket="/home/u/.config/herdr/herdr.sock",
            executable="/opt/herdr",
            authority="0123456789abcdef0123456789abcdef",
        )
        provider.apply_remote_resolution(key_a, tokens[key_a], resolution)
        provider.apply_remote_resolution(key_b, tokens[key_b], resolution)
        self.assertEqual(provider.remote_bindings[key_a], provider.remote_bindings[key_b])
        state = provider.states[provider.remote_bindings[key_a]]
        self.assertEqual(state.info["transport"], "remote")
        self.assertFalse(state.info["capabilities"]["focusAgent"])
        self.assertEqual(len(state.clients), 2)
        provider.shutdown()

    def test_failed_remote_endpoint_keeps_local_live_counts_but_marks_partial(self):
        provider, _pool = self.provider()
        local = ServerState({
            "id": "local-one",
            "transport": "local",
            "host": "local",
            "session": "default",
            "sessions": ["default"],
            "socket": "/tmp/local.sock",
            "capabilities": {"focusAgent": True},
        })
        local.apply_status({"connected": True})
        local.apply_snapshot({
            "ok": True,
            "snapshot": {
                "panes": [{"pane_id": "p1"}],
                "agents": [{"pane_id": "p1", "agent_status": "working"}],
            },
        }, time.monotonic())
        local.apply_status({"connected": True})
        provider.states[local.id] = local

        key, spec = self.group("remote-b", executable=None)
        provider.reconcile_remote_attachments({key: spec})
        snap = normalized_snapshot("epoch", 1, list(provider.states.values()))
        self.assertEqual(snap["liveCounts"]["agents"], 1)
        self.assertFalse(snap["liveCounts"]["complete"])
        self.assertEqual(snap["completeness"]["state"], "partial")
        provider.shutdown()

    def test_remote_focus_is_rejected_before_helper_forwarding(self):
        provider, _pool = self.provider()
        state = ServerState({
            "id": "remote-one",
            "transport": "remote",
            "host": "remote-a",
            "session": "default",
            "sessions": ["default"],
            "socket": "/remote/herdr.sock",
            "capabilities": {"focusAgent": False},
        })
        provider.states[state.id] = state
        replies = []
        provider.emit_action_result = lambda request_id, ok, error="": replies.append(
            (request_id, ok, error)
        )
        provider.apply_focus_agent({
            "requestId": "focus-1",
            "providerEpoch": provider.epoch,
            "serverId": state.id,
            "connectionGeneration": state.generation,
            "agentId": "anything",
            "paneId": "p",
            "terminalId": "",
        })
        self.assertEqual(replies, [("focus-1", False, "unsupported")])
        provider.shutdown()

    def test_remote_queue_lane_cannot_consume_local_reserve(self):
        queue = self.mod.BoundedQueue(max_bytes=1024)
        self.assertTrue(queue.put_data(("remote", 1), 512, "remote-1", "remote"))
        self.assertFalse(queue.put_data(("remote", 2), 1, "remote-1", "remote"))
        self.assertTrue(queue.put_data(("local", 1), 512, "local-1", "local"))
        self.assertEqual(queue.get_nowait(), ("remote", 1))
        self.assertEqual(queue.get_nowait(), ("local", 1))

    def test_expired_remote_probe_invalidates_generation_and_reconnects(self):
        provider, _pool = self.provider()
        state = ServerState({
            "id": "remote-one",
            "transport": "remote",
            "host": "remote-a",
            "session": "default",
            "sessions": ["default"],
            "socket": "/remote/herdr.sock",
            "capabilities": {"focusAgent": False},
        })
        state.apply_status({"connected": True})
        state.apply_snapshot({"ok": True, "snapshot": {"panes": [], "agents": []}}, time.monotonic())
        state.apply_status({"connected": True})
        provider.states[state.id] = state
        provider.backoff[state.id] = 1.0

        class HungHelper:
            def __init__(self):
                self.aborted = False
            def flush(self):
                pass
            def abort(self):
                self.aborted = True

        helper = HungHelper()
        provider.helpers[state.id] = helper
        provider.remote_probe_deadline[state.id] = time.monotonic() - 1
        before = state.generation
        provider.maintenance()
        self.assertTrue(helper.aborted)
        self.assertGreater(state.generation, before)
        self.assertFalse(state.connected)
        self.assertIn(state.id, provider.restart_at)
        provider.shutdown()


if __name__ == "__main__":
    unittest.main()
