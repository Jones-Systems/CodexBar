#!/usr/bin/env python3
"""Small portable harness fixtures; every native command is replaced by a fake."""

import base64
from contextlib import nullcontext, redirect_stderr, redirect_stdout
import errno
import io
import json
import os
from pathlib import Path
import plistlib
import signal
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET
import zipfile

import jones_update_harness as harness


KEY = base64.b64encode(bytes(range(32))).decode("ascii")
SIGNATURE = base64.b64encode(bytes(range(64))).decode("ascii")
FIXTURE_ID = "a65bf229-e140-40a4-a9b6-248ac4bd5d65"
REVISION = "a" * 40


class HarnessTests(unittest.TestCase):
    def setUp(self):
        parent = Path(os.environ.get("CODEXBAR_TEST_SCRATCH_PARENT", harness.ROOT / ".build"))
        parent.mkdir(exist_ok=True)
        self.assertEqual(parent.resolve(), parent.absolute())
        self.assertIn(harness.ROOT, parent.resolve().parents)
        self.temporary = tempfile.TemporaryDirectory(prefix="jones-harness-test-", dir=parent)
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def rejects(self, code, function, *args, **kwargs):
        with self.assertRaises(harness.candidate.CandidateError) as caught:
            function(*args, **kwargs)
        self.assertEqual(caught.exception.code, code)

    def original(self):
        return dict(CFBundleIdentifier=harness.candidate.BUNDLE_ID, CFBundleExecutable="CodexBar",
                    JonesSourceRevision=REVISION, JonesBuildOrigin="local", JonesBuildRun="",
                    **{key: "production" for key in harness.FORBIDDEN})

    def test_fixture_removes_all_production_state_metadata(self):
        original = self.original()
        info = harness.fixture_info(original, FIXTURE_ID, KEY, 39541, harness.BUILD_A)
        self.assertEqual(info["CFBundleIdentifier"], harness.BUNDLE_ID)
        self.assertIs(info["JonesUpdateHarness"], True)
        self.assertEqual(info["JonesSourceRevision"], REVISION)
        self.assertEqual(info["SUFeedURL"], "http://127.0.0.1:39541/appcast.xml")
        self.assertTrue(all(key not in info for key in harness.FORBIDDEN))
        self.assertEqual(original, self.original())
        for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUAutomaticallyUpdate"):
            self.assertIs(info[key], True)
        self.assertIs(type(info["SUSignedFeedFailureExpirationInterval"]), int)
        self.assertEqual(info["SUSignedFeedFailureExpirationInterval"], 0)

    def test_fixture_refuses_foreign_source_invalid_keys_and_ports(self):
        original = self.original()
        self.rejects("fixture-source", harness.fixture_info, {**original, "CFBundleIdentifier": "com.steipete.codexbar"},
                     FIXTURE_ID, KEY, 39541, harness.BUILD_A)
        self.rejects("fixture-source", harness.fixture_info, {**original, "JonesSourceRevision": "short"},
                     FIXTURE_ID, KEY, 39541, harness.BUILD_A)
        for key in ("", "invalid", base64.b64encode(bytes(31)).decode(), harness.candidate.UPSTREAM_KEY):
            self.rejects("fixture-key", harness.public_key, key)
        for port in (80, True, -1, 65536):
            self.rejects("fixture-port", harness.fixture_info, original, FIXTURE_ID, KEY, port, harness.BUILD_A)

    def test_feed_length_and_signature_are_signed_as_exact_bytes(self):
        content = harness.feed(39541, SIGNATURE, 1234)
        root = ET.fromstring(content)
        enclosure = root.find("./channel/item/enclosure")
        self.assertEqual(enclosure.attrib["length"], "1234")
        self.assertEqual(enclosure.attrib["url"], "http://127.0.0.1:39541/update.zip")
        signed = harness.signed_feed(content, SIGNATURE)
        self.assertEqual(signed[:len(content)], content)
        footer = signed[len(content):].decode("ascii")
        self.assertEqual(footer, f"<!-- sparkle-signatures:\nedSignature: {SIGNATURE}\nlength: {len(content)}\n-->\n")
        self.assertEqual(ET.fromstring(signed).tag, "rss")

    def test_prepare_refuses_non_ci_before_creating_any_files(self):
        with patch.object(harness.sys, "platform", "darwin"):
            self.rejects("fixture-ci", harness.prepare, self.root / "unused.app", self.root / "output",
                         self.root / "signer", 39541, {})
        self.assertEqual(list(self.root.iterdir()), [])

    def test_native_fixture_checks_both_slices_of_app_and_sparkle(self):
        bundle = self.root / "CodexBar.app"
        manifest = {"fixture_id": FIXTURE_ID, "source_revision": REVISION, "public_key": KEY, "port": 39541}
        info = harness.fixture_info(self.original(), FIXTURE_ID, KEY, 39541, harness.BUILD_A)
        main = bundle / "Contents/MacOS/CodexBar"
        sparkle = bundle / "Contents/Frameworks/Sparkle.framework/Sparkle"
        for binary in (main, sparkle):
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(b"\xca\xfe\xba\xbe" + b"synthetic universal fixture")
            binary.chmod(0o755)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        architectures = {str(main): b"x86_64 arm64\n", str(sparkle): b"arm64 x86_64\n"}

        def native(arguments):
            args = [str(value) for value in arguments]
            stdout, stderr = b"", b""
            if args[0] == "/usr/bin/lipo":
                stdout = architectures[args[-1]]
            elif "--entitlements" in args:
                stdout = plistlib.dumps({})
            elif "--display" in args:
                stderr = f"Identifier={harness.BUNDLE_ID}\nSignature=adhoc\nTeamIdentifier=not set\n".encode()
            else:
                self.assertIn("--verify", args)
            return subprocess.CompletedProcess(args, 0, stdout, stderr)

        with patch.object(harness, "command", side_effect=native), \
                patch.object(harness.candidate, "list_xattrs", return_value=[]):
            self.assertEqual(harness.inspect_harness(bundle, manifest, harness.BUILD_A),
                             harness.candidate.tree_manifest(bundle))
            for binary in (main, sparkle):
                for invalid in (b"arm64\n", b"x86_64\n", b"arm64 arm64\n", b"arm64 x86_64 arm64e\n"):
                    with self.subTest(binary=binary.name, invalid=invalid):
                        architectures[str(binary)] = invalid
                        self.rejects("fixture-architecture", harness.inspect_harness, bundle, manifest, harness.BUILD_A)
                architectures[str(binary)] = b"arm64 x86_64\n"
            main.write_bytes(b"not a Mach-O executable")
            self.rejects("fixture-architecture", harness.inspect_harness, bundle, manifest, harness.BUILD_A)

    def test_native_result_records_host_architecture_and_keeps_all_six_scenarios(self):
        fixture, manifest = self.export()
        for architecture in ("arm64", "x86_64"):
            with self.subTest(architecture=architecture), patch.object(harness.sys, "platform", "darwin"), \
                    patch.object(harness.platform, "machine", return_value=architecture), \
                    patch.object(harness.shutil, "disk_usage", return_value=Mock(free=4 * 1024 ** 3)), \
                    patch.object(harness, "run_case", side_effect=lambda _root, _scratch, _manifest, _feeds, scenario:
                                 {"scenario": scenario, "result": "passed"}) as run_case, \
                    patch("sys.stdout", new=io.StringIO()):
                result = harness.run(fixture, self.root, REVISION)
            self.assertEqual(result["host_architecture"], architecture)
            self.assertEqual(result["fixture_id"], manifest["fixture_id"])
            self.assertEqual([row["scenario"] for row in result["scenarios"]], list(harness.SCENARIOS))
            self.assertEqual(run_case.call_count, 6)

    def export(self):
        fixture = self.root / "export"
        fixture.mkdir()
        app = self.root / "CodexBar.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"fixture": True}))
        manifest = {"schema": "jones-update-fixture/v1", "fixture_id": FIXTURE_ID,
                    "source_revision": REVISION, "public_key": KEY, "port": 39541, "files": {}, "trees": {}}
        for name in ("A", "B"):
            tree = harness.candidate.tree_manifest(app)
            archive = fixture / f"{name}.zip"
            with zipfile.ZipFile(archive, "w") as handle:
                for entry in sorted(tree):
                    handle.write(app.parent / entry, entry)
            manifest["trees"][name] = tree
        (fixture / "feeds.json").write_text(json.dumps({scenario: "fixture" for scenario in harness.SCENARIOS}))
        for path in fixture.iterdir():
            manifest["files"][path.name] = {"bytes": path.stat().st_size, "sha256": harness.candidate.digest(path)}
        (fixture / "fixture.json").write_text(json.dumps(manifest))
        return fixture, manifest

    def test_export_verification_accepts_only_exact_source_and_bytes(self):
        fixture, manifest = self.export()
        self.assertEqual(harness.verify_fixture(fixture, REVISION)[0], manifest)
        self.rejects("fixture-source", harness.verify_fixture, fixture, "b" * 40)
        with (fixture / "B.zip").open("ab") as handle:
            handle.write(b"changed")
        self.rejects("fixture-hash", harness.verify_fixture, fixture, REVISION)

    def test_export_refuses_extra_files_and_links(self):
        fixture, _ = self.export()
        extra = fixture / "signer.key"
        extra.write_text("must never export a private key")
        self.rejects("fixture-layout", harness.verify_fixture, fixture, REVISION)
        extra.unlink()
        (fixture / "feeds.json").unlink()
        (fixture / "feeds.json").symlink_to(self.root / "missing")
        self.rejects("fixture-layout", harness.verify_fixture, fixture, REVISION)

    def test_command_writes_only_owned_companion_and_refuses_symlinks(self):
        manifest = {"fixture_id": FIXTURE_ID}
        harness.write_command(self.root, manifest, harness.BUILD_A, "check")
        value = json.loads((self.root / "harness-command.json").read_text())
        self.assertEqual((value["fixtureID"], value["build"], value["action"]),
                         (FIXTURE_ID, harness.BUILD_A, "check"))
        uuid.UUID(value["requestID"])
        self.assertFalse((self.root / "harness-command.pending").exists())
        (self.root / "harness-command.json").unlink()
        (self.root / "harness-command.json").symlink_to(self.root / "foreign")
        self.rejects("fixture-command", harness.write_command, self.root, manifest, harness.BUILD_A, "quit")
        self.assertFalse((self.root / "foreign").exists())

    def test_server_is_loopback_and_tampered_payload_changes_one_byte(self):
        archive = self.root / "B.zip"
        archive.write_bytes(b"small-owned-fixture")
        for tamper in (False, True):
            server = harness.FixtureServer(0, b"<rss/>", archive, tamper)
            self.assertEqual(server.server_address[0], "127.0.0.1")
            worker = harness.threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                base = f"http://127.0.0.1:{server.server_address[1]}"
                with urllib.request.urlopen(base + "/appcast.xml", timeout=2) as response:
                    self.assertEqual(response.read(), b"<rss/>")
                with urllib.request.urlopen(base + "/update.zip", timeout=2) as response:
                    actual = response.read()
                self.assertEqual(actual[:-1], archive.read_bytes()[:-1])
                self.assertEqual(actual[-1], archive.read_bytes()[-1] ^ int(tamper))
                self.assertEqual(server.archive_requests, 1)
                with self.assertRaises(urllib.error.HTTPError):
                    urllib.request.urlopen(base + "/../outside", timeout=2)
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=3)
            self.assertFalse(worker.is_alive())

    def closed_feed_response(self, address):
        # Let the server close first, retaining its TIME_WAIT state after this client closes.
        with socket.create_connection(address, timeout=2) as client:
            client.sendall(b"GET /appcast.xml HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
            response = bytearray()
            while chunk := client.recv(4096):
                response.extend(chunk)
                self.assertLessEqual(len(response), 32768)
        return bytes(response).partition(b"\r\n\r\n")[2]

    def test_all_scenarios_rebind_the_same_port_after_server_closed_connections(self):
        manifest = {"port": 0}
        feeds = {scenario: f"<rss>{scenario}</rss>" for scenario in harness.SCENARIOS}
        for scenario in harness.SCENARIOS:
            with self.subTest(scenario=scenario), harness.serving(manifest, feeds, scenario, self.root) as server:
                manifest["port"] = server.server_address[1]
                self.assertEqual(self.closed_feed_response(server.server_address), feeds[scenario].encode())
            self.assertEqual(server.socket.fileno(), -1)
            self.assertFalse(any(thread.name == "jones-fixture-http" for thread in harness.threading.enumerate()))

    def test_active_listener_is_exclusive_and_binding_failure_identifies_errno(self):
        feeds = {"quit": "<rss>owned listener</rss>"}
        with harness.serving({"port": 0}, feeds, "quit", self.root) as server:
            with self.assertRaises(harness.candidate.CandidateError) as caught:
                with harness.serving({"port": server.server_address[1]}, feeds, "quit", self.root):
                    self.fail("A second listener acquired the active fixture port")
            self.assertEqual(caught.exception.code, "fixture-listener")
            self.assertIn(f"errno={errno.EADDRINUSE}", str(caught.exception))
            self.assertEqual(self.closed_feed_response(server.server_address), feeds["quit"].encode())

    def test_server_releases_listener_after_case_failure(self):
        feeds = {"quit": "<rss>owned listener</rss>"}
        port = None
        with self.assertRaisesRegex(RuntimeError, "synthetic case failure"):
            with harness.serving({"port": 0}, feeds, "quit", self.root) as server:
                port = server.server_address[1]
                self.closed_feed_response(server.server_address)
                raise RuntimeError("synthetic case failure")
        self.assertIsNotNone(port)
        with harness.serving({"port": port}, feeds, "quit", self.root) as server:
            self.assertEqual(self.closed_feed_response(server.server_address), feeds["quit"].encode())

    def test_wait_timeout_identifies_its_native_phase(self):
        with patch.object(harness.time, "monotonic", side_effect=[0, 1]), \
                self.assertRaises(harness.candidate.CandidateError) as caught:
            harness.wait_for(lambda: None, bool, timeout=1, phase="update-readiness")
        self.assertEqual(caught.exception.code, "fixture-timeout")
        self.assertIn("update-readiness", str(caught.exception))

    def test_progress_report_omits_unrecognized_and_unbounded_fields(self):
        value = {"build": harness.BUILD_A, "pid": 42, "canCheck": False, "registeredApplication": True,
                 "state": "preparing", "failure": "",
                 "requestID": FIXTURE_ID, "private": "must not be printed", "bundlePath": "/not/needed"}
        self.assertEqual(harness.progress_report(value),
                         {key: value[key] for key in
                          ("build", "pid", "canCheck", "registeredApplication", "state", "failure", "requestID")})
        self.assertEqual(harness.progress_report(None), None)
        for key in ("build", "pid", "canCheck", "registeredApplication", "state", "failure", "requestID"):
            with self.subTest(key=key):
                summary = harness.progress_report({**value, key: "unbounded" * 10000})
                self.assertNotIn(key, summary)
                self.assertLess(len(json.dumps(summary)), 512)

    def test_replacement_failure_keeps_last_report_and_phase_before_cleanup(self):
        home = self.home()
        manifest = {"fixture_id": FIXTURE_ID, "source_revision": REVISION, "trees": {"A": {}}}
        process = Mock(pid=42)
        process.poll.return_value = None
        server = Mock(archive_requests=1)
        first = {"build": harness.BUILD_A, "pid": 42, "canCheck": True, "state": "idle", "failure": ""}
        ready = {**first, "state": "ready", "canCheck": False}
        installing = {**ready, "state": "installing"}

        def extract(arguments, **_):
            directory = Path(arguments[-1])
            contents = directory / "CodexBar.app/Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleVersion": harness.BUILD_A}))

        def wait(read, accept, timeout=90, *, phase="postcondition"):
            value = read()
            if phase == "replacement":
                raise harness.candidate.CandidateError("fixture-timeout", "Timeout during replacement")
            self.assertTrue(accept(value))
            return value

        output, errors = io.StringIO(), io.StringIO()
        with patch.object(harness.Path, "home", return_value=home), \
                patch.object(harness.subprocess, "run", side_effect=self.defaults), \
                patch.object(harness, "command", side_effect=extract), \
                patch.object(harness, "inspect_harness", return_value={}), \
                patch.object(harness, "serving", return_value=nullcontext(server)), \
                patch.object(harness, "launch", return_value=process), \
                patch.object(harness, "report", side_effect=[first, ready, installing]), \
                patch.object(harness, "wait_for", side_effect=wait), \
                patch.object(harness, "drain") as drain, \
                redirect_stdout(output), redirect_stderr(errors), \
                self.assertRaises(harness.candidate.CandidateError) as caught:
            harness.run_case(self.root, self.root, manifest, {"quit": "fixture"}, "quit")
        self.assertEqual(caught.exception.code, "fixture-timeout")
        records = [json.loads(line) for line in errors.getvalue().splitlines()]
        failure = next(record["fixture_failure"] for record in records if "fixture_failure" in record)
        self.assertEqual(failure, {"scenario": "quit", "phase": "replacement", "last_report": installing,
                                   "last_build": harness.BUILD_A, "archive_requests": 1,
                                   "processes_before_drain": [{"pid": 42, "returncode": None}],
                                   "builds_before_drain": {"CodexBar.app": harness.BUILD_A,
                                                           "Jones Update Harness.app": "missing"}})
        self.assertIn('"phase": "update-readiness"', output.getvalue())
        drain.assert_called_once()
        process.wait.assert_called_once_with(timeout=5)
        self.assertEqual(list(self.root.glob("jones-update-native-*")), [])
        self.assertEqual(list((home / "Library/Caches").iterdir()), [])

    def test_failure_builds_identifies_renamed_fixture_without_following_links(self):
        contents = self.root / "Jones Update Harness.app/Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleVersion": harness.BUILD_B}))
        self.assertEqual(harness.failure_builds(self.root), {"CodexBar.app": "missing",
                                                           "Jones Update Harness.app": harness.BUILD_B})
        (self.root / "CodexBar.app").symlink_to(self.root / "Jones Update Harness.app")
        self.assertEqual(harness.failure_builds(self.root)["CodexBar.app"], "symlink")
        (contents / "Info.plist").write_text("invalid fixture plist")
        self.assertEqual(harness.failure_builds(self.root)["Jones Update Harness.app"], "unreadable")

    def home(self):
        home = self.root / "home"
        (home / "Library/Caches").mkdir(parents=True)
        return home

    @staticmethod
    def defaults(arguments, **_):
        action = arguments[1]
        return subprocess.CompletedProcess(arguments, 1 if action == "read" else 0,
                                           stdout=b"", stderr=b"Domain does not exist" if action == "read" else b"")

    def test_native_state_cleanup_success_and_original_failure(self):
        for should_fail in (False, True):
            home = self.home()
            with patch.object(harness.subprocess, "run", side_effect=self.defaults):
                try:
                    with harness.native_state(home) as lease:
                        lease.cache.mkdir()
                        (lease.cache / "owned").write_text("fixture")
                        lease.cleanup_allowed = True
                        if should_fail:
                            raise RuntimeError("original fixture failure")
                except RuntimeError as error:
                    self.assertTrue(should_fail)
                    self.assertEqual(str(error), "original fixture failure")
            self.assertEqual(list((home / "Library/Caches").iterdir()), [])
            harness.shutil.rmtree(home)

    def test_preexisting_native_state_and_lock_are_preserved(self):
        home = self.home()
        cache = harness.state_paths(home)[0]
        cache.mkdir()
        (cache / "foreign").write_text("preserve")
        with self.assertRaises(harness.candidate.CandidateError) as caught:
            with harness.native_state(home):
                self.fail("must not admit existing state")
        self.assertEqual(caught.exception.code, "fixture-state-exists")
        self.assertEqual((cache / "foreign").read_text(), "preserve")
        lock = home / "Library/Caches" / ("." + harness.BUNDLE_ID + ".lock")
        lock.write_text("existing lock")
        with self.assertRaises(FileExistsError):
            with harness.native_state(home):
                self.fail("must not enter an existing lease")
        self.assertEqual(lock.read_text(), "existing lock")

    def test_unproved_process_drain_preserves_cache_and_lock(self):
        home = self.home()
        with patch.object(harness.subprocess, "run", side_effect=self.defaults), redirect_stderr(io.StringIO()):
            with harness.native_state(home) as lease:
                lease.cache.mkdir()
                (lease.cache / "installer").write_text("still owned by native helper")
        self.assertTrue((lease.cache / "installer").exists())
        self.assertTrue((home / "Library/Caches" / ("." + harness.BUNDLE_ID + ".lock")).exists())

    def test_cleanup_failure_preserves_original_error_and_lock(self):
        home = self.home()
        with patch.object(harness.subprocess, "run", side_effect=self.defaults), redirect_stderr(io.StringIO()), \
                patch.object(harness.shutil, "rmtree", side_effect=OSError("cleanup")):
            with self.assertRaisesRegex(RuntimeError, "original"):
                with harness.native_state(home) as lease:
                    lease.cache.mkdir()
                    lease.cleanup_allowed = True
                    raise RuntimeError("original")
        self.assertTrue(lease.cache.exists())
        self.assertTrue((home / "Library/Caches" / ("." + harness.BUNDLE_ID + ".lock")).exists())

    def test_handled_signal_unwinds_owned_state(self):
        home = self.home()
        with patch.object(harness.subprocess, "run", side_effect=self.defaults):
            with self.assertRaises(harness.candidate.CandidateError) as caught:
                with harness.candidate.cancellation_cleanup(), harness.native_state(home) as lease:
                    lease.cache.mkdir()
                    lease.cleanup_allowed = True
                    os.kill(os.getpid(), signal.SIGTERM)
            self.assertEqual(caught.exception.code, "cancelled")
        self.assertEqual(list((home / "Library/Caches").iterdir()), [])

    def test_two_fixture_homes_do_not_clean_each_other(self):
        first = self.home()
        second = self.root / "second-home"
        (second / "Library/Caches").mkdir(parents=True)
        with patch.object(harness.subprocess, "run", side_effect=self.defaults):
            with harness.native_state(first) as first_lease:
                first_lease.cache.mkdir()
                first_lease.cleanup_allowed = True
                with harness.native_state(second) as second_lease:
                    second_lease.cache.mkdir()
                    second_lease.cleanup_allowed = True
                self.assertTrue(first_lease.cache.exists())
                self.assertFalse(second_lease.cache.exists())
        self.assertFalse(first_lease.cache.exists())


if __name__ == "__main__":
    with harness.candidate.cancellation_cleanup():
        unittest.main()
