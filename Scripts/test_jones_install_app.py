#!/usr/bin/env python3
"""Portable installer contracts: owned tiny fixtures, fake native operations, no macOS/app/account access.

Run directly with Python 3.9+; --scratch-parent may select a caller-owned disk
directory. The default is the repository directory, never the system temp root.
"""

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile


sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("jones_installer", Path(__file__).with_name("jones_install_app.py"))
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)
SCRATCH_PARENT = Path(__file__).resolve().parent.parent
REVISION = "a" * 40


def make_bundle(path, build="135.2", legacy=False):
    (path / "Contents/MacOS").mkdir(parents=True)
    info = dict(installer.IDENTITY)
    info.update(CFBundleExecutable="CodexBar", CFBundleVersion=build, CFBundleShortVersionString="0.56.4")
    if not legacy:
        info.update(JonesSourceRevision=REVISION, JonesBuildOrigin="ci-main", JonesUpdateChannel="none",
                    JonesBuildRun="https://github.com/Jones-Systems/CodexBar/actions/runs/12345")
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    executable = path / "Contents/MacOS/CodexBar"
    executable.write_text("arm64", encoding="ascii")
    executable.chmod(0o755)
    seal = {"identifier": installer.BUNDLE_ID, "signature": "adhoc", "team": "not set", "valid": True,
            "entitlements": {"com.apple.security.application-groups": [installer.GROUP_ID]}}
    (path / "Contents/fixture-signature.json").write_text(json.dumps(seal), encoding="utf-8")
    widget = path / "Contents/PlugIns/CodexBarWidget.appex"
    (widget / "Contents/MacOS").mkdir(parents=True)
    widget_info = dict(info)
    widget_info.update(CFBundleExecutable="CodexBarWidget", CFBundleIdentifier=installer.BUNDLE_ID + ".widget")
    (widget / "Contents/Info.plist").write_bytes(plistlib.dumps(widget_info))
    widget_executable = widget / "Contents/MacOS/CodexBarWidget"
    widget_executable.write_text("arm64", encoding="ascii")
    widget_executable.chmod(0o755)
    seal["identifier"] += ".widget"
    seal["entitlements"] = {"com.apple.security.application-groups": [installer.GROUP_ID],
                            "com.apple.security.app-sandbox": True}
    (widget / "Contents/fixture-signature.json").write_text(json.dumps(seal), encoding="utf-8")
    return path


def change_plist(bundle, **changes):
    path = bundle / "Contents/Info.plist"
    value = plistlib.loads(path.read_bytes())
    for key, replacement in changes.items():
        if replacement is None:
            value.pop(key, None)
        else:
            value[key] = replacement
    path.write_bytes(plistlib.dumps(value))


def change_signature(bundle, **changes):
    path = bundle / "Contents/fixture-signature.json"
    value = json.loads(path.read_text(encoding="utf-8"))
    value.update(changes)
    path.write_text(json.dumps(value), encoding="utf-8")


def zip_bundle(bundle, archive):
    paths = [bundle] + sorted(bundle.rglob("*"))
    with zipfile.ZipFile(str(archive), "w", compression=zipfile.ZIP_DEFLATED) as output:
        for path in paths:
            name = str(path.relative_to(bundle.parent))
            if path.is_symlink():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                output.writestr(entry, os.readlink(str(path)))
            else:
                output.write(str(path), name)
    return archive


