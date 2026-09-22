# SPDX-License-Identifier: Apache-2.0
"""Bounded SSH transport for attachment-driven remote Herdr endpoints.

Remote support is deliberately process-attached: this module never enumerates
saved machines, provisions Herdr, persists credentials, or exposes a generic
remote command surface. Dynamic metadata crosses the remote shell only as
base64-encoded JSON in fixed bootstrap commands.
"""
from __future__ import annotations

from dataclasses import dataclass
import base64
import hashlib
import json
import os
import queue
import re
import selectors
import shlex
import signal
import subprocess
import threading
import time
from typing import Any, Callable

SSH_OPTIONS = (
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=8",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=3",
)
MAX_REMOTE_TARGET_BYTES = 255
MAX_REMOTE_PATH_BYTES = 1024
MAX_RESOLVER_OUTPUT = 64 * 1024
MAX_RESOLVER_QUEUE = 64
MAX_RESOLVER_WORKERS = 4
RESOLVER_TIMEOUT = 10.0
RESOLVER_JOIN_TIMEOUT = 2.0
HELPER_OWNER_LEASE_SECONDS = 20.0
HELPER_LEASE_RENEW_EVERY = 5.0
REMOTE_PROBE_TIMEOUT = 8.0
REMOTE_BOOTSTRAP_TIMEOUT = 12.0
SESSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\Z")
MACHINE_ID_RE = re.compile(r"[A-Fa-f0-9]{16,128}\Z")


@dataclass(frozen=True)
class RemoteResolution:
    ok: bool
    socket: str = ""
    executable: str = ""
    authority: str = ""
    error: str = ""


def _clean_text(value: object, maximum_bytes: int, *, whitespace: bool = True) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        encoded = value.encode("utf-8", errors="strict")
    except UnicodeError:
        return None
    if len(encoded) > maximum_bytes:
        return None
    for char in value:
        code = ord(char)
        if code < 32 or code == 127 or 0xD800 <= code <= 0xDFFF:
            return None
        if not whitespace and char.isspace():
            return None
    return value


def valid_remote_target(value: object) -> bool:
    target = _clean_text(value, MAX_REMOTE_TARGET_BYTES, whitespace=False)
    return target is not None and not target.startswith("-")


def valid_session(value: object) -> bool:
    return isinstance(value, str) and SESSION_RE.fullmatch(value) is not None


def valid_remote_executable_evidence(value: object) -> bool:
    path = _clean_text(value, MAX_REMOTE_PATH_BYTES, whitespace=True)
    if path is None or path.startswith("-"):
        return False
    return path.startswith("/") or path.startswith("~/") or path.startswith("$HOME/")


def valid_remote_socket(value: object) -> bool:
    path = _clean_text(value, MAX_REMOTE_PATH_BYTES, whitespace=True)
    return path is not None and path.startswith("/")


def attachment_key(target: str, session: str) -> str:
    if not valid_remote_target(target) or not valid_session(session):
        raise ValueError("invalid remote attachment")
    digest = hashlib.sha256(
        json.dumps(["remote", target, session], separators=(",", ":")).encode("utf-8")
    ).hexdigest()[:20]
    return "remote-attachment-" + digest


