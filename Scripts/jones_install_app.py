#!/usr/bin/env python3
"""Local Jones bundle transactions; operator/trust contract: docs/jones/INSTALL-AND-UPDATES.md.

Only MacOperations reaches native commands. Tests supply a synthetic adapter;
there is deliberately no CLI/environment switch that disables verification.
"""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
import uuid
import zipfile
from xml.parsers.expat import ExpatError

# The shell wrapper uses Python -I; load only this adjacent owned helper without
# adding a search path or accepting PYTHONPATH/site-package overrides.
_XATTR_SPEC = importlib.util.spec_from_file_location("jones_xattrs", Path(__file__).with_name("jones_xattrs.py"))
_XATTR_MODULE = importlib.util.module_from_spec(_XATTR_SPEC)
_XATTR_SPEC.loader.exec_module(_XATTR_MODULE)
list_xattrs = _XATTR_MODULE.list_xattrs
_SIGNING_SPEC = importlib.util.spec_from_file_location("jones_signing", Path(__file__).with_name("jones_signing.py"))
_SIGNING_MODULE = importlib.util.module_from_spec(_SIGNING_SPEC)
_SIGNING_SPEC.loader.exec_module(_SIGNING_MODULE)



SCHEMA = "jones-app-install/v1"
STATE_SCHEMA = "jones-app-install-state/v1"
BUNDLE_ID = "com.jonessystems.codexbar"
GROUP_ID = "JONESLOCAL." + BUNDLE_ID
ICLOUD_ID = "iCloud." + BUNDLE_ID
IDENTITY = {
    "CFBundleIdentifier": BUNDLE_ID,
    "CFBundleDisplayName": "CodexBar Jones",
    "JonesAppBundleID": BUNDLE_ID,
    "JonesAppGroupID": GROUP_ID,
    "JonesICloudID": ICLOUD_ID,
    "JonesStateKey": "jones",
    "CodexBarTeamID": "JONESLOCAL",
}
MAX_ARCHIVE = 256 * 1024 * 1024
MAX_EXPANDED = 1024 * 1024 * 1024
RESERVE = 1024 * 1024 * 1024
MAX_ENTRIES = 50000
SHA_RE = re.compile(r"[0-9a-f]{40}\Z")
HASH_RE = re.compile(r"[0-9a-f]{64}\Z")
BUILD_RE = re.compile(r"[1-9][0-9]{0,8}\.[1-9][0-9]{0,11}\Z")
RUN_RE = re.compile(r"https://github\.com/Jones-Systems/CodexBar/actions/runs/[1-9][0-9]*(?:/attempts/[1-9][0-9]*)?\Z")
PREVIOUS_RE = re.compile(r"previous-[0-9a-f]{32}\.app\Z")
SIGNALS = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)


class InstallError(Exception):
    def __init__(self, code, message, exit_code=2, **details):
        super().__init__(message)
        self.code = code
        self.exit_code = exit_code
        self.details = details


def require(condition, code, message):
    if not condition:
        raise InstallError(code, message)


def exists(path):
    return os.path.lexists(str(path))


def no_symlink_components(path):
    for part in (path,) + tuple(path.parents):
        if exists(part):
            require(not part.is_symlink(), "symlink_path", "A path component is a symlink: " + str(part))


def target_path(value):
    raw = Path(value).expanduser()
    require(raw.is_absolute() and ".." not in raw.parts, "target_path", "Use an absolute target without '..'.")
    no_symlink_components(raw)
    require(raw.suffix == ".app", "target_path", "The target must name one .app bundle.")
    for part in raw.parent.parts:
        require(part not in ("Library", ".codexbar", ".codexbar-jones", ".config")
                and not part.endswith((".app", ".noindex")), "target_path",
                "Choose an application directory outside application state, bundles, and recovery storage.")
    require("AppTranslocation" not in raw.parts, "translocated", "Choose a permanent writable application location.")
    return raw


def nearest_directory(path):
    while not exists(path):
        path = path.parent
    require(path.is_dir() and not path.is_symlink(), "target_parent", "Target parent is not a real directory.")
    return path


def read_plist(path):
    require(path.is_file() and not path.is_symlink(), "bundle_metadata", "Missing regular plist: " + str(path))
    require(path.stat().st_size <= 1024 * 1024, "bundle_metadata", "Bundle plist exceeds the metadata limit.")
    try:
        value = plistlib.loads(path.read_bytes())
    except (ValueError, plistlib.InvalidFileException, ExpatError) as error:
        raise InstallError("bundle_metadata", "Invalid bundle plist: " + str(path)) from error
    require(isinstance(value, dict), "bundle_metadata", "Bundle plist must be a dictionary.")
    return value


def contained_link(item, root):
    # Resolve each link inside the bundle before considering '..'; never stat an outside target.
    pending, resolved, hops = list(item.relative_to(root).parts), [], 0
    while pending:
        part = pending.pop(0)
        if part == ".":
            continue
        if part == "..":
            require(bool(resolved), "unsafe_link", "Bundle symlink leaves the bundle.")
            resolved.pop()
            continue
        path = root.joinpath(*resolved, part)
        try:
            mode = path.lstat().st_mode
        except OSError as error:
            raise InstallError("unsafe_link", "Bundle symlink has a missing or unreadable target.") from error
        if stat.S_ISLNK(mode):
            hops += 1
            require(hops <= 40, "unsafe_link", "Bundle symlink is cyclic or exceeds the supported link depth.")
            destination = os.readlink(str(path))
            require(destination and not destination.startswith("/") and "\\" not in destination
                    and ":" not in destination and "\0" not in destination,
                    "unsafe_link", "Bundle symlink is absolute or malformed.")
            pending = list(PurePosixPath(destination).parts) + pending
        else:
            require(not pending or stat.S_ISDIR(mode), "unsafe_link", "Symlink traverses a non-directory.")
            resolved.append(part)


