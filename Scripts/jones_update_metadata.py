#!/usr/bin/env python3
"""Validate public Jones update configuration and render reproducible package metadata.

`validate` checks only explicit configuration. `metadata` also reads local Git
and, for a requested CI origin, GitHub's event/context. JSON is the default;
plist and shell output are available for CI and package_app.sh. Nothing is
downloaded or written. Context validation is not a remote provenance attestation.
"""

import argparse
import base64
import binascii
from dataclasses import dataclass
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys

import jones_signing


REPOSITORY = "Jones-Systems/CodexBar"
REPOSITORY_ID = "1425008735"
BUNDLE_ID = "com.jonessystems.codexbar"
TEAM_ID = "JONESLOCAL"
APP_GROUP_ID = f"{TEAM_ID}.{BUNDLE_ID}"
ICLOUD_ID = f"iCloud.{BUNDLE_ID}"
DISPLAY_NAME = "CodexBar Jones"
STABLE_FEED_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"
# Public upstream trust anchor, never valid for the independent Jones product.
# https://github.com/steipete/CodexBar/blob/main/.mac-release.env
UPSTREAM_PUBLIC_ED_KEY = "AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI="
REVISION_PATTERN = re.compile(r"[0-9a-f]{40}")
POSITIVE_INTEGER_PATTERN = re.compile(r"[1-9][0-9]*")


class MetadataError(ValueError):
    pass


@dataclass(frozen=True)
class UpdateConfiguration:
    channel: str = "none"
    feed_url: str = ""
    public_ed_key: str = ""
    bundle_id: str = BUNDLE_ID
    team_id: str = TEAM_ID
    state_key: str = "jones"
    display_name: str = DISPLAY_NAME
    app_group_id: str = APP_GROUP_ID
    icloud_id: str = ICLOUD_ID
    signing_mode: str = "adhoc"

    def validate(self):
        if self.signing_mode not in ("adhoc", jones_signing.MODE):
            raise MetadataError("Unknown Jones signing mode")
        production = self.signing_mode == jones_signing.MODE
        if production and self.channel != "none":
            raise MetadataError("Developer ID updates are held pending legacy app-group migration qualification")
        expected = {
            "bundle_id": BUNDLE_ID,
            "team_id": jones_signing.TEAM if production else TEAM_ID,
            "state_key": "jones",
            "display_name": DISPLAY_NAME,
            "app_group_id": jones_signing.GROUP if production else APP_GROUP_ID,
            "icloud_id": ICLOUD_ID,
        }
        for name, value in expected.items():
            if getattr(self, name) != value:
                raise MetadataError(f"Jones {name} must be {value}")
        if self.channel == "none":
            if self.feed_url or self.public_ed_key:
                raise MetadataError("Jones channel none requires an empty feed and public key")
        elif self.channel == "stable":
            if self.feed_url != STABLE_FEED_URL:
                raise MetadataError("Jones stable feed must be the canonical HTTPS Jones release appcast")
            if self.public_ed_key == UPSTREAM_PUBLIC_ED_KEY:
                raise MetadataError("The upstream public key cannot authorize Jones updates")
            try:
                decoded = base64.b64decode(self.public_ed_key, validate=True)
            except (ValueError, binascii.Error) as error:
                raise MetadataError("Jones public key must be canonical base64 for 32 Ed25519 bytes") from error
            if len(decoded) != 32 or base64.b64encode(decoded).decode("ascii") != self.public_ed_key:
                raise MetadataError("Jones public key must be canonical base64 for 32 Ed25519 bytes")
        else:
            raise MetadataError("Jones update channel must be none or stable")

    def metadata(self):
        self.validate()
        enabled = self.channel == "stable"
        return {
            "CFBundleIdentifier": self.bundle_id,
            "CFBundleDisplayName": self.display_name,
            "CodexBarTeamID": self.team_id,
            "JonesStateKey": self.state_key,
            "JonesAppBundleID": self.bundle_id,
            "JonesAppGroupID": self.app_group_id,
            "JonesICloudID": self.icloud_id,
            "JonesUpdateChannel": self.channel,
            "JonesSigningMode": self.signing_mode,
            "SUFeedURL": self.feed_url,
            "SUPublicEDKey": self.public_ed_key,
            "SUEnableAutomaticChecks": enabled,
            "SUAutomaticallyUpdate": enabled,
            "SUAllowsAutomaticUpdates": enabled,
            "SURequireSignedFeed": True,
            "SUVerifyUpdateBeforeExtraction": True,
            "SUSignedFeedFailureExpirationInterval": 0,
        }


