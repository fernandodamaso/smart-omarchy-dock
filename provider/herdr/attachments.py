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
import shlex
from typing import Any, Callable

from remote import valid_remote_target, valid_session as valid_attachment_session

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


@dataclass(frozen=True)
class AttachmentSpec:
    """Bounded TUI attachment identity; raw argv never leaves classification."""

    kind: str
    session: str = "default"
    target: str | None = None


def classify_tui_attachment(argv: list[str] | None) -> AttachmentSpec | None:
    """Classify only verified local/remote Herdr TUI launch forms.

    Current Herdr accepts the default TUI launch with optional --session and
    --remote, plus --remote-keybindings only for remote attach. Control/help,
    handoff and positional subcommands are rejected fail-closed.
    """
    if not argv or _basename(argv[0]) != "herdr":
        return None
    args = argv[1:]
    if not args:
        return AttachmentSpec("local")

    if args[0] == "session":
        if len(args) == 3 and args[1] == "attach" and valid_attachment_session(args[2]):
            return AttachmentSpec("local", args[2], None)
        return None
    if args[0] in _CONTROL_COMMANDS:
        return None

    session = "default"
    session_seen = False
    target: str | None = None
    remote_seen = False
    keybindings_seen = False
    i = 0
    while i < len(args):
        arg = args[i]
        if not isinstance(arg, str) or not arg:
            return None
        if arg in _EXIT_OPTIONS or arg == "--handoff" or arg == "--":
            return None

        if arg == "--session":
            if session_seen or i + 1 >= len(args):
                return None
            value = args[i + 1]
            if not valid_attachment_session(value):
                return None
            session = value
            session_seen = True
            i += 2
            continue
        if arg.startswith("--session="):
            if session_seen:
                return None
            value = arg.split("=", 1)[1]
            if not valid_attachment_session(value):
                return None
            session = value
            session_seen = True
            i += 1
            continue

        if arg == "--remote":
            if remote_seen or i + 1 >= len(args):
                return None
            value = args[i + 1]
            if not valid_remote_target(value):
                return None
            target = value
            remote_seen = True
            i += 2
            continue
        if arg.startswith("--remote="):
            if remote_seen:
                return None
            value = arg.split("=", 1)[1]
            if not valid_remote_target(value):
                return None
            target = value
            remote_seen = True
            i += 1
            continue

        if arg == "--remote-keybindings":
            if keybindings_seen or i + 1 >= len(args):
                return None
            if args[i + 1] not in ("local", "server"):
                return None
            keybindings_seen = True
            i += 2
            continue
        if arg.startswith("--remote-keybindings="):
            if keybindings_seen or arg.split("=", 1)[1] not in ("local", "server"):
                return None
            keybindings_seen = True
            i += 1
            continue

        # Unknown options and positional/control forms are not TUI attachments.
        return None

    if keybindings_seen and target is None:
        return None
    if target is None:
        return AttachmentSpec("local", session, None)
    return AttachmentSpec("remote", session, target)


def parse_tui_session(argv: list[str] | None) -> str | None:
    """Compatibility wrapper for callers that specifically need local TUI sessions."""
    spec = classify_tui_attachment(argv)
    return spec.session if spec is not None and spec.kind == "local" else None


def parse_remote_bridge_executable(argv: list[str] | None) -> str | None:
    """Recover the remote Herdr executable from a direct child SSH bridge.

    This is transient process evidence only. The command line is never
    published, and the returned executable is used only as encoded resolver
    input. Bare PATH lookups are intentionally rejected.
    """
    if not argv or _basename(argv[0]) != "ssh":
        return None
    command = " ".join(str(part) for part in argv[1:])
    if "remote-client-bridge" not in command:
        return None
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return None
    try:
        bridge_index = tokens.index("remote-client-bridge")
    except ValueError:
        return None
    exec_indexes = [index for index, token in enumerate(tokens[:bridge_index]) if token == "exec"]
    if not exec_indexes:
        return None
    exec_index = exec_indexes[-1]
    if exec_index + 1 >= bridge_index:
        return None
    executable = tokens[exec_index + 1]
    if not isinstance(executable, str) or not executable or executable.startswith("-"):
        return None
    try:
        if len(executable.encode("utf-8", errors="strict")) > 1024:
            return None
    except UnicodeError:
        return None
    if any(ord(char) < 32 or ord(char) == 127 or 0xD800 <= ord(char) <= 0xDFFF
           for char in executable):
        return None
    if not (executable.startswith("/") or executable.startswith("~/")
            or executable.startswith("$HOME/")):
        return None
    return executable

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