def walk_error(error):
    raise error


def check_tree(root):
    require(root.is_dir() and not root.is_symlink(), "bundle_path", "Bundle must be a real directory.")
    info = root.lstat()
    require(not info.st_mode & 0o6022, "unsafe_mode", "Bundle root is privileged or externally writable.")
    count, total = 0, 0
    for parent, dirs, files in os.walk(str(root), followlinks=False, onerror=walk_error):
        for name in dirs + files:
            item = Path(parent) / name
            item_info = item.lstat()
            mode = item_info.st_mode
            require(item_info.st_dev == info.st_dev, "volume", "Bundle contains another filesystem.")
            count += 1
            if stat.S_ISREG(mode):
                total += item_info.st_size
            require(count <= MAX_ENTRIES and total <= MAX_EXPANDED,
                    "bundle_size", "Bundle exceeds the supported entry or expanded-size bound.")
            if stat.S_ISLNK(mode):
                contained_link(item, root)
            else:
                require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), "unsafe_file", "Bundle contains a special file.")
                require(not mode & 0o6022, "unsafe_mode", "Bundle contains privileged or externally writable files.")


def tree_hash(root):
    check_tree(root)
    digest = hashlib.sha256()
    entries = [root]
    for parent, dirs, files in os.walk(str(root), followlinks=False, onerror=walk_error):
        entries.extend(Path(parent) / name for name in dirs + files)
    for item in sorted(entries, key=lambda path: str(path.relative_to(root))):
        info = item.lstat()
        name = str(item.relative_to(root))
        digest.update(json.dumps([name, stat.S_IFMT(info.st_mode), stat.S_IMODE(info.st_mode)],
                                 ensure_ascii=True).encode("ascii") + b"\0")
        if item.is_symlink():
            digest.update(os.readlink(str(item)).encode("utf-8") + b"\0")
        elif item.is_file():
            digest.update(str(info.st_size).encode("ascii") + b"\0")
            with item.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
    return digest.hexdigest()


def witness(path):
    info = path.lstat()
    require(stat.S_ISDIR(info.st_mode), "ownership_changed", "Expected a real owned bundle directory.")
    return {"device": info.st_dev, "inode": info.st_ino}


def matches_witness(path, expected):
    return exists(path) and not path.is_symlink() and witness(path) == expected


def signature_details(data, expected_id):
    text = data.decode("utf-8", "strict")
    fields = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            require(key not in fields, "signature", "Ambiguous codesign metadata.")
            fields[key] = value
    require(fields.get("Identifier") == expected_id and fields.get("Signature") == "adhoc"
            and fields.get("TeamIdentifier") == "not set" and "Authority" not in fields,
            "signature", "Expected the exact Jones ad-hoc identity, with no signing team or authority.")
    require(re.fullmatch(r"[0-9a-fA-F]{40,64}", fields.get("CDHash", "")) is not None,
            "signature", "codesign did not report a valid code-directory hash.")
    require(re.fullmatch(r"2 rules=[0-9]+ files=[0-9]+", fields.get("Sealed Resources version", "")) is not None,
            "signature", "Expected a sealed version-2 resource envelope.")
    return fields["CDHash"].lower()


PROCESS_SCRIPT = r'''
ObjC.import('AppKit');
function run(argv) {
    var target = argv[0], ident = argv[1], action = argv[2], rows = [], matches = [];
    var apps = $.NSWorkspace.sharedWorkspace.runningApplications;
    for (var i = 0; i < apps.count; i++) {
        var app = apps.objectAtIndex(i);
        var id = ObjC.unwrap(app.bundleIdentifier) || '';
        var url = app.bundleURL;
        var path = url.isNil() ? '' : (ObjC.unwrap(url.path) || '');
        if (id !== ident && path !== target) continue;
        var exe = app.executableURL;
        var row = {pid: Number(app.processIdentifier), bundle_id: id, bundle_path: path,
                   executable_path: exe.isNil() ? '' : (ObjC.unwrap(exe.path) || '')};
        rows.push(row);
        matches.push(app);
    }
    if (action === 'quit') {
        if (rows.length > 1) throw Error('Multiple matching processes; no quit sent.');
        for (var j = 0; j < rows.length; j++) {
            if (rows[j].bundle_path !== target || rows[j].bundle_id !== ident ||
                rows[j].executable_path !== target + '/Contents/MacOS/CodexBar')
                throw Error('Another Jones copy is running; no quit sent.');
        }
        for (var k = 0; k < matches.length; k++) rows[k].accepted = Boolean(matches[k].terminate);
    }
    return JSON.stringify(rows);
}
'''


