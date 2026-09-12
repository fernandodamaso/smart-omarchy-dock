#!/usr/bin/env python3
"""SmartDock browser-profile provider.

Maps Google Chrome windows to the browser profile that owns them.
Modern Chrome (v136+) runs all profiles inside a single browser process, so a
window's PID cannot identify its profile. Instead each tab belongs to a CDP
browser context (one per profile), which this provider resolves through the
browser's DevTools endpoint:

  1. List browser windows from `hyprctl clients -j`.
  2. Match each window title to the active tab of a CDP page target, giving the
     tab's browserContextId.
  3. Resolve each unknown browserContextId to its on-disk profile directory by
     reading "Profile Path" from a chrome://version page inside that context.
  4. Publish window address -> profile key plus profile metadata as a JSON
     snapshot for the dock's FileView consumer.

The browser must be launched with --remote-debugging-port (Omarchy does this
by default). Without a reachable endpoint the provider stays up and reports
available=false; per-window profiles are simply absent.
"""

import argparse
import base64
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request

TITLE_SUFFIXES = (" - Google Chrome", " - Chromium", " - Brave", " - Microsoft Edge")


class CdpError(Exception):
    pass


class WebSocket:
    """Minimal RFC 6455 client sufficient for Chrome DevTools endpoints."""

    def __init__(self, url, timeout=5.0):
        match = re.match(r"ws://([^:/]+):(\d+)(/.*)?$", url)
        if not match:
            raise CdpError("unsupported websocket URL: " + url)
        host, port, resource = match.group(1), int(match.group(2)), match.group(3) or "/"
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            "GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n" % (resource, host, port, key)
        )
        self.sock.sendall(request.encode())
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise CdpError("websocket handshake closed")
            response += chunk
        if b" 101" not in response.split(b"\r\n", 1)[0]:
            raise CdpError("websocket handshake failed: " + response.split(b"\r\n", 1)[0].decode("utf-8", "replace"))
        self._buffer = response.split(b"\r\n\r\n", 1)[1]

    def _read_exact(self, count):
        while len(self._buffer) < count:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise CdpError("websocket closed")
            self._buffer += chunk
        data, self._buffer = self._buffer[:count], self._buffer[count:]
        return data

    def _read_frame(self):
        while True:
            header = self._read_exact(2)
            fin = header[0] & 0x80
            opcode = header[0] & 0x0F
            masked = header[1] & 0x80
            length = header[1] & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read_exact(8))[0]
            mask = self._read_exact(4) if masked else None
            payload = self._read_exact(length)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x9:  # ping
                self._send_frame(0xA, payload)
                continue
            if opcode == 0x8:
                raise CdpError("websocket close frame")
            if opcode in (0x1, 0x2, 0x0):
                return fin, opcode, payload

    def _send_frame(self, opcode, payload):
        mask = os.urandom(4)
        length = len(payload)
        header = bytes([0x80 | opcode])
        if length < 126:
            header += bytes([0x80 | length])
        elif length < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", length)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", length)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def send_text(self, text):
        self._send_frame(0x1, text.encode())

    def recv_text(self):
        parts = []
        while True:
            fin, opcode, payload = self._read_frame()
            parts.append(payload)
            if fin:
                return b"".join(parts).decode("utf-8", "replace")

    def close(self):
        try:
            self._send_frame(0x8, b"")
            self.sock.close()
        except OSError:
            pass


class CdpClient:
    def __init__(self, port):
        self.port = port
        self.ws = None
        self._next_id = 0

    def _ensure_connected(self):
        if self.ws is not None:
            return
        with urllib.request.urlopen(
            "http://127.0.0.1:%d/json/version" % self.port, timeout=3
        ) as reply:
            version = json.loads(reply.read().decode())
        browser_url = version.get("webSocketDebuggerUrl")
        if not browser_url:
            raise CdpError("endpoint has no browser websocket")
        self.ws = WebSocket(browser_url)

    def call(self, method, params=None, session_id=None):
        self._ensure_connected()
        self._next_id += 1
        message = {"id": self._next_id, "method": method}
        if params is not None:
            message["params"] = params
        if session_id is not None:
            message["sessionId"] = session_id
        self.ws.send_text(json.dumps(message))
        while True:
            reply = json.loads(self.ws.recv_text())
            if reply.get("id") == self._next_id:
                break
        if "error" in reply:
            raise CdpError(reply["error"].get("message", method + " failed"))
        return reply.get("result", {})

    def close(self):
        if self.ws is not None:
            self.ws.close()
            self.ws = None


