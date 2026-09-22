# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from unittest import mock
import json
import subprocess
import sys
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "smartdock-herdr-helper"
sys.path.insert(0, str(ROOT))

import remote  # noqa: E402
from remote import (  # noqa: E402
    HELPER_LEASE_RENEW_EVERY,
    HELPER_OWNER_LEASE_SECONDS,
    MAX_RESOLVER_WORKERS,
    REMOTE_PROBE_TIMEOUT,
    RemoteResolution,
    RemoteResolverPool,
    endpoint_id,
    helper_ssh_argv,
    parse_resolution_output,
    resolver_ssh_argv,
    resolve_remote_endpoint,
    valid_remote_target,
)


class RemoteTransportTests(unittest.TestCase):
    def test_target_validation_is_bounded_and_shell_agnostic(self):
        for value in ("notebook", "user@host", "host;echo-no", "host$(echo-no)", "[::1]"):
            self.assertTrue(valid_remote_target(value), value)
        for value in ("", "-oProxyCommand=x", "host name", "host\nname", "\0host", "x" * 256):
            self.assertFalse(valid_remote_target(value), repr(value))
        self.assertFalse(valid_remote_target("é" * 128), "UTF-8 byte bound must apply")

    def test_resolver_ssh_contract_and_encoded_dynamic_values(self):
        target = "host;echo-no"
        executable = "/opt/Herdr $Build;1/herdr"
        argv = resolver_ssh_argv(target, "work", executable)
        self.assertEqual(argv[:1], ["ssh"])
        for option in (
            "BatchMode=yes",
            "ConnectTimeout=8",
            "ServerAliveInterval=15",
            "ServerAliveCountMax=3",
        ):
            self.assertIn(option, argv)
        marker = argv.index("--")
        self.assertEqual(argv[marker + 1], target)
        command = argv[marker + 2]
        self.assertNotIn(executable, command)
        self.assertNotIn("work", command)
        self.assertNotIn(target, command)

    def test_helper_bootstrap_encodes_opaque_socket_path(self):
        target = "user@remote"
        socket_path = "/tmp/herdr $x; 'quoted' \"double\".sock"
        argv = helper_ssh_argv(target, socket_path, b"print('helper')")
        marker = argv.index("--")
        self.assertEqual(argv[marker + 1], target)
        command = argv[marker + 2]
        self.assertNotIn(socket_path, command)
        self.assertNotIn("$x", command)
        self.assertNotIn("; 'quoted'", command)

    def test_session_metacharacters_are_rejected_before_bootstrap(self):
        for session in ("work space", "work;touch", "work$(id)", "'work'"):
            with self.assertRaises(ValueError):
                resolver_ssh_argv("host", session, "/opt/herdr")

    def test_resolution_does_not_canonicalize_remote_paths_locally(self):
        raw = json.dumps({
            "ok": True,
            "socket": "/remote/home/a/../a/.config/herdr/herdr.sock",
            "executable": "/remote/home/a/bin/herdr",
            "authority": "0123456789abcdef0123456789abcdef",
        }).encode()
        with mock.patch.object(remote.os.path, "realpath", side_effect=AssertionError("local realpath")):
            result = parse_resolution_output(raw, "host")
        self.assertTrue(result.ok)
        self.assertEqual(result.socket, "/remote/home/a/../a/.config/herdr/herdr.sock")

    def test_named_session_failure_never_falls_back_to_default(self):
        seen = []

        def runner(argv, **_kwargs):
            seen.append(argv)
            return True, b'{"ok":false,"error":"remote_session_unavailable"}\n'

        result = resolve_remote_endpoint("host", "work", "/opt/herdr", runner=runner)
        self.assertFalse(result.ok)
        self.assertEqual(result.error, "remote_session_unavailable")
        self.assertEqual(len(seen), 1)

    def test_ssh_failure_is_endpoint_local_unavailable(self):
        def runner(_argv, **_kwargs):
            return False, b""

        result = resolve_remote_endpoint("host", "default", "/opt/herdr", runner=runner)
        self.assertEqual(result, RemoteResolution(False, error="ssh_unavailable"))

    def test_host_aware_endpoint_identity_dedupes_only_proven_aliases(self):
        authority = "0123456789abcdef0123456789abcdef"
        socket = "/home/u/.config/herdr/herdr.sock"
        self.assertEqual(
            endpoint_id(authority, socket, "alias-a"),
            endpoint_id(authority, socket, "alias-b"),
        )
        self.assertNotEqual(
            endpoint_id("", socket, "host-a"),
            endpoint_id("", socket, "host-b"),
        )

    def test_resolver_pool_has_finite_concurrency_and_tokened_results(self):
        lock = threading.Lock()
        release = threading.Event()
        active = 0
        maximum = 0

        def resolver(_target, _session, _executable, *, cancelled):
            nonlocal active, maximum
            with lock:
                active += 1
                maximum = max(maximum, active)
            deadline = time.monotonic() + 2
            while not release.is_set() and not cancelled.is_set() and time.monotonic() < deadline:
                time.sleep(0.01)
            with lock:
                active -= 1
            return RemoteResolution(False, error="ssh_unavailable")

        pool = RemoteResolverPool(resolver, workers=2, queue_size=4)
        try:
            for index in range(4):
                self.assertTrue(pool.submit(f"k{index}", index, "host", "default", "/opt/herdr"))
            deadline = time.monotonic() + 1
            while maximum < 2 and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertEqual(maximum, 2)
            self.assertLessEqual(maximum, MAX_RESOLVER_WORKERS)
            release.set()
            results = []
            deadline = time.monotonic() + 2
            while len(results) < 4 and time.monotonic() < deadline:
                results.extend(pool.poll())
                time.sleep(0.01)
            self.assertEqual(sorted(token for _key, token, _result in results), [0, 1, 2, 3])
        finally:
            release.set()
            pool.close()

    def test_liveness_constants_leave_probe_and_owner_lease_headroom(self):
        self.assertLess(HELPER_LEASE_RENEW_EVERY, REMOTE_PROBE_TIMEOUT)
        self.assertLess(REMOTE_PROBE_TIMEOUT, HELPER_OWNER_LEASE_SECONDS)

    def test_remote_helper_owner_lease_expires_without_provider(self):
        process = subprocess.Popen(
            [
                sys.executable,
                "-B",
                str(HELPER),
                "/tmp/smartdock-nonexistent-herdr.sock",
                "--owner-lease-seconds",
                "1",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        try:
            self.assertEqual(process.wait(timeout=3), 0, process.stderr.read().decode())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=1)
            if process.stdin:
                process.stdin.close()
            if process.stderr:
                process.stderr.close()


if __name__ == "__main__":
    unittest.main()
