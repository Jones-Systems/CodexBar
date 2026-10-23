#!/usr/bin/env python3
"""Prepare CI-only signed fixtures or run their isolated native Sparkle round trip.

`prepare` uses an already compiled memory-only CryptoKit signer on hosted CI.
`run` uses only exported public fixtures: no compiler, signing key, account or
production app initialization. Host admission and scheduling remain the caller's.
"""

import argparse
import base64
from contextlib import contextmanager
from dataclasses import dataclass
import http.server
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from xml.sax.saxutils import quoteattr

import jones_candidate_artifact as candidate


BUNDLE_ID = "com.jonessystems.codexbar.update-harness"
BUILD_A = "900000001"
BUILD_B = "900000002"
SCENARIOS = ("unsigned-feed", "wrong-feed-key", "oversized", "tampered-archive", "quit", "immediate")
ROOT = Path(__file__).resolve().parent.parent
FORBIDDEN = ("JonesStateKey", "JonesAppGroupID", "JonesICloudID", "JonesAppBundleID", "CodexBarTeamID")
require = candidate.require
command = candidate.command


def public_key(value):
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as error:
        raise candidate.CandidateError("fixture-key", "Invalid fixture public key") from error
    require(len(raw) == 32 and base64.b64encode(raw).decode("ascii") == value
            and value != candidate.UPSTREAM_KEY, "fixture-key", "Invalid fixture public key")
    return value


def feed(port, archive_signature, length):
    require(type(port) is int and 1024 <= port <= 65535, "fixture-port", "Use an unprivileged loopback port")
    require(type(length) is int and length > 0, "fixture-length", "Expected a positive archive length")
    signature = base64.b64decode(archive_signature, validate=True)
    require(len(signature) == 64, "fixture-signature", "Expected an Ed25519 signature")
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
        '<channel><title>Isolated Jones updater fixture</title><item><title>Fixture B</title>'
        f'<sparkle:version>{BUILD_B}</sparkle:version>'
        '<sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>'
        '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>'
        f'<enclosure url="http://127.0.0.1:{port}/update.zip" length="{length}" '
        f'type="application/octet-stream" sparkle:edSignature={quoteattr(archive_signature)}/>'
        '</item></channel></rss>\n'
    ).encode("utf-8")


def signed_feed(content, signature):
    require(len(base64.b64decode(signature, validate=True)) == 64,
            "fixture-signature", "Expected an Ed25519 signature")
    # Sparkle 2.9.3 common_cli/Signing.swift: the signature covers exactly the preceding bytes.
    return content + f"<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(content)}\n-->\n".encode("ascii")


def fixture_info(original, fixture_id, key, port, build):
    require(original.get("CFBundleIdentifier") == candidate.BUNDLE_ID,
            "fixture-source", "Only a Jones candidate may supply fixture bytes")
    require(candidate.SHA.fullmatch(original.get("JonesSourceRevision", "")) is not None,
            "fixture-source", "A full source revision is required")
    uuid.UUID(fixture_id)
    public_key(key)
    require(type(port) is int and 1024 <= port <= 65535, "fixture-port", "Invalid port")
    require(build in (BUILD_A, BUILD_B), "fixture-build", "Unknown fixture build")
    info = {name: value for name, value in original.items() if name not in FORBIDDEN}
    info.update(CFBundleIdentifier=BUNDLE_ID, CFBundleName="Jones Update Harness",
                CFBundleDisplayName="Jones Update Harness", CFBundleVersion=build,
                CFBundleShortVersionString="1.0.0" if build == BUILD_A else "1.0.1",
                JonesUpdateHarness=True, JonesUpdateHarnessFixtureID=fixture_id,
                JonesUpdateChannel="stable", SUFeedURL=f"http://127.0.0.1:{port}/appcast.xml",
                SUPublicEDKey=key, SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True,
                SUAllowsAutomaticUpdates=True, SURequireSignedFeed=True,
                SUVerifyUpdateBeforeExtraction=True, SUSignedFeedFailureExpirationInterval=0,
                NSAppTransportSecurity={"NSAllowsLocalNetworking": True})
    return info


