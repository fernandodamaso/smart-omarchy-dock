# SPDX-License-Identifier: Apache-2.0
"""Local Herdr session discovery adapted from omaherdr's Discovery helpers.

This module performs bounded metadata discovery only. It never inspects terminal
transcripts, detects agents itself, starts Herdr, or talks to omaherdr.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
import re
import selectors
import signal
import subprocess
import time
from typing import Callable

MAX_SERVERS = 64
MAX_SESSION_OUTPUT = 64 * 1024
SESSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\Z")


@dataclass(frozen=True)
class RunResult:
    ok: bool
    text: str = ""
    error: str = ""


def _stop_process(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (OSError, ProcessLookupError):
        try:
            proc.terminate()
        except OSError:
            return
    try:
        proc.wait(timeout=0.4)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (OSError, ProcessLookupError):
        try:
            proc.kill()
        except OSError:
            return
    try:
        proc.wait(timeout=0.4)
    except subprocess.TimeoutExpired:
        pass


def run_bounded(argv: list[str], timeout: float = 3.0, limit: int = MAX_SESSION_OUTPUT) -> RunResult:
    """Run a fixed local metadata command with a hard stdout/time bound."""
    try:
        proc = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return RunResult(False, error="command_unavailable")

    assert proc.stdout is not None
    fd = proc.stdout.fileno()
    os.set_blocking(fd, False)
    selector = selectors.DefaultSelector()
    selector.register(fd, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    data = bytearray()
    error = ""
    try:
        while True:
            if len(data) > limit:
                error = "output_too_large"
                break
            if proc.poll() is not None:
                while len(data) <= limit:
                    try:
                        chunk = os.read(fd, min(65536, limit + 1 - len(data)))
                    except BlockingIOError:
                        break
                    if not chunk:
                        break
                    data.extend(chunk)
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                error = "timeout"
                break
            ready = selector.select(min(0.1, remaining))
            if not ready:
                continue
            try:
                chunk = os.read(fd, min(65536, limit + 1 - len(data)))
            except BlockingIOError:
                continue
            if not chunk:
                if proc.poll() is not None:
                    break
                continue
            data.extend(chunk)
    finally:
        selector.close()
        if error:
            _stop_process(proc)
        else:
            try:
                proc.wait(timeout=max(0.0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                error = "timeout"
                _stop_process(proc)
        proc.stdout.close()

    if len(data) > limit:
        return RunResult(False, error="output_too_large")
    if error:
        return RunResult(False, error=error)
    if proc.returncode != 0:
        return RunResult(False, error="command_failed")
    try:
        return RunResult(True, bytes(data).decode("utf-8", errors="strict"))
    except UnicodeError:
        return RunResult(False, error="invalid_output")


def valid_session(value: object) -> bool:
    return isinstance(value, str) and SESSION_RE.fullmatch(value) is not None


def normalize_socket(value: object, home: str | None = None) -> str | None:
    if not isinstance(value, str) or not value or len(value) > 1024:
        return None
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        return None
    if value.startswith("~/"):
        root = home if home is not None else os.path.expanduser("~")
        value = os.path.join(root, value[2:])
    if not os.path.isabs(value):
        return None
    return os.path.realpath(value)


def parse_session_list(text: str, home: str | None = None) -> dict[str, dict[str, str]]:
    """Parse the bounded herdr session list table used by the pinned upstream."""
    rows: dict[str, dict[str, str]] = {}
    for line in text.splitlines()[1:]:
        cols = re.split(r"\s{2,}", line.strip())
        if len(cols) < 4:
            continue
        name, status = cols[0], cols[1]
        socket_path = normalize_socket(cols[3], home)
        if not valid_session(name) or not socket_path:
            continue
        rows[name] = {"status": status[:32], "socket": socket_path}
        if len(rows) >= MAX_SERVERS:
            break
    return rows


def endpoint_id(socket_path: str) -> str:
    digest = hashlib.sha256(socket_path.encode("utf-8")).hexdigest()[:16]
    return "local-" + digest


def _default_socket(home: str | None = None) -> str:
    root = home if home is not None else os.path.expanduser("~")
    return os.path.realpath(os.path.join(root, ".config/herdr/herdr.sock"))


class Discovery:
    """Resolve local running Herdr sessions to unique Unix-socket endpoints."""

    def __init__(
        self,
        runner: Callable[[list[str], float, int], RunResult] = run_bounded,
        home: str | None = None,
        exists: Callable[[str], bool] = os.path.exists,
    ) -> None:
        self.runner = runner
        self.home = home
        self.exists = exists
        self.last_fingerprint: tuple[object, ...] | None = None

    @property
    def session_dir(self) -> str:
        root = self.home if self.home is not None else os.path.expanduser("~")
        return os.path.join(root, ".config/herdr")

    def fingerprint(self) -> tuple[object, ...]:
        """Cheap recursive socket signal; no Herdr command is run here."""
        def signature(path: str) -> tuple[int, int] | None:
            try:
                stat = os.stat(path, follow_symlinks=False)
                return (stat.st_mtime_ns, stat.st_ino)
            except OSError:
                return None

        default = _default_socket(self.home)
        named_root = os.path.join(self.session_dir, "sessions")
        names: list[tuple[str, object, object]] = []
        try:
            with os.scandir(named_root) as entries:
                for entry in entries:
                    if len(names) >= 128:
                        break
                    if not entry.is_dir(follow_symlinks=False) or not valid_session(entry.name):
                        continue
                    names.append((
                        entry.name,
                        signature(entry.path),
                        signature(os.path.join(entry.path, "herdr.sock")),
                    ))
        except OSError:
            pass
        names.sort()
        return (
            signature(self.session_dir),
            signature(default),
            signature(named_root),
            tuple(names),
        )

    def changed(self) -> bool:
        current = self.fingerprint()
        changed = self.last_fingerprint is not None and current != self.last_fingerprint
        self.last_fingerprint = current
        return changed

    def scan(self) -> tuple[list[dict[str, object]], str]:
        result = self.runner(["herdr", "session", "list"], 3.0, MAX_SESSION_OUTPUT)
        parsed = parse_session_list(result.text, self.home) if result.ok else {}
        default = _default_socket(self.home)
        by_socket: dict[str, dict[str, object]] = {}

        # Herdr documents deterministic local socket paths. Direct discovery
        # keeps detached/unattached sessions visible when the metadata CLI is
        # unavailable; the helper still determines whether a stale socket is live.
        if self.exists(default):
            by_socket[default] = {
                "id": endpoint_id(default), "host": "local", "socket": default,
                "sessions": ["default"],
            }

        named_root = os.path.join(self.session_dir, "sessions")
        try:
            with os.scandir(named_root) as entries:
                for entry in entries:
                    if len(by_socket) >= MAX_SERVERS:
                        break
                    if not entry.is_dir(follow_symlinks=False) or not valid_session(entry.name):
                        continue
                    candidate = normalize_socket(os.path.join(entry.path, "herdr.sock"), self.home)
                    if not candidate or not self.exists(candidate):
                        continue
                    item = by_socket.setdefault(candidate, {
                        "id": endpoint_id(candidate), "host": "local", "socket": candidate,
                        "sessions": [],
                    })
                    item["sessions"].append(entry.name)  # type: ignore[index]
        except OSError:
            pass

        for name, row in parsed.items():
            if str(row.get("status", "")).lower() != "running":
                continue
            socket_path = row["socket"]
            entry = by_socket.setdefault(socket_path, {
                "id": endpoint_id(socket_path), "host": "local",
                "socket": socket_path, "sessions": [],
            })
            entry["sessions"].append(name)  # type: ignore[index]

        # Only the default endpoint gets a default fallback. A named-session
        # lookup can never silently resolve to the default socket.
        if self.exists(default):
            entry = by_socket.setdefault(default, {
                "id": endpoint_id(default), "host": "local",
                "socket": default, "sessions": [],
            })
            sessions = entry["sessions"]  # type: ignore[assignment]
            if "default" not in sessions:
                sessions.insert(0, "default")

        servers = list(by_socket.values())[:MAX_SERVERS]
        for entry in servers:
            sessions = sorted(set(entry["sessions"]), key=lambda name: (name != "default", name))  # type: ignore[index]
            entry["sessions"] = sessions
            entry["session"] = sessions[0] if sessions else "default"
            entry["label"] = sessions[0] if len(sessions) == 1 else ", ".join(sessions[:3])
        servers.sort(key=lambda item: (item["session"] != "default", str(item["session"])))
        self.last_fingerprint = self.fingerprint()

        if servers:
            # The local socket itself is authoritative for this milestone. A
            # failed optional metadata probe must not downgrade a live endpoint.
            return servers, ""
        return [], result.error or "no_running_sessions"