def endpoint_id(authority: str, socket_path: str, fallback_target: str) -> str:
    """Host-aware public id; aliases dedupe only with proven authority."""
    if not valid_remote_socket(socket_path):
        raise ValueError("invalid remote socket")
    authority_key = authority if MACHINE_ID_RE.fullmatch(authority or "") else "target:" + fallback_target
    digest = hashlib.sha256(
        json.dumps(["remote", authority_key, socket_path], separators=(",", ":")).encode("utf-8")
    ).hexdigest()[:20]
    return "remote-" + digest


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _encoded_json(value: dict[str, Any]) -> str:
    return _b64(json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


_RESOLVER_SOURCE = r'''
import base64, json, os, re, subprocess, sys

def fail(code):
    print(json.dumps({"ok": False, "error": code}, separators=(",", ":")))
    raise SystemExit(0)

def decode(token):
    token += "=" * ((4 - len(token) % 4) % 4)
    return base64.urlsafe_b64decode(token.encode("ascii"))

def clean(value, limit):
    if not isinstance(value, str) or not value:
        return None
    try:
        raw = value.encode("utf-8", errors="strict")
    except UnicodeError:
        return None
    if len(raw) > limit or any(ord(c) < 32 or ord(c) == 127 or 0xD800 <= ord(c) <= 0xDFFF for c in value):
        return None
    return value

try:
    payload = json.loads(decode(sys.argv[1]))
except Exception:
    fail("invalid_request")
session = payload.get("session")
binary = payload.get("executable")
if not isinstance(session, str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}", session) is None:
    fail("invalid_request")
binary = clean(binary, 1024)
if binary is None:
    fail("remote_herdr_unavailable")
home = os.path.expanduser("~")
if binary.startswith("$HOME/"):
    binary = os.path.join(home, binary[6:])
elif binary.startswith("~/"):
    binary = os.path.expanduser(binary)
if not os.path.isabs(binary):
    fail("remote_herdr_unavailable")
binary = os.path.realpath(binary)
if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
    fail("remote_herdr_unavailable")

def socket_path(value):
    value = clean(value, 1024)
    if value is None:
        return None
    value = os.path.expanduser(value)
    if not os.path.isabs(value):
        return None
    return os.path.realpath(value)

sock = None
if session == "default":
    sock = socket_path("~/.config/herdr/herdr.sock")
else:
    try:
        result = subprocess.run(
            [binary, "session", "list"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        fail("remote_herdr_unavailable")
    if result.returncode != 0 or len(result.stdout) > 65536:
        fail("remote_session_unavailable")
    try:
        text = result.stdout.decode("utf-8", errors="strict")
    except UnicodeError:
        fail("remote_session_unavailable")
    for line in text.splitlines()[1:]:
        cols = re.split(r"\s{2,}", line.strip())
        if len(cols) < 4 or cols[0] != session or cols[1].lower() != "running":
            continue
        sock = socket_path(cols[3])
        break
if sock is None or not os.path.exists(sock):
    fail("remote_session_unavailable")

machine_id = ""
try:
    with open("/etc/machine-id", "r", encoding="ascii") as handle:
        candidate = handle.read(160).strip()
    if re.fullmatch(r"[A-Fa-f0-9]{16,128}", candidate):
        machine_id = candidate.lower()
except (OSError, UnicodeError):
    pass
print(json.dumps({
    "ok": True,
    "socket": sock,
    "executable": binary,
    "authority": machine_id,
}, separators=(",", ":")))
'''.strip()

# The remote shell parses only this fixed wrapper. Source and data arguments use
# a base64 alphabet and never contain user-controlled shell syntax.
_EXEC_SOURCE_WRAPPER = (
    "import base64,sys;"
    "s=sys.argv[1];p=sys.argv[2];s+='='*((4-len(s)%4)%4);"
    "sys.argv=['smartdock-remote-resolver',p];"
    "exec(compile(base64.urlsafe_b64decode(s.encode('ascii')),'<smartdock-remote>','exec'))"
)

_HELPER_WRAPPER = (
    "import base64,sys;"
    "d=lambda s:base64.urlsafe_b64decode((s+'='*((4-len(s)%4)%4)).encode('ascii'));"
    "code=d(sys.argv[1]);sock=d(sys.argv[2]).decode('utf-8');"
    "sys.argv=['smartdock-herdr-helper',sock,'--owner-lease-seconds',sys.argv[3]];"
    "exec(compile(code,'<smartdock-herdr-helper>','exec'),{'__name__':'__main__'})"
)


def ssh_argv(target: str, remote_command: str) -> list[str]:
    if not valid_remote_target(target):
        raise ValueError("invalid remote target")
    if not isinstance(remote_command, str) or not remote_command:
        raise ValueError("invalid remote command")
    return ["ssh", *SSH_OPTIONS, "--", target, remote_command]


def resolver_ssh_argv(target: str, session: str, executable: str) -> list[str]:
    if not valid_remote_target(target) or not valid_session(session):
        raise ValueError("invalid remote resolver identity")
    if not valid_remote_executable_evidence(executable):
        raise ValueError("invalid remote executable")
    source = _b64(_RESOLVER_SOURCE.encode("utf-8"))
    payload = _encoded_json({"session": session, "executable": executable})
    # shell words after -c are base64url / fixed literals only.
    command = "python3 -c " + shlex.quote(_EXEC_SOURCE_WRAPPER) + " " + source + " " + payload
    return ssh_argv(target, command)


def helper_ssh_argv(
    target: str,
    socket_path: str,
    helper_source: bytes,
    *,
    lease_seconds: float = HELPER_OWNER_LEASE_SECONDS,
) -> list[str]:
    if not valid_remote_target(target) or not valid_remote_socket(socket_path):
        raise ValueError("invalid remote helper identity")
    if not isinstance(helper_source, (bytes, bytearray)) or not helper_source:
        raise ValueError("missing helper source")
    if not (1.0 <= float(lease_seconds) <= 300.0):
        raise ValueError("invalid helper lease")
    source = _b64(bytes(helper_source))
    socket_data = _b64(socket_path.encode("utf-8"))
    ttl = str(int(lease_seconds))
    command = "python3 -c " + shlex.quote(_HELPER_WRAPPER) + " " + source + " " + socket_data + " " + ttl
    return ssh_argv(target, command)


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


def run_ssh_bounded(
    argv: list[str],
    *,
    timeout: float = RESOLVER_TIMEOUT,
    limit: int = MAX_RESOLVER_OUTPUT,
    cancelled: threading.Event | None = None,
) -> tuple[bool, bytes]:
    try:
        proc = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return False, b""
    assert proc.stdout is not None
    fd = proc.stdout.fileno()
    os.set_blocking(fd, False)
    selector = selectors.DefaultSelector()
    selector.register(fd, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    data = bytearray()
    ok = False
    try:
        while True:
            if cancelled is not None and cancelled.is_set():
                break
            if len(data) > limit:
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
                ok = proc.returncode == 0 and len(data) <= limit
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            if not selector.select(min(0.1, remaining)):
                continue
            try:
                chunk = os.read(fd, min(65536, limit + 1 - len(data)))
            except BlockingIOError:
                continue
            if not chunk:
                continue
            data.extend(chunk)
    finally:
        selector.close()
        if proc.poll() is None:
            _stop_process(proc)
        proc.stdout.close()
    return ok, bytes(data[:limit + 1])


def parse_resolution_output(raw: bytes, target: str) -> RemoteResolution:
    if not isinstance(raw, (bytes, bytearray)) or len(raw) > MAX_RESOLVER_OUTPUT:
        return RemoteResolution(False, error="remote_metadata_invalid")
    try:
        value = json.loads(bytes(raw).decode("utf-8", errors="strict"))
    except (ValueError, UnicodeError, TypeError):
        return RemoteResolution(False, error="remote_metadata_invalid")
    if not isinstance(value, dict):
        return RemoteResolution(False, error="remote_metadata_invalid")
    if value.get("ok") is not True:
        error = value.get("error")
        if error not in (
            "invalid_request",
            "remote_herdr_unavailable",
            "remote_session_unavailable",
        ):
            error = "remote_metadata_unavailable"
        return RemoteResolution(False, error=error)
    socket_path = value.get("socket")
    executable = value.get("executable")
    authority = value.get("authority", "")
    if not valid_remote_socket(socket_path) or not valid_remote_executable_evidence(executable):
        return RemoteResolution(False, error="remote_metadata_invalid")
    if authority and not MACHINE_ID_RE.fullmatch(authority):
        return RemoteResolution(False, error="remote_metadata_invalid")
    # Do not locally canonicalize a remote path.
    return RemoteResolution(
        True,
        socket=str(socket_path),
        executable=str(executable),
        authority=str(authority).lower(),
    )


def resolve_remote_endpoint(
    target: str,
    session: str,
    executable: str,
    *,
    cancelled: threading.Event | None = None,
    runner: Callable[..., tuple[bool, bytes]] = run_ssh_bounded,
) -> RemoteResolution:
    try:
        argv = resolver_ssh_argv(target, session, executable)
    except ValueError:
        return RemoteResolution(False, error="remote_metadata_invalid")
    ok, raw = runner(argv, timeout=RESOLVER_TIMEOUT, limit=MAX_RESOLVER_OUTPUT, cancelled=cancelled)
    if not ok:
        return RemoteResolution(False, error="ssh_unavailable")
    return parse_resolution_output(raw, target)


class RemoteResolverPool:
    """Finite resolver workers with token-tagged bounded results."""

    def __init__(
        self,
        resolver: Callable[..., RemoteResolution] = resolve_remote_endpoint,
        *,
        workers: int = MAX_RESOLVER_WORKERS,
        queue_size: int = MAX_RESOLVER_QUEUE,
    ) -> None:
        workers = max(1, min(int(workers), MAX_RESOLVER_WORKERS))
        queue_size = max(workers, min(int(queue_size), MAX_RESOLVER_QUEUE))
        self.resolver = resolver
        self.jobs: queue.Queue[tuple[str, int, str, str, str] | None] = queue.Queue(queue_size)
        self.results: queue.Queue[tuple[str, int, RemoteResolution]] = queue.Queue(queue_size)
        self.cancelled = threading.Event()
        self.threads = [
            threading.Thread(target=self._worker, name=f"smartdock-herdr-remote-{index}", daemon=True)
            for index in range(workers)
        ]
        for thread in self.threads:
            thread.start()

    def submit(self, key: str, token: int, target: str, session: str, executable: str) -> bool:
        if self.cancelled.is_set():
            return False
        try:
            self.jobs.put_nowait((key, token, target, session, executable))
            return True
        except queue.Full:
            return False

    def _worker(self) -> None:
        while not self.cancelled.is_set():
            try:
                job = self.jobs.get(timeout=0.1)
            except queue.Empty:
                continue
            if job is None:
                self.jobs.task_done()
                return
            key, token, target, session, executable = job
            try:
                result = self.resolver(
                    target, session, executable, cancelled=self.cancelled
                )
            except Exception:
                result = RemoteResolution(False, error="remote_metadata_unavailable")
            self.jobs.task_done()
            if self.cancelled.is_set():
                return
            while not self.cancelled.is_set():
                try:
                    self.results.put((key, token, result), timeout=0.1)
                    break
                except queue.Full:
                    continue

    def poll(self, limit: int = 64) -> list[tuple[str, int, RemoteResolution]]:
        output = []
        for _ in range(max(0, min(limit, 64))):
            try:
                output.append(self.results.get_nowait())
            except queue.Empty:
                break
        return output

    def close(self) -> None:
        self.cancelled.set()
        for _ in self.threads:
            try:
                self.jobs.put_nowait(None)
            except queue.Full:
                break
        deadline = time.monotonic() + RESOLVER_JOIN_TIMEOUT
        for thread in self.threads:
            thread.join(timeout=max(0.0, deadline - time.monotonic()))
