#!/usr/bin/env python3
"""Explicit hosted-main signing operation; never publishes, installs, or activates a feed."""

import base64
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import tempfile

import jones_candidate_artifact as candidate
import jones_signing as signing


SECRETS = ("MACOS_SIGNING_CERTIFICATE_P12_BASE64", "MACOS_SIGNING_CERTIFICATE_PASSWORD",
           "APPLE_NOTARY_API_KEY_P8_BASE64", "APPLE_NOTARY_KEY_ID", "APPLE_NOTARY_ISSUER_ID")


class ProcessDrainUnknown(signing.SigningError):
    pass


def group_exists(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False


def run(args, environment, timeout=120):
    process = subprocess.Popen([str(arg) for arg in args], env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=timeout)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=20)
        except subprocess.TimeoutExpired as error:
            raise ProcessDrainUnknown("Owned command drain is unknown; retain state until VM teardown") from error
        if group_exists(process.pid):
            raise ProcessDrainUnknown("Owned command descendants remain; retain state until VM teardown")
        raise
    if group_exists(process.pid):
        raise ProcessDrainUnknown("Owned command descendants remain; retain state until VM teardown")
    signing.require(process.returncode == 0, f"Signing step failed: {Path(args[0]).name}")
    return output


def decode_file(value, path, maximum):
    signing.require(isinstance(value, str) and 0 < len(value) <= 2 * maximum, "Missing or oversized signing input")
    data = base64.b64decode(value, validate=True)
    signing.require(0 < len(data) <= maximum, "Invalid signing input size")
    with path.open("xb") as handle:
        handle.write(data)
    path.chmod(0o600)