class MacOperations:
    """Bounded public bundle metadata/process operations; no provider or defaults access."""

    def __init__(self, signing_mode="adhoc"):
        self.signing_mode = signing_mode
        require(sys.platform == "darwin", "platform",
                "Installation/preflight requires macOS; portable tests use fakes.")

    def run(self, arguments, timeout=60):
        try:
            result = subprocess.run(arguments, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise InstallError("native_command", "Native command failed or timed out: " + arguments[0]) from error
        require(result.returncode == 0, "native_command",
                "Native command refused the operation: " + arguments[0] + "; "
                + result.stderr.decode("utf-8", "replace")[-500:])
        return result

    def verify_signature(self, bundle, identifier):
        if read_plist(bundle / "Contents/Info.plist").get("JonesSigningMode") == "developer-id":
            try:
                return _SIGNING_MODULE.verify_bundle(bundle, identifier, distribution=identifier == BUNDLE_ID)
            except _SIGNING_MODULE.SigningError as error:
                raise InstallError("signature", str(error)) from error
        self.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)])
        displayed = self.run(["/usr/bin/codesign", "--display", "--verbose=4", str(bundle)])
        seal = signature_details(displayed.stderr, identifier)
        signed = self.run(["/usr/bin/codesign", "--display", "--entitlements", ":-", str(bundle)])
        try:
            entitlements = plistlib.loads(signed.stdout)
        except (ValueError, plistlib.InvalidFileException, ExpatError) as error:
            raise InstallError("entitlements", "Cannot decode signed entitlements; no install attempted.") from error
        require(isinstance(entitlements, dict), "entitlements", "Signed entitlements must be a dictionary.")
        return seal, entitlements

    def architectures(self, executable):
        return self.run(["/usr/bin/lipo", "-archs", str(executable)]).stdout.decode("ascii").split()

    def quarantine(self, root):
        paths = [root]
        if root.is_dir():
            for parent, dirs, files in os.walk(str(root), followlinks=False, onerror=walk_error):
                paths.extend(Path(parent) / name for name in dirs + files)
        for path in paths:
            try:
                attributes = list_xattrs(path)
            except OSError as error:
                raise InstallError("quarantine_unknown", "Cannot inspect quarantine metadata: " + str(path)) from error
            require("com.apple.quarantine" not in attributes, "quarantine",
                    "Quarantine is present. Use the approved native distribution/consent route; "
                    "this helper never removes it.")

    def available(self, path):
        info = os.statvfs(str(path))
        return info.f_bavail * info.f_frsize

    def clone(self, source, destination):
        self.run(["/usr/bin/ditto", str(source), str(destination)], timeout=180)

    def processes(self, target, action="inspect"):
        result = self.run(["/usr/bin/osascript", "-l", "JavaScript", "-e", PROCESS_SCRIPT,
                           str(target), BUNDLE_ID, action], timeout=20)
        try:
            rows = json.loads(result.stdout)
        except ValueError as error:
            raise InstallError("process_unknown", "Cannot establish running bundle identity.") from error
        require(isinstance(rows, list), "process_unknown", "Invalid process identity response.")
        return rows

    def launch(self, target):
        self.run(["/usr/bin/open", "-n", "-a", str(target)], timeout=30)

    def pause(self):
        time.sleep(0.5)

    def checkpoint(self, _phase):
        pass


def inspect_bundle(path, operations, expected_revision=None, allow_legacy=False):
    check_tree(path)
    operations.quarantine(path)
    info = read_plist(path / "Contents/Info.plist")
    signing_mode = info.get("JonesSigningMode", "adhoc")
    require(signing_mode in ("adhoc", "developer-id"), "identity", "Unknown signing mode.")
    production = signing_mode == "developer-id"
    require(not production or getattr(operations, "signing_mode", "adhoc") == "developer-id",
            "signing_mode", "Developer ID candidates require explicit --signing-mode developer-id.")
    identity = dict(IDENTITY)
    if production:
        identity.update(CodexBarTeamID=_SIGNING_MODULE.TEAM, JonesAppGroupID=_SIGNING_MODULE.GROUP)
        require(info.get("JonesUpdateChannel") == "none" and info.get("SUFeedURL") == ""
                and info.get("SUPublicEDKey") == ""
                and all(info.get(key) is False for key in
                        ("SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates")),
                "migration_held", "Developer ID automatic updates remain held.")
    require(all(info.get(key) == value for key, value in identity.items()), "identity",
            "Bundle identity, group, iCloud metadata, state, display name, or team differs from Jones production.")
    require(not any(key.startswith("JonesUpdateHarness") for key in info),
            "identity", "An update harness cannot be installed as the owner app.")
    require(info.get("CFBundleExecutable") == "CodexBar", "identity", "Unexpected main executable.")
    build = info.get("CFBundleVersion")
    revision = info.get("JonesSourceRevision")
    for key in ("JonesBuildRun", "JonesBuildOrigin", "JonesUpdateChannel"):
        value = info.get(key)
        require(value is None or (isinstance(value, str) and len(value) <= 256), "provenance",
                "Invalid or oversized provenance field: " + key)
    legacy = allow_legacy and not production and revision is None and build == "135"
    if not legacy:
        require(isinstance(build, str) and BUILD_RE.fullmatch(build) is not None, "build",
                "Expected the monotonic <BUILD_NUMBER>.<first-parent-count> bundle version.")
        require(isinstance(revision, str) and SHA_RE.fullmatch(revision) is not None, "provenance",
                "A complete lowercase 40-hex JonesSourceRevision is required.")
        require(info.get("JonesBuildOrigin") == "ci-main" and isinstance(info.get("JonesBuildRun"), str)
                and RUN_RE.fullmatch(info["JonesBuildRun"]) is not None, "provenance",
                "Only canonical-main CI candidates with a canonical run URL may be installed.")
        require(info.get("JonesUpdateChannel") in ("none", "stable"), "provenance",
                "JonesUpdateChannel must explicitly identify the bootstrap or stable channel.")
    require(expected_revision is None or revision == expected_revision, "revision",
            "Source revision does not match --expect-revision.")
    require(isinstance(info.get("CFBundleShortVersionString"), str)
            and len(info["CFBundleShortVersionString"]) <= 64
            and re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", info["CFBundleShortVersionString"]) is not None,
            "version", "Missing or invalid dotted display version.")
    main_seal, main_entitlements = operations.verify_signature(path, BUNDLE_ID)
    expected_app = (_SIGNING_MODULE.entitlements(BUNDLE_ID) if production
                    else {"com.apple.security.application-groups": [GROUP_ID]})
    require(main_entitlements == expected_app, "entitlements",
            "Signed app entitlements differ from the exact selected signing-mode contract.")
    executable = path / "Contents/MacOS/CodexBar"
    require(executable.is_file() and not executable.is_symlink() and os.access(str(executable), os.X_OK),
            "executable", "Missing real executable with execute permission.")
    require(operations.architectures(executable) == ["arm64"], "architecture",
            "This local installer requires an arm64-only bundle.")
    widget = path / "Contents/PlugIns/CodexBarWidget.appex"
    widget_info = read_plist(widget / "Contents/Info.plist")
    widget_identity = dict(identity)
    if production:
        widget_identity["JonesSigningMode"] = "developer-id"
    widget_identity.pop("CFBundleDisplayName")
    widget_identity["CFBundleIdentifier"] = BUNDLE_ID + ".widget"
    require(all(widget_info.get(key) == value for key, value in widget_identity.items())
            and widget_info.get("CFBundleVersion") == build, "widget_identity",
            "Widget identity or build does not match the app.")
    widget_executable = widget_info.get("CFBundleExecutable")
    require(widget_executable == "CodexBarWidget", "widget_identity", "Unexpected widget executable.")
    widget_binary = widget / "Contents/MacOS/CodexBarWidget"
    require(widget_binary.is_file() and not widget_binary.is_symlink() and os.access(str(widget_binary), os.X_OK),
            "executable", "Missing real widget executable with execute permission.")
    widget_seal, widget_entitlements = operations.verify_signature(widget, BUNDLE_ID + ".widget")
    expected_widget = (_SIGNING_MODULE.entitlements(BUNDLE_ID + ".widget") if production else
                       {"com.apple.security.app-sandbox": True, "com.apple.security.application-groups": [GROUP_ID]})
    require(widget_entitlements.get("com.apple.security.app-sandbox") is True
            and widget_entitlements == expected_widget,
            "entitlements", "Unexpected signed widget entitlements.")
    require(operations.architectures(widget_binary) == ["arm64"],
            "architecture", "This local installer requires an arm64-only widget.")
    return {
        "identity": identity, "version": info["CFBundleShortVersionString"], "build": build,
        "revision": revision, "origin": info.get("JonesBuildOrigin"), "run": info.get("JonesBuildRun"),
        "channel": info.get("JonesUpdateChannel"), "legacy_build_135": legacy,
        "architecture": "arm64", "seal": main_seal, "widget_seal": widget_seal,
        "entitlements": main_entitlements, "widget_entitlements": widget_entitlements,
        "tree_sha256": tree_hash(path),
    }


