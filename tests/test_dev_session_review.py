"""PR #65 regressions; no QEMU, SSH server, or host desktop required."""
import contextlib
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import dev_session as ds


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="smartdock-review-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.guest = self.root / "guest"
        self.guest.mkdir()
        self.source = self.root / "source"
        self.source.mkdir()
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.record = {
            "name": "review", "state": "ready", "mode": "plugin",
            "source": str(self.source), "source_digest": "synced-source",
            "evidence_path": str(self.evidence),
            "guest_config_path": ds.GUEST_CONFIG_PATH,
            "config_path": ds.GUEST_CONFIG_PATH,
        }

    def guest_path(self, remote):
        return self.guest / remote.lstrip("/")

    def local_ssh(self, record, command, timeout):
        self.assertEqual(record["name"], "review")
        # Run the production-generated guest command in a private filesystem.
        command = command.replace("/home/admin", str(self.guest / "home/admin"))
        return subprocess.run(["bash", "-c", command], capture_output=True,
                              text=True, timeout=timeout)

    def local_scp(self, record, local, remote):
        self.assertEqual(record["name"], "review")
        shutil.copyfile(local, self.guest_path(remote))

    def init_source(self):
        subprocess.run(["git", "init", "-q", str(self.source)], check=True)
        (self.source / "tracked.txt").write_text("tracked\n")
        (self.source / "keep.txt").write_text("kept\n")
        subprocess.run(["git", "-C", str(self.source), "add", "."], check=True)

    def test_manifest_accepts_unstaged_deletion(self):
        self.init_source()
        _, before = ds.source_manifest(self.source)
        (self.source / "tracked.txt").unlink()
        entries, after = ds.source_manifest(self.source)
        self.assertEqual([e["path"] for e in entries], ["keep.txt"])
        self.assertNotEqual(before, after)

    def test_sync_applies_unstaged_rename_and_removes_old_guest_path(self):
        self.init_source()
        (self.source / "tracked.txt").rename(self.source / "renamed file.txt")
        entries, digest = ds.source_manifest(self.source)
        archive = self.root / "source.tar"
        manifest = self.root / "manifest.json"
        ds._write_source_archive(self.source, entries, archive)
        manifest.write_text(json.dumps({"entries": entries, "digest": digest}))
        dest = self.guest / "candidate"
        dest.mkdir()
        (dest / "tracked.txt").write_text("old guest bytes")
        result = subprocess.run([
            sys.executable, "-c", ds.GUEST_APPLY_SCRIPT, str(archive),
            str(manifest), str(self.guest / "candidate.new"), str(dest),
        ], check=True, capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), digest)
        self.assertFalse((dest / "tracked.txt").exists())
        self.assertEqual((dest / "renamed file.txt").read_text(), "tracked\n")
        self.assertFalse((self.source / "tracked.txt").exists())

    def test_manifest_keeps_dangling_symlinks_and_rejects_special_files(self):
        self.init_source()
        (self.source / "link").symlink_to("missing-target")
        entries, _ = ds.source_manifest(self.source)
        self.assertEqual(next(e["kind"] for e in entries if e["path"] == "link"), "symlink")
        (self.source / "tracked.txt").unlink()
        os.mkfifo(self.source / "tracked.txt")
        with self.assertRaisesRegex(ValueError, "unsupported source path kind"):
            ds.source_manifest(self.source)

    def test_archive_still_rejects_deletion_after_inventory(self):
        self.init_source()
        entries, _ = ds.source_manifest(self.source)
        (self.source / "tracked.txt").unlink()
        with self.assertRaisesRegex(ValueError, "changed during archive"):
            ds._write_source_archive(self.source, entries, self.root / "source.tar")

    def prepare_theme(self):
        colors = self.root / "colors.toml"
        shell = self.root / "shell.toml"
        colors.write_text('background = "#112233"\n')
        shell.write_text('opacity = 0.9\n')
        candidate = self.guest_path(ds.GUEST_CANDIDATE)
        candidate.mkdir(parents=True)
        (candidate / "Overlay.qml").write_text("Item {}\n")
        return colors, shell

    def test_plugin_theme_can_be_installed_twice_and_remains_readonly(self):
        colors, shell = self.prepare_theme()
        with mock.patch.object(ds, "_host_theme_files", return_value=(colors, shell)), \
             mock.patch.object(ds, "_run_ssh", side_effect=self.local_ssh), \
             mock.patch.object(ds, "_scp_to_guest", side_effect=self.local_scp):
            ds.install_guest_plugin_runtime(self.record, {"first_party_plugin_ids": []})
            colors.write_text('background = "#445566"\n')
            ds.install_guest_plugin_runtime(self.record, {"first_party_plugin_ids": []})
        theme = self.guest_path("/home/admin/.local/state/omarchy/current/theme")
        for src in (colors, shell):
            dest = theme / src.name
            self.assertEqual(dest.read_bytes(), src.read_bytes())
            self.assertEqual(dest.stat().st_mode & 0o222, 0)
        self.assertEqual(sorted(p.name for p in theme.iterdir()), ["colors.toml", "shell.toml"])

    def test_failed_theme_upload_preserves_previous_readonly_file(self):
        colors, shell = self.prepare_theme()
        with mock.patch.object(ds, "_host_theme_files", return_value=(colors, shell)), \
             mock.patch.object(ds, "_run_ssh", side_effect=self.local_ssh), \
             mock.patch.object(ds, "_scp_to_guest", side_effect=self.local_scp):
            ds.install_guest_plugin_runtime(self.record, {"first_party_plugin_ids": []})
        dest = self.guest_path("/home/admin/.local/state/omarchy/current/theme/colors.toml")
        before = dest.read_bytes()

        def broken_upload(record, local, remote):
            if Path(local) == colors:
                self.guest_path(remote).write_text("incomplete")
                raise RuntimeError("upload interrupted")
            self.local_scp(record, local, remote)

        with mock.patch.object(ds, "_host_theme_files", return_value=(colors, shell)), \
             mock.patch.object(ds, "_run_ssh", side_effect=self.local_ssh), \
             mock.patch.object(ds, "_scp_to_guest", side_effect=broken_upload):
            with self.assertRaisesRegex(RuntimeError, "upload interrupted"):
                ds.install_guest_plugin_runtime(self.record, {"first_party_plugin_ids": []})
        self.assertEqual(dest.read_bytes(), before)
        self.assertEqual(dest.stat().st_mode & 0o222, 0)
        self.assertEqual(len(list(dest.parent.iterdir())), 2)

    def capture(self):
        ready = {"wayland_display": "wayland-test",
                 "hyprland_instance_signature": "guest-signature", "output": "Virtual-1"}

        def ssh(record, command, timeout):
            if "grim" in command:
                return subprocess.CompletedProcess(command, 0, "", "")
            return self.local_ssh(record, command, timeout)

        def scp(record, remote, local):
            Path(local).write_bytes(ds.PNG_SIGNATURE + b"x" * 64)

        with mock.patch.object(ds, "_require_runnable_session", return_value=dict(self.record)), \
             mock.patch.object(ds, "_read_guest_ready", return_value=ready), \
             mock.patch.object(ds, "_commit_live_record"), \
             mock.patch.object(ds, "_run_ssh", side_effect=ssh), \
             mock.patch.object(ds, "_scp_from_guest", side_effect=scp):
            path = ds.guest_capture("review")
        return json.loads(path.with_suffix(".json").read_text())

    def test_capture_hashes_guest_settings_not_unsynced_host_defaults(self):
        (self.source / "config").mkdir()
        host = self.source / "config/dock.json"
        host.write_text('{"iconSize": 42}\n')
        guest = self.guest_path(ds.GUEST_CONFIG_PATH)
        guest.parent.mkdir(parents=True)
        guest.write_text('{"iconSize": 48}\n')
        a = self.capture()
        self.assertEqual(a["config_digest"], hashlib.sha256(guest.read_bytes()).hexdigest())
        self.assertEqual(a["config_path"], ds.GUEST_CONFIG_PATH)
        host.write_text('{"iconSize": 96}\n')
        b = self.capture()
        self.assertEqual(a["config_digest"], b["config_digest"])
        guest.write_text('{"iconSize": 36}\n')
        c = self.capture()
        self.assertNotEqual(b["config_digest"], c["config_digest"])
        self.assertEqual(c["source_digest"], "synced-source")

    def test_capture_read_error_fails_without_recording_false_evidence(self):
        with mock.patch.object(ds, "_guest_config_digest", side_effect=RuntimeError("read denied")):
            with self.assertRaisesRegex(RuntimeError, "read denied"):
                self.capture()
        self.assertEqual(list(self.evidence.glob("frame-*")), [])

    def test_config_digest_rejects_bad_readback(self):
        for output in ('"not-a-hash"', '{}', 'not JSON'):
            with self.subTest(output=output), mock.patch.object(
                ds, "_run_ssh", return_value=subprocess.CompletedProcess([], 0, output, "")
            ):
                with self.assertRaisesRegex(RuntimeError, "malformed guest config digest"):
                    ds._guest_config_digest(self.record, ds.GUEST_CONFIG_PATH)

    def test_capture_does_not_substitute_host_defaults_when_guest_config_missing(self):
        (self.source / "config").mkdir()
        (self.source / "config/dock.json").write_text('{"iconSize": 42}\n')
        self.assertIsNone(self.capture()["config_digest"])


