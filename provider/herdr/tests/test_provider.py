# SPDX-License-Identifier: Apache-2.0
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / "bin" / "smartdock-herdr-provider"


class ProviderProcessTests(unittest.TestCase):
    def test_process_discovers_supervises_publishes_refreshes_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            home = root / "home"
            home.mkdir()
            marker = root / "helper-stopped"
            socket_path = root / "herdr.sock"

            herdr = bin_dir / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "printf 'NAME  STATUS  PID  SOCKET\\ndefault  running  1  %s\\n' "
                "\"$FAKE_SOCKET\"\n"
            )
            herdr.chmod(0o755)

            helper = root / "fake-helper.py"
            helper.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "snapshot={\"kind\":\"snapshot\",\"ok\":True,\"snapshot\":"
                "{\"panes\":[{\"pane_id\":\"p1\"}],\"agents\":[{\"pane_id\":\"p1\","
                "\"agent\":\"codex\",\"agent_status\":\"working\","
                "\"state_change_seq\":\"18446744073709551615\"}]}}\n"
                "def emit(value): print(json.dumps(value), flush=True)\n"
                "emit(snapshot); emit({\"kind\":\"status\",\"connected\":True})\n"
                "for line in sys.stdin:\n"
                " command=line.strip()\n"
                " if command == \"snapshot\": emit(snapshot)\n"
                " elif command == \"quit\":\n"
                "  open(os.environ[\"FAKE_HELPER_MARKER\"],\"w\").write(\"stopped\")\n"
                "  break\n"
            )
            helper.chmod(0o755)

            env = dict(os.environ)
            env.update({
                "HOME": str(home),
                "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
                "FAKE_SOCKET": str(socket_path),
                "FAKE_HELPER_MARKER": str(marker),
            })
            process = subprocess.Popen(
                [sys.executable, "-B", str(PROVIDER), "--helper", str(helper)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            self.addCleanup(lambda: process.poll() is None and process.kill())
            assert process.stdin is not None and process.stdout is not None
            assert process.stderr is not None

            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            messages = []
            buffer = b""

            def wait_for(predicate, timeout=5):
                nonlocal buffer
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        value = json.loads(line)
                        messages.append(value)
                        if predicate(value):
                            return value
                    ready = selector.select(max(0, deadline - time.monotonic()))
                    if not ready:
                        break
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    buffer += chunk
                self.fail(f"provider condition not reached: {messages!r}")

            ready = wait_for(
                lambda value: (value.get("liveCounts") or {}).get("agents") == 1
            )
            self.assertEqual(ready["schemaVersion"], 1)
            self.assertFalse(ready["capabilities"]["remote"])
            self.assertEqual(
                ready["agents"][0]["stateChangeSeq"],
                str(2 ** 64 - 1),
            )

            first_revision = ready["revision"]
            process.stdin.write(b"refresh\n")
            process.stdin.flush()
            refreshed = wait_for(
                lambda value: value.get("revision", 0) > first_revision
            )
            self.assertGreater(refreshed["revision"], first_revision)

            process.stdin.write(b"quit\n")
            process.stdin.flush()
            self.assertEqual(
                process.wait(timeout=4),
                0,
                process.stderr.read().decode(),
            )
            selector.close()
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
            self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
