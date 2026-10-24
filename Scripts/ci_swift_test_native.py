#!/usr/bin/env python3
"""Bounded native runtime identity for the explicit compiled-test handoff.

Apple formats/APIs: xnu EXTERNAL_HEADERS/mach-o/{loader,fat}.h and dyld
include/mach-o/{dyld,dyld_priv}.h. No artifact-provided command or code is run.
"""

from __future__ import annotations

import ctypes
import hashlib
import json
from pathlib import Path, PurePosixPath
import platform
import posixpath
import re
import shutil
import stat
import struct
import time


SCHEMA = "codexbar.swift-test-native/v1"
MAX_SECONDS = 90
MAX_HASH_BYTES = 2 * 1024 ** 3
MAX_FILE_BYTES = 512 * 1024 ** 2
MAX_SCAN_ENTRIES = 50000
MAX_IMAGES = 512
MAX_QUERIES = 4096
MAX_COMMAND_BYTES = 1024 ** 2
MAX_COMMANDS = 4096
MAX_CONTEXTS = 4096
MAX_CHAIN = 32
MAX_EDGES = 16384
MAX_CANDIDATES = 128
MAX_DIAGNOSTIC_ITEMS = 64
ARM64 = 0x100000C
# Apple Architecture.cpp: generic, v8, old arm64e, versioned user-space arm64e.
# Unknown/future/kernel ABI flags do not qualify a complete proof.
ARM64_SUBTYPES = {0, 1, 2, 0x80000002}
LOADABLE_KINDS = {2, 6, 7, 8}
NONLOADABLE_KINDS = {1, 4, 9, 10}  # object, core dump, linker stub, dSYM
LOADS = {0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20}
WEAK = 0x80000018
SYSTEM_ROOTS = (Path("/usr/lib"), Path("/System/Library/Frameworks"),
                Path("/System/Library/PrivateFrameworks"))


class UnsupportedRuntime(ValueError):
    """Incomplete proof: the caller must retain the original exact-image gate."""


def need(condition, reason):
    if not condition:
        raise UnsupportedRuntime(reason)


class Budget:
    def __init__(self):
        self.started = time.monotonic()
        self.hash_bytes = 0
        self.scan_entries = 0
        self.queries = 0
        self.hashes = {}

    def tick(self):
        need(time.monotonic() - self.started < MAX_SECONDS, "native-identity-time-budget")

    def digest(self, path):
        self.tick()
        info = path.stat()
        need(stat.S_ISREG(info.st_mode) and info.st_size <= MAX_FILE_BYTES, "native-file-budget")
        identity = (str(path.resolve(strict=True)), info.st_dev, info.st_ino, info.st_size,
                    info.st_mtime_ns, info.st_ctime_ns)
        if identity in self.hashes:
            return self.hashes[identity]
        self.hash_bytes += info.st_size
        need(self.hash_bytes <= MAX_HASH_BYTES, "native-hash-byte-budget")
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            while chunk := stream.read(1024 ** 2):
                self.tick()
                digest.update(chunk)
        after = path.stat()
        need((info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
             == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns),
             "native-file-changed")
        self.hashes[identity] = digest.hexdigest()
        return self.hashes[identity]


def safe_absolute(raw):
    need(isinstance(raw, str) and 0 < len(raw) < 4096
         and not any(c in raw for c in "\\\0\r\n"), "invalid-native-path")
    try:
        raw.encode("utf-8", errors="strict")
    except UnicodeEncodeError as error:
        raise UnsupportedRuntime("invalid-native-path-encoding") from error
    path = PurePosixPath(raw)
    need(path.is_absolute() and str(path) == raw and ".." not in path.parts, "invalid-native-path")
    return Path(raw)


def validate_environment(environment):
    if any(key.startswith(("DYLD_", "SWIFTPM_PLATFORM_PATH_")) or key in {
        "TOOLCHAINS", "SDKROOT", "SWIFT_EXEC", "SWIFT_EXEC_MANIFEST", "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC",
        "SWIFTPM_CUSTOM_BIN_DIR", "SWIFTPM_CUSTOM_BINDIR", "SWIFTPM_CUSTOM_LIBS_DIR", "SWIFTPM_PD_LIBS",
        "SWIFT_TESTING_PATH", "SWIFTPM_TESTS_MODULECACHE", "CC", "CXX", "LIBTOOL", "AR",
    } for key, value in environment.items() if value):
        # An injected loader is a rejected request, not unavailable evidence/fallback.
        raise ValueError("native-loader-or-toolchain-override")