def record_bundle(path, operations, expected_revision=None, allow_legacy=False):
    return {"directory": witness(path), "bundle": inspect_bundle(path, operations, expected_revision, allow_legacy)}


def verify_record(path, record, operations):
    require(isinstance(record, dict) and set(record) == {"directory", "bundle"},
            "manifest", "Invalid bundle ownership record.")
    require(matches_witness(path, record["directory"]), "ownership_changed",
            "Recorded bundle directory has changed: " + str(path))
    require(inspect_bundle(path, operations, allow_legacy=True) == record["bundle"],
            "bundle_changed", "Recorded bundle bytes or signed identity have changed: " + str(path))


def newer(candidate, current):
    require(candidate["identity"].get("CodexBarTeamID") == current["identity"].get("CodexBarTeamID"), "migration_held",
            "Cross-team app-group transition is held pending validated migration and owner bootstrap.")
    new = tuple(int(part) for part in candidate["build"].split("."))
    old = tuple(int(part) for part in current["build"].split("."))
    old = old + (0,) * (len(new) - len(old))
    require(new > old, "not_newer", "Candidate build is equal or lower; only explicit --restore permits a downgrade.")
    require(candidate["identity"] == current["identity"]
            and candidate["entitlements"] == current["entitlements"]
            and candidate["widget_entitlements"] == current["widget_entitlements"],
            "identity_drift", "Installed and candidate identity/entitlements differ; no swap is permitted.")


