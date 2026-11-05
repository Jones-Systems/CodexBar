"""Cheap producer finalization and opt-in bounded content baselines; no disposal authority."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import stat
import subprocess
import sys
import time

# Wire behavior pinned to A1; this producer does not implement qualification.
CONTRACT_COMMIT = "d330101012fc7f020b0f72e2d5432ccd2d8ea94c"
CORPUS_SHA256 = "1880306b4c51224024cadf46c77fda5bee4661d08b6b080632883f06e6e38fc2"


class Failure(ValueError):
    def __init__(self, reason, *_args):
        self.reason = reason
        super().__init__(reason)


SCHEMA = "output-attestation/v1"
MAX_ENTRIES = 500_000
MAX_BYTES = 16 * 1024**3
MAX_SECONDS = 300


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def manifest_bytes(entries):
    return b"".join(canonical_json(entry) + b"\n" for entry in sorted(entries, key=lambda entry: entry["relpath"]))


def listing_digest(entries):
    digest = hashlib.sha256()
    for entry in sorted(entries, key=lambda entry: entry["relpath"]):
        fields = [entry["relpath"], entry["type"], str(entry["size"]), str(entry["mtime_ns"]), str(entry["mode"])]
        if entry["type"] == "symlink":
            fields.append(entry["target"])
        digest.update(("\0".join(fields) + "\n").encode("utf-8", "surrogateescape"))
    return digest.hexdigest()


def sensitive(name):
    lower = name.lower()
    return ((lower.startswith(".env") and not lower.endswith((".example", ".sample", ".template")))
            or any(fnmatch.fnmatchcase(lower, pattern) for pattern in ("*.pem", "*.key", "*.p12", "id_*", ".netrc", ".npmrc")))


def _open_relative(root_fd, relpath, flags):
    parts = relpath.split("/") if relpath else []
    parent = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
        return os.open(parts[-1], flags | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent) if parts else os.dup(parent)
    finally:
        os.close(parent)


def _snapshot(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _metadata(root_fd, deadline, max_entries, max_bytes):
    entries, snapshots, reasons, pending = [], {}, set(), [""]
    logical = allocated = 0
    while pending:
        directory = pending.pop()
        descriptor = _open_relative(root_fd, directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            with os.scandir(descriptor) as children:
                for child in children:
                    if time.monotonic() > deadline or len(entries) >= max_entries:
                        raise Failure("bound_exceeded")
                    relpath = directory + "/" + child.name if directory else child.name
                    info = child.stat(follow_symlinks=False)
                    if info.st_dev != os.fstat(root_fd).st_dev:
                        raise Failure("mount_boundary")
                    if sensitive(child.name):
                        reasons.add("sensitive_ignored")
                    if child.name == ".git":
                        # Never inspect a nested store's contents or resolve gitfiles.
                        reasons.add("nested_repository")
                    kind = ("file" if stat.S_ISREG(info.st_mode) else "directory" if stat.S_ISDIR(info.st_mode)
                            else "symlink" if stat.S_ISLNK(info.st_mode) else "special")
                    entry = dict(relpath=relpath, type=kind, size=info.st_size,
                                 mtime_ns=info.st_mtime_ns, mode=stat.S_IMODE(info.st_mode))
                    if kind == "symlink":
                        entry["target"] = os.readlink(child.name, dir_fd=descriptor)
                    elif kind == "directory" and child.name != ".git" and not sensitive(child.name):
                        pending.append(relpath)
                    elif kind == "file":
                        logical += info.st_size
                    elif kind == "special":
                        reasons.add("special_file")
                    allocated += getattr(info, "st_blocks", 0) * 512
                    entries.append(entry)
                    snapshots[relpath] = _snapshot(info)
                    if logical > max_bytes:
                        raise Failure("bound_exceeded")
        finally:
            os.close(descriptor)
    return sorted(entries, key=lambda item: item["relpath"]), snapshots, reasons, logical, allocated


def content_manifest(path, *, max_entries=MAX_ENTRIES, max_bytes=MAX_BYTES, max_seconds=MAX_SECONDS):
    """Scan protection names first, then hash regular files using no-follow FDs.

    Limits may be shortened by tests/callers, never expanded beyond C2.
    Symlink targets are recorded as text and are never opened.
    """
    if not (0 < max_entries <= MAX_ENTRIES and 0 <= max_bytes <= MAX_BYTES and 0 < max_seconds <= MAX_SECONDS):
        raise Failure("invalid_bounds", "invalid_input")
    result = dict(entries=0, logical_bytes=0, allocated_bytes=0, listing_digest=None,
                  verification="unverifiable", content_manifest_sha256=None, reasons=[])
    root_fd = None
    try:
        deadline = time.monotonic() + max_seconds
        components = Path(os.path.abspath(path)).parts
        if any(sensitive(part) for part in components):
            raise Failure("sensitive_ignored")
        if ".git" in components:
            raise Failure("nested_repository")
        anchor = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
        try:
            root_fd = _open_relative(anchor, os.path.abspath(path).lstrip("/"), os.O_RDONLY | os.O_DIRECTORY)
        finally:
            os.close(anchor)
        root_identity = _snapshot(os.fstat(root_fd))
        entries, snapshots, reasons, logical, allocated = _metadata(root_fd, deadline, max_entries, max_bytes)
        result.update(entries=len(entries), logical_bytes=logical, allocated_bytes=allocated,
                      listing_digest=listing_digest(entries), reasons=sorted(reasons))
        if reasons:
            return result, b""
        manifest = []
        for entry in entries:
            if time.monotonic() > deadline:
                raise Failure("bound_exceeded")
            item = {key: value for key, value in entry.items() if key != "mtime_ns"}
            if entry["type"] == "file":
                fd = _open_relative(root_fd, entry["relpath"], os.O_RDONLY)
                with os.fdopen(fd, "rb") as source:
                    if _snapshot(os.fstat(source.fileno())) != snapshots[entry["relpath"]]:
                        raise Failure("attestation_mismatch")
                    digest = hashlib.sha256()
                    count = 0
                    while True:
                        if time.monotonic() > deadline:
                            raise Failure("bound_exceeded")
                        block = source.read(min(1024 * 1024, entry["size"] - count + 1))
                        if not block:
                            break
                        count += len(block)
                        if count > entry["size"]:
                            raise Failure("attestation_mismatch")
                        digest.update(block)
                    if count != entry["size"] or _snapshot(os.fstat(source.fileno())) != snapshots[entry["relpath"]]:
                        raise Failure("attestation_mismatch")
                    item["sha256"] = digest.hexdigest()
            manifest.append(item)
        # Catch additions, replacements and edits during hashing; this does not
        # claim exclusion from unmanaged writers after the final observation.
        _, fresh, reasons, _, _ = _metadata(root_fd, deadline, max_entries, max_bytes)
        if fresh != snapshots or reasons or _snapshot(os.fstat(root_fd)) != root_identity or _snapshot(os.lstat(path)) != root_identity:
            raise Failure("attestation_mismatch")
        payload = manifest_bytes(manifest)
        if time.monotonic() > deadline:
            raise Failure("bound_exceeded")
        result.update(verification="content", content_manifest_sha256=hashlib.sha256(payload).hexdigest())
        return result, payload
    except (OSError, Failure) as exc:
        result["reasons"] = sorted(set(result["reasons"]) | {exc.reason if isinstance(exc, Failure) else "observation_failed"})
        return result, b""
    finally:
        if root_fd is not None:
            os.close(root_fd)


def _publish(path, payload):
    # Immutable names preserve every prior producer baseline. Sidecar appears
    # only after its manifest has been fsynced and published on the same volume.
    temporary = path.with_name("." + path.name + "." + secrets.token_hex(8))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
        os.link(temporary, path, follow_symlinks=False)
    finally:
        os.unlink(temporary)


def _read(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as source:
        before = os.fstat(source.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > limit:
            raise Failure('identity_mismatch')
        data = source.read(limit + 1)
        if len(data) > limit or _snapshot(before) != _snapshot(os.fstat(source.fileno())):
            raise Failure('identity_mismatch')
        return data


def binding(worktree):
    path = os.path.realpath(worktree)
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1')
    # Do not inherit Git location overrides into an incarnation lookup.
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE'):
        environment.pop(key, None)
    result = subprocess.check_output(
        ['git', '-C', path, 'rev-parse', '--show-toplevel', '--absolute-git-dir', '--git-common-dir'],
        env=environment, stderr=subprocess.DEVNULL, timeout=10, text=True).splitlines()
    if len(result) != 3 or os.path.realpath(result[0]) != path:
        raise Failure('identity_mismatch')
    admin = os.path.realpath(result[1])
    common = os.path.realpath(os.path.join(path, result[2]))
    root_info, admin_info = os.lstat(path), os.lstat(admin)
    value = dict(path=path, dev=root_info.st_dev, ino=root_info.st_ino, git_dir=admin,
                 git_dir_dev=admin_info.st_dev, git_dir_ino=admin_info.st_ino,
                 git_common_dir=common, admin_id=os.path.basename(admin), breadcrumb_id=None)
    provenance = Path(admin) / 'workspace-provenance.json'
    if os.path.lexists(provenance):
        record = json.loads(_read(provenance, 65536))
        breadcrumb = record.get('breadcrumb_id', record.get('incarnation_id'))
        if not isinstance(breadcrumb, str) or not breadcrumb:
            raise Failure('identity_mismatch')
        value['breadcrumb_id'] = breadcrumb
    return value


def incarnation(bound):
    keys = ('path', 'dev', 'ino', 'git_dir', 'git_dir_dev', 'git_dir_ino', 'git_common_dir', 'breadcrumb_id')
    return hashlib.sha256(canonical_json({key: bound[key] for key in keys})).hexdigest()


@contextmanager
def mutation_guard(bound):
    # Same store and transaction order as A1. Any row, including malformed or
    # stale-holder evidence, refuses before producer/publication effects.
    directory = Path(bound['git_common_dir']) / 'workspace-lifecycle'
    directory.mkdir(mode=0o700, exist_ok=True)
    if directory.is_symlink():
        raise Failure('reservation_unverifiable')
    path = directory / 'reservations.sqlite3'
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise Failure('reservation_unverifiable')
    finally:
        os.close(fd)
    connection = sqlite3.connect(str(path), timeout=0)
    try:
        connection.execute('BEGIN IMMEDIATE')
        ddl = 'CREATE TABLE reservations (admin_id TEXT PRIMARY KEY, incarnation TEXT NOT NULL, record TEXT NOT NULL)'
        version = connection.execute('PRAGMA user_version').fetchone()[0]
        tables = connection.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
        if version == 0 and not tables:
            connection.execute(ddl)
            connection.execute('PRAGMA user_version=1')
        elif (version != 1 or connection.execute(
                "SELECT sql FROM sqlite_master WHERE name='reservations'").fetchone() != (ddl,)):
            raise Failure('reservation_unverifiable')
        if connection.execute('SELECT 1 FROM reservations WHERE admin_id=?', (bound['admin_id'],)).fetchone():
            raise Failure('retiring')
        yield
        connection.commit()
    finally:
        connection.close()


def output_directory(bound):
    directory = Path(bound['git_dir']) / 'workspace-outputs'
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
        raise Failure('attestation_unverifiable')
    return directory


def sync_directory(directory):
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def attest(path, producer, bound, status, started_at, *, drain_proved=True, capture_content=False):
    with mutation_guard(bound):
        return _attest(path, producer, bound, status, started_at,
                       drain_proved=drain_proved, capture_content=capture_content)


def _attest(path, producer, bound, status, started_at, *, drain_proved=True, capture_content=False):
    if re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,23}', producer) is None:
        raise Failure('invalid_producer')
    if status not in ('succeeded', 'failed', 'cancelled'):
        raise Failure('invalid_status')
    path = os.path.abspath(path)
    if path in (bound['path'], bound['git_dir'], bound['git_common_dir'], '/'):
        raise Failure('invalid_output_root')
    if binding(bound['path']) != bound:
        raise Failure('identity_mismatch')
    if drain_proved and capture_content:
        observation, payload = content_manifest(path)
    else:
        observation = dict(entries=0, logical_bytes=0, allocated_bytes=0, listing_digest=None,
                           verification='unverifiable', content_manifest_sha256=None,
                           reasons=['content_capture_deferred' if drain_proved else 'owned_child_drain_unproved'])
        payload = b''
    if binding(bound['path']) != bound:
        raise Failure('identity_mismatch')
    directory = output_directory(bound)
    output_id = producer + '-' + secrets.token_hex(16)
    manifest = directory / (output_id + '.manifest.jsonl')
    sidecar = directory / (output_id + '.json')
    if observation['verification'] == 'content':
        _publish(manifest, payload)
    record = dict(schema=SCHEMA, producer=producer, producer_version='1', id=output_id,
                  incarnation=dict(bound, id=incarnation(bound)), roots=[dict(path=path, **observation)],
                  status=status, started_at=started_at, finished_at=now(),
                  manifest=manifest.name if observation['verification'] == 'content' else None)
    _publish(sidecar, canonical_json(record) + b'\n')
    sync_directory(directory)
    return {**record, 'sidecar': str(sidecar)}


def now():
    return datetime.now(timezone.utc).isoformat()


class Producer:
    """Durable obligation before launch; immutable finalization after owned drain.

    Retained roots belong to the invoking producer/handoff. No deletion or
    registry allocation is implied. Interrupted writers leave the obligation.
    """
    def __init__(self, worktree, producer, roots):
        self.bound = binding(worktree)
        self.producer = producer
        self.roots = list(dict.fromkeys(os.path.abspath(root) for root in roots))
        self.started = now()
        self.directory = output_directory(self.bound)
        self.obligation = self.directory / (producer + '-' + secrets.token_hex(16) + '.obligation.json')
        with mutation_guard(self.bound):
            if binding(worktree) != self.bound:
                raise Failure('identity_mismatch')
            _publish(self.obligation, canonical_json(dict(
                schema='codexbar-output-obligation/v1', owner=producer, roots=self.roots,
                incarnation=dict(self.bound, id=incarnation(self.bound)), started_at=self.started,
                reason='producer_unfinalized')) + b'\n')
            sync_directory(self.directory)

    def finish(self, status, drain_proved):
        with mutation_guard(self.bound):
            if binding(self.bound['path']) != self.bound:
                raise Failure('identity_mismatch')
            records = []
            for root in self.roots:
                # Missing roots are disposed only after a proved drain. Dangling
                # symlinks are observations, not absence; they remain unverifiable.
                try:
                    os.lstat(root)
                    absent = False
                except FileNotFoundError:
                    absent = True
                if drain_proved and absent:
                    records.append(dict(path=root, disposition='disposed', reason='output_absent'))
                    continue
                record = _attest(root, self.producer, self.bound, status, self.started, drain_proved=drain_proved)
                records.append(dict(path=root, sidecar=record['sidecar'], disposition='retained' if drain_proved
                                    else 'unresolved', owner=self.producer,
                                    reason='producer_handoff_or_reuse' if drain_proved else 'owned_child_drain_unproved'))
            # Keep the initial obligation as immutable history. Its create-only
            # resolution names every sidecar; an interrupted publish never clears it.
            resolution = self.obligation.with_suffix('.resolved.json')
            _publish(resolution, canonical_json(dict(schema='codexbar-output-finalization/v1',
                     obligation=self.obligation.name, status=status, drain_proved=drain_proved,
                     roots=records, finished_at=now())) + b'\n')
            sync_directory(self.directory)
            print(f'workspace outputs: {resolution}', file=sys.stderr, flush=True)
            return resolution


def terminal_status(result, error=None):
    if isinstance(error, (KeyboardInterrupt, SystemExit)) or (result is not None and (result < 0 or result in (129, 130, 143))):
        return 'cancelled'
    return 'succeeded' if result == 0 and error is None else 'failed'


def finalize(producer, result, drain_proved, error=None):
    """Optional producer evidence never changes the command outcome."""
    if producer is None:
        return result
    try:
        producer.finish(terminal_status(result, error), drain_proved)
        return result
    except Exception as failure:
        print(f'Workspace finalization unresolved: {type(failure).__name__}: {failure}; '
              f'obligation={producer.obligation}', file=sys.stderr, flush=True)
        return result


def begin(worktree, producer, roots):
    try:
        return Producer(worktree, producer, roots)
    except Exception as error:
        print(f'Workspace evidence unavailable: {type(error).__name__}: {error}; '
              f'owner={producer}', file=sys.stderr, flush=True)
        return None

def begin_command(command, producer, kind='swift'):
    try:
        worktree, roots = command_roots(command, kind)
        return begin(worktree, producer, roots)
    except Exception as error:
        print(f'Workspace output discovery unavailable: {type(error).__name__}: {error}; '
              f'owner={producer}', file=sys.stderr, flush=True)
        return None


def command_roots(command, kind='swift'):
    # Capture only producer-owned destinations, never hash shared native caches,
    # security/config stores, a package source root or the global temp directory.
    selected = {}
    options = ({'--package-path', '--scratch-path', '--xunit-output', '--event-stream-output-path'}
               if kind == 'swift' else {'-derivedDataPath', '-archivePath', '-resultBundlePath', '-resultStreamPath'})
    args = iter(command[1:])
    for arg in args:
        key, equal, value = arg.partition('=')
        if key in options:
            selected[key] = Path(value if equal else next(args))
    if kind == 'swift':
        package = selected.pop('--package-path', Path.cwd()).absolute()
        for candidate in (package, *package.parents):
            if (candidate / 'Package.swift').is_file():
                package = candidate
                break
        roots = [selected.pop('--scratch-path', package / '.build'), *selected.values()]
        return package, roots
    return Path.cwd(), list(selected.values())


def run_package(worktree, command):
    import ci_swift_test_by_suite as runner
    producer = begin(worktree, 'package-app', [Path(worktree) / '.build', Path(worktree) / 'CodexBar.app'])
    if not hasattr(os, 'waitid'):
        # Preserve packaging on older Python builds. The pre-launch obligation
        # remains unresolved: exec cannot prove a terminal outcome or drain.
        print('Workspace package drain unavailable: Python os.waitid missing; '
              'owner=package-app, finalization remains unresolved', file=sys.stderr, flush=True)
        os.execvp(command[0], command)
    result = None
    try:
        result = runner._run_command(command)
        return result if result >= 0 else 128 - result
    finally:
        finalize(producer, result, runner._scratch_cleanup_safe, sys.exc_info()[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-root', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('a package command is required')
    return run_package(args.package_root, command)


if __name__ == '__main__':
    sys.exit(main())
