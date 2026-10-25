#!/usr/bin/env python3
"""Parser/contract fixtures only; these do not prove native Mac API availability."""

import contextlib
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import ci_swift_test_native as native


ROOT = Path(__file__).resolve().parent.parent


def path_command(command, value, minimum=None):
    minimum = minimum or (24 if command in native.LOADS else 12)
    value = value.encode() + b"\0"
    size = (minimum + len(value) + 7) // 8 * 8
    return struct.pack("<III", command, size, minimum) + bytes(minimum - 12) + value + bytes(
        size - minimum - len(value))


def image(kind=2, dependencies=(), rpaths=(), commands=(), cpu=native.ARM64, subtype=0):
    values = [path_command(command, path) for command, path in dependencies]
    values += [path_command(0x8000001C, path) for path in rpaths]
    values += list(commands)
    data = b"".join(values)
    return struct.pack("<8I", 0xFEEDFACF, cpu, subtype, kind, len(values), len(data), 0, 0) + data


def universal(slices, *, wide=False, hidden=False):
    """Small synthetic payloads; descriptor tuples may deliberately differ from headers."""
    count = len(slices) - int(hidden)
    table = struct.pack(">II", 0xCAFEBABF if wide else 0xCAFEBABE, count)
    offset = (8 + len(slices) * (32 if wide else 20) + 63) // 64 * 64
    payloads = []
    for cpu, subtype, payload in slices:
        table += struct.pack(">IIQQII" if wide else ">IIIII", cpu, subtype, offset, len(payload), 6,
                             *([0] if wide else []))
        payloads.append((offset, payload))
        offset = (offset + len(payload) + 63) // 64 * 64
    result = bytearray(offset)
    result[:len(table)] = table
    for at, payload in payloads:
        result[at:at + len(payload)] = payload
    return bytes(result)


class NativeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix=".test-native-runtime-", dir=ROOT)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        self.build = self.workspace / ".build"
        self.build.mkdir()
        self.xcode = self.root / "Xcode.app/Contents"
        self.frameworks = self.xcode / "Developer/Library/Frameworks"
        self.frameworks.mkdir(parents=True)
        self.api_calls = []

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def parse(self, content):
        return native.macho(self.write("candidate", content))

    def host(self, build=None):
        # Exercise the real graph/containment with fixture roots, without touching /Applications.
        host = native.Host.__new__(native.Host)
        host.budget = native.Budget()
        host.workspace = self.workspace
        host.logical_build = self.build
        host.build = build or self.build
        host.xcode = self.xcode
        host.developer = self.xcode / "Developer"
        def contains(path):
            self.api_calls.append(str(path))
            return str(path).startswith(("/usr/lib/", "/System/Library/Frameworks/"))
        host.system = SimpleNamespace(uuid="a" * 32, contains=contains)
        host.cache_membership = {}
        host.test_framework_roots = (self.frameworks, self.xcode / "Developer/Library/PrivateFrameworks")
        host.test_library_roots = (self.xcode / "Developer/usr/lib",)
        tool = self.write("Xcode.app/Contents/Developer/usr/bin/swift-package",
                          image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        host.tools = {"swift-package":tool}
        for name in ("xctest", "swiftpm-xctest-helper", "swiftpm-testing-helper"):
            host.tools[name] = self.write("Xcode.app/Contents/Developer/usr/bin/" + name,
                                         image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        host.context = {"schema":native.SCHEMA, "os_build":"25G83", "arch":"arm64",
                        "system_cache_uuid":"a" * 32, "sdk_build":"17C529", "tools":{},
                        "developer_framework_roots":[str(path) for path in native.APPLE_RUNTIME_FRAMEWORKS],
                        "apple_runtime_files":[str(path) for path in getattr(native, "APPLE_RUNTIME_FILES", ())],
                        "framework_aliases":[{"source":str(source), "target":str(target),
                            "raw_target_sha256":hashlib.sha256(os.fsencode(raw)).hexdigest()}
                            for source, raw, target in getattr(native, "APPLE_FRAMEWORK_ALIASES", ())]}
        return host

    def mobiledevice_layout(self):
        source = self.root / "System/Library/PrivateFrameworks/MobileDevice.framework"
        target = self.root / "Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework"
        raw = "../../../Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework"
        source.parent.mkdir(parents=True)
        nested = self.write(str((target / "Versions/A/Frameworks/Nested.framework/Versions/A/Nested").relative_to(self.root)),
                            image(kind=6, dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        binary = self.write(str((target / "Versions/A/MobileDevice").relative_to(self.root)), image(
            kind=6, subtype=0x80000002,
            dependencies=[(0xC, "@loader_path/Frameworks/Nested.framework/Versions/A/Nested")]))
        source.symlink_to(raw, target_is_directory=True)
        return {"source":source, "target":target, "raw":raw, "binary":binary, "nested":nested,
                "logical":source / "Versions/A/MobileDevice"}

    @contextlib.contextmanager
    def mobiledevice_policy(self, layout):
        # Preserve the observed relative bytes under one contained synthetic root.
        with patch.object(native, "SYSTEM_ROOTS", (*native.SYSTEM_ROOTS, layout["source"].parent)), \
                patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", (*native.APPLE_RUNTIME_FRAMEWORKS, layout["target"])), \
                patch.object(native, "APPLE_FRAMEWORK_ALIASES",
                             ((layout["source"], layout["raw"], layout["target"]),), create=True):
            yield

    def weak_mobiledevice_layout(self, present=(True, True)):
        layout = self.mobiledevice_layout()
        layout["device_root"] = self.root / "Library/Apple/System/Library/PrivateFrameworks/DeviceInterface.framework"
        layout["device"] = layout["device_root"] / "Versions/A/DeviceInterface"
        layout["device_nested"] = layout["device_root"] / "Versions/A/Frameworks/Nested.framework/Versions/A/Nested"
        layout["extension"] = self.root / "Library/Apple/usr/appleinternal/lib/libMobileRestoreInternalExtensions.dylib"
        layout["binary"].write_bytes(image(kind=6, subtype=0x80000002,
            dependencies=[(native.WEAK, str(layout["device"])), (native.WEAK, str(layout["extension"]))]))
        if present[0]:
            self.write(str(layout["device"].relative_to(self.root)), image(kind=6, subtype=0x80000002,
                dependencies=[(0xC, "@loader_path/Frameworks/Nested.framework/Versions/A/Nested")]))
            self.write(str(layout["device_nested"].relative_to(self.root)), image(kind=6))
        if present[1]:
            self.write(str(layout["extension"].relative_to(self.root)), image(kind=6, subtype=0x80000002,
                dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        return layout

    @contextlib.contextmanager
    def weak_mobiledevice_policy(self, layout):
        # Translate only roots/files the source actually admits. This fixture is
        # unchanged when executed against the exact older source for regression.
        with patch.object(native, "SYSTEM_ROOTS", (*native.SYSTEM_ROOTS, layout["source"].parent)), \
                patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", tuple(
                    self.root / path.relative_to("/") for path in native.APPLE_RUNTIME_FRAMEWORKS)), \
                patch.object(native, "APPLE_RUNTIME_FILES", tuple(self.root / path.relative_to("/")
                    for path in getattr(native, "APPLE_RUNTIME_FILES", ())), create=True), \
                patch.object(native, "APPLE_FRAMEWORK_ALIASES",
                    ((layout["source"], layout["raw"], layout["target"]),), create=True):
            yield

    def shared_dag(self, levels=5, width=4, leaf_count=16):
        host = self.host()
        nodes = [[self.xcode / f"SharedFrameworks/DAG-{level}-{index}.dylib"
                  for index in range(width)] for level in range(levels)]
        for level, row in enumerate(nodes):
            targets = (nodes[level + 1] if level + 1 < levels else
                       [Path(f"/usr/lib/libSynthetic{index}.dylib") for index in range(leaf_count)])
            for path in row:
                self.write(str(path.relative_to(self.root)), image(kind=6,
                    dependencies=[(0xC, str(target)) for target in targets]))
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(path)) for path in nodes[0]]))
        return host, nodes

    def shared_rpath_layout(self, *, weak=False):
        host = self.host()
        paths = {name:self.xcode / f"SharedFrameworks/{name}.dylib" for name in ("A", "B", "Shared")}
        paths["first"] = self.xcode / "SharedFrameworks/first"
        paths["second"] = self.xcode / "SharedFrameworks/second"
        for name in ("A", "B"):
            self.write(str(paths[name].relative_to(self.root)), image(kind=6,
                dependencies=[(0xC, str(paths["Shared"]))], rpaths=[str(paths["first"])]))
        self.write(str(paths["Shared"].relative_to(self.root)), image(kind=6,
            dependencies=[(native.WEAK if weak else 0xC, "@rpath/Choice.dylib")]))
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(paths[name])) for name in ("A", "B")]))
        return host, paths

    def test_shared_branching_dag_qualifies_without_raising_native_limits(self):
        host, nodes = self.shared_dag()
        proof = host.closure(include_build=False)
        for level, row in enumerate(nodes):
            expected = ({str(path) for path in nodes[level + 1]} if level + 1 < len(nodes) else
                        {f"/usr/lib/libSynthetic{index}.dylib" for index in range(16)})
            for path in row:
                self.assertIn(str(path), proof["entries"])
                self.assertEqual({target for edge in proof["edges"][str(path)] for target in edge["targets"]}, expected)
        self.assertEqual(native.MAX_EDGES, 16384)
        self.assertEqual(native.MAX_CONTEXTS, 4096)
        native.validate_work(host.closure_work)
        self.assertGreater(host.closure_work["memo_hits"], 0)
        self.assertLess(host.closure_work["resolved_edges"], 200)

    def test_completed_reuse_matches_complete_small_reference_without_fingerprint_normalization(self):
        host, _nodes = self.shared_dag(levels=3, width=3, leaf_count=4)
        reused = host.closure(include_build=False)
        work = dict(host.closure_work)
        with patch.object(native.RuntimeClosure, "inherited_matches", return_value=False):
            reference = host.closure(include_build=False)
        self.assertEqual(host.closure_work["memo_hits"], 0)
        self.assertGreater(host.closure_work["resolved_edges"], work["resolved_edges"])
        native.same_native_fingerprint(reference, reused)

    def test_shared_subtree_reuses_only_consulted_prefix_without_expanding_unused_ancestor_suffix(self):
        host, paths = self.shared_rpath_layout()
        chosen = self.write(str((paths["first"] / "Choice.dylib").relative_to(self.root)), image(kind=6))
        for name in ("A", "B"):
            paths[name].write_bytes(image(kind=6, dependencies=[(0xC, str(paths["Shared"]))],
                rpaths=[str(paths["first"]), f"@unknown/unused-{name}"]))
        with patch.object(native.RuntimeClosure, "expanded", wraps=native.RuntimeClosure(host).expanded) as expanded:
            proof = host.closure(include_build=False)
        self.assertFalse(any(str(call.args[0]).startswith("@unknown") for call in expanded.call_args_list))
        self.assertGreater(host.closure_work["memo_hits"], 0)
        edges = proof["edges"][str(paths["Shared"])]
        self.assertEqual(len(edges), 1)
        self.assertEqual(edges[0]["targets"], [str(chosen)])
        self.assertEqual(edges[0]["context"]["rpaths"], [str(paths["first"])])

    def test_shared_subtree_changed_order_rechecks_late_binding_and_refuses_conflicting_target(self):
        host, paths = self.shared_rpath_layout()
        for root in (paths["first"], paths["second"]):
            self.write(str((root / "Choice.dylib").relative_to(self.root)), image(kind=6))
        paths["A"].write_bytes(image(kind=6, dependencies=[(0xC, str(paths["Shared"]))],
                                     rpaths=[str(paths["first"]), str(paths["second"])]))
        paths["B"].write_bytes(image(kind=6, dependencies=[(0xC, str(paths["Shared"]))],
                                     rpaths=[str(paths["second"]), str(paths["first"])]))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "binding-order-unproven") as error:
            host.closure(include_build=False)
        self.assertEqual(error.exception.diagnostic["chain"][1]["path"], "<xcode>/SharedFrameworks/B.dylib")
        self.assertEqual(len({item["sha256"] for item in error.exception.diagnostic["candidates"] if item["sha256"]}), 1)
        self.assertEqual({item["canonical"] for item in error.exception.diagnostic["candidates"] if item["sha256"]}, {
            "<xcode>/SharedFrameworks/first/Choice.dylib", "<xcode>/SharedFrameworks/second/Choice.dylib"})

    def test_exhausted_weak_lookup_requires_full_inherited_stream_and_preserves_changed_absence(self):
        host, paths = self.shared_rpath_layout(weak=True)
        paths["B"].write_bytes(image(kind=6, dependencies=[(0xC, str(paths["Shared"]))],
                                     rpaths=[str(paths["first"]), str(paths["second"])]))
        proof = host.closure(include_build=False)
        edges = proof["edges"][str(paths["Shared"])]
        self.assertEqual(len(edges), 2)
        self.assertTrue(all(edge["targets"] == [] for edge in edges))
        self.assertEqual({tuple(edge["context"]["rpaths"]) for edge in edges}, {
            (str(paths["first"]),), (str(paths["first"]), str(paths["second"]))})
        self.write(str((paths["second"] / "Choice.dylib").relative_to(self.root)), image(kind=6))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "binding-order-unproven"):
            host.closure(include_build=False)

    def test_cycle_support_includes_blocked_variants_before_completed_subtree_reuse(self):
        host, paths = self.shared_rpath_layout()
        for root in (paths["first"], paths["second"]):
            self.write(str((root / "Choice.dylib").relative_to(self.root)), image(kind=6))
        paths["Shared"].write_bytes(image(kind=6, dependencies=[(0xC, str(paths["A"]))],
                                          rpaths=[str(paths["second"])]))
        paths["A"].write_bytes(image(kind=6, dependencies=[(0xC, str(paths["Shared"])), (0xC, "@rpath/Choice.dylib")]))
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(paths[name])) for name in ("A", "B")],
                                                rpaths=[str(paths["first"])]))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "binding-order-unproven") as error:
            host.closure(include_build=False)
        self.assertEqual([item["path"] for item in error.exception.diagnostic["chain"][:3]], [
            "<xcode>/SharedFrameworks/A.dylib", "<xcode>/SharedFrameworks/Shared.dylib", "<xcode>/SharedFrameworks/B.dylib"])

    def test_completed_subtree_cannot_bypass_chain_budget_at_a_deeper_call(self):
        host = self.host()
        shared = self.write("Xcode.app/Contents/Shared.dylib", image(kind=6,
            dependencies=[(0xC, "@loader_path/Leaf.dylib")]))
        self.write("Xcode.app/Contents/Leaf.dylib", image(kind=6))
        prior = shared
        for index in range(4):
            prior = self.write(f"Xcode.app/Contents/Deep{index}.dylib", image(kind=6, dependencies=[(0xC, str(prior))]))
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(shared)), (0xC, str(prior))]))
        with patch.object(native, "MAX_CHAIN", 6), self.assertRaisesRegex(native.UnsupportedRuntime, "chain-budget"):
            host.closure(include_build=False)

    def test_root_variants_keep_separate_memos_binding_maps_and_explicit_process_identity(self):
        host, nodes = self.shared_dag(levels=2, width=2, leaf_count=2)
        dependencies = [(0xC, str(path)) for path in nodes[0]]
        host.tools["xctest"].write_bytes(universal([
            (native.ARM64, 0, image(dependencies=dependencies)),
            (native.ARM64, 0x80000002, image(subtype=0x80000002, dependencies=dependencies))]))
        proof = host.closure(include_build=False)
        for path in nodes[1]:
            self.assertEqual({edge["context"]["process"]["subtype"] for edge in proof["edges"][str(path)]},
                             {0, 0x80000002})
        self.assertEqual(host.closure_work["processes"], 5)
        self.assertGreater(host.closure_work["memo_hits"], 0)

    def test_work_counters_are_closed_bounded_non_fingerprint_observations(self):
        host, _nodes = self.shared_dag(levels=2, width=2, leaf_count=2)
        proof = host.closure(include_build=False)
        self.assertIs(native.validate_work(host.closure_work), host.closure_work)
        self.assertNotIn("work", proof)
        self.assertNotIn("work", proof["context"])
        for key, value in (("memo_hits", True), ("resolved_edges", native.MAX_EDGES + 2),
                           ("memo_misses", native.MAX_CONTEXTS + 2), ("command", "untrusted")):
            with self.subTest(key=key), self.assertRaisesRegex(native.UnsupportedRuntime, "work-counters"):
                native.validate_work({**host.closure_work, key:value})

    def test_collection_deadline_remains_enforced_after_completed_memoized_work(self):
        host, _nodes = self.shared_dag(levels=2, width=2, leaf_count=2)
        host.tools = {"xctest":host.tools["xctest"]}
        launch = native.RuntimeClosure.launch
        def deadline(collector, *args, **kwargs):
            launch(collector, *args, **kwargs)
            host.budget.started = time.monotonic() - native.MAX_SECONDS
        with patch.object(native.RuntimeClosure, "launch", deadline), \
                self.assertRaisesRegex(native.UnsupportedRuntime, "time-budget"):
            host.closure(include_build=False)
        self.assertGreater(host.closure_work["memo_hits"], 0)

    def products(self):
        self.write("workspace/.build/ExampleTests.xctest/Contents/MacOS/ExampleTests", image(
            kind=8, dependencies=[(0xC, "@rpath/Sparkle.framework/Versions/B/Sparkle"),
                                  (0xC, "@rpath/Testing.framework/Versions/A/Testing")],
            rpaths=["@loader_path/../../../"]))
        self.write("workspace/.build/Sparkle.framework/Versions/B/Sparkle",
                   image(kind=6, dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        self.write("Xcode.app/Contents/Developer/Library/Frameworks/Testing.framework/Versions/A/Testing",
                   image(kind=6, dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))

    def test_load_commands_include_weak_reexports_upward_dylinker_and_rpaths(self):
        parsed = self.parse(image(kind=8, dependencies=[
            (0xC, "/usr/lib/libSystem.B.dylib"), (native.WEAK, "@rpath/Optional.dylib"),
            (0x8000001F, "@rpath/Reexport.dylib"), (0x80000023, "@rpath/Upward.dylib"),
            (0xE, "/usr/lib/dyld")], rpaths=["@loader_path/../Frameworks"]))
        self.assertEqual(parsed["kind"], 8)
        self.assertEqual({item["path"]:item["weak"] for item in parsed["dependencies"]}, {
            "/usr/lib/libSystem.B.dylib":False, "@rpath/Optional.dylib":True,
            "@rpath/Reexport.dylib":False, "@rpath/Upward.dylib":False, "/usr/lib/dyld":False})
        self.assertEqual(parsed["rpaths"], ["@loader_path/../Frameworks"])

    def test_fat32_and_fat64_select_bounded_arm64_slice(self):
        for wide in (False, True):
            with self.subTest(wide=wide):
                payload = image()
                fat = struct.pack(">II", 0xCAFEBABF if wide else 0xCAFEBABE, 1)
                fat += struct.pack(">IIQQII" if wide else ">IIIII", native.ARM64, 0, 64, len(payload), 0,
                                   *([0] if wide else []))
                fat += bytes(64 - len(fat)) + payload
                self.assertEqual(self.parse(fat)["kind"], 2)
        with self.assertRaisesRegex(native.UnsupportedRuntime, "fat"):
            self.parse(struct.pack(">II", 0xCAFEBABE, 33))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "fat"):
            self.parse(struct.pack(">II", 0xCAFEBABE, 1) + struct.pack(">IIIII", native.ARM64, 0, 500, 64, 0))

    def test_distinct_arm64_variants_keep_all_dependencies_rpaths_and_full_abi(self):
        for wide in (False, True):
            for alternate in (1, 2, 0x80000002):
                # A declared fat32 old arm64e subtype is normalized by Apple's loader.
                actual = 0x80000002 if alternate == 2 and not wide else alternate
                first = image(dependencies=[(native.WEAK, "@rpath/Shared.dylib")], rpaths=["@loader_path/A"])
                second = image(subtype=actual, dependencies=[(0xC, "@rpath/Shared.dylib"),
                               (0x8000001F, "@rpath/Alternate.dylib")], rpaths=["@loader_path/B"])
                with self.subTest(wide=wide, alternate=alternate):
                    parsed = self.parse(universal([(native.ARM64, 0, first),
                                                   (native.ARM64, alternate, second)], wide=wide))
                    self.assertEqual(parsed["subtypes"], [0, actual])
                    self.assertEqual(parsed["dependencies"], [{"path":"@rpath/Alternate.dylib", "weak":False},
                                                              {"path":"@rpath/Shared.dylib", "weak":False}])
                    self.assertEqual(parsed["rpaths"], ["@loader_path/A", "@loader_path/B"])

    def test_legacy_hidden_generic_arm64_descriptor_is_covered_and_bounded(self):
        slices = [(0x1000007, 3, image(cpu=0x1000007, subtype=3)),
                  (native.ARM64, 0x80000002, image(subtype=0x80000002)),
                  (native.ARM64, 0, image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))]
        encoded = universal(slices, hidden=True)
        parsed = self.parse(encoded)
        self.assertEqual(parsed["subtypes"], [0, 0x80000002])
        self.assertEqual(parsed["dependencies"], [{"path":"/usr/lib/libSystem.B.dylib", "weak":False}])
        invalid = bytearray(encoded)
        struct.pack_into(">I", invalid, 8 + 2 * 20 + 8, len(encoded))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-fat-slice") as error:
            self.parse(invalid)
        self.assertTrue(error.exception.diagnostic["fat_slices"][-1]["hidden"])
        overlapping = bytearray(encoded)
        struct.pack_into(">I", overlapping, 8 + 8, 64)
        with self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-fat-slice") as error:
            self.parse(overlapping)
        self.assertTrue(error.exception.diagnostic["fat_slices"][-1]["hidden"])
        # FAT64 has no legacy descriptor interpretation.
        with self.assertRaisesRegex(native.UnsupportedRuntime, "no-arm64"):
            self.parse(universal([slices[0], slices[-1]], wide=True, hidden=True))

    def test_observed_sparkle_and_dsym_fat_layouts_remain_classified_correctly(self):
        # Exact FAT descriptors from artifact 12573057357. Synthetic loadable
        # headers exercise layout only; no downloaded native code is executed.
        cases = [(
            "cafebabe00000002010000070000000300004000000778e00000000e"
            "0100000c000000000007c00000072ad00000000e", 977616, 6), (
            "cafebabe0000000201000007000000030000004000051c6a00000005"
            "0100000c0000000000051cc00004f65300000005", 660243, 10)]
        for table_hex, size, kind in cases:
            content = bytearray(size)
            table = bytes.fromhex(table_hex)
            content[:len(table)] = table
            for index in range(2):
                cpu, subtype, offset, length, alignment = struct.unpack_from(">5I", table, 8 + index * 20)
                header = image(kind=kind, cpu=cpu, subtype=subtype)
                content[offset:offset + len(header)] = header
            with self.subTest(kind=kind):
                parsed = self.parse(content)
                if kind == 10:
                    self.assertIsNone(parsed)
                else:
                    self.assertEqual((parsed["kind"], parsed["subtypes"]), (6, [0]))

    def test_fat_duplicates_mismatches_overlap_alignment_bounds_and_abi_are_rejected(self):
        valid = universal([(native.ARM64, 0, image()),
                           (native.ARM64, 0x80000002, image(subtype=0x80000002))])
        cases = []
        for offset, value, reason in ((8 + 20 + 8, 64, "overlapping"), (8 + 8, 0, "invalid-fat-slice"),
                                      (8 + 12, len(valid), "invalid-fat-slice"),
                                      (8 + 16, 63, "invalid-fat-slice"),
                                      (8 + 20 + 4, 0, "duplicate")):
            candidate = bytearray(valid)
            struct.pack_into(">I", candidate, offset, value)
            cases.append((candidate, reason))
        cases += [(universal([(native.ARM64, 0, image(subtype=1))]), "architecture-mismatch"),
                  (universal([(native.ARM64, 0, image(cpu=0x1000007, subtype=3))]), "architecture-mismatch"),
                  (universal([(native.ARM64, 2, image(subtype=0x80000002)),
                              (native.ARM64, 0x80000002, image(subtype=0x80000002))]), "duplicate")]
        for subtype in (0x81000002, 0xC0000002, 0x80000000, 3):
            cases.append((universal([(native.ARM64, 0, image()),
                                     (native.ARM64, subtype, image(subtype=subtype))]), "subtype-abi"))
        reserved = bytearray(universal([(native.ARM64, 0, image())], wide=True))
        struct.pack_into(">I", reserved, 8 + 28, 1)
        cases.append((reserved, "reserved"))
        for candidate, reason in cases:
            with self.subTest(reason=reason), self.assertRaisesRegex(native.UnsupportedRuntime, reason):
                self.parse(candidate)

    def test_nonloadable_archives_debug_and_objects_are_distinct_from_foreign_loadable_images(self):
        for kind in (1, 4, 9, 10):
            with self.subTest(kind=kind):
                self.assertIsNone(self.parse(universal([(0x1000007, 3, image(kind=kind, cpu=0x1000007, subtype=3)),
                                                       (native.ARM64, 0, image(kind=kind))])))
        self.assertIsNone(self.parse(universal([(0x1000007, 3, b"!<arch>\n"),
                                               (native.ARM64, 0, b"!<arch>\n")])))
        for candidate, reason in ((image(cpu=0x1000007, subtype=3), "no-arm64"),
                                  (universal([(0x1000007, 3, image(cpu=0x1000007, subtype=3))]), "no-arm64"),
                                  (universal([(0x1000007, 3, b"!<arch>\n"),
                                              (native.ARM64, 0, image())]), "mixed-fat"),
                                  (universal([(0x1000007, 3, image(kind=10, cpu=0x1000007, subtype=3)),
                                              (native.ARM64, 0, image())]), "mixed-fat")):
            with self.subTest(reason=reason), self.assertRaisesRegex(native.UnsupportedRuntime, reason):
                self.parse(candidate)

    def test_aggregate_arm64_variant_command_budget_cannot_be_multiplied(self):
        candidate = universal([(native.ARM64, subtype, image(subtype=subtype,
                              dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")])) for subtype in (0, 1)])
        for key, value in (("MAX_COMMANDS", 1), ("MAX_COMMAND_BYTES", 64)):
            with self.subTest(key=key), patch.object(native, key, value), \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "command-budget"):
                self.parse(candidate)

    def test_unsupported_file_diagnostics_are_bounded_and_identify_exact_inspected_layout(self):
        candidate = universal([(native.ARM64, 0, image()),
                               (native.ARM64, 0x81000002, image(subtype=0x81000002))])
        with self.assertRaisesRegex(native.UnsupportedRuntime, "subtype-abi") as error:
            self.parse(candidate)
        diagnostic = error.exception.diagnostic
        self.assertEqual(diagnostic["path"], str(self.root / "candidate"))
        self.assertEqual(diagnostic["file_bytes"], len(candidate))
        self.assertEqual(diagnostic["header_sha256"], hashlib.sha256(candidate[:48]).hexdigest())
        self.assertEqual([item["subtype"] for item in diagnostic["fat_slices"]], [0, 0x81000002])
        self.assertEqual(native.validate_diagnostic(diagnostic), diagnostic)
        for field, value in (("path", "x" * 513), ("path", "bad\n::error::injected"),
                             ("file_bytes", True), ("header_sha256", "x" * 64),
                             ("fat_slices", diagnostic["fat_slices"] * 17),
                             ("fat_slices", [{**diagnostic["fat_slices"][0], "command":"untrusted"}])):
            with self.subTest(field=field), self.assertRaisesRegex(native.UnsupportedRuntime, "diagnostic"):
                native.validate_diagnostic({**diagnostic, field:value})
        with self.assertRaisesRegex(native.UnsupportedRuntime, "diagnostic"):
            native.validate_diagnostic({**diagnostic, "command":"untrusted"})

    def test_malformed_commands_paths_byte_order_and_injected_environment_are_rejected(self):
        original = image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")])
        bad_offset = bytearray(original)
        struct.pack_into("<I", bad_offset, 40, 4)
        bad_utf8 = original.replace(b"/usr", b"\xffusr")
        unterminated = original[:56] + original[56:].replace(b"\0", b"X")
        cases = [original[:20], original[:-1], bytes(bad_offset), bad_utf8, unterminated,
                 image(commands=[struct.pack("<II", 0x8000007F, 8)]),
                 image(commands=[path_command(0x27, "DYLD_LIBRARY_PATH=/untrusted")]),
                 b"\xfe\xed\xfa\xcf" + bytes(28)]
        for candidate in cases:
            with self.subTest(candidate=candidate[:40]), self.assertRaises(native.UnsupportedRuntime):
                self.parse(candidate)
        self.assertIsNone(self.parse(b"plain resource bytes"))
        self.assertIsNone(self.parse(image(kind=1)))

    def test_real_closure_covers_all_transferred_images_helpers_and_external_dependencies(self):
        self.products()
        self.write("workspace/.build/tools/extra-helper", image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        fingerprint = self.host().closure()
        self.assertIn(str(self.build / "tools/extra-helper"), fingerprint["entries"])
        self.assertIn("/usr/lib/libSystem.B.dylib", fingerprint["entries"])
        self.assertIn(str(self.frameworks / "Testing.framework/Versions/A/Testing"), fingerprint["entries"])
        self.assertEqual(fingerprint["entries"]["/usr/lib/libSystem.B.dylib"], {"kind":"system-cache"})
        self.assertEqual(self.api_calls.count("/usr/lib/libSystem.B.dylib"), 1)
        native.same_native_fingerprint(fingerprint, fingerprint)

    def test_closure_covers_both_variant_dependencies_and_cannot_hide_missing_or_changed_alternate(self):
        self.products()
        helper = self.write("workspace/.build/fat-helper", universal([
            (native.ARM64, 0, image(dependencies=[(0xC, "@loader_path/Generic.dylib")])),
            (native.ARM64, 0x80000002, image(subtype=0x80000002,
                                           dependencies=[(0xC, "@loader_path/Alternate.dylib")]))]))
        generic = self.write("workspace/.build/Generic.dylib", image(kind=6))
        alternate = self.write("workspace/.build/Alternate.dylib", image(kind=6, subtype=0x80000002))
        original = self.host().closure()
        self.assertEqual(original["entries"][str(helper)]["subtypes"], [0, 0x80000002])
        self.assertEqual({target for edge in original["edges"][str(helper)] for target in edge["targets"]},
                         {str(generic), str(alternate)})
        alternate.write_bytes(alternate.read_bytes() + b"different alternate bytes")
        with self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
            native.same_native_fingerprint(original, self.host().closure())
        alternate.unlink()
        with self.assertRaisesRegex(native.UnsupportedRuntime, "unresolved"):
            self.host().closure()

    def test_external_native_file_failure_keeps_exact_path_and_fat_inventory(self):
        self.products()
        external = self.write("Xcode.app/Contents/Developer/Library/Frameworks/Testing.framework/Versions/A/Testing",
                              universal([(native.ARM64, 0, image(kind=6)),
                                         (native.ARM64, 0xC0000002, image(kind=6, subtype=0xC0000002))]))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "subtype-abi") as error:
            self.host().closure()
        diagnostic = error.exception.diagnostic
        self.assertEqual(diagnostic["loader"], "<build>/ExampleTests.xctest/Contents/MacOS/ExampleTests")
        self.assertEqual(diagnostic["file"]["path"], "<xcode>/" + str(external.relative_to(self.xcode)))
        self.assertEqual([item["subtype"] for item in diagnostic["file"]["fat_slices"]], [0, 0xC0000002])
        self.assertEqual(diagnostic["candidates"][-1]["sha256"], hashlib.sha256(external.read_bytes()).hexdigest())

    def test_staged_closure_uses_original_logical_paths_without_installing_build(self):
        self.products()
        self.write("workspace/.build/Optional.dylib", image(kind=6,
            dependencies=[(native.WEAK, "@loader_path/Absent.dylib")]))
        producer = self.host().closure()
        stage = self.root / "stage/.build"
        shutil.copytree(self.build, stage, symlinks=True)
        shutil.rmtree(self.build)
        worker = self.host(stage).closure()
        self.assertFalse(self.build.exists())
        native.same_native_fingerprint(producer, worker)

    def test_recursive_cycles_terminate_and_weak_absence_is_recorded(self):
        self.products()
        self.write("workspace/.build/A.dylib", image(kind=6, dependencies=[(0xC, "@loader_path/B.dylib")]))
        self.write("workspace/.build/B.dylib", image(kind=6, dependencies=[
            (0xC, "@loader_path/A.dylib"), (native.WEAK, "@loader_path/Absent.dylib")]))
        fingerprint = self.host().closure()
        missing = [edge for edge in fingerprint["edges"][str(self.build / "B.dylib")] if not edge["targets"]]
        self.assertEqual([{key:edge[key] for key in ("install_name", "weak", "targets")} for edge in missing],
                         [{"install_name":"@loader_path/Absent.dylib", "weak":True, "targets":[]}])
        self.assertEqual(missing[0]["context"]["mode"], "audit")
        self.assertTrue(all(item["cache_absent"] for item in missing[0]["absence"]))
        self.assertEqual(missing[0]["absence"][-1]["canonical"], str(self.build / "Absent.dylib"))

    def test_unresolved_strong_outside_root_and_escaping_symlink_are_incomplete(self):
        self.products()
        path = self.build / "bad"
        cases = [("@loader_path/Absent.dylib", "unresolved"),
                 ("@rpath//usr/lib/libSystem.B.dylib", "unsafe-rpath"),
                 ("@rpath/../libSystem.B.dylib", "unsafe-rpath"),
                 ("/opt/homebrew/lib/unreviewed.dylib", "outside"), ("@unknown/Bad.dylib", "token")]
        for dependency, reason in cases:
            path.write_bytes(image(dependencies=[(0xC, dependency)]))
            with self.subTest(dependency=dependency), self.assertRaisesRegex(native.UnsupportedRuntime, reason):
                self.host().closure()
        path.unlink()
        target = self.write("outside", b"must not hash or load")
        link = self.frameworks / "Escaping.dylib"
        link.symlink_to(target)
        with self.assertRaisesRegex(native.UnsupportedRuntime, "escapes"):
            self.host().location(link)

    def test_changes_to_runtime_bytes_os_build_sdk_toolchain_or_cache_never_match(self):
        self.products()
        original = self.host().closure()
        for key in ("os_build", "sdk_build", "arch", "system_cache_uuid", "tools"):
            changed = json.loads(json.dumps(original))
            changed["context"][key] = "different"
            with self.subTest(key=key), self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
                native.same_native_fingerprint(original, changed)
        path = self.frameworks / "Testing.framework/Versions/A/Testing"
        path.write_bytes(path.read_bytes() + b"changed library bytes")
        with self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
            native.same_native_fingerprint(original, self.host().closure())
        with self.assertRaisesRegex(native.UnsupportedRuntime, "incomplete"):
            native.same_native_fingerprint(original, {"status":"unsupported"})

    def test_scan_hash_image_cache_and_time_budgets_are_bounded(self):
        self.products()
        for key, value in (("MAX_SCAN_ENTRIES", 1), ("MAX_IMAGES", 1), ("MAX_HASH_BYTES", 1), ("MAX_QUERIES", 0)):
            with self.subTest(key=key), patch.object(native, key, value), self.assertRaises(native.UnsupportedRuntime):
                self.host().closure()
        host = self.host()
        host.budget.started = time.monotonic() - native.MAX_SECONDS
        with self.assertRaisesRegex(native.UnsupportedRuntime, "time-budget"):
            host.closure()

    def test_loader_and_toolchain_overrides_are_rejected_before_native_queries(self):
        for key in ("DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "TOOLCHAINS", "SDKROOT", "SWIFT_EXEC",
                    "SWIFT_EXEC_MANIFEST", "SWIFTPM_CUSTOM_LIBS_DIR", "SWIFTPM_PD_LIBS", "SWIFTPM_CUSTOM_BINDIR",
                    "SWIFTPM_PLATFORM_PATH_macosx"):
            with self.subTest(key=key), patch.object(native, "SystemCache") as system, \
                    self.assertRaisesRegex(ValueError, "override"):
                native.Host(self.workspace, self.build, {key:"untrusted"}, None)
            system.assert_not_called()
        native.validate_environment({"DEVELOPER_DIR":"/Applications/Xcode.app/Contents/Developer"})

    def test_executable_relative_rpath_resolves_inside_the_selected_runtime(self):
        self.products()
        self.write("workspace/.build/bin/helper", image(dependencies=[(0xC, "@rpath/Helper.dylib")],
                   rpaths=["@executable_path/../lib"]))
        target = self.write("workspace/.build/lib/Helper.dylib", image(kind=6))
        fingerprint = self.host().closure()
        self.assertIn(str(target), fingerprint["entries"])

    def test_separate_launches_do_not_share_rpaths_or_install_name_bindings(self):
        self.products()
        helpers = []
        for directory in ("First", "Second"):
            helper = self.write(f"workspace/.build/{directory}/helper", image(
                dependencies=[(0xC, "@rpath/Shared.dylib")], rpaths=["@loader_path/lib"]))
            target = self.write(f"workspace/.build/{directory}/lib/Shared.dylib",
                                image(kind=6) + directory.encode())
            helpers.append((helper, target))
        fingerprint = self.host().closure()
        for helper, target in helpers:
            edges = fingerprint["edges"][str(helper)]
            self.assertEqual({edge["context"]["mode"] for edge in edges}, {"plain", "swiftpm-test"})
            self.assertEqual({tuple(edge["targets"]) for edge in edges}, {(str(target),)})
            self.assertTrue(all(edge["context"]["executable"] == str(helper) for edge in edges))

    def test_separate_test_bundle_processes_do_not_share_loaded_name_bindings(self):
        self.products()
        expected = {}
        for name in ("FirstTests", "SecondTests"):
            test = self.write(f"workspace/.build/{name}.xctest/Contents/MacOS/{name}", image(
                kind=8, dependencies=[(0xC, "@rpath/Shared.dylib")], rpaths=["@loader_path/lib"]))
            target = self.write(f"workspace/.build/{name}.xctest/Contents/MacOS/lib/Shared.dylib",
                                image(kind=6) + name.encode())
            expected[str(test)] = str(target)
        fingerprint = self.host().closure()
        for test, target in expected.items():
            self.assertEqual({tuple(edge["targets"]) for edge in fingerprint["edges"][test]}, {(target,)})
            self.assertEqual({Path(edge["context"]["executable"]).name for edge in fingerprint["edges"][test]},
                             {"xctest", "swiftpm-xctest-helper", "swiftpm-testing-helper"})
            self.assertTrue(all(edge["context"]["process"]["test_bundle"] == test
                                for edge in fingerprint["edges"][test]))

    def test_selected_test_launchers_use_only_swiftpm_environment_without_invented_plain_launch(self):
        self.products()
        host = self.host()
        raw = "/Library/Developer/PrivateFrameworks/OverrideOnly.framework/Versions/A/OverrideOnly"
        framework = self.write("Xcode.app/Contents/Developer/Library/PrivateFrameworks/OverrideOnly.framework/Versions/A/OverrideOnly",
                               image(kind=6, dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        for name in ("xctest", "swiftpm-xctest-helper", "swiftpm-testing-helper"):
            host.tools[name].write_bytes(image(dependencies=[(0xC, raw)]))
        fingerprint = host.closure()
        for name in ("xctest", "swiftpm-xctest-helper", "swiftpm-testing-helper"):
            edges = fingerprint["edges"][str(host.tools[name])]
            self.assertEqual({edge["context"]["mode"] for edge in edges}, {"swiftpm-test"})
            self.assertEqual({tuple(edge["targets"]) for edge in edges}, {(str(framework),)})
        self.assertEqual({edge["context"]["mode"]
                          for edge in fingerprint["edges"][str(host.tools["swift-package"])]}, {"plain"})
        self.assertNotIn(raw, fingerprint["entries"])

    def test_developer_framework_closure_hashes_only_reached_nested_runtime_and_rejects_changes(self):
        self.products()
        for public in native.APPLE_RUNTIME_FRAMEWORKS:
            with self.subTest(root=public.name):
                host = self.host()
                root = self.root / public.relative_to("/")
                nested = self.write(str((root / "Versions/A/Frameworks/Nested.framework/Versions/A/Nested").relative_to(self.root)),
                                    image(kind=6, dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
                core = self.write(str((root / "Versions/A" / public.stem).relative_to(self.root)), image(kind=6,
                    dependencies=[(0xC, "@loader_path/Frameworks/Nested.framework/Versions/A/Nested")]))
                unused = self.write(str((root / "unused.dylib").relative_to(self.root)), b"not a runtime image")
                host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(core))]))
                with patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", (root,)):
                    original = host.closure()
                    self.assertEqual(original["entries"][str(core)]["kind"], "developer-framework")
                    self.assertEqual(original["entries"][str(nested)]["sha256"], hashlib.sha256(nested.read_bytes()).hexdigest())
                    self.assertNotIn(str(unused), original["entries"])
                    nested.write_bytes(nested.read_bytes() + b"changed nested runtime")
                    changed = host.closure()
                    self.assertEqual(original["entries"][str(core)], changed["entries"][str(core)])
                    self.assertNotEqual(original["entries"][str(nested)], changed["entries"][str(nested)])
                    with self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
                        native.same_native_fingerprint(original, changed)
                    sibling = root.with_name("Unreviewed.framework") / "Versions/A/Unreviewed"
                    host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(sibling))]))
                    with patch.object(host, "location", wraps=host.location) as location, \
                            self.assertRaisesRegex(native.UnsupportedRuntime, "outside-approved-roots"):
                        host.closure(include_build=False)
                    self.assertFalse(any(call.args[0] == sibling for call in location.call_args_list))

    def test_developer_framework_root_and_nested_symlink_escapes_are_rejected_before_hashing(self):
        host = self.host()
        real = self.write("Library/Developer/PrivateFrameworks/Real.framework/Versions/A/CoreDevice", image(kind=6))
        for public in native.APPLE_RUNTIME_FRAMEWORKS:
            with self.subTest(root=public.name):
                root = self.root / public.relative_to("/")
                root.parent.mkdir(parents=True, exist_ok=True)
                root.symlink_to(real.parents[2], target_is_directory=True)
                with patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", (root,)), \
                        self.assertRaisesRegex(native.UnsupportedRuntime, "noncanonical-developer-framework-root"):
                    host.location(root / "Versions/A" / public.stem)
                root.unlink()
                root.mkdir()
                (root / "Escape.dylib").symlink_to(real)
                with patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", (root,)), \
                        self.assertRaisesRegex(native.UnsupportedRuntime, "runtime-symlink-escapes-root"):
                    host.location(root / "Escape.dylib")

    def test_coredevice_utilities_edge_preserves_arm64e_and_requires_explicit_second_root(self):
        host = self.host()
        fixture_roots = tuple(self.root / path.relative_to("/") for path in native.APPLE_RUNTIME_FRAMEWORKS)
        utility = self.write("Library/Developer/PrivateFrameworks/CoreDeviceUtilities.framework/Versions/A/CoreDeviceUtilities",
                             image(kind=6, subtype=0x80000002))
        core = self.write("Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/CoreDevice", image(
            kind=6, subtype=0x80000002, dependencies=[(0xC, str(utility))]))
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(core))]))
        with patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", fixture_roots):
            fingerprint = host.closure(include_build=False)
        self.assertEqual(fingerprint["entries"][str(utility)]["subtypes"], [0x80000002])
        self.assertEqual({tuple(edge["targets"]) for edge in fingerprint["edges"][str(core)]}, {(str(utility),)})

    def test_mercury_shared_arm64e_import_requires_exact_apple_system_root(self):
        host = self.host()
        fixture_roots = tuple(self.root / path.relative_to("/") for path in native.APPLE_RUNTIME_FRAMEWORKS)
        mercury = self.write("Library/Apple/System/Library/PrivateFrameworks/Mercury.framework/Versions/A/Mercury",
                             image(kind=6, subtype=0x80000002, dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        utility = self.write("Library/Developer/PrivateFrameworks/CoreDeviceUtilities.framework/Versions/A/CoreDeviceUtilities",
                             image(kind=6, subtype=0x80000002, dependencies=[(0xC, str(mercury))]))
        core = self.write("Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/CoreDevice", image(
            kind=6, subtype=0x80000002, dependencies=[(0xC, str(utility)), (0xC, str(mercury))]))
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(core))]))
        with patch.object(native, "APPLE_RUNTIME_FRAMEWORKS", fixture_roots):
            fingerprint = host.closure(include_build=False)
            self.assertEqual(fingerprint["entries"][str(mercury)], {
                "kind":"developer-framework", "sha256":hashlib.sha256(mercury.read_bytes()).hexdigest(),
                "subtypes":[0x80000002]})
            for loader in (core, utility):
                self.assertIn((str(mercury),), {tuple(edge["targets"]) for edge in fingerprint["edges"][str(loader)]})
            incorrect = self.root / "Library/Developer/PrivateFrameworks/Mercury.framework/Versions/A/Mercury"
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(incorrect))]))
            with patch.object(host, "location", wraps=host.location) as location, \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "outside-approved-roots"):
                host.closure(include_build=False)
            self.assertFalse(any(call.args[0] == incorrect for call in location.call_args_list))

    def test_reviewed_mobiledevice_weak_paths_are_exact_observed_declarations(self):
        framework = Path("/Library/Apple/System/Library/PrivateFrameworks/DeviceInterface.framework")
        extension = Path("/Library/Apple/usr/appleinternal/lib/libMobileRestoreInternalExtensions.dylib")
        self.assertIn(framework, native.APPLE_RUNTIME_FRAMEWORKS)
        self.assertEqual(native.APPLE_RUNTIME_FILES, (extension,))
        for path, digest in ((framework / "Versions/A/DeviceInterface",
                "007b89b1d29ed72a2fb9a48c74264545f343b4172db93cacb128c3be46822adb"),
                (extension, "7b64426e60ed950a9c11fbc008a2006774e7371e561d7d2d2d4ffa9b1e90c4f2")):
            self.assertEqual(hashlib.sha256(os.fsencode(path)).hexdigest(), digest)
        self.assertEqual(len(native.APPLE_FRAMEWORK_ALIASES), 1)

    def test_observed_mobiledevice_weak_imports_require_both_exact_boundaries_and_recursive_hashes(self):
        layout = self.weak_mobiledevice_layout()
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            context = json.loads(json.dumps(host.context))
            # Forged cache hits cannot skip actual external file identities.
            host.cache_membership.update({str(layout[key]):True for key in ("device", "extension")})
            with patch.object(Path, "iterdir", side_effect=AssertionError("no framework inventory")):
                original = host.closure(include_build=False)
            self.assertEqual(host.context, context)
            for key, kind in (("device", "developer-framework"), ("extension", "apple-runtime-file")):
                self.assertEqual(original["entries"][str(layout[key])], {"kind":kind, "subtypes":[0x80000002],
                    "sha256":hashlib.sha256(layout[key].read_bytes()).hexdigest()})
            edges = original["edges"][str(layout["binary"])]
            self.assertEqual({tuple(edge["targets"]) for edge in edges},
                             {(str(layout["device"]),), (str(layout["extension"]),)})
            self.assertTrue(all(edge["weak"] for edge in edges))
            self.assertIn(str(layout["device_nested"]), original["entries"])
            for key in ("device_nested", "extension"):
                layout[key].write_bytes(layout[key].read_bytes() + b"changed reached dependency")
                changed = host.closure(include_build=False)
                with self.assertRaisesRegex(native.UnsupportedRuntime, "fingerprint-differs"):
                    native.same_native_fingerprint(original, changed)

    def test_both_absent_weak_imports_require_negative_exact_cache_queries_without_target_reads(self):
        layout = self.weak_mobiledevice_layout(present=(False, False))
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            with patch.object(host.budget, "digest", wraps=host.budget.digest) as digest:
                absent = host.closure(include_build=False)
            edges = absent["edges"][str(layout["binary"])]
            self.assertTrue(all(edge["targets"] == [] and edge["weak"] for edge in edges))
            for key in ("device", "extension"):
                self.assertIn(str(layout[key]), self.api_calls)
                self.assertNotIn(str(layout[key]), absent["entries"])
                self.assertFalse(any(call.args[0] == layout[key] for call in digest.call_args_list))
            self.write(str(layout["extension"].relative_to(self.root)), image(kind=6))
            changed = host.closure(include_build=False)
            self.assertTrue(any(edge["targets"] == [str(layout["extension"])]
                                for edge in changed["edges"][str(layout["binary"])]))
            with self.assertRaisesRegex(native.UnsupportedRuntime, "fingerprint-differs"):
                native.same_native_fingerprint(absent, changed)

    def test_present_device_and_absent_extension_preserve_selected_xcode_override_order(self):
        layout = self.weak_mobiledevice_layout(present=(True, False))
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            override = self.write("Xcode.app/Contents/Developer/usr/lib/" + layout["extension"].name, image(kind=6))
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            with patch.object(host, "location", wraps=host.location) as location:
                proof = host.closure(include_build=False)
            self.assertEqual({tuple(edge["targets"]) for edge in proof["edges"][str(layout["binary"])]},
                             {(str(layout["device"]),), (str(override),)})
            self.assertFalse(any(call.args[0] == layout["extension"] for call in location.call_args_list))
            override.unlink()
            proof = host.closure(include_build=False)
            self.assertEqual({tuple(edge["targets"]) for edge in proof["edges"][str(layout["binary"])]},
                             {(str(layout["device"]),), ()})

    def test_present_extension_does_not_hide_absent_device_interface(self):
        layout = self.weak_mobiledevice_layout(present=(False, True))
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            proof = host.closure(include_build=False)
            self.assertEqual({tuple(edge["targets"]) for edge in proof["edges"][str(layout["binary"])]},
                             {(str(layout["extension"]),), ()})

    def test_absent_external_weak_imports_reject_cache_only_unknown_and_access_errors(self):
        layout = self.weak_mobiledevice_layout(present=(False, False))
        with self.weak_mobiledevice_policy(layout):
            for key in ("device", "extension"):
                for result in (True, None, PermissionError(errno.EACCES, "denied")):
                    with self.subTest(path=key, result=type(result).__name__):
                        host = self.host()
                        host.tools["xctest"].write_bytes(image(dependencies=[(native.WEAK, str(layout[key]))]))
                        original_contains = host.system.contains
                        def contains(path):
                            if path == layout[key]:
                                if isinstance(result, Exception):
                                    raise result
                                return result
                            return original_contains(path)
                        host.system.contains = contains
                        reason = ("cache-only-dependency-unproven" if result is True else
                                  "cache-membership-unavailable" if result is None else "file-unavailable")
                        with self.assertRaisesRegex(native.UnsupportedRuntime, reason) as error:
                            host.closure(include_build=False)
                        native.validate_diagnostic(error.exception.diagnostic)

    def test_exact_runtime_file_does_not_admit_siblings_children_prefixes_or_aliases(self):
        layout = self.weak_mobiledevice_layout()
        extension = layout["extension"]
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            for path in (extension.parent, extension.with_name("Other.dylib"),
                         Path(str(extension) + ".other"), extension / "child"):
                host.tools["xctest"].write_bytes(image(dependencies=[(native.WEAK, str(path))]))
                with patch.object(host, "location", wraps=host.location) as location, \
                        self.assertRaisesRegex(native.UnsupportedRuntime, "outside-approved-roots"):
                    host.closure(include_build=False)
                self.assertFalse(any(call.args[0] == path for call in location.call_args_list))
            for raw in (str(extension.parent) + "/./" + extension.name,
                        str(extension.parent) + "//" + extension.name,
                        str(extension.parent) + "/../lib/" + extension.name):
                host.tools["xctest"].write_bytes(image(dependencies=[(native.WEAK, raw)]))
                with self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-path"):
                    host.closure(include_build=False)
            actual = extension.with_name("Other.dylib")
            extension.rename(actual)
            extension.symlink_to(actual.name)
            with self.assertRaisesRegex(native.UnsupportedRuntime, "noncanonical-apple-runtime-file"):
                host.location(extension)

    def test_missing_runtime_file_with_escaping_parent_is_not_optional_absence(self):
        layout = self.weak_mobiledevice_layout(present=(True, False))
        outside = self.root / "outside"
        outside.mkdir()
        layout["extension"].parent.parent.mkdir(parents=True)
        layout["extension"].parent.symlink_to(outside, target_is_directory=True)
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(native.WEAK, str(layout["extension"]))]))
            with self.assertRaisesRegex(native.UnsupportedRuntime, "noncanonical-apple-runtime-file-parent"):
                host.closure(include_build=False)
            self.assertNotIn(str(layout["extension"]), self.api_calls)

    def test_dangling_runtime_file_or_framework_alias_is_not_weak_absence(self):
        layout = self.weak_mobiledevice_layout(present=(False, False))
        layout["extension"].parent.mkdir(parents=True)
        layout["extension"].symlink_to("Missing.dylib")
        layout["device_root"].symlink_to(self.root / "missing-outside", target_is_directory=True)
        with self.weak_mobiledevice_policy(layout):
            for key, reason in (("extension", "noncanonical-apple-runtime-file"),
                                ("device", "runtime-missing-root-noncanonical")):
                with self.subTest(path=key):
                    host = self.host()
                    host.tools["xctest"].write_bytes(image(dependencies=[(native.WEAK, str(layout[key]))]))
                    with self.assertRaisesRegex(native.UnsupportedRuntime, reason):
                        host.closure(include_build=False)
                    self.assertNotIn(str(layout[key]), self.api_calls)

    def test_missing_contained_version_link_checks_both_logical_and_canonical_cache_names(self):
        layout = self.weak_mobiledevice_layout(present=(False, True))
        version = layout["device_root"] / "Versions/A"
        version.mkdir(parents=True)
        (version.parent / "Current").symlink_to("A", target_is_directory=True)
        logical = version.parent / "Current/DeviceInterface"
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(native.WEAK, str(logical))]))
            proof = host.closure(include_build=False)
            self.assertIn(str(logical), self.api_calls)
            self.assertIn(str(layout["device"]), self.api_calls)
            self.assertEqual(proof["edges"][str(host.tools["xctest"])][0]["targets"], [])
            (version.parent / "Current").unlink()
            (version.parent / "B").mkdir()
            (version.parent / "Current").symlink_to("B", target_is_directory=True)
            changed = host.closure(include_build=False)
            with self.assertRaisesRegex(native.UnsupportedRuntime, "fingerprint-differs"):
                native.same_native_fingerprint(proof, changed)
            host.cache_membership[str(version.parent / "B/DeviceInterface")] = True
            with self.assertRaisesRegex(native.UnsupportedRuntime, "cache-only-dependency-unproven"):
                host.closure(include_build=False)

    def test_missing_proof_rejects_type_permission_race_and_non_enoent_errors(self):
        layout = self.weak_mobiledevice_layout(present=(True, False))
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            extension = layout["extension"]
            for failure in (PermissionError(errno.EACCES, "denied"), NotADirectoryError(errno.ENOTDIR, "type"),
                            FileNotFoundError("unproven ENOENT")):
                with self.subTest(error=type(failure).__name__), patch.object(Path, "lstat", side_effect=failure), \
                        self.assertRaises((OSError, native.UnsupportedRuntime)):
                    host.prove_missing(extension)
            extension.parent.mkdir(parents=True)
            extension.mkdir()
            with self.assertRaisesRegex(native.UnsupportedRuntime, "not-regular"):
                host.location(extension)
            with self.assertRaisesRegex(native.UnsupportedRuntime, "candidate-changed"):
                host.prove_missing(extension)

    def test_unapproved_third_weak_mobiledevice_import_stays_incomplete_without_target_io(self):
        layout = self.weak_mobiledevice_layout()
        third = layout["extension"].with_name("Unreviewed.dylib")
        layout["binary"].write_bytes(image(kind=6, subtype=0x80000002, dependencies=[
            (native.WEAK, str(layout["device"])), (native.WEAK, str(layout["extension"])),
            (native.WEAK, str(third))]))
        with self.weak_mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            with patch.object(host, "location", wraps=host.location) as location, \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "outside-approved-roots") as error:
                host.closure(include_build=False)
            self.assertFalse(any(call.args[0] == third for call in location.call_args_list))
            self.assertNotIn(str(third), self.api_calls)
            self.assertEqual(len(error.exception.diagnostic["unapproved_declarations"]), 1)
            self.assertTrue(error.exception.diagnostic["unapproved_declarations"][0]["weak"])

    def test_swift_testing_helper_selection_matches_first_executable_and_refuses_escape_or_absence(self):
        usr = self.xcode / "Developer/Toolchains/Selected.xctoolchain/usr"
        libexec = self.write(str((usr / "libexec/swift/pm/swiftpm-testing-helper").relative_to(self.root)), image())
        libexec.chmod(0o755)
        self.assertEqual(native.swift_testing_helper(usr, self.xcode), libexec)
        binary = self.write(str((usr / "bin/swiftpm-testing-helper").relative_to(self.root)), image() + b"preferred")
        binary.chmod(0o755)
        self.assertEqual(native.swift_testing_helper(usr, self.xcode), binary)
        binary.chmod(0o644)
        self.assertEqual(native.swift_testing_helper(usr, self.xcode), libexec)
        libexec.unlink()
        with self.assertRaisesRegex(native.UnsupportedRuntime, "native-swift-testing-helper-unavailable"):
            native.swift_testing_helper(usr, self.xcode)
        binary.unlink()
        outside = self.write("outside-selected-xcode", image())
        outside.chmod(0o755)
        binary.symlink_to(outside)
        with self.assertRaisesRegex(native.UnsupportedRuntime, "native-swift-testing-helper-outside-selected-xcode"):
            native.swift_testing_helper(usr, self.xcode)

    def test_missing_selected_test_helper_cannot_leave_bundle_coverage_partial(self):
        self.products()
        host = self.host()
        del host.tools["swiftpm-testing-helper"]
        with self.assertRaisesRegex(native.UnsupportedRuntime, "native-test-launch-context-unavailable"):
            host.closure()

    def test_variant_rpaths_keep_load_order_and_ignore_unvisited_later_roots(self):
        self.products()
        helper = self.write("workspace/.build/ordered", universal([
            (native.ARM64, 0, image(dependencies=[(0xC, "@rpath/Choice.dylib")],
                rpaths=["@loader_path/Z", "@loader_path/A", "/Users/private-person/unused"])),
            (native.ARM64, 0x80000002, image(subtype=0x80000002,
                dependencies=[(0xC, "@rpath/Choice.dylib")], rpaths=["@loader_path/A", "@loader_path/Z"]))]))
        first = self.write("workspace/.build/Z/Choice.dylib", image(kind=6) + b"first")
        second = self.write("workspace/.build/A/Choice.dylib", image(kind=6) + b"second")
        parsed = native.macho(helper)
        self.assertEqual(parsed["variants"][0]["rpaths"][0], "@loader_path/Z")
        host = self.host()
        with patch.object(host, "location", wraps=host.location) as location:
            fingerprint = host.closure()
        self.assertFalse(any("private-person" in str(call) for call in location.call_args_list))
        selected = {edge["context"]["subtype"]:edge["targets"]
                    for edge in fingerprint["edges"][str(helper)]}
        self.assertEqual(selected, {0:[str(first)], 0x80000002:[str(second)]})

    def test_requestor_rpaths_precede_only_its_actual_ancestors(self):
        self.products()
        helper = self.write("workspace/.build/bin/inherited", image(
            dependencies=[(0xC, "@rpath/Child.dylib")], rpaths=["@loader_path/../lib"]))
        child = self.write("workspace/.build/lib/Child.dylib", image(kind=6,
            dependencies=[(0xC, "@rpath/Nested.dylib")], rpaths=["@loader_path/own"]))
        own = self.write("workspace/.build/lib/own/Nested.dylib", image(kind=6) + b"own")
        parent = self.write("workspace/.build/lib/Nested.dylib", image(kind=6) + b"parent")
        fingerprint = self.host().closure()
        self.assertEqual({tuple(edge["targets"]) for edge in fingerprint["edges"][str(child)]}, {(str(own),)})
        self.assertTrue(all(edge["context"]["process"]["root"] == str(helper)
                            for edge in fingerprint["edges"][str(child)]))
        own.unlink()
        fingerprint = self.host().closure()
        self.assertEqual({tuple(edge["targets"]) for edge in fingerprint["edges"][str(child)]}, {(str(parent),)})

    def test_loader_relative_paths_do_not_become_global_loaded_rpath_aliases(self):
        self.products()
        self.write("workspace/.build/contextual", image(dependencies=[
            (0xC, "@loader_path/A/Child.dylib"), (0xC, "@loader_path/B/Child.dylib")]))
        expected = {}
        for name in ("A", "B"):
            child = self.write(f"workspace/.build/{name}/Child.dylib", image(kind=6,
                dependencies=[(0xC, "@loader_path/Local.dylib")]))
            target = self.write(f"workspace/.build/{name}/Local.dylib", image(kind=6) + name.encode())
            expected[str(child)] = str(target)
        fingerprint = self.host().closure()
        for child, target in expected.items():
            self.assertEqual({tuple(edge["targets"]) for edge in fingerprint["edges"][child]}, {(target,)})

    def test_swiftpm_framework_and_library_overrides_apply_only_in_test_contexts(self):
        self.products()
        helper = self.write("workspace/.build/context", image(dependencies=[
            (0xC, "/System/Library/Frameworks/Example.framework/Versions/A/Example"),
            (0xC, "/System/Library/Frameworks/Example.framework/Libraries/libSide.dylib"), (0xE, "/usr/lib/dyld")]))
        framework = self.write("Xcode.app/Contents/Developer/Library/PrivateFrameworks/Example.framework/Versions/A/Example",
                               image(kind=6))
        library = self.write("Xcode.app/Contents/Developer/usr/lib/libSide.dylib", image(kind=6))
        # This similarly named framework child is not DYLD_FRAMEWORK_PATH's target.
        wrong = self.write("Xcode.app/Contents/Developer/Library/Frameworks/Example.framework/Libraries/libSide.dylib",
                           image(kind=6) + b"wrong")
        wrong_dylinker = self.write("Xcode.app/Contents/Developer/usr/lib/dyld", image(kind=7))
        fingerprint = self.host().closure()
        edges = fingerprint["edges"][str(helper)]
        test_targets = {target for edge in edges if edge["context"]["mode"] == "swiftpm-test"
                        for target in edge["targets"]}
        plain_targets = {target for edge in edges if edge["context"]["mode"] == "plain"
                         for target in edge["targets"]}
        self.assertEqual(test_targets, {str(framework), str(library), "/usr/lib/dyld"})
        self.assertTrue(all(fingerprint["entries"][path]["kind"] == "system-cache" for path in plain_targets))
        self.assertNotIn(str(wrong), fingerprint["entries"])
        self.assertNotIn(str(wrong_dylinker), fingerprint["entries"])

    def test_conflicting_loaded_name_within_one_launch_fails_with_both_candidate_hashes(self):
        self.products()
        self.write("workspace/.build/conflict", image(dependencies=[
            (0xC, "@loader_path/A.dylib"), (0xC, "@loader_path/B.dylib")]))
        targets = []
        for directory in ("A", "B"):
            self.write(f"workspace/.build/{directory}.dylib", image(kind=6,
                dependencies=[(0xC, "@rpath/Shared.dylib")], rpaths=[f"@loader_path/{directory}"]))
            targets.append(self.write(f"workspace/.build/{directory}/Shared.dylib", image(kind=6) + directory.encode()))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "binding-order-unproven") as error:
            self.host().closure()
        diagnostic = error.exception.diagnostic
        self.assertEqual(diagnostic["loader"], "<build>/B.dylib")
        self.assertEqual(diagnostic["install_name"], "@rpath/Shared.dylib")
        self.assertEqual(diagnostic["executable"], "<build>/conflict")
        found = {item["canonical"]:item["sha256"] for item in diagnostic["candidates"] if item["canonical"]}
        self.assertEqual(found, {"<build>/" + str(path.relative_to(self.build)):hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in targets})
        self.assertEqual(diagnostic["rpaths"], [
            {"loader":"<build>/B.dylib", "raw":"@loader_path/B", "expanded":"<build>/B"},
            {"loader":"<build>/A.dylib", "raw":"@loader_path/A", "expanded":"<build>/A"}])

    def test_resolver_failures_have_closed_redacted_diagnostics_including_global_budgets(self):
        self.products()
        bad = self.build / "bad"
        for dependency in ("@rpath/Missing.dylib", "/Users/private-person/Credentials/secret.dylib", "@unknown/Bad"):
            bad.write_bytes(image(dependencies=[(0xC, dependency)], rpaths=["@loader_path"]))
            with self.subTest(dependency=dependency), self.assertRaises(native.UnsupportedRuntime) as error:
                self.host().closure()
            diagnostic = error.exception.diagnostic
            self.assertIs(native.validate_diagnostic(diagnostic), diagnostic)
            encoded = json.dumps(diagnostic, ensure_ascii=True)
            self.assertNotIn("private-person", encoded)
            self.assertNotIn(str(self.root), encoded)
            self.assertEqual(diagnostic["loader"], "<build>/bad")
            self.assertTrue(diagnostic["candidates"] or diagnostic["install_name"])
            with self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-diagnostic"):
                native.validate_diagnostic({**diagnostic, "command":"untrusted"})
        bad.unlink()
        for constant, limit in (("MAX_SCAN_ENTRIES", 0), ("MAX_HASH_BYTES", 0), ("MAX_QUERIES", 0),
                                ("MAX_CONTEXTS", 0), ("MAX_EDGES", 0), ("MAX_CHAIN", 0), ("MAX_CANDIDATES", 0)):
            with self.subTest(constant=constant), patch.object(native, constant, limit), \
                    self.assertRaises(native.UnsupportedRuntime) as error:
                self.host().closure()
            self.assertEqual(error.exception.diagnostic["type"], "resolver")
            native.validate_diagnostic(error.exception.diagnostic)

    def test_tool_only_preflight_does_not_scan_build_and_reports_external_dependency_failures(self):
        host = self.host()
        shutil.rmtree(self.build)
        with patch.object(host, "images", side_effect=AssertionError("preflight must not scan products")):
            fingerprint = host.closure(include_build=False)
        self.assertIn(str(host.tools["swift-package"]), fingerprint["entries"])
        self.assertFalse(self.build.exists())
        host.tools["swift-package"].write_bytes(image(dependencies=[(0xC, "@rpath/Missing.dylib")],
                                                      rpaths=["@loader_path"]))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "unresolved") as error:
            host.closure(include_build=False)
        diagnostic = error.exception.diagnostic
        self.assertEqual(diagnostic["loader"], "<xcode>/Developer/usr/bin/swift-package")
        self.assertEqual(diagnostic["candidates"], [{"path":"<xcode>/Developer/usr/bin/Missing.dylib",
                                                    "canonical":None, "kind":"missing", "sha256":None}])

    def test_unapproved_declaration_inventory_batches_only_parsed_headers_without_target_io(self):
        host = self.host()
        declarations = ["/Users/private-person/First.dylib", "/Users/private-person/Second.dylib",
                        "/Users/private-person/OtherLoader"]
        tool = host.tools["swift-package"]
        tool.write_bytes(image(dependencies=list(zip((0xC, native.WEAK, 0xE), declarations))))
        digest = hashlib.sha256(tool.read_bytes()).hexdigest()
        collector = native.RuntimeClosure(host)
        with patch.object(host, "location", wraps=host.location) as location, \
                self.assertRaisesRegex(native.UnsupportedRuntime, "outside-approved-roots") as error:
            collector.collect(include_build=False)
        self.assertFalse(any(str(call.args[0]) in declarations for call in location.call_args_list))
        diagnostic = error.exception.diagnostic
        items = diagnostic["unapproved_declarations"]
        self.assertEqual(len(items), 3)
        self.assertEqual([item["install_name"] for item in items], [
            "<outside-approved-roots:" + hashlib.sha256(path.encode()).hexdigest() + ">" for path in declarations])
        self.assertTrue(all(item["loader_sha256"] == digest and item["subtype"] == 0 for item in items))
        self.assertEqual([(item["weak"], item["dylinker"]) for item in items],
                         [(False, False), (True, False), (False, True)])
        self.assertNotIn("private-person", json.dumps(diagnostic))
        with patch.object(host, "location", side_effect=AssertionError("no location lookup")), \
                patch.object(host, "cached", side_effect=AssertionError("no cache query")), \
                patch.object(host.budget, "digest", side_effect=AssertionError("no new hash")), \
                patch.object(native, "macho", side_effect=AssertionError("no new parser read")), \
                patch.object(Path, "open", side_effect=AssertionError("no file read")), \
                patch.object(Path, "stat", side_effect=AssertionError("no stat")), \
                patch.object(Path, "resolve", side_effect=AssertionError("no symlink resolution")), \
                patch.object(Path, "iterdir", side_effect=AssertionError("no directory scan")):
            self.assertEqual(collector.unapproved_declarations(), items)
        self.assertIs(native.validate_diagnostic(diagnostic), diagnostic)
        for key, value in (("loader_sha256", None), ("subtype", True), ("install_name", "x" * 513),
                           ("weak", 1), ("dylinker", "yes"), ("command", "untrusted")):
            invalid = json.loads(json.dumps(diagnostic))
            invalid["unapproved_declarations"][0][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-diagnostic"):
                native.validate_diagnostic(invalid)

    def test_unapproved_declaration_inventory_respects_record_inspection_and_shared_time_caps(self):
        host = self.host()
        tool = host.tools["swift-package"]
        tool.write_bytes(image(dependencies=[(0xC, f"/Unapproved/Library{number}.dylib")
                                            for number in range(native.MAX_DIAGNOSTIC_ITEMS + 1)]))
        collector = native.RuntimeClosure(host)
        with self.assertRaisesRegex(native.UnsupportedRuntime, "outside-approved-roots") as error:
            collector.collect(include_build=False)
        diagnostic = error.exception.diagnostic
        self.assertEqual(len(diagnostic["unapproved_declarations"]), native.MAX_DIAGNOSTIC_ITEMS)
        self.assertTrue(diagnostic["truncated"])
        invalid = json.loads(json.dumps(diagnostic))
        invalid["unapproved_declarations"].append(invalid["unapproved_declarations"][0])
        with self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-diagnostic"):
            native.validate_diagnostic(invalid)
        collector.diagnostic["truncated"] = False
        with patch.object(native, "MAX_DECLARATION_INSPECTIONS", 1):
            self.assertEqual(len(collector.unapproved_declarations()), 1)
        self.assertTrue(collector.diagnostic["truncated"])
        collector.diagnostic["truncated"] = False
        host.budget.started = time.monotonic() - native.MAX_SECONDS
        self.assertEqual(collector.unapproved_declarations(), [])
        self.assertTrue(collector.diagnostic["truncated"])
        self.assertEqual(str(error.exception), "runtime-path-outside-approved-roots")

    def test_resolver_diagnostic_caps_and_escapes_without_using_untrusted_fields(self):
        self.products()
        self.write("workspace/.build/many-paths", image(dependencies=[(0xC, "@rpath/Absent.dylib")],
            rpaths=[f"@loader_path/missing{index}\t" for index in range(native.MAX_CANDIDATES + 1)]))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "candidate-budget") as error:
            self.host().closure()
        diagnostic = error.exception.diagnostic
        self.assertTrue(diagnostic["truncated"])
        self.assertEqual(len(diagnostic["candidates"]), native.MAX_DIAGNOSTIC_ITEMS)
        self.assertEqual(len(diagnostic["rpaths"]), native.MAX_DIAGNOSTIC_ITEMS)
        self.assertIn("\\t", diagnostic["rpaths"][0]["raw"])
        self.assertNotIn("\t", diagnostic["rpaths"][0]["raw"])
        native.validate_diagnostic(diagnostic)
        invalid = json.loads(json.dumps(diagnostic))
        invalid["candidates"][0]["sha256"] = "untrusted-command"
        with self.assertRaises(native.UnsupportedRuntime):
            native.validate_diagnostic(invalid)
        invalid = json.loads(json.dumps(diagnostic))
        invalid["candidates"].append(invalid["candidates"][0])
        with self.assertRaises(native.UnsupportedRuntime):
            native.validate_diagnostic(invalid)
        invalid = {**diagnostic}
        invalid["file"] = invalid
        with self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-diagnostic"):
            native.validate_diagnostic(invalid)

    def test_resolver_symlink_and_io_failures_never_expose_or_hash_outside_targets(self):
        self.products()
        private = self.write("private-person/secret", b"outside bytes must not be read")
        link = self.frameworks / "Escaping.dylib"
        link.symlink_to(private)
        self.write("workspace/.build/escape", image(dependencies=[(0xC, str(link))]))
        host = self.host()
        with patch.object(host.budget, "digest", wraps=host.budget.digest) as digest, \
                self.assertRaisesRegex(native.UnsupportedRuntime, "symlink-escapes") as error:
            host.closure()
        self.assertFalse(any(str(private) in str(call) for call in digest.call_args_list))
        self.assertNotIn("private-person", json.dumps(error.exception.diagnostic))
        self.assertEqual(error.exception.diagnostic["candidates"][-1], {
            "path":"<xcode>/Developer/Library/Frameworks/Escaping.dylib",
            "canonical":"<outside-approved-roots:" + hashlib.sha256(str(private).encode()).hexdigest() + ">",
            "kind":"uninspected", "sha256":None})
        host = self.host()
        with patch.object(host, "location", side_effect=PermissionError("/Users/private-person/secret")), \
                self.assertRaisesRegex(native.UnsupportedRuntime, "native-runtime-file-unavailable") as error:
            host.closure(include_build=False)
        self.assertNotIn("private-person", json.dumps(error.exception.diagnostic))
        native.validate_diagnostic(error.exception.diagnostic)

    def test_mobiledevice_escape_retains_canonical_and_first_alias_without_admission(self):
        host = self.host()
        root = self.root / "System/Library/PrivateFrameworks"
        root.mkdir(parents=True)
        target = self.write("Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice",
                            b"escaped bytes must never be read")
        destination = target.parents[2]
        alias = root / "MobileDevice.framework"
        alias.symlink_to(destination, target_is_directory=True)
        logical = alias / "Versions/A/MobileDevice"
        host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(logical))]))
        with patch.object(native, "SYSTEM_ROOTS", (*native.SYSTEM_ROOTS, root)), \
                patch.object(host.budget, "digest", wraps=host.budget.digest) as digest, \
                self.assertRaisesRegex(native.UnsupportedRuntime, "runtime-symlink-escapes-root") as error:
            host.closure(include_build=False)
        diagnostic = error.exception.diagnostic
        self.assertIn("location", diagnostic)
        redact = lambda path: "<outside-approved-roots:" + hashlib.sha256(str(path).encode()).hexdigest() + ">"
        self.assertEqual(diagnostic["location"], {
            "path":str(logical), "root":str(root), "canonical":redact(target), "root_canonical":str(root),
            "status":"first-link", "first_symlink":{
                "path":str(alias), "target":redact(destination),
                "raw_target_sha256":hashlib.sha256(str(destination).encode()).hexdigest(), "relative":False}})
        self.assertEqual(diagnostic["candidates"][-1]["canonical"], redact(target))
        self.assertIsNone(diagnostic["candidates"][-1]["sha256"])
        self.assertFalse(any(str(target) in str(call) for call in digest.call_args_list))
        self.assertNotIn(str(destination), json.dumps(diagnostic))
        native.validate_diagnostic(diagnostic)
        for field, value in (("canonical", "x" * 513), ("status", "accepted"), ("first_symlink", None),
                             ("command", "untrusted")):
            invalid = json.loads(json.dumps(diagnostic))
            invalid["location"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-diagnostic"):
                native.validate_diagnostic(invalid)
        for field, value in (("relative", 1), ("raw_target_sha256", None), ("target", "x" * 513),
                             ("execute", "untrusted")):
            invalid = json.loads(json.dumps(diagnostic))
            invalid["location"]["first_symlink"][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(native.UnsupportedRuntime, "invalid-native-diagnostic"):
                native.validate_diagnostic(invalid)

    def test_observed_mobiledevice_alias_has_complete_recursive_fingerprint_without_context_mutation(self):
        layout = self.mobiledevice_layout()
        with self.mobiledevice_policy(layout):
            host = self.host()
            # Canonical first, then alias: reuse must still bind the observed alias.
            host.tools["swift-package"].write_bytes(image(dependencies=[(0xC, str(layout["binary"]))]))
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            context = json.loads(json.dumps(host.context))
            with patch.object(Path, "iterdir", side_effect=AssertionError("no framework or parent scan")):
                fingerprint = host.closure(include_build=False)
                native.same_native_fingerprint(fingerprint, host.closure(include_build=False))
            self.assertEqual(host.context, context)
            expected_alias = {"source":str(layout["source"]), "target":str(layout["target"]),
                "raw_target_sha256":"07f8a0bffc980890bdef20b697b173e9cc32e5a01ca0b8d855b25c6003506769"}
            self.assertEqual(context["framework_aliases"], [expected_alias])
            self.assertEqual(fingerprint["entries"][str(layout["binary"])], {
                "kind":"developer-framework", "sha256":hashlib.sha256(layout["binary"].read_bytes()).hexdigest(),
                "subtypes":[0x80000002], "aliases":[expected_alias]})
            self.assertEqual(fingerprint["entries"][str(layout["nested"])]["sha256"],
                             hashlib.sha256(layout["nested"].read_bytes()).hexdigest())
            self.assertNotIn(str(layout["logical"]), fingerprint["entries"])
            changed = json.loads(json.dumps(fingerprint))
            del changed["entries"][str(layout["binary"])]["aliases"]
            with self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
                native.same_native_fingerprint(changed, host.closure(include_build=False))
            layout["nested"].write_bytes(layout["nested"].read_bytes() + b"changed nested bytes")
            with self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
                native.same_native_fingerprint(fingerprint, host.closure(include_build=False))
            self.assertEqual(host.context, context)

    def test_fixed_mobiledevice_policy_matches_all_three_observed_path_hashes(self):
        source, raw, target = native.APPLE_FRAMEWORK_ALIASES[0]
        self.assertEqual(len(native.APPLE_FRAMEWORK_ALIASES), 1)
        self.assertEqual(str(source), "/System/Library/PrivateFrameworks/MobileDevice.framework")
        self.assertEqual(raw, "../../../Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework")
        self.assertEqual(str(target), "/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework")
        for text, expected in (
                (raw, "07f8a0bffc980890bdef20b697b173e9cc32e5a01ca0b8d855b25c6003506769"),
                (str(target), "ac888c17d1c5d8148858ac86815997ebd61e036f7c934678bb5574abf8cf8d39"),
                (str(target / "Versions/A/MobileDevice"), "4f608c6a4ce73221c54703c8537fa301d34df138169be8b329de19d6033cbc16")):
            self.assertEqual(hashlib.sha256(text.encode()).hexdigest(), expected)
        self.assertIn(target, native.APPLE_RUNTIME_FRAMEWORKS)
        self.assertNotIn(target.parent, native.APPLE_RUNTIME_FRAMEWORKS)
        self.assertNotIn(Path("/Library/Developer/PrivateFrameworks/MobileDevice.framework"), native.APPLE_RUNTIME_FRAMEWORKS)

    def test_mobiledevice_cache_answer_cannot_bypass_alias_validation_or_full_hash(self):
        layout = self.mobiledevice_layout()
        with self.mobiledevice_policy(layout):
            host = self.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            host.cache_membership[str(layout["logical"])] = True
            host.cache_membership[str(layout["binary"])] = True
            original_contains = host.system.contains
            def contains(path):
                self.assertFalse(path.is_relative_to(layout["source"]))
                return original_contains(path)
            host.system.contains = contains
            fingerprint = host.closure(include_build=False)
            self.assertEqual(fingerprint["entries"][str(layout["binary"])]["sha256"],
                             hashlib.sha256(layout["binary"].read_bytes()).hexdigest())
            layout["source"].unlink()
            layout["source"].symlink_to(layout["target"], target_is_directory=True)
            with self.assertRaisesRegex(native.UnsupportedRuntime, "alias-target-differs"):
                host.closure(include_build=False)

    def test_mobiledevice_wrong_raw_target_fails_before_any_destination_io(self):
        layout = self.mobiledevice_layout()
        original_resolve = Path.resolve
        original_stat = Path.stat
        with self.mobiledevice_policy(layout):
            host = self.host()
            def source_resolve(path, *args, **kwargs):
                self.assertEqual(path, layout["source"].parent)
                return original_resolve(path, *args, **kwargs)
            def source_stat(path, *args, **kwargs):
                self.assertEqual(path, layout["source"])
                self.assertIs(kwargs.get("follow_symlinks"), False)
                return original_stat(path, *args, **kwargs)
            variants = [str(layout["target"]), layout["raw"].replace("/MobileDevice.framework", "/./MobileDevice.framework"),
                        layout["raw"].replace("MobileDevice.framework", "Sibling.framework")]
            for raw in variants:
                layout["source"].unlink()
                layout["source"].symlink_to(raw, target_is_directory=True)
                with self.subTest(raw=raw), \
                        patch.object(Path, "resolve", autospec=True, side_effect=source_resolve), \
                        patch.object(Path, "stat", autospec=True, side_effect=source_stat), \
                        patch.object(Path, "open", side_effect=AssertionError("no target read")), \
                        patch.object(Path, "iterdir", side_effect=AssertionError("no scan")), \
                        patch.object(host.budget, "digest", side_effect=AssertionError("no target hash")), \
                        patch.object(native, "macho", side_effect=AssertionError("no target parser")), \
                        self.assertRaisesRegex(native.UnsupportedRuntime, "alias-target-differs"):
                    host.location(layout["logical"])

    def test_mobiledevice_source_parent_link_and_canonical_target_root_are_required(self):
        layout = self.mobiledevice_layout()
        with self.mobiledevice_policy(layout):
            host = self.host()
            parent = layout["source"].parent
            actual_parent = parent.with_name("ActualPrivateFrameworks")
            parent.rename(actual_parent)
            parent.symlink_to(actual_parent, target_is_directory=True)
            with self.assertRaisesRegex(native.UnsupportedRuntime, "alias-parent-noncanonical"):
                host.location(layout["logical"])
            parent.unlink()
            actual_parent.rename(parent)
            layout["source"].unlink()
            layout["source"].mkdir()
            with patch.object(native.os, "readlink", side_effect=AssertionError("source is not a link")), \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "alias-not-symlink"):
                host.location(layout["logical"])
            layout["source"].rmdir()
            layout["source"].symlink_to(layout["raw"], target_is_directory=True)
            actual_target = layout["target"].with_name("Other.framework")
            layout["target"].rename(actual_target)
            layout["target"].symlink_to(actual_target, target_is_directory=True)
            with patch.object(host.budget, "digest", side_effect=AssertionError("no escaped target hash")), \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "noncanonical-developer-framework-root"):
                native.RuntimeClosure(host).add(layout["logical"])

    def test_mobiledevice_contained_version_links_work_but_leaf_escape_and_missing_target_reject(self):
        layout = self.mobiledevice_layout()
        original_binary = layout["binary"].read_bytes()
        with self.mobiledevice_policy(layout):
            host = self.host()
            (layout["target"] / "Versions/Current").symlink_to("A", target_is_directory=True)
            logical = layout["source"] / "Versions/Current/MobileDevice"
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(logical))]))
            fingerprint = host.closure(include_build=False)
            self.assertIn("aliases", fingerprint["entries"][str(layout["binary"])])
            outside = self.write("private-person/outside", b"must never read or hash")
            layout["binary"].unlink()
            layout["binary"].symlink_to(outside)
            with patch.object(host.budget, "digest", side_effect=AssertionError("no escaped target hash")), \
                    patch.object(native, "macho", side_effect=AssertionError("no escaped parser")), \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "runtime-symlink-escapes-root"):
                native.RuntimeClosure(host).add(logical)
            layout["binary"].unlink()
            with self.assertRaisesRegex(native.UnsupportedRuntime, "unresolved-runtime-dependency"):
                host.closure(include_build=False)
            layout["binary"].write_bytes(original_binary)
            layout["source"].unlink()
            with self.assertRaisesRegex(native.UnsupportedRuntime, "runtime-missing-alias-unproven"):
                host.closure(include_build=False)

    def test_alias_metadata_stops_at_first_absolute_or_relative_link_without_target_queries(self):
        host = self.host()
        root = self.frameworks
        target = self.write("private-person/Target.framework/Versions/A/Target", b"do not inspect")
        destination = target.parents[2]
        original_lstat = Path.lstat
        original_stat = Path.stat
        for relative in (False, True):
            with self.subTest(relative=relative):
                alias = root / ("Relative.framework" if relative else "Absolute.framework")
                raw = native.posixpath.relpath(str(destination), str(root)) if relative else str(destination)
                alias.symlink_to(raw, target_is_directory=True)
                queries = []
                def source_lstat(path, *args, **kwargs):
                    queries.append(path)
                    self.assertIn(path, (root, alias))
                    return original_lstat(path, *args, **kwargs)
                def source_stat(path, *args, **kwargs):
                    self.assertIn(path, (root, alias))
                    self.assertIs(kwargs.get("follow_symlinks"), False)
                    return original_stat(path, *args, **kwargs)
                with patch.object(Path, "lstat", autospec=True, side_effect=source_lstat), \
                        patch.object(Path, "resolve", side_effect=AssertionError("no new resolution")), \
                        patch.object(Path, "stat", autospec=True, side_effect=source_stat), \
                        patch.object(Path, "open", side_effect=AssertionError("no binary read")), \
                        patch.object(Path, "iterdir", side_effect=AssertionError("no directory scan")), \
                        patch.object(host.budget, "digest", side_effect=AssertionError("no target hash")), \
                        patch.object(native, "macho", side_effect=AssertionError("no target parser")):
                    detail = host.alias_metadata(alias / "Versions/A/Target", alias / "Versions/A/Target",
                                                 root, target, root)
                self.assertEqual(queries, [root, alias])
                self.assertEqual(detail["status"], "first-link")
                self.assertEqual(detail["first_symlink"], {
                    "path":str(alias), "target":str(destination), "relative":relative,
                    "raw_target_sha256":hashlib.sha256(raw.encode()).hexdigest()})
                alias.unlink()

    def test_alias_metadata_caps_and_io_failure_preserve_the_original_escape(self):
        host = self.host()
        root = self.frameworks
        target = self.write("private-person/Target", b"do not inspect")
        alias = root / "Alias"
        alias.symlink_to(target)
        def detail():
            return host.alias_metadata(alias, alias, root, target, root)
        with patch.object(native, "MAX_ALIAS_COMPONENTS", 1):
            self.assertEqual(detail()["status"], "budget")
        with patch.object(native.os, "readlink", return_value="x" * 4096):
            self.assertEqual(detail()["status"], "budget")
        with patch.object(native.os, "readlink", return_value="\udcff"):
            self.assertEqual(detail()["first_symlink"]["raw_target_sha256"], hashlib.sha256(b"\xff").hexdigest())
        with patch.object(Path, "lstat", side_effect=PermissionError("private-person")):
            unavailable = detail()
        self.assertEqual(unavailable["status"], "metadata-unavailable")
        self.assertIsNone(unavailable["first_symlink"])
        host.budget.started = time.monotonic() - native.MAX_SECONDS
        with patch.object(Path, "lstat", side_effect=AssertionError("no metadata I/O after time budget")):
            self.assertEqual(detail()["status"], "budget")
        with self.assertRaisesRegex(native.UnsupportedRuntime, "runtime-symlink-escapes-root") as error:
            host.location(alias)
        self.assertEqual(error.exception.location["status"], "budget")

    def test_native_api_signatures_missing_symbols_no_cache_and_non_darwin(self):
        class Function:
            def __init__(self, operation):
                self.operation = operation
            def __call__(self, argument):
                return self.operation(argument)
        def uuid(buffer):
            for index in range(16):
                buffer[index] = index + 1
            return True
        query = Function(uuid)
        contains = Function(lambda path: path == b"/usr/lib/libSystem.B.dylib")
        library = SimpleNamespace(_dyld_get_shared_cache_uuid=query, _dyld_shared_cache_contains_path=contains)
        with patch.object(native.platform, "system", return_value="Darwin"), \
                patch.object(native.platform, "machine", return_value="arm64"), \
                patch.object(native.ctypes, "CDLL", return_value=library) as loader:
            cache = native.SystemCache()
            self.assertEqual(cache.uuid, bytes(range(1,17)).hex())
            self.assertTrue(cache.contains(Path("/usr/lib/libSystem.B.dylib")))
            self.assertEqual(query.argtypes, [ctypes.POINTER(ctypes.c_ubyte)])
            self.assertIs(query.restype, ctypes.c_bool)
            self.assertEqual(contains.argtypes, [ctypes.c_char_p])
            self.assertIs(contains.restype, ctypes.c_bool)
            loader.assert_called_once_with(None)
            with patch.object(native.ctypes, "CDLL", return_value=SimpleNamespace()), \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "api-unavailable"):
                native.SystemCache()
            with patch.object(query, "operation", return_value=False), \
                    self.assertRaisesRegex(native.UnsupportedRuntime, "cache-unavailable"):
                native.SystemCache()
        with patch.object(native.platform, "system", return_value="Linux"), \
                self.assertRaisesRegex(native.UnsupportedRuntime, "platform-unavailable"):
            native.SystemCache()


if __name__ == "__main__":
    unittest.main()