def validate_diagnostic(value):
    """Closed, bounded data only. A manifest diagnostic never selects a file or command."""
    def text(value, nullable=False):
        return (nullable and value is None) or (isinstance(value, str) and 0 < len(value) <= 512
            and not any(ord(character) < 32 for character in value))

    def digest(value):
        return value is None or (isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value))

    if isinstance(value, dict) and value.get("type") == "resolver":
        fields = {"type", "loader", "install_name", "executable", "mode", "chain", "rpaths", "candidates", "truncated"}
        need(set(value) == fields | ({"file"} if "file" in value else set())
             and text(value["loader"]) and text(value["install_name"], True) and text(value["executable"], True)
             and isinstance(value["mode"], str) and value["mode"] in {"plain", "swiftpm-test", "audit"}
             and type(value["truncated"]) is bool,
             "invalid-native-diagnostic")
        for field in ("chain", "rpaths", "candidates"):
            need(isinstance(value[field], list) and len(value[field]) <= MAX_DIAGNOSTIC_ITEMS,
                 "invalid-native-diagnostic")
        for item in value["chain"]:
            need(isinstance(item, dict) and set(item) == {"path", "subtype"} and text(item["path"])
                 and type(item["subtype"]) is int and 0 <= item["subtype"] <= 0xFFFFFFFF,
                 "invalid-native-diagnostic")
        for item in value["rpaths"]:
            need(isinstance(item, dict) and set(item) == {"loader", "raw", "expanded"}
                 and all(text(item[key], key == "expanded") for key in item), "invalid-native-diagnostic")
        for item in value["candidates"]:
            need(isinstance(item, dict) and set(item) == {"path", "canonical", "kind", "sha256"}
                 and text(item["path"]) and text(item["canonical"], True) and digest(item["sha256"])
                 and isinstance(item["kind"], str)
                 and item["kind"] in {"uninspected", "missing", "bundled", "xcode", "system-file",
                                     "system-cache", "system-swift-shim"}, "invalid-native-diagnostic")
        if "file" in value:
            need(isinstance(value["file"], dict) and "type" not in value["file"], "invalid-native-diagnostic")
            validate_diagnostic(value["file"])
        return value
    need(isinstance(value, dict) and set(value) == {"path", "file_bytes", "header_sha256", "fat_slices"},
         "invalid-native-diagnostic")
    need(isinstance(value["path"], str) and 0 < len(value["path"]) <= 512
         and not any(ord(character) < 32 for character in value["path"]), "invalid-native-diagnostic")
    need(type(value["file_bytes"]) is int and 0 <= value["file_bytes"] < 2 ** 63
         and isinstance(value["header_sha256"], str)
         and re.fullmatch(r"[0-9a-f]{64}", value["header_sha256"]), "invalid-native-diagnostic")
    need(isinstance(value["fat_slices"], list) and len(value["fat_slices"]) <= 33,
         "invalid-native-diagnostic")
    for item in value["fat_slices"]:
        need(isinstance(item, dict) and set(item) == {"cpu", "subtype", "offset", "bytes", "alignment", "hidden"}
             and type(item["hidden"]) is bool and all(type(item[key]) is int and 0 <= item[key] < 2 ** 64
                 for key in ("cpu", "subtype", "offset", "bytes", "alignment")), "invalid-native-diagnostic")
    return value


def macho(path):
    """Cover every supported ARM64 variant, rather than guess launch/load grading."""
    diagnostic = {"path": str(path)[:512], "file_bytes": 0,
                  "header_sha256": hashlib.sha256(b"").hexdigest(), "fat_slices": []}
    try:
        return _macho(path, diagnostic)
    except UnsupportedRuntime as error:
        error.diagnostic = validate_diagnostic(diagnostic)
        raise