def archive_layout(archive):
    entries = archive.infolist()
    require(0 < len(entries) <= MAX_ENTRIES, "archive_layout", "Archive entry count is outside the supported bound.")
    nodes, folded, roots, total = {}, {}, set(), 0
    for entry in entries:
        name = entry.filename.rstrip("/")
        parts = name.split("/")
        require(name and not entry.filename.startswith("/") and "\\" not in name and ":" not in name
                and all(part not in ("", ".", "..") for part in parts)
                and all(ord(char) >= 32 and ord(char) != 127 for char in name),
                "archive_path", "Archive has an unsafe path.")
        require(entry.orig_filename == entry.filename, "archive_path", "Archive contains a NUL-truncated name.")
        roots.add(parts[0])
        key = unicodedata.normalize("NFC", name).casefold()
        require(key not in folded and name not in nodes, "archive_path",
                "Archive has duplicate or case/Unicode-colliding paths.")
        folded[key] = name
        mode = entry.external_attr >> 16
        kind = stat.S_IFMT(mode)
        require(kind in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK),
                "archive_type", "Archive contains a special file.")
        require(not entry.flag_bits & 1 and entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
                "archive_type", "Encrypted or unsupported-compression archive.")
        is_link = kind == stat.S_IFLNK
        is_directory = entry.is_dir()
        require((kind != stat.S_IFDIR or is_directory) and not (is_link and is_directory),
                "archive_type", "Archive file type disagrees with its path.")
        require(is_link or not mode & 0o6022, "archive_mode", "Archive contains unsafe permission bits.")
        total += entry.file_size
        require(0 <= entry.file_size <= MAX_EXPANDED and total <= MAX_EXPANDED,
                "archive_size", "Expanded archive exceeds 1 GiB.")
        nodes[name] = (entry, "link" if is_link else "dir" if is_directory else "file")
    require(len(roots) == 1 and next(iter(roots)) in ("CodexBar.app", "CodexBar Jones.app"),
            "archive_layout", "Expected one top-level CodexBar.app or CodexBar Jones.app, "
            "with no siblings or AppleDouble entries.")
    root = next(iter(roots))
    for name in nodes:
        for parent in PurePosixPath(name).parents:
            if str(parent) == ".":
                continue
            if str(parent) in nodes:
                require(nodes[str(parent)][1] == "dir", "archive_path", "An archive entry traverses a file or symlink.")
            normalized = unicodedata.normalize("NFC", str(parent)).casefold()
            require(normalized not in folded or folded[normalized] == str(parent),
                    "archive_path", "Archive parent paths collide on macOS.")
            folded[normalized] = str(parent)
    for name, (entry, kind) in nodes.items():
        if kind == "link":
            require(entry.file_size <= 4096, "archive_link", "Oversized symlink target.")
            try:
                destination = archive.read(entry).decode("utf-8")
            except (ValueError, UnicodeError) as error:
                raise InstallError("archive_link", "Invalid symlink target.") from error
            require(destination and not destination.startswith("/") and "\\" not in destination
                    and ":" not in destination and "\0" not in destination,
                    "archive_link", "Unsafe absolute or malformed symlink target.")
            joined = os.path.normpath(str(PurePosixPath(name).parent / destination))
            require(joined == root or joined.startswith(root + "/"), "archive_link", "Symlink target escapes the app.")
    return root, nodes, total


def extract_archive(archive, root, nodes, destination):
    # Create links last; no archive pathname is ever extracted through a link.
    for name, (entry, kind) in sorted(nodes.items(), key=lambda item: (item[0].count("/"), item[0])):
        if kind == "link":
            continue
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if kind == "dir":
            path.mkdir(exist_ok=True)
            os.chmod(str(path), (entry.external_attr >> 16) & 0o777 or 0o755)
        else:
            with archive.open(entry) as source, path.open("xb") as target:
                shutil.copyfileobj(source, target, 1024 * 1024)
            os.chmod(str(path), (entry.external_attr >> 16) & 0o777 or 0o644)
    for name, (entry, kind) in nodes.items():
        if kind == "link":
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(archive.read(entry).decode("utf-8"), str(path))
    check_tree(destination / root)


def json_file(path):
    require(path.is_file() and not path.is_symlink(), "manifest", "Expected a regular installer metadata file.")
    info = path.stat()
    require(info.st_uid == os.getuid() and info.st_nlink == 1 and not info.st_mode & 0o077
            and info.st_size <= 256 * 1024, "manifest", "Installer metadata ownership, permissions, or size is unsafe.")
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_json_object)
    except (ValueError, UnicodeError) as error:
        raise InstallError("manifest", "Malformed installer metadata; reconcile it before retrying.") from error
    require(isinstance(value, dict), "manifest", "Installer metadata must be an object.")
    return value


def unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "manifest", "Duplicate keys make installer metadata ambiguous.")
        result[key] = value
    return result


