#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Fixtures exercise identity metadata and isolated session compilation; packaging/signing never runs.
exec python3 - "$ROOT" <<'PYTEST'
import hashlib
from pathlib import Path
import plistlib
import re
import resource
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = Path(sys.argv[1])
SOURCE = (ROOT / "Scripts/package_app.sh").read_text()
GOLDEN = {'release/identity/$APP/Contents/Info.plist': '139d367a203b990fea2584d54fcb9893ba6510f0a8b5cc11c04c0c556acaed5e', 'release/identity/$APP_ENTITLEMENTS': '82637aeed3306a079b86c3828b0159d193b3af3b8312349fd0f1cd0d755982d5', 'release/identity/$WIDGET_ENTITLEMENTS': '068b22ca7b56d898fd0c275d87a3924ba6b2266244d59e059cd7ba4e4cde12a4', 'release/adhoc/$APP/Contents/Info.plist': '3023450dd5489602ee0c1ee03020194506ae3457714e19d7ba0f3448cf0973ca', 'release/adhoc/$APP_ENTITLEMENTS': '82637aeed3306a079b86c3828b0159d193b3af3b8312349fd0f1cd0d755982d5', 'release/adhoc/$WIDGET_ENTITLEMENTS': '068b22ca7b56d898fd0c275d87a3924ba6b2266244d59e059cd7ba4e4cde12a4', 'debug/identity/$APP/Contents/Info.plist': '0f709318f2455aabae759f9868e35e66108d11e4bb15d9699e21684cde9327d0', 'debug/identity/$APP_ENTITLEMENTS': '55f83f8a1f01c38a1fdeb735c46e1f72c5baa709be046c5b2780649085f211e3', 'debug/identity/$WIDGET_ENTITLEMENTS': '7bdbe4f531d23ac5ff9ded2b82e46c110346dd1b7102fc1bce52af14fd41a098', 'debug/adhoc/$APP/Contents/Info.plist': '0f709318f2455aabae759f9868e35e66108d11e4bb15d9699e21684cde9327d0', 'debug/adhoc/$APP_ENTITLEMENTS': '55f83f8a1f01c38a1fdeb735c46e1f72c5baa709be046c5b2780649085f211e3', 'debug/adhoc/$WIDGET_ENTITLEMENTS': '7bdbe4f531d23ac5ff9ded2b82e46c110346dd1b7102fc1bce52af14fd41a098'}
BASE_OID = "0f842d7f26edcd1a1fff886409291ef9b4f846b6"
BASE_SOURCE = subprocess.check_output(
    ["git", "-C", str(ROOT), "show", BASE_OID + ":Scripts/package_app.sh"], text=True)
BASE_FUNCTION = "resolve_package_identity() {\n" + BASE_SOURCE.split(
    'BUNDLE_ID="com.steipete.codexbar"', 1)[1].split('ENTITLEMENTS_DIR=', 1)[0]
BASE_FUNCTION = BASE_FUNCTION.replace("resolve_package_identity() {\n", 
    'resolve_package_identity() {\nBUNDLE_ID="com.steipete.codexbar"', 1) + "\n}"
TARGETS = ("$APP/Contents/Info.plist", "$APP_ENTITLEMENTS", "$WIDGET_ENTITLEMENTS")
FIELDS = ("BUNDLE_ID", "WIDGET_BUNDLE_ID", "APP_GROUP_ID", "ICLOUD_ID", "FEED_URL",
          "PUBLIC_ED_KEY", "AUTO_CHECKS", "APP_TEAM_ID", "DISPLAY_NAME")
FUNCTION = re.search(r"^resolve_package_identity\(\) \{\n.*?^\}", SOURCE, re.M | re.S).group()

def signal_exit(signum, _frame):
    raise SystemExit(128 + signum)

for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(sig, signal_exit)

