# SPDX-License-Identifier: Apache-2.0
"""Local Herdr TUI attachment discovery via process identity.

Raw argv and environment are read transiently for classification only. Public
output is bounded to pid/startTime ancestry metadata — never socket paths,
command lines, or environment values.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from typing import Any, Callable

ANCESTOR_DEPTH = 8
MAX_CLIENTS_PER_SERVER = 16
CMDLINE_BYTE_LIMIT = 4096
MAX_ARGV = 64
MAX_WINDOW_PROCESS_PIDS = 256
MAX_STDIN_COMMAND = 4096

# Local TUI attach accepts only these options (from installed `herdr --help`).
# Remote / exit-immediately / control surfaces are rejected.
_CONTROL_COMMANDS = frozenset({
    "server", "api", "agent", "pane", "tab", "workspace", "worktree",
    "config", "channel", "machine", "integration", "completion", "update",
    "status", "notification",
})
_EXIT_OPTIONS = frozenset({
    "--help", "-h", "--version", "-V", "--default-config", "--skill",
})

IdentityFn = Callable[[int], dict[str, int] | None]
ListPidsFn = Callable[[], list[int]]
OpenProcFn = Callable[[int], "ProcHandle | None"]


class ProcHandle:
    """Bound view of one /proc/<pid> process instance."""

    def uid(self) -> int | None:  # pragma: no cover - protocol
        raise NotImplementedError

    def identity(self) -> dict[str, int] | None:  # pragma: no cover - protocol
        raise NotImplementedError

    def cmdline(self) -> list[str] | None:  # pragma: no cover - protocol
        raise NotImplementedError

    def close(self) -> None:  # pragma: no cover - protocol
        raise NotImplementedError


@dataclass(frozen=True)
class _ParentLink:
    """Private parent-child PPID edge — never published."""

    child_pid: int
    child_start: int
    ppid: int
    parent_pid: int
    parent_start: int


def _basename(value: str) -> str:
    return os.path.basename(value.rstrip("/")) or value


def parse_tui_session(argv: list[str] | None) -> str | None:
    """Return the local TUI session name, or None when not a local attach."""
    if not argv:
        return None
    binary = _basename(argv[0])
    if binary != "herdr":
        return None
    args = argv[1:]

    if not args:
        return "default"

    if args[0] == "session":
        if len(args) >= 3 and args[1] == "attach":
            name = args[2]
            if not isinstance(name, str) or not name or name.startswith("-"):
                return None
            # Only `session attach NAME` — reject trailing help/control tokens.
            if len(args) > 3:
                return None
            return name
        return None

    if args[0] in _CONTROL_COMMANDS:
        return None

    session: str | None = None
    i = 0
    while i < len(args):
        arg = args[i]
        if not isinstance(arg, str) or not arg:
            return None
        if arg in _EXIT_OPTIONS:
            return None
        if arg == "--remote" or arg.startswith("--remote="):
            return None
        if arg == "--remote-keybindings" or arg.startswith("--remote-keybindings="):
            return None
        if arg == "--handoff":
            return None
        if arg == "--session":
            if i + 1 >= len(args):
                return None
            value = args[i + 1]
            if not isinstance(value, str) or not value or value.startswith("-"):
                return None
            if session is not None:
                # Repeated or conflicting --session is not a local attach.
                return None
            session = value
            i += 2
            continue
        if arg.startswith("--session="):
            value = arg.split("=", 1)[1]
            if not value:
                return None
            if session is not None:
                return None
            session = value
            i += 1
            continue
        # Unknown option or positional — not a whitelisted local TUI attach.
        return None

    if session is None:
        return "default"
    if session.startswith("-"):
        return None
    return session


def identity_alive(client: dict[str, Any], identity_of: IdentityFn) -> bool:
    pid = client.get("pid")
    start = client.get("startTime")
    if not isinstance(pid, int) or not isinstance(start, int):
        return False
    live = identity_of(pid)
    if live is None:
        return False
    return int(live["pid"]) == pid and int(live["startTime"]) == start


def decode_cmdline(
    raw: bytes,
    *,
    limit: int = CMDLINE_BYTE_LIMIT,
    max_args: int = MAX_ARGV,
) -> list[str] | None:
    """Fail closed on truncated, non-terminated, or over-long argv frames.

    Proc cmdline is NUL-separated with one trailing NUL. Only that terminator is
    removed; empty argument elements are rejected rather than filtered away.
    """
    if len(raw) > limit:
        return None
    if not raw:
        return []
    if not raw.endswith(b"\0"):
        return None
    body = raw[:-1]
    if not body:
        return []
    parts = body.split(b"\0")
    if any(part == b"" for part in parts):
        return None
    if len(parts) > max_args:
        return None
    return [part.decode("utf-8", errors="replace") for part in parts]


def parse_stat(data: bytes, pid: int) -> dict[str, int] | None:
    """Parse /proc/<pid>/stat bytes; `comm` may contain arbitrary non-UTF8."""
    if not data:
        return None
    rparen = data.rfind(b")")
    if rparen < 0:
        return None
    fields = data[rparen + 2:].split()
    if len(fields) < 20:
        return None
    try:
        return {
            "pid": int(pid),
            "ppid": int(fields[1]),
            "startTime": int(fields[19]),
        }
    except (ValueError, IndexError):
        return None


def public_clients(clients: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for client in clients[:MAX_CLIENTS_PER_SERVER]:
        pid = client.get("pid")
        start = client.get("startTime")
        if not isinstance(pid, int) or not isinstance(start, int):
            continue
        ancestors = []
        for ancestor in client.get("ancestors") or []:
            if not isinstance(ancestor, dict):
                continue
            apid = ancestor.get("pid")
            astart = ancestor.get("startTime")
            if isinstance(apid, int) and isinstance(astart, int):
                ancestors.append({"pid": apid, "startTime": astart})
            if len(ancestors) >= ANCESTOR_DEPTH:
                break
        output.append({"pid": pid, "startTime": start, "ancestors": ancestors})
    return output


def _session_index(inventory: list[dict[str, Any]]) -> dict[str, str]:
    """Map session name -> server id.

    Names that resolve to distinct server IDs are left unresolved (no list-order
    winner). Aliases for the same canonical endpoint remain valid.
    """
    mapping: dict[str, str] = {}
    ambiguous: set[str] = set()
    for entry in inventory:
        server_id = entry.get("id")
        if not isinstance(server_id, str) or not server_id:
            continue
        sessions = entry.get("sessions")
        if not isinstance(sessions, list):
            continue
        for name in sessions:
            if not isinstance(name, str) or not name or name in ambiguous:
                continue
            existing = mapping.get(name)
            if existing is None:
                mapping[name] = server_id
            elif existing != server_id:
                mapping.pop(name, None)
                ambiguous.add(name)
    return mapping


def _walk_ancestors(
    client: ProcHandle,
    pid: int,
    start_time: int,
    open_proc: OpenProcFn,
    uid: int,
    depth: int = ANCESTOR_DEPTH,
) -> tuple[list[dict[str, int]], list[_ParentLink]] | None:
    """Walk same-user parents via bound proc handles; keep private PPID links."""
    ancestors: list[dict[str, int]] = []
    links: list[_ParentLink] = []
    seen: set[int] = set()
    current_pid = pid
    current_start = start_time
    current: ProcHandle = client
    opened: list[ProcHandle] = []
    try:
        for _ in range(depth):
            info = current.identity()
            if info is None or int(info["startTime"]) != current_start:
                return None
            ppid = int(info.get("ppid", 0))
            if ppid <= 0 or ppid in seen:
                break
            seen.add(ppid)
            parent = open_proc(ppid)
            if parent is None:
                # Unreadable parent: stop ancestry (same as a UID mismatch),
                # do not fail the whole candidate.
                break
            opened.append(parent)
            # Stop at a different-user ancestor without reading its identity.
            parent_uid = parent.uid()
            if parent_uid is None or parent_uid != uid:
                break
            parent_info = parent.identity()
            if parent_info is None:
                return None
            parent_pid = int(parent_info["pid"])
            parent_start = int(parent_info["startTime"])
            links.append(_ParentLink(
                child_pid=current_pid,
                child_start=current_start,
                ppid=ppid,
                parent_pid=parent_pid,
                parent_start=parent_start,
            ))
            ancestors.append({"pid": parent_pid, "startTime": parent_start})
            current = parent
            current_pid = parent_pid
            current_start = parent_start
        return ancestors, links
    finally:
        for handle in opened:
            handle.close()


def _revalidate_links(
    bound: dict[str, int],
    links: list[_ParentLink],
    open_proc: OpenProcFn,
    uid: int,
    client: ProcHandle,
) -> bool:
    """Confirm each recorded PPID edge still holds for the same identities."""
    if client.uid() != uid:
        return False
    live = client.identity()
    if live is None or int(live["startTime"]) != bound["startTime"]:
        return False

    for link in links:
        child: ProcHandle | None = None
        parent: ProcHandle | None = None
        child_owned = False
        parent_owned = False
        try:
            if link.child_pid == bound["pid"]:
                child = client
            else:
                child = open_proc(link.child_pid)
                child_owned = True
            if child is None or child.uid() != uid:
                return False
            child_info = child.identity()
            if child_info is None:
                return False
            if (int(child_info["pid"]) != link.child_pid
                    or int(child_info["startTime"]) != link.child_start):
                return False
            if int(child_info.get("ppid", -1)) != link.ppid:
                return False

            parent = open_proc(link.parent_pid)
            parent_owned = True
            if parent is None or parent.uid() != uid:
                return False
            parent_info = parent.identity()
            if parent_info is None:
                return False
            if (int(parent_info["pid"]) != link.parent_pid
                    or int(parent_info["startTime"]) != link.parent_start):
                return False
        finally:
            if child_owned and child is not None:
                child.close()
            if parent_owned and parent is not None:
                parent.close()
    return True


def discover_attachments(
    inventory: list[dict[str, Any]],
    *,
    uid: int | None = None,
    list_pids: ListPidsFn | None = None,
    open_proc: OpenProcFn | None = None,
) -> dict[str, list[dict[str, Any]]]:
    """Discover same-user local TUI attachments keyed by canonical server id."""
    uid = os.getuid() if uid is None else uid
    list_pids = list_pids or _list_pids
    open_proc = open_proc or open_linux_proc

    sessions = _session_index(inventory)
    found: dict[str, list[dict[str, Any]]] = {}

    for pid in list_pids():
        proc = open_proc(pid)
        if proc is None:
            continue
        try:
            # Same-user gate from the bound handle before identity/cmdline.
            if proc.uid() != uid:
                continue

            identity = proc.identity()
            if identity is None:
                continue
            start_time = int(identity["startTime"])
            bound = {"pid": int(pid), "startTime": start_time}

            argv = proc.cmdline()
            if argv is None:
                continue
            session = parse_tui_session(argv)
            if session is None:
                continue
            server_id = sessions.get(session)
            if server_id is None:
                continue

            walked = _walk_ancestors(proc, pid, start_time, open_proc, uid)
            if walked is None:
                continue
            ancestors, links = walked

            if not _revalidate_links(bound, links, open_proc, uid, proc):
                continue
            if proc.uid() != uid:
                continue
            live = proc.identity()
            if live is None or int(live["startTime"]) != bound["startTime"]:
                continue

            client = {
                "pid": bound["pid"],
                "startTime": bound["startTime"],
                "ancestors": ancestors,
            }
            bucket = found.setdefault(server_id, [])
            if len(bucket) >= MAX_CLIENTS_PER_SERVER:
                continue
            if any(row["pid"] == client["pid"] and row["startTime"] == client["startTime"]
                   for row in bucket):
                continue
            bucket.append(client)
        finally:
            proc.close()

    for server_id in found:
        found[server_id] = public_clients(found[server_id])
    return found


def _list_pids() -> list[int]:
    pids: list[int] = []
    try:
        for name in os.listdir("/proc"):
            if name.isdigit():
                pids.append(int(name))
                if len(pids) >= 8192:
                    break
    except OSError:
        return []
    pids.sort()
    return pids


class _LinuxProcHandle(ProcHandle):
    """Reads status/stat/cmdline through one opened /proc/<pid> directory FD."""

    def __init__(self, pid: int, dirfd: int) -> None:
        self.pid = int(pid)
        self._dirfd = int(dirfd)

    def close(self) -> None:
        fd = self._dirfd
        self._dirfd = -1
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass

    def _read(self, name: str, *, limit: int) -> bytes | None:
        """Read up to limit bytes via dir_fd; fail closed if limit+1 is observed."""
        if self._dirfd < 0:
            return None
        fd = -1
        try:
            fd = os.open(name, os.O_RDONLY | os.O_CLOEXEC, dir_fd=self._dirfd)
            chunks = bytearray()
            probe = limit + 1
            while len(chunks) < probe:
                try:
                    piece = os.read(fd, min(4096, probe - len(chunks)))
                except OSError:
                    return None
                if not piece:
                    break
                chunks.extend(piece)
            if len(chunks) > limit:
                return None
            return bytes(chunks)
        except OSError:
            return None
        finally:
            if fd >= 0:
                try:
                    os.close(fd)
                except OSError:
                    pass

    def uid(self) -> int | None:
        raw = self._read("status", limit=4096)
        if raw is None:
            return None
        try:
            text = raw.decode("utf-8", errors="replace")
        except Exception:
            return None
        for line in text.splitlines():
            if line.startswith("Uid:"):
                try:
                    return int(line.split()[1])
                except (ValueError, IndexError):
                    return None
        return None

    def identity(self) -> dict[str, int] | None:
        raw = self._read("stat", limit=4096)
        if raw is None:
            return None
        return parse_stat(raw, self.pid)

    def cmdline(self) -> list[str] | None:
        # Probe at most CMDLINE_BYTE_LIMIT+1 (4097) bytes; oversized fails closed.
        raw = self._read("cmdline", limit=CMDLINE_BYTE_LIMIT)
        if raw is None:
            return None
        return decode_cmdline(raw)


def open_linux_proc(pid: int) -> ProcHandle | None:
    try:
        dirfd = os.open(
            f"/proc/{int(pid)}",
            os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC,
        )
    except OSError:
        return None
    return _LinuxProcHandle(int(pid), dirfd)


def parse_window_processes_command(raw: bytes) -> dict[str, Any] | None:
    """Parse a bounded window-processes stdin command.

    Accepts only an integer revision and at most 256 unique positive integer
    PIDs. Paths, commands, argv, extra fields, and oversize unique sets are
    rejected fail-closed.
    """
    if not isinstance(raw, (bytes, bytearray)) or len(raw) > MAX_STDIN_COMMAND:
        return None
    try:
        message = json.loads(raw)
    except (ValueError, UnicodeError, TypeError):
        return None
    if not isinstance(message, dict):
        return None
    if set(message) - {"kind", "revision", "pids"}:
        return None
    if message.get("kind") != "window-processes":
        return None
    revision = message.get("revision")
    if not isinstance(revision, int) or isinstance(revision, bool):
        return None
    if revision < 0:
        return None
    pids = message.get("pids")
    if not isinstance(pids, list):
        return None
    normalized: list[int] = []
    seen: set[int] = set()
    for value in pids:
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            return None
        if value in seen:
            continue
        if len(normalized) >= MAX_WINDOW_PROCESS_PIDS:
            return None
        seen.add(value)
        normalized.append(value)
    return {"revision": revision, "pids": normalized}


def _bounded_id(value: object, *, max_len: int = 128) -> str | None:
    if not isinstance(value, str) or not value or len(value) > max_len:
        return None
    if any(ord(char) < 32 or ord(char) == 127 or 0xD800 <= ord(char) <= 0xDFFF
           for char in value):
        return None
    return value


def parse_provider_focus_agent_command(raw: bytes) -> dict[str, Any] | None:
    """Parse SmartDock→provider focus-agent stdin command.

    Fail-closed: exact field set, bounded ids, positive generation. No socket
    paths, methods, or free-form Herdr payloads.
    """
    if not isinstance(raw, (bytes, bytearray)) or len(raw) > MAX_STDIN_COMMAND:
        return None
    try:
        message = json.loads(raw)
    except (ValueError, UnicodeError, TypeError):
        return None
    if not isinstance(message, dict):
        return None
    allowed = {
        "kind", "requestId", "providerEpoch", "serverId",
        "connectionGeneration", "agentId", "paneId", "terminalId",
    }
    if set(message) - allowed:
        return None
    if message.get("kind") != "focus-agent":
        return None
    request_id = _bounded_id(message.get("requestId"), max_len=64)
    epoch = _bounded_id(message.get("providerEpoch"), max_len=64)
    server_id = _bounded_id(message.get("serverId"), max_len=128)
    agent_id = _bounded_id(message.get("agentId"), max_len=192)
    pane_id = _bounded_id(message.get("paneId"), max_len=128)
    if not request_id or not epoch or not server_id or not agent_id or not pane_id:
        return None
    generation = message.get("connectionGeneration")
    if isinstance(generation, bool):
        return None
    if isinstance(generation, float):
        if not generation.is_integer() or generation <= 0:
            return None
        generation = int(generation)
    elif not isinstance(generation, int) or generation <= 0:
        return None
    terminal_id = message.get("terminalId", "")
    if terminal_id in ("", None):
        terminal = ""
    else:
        terminal = _bounded_id(terminal_id, max_len=128)
        if terminal is None:
            return None
    return {
        "requestId": request_id,
        "providerEpoch": epoch,
        "serverId": server_id,
        "connectionGeneration": generation,
        "agentId": agent_id,
        "paneId": pane_id,
        "terminalId": terminal,
    }


def parse_helper_focus_agent_command(raw: bytes) -> dict[str, Any] | None:
    """Parse provider→helper focus-agent stdin command (requestId + pane_id)."""
    if not isinstance(raw, (bytes, bytearray)) or len(raw) > MAX_STDIN_COMMAND:
        return None
    try:
        message = json.loads(raw)
    except (ValueError, UnicodeError, TypeError):
        return None
    if not isinstance(message, dict):
        return None
    if set(message) - {"kind", "requestId", "pane_id"}:
        return None
    if message.get("kind") != "focus-agent":
        return None
    request_id = _bounded_id(message.get("requestId"), max_len=64)
    pane_id = _bounded_id(message.get("pane_id"), max_len=128)
    if not request_id or not pane_id:
        return None
    return {"requestId": request_id, "pane_id": pane_id}


def resolve_window_identities(
    pids: list[int],
    *,
    uid: int | None = None,
    open_proc: OpenProcFn | None = None,
) -> list[dict[str, int]]:
    """Resolve same-user PID/startTime identities through opened proc handles."""
    uid = os.getuid() if uid is None else uid
    open_proc = open_proc or open_linux_proc
    identities: list[dict[str, int]] = []
    seen: set[int] = set()
    for raw_pid in pids:
        if not isinstance(raw_pid, int) or isinstance(raw_pid, bool) or raw_pid <= 0:
            continue
        if raw_pid in seen:
            continue
        seen.add(raw_pid)
        if len(identities) >= MAX_WINDOW_PROCESS_PIDS:
            break
        proc = open_proc(raw_pid)
        if proc is None:
            continue
        try:
            if proc.uid() != uid:
                continue
            identity = proc.identity()
            if identity is None:
                continue
            pid = int(identity["pid"])
            start = int(identity["startTime"])
            if pid != raw_pid or start < 0:
                continue
            # Re-check UID after identity so a recycled PID cannot leak.
            if proc.uid() != uid:
                continue
            live = proc.identity()
            if live is None or int(live["startTime"]) != start:
                continue
            identities.append({"pid": pid, "startTime": start})
        finally:
            proc.close()
    return identities
