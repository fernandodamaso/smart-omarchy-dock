# SPDX-License-Identifier: Apache-2.0
"""Attachment discovery: local Herdr TUI process identity only."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from attachments import (  # noqa: E402
    CMDLINE_BYTE_LIMIT,
    decode_cmdline,
    discover_attachments,
    identity_alive,
    parse_stat,
    parse_tui_session,
    public_clients,
)
from discovery import endpoint_id  # noqa: E402


def server(socket, sessions, session=None):
    sessions = list(sessions)
    return {
        "id": endpoint_id(socket),
        "host": "local",
        "socket": socket,
        "sessions": sessions,
        "session": session or sessions[0],
        "label": sessions[0] if len(sessions) == 1 else ", ".join(sessions[:3]),
    }


class FakeHandle:
    """Bound fake process: does not follow PID reuse by another identity."""

    def __init__(self, fake: "FakeProc", pid: int, row: dict) -> None:
        self.fake = fake
        self.pid = int(pid)
        self._uid = int(row["uid"])
        self._start = int(row["starttime"])
        self._ppid = int(row["ppid"])
        self._cmdline = None if row["cmdline"] is None else list(row["cmdline"])
        self.closed = False
        fake.handles.append(self)

    def _live_row(self) -> dict | None:
        if self.closed:
            return None
        row = self.fake.rows.get(self.pid)
        if row is None:
            return None
        # Replacement (new UID or starttime) is invisible through this handle.
        if int(row["uid"]) != self._uid or int(row["starttime"]) != self._start:
            return None
        return row

    def uid(self) -> int | None:
        row = self._live_row()
        if row is None:
            return None
        self.fake.uid_pids.append(self.pid)
        return int(row["uid"])

    def identity(self) -> dict[str, int] | None:
        row = self._live_row()
        if row is None:
            return None
        self.fake.identity_calls += 1
        self.fake.identity_pids.append(self.pid)
        if self.fake.on_identity is not None:
            self.fake.on_identity(self.fake, self.pid, self.fake.identity_calls)
            row = self._live_row()
            if row is None:
                return None
        return {
            "pid": self.pid,
            "startTime": int(row["starttime"]),
            "ppid": int(row["ppid"]),
        }

    def cmdline(self) -> list[str] | None:
        row = self._live_row()
        if row is None:
            self.fake.cmdline_values.append(None)
            return None
        self.fake.cmdline_pids.append(self.pid)
        cmdline = row["cmdline"]
        if cmdline is None:
            self.fake.cmdline_values.append(None)
            return None
        value = list(cmdline)
        self.fake.cmdline_values.append(value)
        return value

    def close(self) -> None:
        self.closed = True


class FakeProc:
    """Injectable process table with bound open_proc handles."""

    def __init__(self, rows, on_identity=None):
        # pid -> {uid, cmdline:list[str]|None, starttime:int, ppid:int}
        self.rows = {int(pid): dict(row) for pid, row in rows.items()}
        self.on_identity = on_identity
        self.identity_calls = 0
        self.identity_pids: list[int] = []
        self.cmdline_pids: list[int] = []
        self.uid_pids: list[int] = []
        self.cmdline_values: list[list[str] | None] = []
        self.handles: list[FakeHandle] = []

    def list_pids(self):
        return sorted(self.rows)

    def open_proc(self, pid: int) -> FakeHandle | None:
        row = self.rows.get(int(pid))
        if row is None:
            return None
        return FakeHandle(self, int(pid), row)

    def identity_of(self, pid: int) -> dict[str, int] | None:
        """Unbound helper for post-discovery identity_alive checks only."""
        row = self.rows.get(int(pid))
        if row is None:
            return None
        return {"pid": int(pid), "startTime": int(row["starttime"]), "ppid": int(row["ppid"])}


class AttachmentDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.uid = 1000
        self.default = server("/tmp/herdr-default.sock", ["default"])
        self.work = server("/tmp/herdr-work.sock", ["work"])
        self.aliased = server("/tmp/herdr-shared.sock", ["default", "work"])

    def discover(self, servers, rows, uid=None, on_identity=None, open_proc=None):
        fake = FakeProc(rows, on_identity=on_identity)
        found = discover_attachments(
            servers,
            uid=self.uid if uid is None else uid,
            list_pids=fake.list_pids,
            open_proc=open_proc or fake.open_proc,
        )
        return found, fake

    def test_default_invocation_resolves_through_inventory(self):
        rows = {
            10: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 100, "ppid": 1},
        }
        found, _ = self.discover([self.default], rows)
        self.assertEqual(list(found), [self.default["id"]])
        clients = found[self.default["id"]]
        self.assertEqual(len(clients), 1)
        self.assertEqual(clients[0]["pid"], 10)
        self.assertEqual(clients[0]["startTime"], 100)
        self.assertEqual(clients[0]["ancestors"], [])

    def test_named_session_flag_forms_and_attach_alias(self):
        rows = {
            11: {
                "uid": self.uid,
                "cmdline": ["herdr", "--session", "work"],
                "starttime": 200,
                "ppid": 1,
            },
            12: {
                "uid": self.uid,
                "cmdline": ["herdr", "--session=work"],
                "starttime": 201,
                "ppid": 1,
            },
            13: {
                "uid": self.uid,
                "cmdline": ["herdr", "session", "attach", "work"],
                "starttime": 202,
                "ppid": 1,
            },
        }
        found, _ = self.discover([self.work], rows)
        clients = found[self.work["id"]]
        self.assertEqual(sorted(c["pid"] for c in clients), [11, 12, 13])

    def test_aliases_share_one_endpoint_without_default_fallback(self):
        rows = {
            20: {
                "uid": self.uid,
                "cmdline": ["herdr", "--session", "work"],
                "starttime": 300,
                "ppid": 1,
            },
            21: {
                "uid": self.uid,
                "cmdline": ["herdr", "--session", "missing"],
                "starttime": 301,
                "ppid": 1,
            },
        }
        found, _ = self.discover([self.aliased], rows)
        self.assertEqual(list(found), [self.aliased["id"]])
        self.assertEqual([c["pid"] for c in found[self.aliased["id"]]], [20])
        self.assertNotIn(21, [c["pid"] for c in found[self.aliased["id"]]])

    def test_conflicting_session_names_across_endpoints_stay_unresolved(self):
        one = server("/tmp/herdr-one.sock", ["work"])
        two = server("/tmp/herdr-two.sock", ["work"])
        rows = {
            70: {
                "uid": self.uid,
                "cmdline": ["herdr", "--session", "work"],
                "starttime": 700,
                "ppid": 1,
            },
        }
        found_fwd, _ = self.discover([one, two], rows)
        found_rev, _ = self.discover([two, one], rows)
        self.assertEqual(found_fwd, {})
        self.assertEqual(found_rev, {})
        self.assertEqual(found_fwd, found_rev)

    def test_rejects_help_version_missing_session_and_control_forms(self):
        rejected = [
            ["herdr", "--help"],
            ["herdr", "-h"],
            ["herdr", "--version"],
            ["herdr", "-V"],
            ["herdr", "--default-config"],
            ["herdr", "--skill"],
            ["herdr", "--handoff"],
            ["herdr", "--session"],
            ["herdr", "--session", "--help"],
            ["herdr", "--session", "work", "--session", "other"],
            ["herdr", "--session", "work", "--session", "work"],
            ["herdr", "--session=work", "--session=other"],
            ["herdr", "--session="],
            ["herdr", ""],
            ["herdr", "session", "attach"],
            ["herdr", "session", "attach", ""],
            ["herdr", "session", "attach", "work", "--help"],
            ["herdr", "session", "attach", "work", "-h"],
            ["herdr", "server"],
            ["herdr", "status"],
            ["herdr", "agent", "list"],
            ["herdr", "--remote", "box"],
            ["herdr", "--remote=box", "--session", "work"],
            ["herdr", "--remote-keybindings", "local"],
            ["echo", "herdr"],
        ]
        for argv in rejected:
            self.assertIsNone(parse_tui_session(argv), argv)

        accepted = [
            (["herdr"], "default"),
            (["herdr", "--session", "work"], "work"),
            (["herdr", "--session=work"], "work"),
            (["herdr", "session", "attach", "work"], "work"),
        ]
        for argv, session in accepted:
            self.assertEqual(parse_tui_session(argv), session, argv)

        rows = {
            30: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 1, "ppid": 1},
            31: {"uid": self.uid, "cmdline": ["herdr", "--help"], "starttime": 2, "ppid": 1},
            32: {"uid": self.uid, "cmdline": ["herdr", "--version"], "starttime": 3, "ppid": 1},
            33: {
                "uid": self.uid,
                "cmdline": ["herdr", "session", "attach", "work", "--help"],
                "starttime": 4,
                "ppid": 1,
            },
            34: {"uid": self.uid, "cmdline": ["herdr", "--session"], "starttime": 5, "ppid": 1},
            35: {"uid": self.uid, "cmdline": ["herdr", "server"], "starttime": 6, "ppid": 30},
            36: {
                "uid": self.uid + 1,
                "cmdline": ["herdr"],
                "starttime": 7,
                "ppid": 1,
            },
        }
        found, fake = self.discover([self.default, self.work], rows)
        self.assertEqual(list(found), [self.default["id"]])
        self.assertEqual([c["pid"] for c in found[self.default["id"]]], [30])
        self.assertNotIn(36, fake.identity_pids)
        self.assertNotIn(36, fake.cmdline_pids)

    def test_foreign_uid_never_reaches_identity_or_cmdline(self):
        foreign = self.uid + 7
        rows = {
            80: {"uid": foreign, "cmdline": ["herdr"], "starttime": 80, "ppid": 1},
            81: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 81, "ppid": 1},
        }
        found, fake = self.discover([self.default], rows)
        self.assertEqual([c["pid"] for c in found[self.default["id"]]], [81])
        self.assertNotIn(80, fake.identity_pids)
        self.assertNotIn(80, fake.cmdline_pids)
        self.assertIn(81, fake.identity_pids)
        self.assertIn(81, fake.cmdline_pids)
        self.assertTrue(all(handle.closed for handle in fake.handles))

    def test_pid_reuse_other_uid_between_uid_gate_and_reads(self):
        """Replacement by another UID after uid() must not leak identity/cmdline."""
        foreign = self.uid + 11
        rows = {
            41: {
                "uid": self.uid,
                "cmdline": ["herdr"],
                "starttime": 41,
                "ppid": 1,
            },
        }
        fake = FakeProc(rows)
        real_open = fake.open_proc

        def open_proc(pid: int):
            handle = real_open(pid)
            if handle is None:
                return None
            original_uid = handle.uid

            def uid_then_replace():
                value = original_uid()
                # Simulate exit + reuse by another user after the same-UID gate.
                if value == self.uid and fake.rows.get(41, {}).get("uid") == self.uid:
                    fake.rows[41] = {
                        "uid": foreign,
                        "cmdline": ["evil-remote"],
                        "starttime": 9900,
                        "ppid": 1,
                    }
                return value

            handle.uid = uid_then_replace  # type: ignore[method-assign]
            return handle

        found = discover_attachments(
            [self.default],
            uid=self.uid,
            list_pids=fake.list_pids,
            open_proc=open_proc,
        )
        self.assertEqual(found, {})
        self.assertNotIn(41, fake.identity_pids)
        self.assertNotIn(41, fake.cmdline_pids)
        self.assertNotIn(["evil-remote"], fake.cmdline_values)
        self.assertTrue(all(handle.closed for handle in fake.handles))

    def test_stops_ancestry_at_different_user_parent(self):
        rows = {
            1: {"uid": 0, "cmdline": ["init"], "starttime": 1, "ppid": 0},
            40: {"uid": self.uid, "cmdline": ["ghostty"], "starttime": 40, "ppid": 1},
            41: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 41, "ppid": 40},
        }
        found, fake = self.discover([self.default], rows)
        client = found[self.default["id"]][0]
        self.assertEqual(
            [(a["pid"], a["startTime"]) for a in client["ancestors"]],
            [(40, 40)],
        )
        self.assertNotIn(1, [a["pid"] for a in client["ancestors"]])
        self.assertNotIn(1, fake.identity_pids)

    def test_records_same_user_ancestry_and_post_discovery_identity_alive(self):
        rows = {
            1: {"uid": self.uid, "cmdline": ["init"], "starttime": 1, "ppid": 0},
            40: {"uid": self.uid, "cmdline": ["ghostty"], "starttime": 40, "ppid": 1},
            41: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 41, "ppid": 40},
        }
        found, _ = self.discover([self.default], rows)
        client = found[self.default["id"]][0]
        self.assertEqual(client["pid"], 41)
        self.assertEqual(
            [(a["pid"], a["startTime"]) for a in client["ancestors"]],
            [(40, 40), (1, 1)],
        )
        self.assertTrue(identity_alive(client, identity_of=FakeProc(rows).identity_of))
        reused = {
            41: {"uid": self.uid, "cmdline": ["other"], "starttime": 99, "ppid": 1},
        }
        self.assertFalse(identity_alive(client, identity_of=FakeProc(reused).identity_of))
        self.assertFalse(identity_alive(client, identity_of=FakeProc({}).identity_of))

    def test_rejects_recycled_parent_pid_after_reparent(self):
        rows = {
            40: {"uid": self.uid, "cmdline": ["ghostty"], "starttime": 40, "ppid": 1},
            41: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 41, "ppid": 40},
        }
        reads: dict[int, int] = {}

        def recycle_parent(fake, pid, _call_count):
            reads[pid] = reads.get(pid, 0) + 1
            # After ancestry walk records 41→40, replace parent PID 40 with an
            # unrelated process and reparent the client so the PPID link breaks.
            if pid == 41 and reads[41] >= 3:
                fake.rows[40] = {
                    "uid": self.uid,
                    "cmdline": ["unrelated"],
                    "starttime": 999,
                    "ppid": 1,
                }
                fake.rows[41]["ppid"] = 1

        found, fake = self.discover([self.default], rows, on_identity=recycle_parent)
        self.assertEqual(found, {})
        self.assertGreaterEqual(reads.get(41, 0), 3)
        self.assertGreaterEqual(fake.identity_calls, 4)
        blob = repr(found)
        self.assertNotIn("ppid", blob)
        self.assertNotIn("_ParentLink", blob)

    def test_discards_when_pid_disappears_during_discovery(self):
        rows = {
            1: {"uid": self.uid, "cmdline": ["init"], "starttime": 1, "ppid": 0},
            41: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 41, "ppid": 1},
        }
        # Client 41: 1=bind, 2=walk, 3+=post-walk link/identity revalidation.
        reads: dict[int, int] = {}

        def disappear(fake, pid, _call_count):
            reads[pid] = reads.get(pid, 0) + 1
            if pid == 41 and reads[pid] >= 3:
                fake.rows.pop(41, None)

        found, fake = self.discover([self.default], rows, on_identity=disappear)
        self.assertEqual(found, {})
        self.assertGreaterEqual(reads.get(41, 0), 3)
        self.assertGreaterEqual(reads.get(1, 0), 2, "parent identity read after client bind")
        self.assertGreaterEqual(fake.identity_calls, 5)

    def test_discards_when_pid_reused_during_discovery(self):
        rows = {
            1: {"uid": self.uid, "cmdline": ["init"], "starttime": 1, "ppid": 0},
            41: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 41, "ppid": 1},
        }
        reads: dict[int, int] = {}

        def reuse(fake, pid, _call_count):
            reads[pid] = reads.get(pid, 0) + 1
            if pid == 41 and reads[pid] >= 3 and 41 in fake.rows:
                fake.rows[41]["starttime"] = 99
                fake.rows[41]["cmdline"] = ["other"]

        found, fake = self.discover([self.default], rows, on_identity=reuse)
        self.assertEqual(found, {})
        self.assertGreaterEqual(reads.get(41, 0), 3)
        self.assertGreaterEqual(reads.get(1, 0), 2, "parent identity read after client bind")
        self.assertGreaterEqual(fake.identity_calls, 5)

    def test_cmdline_truncation_fails_closed_before_hidden_remote(self):
        complete = b"herdr\0--session\0work\0"
        self.assertEqual(
            decode_cmdline(complete),
            ["herdr", "--session", "work"],
        )
        # Oversized frame (one byte beyond the bound) is rejected entirely.
        oversized = complete + (b"x" * (CMDLINE_BYTE_LIMIT - len(complete) + 1))
        self.assertIsNone(decode_cmdline(oversized))
        # Non-terminated prefix that would otherwise look local is rejected.
        truncated = b"herdr\0--session\0work\0--remo"
        self.assertIsNone(decode_cmdline(truncated))
        self.assertIsNone(parse_tui_session(decode_cmdline(truncated)))
        # Too many arguments fails closed.
        many = b"herdr\0" + b"a\0" * 64
        self.assertIsNone(decode_cmdline(many))

    def test_cmdline_empty_positional_nul_is_not_default_attach(self):
        # Trailing proc NUL plus an empty argv element must not collapse to ['herdr'].
        raw = b"herdr\0\0"
        decoded = decode_cmdline(raw)
        self.assertIsNone(decoded)
        self.assertIsNone(parse_tui_session(decoded))
        self.assertEqual(decode_cmdline(b""), [])
        self.assertIsNone(parse_tui_session([]))
        self.assertEqual(decode_cmdline(b"herdr\0"), ["herdr"])
        self.assertEqual(parse_tui_session(["herdr"]), "default")

    def test_parse_stat_tolerates_non_utf8_comm(self):
        # Field layout after `)`: state ppid ... starttime at index 19.
        trailing = b" ".join(
            [b"S", b"40"] + [b"0"] * 17 + [b"12345"] + [b"0"] * 5
        )
        data = b"41 (herdr\xff\xfe) " + trailing + b"\n"
        parsed = parse_stat(data, 41)
        self.assertEqual(parsed, {"pid": 41, "ppid": 40, "startTime": 12345})

    def test_open_linux_proc_reads_self_uid_identity_cmdline(self):
        import os
        from attachments import open_linux_proc

        handle = open_linux_proc(os.getpid())
        self.assertIsNotNone(handle)
        assert handle is not None
        try:
            uid = handle.uid()
            self.assertIsInstance(uid, int)
            self.assertEqual(uid, os.getuid())
            identity = handle.identity()
            self.assertIsInstance(identity, dict)
            self.assertEqual(identity["pid"], os.getpid())
            self.assertIsInstance(identity["startTime"], int)
            self.assertIsInstance(identity["ppid"], int)
            cmdline = handle.cmdline()
            # Readable (list or fail-closed None for exotic frames); not classified.
            self.assertTrue(cmdline is None or isinstance(cmdline, list))
        finally:
            handle.close()

    def test_public_clients_omit_private_fields_and_sockets(self):
        rows = {
            50: {"uid": self.uid, "cmdline": ["herdr"], "starttime": 50, "ppid": 1},
        }
        found, _ = self.discover([self.default], rows)
        published = public_clients(found[self.default["id"]])
        self.assertEqual(published, [{
            "pid": 50,
            "startTime": 50,
            "ancestors": [],
        }])
        blob = repr(published)
        self.assertNotIn("cmdline", blob)
        self.assertNotIn("socket", blob)
        self.assertNotIn("/tmp/", blob)
        self.assertNotIn("ppid", blob)


if __name__ == "__main__":
    unittest.main()
