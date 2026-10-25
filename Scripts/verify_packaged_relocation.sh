#!/usr/bin/env bash
set -euo pipefail
# Python owns the scratch and unreaped direct-child lifecycle; no normal app launch.
exec python3 - "$@" <<'PY'
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time

MARKER = "CODEXBAR_RESOURCE_SMOKE_OK"
MISSING = ("RESOURCE SMOKE FAILURE: CodexBarCore resource bundle is missing next to the executable; "
           "reinstall or update CodexBar")
SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


class Failure(Exception):
    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status


class Cancelled(BaseException):
    def __init__(self, number):
        self.status = 128 + number


def emit(event, **fields):
    print(json.dumps(dict(event=event, **fields), sort_keys=True), flush=True)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def canonical_directory(raw):
    path = Path(raw)
    if not path.is_absolute() or str(path) != raw or path.resolve(strict=True) != path or not path.is_dir():
        raise Failure("Expected an existing canonical absolute directory: " + raw, 2)
    return path


def sandbox_profile(root, checkout):
    # Default denial includes network, preference/Keychain Mach services, and fork.
    # dyld opens the root directory while locating its shared cache. This
    # literal grant does not permit reading descendant files.
    # HOME alone cannot isolate UserDefaults; the resource smoke's plugin engine
    # selection currently consults UserDefaults.standard even with an engine flag.
    paths = ["/System", "/usr/lib", "/usr/share", "/Library/Apple", "/private/var/db/dyld",
             "/private/preboot/Cryptexes/OS", str(root)]
    reads = " ".join("(subpath " + json.dumps(path) + ")" for path in paths)
    return ("(version 1)\n(deny default)\n(allow process-exec)\n(allow sysctl-read)\n"
            '(allow file-read-data file-read-metadata (literal "/"))\n'
            "(allow file-read* " + reads + ' (literal "/bin/cat") (literal "/dev/null")'
            ' (literal "/dev/random") (literal "/dev/urandom"))\n'
            '(allow file-write* (subpath ' + json.dumps(str(root)) + ') (literal "/dev/null"))\n'
            '(deny file-read* (subpath ' + json.dumps(str(checkout)) + "))\n")


class Run:
    def __init__(self, parent):
        self.parent = parent
        self.root = None
        self.identity = None
        self.child = None
        self.pending_log = None
        self.cleaned = False
        self.started = time.monotonic()

    def allocate(self):
        old = signal.pthread_sigmask(signal.SIG_BLOCK, SIGNALS)
        try:
            self.root = Path(tempfile.mkdtemp(prefix="codexbar-relocation-", dir=self.parent))
            stat = self.root.stat()
            self.identity = (stat.st_dev, stat.st_ino)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, old)
        emit("scratch", path=str(self.root))

    def command(self, name, argv, environment):
        remaining = min(20, 180 - (time.monotonic() - self.started))
        if remaining <= 0:
            raise Failure("Relocation exceeded its 180-second budget", 124)
        log = self.root / (name + ".log")
        started = time.monotonic()
        self.pending_log = (name, log, started)
        with log.open("wb") as output:
            old = signal.pthread_sigmask(signal.SIG_BLOCK, SIGNALS)
            try:
                self.child = subprocess.Popen(argv, cwd=self.root, env=environment,
                                              stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                                              preexec_fn=lambda: signal.pthread_sigmask(signal.SIG_SETMASK, old),
                                              start_new_session=True)
            finally:
                signal.pthread_sigmask(signal.SIG_SETMASK, old)
            try:
                status = self.child.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                raise Failure(name + " timed out (not a negative-control pass)", 124)
            self.child = None
        return status, self.report_output(status)

    def report_output(self, status):
        name, log, started = self.pending_log
        output = log.read_text(errors="replace") if log.exists() else ""
        emit("phase", name=name, status=status, seconds=round(time.monotonic() - started, 3),
             output=output[-8000:])
        self.pending_log = None
        return output

    def cleanup(self):
        if self.cleaned:
            return
        # A timed-out/cancelled child has not been reaped, so its PID cannot be reused.
        # Sandbox process-fork is denied; this lifecycle does not claim arbitrary trees.
        if self.child is not None:
            try:
                self.child.terminate()
                try:
                    self.child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.child.kill()
                    self.child.wait(timeout=2)
            finally:
                if self.child.returncode is None:
                    raise Failure("Child drain unknown; preserving scratch " + str(self.root))
            status = self.child.returncode
            self.child = None
            if self.pending_log is not None:
                self.report_output(status)
        elif self.pending_log is not None:
            self.report_output(None)
        if self.root is not None:
            stat = self.root.lstat()
            if self.root.is_symlink() or (stat.st_dev, stat.st_ino) != self.identity:
                raise Failure("Scratch identity changed; refusing removal: " + str(self.root))
            shutil.rmtree(self.root)
            if os.path.lexists(self.root):
                raise Failure("Scratch remains: " + str(self.root))
            self.cleaned = True
            emit("cleanup", path=str(self.root), absent=True)