def strip_browser_suffix(title):
    for suffix in TITLE_SUFFIXES:
        if title.endswith(suffix):
            return title[: -len(suffix)]
    return title


def list_windows(classes):
    try:
        output = subprocess.run(
            ["hyprctl", "clients", "-j"], capture_output=True, timeout=5, check=True
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    try:
        clients = json.loads(output)
    except ValueError:
        return []
    wanted = set(classes)
    windows = []
    for client in clients:
        if client.get("class") in wanted and client.get("mapped", True):
            windows.append(
                {
                    "address": str(client.get("address", "")),
                    "title": str(client.get("title", "")),
                    "size": list(client.get("size", [])),
                }
            )
    return windows


def match_window_contexts(client, windows, pages):
    """Match OS windows one-to-one with CDP browser windows."""
    assignments = {}
    cdp_windows = {}
    for page in pages:
        try:
            window_id = client.call(
                "Browser.getWindowForTarget", {"targetId": page["targetId"]}
            )["windowId"]
        except (CdpError, KeyError):
            continue
        group = cdp_windows.setdefault(window_id, {"pages": [], "size": None})
        group["pages"].append(page)
    for window_id, group in cdp_windows.items():
        try:
            bounds = client.call("Browser.getWindowBounds", {"windowId": window_id})["bounds"]
            group["size"] = [bounds.get("width"), bounds.get("height")]
        except (CdpError, KeyError):
            pass
        contexts = {page.get("browserContextId") for page in group["pages"]}
        contexts.discard(None)
        group["context"] = contexts.pop() if len(contexts) == 1 else None
        group["titles"] = {page.get("title", "") for page in group["pages"]}

    os_by_title = {}
    cdp_by_title = {}
    for window in windows:
        os_by_title.setdefault(strip_browser_suffix(window["title"]), []).append(window)
    for window_id, group in cdp_windows.items():
        if not group["context"]:
            continue
        for title in group["titles"]:
            cdp_by_title.setdefault(title, []).append(window_id)

    reserved = set()
    # A title unique on both sides identifies the active CDP window even when
    # another window contains a same-sized background tab with another title.
    unique_matches = []
    for title, matching_windows in os_by_title.items():
        matching_cdp = cdp_by_title.get(title, [])
        if len(matching_windows) == 1 and len(matching_cdp) == 1:
            unique_matches.append((matching_windows[0], matching_cdp[0]))
    unique_owners = {}
    for window, window_id in unique_matches:
        unique_owners.setdefault(window_id, []).append(window)
    for window_id, matching_windows in unique_owners.items():
        if len(matching_windows) == 1:
            assignments[matching_windows[0]["address"]] = cdp_windows[window_id]["context"]
            reserved.add(window_id)

    # Geometry resolves duplicate titles only when it produces a unique pair
    # in both directions. Anything still ambiguous keeps the plain icon.
    remaining = [window for window in windows if window["address"] not in assignments]
    candidates = {}
    for window in remaining:
        title = strip_browser_suffix(window["title"])
        candidates[window["address"]] = {
            window_id for window_id in cdp_by_title.get(title, [])
            if window_id not in reserved and cdp_windows[window_id]["size"] == window["size"]
        }
    owners = {}
    for address, window_ids in candidates.items():
        for window_id in window_ids:
            owners.setdefault(window_id, []).append(address)
    for address, window_ids in candidates.items():
        if len(window_ids) != 1:
            continue
        window_id = next(iter(window_ids))
        if len(owners[window_id]) == 1:
            assignments[address] = cdp_windows[window_id]["context"]
    return assignments


def read_profile_path(client, context_id, pages_in_context):
    """Resolve a browser context to its on-disk profile directory."""
    try:
        target = client.call(
            "Target.createTarget",
            {"url": "chrome://version", "browserContextId": context_id, "hidden": True},
        )
        target_id = target["targetId"]
        try:
            return _profile_path_from_target(client, target_id)
        finally:
            try:
                client.call("Target.closeTarget", {"targetId": target_id})
            except CdpError:
                pass
    except CdpError:
        pass

    # Some contexts refuse createTarget. An already-open chrome://version page
    # is safe to inspect, but existing user pages must never be navigated.
    for page in pages_in_context:
        if not page.get("url", "").startswith("chrome://version"):
            continue
        try:
            result = _profile_path_from_target(client, page["targetId"])
        except CdpError:
            continue
        if result:
            return result
    return ""


def _profile_path_from_target(client, target_id):
    session_id = client.call(
        "Target.attachToTarget", {"targetId": target_id, "flatten": True}
    )["sessionId"]
    try:
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            time.sleep(0.4)
            reply = client.call(
                "Runtime.evaluate",
                {"expression": "document.body ? document.body.innerText : ''"},
                session_id=session_id,
            )
            text = str(reply.get("result", {}).get("value", ""))
            match = re.search(r"Profile Path\s+(\S[^\n]*)", text)
            if match:
                return match.group(1).strip()
        return ""
    finally:
        try:
            client.call("Target.detachFromTarget", {"sessionId": session_id})
        except CdpError:
            pass


def load_profile_names(user_data_dir):
    state_path = os.path.join(user_data_dir, "Local State")
    try:
        with open(state_path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return {}
    cache = state.get("profile", {}).get("info_cache", {})
    return {key: str(value.get("name", "")) for key, value in cache.items()}


def build_snapshot(assignments, context_profiles, port):
    profiles = {}
    names_cache = {}
    for context_id in set(assignments.values()):
        profile_path = context_profiles.get(context_id, "")
        if not profile_path:
            continue
        profile_dir = os.path.basename(profile_path.rstrip("/"))
        user_data_dir = os.path.dirname(profile_path.rstrip("/"))
        if user_data_dir not in names_cache:
            names_cache[user_data_dir] = load_profile_names(user_data_dir)
        avatar = os.path.join(profile_path, "Google Profile Picture.png")
        profiles[profile_dir] = {
            "name": names_cache[user_data_dir].get(profile_dir, ""),
            "path": profile_path,
            "avatarPath": avatar if os.path.isfile(avatar) else "",
        }
    windows = {}
    for address, context_id in assignments.items():
        profile_path = context_profiles.get(context_id, "")
        if profile_path:
            windows[address] = os.path.basename(profile_path.rstrip("/"))
    return {
        "schemaVersion": 1,
        "available": True,
        "port": port,
        "windows": windows,
        "profiles": profiles,
    }


def write_snapshot(state_file, payload, revision):
    payload["revision"] = revision
    directory = os.path.dirname(state_file)
    os.makedirs(directory, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(dir=directory, prefix=".browser-profiles-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        os.replace(temp_path, state_file)
    except OSError:
        try:
            os.unlink(temp_path)
        except OSError:
            pass


def snapshot_windows(snapshot):
    return snapshot.get("windows", {})


def run(args):
    classes = [name.strip() for name in args.classes.split(",") if name.strip()]
    client = CdpClient(args.port)
    context_profiles = {}
    context_retry_after = {}
    revision = 0
    last_windows = None
    last_available = None
    while True:
        try:
            targets = client.call("Target.getTargets").get("targetInfos", [])
            pages = [t for t in targets if t.get("type") == "page"]
            windows = list_windows(classes)
            assignments = match_window_contexts(client, windows, pages)
            by_context = {}
            for page in pages:
                by_context.setdefault(page.get("browserContextId"), []).append(page)
            for context_id in set(assignments.values()):
                if context_id in context_profiles:
                    continue
                if time.monotonic() < context_retry_after.get(context_id, 0):
                    continue
                profile_path = read_profile_path(client, context_id, by_context.get(context_id, []))
                if profile_path:
                    context_profiles[context_id] = profile_path
                else:
                    context_retry_after[context_id] = time.monotonic() + 30
            snapshot = build_snapshot(assignments, context_profiles, args.port)
            current_windows = snapshot_windows(snapshot)
            available = True
        except (CdpError, OSError, ValueError) as error:
            client.close()
            context_profiles.clear()
            context_retry_after.clear()
            snapshot = {
                "schemaVersion": 1,
                "available": False,
                "error": str(error),
                "windows": {},
                "profiles": {},
            }
            current_windows = {}
            available = False
        if current_windows != last_windows or available != last_available:
            revision += 1
            write_snapshot(args.state_file, snapshot, revision)
            last_windows = current_windows
            last_available = available
        time.sleep(args.interval)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--port", type=int, default=9222,
                        help="browser DevTools port (default: 9222)")
    parser.add_argument("--interval", type=float, default=1.5,
                        help="poll interval in seconds (default: 1.5)")
    parser.add_argument("--classes", default="google-chrome",
                        help="comma-separated Hyprland window classes to track")
    args = parser.parse_args()
    try:
        run(args)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
