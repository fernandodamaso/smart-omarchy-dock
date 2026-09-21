# SPDX-License-Identifier: Apache-2.0
# Adapted from njpatel/omaherdr tests/test_events.py at c20d9b0db3a65b5a7590876c56026bc906306e04.
# Modified for SmartDock, 2026-09-18: exercise the extracted read-only helper,
# subscription replacement, malformed input, reconnection and shutdown.
# See ../UPSTREAM.md and ../LICENSE.omaherdr.
import copy
import json
import os
from pathlib import Path
import queue
import selectors
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "smartdock-herdr-helper"


class LiveOnlyServer:
    """Real Unix socket fixture; subscriptions intentionally have no replay."""

    def __init__(self, change_during_snapshot=False, malformed_first=False):
        self.change_during_snapshot = change_during_snapshot
        self.malformed_first = malformed_first
        self.requests = []
        self.subscribers = []
        self.errors = queue.Queue()
        self.lock = threading.Lock()
        self.state = {
            "workspaces": [{"workspace_id": "w1", "label": "Fixture"}],
            "tabs": [{"tab_id": "w1:t1", "workspace_id": "w1"}],
            "panes": [{"pane_id": "w1:p1", "terminal_id": "t1"}],
            "agents": [],
        }

    def __enter__(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = str(Path(self.directory.name) / "herdr.sock")
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(self.path)
        self.listener.listen()
        self.listener.settimeout(0.05)
        self.stopping = threading.Event()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.stopping.set()
        self.listener.close()
        self.thread.join(timeout=2)
        for connection in self.subscribers:
            connection.close()
        self.directory.cleanup()
        if self.thread.is_alive():
            raise AssertionError("fake server did not stop")
        if not self.errors.empty():
            raise self.errors.get()

    def publish(self, event):
        payload = (json.dumps(event) + "\n").encode()
        with self.lock:
            for connection in self.subscribers:
                try:
                    connection.sendall(payload)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass

    def disconnect(self):
        with self.lock:
            for connection in self.subscribers:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                connection.close()
            self.subscribers.clear()

    def serve(self):
        try:
            while not self.stopping.is_set():
                try:
                    connection, _ = self.listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if self.stopping.is_set():
                        return
                    raise
                retained = False
                try:
                    connection.settimeout(2)
                    with connection.makefile("rb") as stream:
                        request = json.loads(stream.readline(1024 * 1024))
                    self.requests.append(request)
                    method = request["method"]
                    if method == "events.subscribe":
                        with self.lock:
                            self.subscribers.append(connection)
                        retained = True
                        response = {"id": request["id"], "result": {"type": "subscription_started"}}
                    elif method == "session.snapshot":
                        if self.malformed_first:
                            self.malformed_first = False
                            connection.sendall(b'["secret fixture error"]\n')
                            continue
                        response = {"id": request["id"], "result": {"snapshot": copy.deepcopy(self.state)}}
                        if self.change_during_snapshot:
                            self.change_during_snapshot = False
                            self.state["workspaces"].append({"workspace_id": "w2"})
                            self.state["panes"].append({"pane_id": "w2:p1"})
                            self.publish({"event": "workspace_created", "data": {"workspace_id": "w2"}})
                    else:
                        raise AssertionError("unexpected socket method: " + method)
                    connection.sendall((json.dumps(response) + "\n").encode())
                except (BrokenPipeError, ConnectionResetError):
                    pass
                finally:
                    if not retained:
                        connection.close()
        except Exception as error:
            self.errors.put(error)


class HelperProcess:
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        self.process = subprocess.Popen(
            [sys.executable, "-B", str(HELPER), self.path],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""
        self.messages = []
        return self

    def send(self, line):
        self.process.stdin.write(line + b"\n")
        self.process.stdin.flush()

    def until(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                message = json.loads(line)
                self.messages.append(message)
                if predicate(message):
                    return message
            if not self.selector.select(max(0, deadline - time.monotonic())):
                break
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                break
            self.buffer += chunk
        raise AssertionError("expected helper message not received: " + repr(self.messages))

    def __exit__(self, *args):
        try:
            if self.process.poll() is None and not self.process.stdin.closed:
                self.send(b"quit")
            self.process.wait(timeout=3)
        except (subprocess.TimeoutExpired, BrokenPipeError):
            self.process.kill()
            self.process.wait(timeout=2)
            if args[0] is None:
                raise AssertionError("helper failed to exit cleanly")
        finally:
            self.selector.close()
            self.stderr = self.process.stderr.read()
            for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
                stream.close()
        if args[0] is None and self.stderr:
            raise AssertionError("helper leaked diagnostics: " + repr(self.stderr))


def snapshot_ok(message):
    return message.get("kind") == "snapshot" and message.get("ok") is True


class EventTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(HELPER.is_file(), "SmartDock-owned helper is not scaffolded")

    def test_workspace_change_during_initial_snapshot_reaches_consumer(self):
        with LiveOnlyServer(change_during_snapshot=True) as server, HelperProcess(server.path) as helper:
            helper.until(lambda message: snapshot_ok(message) and any(
                row["workspace_id"] == "w2" for row in message["snapshot"].get("workspaces", [])))
            # A snapshot is emitted before subscription replacement is acknowledged.
            helper.until(lambda message: message.get("kind") == "status" and message.get("connected"))
            self.assertEqual(server.requests[0]["method"], "events.subscribe")
            self.assertGreaterEqual(sum(r["method"] == "session.snapshot" for r in server.requests), 2)
            subscriptions = [r for r in server.requests if r["method"] == "events.subscribe"]
            self.assertIn({"type": "pane.agent_status_changed", "pane_id": "w2:p1"},
                          subscriptions[-1]["params"]["subscriptions"])

    def test_status_event_is_forwarded_without_waiting_for_a_snapshot(self):
        with LiveOnlyServer() as server, HelperProcess(server.path) as helper:
            helper.until(lambda message: message.get("kind") == "status" and message.get("connected"))
            for status in ("blocked", "working", "done", "idle", "unknown"):
                server.publish({"event": "pane.agent_status_changed",
                                "data": {"pane_id": "w1:p1", "agent_status": status}})
                event = helper.until(lambda message: message.get("kind") == "event")
                self.assertEqual(event["data"]["agent_status"], status)

    def test_arbitrary_rpc_and_focus_commands_never_reach_herdr(self):
        with LiveOnlyServer() as server, HelperProcess(server.path) as helper:
            helper.until(snapshot_ok)
            helper.send(b'rpc {"method":"pane.focus","params":{"pane_id":"w1:p1"}}')
            helper.until(lambda message: message.get("error") == "unsupported_command")
            helper.send(b"snapshot")
            helper.until(snapshot_ok)
            self.assertTrue(all(r["method"] in ("session.snapshot", "events.subscribe") for r in server.requests))

    def test_malformed_snapshot_recovers_without_echoing_input(self):
        with LiveOnlyServer(malformed_first=True) as server, HelperProcess(server.path) as helper:
            helper.until(lambda message: message.get("kind") == "snapshot" and message.get("ok") is False)
            helper.until(snapshot_ok)
            self.assertNotIn("secret fixture error", json.dumps(helper.messages))

    def test_disconnect_marks_unavailable_then_resubscribes(self):
        with LiveOnlyServer() as server, HelperProcess(server.path) as helper:
            helper.until(lambda message: message.get("kind") == "status" and message.get("connected"))
            # Drain the reconciliation snapshot before interrupting the stream.
            helper.until(snapshot_ok)
            server.disconnect()
            helper.until(lambda message: message.get("kind") == "status" and message.get("connected") is False)
            helper.until(snapshot_ok)

    def test_stdin_eof_stops_without_stopping_server(self):
        with LiveOnlyServer() as server, HelperProcess(server.path) as helper:
            helper.until(snapshot_ok)
            helper.process.stdin.close()
            self.assertEqual(helper.process.wait(timeout=2), 0)
            self.assertTrue(server.thread.is_alive())

    def test_requires_explicit_socket_instead_of_guessing_a_session(self):
        result = subprocess.run([sys.executable, "-B", str(HELPER)], capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"socket", result.stderr.lower())


    def test_sigterm_stops_the_helper_without_stopping_the_server(self):
        with LiveOnlyServer() as server, HelperProcess(server.path) as helper:
            helper.until(snapshot_ok)
            helper.process.terminate()
            self.assertEqual(helper.process.wait(timeout=2), 0)
            self.assertTrue(server.thread.is_alive())

    def test_oversized_command_is_rejected_without_echoing_it(self):
        with LiveOnlyServer() as server, HelperProcess(server.path) as helper:
            helper.until(snapshot_ok)
            helper.send(b"secret" * 1000)
            helper.until(lambda message: message.get("error") == "command_too_large")
            self.assertEqual(helper.process.wait(timeout=2), 0)
            self.assertNotIn("secret", json.dumps(helper.messages))

    def test_slow_output_consumer_does_not_pin_the_helper(self):
        with LiveOnlyServer() as server:
            server.state["panes"] = [{"pane_id": "w1:p" + str(index), "label": "x" * 256}
                                     for index in range(2048)]
            with HelperProcess(server.path) as helper:
                # Deliberately do not drain stdout: the bounded writer must exit.
                self.assertEqual(helper.process.wait(timeout=5), 0)

if __name__ == "__main__":
    unittest.main()