def main():
    source_environment = dict(os.environ)
    repo = Path(__file__).resolve().parent.parent
    context = candidate.inspect_context(repo, source_environment, signing_mode=signing.MODE)
    signing.require(context.origin == "ci-main" and source_environment.get("RUNNER_ENVIRONMENT") == "github-hosted",
                    "Signing requires a fresh GitHub-hosted canonical-main run")
    environment = {key: value for key, value in source_environment.items() if key not in SECRETS}
    for key in SECRETS:
        signing.require(bool(source_environment.get(key)), f"Missing {key}")
        os.environ.pop(key, None)
    signing.require(re.fullmatch(r"[A-Z0-9]{10}", source_environment["APPLE_NOTARY_KEY_ID"]) is not None
                    and re.fullmatch(r"[0-9a-fA-F-]{36}", source_environment["APPLE_NOTARY_ISSUER_ID"]) is not None,
                    "Invalid notary API identifiers")
    overlay = repo / ".mac-release.jones.env"
    signing.require(not overlay.exists() and not overlay.is_symlink(), "Existing Jones overlay is not owned")
    build = repo / ".build"
    signing.require(build.is_dir() and not build.is_symlink(), "Expected the admitted build directory")
    importer = build / "jones-import-identity"
    signing.require(importer.is_file() and not importer.is_symlink(), "Missing precompiled identity importer")
    old_mask = os.umask(0o077)
    scratch = Path(tempfile.mkdtemp(prefix="jones-signing-", dir=build))
    keychain = scratch / "signing.keychain-db"
    original_search = None
    overlay_owned = False
    primary_error = None
    try:
        environment["TMPDIR"] = str(scratch)
        run(["python3", "-B", repo / "Scripts/jones_candidate_admission.py", "--workspace", repo,
             "--scratch", scratch, "--compiler-jobs", "1", "--wait-seconds", "180"], environment, timeout=240)
        app_profile, widget_profile = scratch / "app.provisionprofile", scratch / "widget.provisionprofile"
        decode_file(environment.get("JONES_APP_PROVISIONING_PROFILE_BASE64"), app_profile, 128 * 1024)
        decode_file(environment.get("JONES_WIDGET_PROVISIONING_PROFILE_BASE64"), widget_profile, 128 * 1024)
        p12, p8 = scratch / "identity.p12", scratch / "notary.p8"
        decode_file(source_environment[SECRETS[0]], p12, 128 * 1024)
        decode_file(source_environment[SECRETS[2]], p8, 16 * 1024)
        original_search = shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"], environment).decode())
        # The empty keychain password is intentional, not a secret. No login keychain is unlocked or modified.
        run(["/usr/bin/security", "create-keychain", "-p", "", keychain], environment)
        run(["/usr/bin/security", "set-keychain-settings", "-lut", "7200", keychain], environment)
        run(["/usr/bin/security", "unlock-keychain", "-p", "", keychain], environment)
        import_environment = dict(environment, MACOS_SIGNING_CERTIFICATE_PASSWORD=source_environment[SECRETS[1]])
        identity = run([importer, p12, keychain], import_environment).decode().strip()
        signing.require(re.fullmatch(r"[A-F0-9]{40}", identity) is not None, "Invalid imported identity selector")
        import_environment.pop("MACOS_SIGNING_CERTIFICATE_PASSWORD")
        p12.unlink()
        for profile, identifier in ((app_profile, signing.BUNDLE), (widget_profile, signing.BUNDLE + ".widget")):
            signing.validate_profile(signing.profile_from_file(profile), identifier, identity)
        run(["/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
             "-s", "-k", "", keychain], environment)
        values = {
            "JONES_BUNDLE_ID": signing.BUNDLE, "JONES_DISPLAY_NAME": "CodexBar Jones", "JONES_STATE_KEY": "jones",
            "JONES_TEAM_ID": signing.TEAM, "JONES_SIGNING_MODE": signing.MODE, "JONES_SIGNING_IDENTITY": identity,
            "JONES_SIGNING_KEYCHAIN": str(keychain), "JONES_PROVISIONING_PROFILE": str(app_profile),
            "JONES_WIDGET_PROVISIONING_PROFILE": str(widget_profile), "JONES_UPDATE_CHANNEL": "none",
            "JONES_UPDATE_FEED_URL": "", "JONES_UPDATE_PUBLIC_ED_KEY": "",
        }
        with overlay.open("x") as handle:
            overlay_owned = True
            handle.write("".join(f"{key}={shlex.quote(value)}\n" for key, value in values.items()))
        environment.update(CODEXBAR_SIGNING="identity", CODEXBAR_BUILD_JOBS="1", ARCHES="arm64",
                           JONES_BUILD_ORIGIN="ci-main", CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY="1")
        run(["/bin/bash", repo / "Scripts/package_app.sh", "release"], environment, timeout=3600)
        app = repo / "CodexBar.app"
        signing.verify_bundle(app, signing.BUNDLE)
        signing.verify_bundle(app / "Contents/PlugIns/CodexBarWidget.appex", signing.BUNDLE + ".widget")
        submission = scratch / "submission.zip"
        run(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", app, submission], environment, 300)
        response = json.loads(run(["/usr/bin/xcrun", "notarytool", "submit", submission, "--key", p8,
                                   "--key-id", source_environment[SECRETS[3]], "--issuer", source_environment[SECRETS[4]],
                                   "--wait", "--timeout", "30m", "--output-format", "json"], environment, 1900))
        signing.require(response.get("status") == "Accepted", "Notarization was not accepted; no artifact eligible")
        run(["/usr/bin/xcrun", "stapler", "staple", app], environment)
        signing.verify_bundle(app, signing.BUNDLE, distribution=True)
        candidate.create_artifact(app, build / "jones-signed-artifact", context, "none", signing.MODE)
    except BaseException as error:
        primary_error = error
        raise
    finally:
        cleanup_errors = []
        if isinstance(primary_error, ProcessDrainUnknown):
            os.umask(old_mask)
            print(json.dumps({"status": "drain-unknown", "path": str(scratch), "retention": "hosted-vm-teardown"}))
            raise primary_error
        if overlay_owned:
            try:
                overlay.unlink()
            except OSError:
                cleanup_errors.append("overlay")
        if original_search is not None:
            try:
                run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *original_search], environment)
                restored = shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"], environment).decode())
                signing.require(restored == original_search, "Keychain search-list restoration failed")
            except Exception:
                cleanup_errors.append("search-list")
        if keychain.exists():
            try:
                run(["/usr/bin/security", "delete-keychain", keychain], environment)
            except Exception:
                cleanup_errors.append("keychain")
        # Unknown keychain/search-list cleanup preserves the exact root until hosted VM teardown.
        if not cleanup_errors:
            try:
                shutil.rmtree(scratch)
            except OSError:
                cleanup_errors.append("scratch")
        os.umask(old_mask)
        if cleanup_errors:
            print(json.dumps({"status": "cleanup-failed", "components": cleanup_errors, "path": str(scratch)}))
            if primary_error is None:
                raise signing.SigningError("Signing cleanup failed")


if __name__ == "__main__":
    def cancel(signum, _frame):
        raise SystemExit(128 + signum)

    for handled in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(handled, cancel)
    try:
        main()
    except Exception:
        # Never render subprocess output, decoded secrets, or exception arguments.
        raise SystemExit("Jones signing failed; no release or installation was performed.")