def sync_directory(path):
    descriptor = os.open(str(path), os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_json(path, value):
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        descriptor = os.open(str(temporary), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(str(temporary), str(path))
        sync_directory(path.parent)
    finally:
        if exists(temporary):
            temporary.unlink()


class State:
    def __init__(self, target):
        self.target = target
        suffix = hashlib.sha256(str(target).encode("utf-8")).hexdigest()[:16]
        self.root = target.parent / (".codexbar-jones-install-" + suffix + ".noindex")
        self.owner = {"schema": STATE_SCHEMA, "target": str(target), "uid": os.getuid(), "bundle_id": BUNDLE_ID}

    def load(self, operations):
        if not exists(self.root):
            return None
        info = self.root.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid() and not info.st_mode & 0o077,
                "unknown_state", "Recovery directory is not owned private installer storage; leave it untouched.")
        require(json_file(self.root / "owner.json") == self.owner,
                "unknown_state", "Recovery owner/target binding differs.")
        require(not exists(self.root / "journal.json"), "pending_transaction",
                "A pending transaction exists. Do not rerun or delete it; reconcile its exact paths and effects first.")
        manifest_path = self.root / "manifest.json"
        manifest = json_file(manifest_path) if exists(manifest_path) else None
        allowed = {"owner.json", "lock"}
        if manifest is not None:
            require(set(manifest) == {"schema", "target", "transaction", "current", "previous", "retired"}
                    and manifest["schema"] == STATE_SCHEMA and manifest["target"] == str(self.target)
                    and re.fullmatch(r"[0-9a-f]{32}", str(manifest["transaction"])) is not None
                    and manifest["retired"] == [], "manifest", "Unknown or unfinished recovery manifest.")
            allowed.add("manifest.json")
            verify_record(self.target, manifest["current"], operations)
            previous = manifest["previous"]
            if previous is not None:
                require(isinstance(previous, dict) and set(previous) == {"name", "record"}
                        and isinstance(previous["name"], str) and PREVIOUS_RE.fullmatch(previous["name"]) is not None,
                        "manifest", "Invalid owned previous-bundle path.")
                allowed.add(previous["name"])
                verify_record(self.root / previous["name"], previous["record"], operations)
        require(set(item.name for item in self.root.iterdir()) == allowed,
                "unknown_state", "Recovery storage has missing or unowned entries; no automatic cleanup is allowed.")
        return manifest

    @contextmanager
    def lock(self, create=False):
        if not exists(self.root):
            if not create:
                yield
                return
            self.target.parent.mkdir(parents=True, exist_ok=True)
            self.root.mkdir(mode=0o700)
            atomic_json(self.root / "owner.json", self.owner)
            descriptor = os.open(str(self.root / "lock"), os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
        else:
            descriptor = os.open(str(self.root / "lock"), os.O_RDONLY | os.O_NOFOLLOW)
        try:
            info = os.fstat(descriptor)
            require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_nlink == 1
                    and not info.st_mode & 0o077, "unknown_state", "Unsafe installer lock file.")
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                raise InstallError("busy", "Another installer owns this target; wait for it to finish.") from error
            yield
        finally:
            os.close(descriptor)

    def journal(self, payload, phase, operations):
        journal = self.root / "journal.json"
        if phase == "staging":
            require(not exists(journal), "pending_transaction", "A journal appeared before staging; preserve it.")
        else:
            previous = json_file(journal)
            require(previous.get("transaction") == payload["transaction"]
                    and previous.get("target") == payload["target"] and previous.get("schema") == STATE_SCHEMA,
                    "unknown_state", "The journal no longer belongs to this invocation; preserve it.")
        payload["phase"] = phase
        atomic_json(journal, payload)
        operations.checkpoint(phase)


def process_rows(operations, target, action="inspect"):
    rows = operations.processes(target, action)
    for row in rows:
        require(isinstance(row, dict) and type(row.get("pid")) is int and row["pid"] > 0,
                "process_unknown", "Running process identity is incomplete.")
        require(row.get("bundle_id") == BUNDLE_ID and row.get("bundle_path") == str(target)
                and row.get("executable_path") == str(target / "Contents/MacOS/CodexBar"),
                "other_running_copy", "A foreign or other-location Jones process is running; "
                "close that exact copy normally first.")
    require(len(rows) <= 1, "process_unknown",
            "Multiple target processes are running; close them normally before installation.")
    return rows


def graceful_quit(operations, target):
    if not process_rows(operations, target):
        return
    process_rows(operations, target, "quit")
    for _ in range(40):
        if not process_rows(operations, target):
            return
        operations.pause()
    raise InstallError("still_running", "The exact Jones app is still running after graceful quit. "
                       "Finish its interaction and quit normally.")


def capacity(operations, parent, required):
    available = operations.available(parent)
    require(type(available) is int and available >= 0, "capacity_unknown",
            "Cannot establish available bytes on the target volume.")
    require(available >= required, "capacity", "Insufficient target-volume space; required bytes: " + str(required))
    require(os.access(str(parent), os.W_OK | os.X_OK), "read_only",
            "Target location is not writable; choose your own Applications folder.")
    return available


@contextmanager
def cancellation_handlers(ignore=False):
    previous = {}

    def cancelled(signum, _frame):
        raise InstallError("cancelled", "Installer cancelled; known uncommitted changes are recovered. "
                           "Committed installs require explicit inspection.",
                           128 + signum)

    try:
        for number in SIGNALS:
            previous[number] = signal.signal(number, signal.SIG_IGN if ignore else cancelled)
        yield
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)


def remove_owned(path, expected):
    require(matches_witness(path, expected), "ownership_changed",
            "Refusing cleanup of a changed directory: " + str(path))
    shutil.rmtree(str(path))
    require(not exists(path), "cleanup", "Owned directory cleanup failed: " + str(path))


@contextmanager
def deferred_cancellation():
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, SIGNALS)
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)


@contextmanager
def owned_scratch(parent):
    root, identity, original = None, None, None
    try:
        with deferred_cancellation():
            root = Path(tempfile.mkdtemp(prefix=".jones-install-preflight-", suffix=".noindex", dir=str(parent)))
            identity = witness(root)
        yield root
    except BaseException as error:
        original = error
        raise
    finally:
        if root is not None and identity is not None:
            with cancellation_handlers(ignore=True):
                try:
                    remove_owned(root, identity)
                except BaseException as cleanup:
                    message = "Owned scratch cleanup failed; preserve/reconcile this exact path: " + str(root)
                    if isinstance(original, InstallError):
                        original.details["scratch_cleanup_error"] = message
                    elif original is not None:
                        print(json.dumps({"code": "scratch_cleanup", "message": message}), file=sys.stderr)
                    else:
                        raise InstallError("scratch_cleanup", message, 3) from cleanup