class Signer:
    def __init__(self, executable, root):
        self.process = subprocess.Popen([str(executable), str(root)], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.key = None

    def reply(self):
        with selectors.DefaultSelector() as selector:
            selector.register(self.process.stdout, selectors.EVENT_READ)
            require(bool(selector.select(30)), "fixture-signer", "Fixture signer timed out")
        line = self.process.stdout.readline(4097)
        require(0 < len(line) <= 4096, "fixture-signer", "Invalid fixture signer reply")
        return json.loads(line)

    def sign(self, path, wrong_key=False):
        request = json.dumps({"path": str(path), "wrongKey": wrong_key}).encode("utf-8") + b"\n"
        self.process.stdin.write(request)
        self.process.stdin.flush()
        return self.reply()["signature"]

    def __enter__(self):
        try:
            self.key = public_key(self.reply()["publicKey"])
        except BaseException:
            self.close()
            raise
        return self

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.process.stdout.close()

    def __exit__(self, *_):
        self.close()


def inspect_harness(bundle, manifest, build):
    tree = candidate.tree_manifest(bundle, check_quarantine=True)
    info = candidate.read_plist(bundle / "Contents/Info.plist")
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "CodexBar",
                "CFBundleVersion": build, "JonesSourceRevision": manifest["source_revision"],
                "JonesUpdateHarness": True, "JonesUpdateHarnessFixtureID": manifest["fixture_id"],
                "JonesUpdateChannel": "stable", "SUPublicEDKey": manifest["public_key"],
                "SUFeedURL": f"http://127.0.0.1:{manifest['port']}/appcast.xml",
                "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
                "SUSignedFeedFailureExpirationInterval": 0}
    candidate.exact_values(info, expected, "fixture-identity")
    require(not any(key in info for key in FORBIDDEN), "fixture-identity", "Production identity leaked into fixture")
    require(not (bundle / "Contents/PlugIns").exists() and not (bundle / "Contents/Helpers").exists(),
            "fixture-identity", "Fixture must not contain product helpers or widgets")
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", bundle])
    displayed = command(["/usr/bin/codesign", "--display", "--verbose=4", bundle])
    candidate.validate_signature((displayed.stdout + displayed.stderr).decode("utf-8"), BUNDLE_ID)
    entitlements = command(["/usr/bin/codesign", "--display", "--entitlements", ":-", bundle]).stdout
    require(plistlib.loads(entitlements) == {}, "fixture-entitlements", "Fixture must have no signed entitlements")
    macho = set()
    for name, entry in tree.items():
        if entry["kind"] != "file":
            continue
        path = bundle.parent / name
        with path.open("rb") as handle:
            if handle.read(4) not in candidate.MACHO_MAGICS:
                continue
        raw = command(["/usr/bin/codesign", "--display", "--entitlements", ":-", path]).stdout
        nested = plistlib.loads(raw) if raw.strip() else {}
        require(not any("icloud" in key.lower() or "ubiquity" in key.lower() for key in nested)
                and not nested.get("com.apple.security.application-groups"),
                "fixture-entitlements", "No fixture executable may carry app groups or iCloud entitlements")
        architectures = command(["/usr/bin/lipo", "-archs", path]).stdout.decode("ascii").split()
        candidate.validate_architectures(architectures, "fixture-architecture")
        macho.add(name)
    executable = tree.get("CodexBar.app/Contents/MacOS/CodexBar", {})
    require("CodexBar.app/Contents/MacOS/CodexBar" in macho and executable.get("mode", 0) & 0o111,
            "fixture-architecture", "Fixture executable must be present and executable")
    return tree