@dataclass(frozen=True)
class SourceRevision:
    revision: str
    first_parent_count: str


def git_output(repo, *arguments):
    # Ignore inherited Git redirection/replacement variables when binding the source.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment.update(GIT_OPTIONAL_LOCKS="0", GIT_NO_REPLACE_OBJECTS="1")
    try:
        result = subprocess.run(
            ["git", "--no-optional-locks", "-C", str(repo), *arguments],
            env=environment, check=True, capture_output=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise MetadataError("Cannot read Jones source provenance from the selected repository") from error
    return result.stdout.rstrip("\n")


def inspect_source(repo):
    repo = Path(repo).resolve()
    if Path(git_output(repo, "rev-parse", "--show-toplevel")).resolve() != repo:
        raise MetadataError("Jones metadata requires the repository root")
    revision = git_output(repo, "rev-parse", "--verify", "HEAD^{commit}")
    if not REVISION_PATTERN.fullmatch(revision):
        raise MetadataError("Jones source revision must be a complete lowercase SHA-1")
    if git_output(repo, "rev-parse", "--is-shallow-repository") != "false":
        raise MetadataError("Jones packaging requires full Git history; shallow source is refused")
    if git_output(repo, "status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none"):
        raise MetadataError("Jones packaging refuses dirty or untracked source")
    count = git_output(repo, "rev-list", "--first-parent", "--count", revision)
    if not POSITIVE_INTEGER_PATTERN.fullmatch(count):
        raise MetadataError("Jones first-parent commit count must be a positive integer")
    if git_output(repo, "rev-parse", "--verify", "HEAD^{commit}") != revision:
        raise MetadataError("Jones source revision changed while collecting provenance")
    return SourceRevision(revision, count)


def canonical_repository(value):
    return (
        isinstance(value, dict)
        and value.get("full_name") == REPOSITORY
        and str(value.get("id")) == REPOSITORY_ID
        and value.get("default_branch") == "main"
        and value.get("fork") is False
    )


def load_ci_event(environment):
    event_path = environment.get("GITHUB_EVENT_PATH", "")
    if not event_path:
        raise MetadataError("CI provenance requires GITHUB_EVENT_PATH")
    try:
        event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise MetadataError("Cannot read the GitHub event for Jones CI provenance") from error
    if not isinstance(event, dict):
        raise MetadataError("GitHub event must be a JSON object")
    return event


def provenance_metadata(source, build_number, origin="local", build_run="", environment=None, event=None, signing_mode="adhoc"):
    environment = {} if environment is None else environment
    if not REVISION_PATTERN.fullmatch(source.revision):
        raise MetadataError("Jones source revision must be a complete lowercase SHA-1")
    if not POSITIVE_INTEGER_PATTERN.fullmatch(source.first_parent_count):
        raise MetadataError("Jones first-parent commit count must be a positive integer")
    if not POSITIVE_INTEGER_PATTERN.fullmatch(build_number):
        raise MetadataError("BUILD_NUMBER must be a positive integer before Jones version composition")
    run = ""
    if origin == "local":
        if build_run:
            raise MetadataError("Local Jones builds must have an empty build run")
    elif origin in ("ci-main", "ci-pr"):
        required = {
            "GITHUB_ACTIONS": "true",
            "GITHUB_SERVER_URL": "https://github.com",
            "GITHUB_REPOSITORY": REPOSITORY,
            "GITHUB_REPOSITORY_ID": REPOSITORY_ID,
        }
        if any(environment.get(key) != value for key, value in required.items()):
            raise MetadataError("CI origin requires the canonical Jones GitHub Actions repository context")
        run_id = environment.get("GITHUB_RUN_ID", "")
        if not POSITIVE_INTEGER_PATTERN.fullmatch(run_id):
            raise MetadataError("CI provenance requires a positive GitHub run ID")
        if event is None:
            event = load_ci_event(environment)
        if not isinstance(event, dict) or not canonical_repository(event.get("repository")):
            raise MetadataError("GitHub event repository is not canonical Jones CodexBar")
        if origin == "ci-main":
            production_dispatch = (
                signing_mode == jones_signing.MODE
                and environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
                and environment.get("GITHUB_WORKFLOW_REF") ==
                f"{REPOSITORY}/{jones_signing.WORKFLOW}@refs/heads/main"
                and environment.get("GITHUB_WORKFLOW_SHA") == source.revision
                and environment.get("GITHUB_REF") == "refs/heads/main"
                and environment.get("GITHUB_SHA") == source.revision
            )
            if not production_dispatch and (
                environment.get("GITHUB_EVENT_NAME") != "push"
                or environment.get("GITHUB_REF") != "refs/heads/main"
                or environment.get("GITHUB_SHA") != source.revision
                or event.get("ref") != "refs/heads/main"
                or event.get("after") != source.revision
                or event.get("deleted") is not False
            ):
                raise MetadataError("ci-main requires the exact non-deleted canonical main push revision")
        else:
            pull_request = event.get("pull_request")
            if not isinstance(pull_request, dict):
                raise MetadataError("ci-pr requires a pull_request event")
            head, base = pull_request.get("head"), pull_request.get("base")
            number = event.get("number")
            if (
                environment.get("GITHUB_EVENT_NAME") != "pull_request"
                or not isinstance(number, int) or isinstance(number, bool) or number <= 0
                or environment.get("GITHUB_REF") != f"refs/pull/{number}/merge"
                or not isinstance(head, dict) or head.get("sha") != source.revision
                or not head.get("ref") or environment.get("GITHUB_HEAD_REF") != head["ref"]
                or not isinstance(base, dict) or base.get("ref") != "main"
                or not canonical_repository(base.get("repo"))
                or environment.get("GITHUB_BASE_REF") != "main"
            ):
                raise MetadataError("ci-pr requires the exact PR head and canonical main base")
        run = f"https://github.com/{REPOSITORY}/actions/runs/{run_id}"
        if build_run and build_run != run:
            raise MetadataError("Jones build run does not match the GitHub Actions context")
    else:
        raise MetadataError("Jones build origin must be local, ci-pr or ci-main")
    return {
        "CFBundleVersion": f"{build_number}.{source.first_parent_count}",
        "JonesSourceRevision": source.revision,
        "JonesBuildOrigin": origin,
        "JonesBuildRun": run,
    }


def plist_fragment(metadata):
    serialized = plistlib.dumps(metadata, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8")
    return serialized.split("<dict>\n", 1)[1].rsplit("</dict>", 1)[0].rstrip()


def shell_metadata(provenance):
    values = {
        "BUILD_NUMBER": provenance["CFBundleVersion"],
        "JONES_SOURCE_REVISION": provenance["JonesSourceRevision"],
        "JONES_BUILD_ORIGIN": provenance["JonesBuildOrigin"],
        "JONES_BUILD_RUN": provenance["JonesBuildRun"],
        "JONES_PROVENANCE_METADATA": "\n" + plist_fragment(
            {key: value for key, value in provenance.items() if key != "CFBundleVersion"}),
    }
    return "\n".join(f"{key}={shlex.quote(value)}" for key, value in values.items()) + "\n"


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    subcommands = result.add_subparsers(dest="command", required=True)
    for name in ("validate", "metadata"):
        command = subcommands.add_parser(name)
        for flag, default in (
            ("signing-mode", "adhoc"), ("channel", "none"), ("feed-url", ""), ("public-ed-key", ""),
            ("bundle-id", BUNDLE_ID), ("team-id", TEAM_ID), ("state-key", "jones"),
            ("display-name", DISPLAY_NAME), ("app-group-id", APP_GROUP_ID), ("icloud-id", ICLOUD_ID),
        ):
            command.add_argument(f"--{flag}", default=default)
        formats = ("json", "plist", "shell") if name == "metadata" else ("json", "plist")
        command.add_argument("--format", choices=formats, default="json")
        if name == "metadata":
            command.add_argument("--repo", type=Path, required=True)
            command.add_argument("--build-number", required=True)
            command.add_argument("--origin", default="local")
            command.add_argument("--build-run", default="")
    return result


def main(argv=None, environment=None, stdout=None, stderr=None):
    args = parser().parse_args(argv)
    environment = os.environ if environment is None else environment
    stdout = sys.stdout if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    try:
        configuration = UpdateConfiguration(**{
            key: getattr(args, key) for key in UpdateConfiguration.__dataclass_fields__
        })
        metadata = configuration.metadata()
        if args.command == "metadata":
            provenance = provenance_metadata(
                inspect_source(args.repo), args.build_number, args.origin, args.build_run, environment, signing_mode=args.signing_mode)
            metadata.update(provenance)
        if args.format == "shell":
            output = shell_metadata(provenance)
        elif args.format == "plist":
            output = plistlib.dumps(metadata, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8")
        else:
            output = json.dumps(metadata, sort_keys=True, indent=2) + "\n"
        stdout.write(output)
    except MetadataError as error:
        print(f"ERROR: {error}", file=stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
