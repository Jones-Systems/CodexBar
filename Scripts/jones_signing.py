#!/usr/bin/env python3
"""Jones Developer ID contract; native verification never imports a signing key."""

import argparse
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


TEAM = "2CUPSQS986"
BUNDLE = "com.jonessystems.codexbar"
GROUP = f"{TEAM}.{BUNDLE}"
ICLOUD = f"iCloud.{BUNDLE}"
MODE = "developer-id"
WORKFLOW = ".github/workflows/jones-macos-signing.yml"


class SigningError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise SigningError(message)


def entitlements(identifier):
    require(identifier in (BUNDLE, BUNDLE + ".widget"), "Unexpected Jones bundle identifier")
    result = {
        "com.apple.application-identifier": f"{TEAM}.{identifier}",
        "com.apple.developer.team-identifier": TEAM,
        "com.apple.security.application-groups": [GROUP],
    }
    if identifier == BUNDLE:
        result.update({
            "com.apple.developer.icloud-services": ["CloudKit"],
            "com.apple.developer.icloud-container-identifiers": [ICLOUD],
            "com.apple.developer.icloud-container-environment": "Production",
        })
    else:
        result["com.apple.security.app-sandbox"] = True
    return result


def validate_profile(profile, identifier, certificate_sha1, now=None):
    now = now or datetime.now(timezone.utc)
    require(isinstance(profile, dict), "Provisioning profile must be a dictionary")
    require(profile.get("TeamIdentifier") == [TEAM] and profile.get("ApplicationIdentifierPrefix") == [TEAM],
            "Provisioning profile team or application prefix differs")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime), "Provisioning profile expiry is missing")
    require(expiry.replace(tzinfo=timezone.utc) > now, "Provisioning profile is expired")
    require(profile.get("ProvisionsAllDevices") is True and "ProvisionedDevices" not in profile,
            "A Developer ID distribution profile is required")
    require(re.fullmatch(r"[0-9A-Fa-f]{40}", certificate_sha1) is not None, "Expected a certificate SHA-1 selector")
    certificates = profile.get("DeveloperCertificates")
    require(isinstance(certificates, list) and any(
        isinstance(cert, bytes) and hashlib.sha1(cert).hexdigest() == certificate_sha1.lower()
        for cert in certificates), "Provisioning profile does not authorize the signing certificate")
    granted = profile.get("Entitlements")
    require(isinstance(granted, dict), "Provisioning profile entitlements are missing")
    for key, value in entitlements(identifier).items():
        if key == "com.apple.security.app-sandbox":
            continue
        if key == "com.apple.security.application-groups":
            # Mac profiles may authorize the exact signed group with the owning team's wildcard.
            groups = granted.get(key)
            require(isinstance(groups, list) and bool(groups)
                    and all(group in (GROUP, TEAM + ".*") for group in groups),
                    "Provisioning profile does not authorize the selected Jones app group")
            continue
        require(type(granted.get(key)) is type(value) and granted[key] == value,
                f"Provisioning profile does not authorize exact {key}")
    require(granted.get("get-task-allow", False) is False
            and granted.get("com.apple.security.get-task-allow", False) is False,
            "Development profile cannot authorize distribution")


def validate_signature(text, identifier, resources=True):
    rows = text.splitlines()
    for key, value in (("Identifier", identifier), ("TeamIdentifier", TEAM)):
        require(rows.count(f"{key}={value}") == 1
                and sum(row.startswith(key + "=") for row in rows) == 1, f"Unexpected signed {key}")
    authorities = [row.removeprefix("Authority=") for row in rows if row.startswith("Authority=")]
    require(len(authorities) == 3 and authorities[0].startswith("Developer ID Application: ")
            and authorities[0].endswith(f" ({TEAM})")
            and authorities[1:] == ["Developer ID Certification Authority", "Apple Root CA"],
            "Expected the Jones Developer ID Application certificate chain")
    require(not any(row.startswith("Signature=") for row in rows), "Ad-hoc signature is not Developer ID")
    require(sum(row.startswith("Timestamp=") and len(row) > 10 for row in rows) == 1,
            "A secure signing timestamp is required")
    require(any(re.search(r"flags=0x[0-9a-f]+\([^)]*\bruntime\b", row) for row in rows),
            "Hardened runtime is required")
    hashes = [row[7:] for row in rows if row.startswith("CDHash=")]
    require(len(hashes) == 1 and re.fullmatch(r"[0-9a-fA-F]{40,64}", hashes[0]) is not None,
            "A code-directory hash is required")
    if resources:
        require(sum(re.fullmatch(r"Sealed Resources version=2 rules=[0-9]+ files=[0-9]+", row) is not None
                    for row in rows) == 1, "A sealed version-2 resource envelope is required")
    return hashes[0].lower()


def run(arguments):
    result = subprocess.run([str(arg) for arg in arguments], capture_output=True, check=False, timeout=90)
    require(result.returncode == 0, f"Native signing verification failed: {Path(arguments[0]).name}")
    return result


def profile_from_file(path):
    require(path.is_file() and not path.is_symlink(), "An explicit regular provisioning profile is required")
    return plistlib.loads(run(["/usr/bin/security", "cms", "-D", "-i", path]).stdout)


def verify_bundle(bundle, identifier, distribution=False):
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", bundle])
    shown = run(["/usr/bin/codesign", "--display", "--verbose=4", bundle])
    seal = validate_signature((shown.stdout + shown.stderr).decode(), identifier)
    actual = plistlib.loads(run(["/usr/bin/codesign", "--display", "--entitlements", ":-", bundle]).stdout)
    require(actual == entitlements(identifier)
            and (identifier == BUNDLE or actual.get("com.apple.security.app-sandbox") is True),
            "Unexpected signed Developer ID entitlements")
    # Public certificate bytes only; the caller owns the containing bundle volume.
    with tempfile.TemporaryDirectory(prefix=".jones-signature-", dir=bundle.parent) as scratch:
        prefix = Path(scratch) / "certificate"
        run(["/usr/bin/codesign", "--display", "--extract-certificates", prefix, bundle])
        certificate = Path(str(prefix) + "0").read_bytes()
        validate_profile(profile_from_file(bundle / "Contents/embedded.provisionprofile"), identifier,
                         hashlib.sha1(certificate).hexdigest())
    if distribution:
        require(identifier == BUNDLE, "Distribution assessment applies to the outer app")
        run(["/usr/bin/xcrun", "stapler", "validate", bundle])
        run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", bundle])
    return seal, actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-profile", type=Path, required=True)
    parser.add_argument("--widget-profile", type=Path, required=True)
    parser.add_argument("--certificate-sha1", required=True)
    parser.add_argument("--app-entitlements", type=Path)
    parser.add_argument("--widget-entitlements", type=Path)
    args = parser.parse_args()
    for profile, identifier in ((args.app_profile, BUNDLE), (args.widget_profile, BUNDLE + ".widget")):
        validate_profile(profile_from_file(profile), identifier, args.certificate_sha1)
    for path, identifier in ((args.app_entitlements, BUNDLE), (args.widget_entitlements, BUNDLE + ".widget")):
        if path is not None:
            path.write_bytes(plistlib.dumps(entitlements(identifier)))


if __name__ == "__main__":
    main()