def _macho(path, diagnostic):
    size = path.stat().st_size
    diagnostic["file_bytes"] = size
    with path.open("rb") as stream:
        header = stream.read(32)
        diagnostic["header_sha256"] = hashlib.sha256(header).hexdigest()
        if len(header) < 4:
            return None
        slices = []
        if header[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            wide = header[:4] == b"\xca\xfe\xba\xbf"
            need(len(header) >= 8, "truncated-fat-header")
            count = struct.unpack_from(">I", header, 4)[0]
            need(0 < count <= 32, "fat-architecture-budget")
            stream.seek(8)
            entry_size = 32 if wide else 20
            table_end = 8 + count * entry_size
            encoded = header[:8]
            for _ in range(count):
                data = stream.read(entry_size)
                need(len(data) == entry_size, "truncated-fat-table")
                encoded += data
                cpu, subtype = struct.unpack_from(">II", data)
                offset, length = struct.unpack_from(">QQ" if wide else ">II", data, 8)
                alignment = struct.unpack_from(">I", data, 24 if wide else 16)[0]
                slices.append({"cpu":cpu, "subtype":subtype, "offset":offset, "bytes":length,
                               "alignment":alignment, "hidden":False})
                diagnostic["fat_slices"] = slices
                need(not wide or struct.unpack_from(">I", data, 28)[0] == 0, "invalid-fat-reserved-field")
            # Apple's Universal::forEachSlice recognizes exactly one legacy extra
            # generic ARM64 descriptor after a fat32 table. It must fit entirely
            # before every payload, and receives the same containment checks.
            if not wide and table_end + 20 <= size:
                extra = stream.read(20)
                if len(extra) == 20 and struct.unpack_from(">II", extra) == (ARM64, 0):
                    cpu, subtype, offset, length, alignment = struct.unpack(">IIIII", extra)
                    slices.append({"cpu":cpu, "subtype":subtype, "offset":offset, "bytes":length,
                                   "alignment":alignment, "hidden":True})
                    encoded += extra
                    table_end += 20
            diagnostic["header_sha256"] = hashlib.sha256(encoded).hexdigest()
            need(len(slices) <= 32, "fat-architecture-budget")
            for item in slices:
                need(item["offset"] >= table_end and item["bytes"] >= 8
                     and item["offset"] + item["bytes"] <= size and item["alignment"] <= 63
                     and item["offset"] % (1 << item["alignment"]) == 0, "invalid-fat-slice")
            pairs = [(item["cpu"], (0x80000002 if not wide and item["subtype"] == 2 else item["subtype"])
                      if item["cpu"] == ARM64 else item["subtype"] & 0xFFFFFF) for item in slices]
            need(len(pairs) == len(set(pairs)), "duplicate-fat-architecture")
            ordered = sorted((item["offset"], item["offset"] + item["bytes"]) for item in slices)
            need(all(left[1] <= right[0] for left, right in zip(ordered, ordered[1:])),
                 "overlapping-fat-slices")
        elif header[:4] in (b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca",
                            b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce"):
            raise UnsupportedRuntime("unsupported-macho-byte-order-or-width")
        elif header[:4] != b"\xcf\xfa\xed\xfe":
            return None
        else:
            slices = [{"offset":0, "bytes":size}]
        images, categories, kinds, command_total, count_total = [], set(), set(), 0, 0
        for item in slices:
            stream.seek(item["offset"])
            header = stream.read(min(32, item["bytes"]))
            if header.startswith(b"!<arch>\n"):
                categories.add("archive")
                continue
            need(header[:4] == b"\xcf\xfa\xed\xfe" and len(header) == 32, "unsupported-or-truncated-fat-payload")
            _, cpu, subtype, kind, count, command_bytes, flags, _ = struct.unpack("<8I", header)
            if "cpu" in item:
                historical_arm64e = (not wide and cpu == item["cpu"] == ARM64 and item["subtype"] == 2
                                     and subtype == 0x80000002)
                need((cpu, subtype) == (item["cpu"], item["subtype"]) or historical_arm64e,
                     "fat-header-architecture-mismatch")
            need(kind in LOADABLE_KINDS | NONLOADABLE_KINDS, "unsupported-macho-filetype")
            categories.add("nonloadable" if kind in NONLOADABLE_KINDS else "loadable")
            if kind in NONLOADABLE_KINDS:
                continue
            kinds.add(kind)
            need(count <= MAX_COMMANDS and command_bytes <= MAX_COMMAND_BYTES
                 and 32 + command_bytes <= item["bytes"], "macho-load-command-budget")
            if cpu != ARM64:
                continue  # Another architecture's alternative in a fat file; never native ARM64 fallback.
            need(subtype in ARM64_SUBTYPES, "unsupported-arm64-subtype-abi")
            count_total += count
            command_total += command_bytes
            need(count_total <= MAX_COMMANDS and command_total <= MAX_COMMAND_BYTES, "macho-load-command-budget")
            data = stream.read(command_bytes)
            need(len(data) == command_bytes, "truncated-load-commands")
            images.append({"kind":kind, "subtype":subtype, **load_commands(data, count)})
        need(len(categories) == 1, "mixed-fat-payload-types")
        if categories != {"loadable"}:
            return None
        need(images, "loadable-file-has-no-arm64-slice")
        need(len(kinds) == 1 and len({image["subtype"] for image in images}) == len(images),
             "ambiguous-fat-arm64-variants")
    dependencies = {}
    for image in images:
        for dependency in image["dependencies"]:
            raw = dependency["path"]
            dependencies[raw] = dependencies.get(raw, True) and dependency["weak"]
    return {"kind":images[0]["kind"], "subtypes":sorted(image["subtype"] for image in images),
            "dependencies":[{"path":raw, "weak":weak} for raw, weak in sorted(dependencies.items())],
            "rpaths":sorted({raw for image in images for raw in image["rpaths"]}),
            "variants":sorted(images, key=lambda image: image["subtype"])}


def load_commands(data, count):
    dependencies, rpaths, cursor = [], [], 0
    for _ in range(count):
        need(cursor + 8 <= len(data), "truncated-load-command")
        command, length = struct.unpack_from("<II", data, cursor)
        need(length >= 8 and length % 8 == 0 and cursor + length <= len(data), "invalid-load-command")
        need(command not in (0x6, 0x10, 0x27), "unsupported-legacy-or-environment-load-command")
        need(not command & 0x80000000 or command in {
            0x80000018, 0x8000001C, 0x8000001F, 0x80000022, 0x80000023,
            0x80000028, 0x80000033, 0x80000034,
        }, "unknown-required-load-command")
        if command in LOADS or command in (0x8000001C, 0xE):
            minimum = 24 if command in LOADS else 12
            need(length >= minimum, "short-load-path-command")
            at = struct.unpack_from("<I", data, cursor + 8)[0]
            need(minimum <= at < length, "invalid-load-path-offset")
            raw = data[cursor + at:cursor + length]
            need(b"\0" in raw, "unterminated-load-path")
            try:
                value = raw.split(b"\0", 1)[0].decode("utf-8", errors="strict")
            except UnicodeDecodeError as error:
                raise UnsupportedRuntime("invalid-load-path-encoding") from error
            need(value and len(value) < 4096 and not any(c in value for c in "\\\r\n"),
                 "invalid-load-path")
            if command == 0x8000001C:
                rpaths.append(value)
            else:
                dependencies.append({"path": value, "weak": command == WEAK,
                                     **({"dylinker": True} if command == 0xE else {})})
        cursor += length
    need(cursor == len(data), "load-command-count-differs")
    return {"dependencies": dependencies, "rpaths": rpaths}


class SystemCache:
    """Fixed read-only Apple API calls against the already loaded process image.

    dyld_priv.h: bool _dyld_get_shared_cache_uuid(uuid_t);
    dyld.h: bool _dyld_shared_cache_contains_path(const char *).
    Missing symbols, no active cache or non-Darwin: no compatibility proof.
    """
    def __init__(self):
        need(platform.system() == "Darwin" and platform.machine() == "arm64", "native-platform-unavailable")
        try:
            library = ctypes.CDLL(None)
            query_uuid = library._dyld_get_shared_cache_uuid
            self._contains = library._dyld_shared_cache_contains_path
            query_uuid.argtypes = [ctypes.POINTER(ctypes.c_ubyte)]
            query_uuid.restype = ctypes.c_bool
            self._contains.argtypes = [ctypes.c_char_p]
            self._contains.restype = ctypes.c_bool
            value = (ctypes.c_ubyte * 16)()
            need(query_uuid(value) and any(value), "native-cache-unavailable")
            self.uuid = bytes(value).hex()
        except (AttributeError, OSError) as error:
            raise UnsupportedRuntime("native-cache-api-unavailable") from error

    def contains(self, path):
        # Data query only; never dlopen a path supplied by a Mach-O or manifest.
        return bool(self._contains(str(path).encode("utf-8")))


class Host:
    def __init__(self, workspace, build, environment, capture, system=None, swift_command=None):
        self.budget = Budget()
        self.workspace = safe_absolute(str(workspace))
        self.logical_build = self.workspace / ".build"
        self.build = Path(build)
        validate_environment(environment)
        self.system = system if system is not None else SystemCache()
        self.cache_membership = {}
        self.developer = safe_absolute(environment.get("DEVELOPER_DIR", ""))
        need(self.developer.resolve(strict=True) == self.developer and self.developer.name == "Developer"
             and self.developer.parent.name == "Contents" and self.developer.parent.parent.suffix == ".app"
             and self.developer.parent.parent.parent == Path("/Applications"), "unsupported-developer-directory")
        self.xcode = self.developer.parent

        def output(arguments):
            self.budget.tick()
            result = capture(arguments, timeout=min(30, max(1, MAX_SECONDS - int(
                time.monotonic() - self.budget.started))))
            result.check_returncode()
            value = result.stdout.strip()
            need(value and len(value) < 4096 and "\0" not in value, "invalid-native-tool-output")
            return value

        self.tools = {}
        for name in ("swift", "swift-build", "swift-package", "swift-frontend", "xctest"):
            arguments = ["/usr/bin/xcrun", *(["--sdk", "macosx"] if name == "xctest" else []), "--find", name]
            path = safe_absolute(output(arguments))
            need(path.resolve(strict=True).is_relative_to(self.xcode), "native-tool-outside-selected-xcode")
            self.tools[name] = path.resolve(strict=True)
        command = swift_command or ["swift"]
        if len(command) != 1:
            raise ValueError("native-custom-swift-command-override")
        entrypoint = shutil.which(command[0], path=environment.get("PATH", ""))
        need(entrypoint is not None, "native-swift-entrypoint-unavailable")
        self.entrypoint = safe_absolute(entrypoint).resolve(strict=True)
        if self.entrypoint not in (Path("/usr/bin/swift"), self.tools["swift"]):
            raise ValueError("native-swift-entrypoint-outside-selected-toolchain")
        self.tools["swift-entrypoint"] = self.entrypoint
        toolchain_usr = self.tools["swift-build"].parent.parent
        helper = toolchain_usr / "libexec/swift/pm/swiftpm-xctest-helper"
        need(helper.is_file() and helper.resolve(strict=True).is_relative_to(self.xcode),
             "native-xctest-helper-unavailable")
        self.tools["swiftpm-xctest-helper"] = helper.resolve(strict=True)
        manifest_library = toolchain_usr / "lib/swift/pm/ManifestAPI/libPackageDescription.dylib"
        need(manifest_library.is_file() and manifest_library.resolve(strict=True).is_relative_to(self.xcode),
             "native-manifest-runtime-unavailable")
        self.tools["swiftpm-manifest-runtime"] = manifest_library.resolve(strict=True)
        configuration = toolchain_usr / "share/pm/config.json"
        configuration_sha256 = None
        if configuration.exists():
            need(configuration.resolve(strict=True).is_relative_to(self.xcode),
                 "native-swiftpm-config-outside-selected-xcode")
            configuration_sha256 = self.budget.digest(configuration)
        sdk = safe_absolute(output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]))
        need(sdk.resolve(strict=True).is_relative_to(self.developer), "native-sdk-outside-selected-xcode")
        sdk = sdk.resolve(strict=True)
        settings = sdk / "SDKSettings.json"
        need(settings.resolve(strict=True).is_relative_to(sdk), "native-sdk-settings-outside-sdk")
        platform_developer = sdk.parent.parent
        platform_path = safe_absolute(output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-platform-path"]))
        need(platform_path.resolve(strict=True) == platform_developer.parent,
             "native-sdk-platform-layout-unavailable")
        # SwiftPM 6.2 TestingSupport + SwiftSDK.sdkPlatformPaths order. These
        # overrides belong only to test subprocesses, never the ordinary tools.
        self.test_framework_roots = (platform_developer / "Library/Frameworks",
                                     platform_developer / "Library/PrivateFrameworks")
        self.test_library_roots = (platform_developer / "usr/lib",)
        testing_frameworks = toolchain_usr.parent / "Library/Developer/Frameworks"
        testing_libraries = toolchain_usr / "lib/swift/macosx/testing"
        if (testing_frameworks / "Testing.framework").exists():
            testing_path = testing_frameworks
        else:
            testing_path = testing_libraries if testing_libraries.exists() else None
        if testing_path is not None:
            need(testing_path.resolve(strict=True).is_relative_to(self.xcode),
                 "native-testing-path-outside-selected-xcode")
            # Match SwiftPM's extension test exactly, including a directory
            # named Frameworks being a library-path override rather than .framework.
            if testing_path.suffix == ".framework":
                self.test_framework_roots = (testing_path, *self.test_framework_roots)
            else:
                self.test_library_roots = (testing_path, *self.test_library_roots)
        self.context = {
            "schema": SCHEMA, "arch": "arm64", "os_version": output(["/usr/bin/sw_vers", "-productVersion"]),
            "os_build": output(["/usr/bin/sw_vers", "-buildVersion"]), "developer_dir": str(self.developer),
            "xcode_version": output(["/usr/bin/xcodebuild", "-version"]), "sdk_path": str(sdk),
            "sdk_version": output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            "sdk_build": output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-build-version"]),
            "sdk_settings_sha256": self.budget.digest(settings), "system_cache_uuid": self.system.uuid,
            "swiftpm_config_sha256": configuration_sha256,
            "test_framework_roots": [str(path) for path in self.test_framework_roots],
            "test_library_roots": [str(path) for path in self.test_library_roots],
            "tools": {name: {"path": str(path), "sha256": self.budget.digest(path)}
                      for name, path in sorted(self.tools.items())},
        }

    def location(self, logical):
        logical = safe_absolute(str(logical))
        if logical.is_relative_to(self.logical_build):
            physical = self.build / logical.relative_to(self.logical_build)
            root, kind = self.build, "bundled"
        elif logical.is_relative_to(self.xcode):
            physical, root, kind = logical, self.xcode, "xcode"
        elif logical == getattr(self, "entrypoint", None) == Path("/usr/bin/swift"):
            physical, root, kind = logical, Path("/usr/bin"), "system-swift-shim"
        else:
            roots = [root for root in SYSTEM_ROOTS if logical.is_relative_to(root)]
            need(roots, "runtime-path-outside-approved-roots")
            physical, root, kind = logical, roots[0], "system-file"
        # Do not inspect the destination of an external/escaping symlink.
        resolved = physical.resolve(strict=True)
        need(resolved.is_relative_to(root.resolve(strict=True)), "runtime-symlink-escapes-root")
        need(stat.S_ISREG(resolved.stat().st_mode), "runtime-path-is-not-regular")
        canonical = (self.logical_build / resolved.relative_to(self.build.resolve(strict=True))
                     if kind == "bundled" else resolved)
        return physical, str(canonical), kind

    def cached(self, logical):
        if not any(logical.is_relative_to(root) for root in SYSTEM_ROOTS):
            return False
        if str(logical) in self.cache_membership:
            return self.cache_membership[str(logical)]
        self.budget.queries += 1
        need(self.budget.queries <= MAX_QUERIES, "native-cache-query-budget")
        self.budget.tick()
        result = self.system.contains(logical)
        self.cache_membership[str(logical)] = result
        return result

    def images(self):
        """All transferred loadable images, including tools and dependency helpers."""
        pending = [self.build]
        found = []
        while pending:
            directory = pending.pop()
            for path in sorted(directory.iterdir()):
                self.inspected_path = self.logical_build / path.relative_to(self.build)
                self.budget.tick()
                self.budget.scan_entries += 1
                need(self.budget.scan_entries <= MAX_SCAN_ENTRIES, "native-scan-entry-budget")
                info = path.lstat()
                if stat.S_ISDIR(info.st_mode):
                    pending.append(path)
                elif stat.S_ISREG(info.st_mode):
                    image = macho(path)
                    if image is not None:
                        found.append((self.logical_build / path.relative_to(self.build), image))
                        need(len(found) <= MAX_IMAGES, "native-image-budget")
                else:
                    need(stat.S_ISLNK(info.st_mode)
                         and path.resolve(strict=True).is_relative_to(self.build.resolve(strict=True)),
                         "unsupported-or-escaping-build-entry")
        need(any(path.name.endswith("Tests") and ".xctest/" in str(path) for path, _ in found),
             "native-test-image-unavailable")
        return found

    def closure(self, *, include_build=True):
        return RuntimeClosure(self).collect(include_build=include_build)


class RuntimeClosure:
    """Declared native dependency graph; ordered per launch, never a global rpath union.

    Loader.cpp's requestor-to-ancestor stack and DyldProcessConfig.cpp's test
    override order are the supported subset. Unknown fallback/load-order choices
    remain incomplete evidence. See the native compatibility engineering spec.
    """
    def __init__(self, host):
        self.host = host
        self.images, self.entries, self.edges = {}, {}, {}
        self.visited, self.covered = set(), set()
        self.edge_count = 0
        self.diagnostic = {"type":"resolver", "loader":"<inventory>", "install_name":None,
                           "executable":None, "mode":"audit", "chain":[], "rpaths":[],
                           "candidates":[], "truncated":False}

    def label(self, value):
        if value is None:
            return None
        raw = str(value)
        if raw.startswith("/"):
            path = Path(posixpath.normpath(raw))
            for root, token in ((self.host.logical_build, "<build>"), (self.host.build, "<build>"),
                                (self.host.xcode, "<xcode>")):
                if path.is_relative_to(root):
                    raw = token + "/" + str(path.relative_to(root))
                    break
            else:
                if not (any(path.is_relative_to(root) for root in SYSTEM_ROOTS)
                        or path == Path("/usr/bin/swift")):
                    raw = "<outside-approved-roots:" + hashlib.sha256(raw.encode("utf-8", "surrogatepass")).hexdigest() + ">"
        elif not raw.startswith(("@rpath/", "@loader_path", "@executable_path", "<")):
            raw = "<unsupported-path:" + hashlib.sha256(raw.encode("utf-8", "surrogatepass")).hexdigest() + ">"
        return raw.encode("unicode_escape").decode("ascii")[:512]

    def note(self, field, value):
        if len(self.diagnostic[field]) < MAX_DIAGNOSTIC_ITEMS:
            self.diagnostic[field].append(value)
        else:
            self.diagnostic["truncated"] = True

    def state(self, key, executable=None, mode="audit", chain=(), raw=None):
        self.diagnostic = {"type":"resolver", "loader":self.label(key), "install_name":self.label(raw),
                           "executable":self.label(executable), "mode":mode,
                           "chain":[{"path":self.label(path), "subtype":variant["subtype"]}
                                    for path, variant in chain[:MAX_DIAGNOSTIC_ITEMS]],
                           "rpaths":[], "candidates":[], "truncated":len(chain) > MAX_DIAGNOSTIC_ITEMS}

    def permitted(self, path):
        return (path.is_relative_to(self.host.logical_build) or path.is_relative_to(self.host.xcode)
                or any(path.is_relative_to(root) for root in SYSTEM_ROOTS)
                or path == getattr(self.host, "entrypoint", None))

    def add(self, logical, image=None, candidate=None):
        if candidate is None:
            candidate = {"path":self.label(logical), "canonical":None, "kind":"uninspected", "sha256":None}
            self.note("candidates", candidate)
        self.host.budget.tick()
        need(self.permitted(logical), "runtime-path-outside-approved-roots")
        if self.host.cached(logical):
            key = str(logical)
            self.entries[key] = {"kind":"system-cache"}
            candidate.update(canonical=self.label(key), kind="system-cache")
            return key
        physical, key, kind = self.host.location(logical)
        candidate.update(canonical=self.label(key), kind=kind)
        if key in self.entries:
            candidate["sha256"] = self.entries[key].get("sha256")
            return key
        need(len(self.images) < MAX_IMAGES, "native-image-budget")
        digest = self.host.budget.digest(physical)
        candidate["sha256"] = digest
        image = image if image is not None else macho(physical)
        need(image is not None, "runtime-dependency-is-not-supported-macho")
        self.entries[key] = {"kind":kind, "sha256":digest, "subtypes":image["subtypes"]}
        self.images[key] = image
        return key

    def expanded(self, raw, loader, executable):
        if raw == "@loader_path" or raw.startswith("@loader_path/"):
            value = str(Path(loader).parent) + raw[len("@loader_path"):]
        elif raw == "@executable_path" or raw.startswith("@executable_path/"):
            need(executable is not None, "runtime-executable-context-unavailable")
            value = str(Path(executable).parent) + raw[len("@executable_path"):]
        elif raw.startswith("/"):
            value = raw
        else:
            raise UnsupportedRuntime("unsupported-runtime-path-token")
        return safe_absolute(posixpath.normpath(value))

    def candidates(self, dependency, chain, executable, mode):
        raw = dependency["path"]
        if raw.startswith("@rpath/"):
            suffix = raw[len("@rpath/"):]
            need(suffix and not suffix.startswith("/") and str(PurePosixPath(suffix)) == suffix
                 and ".." not in PurePosixPath(suffix).parts, "unsafe-rpath-dependency")
        else:
            # Validate even if a test override could otherwise satisfy the leaf.
            self.expanded(raw, chain[0][0], executable)
        # Apple only treats the last .framework component as a framework when
        # its name equals the leaf; nested Libraries/foo.dylib uses library paths.
        partial = None
        at = raw.rfind(".framework/")
        if at >= 0:
            start = raw.rfind("/", 0, at) + 1
            if raw[start:at] == raw.rsplit("/", 1)[-1]:
                partial = raw[start:]
        if mode == "swiftpm-test" and not dependency.get("dylinker"):
            roots = self.host.test_framework_roots if partial else self.host.test_library_roots
            suffix = partial or raw.rsplit("/", 1)[-1]
            need(suffix and suffix not in {".", ".."}, "unsafe-runtime-override-suffix")
            for root in roots:
                yield root / suffix
        if raw.startswith("@rpath/"):
            suffix = raw[len("@rpath/"):]
            # This generator stops at the first chosen candidate. Unused later
            # rpaths (including old compiler paths) never cause filesystem probes.
            for loader, variant in chain:
                for rpath in variant["rpaths"]:
                    item = {"loader":self.label(loader), "raw":self.label(rpath), "expanded":None}
                    self.note("rpaths", item)
                    root = self.expanded(rpath, loader, executable)
                    item["expanded"] = self.label(root)
                    need(self.permitted(root), "unsupported-required-rpath")
                    yield root / suffix
        else:
            yield self.expanded(raw, chain[0][0], executable)

    def resolve(self, dependency, chain, executable, mode, bindings):
        key = chain[0][0]
        raw = dependency["path"]
        self.state(key, executable, mode, chain, raw)
        selected = None
        for index, logical in enumerate(self.candidates(dependency, chain, executable, mode)):
            need(index < MAX_CANDIDATES, "native-resolution-candidate-budget")
            candidate = {"path":self.label(logical), "canonical":None, "kind":"uninspected", "sha256":None}
            self.note("candidates", candidate)
            try:
                selected = self.add(logical, candidate=candidate)
            except FileNotFoundError:
                candidate["kind"] = "missing"
                continue
            break
        need(selected is not None or dependency["weak"], "unresolved-runtime-dependency")
        # Already-loaded @rpath names can bind before a new search. Rather than
        # guess cross-chain load order, require every search in this launch to
        # agree on the canonical image. Separate launches never share bindings.
        if raw.startswith("@rpath/") and raw in bindings and bindings[raw]["target"] != selected:
            prior = bindings[raw]
            previous = prior["target"]
            self.diagnostic["truncated"] |= prior["truncated"]
            for item in prior["rpaths"]:
                self.note("rpaths", item)
            if previous is not None:
                entry = self.entries[previous]
                self.note("candidates", {"path":self.label(previous), "canonical":self.label(previous),
                                         "kind":entry["kind"], "sha256":entry.get("sha256")})
            raise UnsupportedRuntime("runtime-binding-order-unproven")
        if raw.startswith("@rpath/"):
            bindings[raw] = {"target":selected, "rpaths":list(self.diagnostic["rpaths"]),
                             "truncated":self.diagnostic["truncated"]}
        return selected

    def walk(self, key, ancestors, executable, mode, bindings, variant=None):
        if key not in self.images:
            return  # The matching cache UUID covers the system cache's internal closure.
        for current in [variant] if variant is not None else self.images[key]["variants"]:
            self.state(key, executable, mode, ancestors)
            if any(path == key and prior["subtype"] == current["subtype"] for path, prior in ancestors):
                continue
            chain = ((key, current), *ancestors)
            self.state(key, executable, mode, chain)
            need(len(chain) <= MAX_CHAIN, "native-loader-chain-budget")
            identity = (executable, mode, tuple((path, item["subtype"]) for path, item in chain))
            if identity in self.visited:
                continue
            need(len(self.visited) < MAX_CONTEXTS, "native-loader-context-budget")
            self.visited.add(identity)
            self.covered.add(key)
            for dependency in current["dependencies"]:
                target = self.resolve(dependency, chain, executable, mode, bindings)
                edge = {"install_name":dependency["path"], "weak":dependency["weak"],
                        "targets":[] if target is None else [target],
                        "context":{"executable":executable, "mode":mode,
                                   "chain":[[path, item["subtype"]] for path, item in chain]}}
                self.edges.setdefault(key, []).append(edge)
                self.edge_count += 1
                need(self.edge_count <= MAX_EDGES, "native-runtime-edge-budget")
                if target is not None:
                    self.walk(target, chain, executable, mode, bindings)

    def collect(self, *, include_build):
        try:
            pending = self.host.images() if include_build else []
            bundled = set()
            for logical, image in pending:
                self.state(logical)
                bundled.add(self.add(logical, image))
            tools = {}
            for name, path in sorted(self.host.tools.items()):
                self.state(path)
                tools[name] = self.add(path)
            need(self.images, "native-runtime-images-unavailable")
            tests = sorted(key for key in bundled if self.images[key]["kind"] == 8
                           and ".xctest/" in key and Path(key).name.endswith("Tests"))
            test_launchers = {tools[name] for name in ("xctest", "swiftpm-xctest-helper") if name in tools}
            need(not tests or len(test_launchers) == 2, "native-test-launch-context-unavailable")
            roots = sorted(key for key, image in self.images.items() if image["kind"] in (2, 7))
            for key in roots:
                modes = ("plain", "swiftpm-test") if key in bundled or key in test_launchers else ("plain",)
                for mode in modes:
                    for variant in self.images[key]["variants"]:
                        bindings = {}
                        self.walk(key, (), key, mode, bindings, variant)
                        if key in test_launchers and mode == "swiftpm-test":
                            for test in tests:
                                # SwiftPM starts a separate process for each bundle.
                                self.walk(test, ((key, variant),), key, mode, dict(bindings))
            # Audit every remaining loadable image too, including unreferenced
            # dependency SDK tools/libraries. No invented parent search paths.
            for key in sorted(self.images):
                if key not in self.covered:
                    self.walk(key, (), None, "audit", {})
            return {"schema":SCHEMA, "context":self.host.context, "entries":dict(sorted(self.entries.items())),
                    "edges":{key:sorted(values, key=lambda item: json.dumps(item, sort_keys=True))
                             for key, values in sorted(self.edges.items())}}
        except (UnsupportedRuntime, OSError) as error:
            if self.diagnostic["loader"] == "<inventory>" and hasattr(self.host, "inspected_path"):
                self.state(self.host.inspected_path)
            if isinstance(error, OSError):
                failure = UnsupportedRuntime("native-runtime-file-unavailable")
            else:
                failure = error
            file_diagnostic = getattr(error, "diagnostic", None)
            if file_diagnostic is not None and "type" not in file_diagnostic:
                self.diagnostic["file"] = {**file_diagnostic, "path":self.label(file_diagnostic["path"])}
            failure.diagnostic = validate_diagnostic(self.diagnostic)
            raise failure from (error if failure is not error else None)


def same_native_fingerprint(producer, worker):
    """Complete byte/data equality only. No image-pair allowlist or partial proof."""
    need(isinstance(producer, dict) and isinstance(worker, dict)
         and set(producer) == {"schema", "context", "entries", "edges"}
         and set(worker) == set(producer) and producer["schema"] == worker["schema"] == SCHEMA,
         "incomplete-native-fingerprint")
    need(producer == worker, "native-runtime-fingerprint-differs")