class NativeQuarantineAdapterTests(unittest.TestCase):
    def test_native_adapter_binds_explicit_signing_mode_without_running_a_command(self):
        with patch.object(installer.sys, "platform", "darwin"):
            self.assertEqual(installer.MacOperations().signing_mode, "adhoc")
            self.assertEqual(installer.MacOperations("developer-id").signing_mode, "developer-id")

    def test_reads_every_owned_entry_without_traversing_symlink_destinations(self):
        with tempfile.TemporaryDirectory(prefix="jones-quarantine-", dir=SCRATCH_PARENT) as temporary:
            root = Path(temporary)
            bundle = make_bundle(root / "candidate.app")
            outside = root / "outside"
            outside.mkdir()
            (outside / "unread.txt").write_text("synthetic", encoding="ascii")
            link = bundle / "Contents/link"
            link.symlink_to(outside, target_is_directory=True)
            with patch.object(installer.sys, "platform", "darwin"), \
                    patch.object(installer, "list_xattrs", return_value=[]) as read:
                installer.MacOperations().quarantine(bundle)
            inspected = [call.args[0] for call in read.call_args_list]
            self.assertIn(bundle, inspected)
            self.assertIn(bundle / "Contents/MacOS/CodexBar", inspected)
            self.assertIn(link, inspected)
            self.assertFalse(any(path == outside or outside in path.parents for path in inspected))

    def test_quarantine_and_unknown_metadata_both_refuse_the_native_adapter(self):
        with tempfile.TemporaryDirectory(prefix="jones-quarantine-", dir=SCRATCH_PARENT) as temporary:
            path = Path(temporary) / "archive.zip"
            path.write_bytes(b"synthetic")
            for attributes, failure, code in ((["com.apple.quarantine"], None, "quarantine"),
                                               (None, OSError("unavailable"), "quarantine_unknown")):
                with patch.object(installer.sys, "platform", "darwin"), \
                        patch.object(installer, "list_xattrs", return_value=attributes, side_effect=failure):
                    with self.assertRaises(installer.InstallError) as caught:
                        installer.MacOperations().quarantine(path)
                self.assertEqual(caught.exception.code, code)

    def test_isolated_cli_loads_its_owned_helper_without_pythonpath_overrides(self):
        with tempfile.TemporaryDirectory(prefix="jones-isolated-cli-", dir=SCRATCH_PARENT) as temporary:
            root = Path(temporary)
            (root / "jones_xattrs.py").write_text("raise RuntimeError('foreign helper loaded')\n", encoding="ascii")
            wrapper = Path(__file__).with_name("jones_install_app.sh")
            result = subprocess.run(["/bin/bash", str(wrapper), "--help"], cwd=root,
                                    env=dict(os.environ, PYTHONPATH=str(root)), capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--expect-revision", result.stdout)
            self.assertEqual(sorted(path.name for path in root.iterdir()), ["jones_xattrs.py"])


class FakeOperations:
    def __init__(self):
        self.events = []
        self.running = []
        self.free = 10 * installer.RESERVE
        self.fail_copy = False
        self.fail_launch = False
        self.refuse_quit = False
        self.failure_phase = None
        self.phase_effect = None

    def verify_signature(self, bundle, identifier):
        self.events.append(("signature", str(bundle)))
        value = json.loads((bundle / "Contents/fixture-signature.json").read_text(encoding="utf-8"))
        installer.require(value["valid"], "signature", "Synthetic seal rejected.")
        detail = ("Identifier=" + value["identifier"] + "\nSignature=" + value["signature"]
                  + "\nTeamIdentifier=" + value["team"] + "\nCDHash=" + "b" * 40
                  + "\nSealed Resources version=2 rules=13 files=12\n")
        return installer.signature_details(detail.encode("utf-8"), identifier), value["entitlements"]

    def architectures(self, executable):
        return executable.read_text(encoding="ascii").split()

    def quarantine(self, root):
        marker = root / "Contents/fixture-quarantine" if root.is_dir() else root.with_suffix(".quarantine")
        installer.require(not marker.exists(), "quarantine", "Synthetic quarantine refusal.")

    def available(self, _path):
        return self.free

    def clone(self, source, destination):
        self.events.append(("ditto", str(source), str(destination)))
        if self.fail_copy:
            (destination / "partial").write_text("partial", encoding="ascii")
            raise installer.InstallError("copy_failure", "Synthetic ditto failure.", 3)
        shutil.copytree(str(source), str(destination), dirs_exist_ok=True, symlinks=True)

    def processes(self, target, action="inspect"):
        matching = [row for row in self.running if row["bundle_id"] == installer.BUNDLE_ID
                    or row["bundle_path"] == str(target)]
        self.events.append((action, str(target)))
        if action == "quit":
            for row in matching:
                assert row["bundle_path"] == str(target) and row["bundle_id"] == installer.BUNDLE_ID
            if not self.refuse_quit:
                self.running = [row for row in self.running if row not in matching]
        return copy.deepcopy(matching)

    def launch(self, target):
        self.events.append(("launch", str(target)))
        if self.fail_launch:
            raise installer.InstallError("launch", "Synthetic native consent refusal.", 3)
        self.running = [self.row(target)]

    @staticmethod
    def row(target):
        return {"pid": 501, "bundle_id": installer.BUNDLE_ID, "bundle_path": str(target),
                "executable_path": str(target / "Contents/MacOS/CodexBar")}

    def pause(self):
        pass

    def bootstrap(self, bundle, action, root):
        self.events.append(("bootstrap", action))
        if getattr(self, "bootstrap_error", False):
            raise installer.InstallError("synthetic_data_drift", "Synthetic migration data changed.")
        request = installer.json_file(root / "request.json")
        if action in ("prepare", "resume"):
            plan = {"request": request, "oldGroup": installer.GROUP_ID, "newGroup": installer._SIGNING_MODULE.GROUP,
                    "locations": {"old": str(root / "synthetic-old"), "destination": str(root / "synthetic-new"),
                                  "fallback": str(root / "synthetic-fallback"), "standard": str(root / "synthetic-local")},
                    "sources": {}, "items": []}
            encoded = json.dumps(plan, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
            installer.atomic_json(root / "receipt.json", {"schema": "jones-bootstrap-receipt/v1", "plan": plan,
                                  "planSHA256": hashlib.sha256(encoded).hexdigest(), "phase": "prepared"})
        elif action == "verify":
            receipt = installer.json_file(root / "receipt.json")
            receipt["phase"] = "data-verified"
            installer.atomic_json(root / "receipt.json", receipt)

    def checkpoint(self, phase):
        self.events.append(("phase", phase))
        if phase == self.failure_phase:
            self.failure_phase = None
            if self.phase_effect is not None:
                self.phase_effect()
            raise installer.InstallError("injected", "Synthetic transaction failure at " + phase, 3)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.addCleanup(os.umask, os.umask(0o022))
        self.temporary = tempfile.TemporaryDirectory(prefix="jones-installer-case-", dir=str(SCRATCH_PARENT))
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / "Applications/CodexBar Jones.app"
        self.bundle = make_bundle(self.root / "source/CodexBar.app")
        self.archive = zip_bundle(self.bundle, self.root / "candidate.zip")
        self.ops = FakeOperations()

    def args(self, preflight=False):
        values = ["--archive", str(self.archive), "--sha256", hashlib.sha256(self.archive.read_bytes()).hexdigest(),
                  "--expect-revision", REVISION, "--target", str(self.target)]
        if preflight:
            values.append("--preflight")
        return installer.arguments(values)

    def repack(self):
        zip_bundle(self.bundle, self.archive)

    def old(self, build="135", legacy=True):
        return make_bundle(self.target, build, legacy)

    def run_install(self, preflight=False):
        return installer.execute(self.args(preflight), self.ops)

    def restore(self):
        return installer.execute(installer.arguments(["--restore", "--target", str(self.target)]), self.ops)

    def assert_error(self, code, action):
        with self.assertRaises(installer.InstallError) as captured:
            action()
        self.assertEqual(captured.exception.code, code)
        return captured.exception

    def assert_no_scratch(self):
        self.assertEqual(list(self.root.rglob(".jones-install-preflight-*")), [])

    def production_fixture(self):
        changes = dict(JonesSigningMode="developer-id", CodexBarTeamID=installer._SIGNING_MODULE.TEAM,
                       JonesAppGroupID=installer._SIGNING_MODULE.GROUP, SUFeedURL="", SUPublicEDKey="",
                       SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False)
        change_plist(self.bundle, **changes)
        change_plist(self.bundle / "Contents/PlugIns/CodexBarWidget.appex", **changes)
        self.repack()

    def test_production_requires_explicit_mode_and_legacy_transition_is_held_before_mutation(self):
        self.production_fixture()
        self.assert_error("signing_mode", lambda: self.run_install(preflight=True))
        self.ops.signing_mode = "developer-id"
        self.old()
        adhoc_signature = self.ops.verify_signature

        def signature(bundle, identifier):
            info = installer.read_plist(bundle / "Contents/Info.plist")
            if info.get("JonesSigningMode") == "developer-id":
                return "c" * 40, installer._SIGNING_MODULE.entitlements(identifier)
            return adhoc_signature(bundle, identifier)

        before = installer.tree_hash(self.target)
        with patch.object(self.ops, "verify_signature", side_effect=signature):
            self.assert_error("migration_held", lambda: self.run_install(preflight=True))
            self.assert_error("migration_held", self.run_install)
        self.assertEqual(installer.tree_hash(self.target), before)
        self.assertFalse(installer.State(self.target).root.exists())
        self.assertFalse(any(event[0] in ("quit", "launch", "ditto") for event in self.ops.events))
        self.assert_no_scratch()

    def test_production_opt_in_can_preflight_first_install_but_not_enable_feed(self):
        self.production_fixture()
        self.ops.signing_mode = "developer-id"
        with patch.object(self.ops, "verify_signature", side_effect=lambda bundle, identifier:
                          ("c" * 40, installer._SIGNING_MODULE.entitlements(identifier))):
            result = self.run_install(preflight=True)
            self.assertEqual(result["candidate"]["identity"]["CodexBarTeamID"], "2CUPSQS986")
            self.assertFalse(self.target.exists())
            change_plist(self.bundle, JonesUpdateChannel="stable")
            self.repack()
            self.assert_error("migration_held", lambda: self.run_install(preflight=True))

    def bootstrap_fixture(self):
        self.old()
        self.production_fixture()
        self.ops.signing_mode = "developer-id"
        adhoc_signature = self.ops.verify_signature

        def signature(bundle, identifier):
            if installer.read_plist(bundle / "Contents/Info.plist").get("JonesSigningMode") == "developer-id":
                return "c" * 40, installer._SIGNING_MODULE.entitlements(identifier)
            return adhoc_signature(bundle, identifier)

        self.ops.verify_signature = signature
        args = self.args()
        args.signing_mode = "developer-id"
        args.bootstrap_prepare = True
        result = installer.execute(args, self.ops)
        args.bootstrap_prepare = False
        args.bootstrap_receipt = result["receipt"]
        args.receipt_sha256 = result["receipt_sha256"]
        return args

    def bootstrap_finish_args(self, result, action):
        return installer.arguments([action, "--target", str(self.target), "--signing-mode", "developer-id",
                                    "--bootstrap-receipt", result["receipt"],
                                    "--receipt-sha256", result["receipt_sha256"]])

    def test_bootstrap_prepare_install_and_explicit_launch_keep_separate_legacy(self):
        args = self.bootstrap_fixture()
        old = installer.tree_hash(self.target)
        result = installer.execute(args, self.ops)
        self.assertEqual(result["status"], "installed-not-launched")
        self.assertFalse(any(event[0] == "launch" for event in self.ops.events))
        self.assertEqual(installer.tree_hash(Path(result["legacy_path"])), old)
        manifest = installer.State(self.target).load(self.ops)
        self.assertEqual(manifest["schema"], installer.BOOTSTRAP_STATE_SCHEMA)
        self.assertIsNone(manifest["previous"])
        launched = installer.execute(self.bootstrap_finish_args(result, "--bootstrap-launch"), self.ops)
        self.assertEqual(launched["status"], "bootstrap-launched")
        self.assert_error("bootstrap_replay", lambda: installer.execute(
            self.bootstrap_finish_args(result, "--bootstrap-rollback"), self.ops))

    def test_bootstrap_before_launch_rollback_preserves_prepared_data_and_production(self):
        args = self.bootstrap_fixture()
        old = installer.tree_hash(self.target)
        result = installer.execute(args, self.ops)
        root = Path(result["receipt"]).parent
        sentinel = root / "synthetic-prepared-data"
        sentinel.write_bytes(b"prepared destination data")
        restored = installer.execute(self.bootstrap_finish_args(result, "--bootstrap-rollback"), self.ops)
        self.assertEqual(restored["status"], "bootstrap-rolled-back")
        self.assertEqual(installer.tree_hash(self.target), old)
        self.assertEqual(sentinel.read_bytes(), b"prepared destination data")
        self.assertTrue((root / "production.app").is_dir())
        self.assertIsNone(installer.State(self.target).load(self.ops))
        self.assert_error("bootstrap_replay", lambda: installer.execute(
            self.bootstrap_finish_args(result, "--bootstrap-launch"), self.ops))

    def test_bootstrap_receipt_wrong_hash_or_binding_and_source_drift_never_swap(self):
        args = self.bootstrap_fixture()
        before = installer.tree_hash(self.target)
        original_hash = args.receipt_sha256
        args.receipt_sha256 = "f" * 64
        self.assert_error("bootstrap_receipt", lambda: installer.execute(args, self.ops))
        args.receipt_sha256 = original_hash
        receipt_path = Path(args.bootstrap_receipt)
        original = installer.json_file(receipt_path)
        for field, replacement in (("uid", os.getuid() + 1), ("target", "/other/CodexBar Jones.app"),
                                   ("oldTree", "f" * 64), ("candidateTree", "f" * 64),
                                   ("revision", "f" * 40), ("archive", "f" * 64)):
            receipt = copy.deepcopy(original)
            receipt["plan"]["request"][field] = replacement
            plan = json.dumps(receipt["plan"], sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
            receipt["planSHA256"] = hashlib.sha256(plan).hexdigest()
            installer.atomic_json(receipt_path, receipt)
            args.receipt_sha256 = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
            self.assert_error("bootstrap_binding", lambda: installer.execute(args, self.ops))
        installer.atomic_json(receipt_path, original)
        args.receipt_sha256 = hashlib.sha256(receipt_path.read_bytes()).hexdigest()
        self.ops.bootstrap_error = True
        self.assert_error("synthetic_data_drift", lambda: installer.execute(args, self.ops))
        self.assertEqual(installer.tree_hash(self.target), before)
        self.assertFalse(any(event[0] in ("ditto", "launch") for event in self.ops.events))

    def test_bootstrap_stale_app_and_changed_receipt_refuse(self):
        args = self.bootstrap_fixture()
        change_plist(self.target, CFBundleShortVersionString="0.56.5")
        self.assert_error("bootstrap_binding", lambda: installer.execute(args, self.ops))
        self.assertFalse(any(event[0] == "ditto" for event in self.ops.events))

    def test_bootstrap_journal_interruption_preserves_legacy_before_commit(self):
        args = self.bootstrap_fixture()
        before = installer.tree_hash(self.target)
        for phase in ("staging", "prepared", "will_move_previous", "will_install", "installed_uncommitted", "will_commit"):
            self.ops.failure_phase = phase
            self.assert_error("injected", lambda: installer.execute(args, self.ops))
            self.assertEqual(installer.tree_hash(self.target), before)
            self.assertFalse((Path(args.bootstrap_receipt).parent / "legacy.app").exists())
        result = installer.execute(args, self.ops)
        self.assertEqual(result["status"], "installed-not-launched")

    def test_bootstrap_consumed_receipt_and_unknown_schema_refuse(self):
        args = self.bootstrap_fixture()
        path = Path(args.bootstrap_receipt)
        receipt = installer.json_file(path)
        for schema, phase in (("unknown", "data-verified"), ("jones-bootstrap-receipt/v1", "launch-attempted")):
            changed = dict(receipt, schema=schema, phase=phase)
            installer.atomic_json(path, changed)
            args.receipt_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
            self.assert_error("bootstrap_receipt", lambda: installer.execute(args, self.ops))

    def test_bootstrap_concurrent_invocation_refuses_before_native_data_command(self):
        args = self.bootstrap_fixture()
        bootstrap = installer.Bootstrap(installer.State(self.target), args.bootstrap_receipt, args.receipt_sha256)
        with bootstrap.lock():
            self.assert_error("busy", lambda: installer.execute(args, self.ops))

    def test_bootstrap_preserves_v1_previous_and_future_production_rotation(self):
        self.old()
        self.run_install()
        self.ops.running = []
        before = installer.State(self.target).load(self.ops)
        legacy = installer.tree_hash(self.target)
        self.production_fixture()
        change_plist(self.bundle, CFBundleVersion="135.3")
        change_plist(self.bundle / "Contents/PlugIns/CodexBarWidget.appex", CFBundleVersion="135.3")
        self.repack()
        self.ops.signing_mode = "developer-id"
        adhoc_signature = self.ops.verify_signature
        self.ops.verify_signature = lambda bundle, identifier: (
            ("c" * 40, installer._SIGNING_MODULE.entitlements(identifier))
            if installer.read_plist(bundle / "Contents/Info.plist").get("JonesSigningMode") == "developer-id"
            else adhoc_signature(bundle, identifier))
        args = self.args()
        args.bootstrap_prepare = True
        prepared = installer.execute(args, self.ops)
        args.bootstrap_prepare = False
        args.bootstrap_receipt = prepared["receipt"]
        args.receipt_sha256 = prepared["receipt_sha256"]
        result = installer.execute(args, self.ops)
        state = installer.State(self.target)
        self.assertEqual(state.load(self.ops)["bootstrap_previous"], before["previous"])
        self.assert_error("bootstrap_pending", lambda: installer.execute(self.args(), self.ops))
        self.assert_error("bootstrap_pending", self.restore)
        installer.execute(self.bootstrap_finish_args(result, "--bootstrap-launch"), self.ops)
        for build in ("135.4", "135.5"):
            change_plist(self.bundle, CFBundleVersion=build)
            change_plist(self.bundle / "Contents/PlugIns/CodexBarWidget.appex", CFBundleVersion=build)
            self.repack()
            installer.execute(self.args(), self.ops)
        self.assertEqual(installer.tree_hash(Path(result["legacy_path"])), legacy)
        self.assertEqual(state.load(self.ops)["bootstrap_previous"], before["previous"])
        restored = self.restore()
        self.assertEqual(restored["candidate"]["build"], "135.4")
        self.assertEqual(installer.tree_hash(Path(result["legacy_path"])), legacy)

    def test_bootstrap_argument_routes_do_not_weaken_ordinary_restore(self):
        for values in (["--restore", "--bootstrap-prepare"],
                       ["--bootstrap-prepare", "--preflight", "--signing-mode", "developer-id"],
                       ["--bootstrap-launch", "--signing-mode", "developer-id"],
                       ["--bootstrap-receipt", "/some/receipt.json"]):
            self.assert_error("arguments", lambda: installer.arguments(values))

    def test_preflight_has_machine_contract_and_no_persistent_effect(self):
        before = sorted(str(path.relative_to(self.root)) for path in self.root.rglob("*"))
        result = self.run_install(preflight=True)
        self.assertEqual(result["schema"], installer.SCHEMA)
        self.assertEqual(result["status"], "preflight_ok")
        self.assertEqual(result["candidate"]["revision"], REVISION)
        self.assertEqual(result["candidate"]["origin"], "ci-main")
        self.assertEqual(result["external_provenance"], "operator_verified_required")
        self.assertFalse(self.target.parent.exists())
        self.assertEqual(before, sorted(str(path.relative_to(self.root)) for path in self.root.rglob("*")))
        self.assertFalse(any(event[0] in ("quit", "launch", "ditto") for event in self.ops.events))

    def test_hash_mismatch_refuses_without_state(self):
        args = self.args()
        args.sha256 = "0" * 64
        self.assert_error("hash", lambda: installer.execute(args, self.ops))
        self.assertFalse(self.target.parent.exists())
        self.assert_no_scratch()

    def test_revision_origin_and_complete_provenance_are_required(self):
        original = (self.bundle / "Contents/Info.plist").read_bytes()
        cases = [dict(JonesSourceRevision="b" * 40), dict(JonesSourceRevision="a" * 8),
                 dict(JonesSourceRevision=None), dict(JonesBuildOrigin="ci-pr"), dict(JonesBuildOrigin="local"),
                 dict(JonesBuildRun="https://github.com/steipete/CodexBar/actions/runs/1"),
                 dict(JonesUpdateChannel=None), dict(CFBundleVersion="135"), dict(CFBundleVersion="135.02")]
        for changes in cases:
            with self.subTest(changes=changes):
                (self.bundle / "Contents/Info.plist").write_bytes(original)
                change_plist(self.bundle, **changes)
                self.repack()
                with self.assertRaises(installer.InstallError):
                    self.run_install()
                self.assertFalse(installer.State(self.target).root.exists())
                self.assert_no_scratch()

    def test_all_identity_fields_and_harness_are_rejected_before_mutation(self):
        original = (self.bundle / "Contents/Info.plist").read_bytes()
        for key in list(installer.IDENTITY) + ["JonesUpdateHarness", "JonesUpdateHarnessFixtureID"]:
            with self.subTest(key=key):
                (self.bundle / "Contents/Info.plist").write_bytes(original)
                change_plist(self.bundle, **{key: True if key == "JonesUpdateHarness" else "foreign"})
                self.repack()
                self.assert_error("identity", self.run_install)
                self.assertFalse(self.target.parent.exists())
        self.assert_no_scratch()

    def test_unsigned_wrong_team_and_icloud_entitlements_are_refused(self):
        path = self.bundle / "Contents/fixture-signature.json"
        original = path.read_bytes()
        for changes in [dict(valid=False), dict(signature="Developer ID Application"), dict(team="OTHERTEAM"),
                        dict(entitlements={"com.apple.security.application-groups": [installer.GROUP_ID],
                                           "com.apple.developer.icloud-container-identifiers": [installer.ICLOUD_ID]})]:
            with self.subTest(changes=changes):
                path.write_bytes(original)
                change_signature(self.bundle, **changes)
                self.repack()
                with self.assertRaises(installer.InstallError):
                    self.run_install()
                self.assertFalse(self.target.parent.exists())

    def test_signature_parser_requires_typed_adhoc_and_resource_seal(self):
        correct = ("Identifier=" + installer.BUNDLE_ID + "\nSignature=adhoc\nTeamIdentifier=not set\nCDHash="
                   + "b" * 40 + "\nSealed Resources version=2 rules=13 files=12\n")
        self.assertEqual(installer.signature_details(correct.encode(), installer.BUNDLE_ID), "b" * 40)
        for value in [correct.replace("Signature=adhoc", "Signature=not-adhoc"),
                      correct.replace("Sealed Resources version=2", "Sealed Resources version=1"),
                      correct + "Authority=Other\n", correct + "Signature=adhoc\n"]:
            with self.subTest(value=value):
                self.assert_error("signature", lambda: installer.signature_details(value.encode(), installer.BUNDLE_ID))

    def test_native_command_adapter_uses_exact_bundle_and_system_tools(self):
        detail = ("Identifier=" + installer.BUNDLE_ID + "\nSignature=adhoc\nTeamIdentifier=not set\nCDHash="
                  + "b" * 40 + "\nSealed Resources version=2 rules=13 files=12\n").encode()
        entitlements = {"com.apple.security.application-groups": [installer.GROUP_ID]}
        commands = []

        def fake_run(arguments, timeout=60):
            commands.append(arguments)
            if "--entitlements" in arguments:
                return SimpleNamespace(stdout=plistlib.dumps(entitlements), stderr=b"")
            if "--verbose=4" in arguments:
                return SimpleNamespace(stdout=b"", stderr=detail)
            if arguments[0] == "/usr/bin/lipo":
                return SimpleNamespace(stdout=b"arm64\n", stderr=b"")
            if arguments[0] == "/usr/bin/osascript":
                return SimpleNamespace(stdout=b"[]\n", stderr=b"")
            return SimpleNamespace(stdout=b"", stderr=b"")

        with patch.object(installer.sys, "platform", "darwin"):
            native = installer.MacOperations()
        with patch.object(native, "run", side_effect=fake_run):
            self.assertEqual(native.verify_signature(self.bundle, installer.BUNDLE_ID), ("b" * 40, entitlements))
            self.assertEqual(native.architectures(self.bundle / "Contents/MacOS/CodexBar"), ["arm64"])
            native.clone(self.bundle, self.target)
            self.assertEqual(native.processes(self.target), [])
            native.launch(self.target)
        self.assertIn(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(self.bundle)], commands)
        self.assertIn(["/usr/bin/ditto", str(self.bundle), str(self.target)], commands)
        self.assertIn(["/usr/bin/open", "-n", "-a", str(self.target)], commands)
        script = next(command for command in commands if command[0] == "/usr/bin/osascript")
        self.assertEqual(script[-3:], [str(self.target), installer.BUNDLE_ID, "inspect"])

    def test_widget_identity_architecture_and_entitlements_are_checked(self):
        widget = self.bundle / "Contents/PlugIns/CodexBarWidget.appex"
        change_plist(widget, JonesICloudID="iCloud.foreign")
        self.repack()
        self.assert_error("widget_identity", self.run_install)
        change_plist(widget, JonesICloudID=installer.ICLOUD_ID)
        (widget / "Contents/MacOS/CodexBarWidget").write_text("x86_64", encoding="ascii")
        self.repack()
        self.assert_error("architecture", self.run_install)
        (widget / "Contents/MacOS/CodexBarWidget").write_text("arm64", encoding="ascii")
        change_signature(widget, entitlements={"com.apple.security.application-groups": ["foreign"]})
        self.repack()
        self.assert_error("entitlements", self.run_install)
        change_signature(widget, entitlements={"com.apple.security.application-groups": [installer.GROUP_ID],
                                              "com.apple.security.app-sandbox": 1})
        self.repack()
        self.assert_error("entitlements", self.run_install)

    def test_archive_and_bundle_quarantine_are_never_removed(self):
        marker = self.archive.with_suffix(".quarantine")
        marker.write_text("synthetic", encoding="ascii")
        self.assert_error("quarantine", self.run_install)
        self.assertTrue(marker.exists())
        marker.unlink()
        (self.bundle / "Contents/fixture-quarantine").write_text("synthetic", encoding="ascii")
        self.repack()
        self.assert_error("quarantine", self.run_install)
        self.assertFalse(self.target.parent.exists())

    def test_capacity_unknown_and_insufficient_are_refusals(self):
        for free, code in [(None, "capacity_unknown"), (-1, "capacity_unknown"),
                           (True, "capacity_unknown"), (1, "capacity")]:
            with self.subTest(free=free):
                self.ops.free = free
                self.assert_error(code, self.run_install)
                self.assertFalse(self.target.parent.exists())
                self.assert_no_scratch()

    def test_unsafe_archive_names_and_siblings_are_rejected(self):
        for name in ["../escape", "/absolute", "CodexBar.app/../escape", "CodexBar.app/a\\b", "CodexBar.app/x:y",
                     "Other.app/Contents/Info.plist", "__MACOSX/._CodexBar.app", "CodexBar.app/contents/info.plist"]:
            with self.subTest(name=name):
                self.repack()
                with zipfile.ZipFile(str(self.archive), "a") as archive:
                    archive.writestr(name, "hostile")
                with self.assertRaises(installer.InstallError):
                    self.run_install()
                self.assertFalse((self.root / "escape").exists())
                self.assertFalse(self.target.parent.exists())

    def test_symlink_escape_cycle_and_symlink_parent_are_refused(self):
        for destination, child in [("../../escape", False), ("alias", False), ("MacOS", True)]:
            with self.subTest(destination=destination, child=child):
                self.repack()
                with zipfile.ZipFile(str(self.archive), "a") as archive:
                    entry = zipfile.ZipInfo("CodexBar.app/Contents/alias")
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, destination)
                    if child:
                        archive.writestr("CodexBar.app/Contents/alias/payload", "hostile")
                with self.assertRaises(installer.InstallError):
                    self.run_install()
                self.assert_no_scratch()

    def test_internal_framework_style_symlink_survives(self):
        framework = self.bundle / "Contents/Frameworks/Example.framework"
        (framework / "Versions/B").mkdir(parents=True)
        (framework / "Versions/B/Example").write_text("fixture", encoding="ascii")
        (framework / "Versions/Current").symlink_to("B")
        (framework / "Example").symlink_to("Versions/Current/Example")
        self.repack()
        self.run_install()
        self.assertTrue((self.target / "Contents/Frameworks/Example.framework/Example").is_symlink())

    def test_archive_size_and_special_files_are_refused(self):
        with patch.object(installer, "MAX_ARCHIVE", 10):
            self.assert_error("archive_size", self.run_install)
        with patch.object(installer, "MAX_EXPANDED", 10):
            self.assert_error("archive_size", self.run_install)
        with zipfile.ZipFile(str(self.archive), "a") as archive:
            entry = zipfile.ZipInfo("CodexBar.app/device")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFCHR | 0o600) << 16
            archive.writestr(entry, b"")
        self.assert_error("archive_type", self.run_install)

    def test_foreign_symlink_and_unsupported_legacy_targets_are_untouched(self):
        self.old()
        change_plist(self.target, CFBundleIdentifier="com.steipete.codexbar")
        before = installer.tree_hash(self.target)
        self.assert_error("identity", self.run_install)
        self.assertEqual(before, installer.tree_hash(self.target))
        self.assertFalse(installer.State(self.target).root.exists())
        change_plist(self.target, CFBundleIdentifier=installer.BUNDLE_ID, CFBundleVersion="136")
        self.assert_error("build", self.run_install)
        moved = self.target.with_name("Other.app")
        self.target.rename(moved)
        self.target.symlink_to(moved)
        self.assert_error("symlink_path", self.run_install)
        self.assertTrue(self.target.is_symlink())

    def test_equal_and_lower_builds_refuse_even_with_different_source(self):
        self.old(build="135.2", legacy=False)
        before = installer.tree_hash(self.target)
        self.assert_error("not_newer", self.run_install)
        change_plist(self.target, CFBundleVersion="136.1")
        widget = self.target / "Contents/PlugIns/CodexBarWidget.appex"
        change_plist(widget, CFBundleVersion="136.1")
        self.assert_error("not_newer", self.run_install)
        self.assertFalse(installer.State(self.target).root.exists())
        self.assertNotEqual(before, installer.tree_hash(self.target))

    def test_install_renames_legacy_previous_and_preserves_siblings(self):
        self.old()
        old_inode = self.target.stat().st_ino
        old_hash = installer.tree_hash(self.target)
        sibling = self.target.with_name("CodexBar Jones.pending.app")
        sibling.mkdir()
        (sibling / "unknown").write_text("leave alone", encoding="ascii")
        stock = self.target.with_name("CodexBar.app")
        stock.mkdir()
        (stock / "owner-data").write_text("untouched", encoding="ascii")
        before = (installer.tree_hash(sibling), installer.tree_hash(stock))
        self.ops.running = [self.ops.row(self.target)]
        result = self.run_install()
        self.assertEqual(result["status"], "installed")
        previous = Path(result["previous_path"])
        self.assertEqual(previous.stat().st_ino, old_inode)
        self.assertEqual(installer.tree_hash(previous), old_hash)
        self.assertEqual(before, (installer.tree_hash(sibling), installer.tree_hash(stock)))
        self.assertIn(("quit", str(self.target)), self.ops.events)
        self.assertIn(("launch", str(self.target)), self.ops.events)
        self.assert_no_scratch()

    def test_next_install_keeps_exactly_one_previous_and_explicit_restore_rotates(self):
        self.old()
        first = self.run_install()
        retired = Path(first["previous_path"])
        second_source = self.root / "second/CodexBar.app"
        make_bundle(second_source, "135.3")
        zip_bundle(second_source, self.archive)
        second = self.run_install()
        self.assertFalse(retired.exists())
        state = installer.State(self.target)
        self.assertEqual(len(list(state.root.glob("previous-*.app"))), 1)
        restored = self.restore()
        self.assertEqual(restored["candidate"]["build"], "135.2")
        self.assertEqual(len(list(state.root.glob("previous-*.app"))), 1)
        self.assertFalse(Path(second["previous_path"]).exists())
        self.assertEqual(state.load(self.ops)["previous"]["record"]["bundle"]["build"], "135.3")

    def test_first_install_has_no_previous_and_restore_refuses(self):
        result = self.run_install()
        self.assertIsNone(result["previous_path"])
        self.assert_error("no_previous", self.restore)

    def test_restore_can_recover_exact_legacy_135(self):
        self.old()
        old_hash = installer.tree_hash(self.target)
        self.run_install()
        result = self.restore()
        self.assertTrue(result["candidate"]["legacy_build_135"])
        self.assertEqual(installer.tree_hash(self.target), old_hash)

    def test_other_running_copy_and_quit_refusal_never_launch(self):
        self.old()
        old_hash = installer.tree_hash(self.target)
        self.ops.running = [self.ops.row(self.target.with_name("Pending.app"))]
        self.assert_error("other_running_copy", self.run_install)
        self.assertFalse(any(event[0] == "quit" for event in self.ops.events))
        self.ops.running = [self.ops.row(self.target)]
        self.ops.refuse_quit = True
        self.assert_error("still_running", self.run_install)
        self.assertEqual(installer.tree_hash(self.target), old_hash)
        self.assertFalse(any(event[0] == "launch" for event in self.ops.events))
        self.assert_no_scratch()

    def test_copy_failure_cleans_stage_and_preserves_target(self):
        self.old()
        before = installer.tree_hash(self.target)
        self.ops.fail_copy = True
        self.assert_error("copy_failure", self.run_install)
        self.assertEqual(installer.tree_hash(self.target), before)
        state = installer.State(self.target)
        self.assertIsNone(state.load(self.ops))
        self.assert_no_scratch()

    def test_every_uncommitted_phase_failure_restores_known_preimage(self):
        self.old()
        before = installer.tree_hash(self.target)
        original_inode = self.target.stat().st_ino
        for phase in ("staging", "prepared", "will_move_previous", "will_install",
                      "installed_uncommitted", "will_commit"):
            with self.subTest(phase=phase):
                self.ops.failure_phase = phase
                self.assert_error("injected", self.run_install)
                self.assertEqual(installer.tree_hash(self.target), before)
                self.assertEqual(self.target.stat().st_ino, original_inode)
                self.assertIsNone(installer.State(self.target).load(self.ops))
                self.assert_no_scratch()

    def test_rename_failures_restore_without_replacing_unowned_paths(self):
        self.old()
        before = installer.tree_hash(self.target)
        actual_rename = os.rename
        for fail_number in (1, 2):
            with self.subTest(rename=fail_number):
                calls = []

                def fail_one(source, destination):
                    calls.append((source, destination))
                    if len(calls) == fail_number:
                        raise OSError("synthetic rename failure")
                    return actual_rename(source, destination)

                with patch.object(installer.os, "rename", side_effect=fail_one):
                    with self.assertRaisesRegex(OSError, "synthetic rename failure"):
                        self.run_install()
                self.assertEqual(installer.tree_hash(self.target), before)
                self.assertIsNone(installer.State(self.target).load(self.ops))
                self.assert_no_scratch()

    def test_first_install_failure_removes_only_its_new_bundle(self):
        self.ops.failure_phase = "installed_uncommitted"
        self.assert_error("injected", self.run_install)
        self.assertFalse(self.target.exists())
        self.assertIsNone(installer.State(self.target).load(self.ops))
        self.assert_no_scratch()

    def test_handled_signals_restore_and_clean_owned_scratch(self):
        self.old()
        before = installer.tree_hash(self.target)
        for number in installer.SIGNALS:
            with self.subTest(signal=number):
                self.ops.failure_phase = "installed_uncommitted"
                self.ops.phase_effect = lambda: signal.raise_signal(number)
                with installer.cancellation_handlers():
                    error = self.assert_error("cancelled", self.run_install)
                self.assertEqual(error.exit_code, 128 + number)
                self.assertEqual(installer.tree_hash(self.target), before)
                self.assertIsNone(installer.State(self.target).load(self.ops))
                self.assert_no_scratch()

    def test_restore_failure_keeps_current_and_prior_manifest(self):
        self.old()
        self.run_install()
        state = installer.State(self.target)
        original = state.load(self.ops)
        self.ops.failure_phase = "installed_uncommitted"
        self.assert_error("injected", self.restore)
        self.assertEqual(state.load(self.ops), original)

    def test_unknown_rollback_effect_preserves_journal_and_refuses_rerun(self):
        self.old()

        def substitute():
            self.target.rename(self.target.with_name("external-moved.app"))
            self.target.mkdir()
            (self.target / "owner").write_text("unknown", encoding="ascii")

        self.ops.failure_phase = "installed_uncommitted"
        self.ops.phase_effect = substitute
        self.assert_error("rollback_unknown", self.run_install)
        state = installer.State(self.target)
        journal = state.root / "journal.json"
        before = journal.read_bytes()
        self.assert_error("pending_transaction", self.run_install)
        self.assert_error("pending_transaction", self.restore)
        self.assertEqual(journal.read_bytes(), before)
        self.assertTrue((self.target / "owner").exists())
        self.assert_no_scratch()

    def test_committed_failure_has_no_automatic_rollback(self):
        self.old()
        self.ops.failure_phase = "committed"
        self.assert_error("committed_needs_reconciliation", self.run_install)
        self.assertEqual(plistlib.loads((self.target / "Contents/Info.plist").read_bytes())["CFBundleVersion"], "135.2")
        self.assert_error("pending_transaction", self.restore)
        self.assert_no_scratch()

    def test_retirement_failure_preserves_manifest_owned_copies_and_journal(self):
        self.old()
        first = self.run_install()
        retired = Path(first["previous_path"])
        second = make_bundle(self.root / "newer/CodexBar.app", "135.3")
        zip_bundle(second, self.archive)
        original_remove = installer.remove_owned

        def refuse_retirement(path, identity):
            if path == retired:
                raise OSError("synthetic retirement failure")
            return original_remove(path, identity)

        with patch.object(installer, "remove_owned", side_effect=refuse_retirement):
            self.assert_error("committed_needs_reconciliation", self.run_install)
        state = installer.State(self.target)
        self.assertTrue(retired.exists())
        self.assertEqual(len(list(state.root.glob("previous-*.app"))), 2)
        self.assert_error("pending_transaction", self.restore)
        self.assertEqual(plistlib.loads((self.target / "Contents/Info.plist").read_bytes())["CFBundleVersion"], "135.3")
        self.assert_no_scratch()

    def test_launch_failure_preserves_completed_manifest_for_explicit_restore(self):
        self.old()
        self.ops.fail_launch = True
        self.assert_error("installed_launch_unverified", self.run_install)
        state = installer.State(self.target)
        self.assertEqual(state.load(self.ops)["current"]["bundle"]["build"], "135.2")
        self.ops.fail_launch = False
        restored = self.restore()
        self.assertEqual(restored["candidate"]["build"], "135")

    def test_unowned_recovery_state_and_tampered_manifest_are_not_cleaned(self):
        state = installer.State(self.target)
        state.root.mkdir(parents=True, mode=0o700)
        unknown = state.root / "owner-data"
        unknown.write_text("retain", encoding="ascii")
        with self.assertRaises(installer.InstallError):
            self.run_install()
        self.assertEqual(unknown.read_text(encoding="ascii"), "retain")
        unknown.unlink()
        state.root.rmdir()
        self.old()
        self.run_install()
        path = state.root / "manifest.json"
        manifest = installer.json_file(path)
        manifest["previous"]["name"] = "../owner-data.app"
        installer.atomic_json(path, manifest)
        self.assert_error("manifest", self.restore)
        self.assertTrue(self.target.exists())

    def test_changed_previous_and_busy_lock_are_refusals(self):
        self.old()
        result = self.run_install()
        state = installer.State(self.target)
        with state.lock():
            self.assert_error("busy", self.restore)
        previous = Path(result["previous_path"])
        (previous / "Contents/MacOS/CodexBar").write_text("changed", encoding="ascii")
        self.assert_error("architecture", self.restore)
        self.assertTrue(previous.exists())

    def test_scratch_cleanup_failure_preserves_primary_error(self):
        args = self.args()
        args.sha256 = "0" * 64
        original_remove = installer.remove_owned

        def fail_scratch(path, identity):
            if path.name.startswith(".jones-install-preflight-"):
                raise OSError("synthetic cleanup refusal")
            return original_remove(path, identity)

        with patch.object(installer, "remove_owned", side_effect=fail_scratch):
            error = self.assert_error("hash", lambda: installer.execute(args, self.ops))
        self.assertIn("scratch_cleanup_error", error.details)
        self.assertEqual(len(list(self.root.glob(".jones-install-preflight-*"))), 1)

    def test_scratch_cleanup_failure_fails_otherwise_successful_preflight(self):
        original_remove = installer.remove_owned

        def fail_scratch(path, identity):
            if path.name.startswith(".jones-install-preflight-"):
                raise OSError("synthetic cleanup refusal")
            return original_remove(path, identity)

        with patch.object(installer, "remove_owned", side_effect=fail_scratch):
            self.assert_error("scratch_cleanup", lambda: self.run_install(preflight=True))
        self.assertFalse(self.target.parent.exists())

    def test_one_scratch_scope_cannot_clean_another(self):
        with installer.owned_scratch(self.root) as first:
            with installer.owned_scratch(self.root) as second:
                self.assertNotEqual(first, second)
            self.assertFalse(second.exists())
            self.assertTrue(first.exists())
        self.assertFalse(first.exists())

    def test_restore_arguments_are_separate(self):
        for flag, value in [("--archive", "candidate.zip"), ("--sha256", "a" * 64), ("--expect-revision", REVISION)]:
            self.assert_error("arguments", lambda: installer.arguments(["--restore", flag, value]))
        self.assert_error("arguments", lambda: installer.arguments(["--restore", "--preflight"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--scratch-parent", type=Path, default=SCRATCH_PARENT)
    options, remaining = parser.parse_known_args()
    cancellation = []

    def stop_suite(signum, _frame):
        cancellation.append(signum)
        # unittest must stop, rather than treating cancellation as an ordinary failed test.
        raise KeyboardInterrupt

    prior_handlers = {number: signal.signal(number, stop_suite) for number in installer.SIGNALS}
    try:
        # The outer fixture owner cleans even when unittest cannot reach a per-test teardown.
        with tempfile.TemporaryDirectory(prefix=".jones-installer-suite-", dir=str(options.scratch_parent)) as suite:
            SCRATCH_PARENT = Path(suite)
            unittest.main(argv=[sys.argv[0]] + remaining)
    except KeyboardInterrupt:
        sys.exit(128 + (cancellation[-1] if cancellation else signal.SIGINT))
    finally:
        for number, handler in prior_handlers.items():
            signal.signal(number, handler)
