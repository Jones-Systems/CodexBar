#!/usr/bin/env python3
"""Parser/contract fixtures only; these do not prove native Mac API availability."""

import ctypes
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


def image(kind=2, dependencies=(), rpaths=(), commands=()):
    values = [path_command(command, path) for command, path in dependencies]
    values += [path_command(0x8000001C, path) for path in rpaths]
    values += list(commands)
    data = b"".join(values)
    return struct.pack("<8I", 0xFEEDFACF, native.ARM64, 0, kind, len(values), len(data), 0, 0) + data


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
        host.search_roots = (self.build, self.frameworks)
        host.override_roots = (self.frameworks, self.xcode / "Developer/usr/lib")
        tool = self.write("Xcode.app/Contents/Developer/usr/bin/swift-package",
                          image(dependencies=[(0xC, "/usr/lib/libSystem.B.dylib")]))
        host.tools = {"swift-package":tool}
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
        self.assertEqual([item["weak"] for item in parsed["dependencies"]], [False, True, False, False, False])
        self.assertEqual(parsed["dependencies"][-1]["path"], "/usr/lib/dyld")
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
        self.assertEqual(missing, [{"install_name":"@loader_path/Absent.dylib", "weak":True, "targets":[]}])

    def test_unresolved_strong_outside_root_ambiguous_and_escaping_symlink_are_incomplete(self):
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
        self.write("workspace/.build/Testing.framework/Versions/A/Testing", image(kind=6, commands=[
            struct.pack("<II", 0x1B, 24) + bytes(16)]))
        with self.assertRaisesRegex(native.UnsupportedRuntime, "ambiguous"):
            self.host().closure()
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
                    "SWIFT_EXEC_MANIFEST", "SWIFTPM_CUSTOM_LIBS_DIR", "SWIFTPM_PD_LIBS", "SWIFTPM_CUSTOM_BINDIR"):
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