def prepare(app, output, signer, port, environment):
    require(sys.platform == "darwin" and environment.get("GITHUB_ACTIONS") == "true"
            and environment.get("RUNNER_ENVIRONMENT") == "github-hosted",
            "fixture-ci", "Fixture signing is limited to GitHub-hosted macOS CI")
    require(not output.exists() and not output.is_symlink(), "output-exists", "Fixture output must be new")
    source = candidate.tree_manifest(app, check_quarantine=True)
    source_size = sum(entry["size"] for entry in source.values())
    require(0 < source_size <= candidate.MAX_UNPACKED_BYTES, "fixture-size", "Source bundle is too large")
    require(shutil.disk_usage(output.parent).free >= 3 * source_size + 2 * candidate.MAX_ARCHIVE_BYTES + candidate.GIB,
            "fixture-storage", "Insufficient space to create the fixture")
    original = candidate.read_plist(app / "Contents/Info.plist")
    with candidate.owned_scratch(output.parent) as scratch:
        delivery = scratch / "delivery"
        delivery.mkdir()
        fixture_id = str(uuid.uuid4())
        with Signer(signer, scratch) as signing:
            manifest = {"schema": "jones-update-fixture/v1", "fixture_id": fixture_id,
                        "source_revision": original["JonesSourceRevision"], "public_key": signing.key,
                        "port": port, "trees": {}, "files": {}}
            for build, name in ((BUILD_A, "A"), (BUILD_B, "B")):
                parent = scratch / name
                parent.mkdir()
                bundle = parent / "CodexBar.app"
                shutil.copytree(app, bundle, symlinks=True)
                for child in ("Helpers", "PlugIns"):
                    path = bundle / "Contents" / child
                    require(not path.is_symlink(), "fixture-path", "Unexpected helper symlink")
                    if path.exists():
                        shutil.rmtree(path)
                (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(
                    fixture_info(original, fixture_id, signing.key, port, build)))
                entitlements = parent / "empty-entitlements.plist"
                entitlements.write_bytes(plistlib.dumps({}))
                command(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", entitlements, bundle])
                tree = inspect_harness(bundle, manifest, build)
                archive = delivery / f"{name}.zip"
                command(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", "--noqtn",
                         bundle, archive], timeout=300)
                candidate.validate_zip(archive, tree)
                manifest["trees"][name] = tree
            archive = delivery / "B.zip"
            archive_signature = signing.sign(archive)
            feeds = {}
            for scenario in SCENARIOS:
                length = candidate.MAX_ARCHIVE_BYTES + 1 if scenario == "oversized" else archive.stat().st_size
                content = feed(port, archive_signature, length)
                if scenario != "unsigned-feed":
                    input_path = scratch / "appcast-input.xml"
                    input_path.write_bytes(content)
                    content = signed_feed(content, signing.sign(input_path, scenario == "wrong-feed-key"))
                feeds[scenario] = content.decode("utf-8")
            (delivery / "feeds.json").write_text(json.dumps(feeds, sort_keys=True) + "\n", encoding="utf-8")
        # The signer has exited; neither private seed nor executable is an exported artifact.
        for path in sorted(delivery.iterdir()):
            manifest["files"][path.name] = {"sha256": candidate.digest(path), "bytes": path.stat().st_size}
        unpacked = max(sum(entry["size"] for entry in tree.values()) for tree in manifest["trees"].values())
        manifest["disk"] = {"unpacked_bundle_bytes": unpacked,
                            "estimated_additional_run_peak_bytes": 4 * unpacked + archive.stat().st_size,
                            "required_reserve_bytes": candidate.GIB,
                            "basis": "one app, Sparkle download/extraction/replacement, serial cases; no hard cache quota"}
        (delivery / "fixture.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        require(not output.exists() and not output.is_symlink(), "output-exists", "Fixture output appeared")
        delivery.rename(output)
    return manifest


def verify_fixture(root, expected_revision):
    require(root.is_dir() and root.resolve() == root.absolute(), "fixture-path", "Use a canonical fixture directory")
    require(sorted(path.name for path in root.iterdir()) == ["A.zip", "B.zip", "feeds.json", "fixture.json"],
            "fixture-layout", "Only the four exported public fixture files are accepted")
    require(all(path.is_file() and not path.is_symlink() for path in root.iterdir()),
            "fixture-layout", "Fixture files must be regular, non-symlink files")
    manifest = candidate.load_json(root / "fixture.json")
    require(manifest.get("schema") == "jones-update-fixture/v1" and
            manifest.get("source_revision") == expected_revision and candidate.SHA.fullmatch(expected_revision),
            "fixture-source", "Fixture source revision does not match")
    uuid.UUID(manifest["fixture_id"])
    public_key(manifest["public_key"])
    require(type(manifest.get("port")) is int and 1024 <= manifest["port"] <= 65535,
            "fixture-port", "Invalid loopback port")
    require(set(manifest["files"]) == {"A.zip", "B.zip", "feeds.json"}
            and set(manifest["trees"]) == {"A", "B"}, "fixture-layout", "Incomplete fixture manifest")
    for name, expected in manifest["files"].items():
        path = root / name
        require(path.stat().st_size == expected["bytes"] and candidate.digest(path) == expected["sha256"],
                "fixture-hash", "Fixture bytes changed")
    for name in ("A", "B"):
        candidate.validate_zip(root / f"{name}.zip", manifest["trees"][name])
    feeds = candidate.load_json(root / "feeds.json")
    require(set(feeds) == set(SCENARIOS) and all(type(value) is str and len(value) < 16384 for value in feeds.values()),
            "fixture-feed", "Unexpected feed variants")
    return manifest, feeds


class FixtureServer(http.server.HTTPServer):
    allow_reuse_address = False

    def __init__(self, port, content, archive, tamper):
        self.content, self.archive, self.tamper = content, archive, tamper
        self.archive_requests = 0
        super().__init__(("127.0.0.1", port), FixtureHandler)


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def do_GET(self):
        if self.path == "/appcast.xml":
            content = self.server.content
            self.send_response(200)
            self.send_header("Content-Type", "application/rss+xml")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        elif self.path == "/update.zip":
            self.server.archive_requests += 1
            size = self.server.archive.stat().st_size
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.end_headers()
            with self.server.archive.open("rb") as handle:
                while chunk := handle.read(1024 * 1024):
                    if self.server.tamper and handle.tell() == size:
                        chunk = chunk[:-1] + bytes([chunk[-1] ^ 1])
                    self.wfile.write(chunk)
        else:
            self.send_error(404)

    def log_message(self, *_):
        pass


@contextmanager
def serving(manifest, feeds, scenario, root):
    server = FixtureServer(manifest["port"], feeds[scenario].encode("utf-8"), root / "B.zip",
                           scenario == "tampered-archive")
    server.timeout = 5
    thread = threading.Thread(target=server.serve_forever, name="jones-fixture-http", daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=10)
        require(not thread.is_alive(), "fixture-server", "Fixture HTTP thread did not stop")


def write_command(directory, manifest, build, action):
    path = directory / "harness-command.json"
    pending = directory / "harness-command.pending"
    require(not path.is_symlink() and not pending.exists() and not pending.is_symlink(),
            "fixture-command", "Unexpected command file")
    with pending.open("x", encoding="utf-8") as handle:
        json.dump({"fixtureID": manifest["fixture_id"], "requestID": str(uuid.uuid4()),
                   "build": build, "action": action}, handle)
    pending.replace(path)


def wait_for(read, accept, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = read()
        if accept(value):
            return value
        time.sleep(0.2)
    raise candidate.CandidateError("fixture-timeout", "Native fixture did not reach its expected postcondition")


def report(directory, manifest):
    path = directory / "harness-report.json"
    if not path.exists():
        return None
    require(not path.is_symlink(), "fixture-report", "Unexpected report symlink")
    value = candidate.load_json(path)
    require(value.get("schema") == "jones-update-harness-report/v1" and
            value.get("fixtureID") == manifest["fixture_id"] and
            value.get("sourceRevision") == manifest["source_revision"] and
            value.get("bundlePath") == str(directory / "CodexBar.app") and
            type(value.get("pid")) is int and value["pid"] > 1,
            "fixture-report", "Report does not identify this fixture executable")
    return value


def owned_pids(roots):
    pattern = "|".join("^" + re.escape(str(root)) + "/" for root in roots)
    result = subprocess.run(["/usr/bin/pgrep", "-f", pattern], capture_output=True, timeout=10, check=False)
    require(result.returncode in (0, 1), "fixture-process", "Cannot inspect fixture processes")
    pids = [int(value) for value in result.stdout.split()]
    # Recheck the executable, not merely an argument that happened to name the fixture.
    owned = []
    for pid in pids:
        result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, timeout=10)
        executable = result.stdout.decode("utf-8").strip()
        if any(executable.startswith(str(root) + "/") for root in roots):
            owned.append(pid)
    return owned


def drain(roots):
    pids = owned_pids(roots)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    wait_for(lambda: owned_pids(roots), lambda value: not value, timeout=15)


def state_paths(home):
    return [home / "Library" / parent / (BUNDLE_ID + suffix) for parent, suffix in (
        ("Caches", ""), ("Preferences", ".plist"), ("Saved Application State", ".savedState"),
        ("HTTPStorages", ""), ("HTTPStorages", ".binarycookies"), ("WebKit", ""), ("Logs", ""))]


@dataclass
class NativeState:
    cache: Path
    cleanup_allowed: bool = False


@contextmanager
def native_state(home):
    # A fixed bundle ID needs one native fixture run per user, including other workspaces.
    lock = home / "Library/Caches" / ("." + BUNDLE_ID + ".lock")
    require(lock.parent.resolve() == lock.parent.absolute(), "fixture-state-path", "Cache parent must be canonical")
    descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    paths = state_paths(home)
    admitted = False
    lease = NativeState(paths[0])
    primary = None
    remove_lock = True
    try:
        require(all(path.parent.resolve() == path.parent.absolute() for path in paths),
                "fixture-state-path", "Fixture state parents must not traverse symlinks")
        require(not any(os.path.lexists(path) for path in paths),
                "fixture-state-exists", "Existing harness state must be preserved; use a fresh qualified user")
        result = subprocess.run(["/usr/bin/defaults", "read", BUNDLE_ID], stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, timeout=10, env={**os.environ, "LC_ALL": "C"})
        require(result.returncode == 1 and b"does not exist" in result.stderr,
                "fixture-defaults-exist", "The harness defaults domain must be absent")
        admitted = True
        yield lease
    except BaseException as error:
        primary = error
        raise
    finally:
        try:
            if admitted and not lease.cleanup_allowed:
                remove_lock = False
                print(f"Native process drain unproved; fixture state and owned lock retained: {lock}", file=sys.stderr)
            elif admitted:
                result = subprocess.run(["/usr/bin/defaults", "delete", BUNDLE_ID], stdout=subprocess.DEVNULL,
                                        stderr=subprocess.PIPE, timeout=10, env={**os.environ, "LC_ALL": "C"})
                require(result.returncode == 0 or result.returncode == 1 and
                        (b"not found" in result.stderr or b"does not exist" in result.stderr),
                        "fixture-defaults-cleanup", "Could not remove the owned fixture defaults domain")
                for path in paths:
                    require(not path.is_symlink(), "fixture-cleanup", "Unexpected state symlink; cleanup held")
                    if path.is_dir():
                        shutil.rmtree(path)
                    elif path.exists():
                        path.unlink()
                require(not any(os.path.lexists(path) for path in paths), "fixture-cleanup", "Fixture state remains")
        except BaseException as error:
            remove_lock = False
            print(f"Fixture state cleanup failed ({type(error).__name__}); owned lock retained: {lock}", file=sys.stderr)
            if primary is None:
                raise
        finally:
            os.close(descriptor)
            if remove_lock:
                lock.unlink()


def launch(bundle, log):
    environment = dict(os.environ)
    environment.pop("CODEXBAR_RESOURCE_SMOKE", None)
    temporary = bundle.parent / "native-tmp"
    temporary.mkdir(exist_ok=True)
    require(temporary.is_dir() and not temporary.is_symlink(), "fixture-temp", "Invalid native temporary directory")
    environment["TMPDIR"] = str(temporary)
    return subprocess.Popen([str(bundle / "Contents/MacOS/CodexBar")], stdout=log, stderr=log,
                            env=environment, start_new_session=True)


def current_build(bundle):
    try:
        raw = (bundle / "Contents/Info.plist").read_bytes()
    except FileNotFoundError:
        # Sparkle's non-atomic fallback can briefly leave the destination absent.
        return None
    return plistlib.loads(raw).get("CFBundleVersion")


def run_case(root, scratch_parent, manifest, feeds, scenario):
    directory = Path(tempfile.mkdtemp(prefix="jones-update-native-", dir=scratch_parent)).resolve()
    processes = []
    clean = False
    try:
        with native_state(Path.home()) as lease:
            cache = lease.cache
            try:
                command(["/usr/bin/ditto", "-x", "-k", "--noqtn", root / "A.zip", directory], timeout=300)
                bundle = directory / "CodexBar.app"
                require(inspect_harness(bundle, manifest, BUILD_A) == manifest["trees"]["A"],
                        "fixture-roundtrip", "Extracted A differs from the signed fixture")
                write_command(directory, manifest, BUILD_A, "wait")
                with (directory / "native.log").open("wb") as log, serving(manifest, feeds, scenario, root) as server:
                    processes.append(launch(bundle, log))
                    first = wait_for(lambda: report(directory, manifest),
                                     lambda value: value and value["build"] == BUILD_A and value["canCheck"])
                    require(first["pid"] == processes[0].pid, "fixture-process", "Unexpected initial process")
                    write_command(directory, manifest, BUILD_A, "check")
                    outcome = wait_for(lambda: report(directory, manifest),
                                       lambda value: value and value["state"] in ("ready", "failed"))
                    if scenario in ("quit", "immediate"):
                        require(outcome["state"] == "ready" and server.archive_requests > 0,
                                "fixture-readiness", "The real installer never prepared an authenticated archive")
                        write_command(directory, manifest, BUILD_A, "install" if scenario == "immediate" else "quit")
                        wait_for(lambda: current_build(bundle),
                                 lambda value: value == BUILD_B)
                        if scenario == "quit":
                            processes[0].wait(timeout=20)
                            # Normal quit installs without silently reopening the app.
                            time.sleep(2)
                            require(report(directory, manifest)["build"] == BUILD_A,
                                    "fixture-quit", "Normal quit unexpectedly relaunched the fixture")
                            processes.append(launch(bundle, log))
                        installed = wait_for(lambda: report(directory, manifest),
                                             lambda value: value and value["build"] == BUILD_B)
                        require(installed["pid"] != first["pid"] and installed["pid"] in owned_pids([directory]),
                                "fixture-relaunch", "Replacement must run at the same path in a new process")
                        require(inspect_harness(bundle, manifest, BUILD_B) == manifest["trees"]["B"],
                                "fixture-installed", "Installed B does not match the signed fixture")
                        write_command(directory, manifest, BUILD_B, "stop")
                    else:
                        require(outcome["state"] == "failed", "fixture-rejection", "Invalid update reached readiness")
                        require((server.archive_requests > 0) == (scenario == "tampered-archive"),
                                "fixture-download", "Invalid metadata must be rejected before downloading")
                        if scenario == "oversized":
                            require(outcome["failure"] == "archive-too-large",
                                    "fixture-admission", "Size rejection did not come from production admission")
                        require(inspect_harness(bundle, manifest, BUILD_A) == manifest["trees"]["A"],
                                "fixture-rejection", "Rejected update changed the installed app")
                        write_command(directory, manifest, BUILD_A, "stop")
                        installed = None
                    wait_for(lambda: owned_pids([directory, cache]), lambda value: not value, timeout=20)
                    return {"scenario": scenario, "result": "passed", "initial": first, "outcome": outcome,
                            "installed": installed, "archive_requests": server.archive_requests}
            finally:
                primary = sys.exc_info()[1]
                try:
                    drain([directory, cache])
                    for process in processes:
                        process.wait(timeout=5)
                    clean = True
                    lease.cleanup_allowed = True
                except BaseException as error:
                    print(f"Fixture process cleanup failed: {type(error).__name__}", file=sys.stderr)
                    if primary is None:
                        raise
    except BaseException:
        log_path = directory / "native.log"
        if log_path.is_file() and not log_path.is_symlink():
            with log_path.open("rb") as handle:
                handle.seek(max(0, log_path.stat().st_size - 16384))
                print(json.dumps({"fixture_log_tail": handle.read().decode("utf-8", errors="replace")}), file=sys.stderr)
        raise
    finally:
        # Never unlink live executables if native cleanup could not prove its postcondition.
        if clean or not processes:
            shutil.rmtree(directory)
            require(not directory.exists(), "fixture-cleanup", "Native scratch remains")
        else:
            print(f"Fixture cleanup held; retained owned scratch: {directory}", file=sys.stderr)


def run(root, scratch_parent, expected_revision):
    require(sys.platform == "darwin", "fixture-platform", "Native fixture requires macOS")
    require(scratch_parent.is_dir() and scratch_parent.resolve() == scratch_parent.absolute(),
            "fixture-scratch", "Use an existing canonical scratch parent")
    manifest, feeds = verify_fixture(root, expected_revision)
    unpacked = max(sum(entry["size"] for entry in tree.values()) for tree in manifest["trees"].values())
    needed = 4 * unpacked + (root / "B.zip").stat().st_size + candidate.GIB
    require(shutil.disk_usage(scratch_parent).free >= needed and shutil.disk_usage(Path.home()).free >= needed,
            "fixture-storage", "Insufficient native app/cache capacity")
    results = []
    for scenario in SCENARIOS:
        result = run_case(root, scratch_parent, manifest, feeds, scenario)
        results.append(result)
        print(json.dumps(result, sort_keys=True), flush=True)
    return {"schema": "jones-update-native-result/v1", "source_revision": expected_revision,
            "fixture_id": manifest["fixture_id"], "host_architecture": platform.machine(),
            "scenarios": results, "result": "passed"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--app", type=Path, required=True)
    prepare_parser.add_argument("--output", type=Path, required=True)
    prepare_parser.add_argument("--signer", type=Path, required=True)
    prepare_parser.add_argument("--port", type=int, default=39541)
    run_parser = commands.add_parser("run")
    run_parser.add_argument("--fixture", type=Path, required=True)
    run_parser.add_argument("--scratch-parent", type=Path, required=True)
    run_parser.add_argument("--expect-revision", required=True)
    run_parser.add_argument("--result", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        with candidate.cancellation_cleanup():
            if args.action == "prepare":
                result = prepare(args.app.absolute(), args.output.absolute(), args.signer.absolute(), args.port, os.environ)
            else:
                require(not args.result.exists() and not args.result.is_symlink(),
                        "output-exists", "Result path must be new")
                result = run(args.fixture.absolute(), args.scratch_parent.absolute(), args.expect_revision)
                with args.result.open("x", encoding="utf-8") as handle:
                    json.dump(result, handle, indent=2, sort_keys=True)
            print(json.dumps({"result": "prepared" if args.action == "prepare" else "passed",
                              "source_revision": result.get("source_revision")}, sort_keys=True))
        return 0
    except candidate.CandidateError as error:
        print(json.dumps({"result": "failed", "code": error.code, "reason": str(error)}), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"result": "failed", "code": "fixture-unavailable", "reason": type(error).__name__}),
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