def transaction(state, operations, manifest, current, source, candidate, restoring=False):
    token = uuid.uuid4().hex
    stage = source if restoring else state.root / ("stage-" + token + ".app")
    backup = state.root / ("previous-" + token + ".app")
    payload = {"schema": STATE_SCHEMA, "transaction": token, "target": str(state.target),
               "action": "restore" if restoring else "install", "source": str(stage), "backup": str(backup),
               "before": current, "manifest_before": manifest, "candidate": candidate}
    stage_witness = witness(stage) if restoring else None
    new_manifest = None
    committed = False
    try:
        state.journal(payload, "staging", operations)
        if not restoring:
            with deferred_cancellation():
                stage.mkdir(mode=0o755)
                stage_witness = witness(stage)
            operations.clone(source, stage)
        staged = record_bundle(stage, operations, allow_legacy=restoring)
        require(staged["bundle"] == candidate, "copy_changed", "Staged bundle does not match the verified candidate.")
        require(witness(stage)["device"] == state.target.parent.stat().st_dev,
                "volume", "Staging and target are on different volumes.")
        payload["staged"] = staged
        state.journal(payload, "prepared", operations)
        graceful_quit(operations, state.target)
        if current is not None:
            verify_record(state.target, current, operations)
        else:
            require(not exists(state.target), "target_changed", "A target appeared after preflight.")
        require(not exists(backup), "unknown_state", "Reserved backup path already exists.")
        state.journal(payload, "will_move_previous", operations)
        if current is not None:
            os.rename(str(state.target), str(backup))
            sync_directory(state.target.parent)
        state.journal(payload, "will_install", operations)
        require(not exists(state.target), "target_changed", "Target unexpectedly reappeared; no overwrite allowed.")
        os.rename(str(stage), str(state.target))
        sync_directory(state.target.parent)
        state.journal(payload, "installed_uncommitted", operations)
        verify_record(state.target, staged, operations)
        previous = {"name": backup.name, "record": current} if current is not None else None
        retired = [] if restoring or manifest is None or manifest["previous"] is None else [manifest["previous"]]
        new_manifest = {"schema": STATE_SCHEMA, "target": str(state.target), "transaction": token,
                        "current": staged, "previous": previous, "retired": retired}
        state.journal(payload, "will_commit", operations)
        atomic_json(state.root / "manifest.json", new_manifest)
        committed = True
        state.journal(payload, "committed", operations)
        # Only records inherited from the validated old manifest authorize retirement.
        for old in retired:
            path = state.root / old["name"]
            verify_record(path, old["record"], operations)
            remove_owned(path, old["record"]["directory"])
        new_manifest["retired"] = []
        atomic_json(state.root / "manifest.json", new_manifest)
        (state.root / "journal.json").unlink()
        sync_directory(state.root)
        operations.checkpoint("complete")
        return new_manifest
    except BaseException as original:
        with cancellation_handlers(ignore=True):
            try:
                if not committed and new_manifest is not None and exists(state.root / "manifest.json"):
                    committed = json_file(state.root / "manifest.json") == new_manifest
                if committed:
                    raise InstallError("committed_needs_reconciliation",
                                       "Bundle replacement committed, but completion failed. "
                                       "Preserve recovery storage and reconcile it; no automatic rollback/retry.",
                                       3, target=str(state.target)) from original
                # In-process recovery uses captured directory identities, never a journal from a prior invocation.
                if stage_witness is not None and matches_witness(state.target, stage_witness):
                    require(not exists(stage), "rollback_unknown", "Both stage and target exist; effect is unknown.")
                    require(not process_rows(operations, state.target), "rollback_running",
                            "A replaced bundle is now running; no automatic rollback.")
                    verify_record(state.target, staged, operations)
                    os.rename(str(state.target), str(stage))
                if current is not None and exists(backup):
                    verify_record(backup, current, operations)
                    require(not exists(state.target), "rollback_unknown",
                            "Target is occupied; preserve both copies for reconciliation.")
                    os.rename(str(backup), str(state.target))
                if current is not None:
                    verify_record(state.target, current, operations)
                else:
                    require(not exists(state.target), "rollback_unknown", "Unexpected first-install target remains.")
                if not restoring and stage_witness is not None and exists(stage):
                    remove_owned(stage, stage_witness)
                if restoring:
                    verify_record(stage, manifest["previous"]["record"], operations)
                manifest_path = state.root / "manifest.json"
                actual_manifest = json_file(manifest_path) if exists(manifest_path) else None
                require(actual_manifest == manifest, "rollback_unknown", "Recovery manifest changed unexpectedly.")
                sync_directory(state.target.parent)
                if exists(state.root / "journal.json"):
                    recorded = json_file(state.root / "journal.json")
                    require(recorded.get("transaction") == token and recorded.get("target") == str(state.target),
                            "rollback_unknown", "Another journal appeared; do not delete it.")
                    (state.root / "journal.json").unlink()
                sync_directory(state.root)
            except BaseException as recovery:
                if isinstance(recovery, InstallError) and recovery.code == "committed_needs_reconciliation":
                    raise
                raise InstallError("rollback_unknown", "Recovery could not prove the preimage. "
                                   "Preserve the journal and all bundles; do not retry.",
                                   3, original_error=str(original), recovery_error=str(recovery)) from recovery
        raise


def launch_installed(operations, target, expected):
    # Launch may write app data even if open/readback fails. Never roll binary bytes back after this boundary.
    try:
        operations.launch(target)
        rows = []
        for _ in range(20):
            rows = process_rows(operations, target)
            if rows:
                break
            operations.pause()
        require(rows, "launch_unverified", "No exact installed executable appeared after launch.")
        for _ in range(4):
            operations.pause()
            require(process_rows(operations, target) == rows, "launch_unverified",
                    "Installed process did not survive readback.")
        verify_record(target, expected, operations)
        return rows[0]
    except BaseException as error:
        raise InstallError("installed_launch_unverified",
                           "Replacement is committed; launch/readback failed or needs native consent. "
                           "No automatic postlaunch or data rollback. Inspect normally or choose explicit --restore.",
                           3, target=str(target), launch_error=str(error)) from error