# The helper runs the actual supervisor and detached child; only unavailable
# VM/desktop boundaries are replaced. Shorten its normal five-second kill grace.
SIGNAL_HELPER = r'''
import json, os, signal, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import dev_session as ds
root, phase = Path(sys.argv[2]), sys.argv[3]
name = "signal-test"
session = ds.session_dir(name)
evidence = session / "evidence"
evidence.mkdir(parents=True)
paths = {"name": name, "session": session, "evidence": evidence,
         "source": root, "base_image": root / "base"}
ds.prepare_private_inputs = lambda *a, **k: paths
ds._capture_host_state = lambda *a: {"production_settings_sha256": "unchanged"}
ds._launch_rule = lambda *a: None
ds._disable_launch_rule = lambda *a: None
ds.qemu_argv = lambda *a: [sys.executable, "-c", "import time; time.sleep(60)"]
ds._wait_for_owned_port = lambda *a: None
ds._place_owned_window = lambda *a: {"address": "0xfixture"}
ds._show_both_qemu_heads = lambda *a: [{"address": "0xfixture", "at": [0, 0]}]
def gate(record, evidence):
    if phase == "boot":
        (root / "gate").write_text("boot")
        time.sleep(60)
ds._wait_for_guest_setup = gate
ds.sync_source = lambda *a: None
ds._run_guest_argv = lambda *a: subprocess.CompletedProcess([], 0, "", "")
def dock(name):
    record = ds.read_record(name)
    record.update(state="ready", host_pid=42, guest_dock_pid=42)
    ds._write_record(record)
    (root / "gate").write_text("ready")
    return record
ds.start_guest_dock = dock
terminate = ds._terminate_owned
def cleanup(record):
    if phase == "repeat":
        os.kill(os.getpid(), signal.SIGHUP)
        os.kill(os.getpid(), signal.SIGTERM)
    return terminate(record, wait_seconds=0.05)
ds._terminate_owned = cleanup
if phase == "spawn":
    popen = ds.subprocess.Popen
    def spawn(*args, **kwargs):
        child = popen(*args, **kwargs)
        (root / "spawn.json").write_text(json.dumps(ds.process_identity(child.pid)))
        (root / "gate").write_text("spawn")
        os.kill(os.getpid(), signal.SIGTERM)
        return child
    ds.subprocess.Popen = spawn
previous = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
try:
    ds.start(name, source=root, base_image=root / "base", mode="standalone", workspace="4")
except BaseException:
    pass
finally:
    restored = all(signal.getsignal(sig) == handler for sig, handler in previous.items())
    (root / "handlers-restored").write_text(str(restored))
'''