def shell(fixture, config, mode, body, extra=None, check=True, function=FUNCTION):
    env = {"PATH": "/usr/bin:/bin", "HOME": str(fixture / "home"), "TMPDIR": str(fixture),
           "ROOT": str(fixture), "LOWER_CONF": config, "SIGNING_MODE": mode,
           "ALLOW_LLDB": "0", "MARKETING_VERSION": "1.2.3", "BUILD_NUMBER": "42",
           "BUILD_TIMESTAMP": "2000-01-01T00:00:00Z", "GIT_COMMIT": "fixture",
           "ICLOUD_ENTITLEMENT_KEYS": ""}
    env.update(extra or {})
    return subprocess.run(["bash", "-c", "set -euo pipefail\n" + function +
                           "\nresolve_package_identity\n" + body], env=env,
                          capture_output=True, check=check)

def render(fixture, config, mode, target, extra=None, source=SOURCE, function=FUNCTION):
    template = re.search(r'cat > "' + re.escape(target) + r'" <<PLIST\n(.*?)\nPLIST',
                         source, re.S).group(1)
    return shell(fixture, config, mode, "cat <<PLIST\n" + template + "\nPLIST\n", extra, function=function).stdout

def values(fixture, config="release", mode="adhoc", extra=None):
    body = "printf '%s\\0' " + " ".join('"$' + field + '"' for field in FIELDS)
    data = shell(fixture, config, mode, body, extra).stdout.decode().split("\0")[:-1]
    return dict(zip(FIELDS, data))

