#!/usr/bin/env python3
"""Parser/contract fixtures only; these do not prove native Mac API availability."""

import ctypes
import hashlib
import json
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
        for name in ("xctest", "swiftpm-xctest-helper"):
            host.tools[name] = self.write("Xcode.app/Contents/Developer/usr/bin/" + name,
                                         image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        host.context = {"schema":native.SCHEMA, "os_build":"25G83", "arch":"arm64",
                        "system_cache_uuid":"a" * 32, "sdk_build":"17C529", "tools":{}}
        return host

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
                             {"xctest", "swiftpm-xctest-helper"})

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
        selected = {edge["context"]["chain"][0][1]:edge["targets"]
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
        self.assertTrue(all(edge["context"]["chain"][-1][0] == str(helper)
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
            "path":"<xcode>/Developer/Library/Frameworks/Escaping.dylib", "canonical":None,
            "kind":"uninspected", "sha256":None})
        host = self.host()
        with patch.object(host, "location", side_effect=PermissionError("/Users/private-person/secret")), \
                self.assertRaisesRegex(native.UnsupportedRuntime, "native-runtime-file-unavailable") as error:
            host.closure(include_build=False)
        self.assertNotIn("private-person", json.dumps(error.exception.diagnostic))
        native.validate_diagnostic(error.exception.diagnostic)

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
