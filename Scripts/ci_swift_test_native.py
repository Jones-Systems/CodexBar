#!/usr/bin/env python3
"""Bounded native runtime identity for the explicit compiled-test handoff.

Apple formats/APIs: xnu EXTERNAL_HEADERS/mach-o/{loader,fat}.h and dyld
include/mach-o/{dyld,dyld_priv}.h. No artifact-provided command or code is run.
"""

from __future__ import annotations

import ctypes
import hashlib
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
    path = PurePosixPath(raw)
    need(path.is_absolute() and str(path) == raw and ".." not in path.parts, "invalid-native-path")
    return Path(raw)


def validate_environment(environment):
    if any(key.startswith("DYLD_") or key in {
        "TOOLCHAINS", "SDKROOT", "SWIFT_EXEC", "SWIFT_EXEC_MANIFEST", "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC",
        "SWIFTPM_CUSTOM_BIN_DIR", "SWIFTPM_CUSTOM_BINDIR", "SWIFTPM_CUSTOM_LIBS_DIR", "SWIFTPM_PD_LIBS",
        "SWIFT_TESTING_PATH", "SWIFTPM_TESTS_MODULECACHE", "CC", "CXX", "LIBTOOL", "AR",
    } for key, value in environment.items() if value):
        # An injected loader is a rejected request, not unavailable evidence/fallback.
        raise ValueError("native-loader-or-toolchain-override")