def validate_app(app, commit):
    # Inspect only the explicitly supplied build; never discover installed apps.
    if app == Path("/Applications") or Path("/Applications") in app.parents:
        raise Failure("Supply a disposable qualified build, not an installed app", 2)
    for path in app.rglob("*"):
        if path.is_symlink() and not path.resolve(strict=True).is_relative_to(app):
            raise Failure("Bundle symlink escapes the supplied build: " + str(path), 2)
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
        raise Failure("Qualified source commit must be a full lowercase SHA", 2)
    embedded = info.get("CodexGitCommit", "")
    # package_app.sh writes git rev-parse --short; the reviewer supplies the full SHA.
    if not isinstance(embedded, str) or len(embedded) < 7 or not commit.startswith(embedded):
        raise Failure("Bundle CodexGitCommit does not match the qualified source", 2)
    for relative in ("Contents/MacOS/CodexBar", "Contents/Helpers/CodexBarCLI"):
        path = app / relative
        if not path.is_file() or not os.access(path, os.X_OK):
            raise Failure("Missing executable: " + str(path), 2)
    for relative in ("Contents/Resources/CodexBar_CodexBarCore.bundle",
                     "Contents/Helpers/CodexBar_CodexBarCore.bundle"):
        if not (app / relative).is_dir():
            raise Failure("Missing packaged resource bundle: " + relative, 2)
    return info


def relocation(run, args):
    app = canonical_directory(args.app)
    checkout = canonical_directory(args.checkout)
    if run.parent == checkout or checkout in run.parent.parents:
        raise Failure("Scratch parent must be outside the denied checkout", 2)
    if run.parent == app or app in run.parent.parents:
        raise Failure("Scratch parent must be outside the supplied bundle", 2)
    if not args.resource_entrypoints_reviewed:
        raise Failure("Exact build source must be reviewed before resource entrypoints may execute", 2)
    info = validate_app(app, args.qualified_source_commit)
    run.allocate()
    copied = run.root / "CodexBar.app"
    shutil.copytree(app, copied, symlinks=True)
    cli = copied / "Contents/Helpers/CodexBarCLI"
    binary = copied / "Contents/MacOS/CodexBar"
    link = run.root / "codexbar"
    link.symlink_to(cli)
    emit("identity", source_commit=args.qualified_source_commit, bundle_id=info.get("CFBundleIdentifier"),
         embedded_source_commit=info.get("CodexGitCommit"),
         source_bundle=str(app), copied_bundle=str(copied), checkout=str(checkout),
         app_sha256=digest(binary), cli_sha256=digest(cli), os=platform.platform(),
         architecture=platform.machine(), proof="resources-only; no ordinary app/UI startup")
    home = run.root / "home"
    home.mkdir()
    environment = {"PATH": "/usr/bin:/bin", "HOME": str(home), "CFFIXED_USER_HOME": str(home),
                   "TMPDIR": str(run.root), "LANG": "en_US.UTF-8", "TZ": "America/New_York",
                   "CODEXBAR_RESOURCE_SMOKE": "1", "CODEXBAR_PLUGIN_ENGINE": "quickjs"}
    profile = sandbox_profile(run.root, checkout)

    def probe(name, executable):
        return run.command(name, ["/usr/bin/sandbox-exec", "-p", profile, str(executable)], environment)

    # A denied read counts only after the same command reads an owned control file.
    readable = run.root / "readable"
    readable.write_text("owned-read-control\n")
    status, output = run.command("read-control", ["/usr/bin/sandbox-exec", "-p", profile,
                                                "/bin/cat", str(readable)], environment)
    if status != 0 or output.strip() != "owned-read-control":
        raise Failure("Sandbox read control failed")
    sentinel = checkout / "AGENTS.md"
    if not sentinel.is_file():
        raise Failure("Checkout denial control requires AGENTS.md", 2)
    status, output = run.command("checkout-denial", ["/usr/bin/sandbox-exec", "-p", profile,
                                                   "/bin/cat", str(sentinel)], environment)
    if status != 1 or not any(message in output for message in ("Operation not permitted", "Permission denied")):
        raise Failure("Checkout denial was not proved")
    for name, executable in (("helper", cli), ("symlink", link), ("app-resource", binary)):
        status, output = probe(name, executable)
        if status != 0 or MARKER not in output.splitlines():
            raise Failure(name + " resource smoke failed", status if 0 < status < 126 else 1)

    # Remove every resolver candidate in our copy, including legacy root placement.
    candidates = [p for p in copied.rglob("*")
                  if p.name in ("CodexBar_CodexBarCore.bundle", "CodexBar_CodexBarCore.resources")]
    for path in sorted(candidates, key=lambda p: len(p.parts), reverse=True):
        if path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    for name, executable in (("missing-helper", cli), ("missing-symlink", link), ("missing-app", binary)):
        status, output = probe(name, executable)
        if status != 1 or MISSING not in output.splitlines() or MARKER in output:
            raise Failure(name + " did not fail with the exact missing-bundle diagnostic")
    emit("resources", result="passed", seconds=round(time.monotonic() - run.started, 3))