count = 0
with tempfile.TemporaryDirectory(prefix=".jones-identity-fixture-", dir=ROOT) as name:
    fixture = Path(name)
    # Exercise the real standalone compile command without claiming a native Swift build.
    tools = fixture / "tools"
    tools.mkdir()
    compiler = tools / "swiftc"
    compiler.write_text("""#!/usr/bin/python3
from pathlib import Path
import os, sys
args = sys.argv[1:]
assert '-O' in args and '-parse-as-library' in args
sources = [Path(arg) for arg in args if arg.endswith('.swift')]
assert all(path.is_file() for path in sources)
assert {path.name for path in sources} == {
    'JonesStateRoot.swift', 'ProviderSessionStoreFile.swift', 'KeychainSecurity.swift',
    'provider_session_file_proof.swift'}, 'standalone compile source dependency missing'
output = Path(args[args.index('-o') + 1])
assert Path(args[args.index('-module-cache-path') + 1]).parent == output.parent
assert Path(os.environ['TMPDIR']) == output.parent
Path(os.environ['PROOF_RECORD']).write_text(str(output.parent))
if os.environ['PROOF_MODE'] == 'compile-failure':
    sys.exit(37)
output.write_text('''#!/usr/bin/python3
from pathlib import Path
import os, sys
assert sys.argv[1] == 'launch'
root = Path(sys.argv[2])
assert root.parent == Path(sys.argv[0]).parent
root.mkdir()
(root / 'synthetic-session').write_text('fixture')
sys.exit(41 if os.environ['PROOF_MODE'] == 'child-failure' else 0)
''')
output.chmod(0o700)
""")
    compiler.chmod(0o700)
    record = fixture / "proof-root"
    for mode, expected in (("success", 0), ("compile-failure", 37), ("child-failure", 41)):
        result = subprocess.run(
            ["bash", str(ROOT / "Scripts/test_provider_session_file_isolation.sh")],
            env={"PATH": str(tools) + ":/usr/bin:/bin", "TMPDIR": str(fixture),
                 "PROOF_MODE": mode, "PROOF_RECORD": str(record)},
            capture_output=True)
        assert result.returncode == expected, (mode, result.stderr.decode())
        assert not Path(record.read_text()).exists(), mode + " leaked owned scratch"
        count += 1
    print("Standalone session fixture: compile source list and success/failure cleanup passed (stub compiler)")

    # Compile the real identity policy when available; never translate its semantics into Python.
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        print("UNAVAILABLE: native JonesStateRoot metadata rejection proof (swiftc missing)")
    else:
        # Deliberate precondition failures must not leave crash core files.
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        (fixture / "home").mkdir()
        probe_source = fixture / "identity-proof.swift"
        probe_source.write_text('''import Foundation

@main
struct IdentityProof {
    static func main() throws {
        let args = CommandLine.arguments
        let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let identity: JonesStateRoot.Identity?
        if args[2] == "direct" {
            identity = JonesStateRoot.identity(info: info)
        } else {
            identity = JonesStateRoot.resolveIdentity(
                info: [:], executableURL: URL(fileURLWithPath: "/synthetic/Fixture.app/Contents/Helpers/CLI"),
                readInfo: { _ in info })
        }
        print(identity?.bundleID ?? "absent")
    }
}
''')
        probe = fixture / "identity-proof"
        native_env = {"PATH": "/usr/bin:/bin", "HOME": str(fixture / "home"),
                      "TMPDIR": str(fixture), "SWIFT_BACKTRACE": "enable=no"}
        subprocess.run([swiftc, "-O", "-parse-as-library", "-module-cache-path", str(fixture / "modules"),
                        str(ROOT / "Sources/CodexBarCore/JonesStateRoot.swift"), str(probe_source),
                        "-o", str(probe)], env=native_env, check=True)
        metadata = {"JonesAppBundleID": "com.example.fixture", "JonesAppGroupID": "FIXTURE.com.example.fixture",
                    "CodexBarTeamID": "FIXTURE", "JonesICloudID": "iCloud.com.example.fixture"}
        for marker, expected in ((None, b"absent"), ("jones", b"com.example.fixture"),
                                 (True, None), (False, None), (1, None), (0, None), ("unknown", None), ("", None)):
            info = dict(metadata)
            if marker is not None:
                info["JonesStateKey"] = marker
            plist = fixture / "identity.plist"
            plist.write_bytes(plistlib.dumps(info))
            for route in ("direct", "bundled-cli"):
                result = subprocess.run([str(probe), str(plist), route], cwd=fixture, env=native_env,
                                        capture_output=True)
                if expected is None:
                    assert result.returncode != 0, (marker, route, "invalid metadata fell back")
                else:
                    assert result.returncode == 0 and result.stdout.strip() == expected, (marker, route)
                count += 1
        print("Native JonesStateRoot: 16 valid/absent/invalid metadata cases passed")
    for config in ("release", "debug"):
        for mode in ("identity", "adhoc"):
            for target in TARGETS:
                actual = render(fixture, config, mode, target)
                baseline = render(fixture, config, mode, target, source=BASE_SOURCE, function=BASE_FUNCTION)
                assert actual == baseline, (config, mode, target, "differs from pinned original output")
                key = f"{config}/{mode}/{target}"
                assert hashlib.sha256(actual).hexdigest() == GOLDEN[key], key + " changed without overlay"
                plistlib.loads(actual)
                count += 1
    assert values(fixture, extra={"APP_TEAM_ID": "SYNTHETIC"})["APP_GROUP_ID"] == "SYNTHETIC.com.steipete.codexbar"
    # Environment-only names do not activate the overlay.
    assert values(fixture, extra={"JONES_BUNDLE_ID": "invalid.example"})["BUNDLE_ID"] == "com.steipete.codexbar"
    overlay = fixture / ".mac-release.jones.env"
    example = (ROOT / ".mac-release.jones.env.example").read_text()
    overlay.write_text(example)
    for config in ("release", "debug"):
        for mode in ("identity", "adhoc"):
            extra = {"JONES_SIGNING_IDENTITY": "SYNTHETIC_SIGNER"}
            result = values(fixture, config, mode, extra)
            assert result == dict(zip(FIELDS, ("com.jonessystems.codexbar", "com.jonessystems.codexbar.widget",
                "REPLACE_WITH_YOUR_TEAM.com.jonessystems.codexbar", "iCloud.com.jonessystems.codexbar",
                "", "", "false", "REPLACE_WITH_YOUR_TEAM", "CodexBar Jones"))), result
            app = plistlib.loads(render(fixture, config, mode, TARGETS[0], extra))
            assert app["JonesAppBundleID"] == result["BUNDLE_ID"] == app["CFBundleIdentifier"]
            assert app["JonesAppGroupID"] == result["APP_GROUP_ID"]
            assert app["JonesICloudID"] == result["ICLOUD_ID"]
            assert app["JonesStateKey"] == "jones"
            assert app["CodexBarTeamID"] == result["APP_TEAM_ID"]
            assert app["SUFeedURL"] == app["SUPublicEDKey"] == ""
            assert app["SUEnableAutomaticChecks"] is False
            for target in TARGETS[1:]:
                entitlements = plistlib.loads(render(fixture, config, mode, target, extra))
                assert entitlements["com.apple.security.application-groups"] == [result["APP_GROUP_ID"]]
            # Render the actual iCloud fragment without entering the provisioning/profile branch.
            fragment = re.search(r'cat <<ICLOUD\n(.*?)\nICLOUD', SOURCE, re.S).group(1)
            cloud = shell(fixture, config, mode, 'cat <<PLIST\n<plist><dict>\n' + fragment +
                          '\n</dict></plist>\nPLIST\n', extra).stdout
            assert plistlib.loads(cloud)["com.apple.developer.icloud-container-identifiers"] == [result["ICLOUD_ID"]]
            count += 1
    # Execute the actual widget metadata hook against a fixture-only PlistBuddy substitute.
    # Xcode's build-setting substitution and native PlistBuddy remain macOS qualification gates.
    buddy = fixture / "plist-buddy"
    buddy.write_text("""#!/usr/bin/python3
import plistlib, sys
from pathlib import Path
assert sys.argv[1] == '-c'
op, key, kind, value = sys.argv[2].split(' ', 3)
assert op == 'Add' and kind == 'string'
p = Path(sys.argv[3])
data = plistlib.loads(p.read_bytes())
assert key[1:] not in data
data[key[1:]] = value
p.write_bytes(plistlib.dumps(data))
""")
    buddy.chmod(0o700)
    app_dir = fixture / "Fixture.app"
    widget_info = app_dir / "Contents/PlugIns/CodexBarWidget.appex/Contents/Info.plist"
    widget_info.parent.mkdir(parents=True)
    widget_template = (ROOT / "WidgetExtension/Info.plist").read_text()
    replacements = {"CODEXBAR_TEAM_ID": "REPLACE_WITH_YOUR_TEAM",
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.jonessystems.codexbar.widget",
                    "MARKETING_VERSION": "1.2.3", "CURRENT_PROJECT_VERSION": "42",
                    "PRODUCT_NAME": "CodexBarWidget", "EXECUTABLE_NAME": "CodexBarWidget"}
    for key, value in replacements.items():
        widget_template = widget_template.replace("$(" + key + ")", value)
    widget_info.write_text(widget_template)
    widget_hook = SOURCE.split('# JONES(trial-identity): widget metadata', 1)[1]
    widget_hook = widget_hook[widget_hook.index('if [['):].split('\n# Sign widget extension', 1)[0]
    widget_hook = widget_hook.replace('/usr/libexec/PlistBuddy', '"' + str(buddy) + '"')
    shell(fixture, "release", "adhoc", widget_hook, {"APP": str(app_dir)})
    widget_plist = plistlib.loads(widget_info.read_bytes())
    assert widget_plist["JonesAppBundleID"] == "com.jonessystems.codexbar"
    assert widget_plist["JonesAppGroupID"] == "REPLACE_WITH_YOUR_TEAM.com.jonessystems.codexbar"
    assert widget_plist["JonesICloudID"] == "iCloud.com.jonessystems.codexbar"
    assert widget_plist["JonesStateKey"] == "jones"
    assert widget_plist["CodexBarTeamID"] == "REPLACE_WITH_YOUR_TEAM"
    assert widget_plist["CFBundleIdentifier"] == "com.jonessystems.codexbar.widget"
    count += 1
    # The widget's existing team build setting and added metadata must agree with the app.
    widget = (ROOT / "WidgetExtension/Info.plist").read_text()
    assert "$(CODEXBAR_TEAM_ID)" in widget
    project = (ROOT / "WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.pbxproj").read_text()
    assert 'PRODUCT_BUNDLE_IDENTIFIER = "$(CODEXBAR_WIDGET_BUNDLE_ID)";' in project
    assert 'INFOPLIST_KEY_CodexBarTeamID = "$(CODEXBAR_TEAM_ID)";' in project
    assert 'CODEXBAR_TEAM_ID="$APP_TEAM_ID"' in SOURCE
    assert 'CODEXBAR_WIDGET_BUNDLE_ID="$WIDGET_BUNDLE_ID"' in SOURCE
    for key, value in (("JonesStateKey", "jones"), ("JonesAppBundleID", "${BUNDLE_ID}"),
                       ("JonesAppGroupID", "${APP_GROUP_ID}"), ("JonesICloudID", "${ICLOUD_ID}")):
        assert f'Add :{key} string {value}' in SOURCE, key
    assert 'PROVISIONING_PROFILE_SOURCE="${JONES_PROVISIONING_PROFILE:-}"' in SOURCE
    assert 'CODESIGN_ID="$JONES_SIGNING_IDENTITY"' in SOURCE
    # Reject upstream identifiers/team and incomplete overlay before any build effects.
    for bad in (example.replace("com.jonessystems.codexbar", "com.steipete.codexbar"),
                example.replace("REPLACE_WITH_YOUR_TEAM", "Y5PE65HELJ"),
                example.replace('JONES_STATE_KEY="jones"', 'JONES_STATE_KEY="unknown"')):
        overlay.write_text(bad)
        assert shell(fixture, "release", "adhoc", ":", check=False).returncode != 0
        count += 1
    overlay.write_text(example)
    assert shell(fixture, "release", "identity", ":", check=False).returncode != 0
    assert shell(fixture, "release", "identity", ":", {"JONES_SIGNING_IDENTITY": "upstream (Y5PE65HELJ)"}, check=False).returncode != 0
    count += 2
    # Run only the re-sign identity guard; no release, credential, or signing code is evaluated.
    sign_source = (ROOT / "Scripts/sign-and-notarize.sh").read_text()
    sign_guard = sign_source.split('# JONES(trial-identity):', 1)[1]
    sign_guard = sign_guard[sign_guard.index('if [['):].split('\nsource "$ROOT/version.env"', 1)[0]
    for signer, succeeds in (("SYNTHETIC_SIGNER", True), ("", False), ("upstream (Y5PE65HELJ)", False)):
        result = shell(fixture, "release", "adhoc", sign_guard + '\nprintf "%s" "$APP_IDENTITY"',
                       {"JONES_SIGNING_IDENTITY": signer}, check=False)
        assert (result.returncode == 0) == succeeds
        if succeeds:
            assert result.stdout == b"SYNTHETIC_SIGNER"
        count += 1
    overlay.unlink()
    # No overlay means the guard leaves the pre-existing identity untouched.
    result = shell(fixture, "release", "adhoc", sign_guard + '\nprintf "%s" "$APP_IDENTITY"',
                   {"APP_IDENTITY": "ORIGINAL_FIXTURE_IDENTITY"})
    assert result.stdout == b"ORIGINAL_FIXTURE_IDENTITY"
    count += 1
    # No overlay needs to be created in the checkout to prove the ignore pattern.
    ignored = subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--no-index", "--quiet",
                              ".mac-release.jones.env"], check=False)
    assert ignored.returncode == 0, "local overlay must be ignored"
    count += 1
assert not fixture.exists(), "owned fixture cleanup failed"
print(f"Jones identity overlay: {count} checks passed; fixture removed")
PYTEST