def validate_diagnostic(value):
    """Closed, bounded data only. A manifest diagnostic never selects a file or command."""
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
            "rpaths":sorted({raw for image in images for raw in image["rpaths"]})}


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
                dependencies.append({"path": value, "weak": command == WEAK})
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
        self.search_roots = (
            platform_developer / "Library/Frameworks", platform_developer / "Library/PrivateFrameworks",
            platform_developer / "usr/lib", toolchain_usr / "lib/swift/macosx",
            toolchain_usr / "lib/swift/host", toolchain_usr / "lib/swift/pm", toolchain_usr / "lib",
            self.xcode / "SharedFrameworks", self.xcode / "Frameworks",
        )
        self.override_roots = (platform_developer / "Library/Frameworks", platform_developer / "usr/lib")
        self.context = {
            "schema": SCHEMA, "arch": "arm64", "os_version": output(["/usr/bin/sw_vers", "-productVersion"]),
            "os_build": output(["/usr/bin/sw_vers", "-buildVersion"]), "developer_dir": str(self.developer),
            "xcode_version": output(["/usr/bin/xcodebuild", "-version"]), "sdk_path": str(sdk),
            "sdk_version": output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            "sdk_build": output(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-build-version"]),
            "sdk_settings_sha256": self.budget.digest(settings), "system_cache_uuid": self.system.uuid,
            "swiftpm_config_sha256": configuration_sha256,
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

    def closure(self):
        pending = self.images() + [(path, macho(path)) for path in sorted(set(self.tools.values()))]
        images, entries, edges = {}, {}, {}
        roots = set(self.search_roots)
        executables = [path for path, image in pending if image is not None and image["kind"] in (2, 7)]

        def expanded(raw, loader, executable=None):
            if raw.startswith("@loader_path/"):
                value = posixpath.normpath(str(loader.parent) + raw[len("@loader_path"):])
            elif raw == "@loader_path":
                value = str(loader.parent)
            elif raw.startswith("@executable_path/") or raw == "@executable_path":
                need(executable is not None, "runtime-executable-context-unavailable")
                value = posixpath.normpath(str(executable.parent) + raw[len("@executable_path"):])
            elif raw.startswith("/"):
                value = posixpath.normpath(raw)
            else:
                raise UnsupportedRuntime("unsupported-runtime-path-token")
            return safe_absolute(value)

        def expansions(raw, loader, image):
            contexts = ([loader] if image["kind"] in (2, 7) else executables) if raw.startswith(
                "@executable_path") else [None]
            return [expanded(raw, loader, executable) for executable in contexts]

        def permitted(path):
            return path.is_relative_to(self.logical_build) or path.is_relative_to(self.xcode) or any(
                path.is_relative_to(root) for root in SYSTEM_ROOTS) or path == getattr(self, "entrypoint", None)

        def add(logical, image=None):
            self.budget.tick()
            if self.cached(logical):
                key = str(logical)
                entries[key] = {"kind": "system-cache"}
                return key
            physical, key, kind = self.location(logical)
            if key in entries:
                return key
            need(len(images) < MAX_IMAGES, "native-image-budget")
            image = image if image is not None else macho(physical)
            need(image is not None, "runtime-dependency-is-not-supported-macho")
            entries[key] = {"kind": kind, "sha256": self.budget.digest(physical), "subtypes":image["subtypes"]}
            images[key] = image
            for raw in image["rpaths"]:
                # Old unused rpaths on transferred tools do not select a library. Never probe them.
                try:
                    for path in expansions(raw, Path(key), image):
                        if permitted(path):
                            roots.add(path)
                except UnsupportedRuntime:
                    pass
            return key

        for logical, image in pending:
            need(image is not None, "native-launcher-is-not-supported-macho")
            add(logical, image)
        need(images, "native-runtime-images-unavailable")
        # A fixed point includes inherited rpaths and each recursively discovered image.
        # An ambiguous resolution with different bytes is unsupported, never guessed.
        while True:
            self.budget.tick()
            prior = (len(images), len(roots))
            unresolved = []
            edges = {}
            for key, image in list(sorted(images.items())):
                selected = []
                for dependency in image["dependencies"]:
                    raw = dependency["path"]
                    if raw.startswith("@rpath/"):
                        suffix = raw[len("@rpath/"):]
                        need(suffix and not suffix.startswith("/") and str(PurePosixPath(suffix)) == suffix
                             and ".." not in PurePosixPath(suffix).parts, "unsafe-rpath-dependency")
                        for rpath in image["rpaths"]:
                            need(all(permitted(path) for path in expansions(rpath, Path(key), image)),
                                 "unsupported-required-rpath")
                        candidates = [root / suffix for root in sorted(roots)]
                    else:
                        candidates = expansions(raw, Path(key), image)
                        # SwiftPM injects the selected platform's library/framework paths.
                        # Include any concrete override, rather than silently assuming the
                        # shared-cache version wins. Different candidate bytes are unsupported.
                        if raw.startswith("/"):
                            framework = re.search(r"([^/]+\.framework/.*)$", raw)
                            suffix = framework.group(1) if framework else Path(raw).name
                            candidates += [root / suffix for root in self.override_roots]
                    matches = []
                    for candidate in candidates:
                        need(permitted(candidate), "runtime-path-outside-approved-roots")
                        try:
                            matches.append(add(candidate))
                        except FileNotFoundError:
                            continue
                    matches = sorted(set(matches))
                    if not matches:
                        unresolved.append((key, raw, dependency["weak"]))
                        continue
                    fingerprints = {entries[name].get("sha256", "system-cache") for name in matches}
                    need(len(fingerprints) == 1, "ambiguous-runtime-dependency")
                    selected.append({"install_name": raw, "weak": dependency["weak"], "targets": matches})
                edges[key] = selected
            if prior == (len(images), len(roots)):
                for key, raw, weak in unresolved:
                    need(weak, "unresolved-runtime-dependency")
                    edges[key].append({"install_name": raw, "weak": True, "targets": []})
                break
        return {"schema": SCHEMA, "context": self.context, "entries": dict(sorted(entries.items())),
                "edges": dict(sorted(edges.items()))}


def same_native_fingerprint(producer, worker):
    """Complete byte/data equality only. No image-pair allowlist or partial proof."""
    need(isinstance(producer, dict) and isinstance(worker, dict)
         and set(producer) == {"schema", "context", "entries", "edges"}
         and set(worker) == set(producer) and producer["schema"] == worker["schema"] == SCHEMA,
         "incomplete-native-fingerprint")
    need(producer == worker, "native-runtime-fingerprint-differs")