def _remote_bridge_executables(
    parent_pids: set[int],
    pids: list[int],
    open_proc: OpenProcFn,
    uid: int,
) -> dict[int, str | None]:
    """Resolve at most one stable direct-child SSH bridge executable per parent."""
    candidates: dict[int, set[str]] = {pid: set() for pid in parent_pids}
    for child_pid in pids[:8192]:
        child = open_proc(child_pid)
        if child is None:
            continue
        try:
            if child.uid() != uid:
                continue
            identity = child.identity()
            if identity is None:
                continue
            parent = int(identity.get("ppid", 0))
            if parent not in parent_pids:
                continue
            start = int(identity.get("startTime", -1))
            argv = child.cmdline()
            executable = parse_remote_bridge_executable(argv)
            if executable is None:
                continue
            # Revalidate the bound child after reading argv.
            if child.uid() != uid:
                continue
            live = child.identity()
            if live is None or int(live.get("startTime", -2)) != start:
                continue
            if int(live.get("ppid", 0)) != parent:
                continue
            candidates[parent].add(executable)
        finally:
            child.close()
    return {
        parent: (next(iter(values)) if len(values) == 1 else None)
        for parent, values in candidates.items()
    }


def discover_attachment_inventory(
    inventory: list[dict[str, Any]],
    *,
    uid: int | None = None,
    list_pids: ListPidsFn | None = None,
    open_proc: OpenProcFn | None = None,
) -> list[dict[str, Any]]:
    """Discover verified local and remote TUI attachments before endpoint lookup."""
    uid = os.getuid() if uid is None else uid
    list_pids = list_pids or _list_pids
    open_proc = open_proc or open_linux_proc
    pids = list_pids()[:8192]
    sessions = _session_index(inventory)
    rows: list[dict[str, Any]] = []

    for pid in pids:
        if len(rows) >= 256:
            break
        proc = open_proc(pid)
        if proc is None:
            continue
        try:
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
            spec = classify_tui_attachment(argv)
            if spec is None:
                continue

            server_id = None
            if spec.kind == "local":
                server_id = sessions.get(spec.session)
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

            row = {
                "kind": spec.kind,
                "session": spec.session,
                "target": spec.target,
                "serverId": server_id,
                "client": {
                    "pid": bound["pid"],
                    "startTime": bound["startTime"],
                    "ancestors": ancestors,
                },
            }
            rows.append(row)
        finally:
            proc.close()

    remote_parents = {row["client"]["pid"] for row in rows if row["kind"] == "remote"}
    if remote_parents:
        executables = _remote_bridge_executables(remote_parents, pids, open_proc, uid)
        for row in rows:
            if row["kind"] == "remote":
                row["herdrExecutable"] = executables.get(row["client"]["pid"])
    return rows


def discover_attachments(
    inventory: list[dict[str, Any]],
    *,
    uid: int | None = None,
    list_pids: ListPidsFn | None = None,
    open_proc: OpenProcFn | None = None,
) -> dict[str, list[dict[str, Any]]]:
    """Compatibility local attachment map keyed by canonical local server id."""
    found: dict[str, list[dict[str, Any]]] = {}
    for row in discover_attachment_inventory(
        inventory, uid=uid, list_pids=list_pids, open_proc=open_proc
    ):
        if row.get("kind") != "local":
            continue
        server_id = row.get("serverId")
        client = row.get("client")
        if not isinstance(server_id, str) or not isinstance(client, dict):
            continue
        bucket = found.setdefault(server_id, [])
        if len(bucket) >= MAX_CLIENTS_PER_SERVER:
            continue
        if any(item.get("pid") == client.get("pid")
               and item.get("startTime") == client.get("startTime") for item in bucket):
            continue
        bucket.append(client)
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