def execute(args, operations):
    target = target_path(args.target)
    state = State(target)
    parent = nearest_directory(target.parent)
    state.load(operations)
    if args.restore:
        with state.lock():
            manifest = state.load(operations)
            require(manifest is not None and manifest["previous"] is not None, "no_previous",
                    "No completed manifest-owned previous bundle is available.")
            capacity(operations, parent, RESERVE)
            previous = manifest["previous"]
            candidate = previous["record"]["bundle"]
            require(candidate["identity"] == manifest["current"]["bundle"]["identity"], "migration_held",
                    "Restore cannot cross the legacy/Developer ID app-group boundary.")
            result = transaction(state, operations, manifest, manifest["current"], state.root / previous["name"],
                                 candidate, restoring=True)
            process = launch_installed(operations, target, result["current"])
            return {"schema": SCHEMA, "status": "restored", "target": str(target), "candidate": candidate,
                    "running": process, "previous_path": str(state.root / result["previous"]["name"])}

    require(isinstance(args.sha256, str) and HASH_RE.fullmatch(args.sha256) is not None,
            "arguments", "--sha256 must be 64 lowercase hexadecimal characters.")
    require(isinstance(args.expect_revision, str) and SHA_RE.fullmatch(args.expect_revision) is not None,
            "arguments", "--expect-revision must be the full 40-character lowercase source revision.")
    archive_path = Path(args.archive).expanduser().absolute()
    no_symlink_components(archive_path)
    require(archive_path.is_file() and not archive_path.is_symlink(),
            "archive", "Archive must be a regular local file.")
    length = archive_path.stat().st_size
    require(0 < length <= MAX_ARCHIVE, "archive_size", "Archive must be nonempty and at most 256 MiB.")
    operations.quarantine(archive_path)
    with zipfile.ZipFile(str(archive_path)) as archive:
        _, _, expanded = archive_layout(archive)
    required = length + 2 * expanded + RESERVE
    available = capacity(operations, parent, required)
    # Scratch is on the target volume, never an implicit /tmp or provider-state root.
    with owned_scratch(parent) as scratch:
        copied = scratch / "candidate.zip"
        digest = hashlib.sha256()
        written = 0
        with archive_path.open("rb") as source, copied.open("xb") as destination:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                written += len(block)
                require(written <= length, "archive_changed", "Archive grew while reading; obtain a stable artifact.")
                digest.update(block)
                destination.write(block)
        require(written == length and digest.hexdigest() == args.sha256, "hash",
                "Archive SHA-256 does not match the externally verified value.")
        operations.quarantine(archive_path)
        with zipfile.ZipFile(str(copied)) as archive:
            root_name, nodes, actual_expanded = archive_layout(archive)
            require(actual_expanded == expanded, "archive_changed", "Archive layout changed while reading.")
            extract_archive(archive, root_name, nodes, scratch)
        source = scratch / root_name
        candidate = inspect_bundle(source, operations, args.expect_revision)
        # Refusals precede creation of persistent recovery directories, even on first use.
        observed = record_bundle(target, operations, allow_legacy=True) if exists(target) else None
        if observed is not None:
            newer(candidate, observed["bundle"])
        process_rows(operations, target)
        with state.lock(create=not args.preflight):
            manifest = state.load(operations)
            current = record_bundle(target, operations, allow_legacy=True) if exists(target) else None
            require(current == observed, "target_changed", "Target changed during validation; no transaction started.")
            if current is not None:
                newer(candidate, current["bundle"])
                require(current["directory"]["device"] == parent.stat().st_dev, "volume",
                        "Target bundle is a separate mount; same-volume rename is required.")
            rows = process_rows(operations, target)
            result = {"schema": SCHEMA, "status": "preflight_ok", "target": str(target), "candidate": candidate,
                      "installed": None if current is None else current["bundle"], "archive_sha256": digest.hexdigest(),
                      "archive_bytes": length, "expanded_bytes": expanded, "required_bytes": required,
                      "available_bytes": available, "running": rows,
                      "external_provenance": "operator_verified_required"}
            if args.preflight:
                return result
            capacity(operations, state.root, expanded + RESERVE)
            completed = transaction(state, operations, manifest, current, source, candidate)
            result["running"] = launch_installed(operations, target, completed["current"])
            result["status"] = "installed"
            previous = completed["previous"]
            result["previous_path"] = None if previous is None else str(state.root / previous["name"])
            return result


def arguments(argv):
    parser = argparse.ArgumentParser(description="Preflight, install, or restore one verified local Jones app.")
    parser.add_argument("--archive")
    parser.add_argument("--sha256")
    parser.add_argument("--expect-revision")
    parser.add_argument("--target", default=str(Path.home() / "Applications/CodexBar Jones.app"))
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--signing-mode", choices=("adhoc", "developer-id"), default="adhoc")
    args = parser.parse_args(argv)
    if args.restore:
        require(not args.archive and not args.sha256 and not args.expect_revision and not args.preflight,
                "arguments", "--restore is separate from archive/preflight arguments.")
    else:
        require(bool(args.archive and args.sha256 and args.expect_revision), "arguments",
                "Supply --archive, --sha256, and --expect-revision together.")
    return args


def main(argv=None):
    try:
        with cancellation_handlers():
            args = arguments(argv)
            result = execute(args, MacOperations(args.signing_mode))
        print(json.dumps(result, sort_keys=True))
        return 0
    except InstallError as error:
        print(json.dumps({"schema": SCHEMA, "status": "refused" if error.exit_code == 2 else "failed",
                          "code": error.code, "message": str(error), **error.details}, sort_keys=True))
        return error.exit_code
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
        print(json.dumps({"schema": SCHEMA, "status": "failed", "code": "io_or_archive",
                          "message": str(error)}, sort_keys=True))
        return 3


if __name__ == "__main__":
    sys.exit(main())