def ax_trust_probe():
    # Direct public C API call in this interpreter; no Swift compiler or UI driver.
    # This boolean qualifies only this executing context, never a future driver binary.
    cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    ax = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
    pointer = ctypes.c_void_p
    cf.CFDictionaryCreate.argtypes = [pointer, ctypes.POINTER(pointer), ctypes.POINTER(pointer),
                                      ctypes.c_long, pointer, pointer]
    cf.CFDictionaryCreate.restype = pointer
    cf.CFRelease.argtypes = [pointer]
    cf.CFRelease.restype = None
    ax.AXIsProcessTrustedWithOptions.argtypes = [pointer]
    ax.AXIsProcessTrustedWithOptions.restype = ctypes.c_bool
    key = pointer.in_dll(ax, "kAXTrustedCheckOptionPrompt")
    false = pointer.in_dll(cf, "kCFBooleanFalse")
    options = cf.CFDictionaryCreate(None, (pointer * 1)(key.value), (pointer * 1)(false.value), 1, None, None)
    if not options:
        raise Failure("Could not create explicit prompt=false options")
    try:
        trusted = bool(ax.AXIsProcessTrustedWithOptions(options))
    finally:
        cf.CFRelease(options)
    emit("G-CB1", trusted=trusted, prompt=False, pid=os.getpid(), parent_pid=os.getppid(),
         executable=str(Path(sys.executable).resolve()), executable_sha256=digest(Path(sys.executable)),
         os=platform.platform(), architecture=platform.machine(),
         scope="current Python executing context only; recheck in the actual AX driver",
         disposition="driver qualification required" if trusted else "CB-N1/CB-N3 held: owner Accessibility grant")
    return 0 if trusted else 3


def main(argv=None):
    parser = argparse.ArgumentParser(description="Resource-only packaged relocation proof; never normal startup")
    parser.add_argument("--ax-trust-probe", action="store_true")
    parser.add_argument("--app")
    parser.add_argument("--checkout")
    parser.add_argument("--scratch-parent")
    parser.add_argument("--qualified-source-commit")
    parser.add_argument("--resource-entrypoints-reviewed", action="store_true")
    args = parser.parse_args(argv)
    run = None
    status = 0
    previous = {}
    try:
        for number in SIGNALS:
            previous[number] = signal.signal(number, lambda number, frame: (_ for _ in ()).throw(Cancelled(number)))
        if platform.system() != "Darwin":
            raise Failure("Unavailable: this proof requires macOS", 2)
        if args.ax_trust_probe:
            if any((args.app, args.checkout, args.scratch_parent, args.qualified_source_commit,
                    args.resource_entrypoints_reviewed)):
                raise Failure("AX probe is a separate mode; omit relocation arguments", 2)
            return ax_trust_probe()
        if not all((args.app, args.checkout, args.scratch_parent, args.qualified_source_commit)):
            raise Failure("Relocation requires --app, --checkout, --scratch-parent and --qualified-source-commit", 2)
        if not Path("/usr/bin/sandbox-exec").is_file():
            raise Failure("Unavailable: sandbox-exec is required; no unsandboxed fallback", 2)
        run = Run(canonical_directory(args.scratch_parent))
        relocation(run, args)
    except Cancelled as error:
        status = error.status
        emit("cancelled", status=status)
    except (Failure, OSError, ValueError) as error:
        status = error.status if isinstance(error, Failure) else 1
        emit("failure", status=status, message=str(error))
    finally:
        # Repeated handled signals cannot interrupt exact-child drain/root removal.
        for number in previous:
            signal.signal(number, signal.SIG_IGN)
        try:
            if run is not None:
                run.cleanup()
        except (Failure, OSError) as error:
            emit("cleanup-failure", primary_status=status, message=str(error))
            status = status or 1
        finally:
            for number, handler in previous.items():
                signal.signal(number, handler)
    emit("result", status=status, passed=status == 0)
    return status


if __name__ == "__main__":
    sys.exit(main())
PY