class SignalCleanupTests(unittest.TestCase):
    def check_signal(self, signum, phase):
        with tempfile.TemporaryDirectory(prefix="smartdock-signals-") as tmp:
            root = Path(tmp)
            env = {**os.environ, "XDG_STATE_HOME": str(root / "state"),
                   "XDG_RUNTIME_DIR": str(root / "runtime")}
            proc = subprocess.Popen([sys.executable, "-c", SIGNAL_HELPER,
                                     str(Path(ds.__file__).parent), tmp, phase],
                                    env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    start_new_session=True, text=True)
            record_path = root / "state/smartdock/dev-sessions/signal-test/record.json"
            child = None
            try:
                deadline = time.monotonic() + 10
                while not (root / "gate").exists() and proc.poll() is None:
                    if time.monotonic() > deadline:
                        self.fail("supervisor did not reach signal gate")
                    time.sleep(0.02)
                self.assertTrue((root / "gate").exists())
                record = json.loads(record_path.read_text())
                child = (json.loads((root / "spawn.json").read_text())["pid"]
                         if phase == "spawn" else record["qemu_pid"])
                self.assertNotEqual(child, proc.pid)
                # Do not race the last ready-record write with proc.wait().
                if phase == "ready":
                    time.sleep(0.05)
                if phase != "spawn":
                    proc.send_signal(signum)
                stdout, stderr = proc.communicate(timeout=10)
                latest = json.loads(record_path.read_text())
                self.assertNotIn(latest["state"], ds.ACTIVE_STATES, (stdout, stderr))
                ports = root / "runtime/smartdock-dev/ports"
                self.assertEqual(list(ports.glob("*.json")), [], "port reservation leaked")
                self.assertEqual((root / "handlers-restored").read_text(), "True")
                stat = Path(f"/proc/{child}/stat")
                self.assertTrue(not stat.exists() or stat.read_text().split(")", 1)[1].split()[0] == "Z",
                                "detached child survived supervisor termination")
            finally:
                if proc.poll() is None:
                    proc.kill()
                proc.communicate(timeout=5)
                if child is not None:
                    with contextlib.suppress(ProcessLookupError):
                        os.kill(child, signal.SIGKILL)

    def test_signal_during_spawn_waits_until_child_ownership_is_recorded(self):
        self.check_signal(signal.SIGTERM, "spawn")

    def test_repeated_signals_do_not_interrupt_cleanup(self):
        self.check_signal(signal.SIGTERM, "repeat")

    def test_sigterm_cleans_up_ready_session(self):
        self.check_signal(signal.SIGTERM, "ready")

    def test_sighup_cleans_up_ready_session(self):
        self.check_signal(signal.SIGHUP, "ready")

    def test_sigint_still_cleans_up_ready_session(self):
        self.check_signal(signal.SIGINT, "ready")

    def test_sigterm_cleans_up_during_guest_boot(self):
        self.check_signal(signal.SIGTERM, "boot")

    def test_sighup_cleans_up_during_guest_boot(self):
        self.check_signal(signal.SIGHUP, "boot")


if __name__ == "__main__":
    unittest.main()
