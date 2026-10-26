#!/usr/bin/env bash
set -euo pipefail

# This read-only query precedes configuration, tool discovery and all packaging effects.
if [[ "${1:-}" == "--jones-candidate-capabilities" ]]; then
  [[ "$#" == "1" ]] || { echo 'The capability query accepts no other arguments.' >&2; exit 2; }
  printf '%s\n' '{"schema":"jones-candidate-packager/v1","compiler_jobs_env":"CODEXBAR_BUILD_JOBS","compiler_jobs_max":6,"bounded_compilers":["swift-build","xcodebuild"],"resource_only_smoke_env":"CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY","resource_only_smoke_value":"1"}'
  exit 0
fi

# JONES(trial-identity): pure identity resolution; fixture tests source only this block.
resolve_package_identity() {
  BUNDLE_ID="com.steipete.codexbar"
  FEED_URL="https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml"
  AUTO_CHECKS=true
  PUBLIC_ED_KEY="AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI="
  DISPLAY_NAME="CodexBar"
  JONES_OVERLAY=0
  JONES_SIGNING_MODE=adhoc
  JONES_METADATA=""
  if [[ "$LOWER_CONF" == "debug" ]]; then
    BUNDLE_ID="com.steipete.codexbar.debug"
    FEED_URL=""
    AUTO_CHECKS=false
  fi
  if [[ "$SIGNING_MODE" == "adhoc" ]]; then
    FEED_URL=""
    AUTO_CHECKS=false
  fi
  if [[ -f "$ROOT/.mac-release.jones.env" ]]; then
    source "$ROOT/.mac-release.jones.env"
    : "${JONES_BUNDLE_ID:?Missing JONES_BUNDLE_ID}" "${JONES_TEAM_ID:?Missing JONES_TEAM_ID}"
    [[ "$JONES_BUNDLE_ID" == "com.jonessystems.codexbar" ]] || return 1
    JONES_SIGNING_MODE="${JONES_SIGNING_MODE:-adhoc}"
    case "$JONES_SIGNING_MODE" in
      adhoc) [[ "$JONES_TEAM_ID" == "JONESLOCAL" ]] || return 1 ;;
      developer-id)
        [[ "$JONES_TEAM_ID" == "2CUPSQS986" && "$SIGNING_MODE" == "identity" && "$LOWER_CONF" == "release" ]] || return 1
        [[ "${ALLOW_LLDB:-0}" == "0" && "${JONES_UPDATE_CHANNEL:-none}" == "none" ]] || return 1
        [[ "${JONES_SIGNING_IDENTITY:-}" =~ ^[A-Fa-f0-9]{40}$ ]] || return 1
        : "${JONES_PROVISIONING_PROFILE:?Explicit app profile required}"
        : "${JONES_WIDGET_PROVISIONING_PROFILE:?Explicit widget profile required}"
        ;;
      *) return 1 ;;
    esac
    [[ "${JONES_STATE_KEY:-}" == "jones" ]] || return 1
    [[ "${JONES_DISPLAY_NAME:-}" == "CodexBar Jones" ]] || return 1
    BUNDLE_ID="$JONES_BUNDLE_ID"
    APP_TEAM_ID="$JONES_TEAM_ID"
    DISPLAY_NAME="$JONES_DISPLAY_NAME"
    JONES_UPDATE_CHANNEL="${JONES_UPDATE_CHANNEL-none}"
    FEED_URL="${JONES_UPDATE_FEED_URL:-}"
    PUBLIC_ED_KEY="${JONES_UPDATE_PUBLIC_ED_KEY:-}"
    AUTO_CHECKS=false
    case "$JONES_UPDATE_CHANNEL" in
      none)
        [[ -z "$FEED_URL" && -z "$PUBLIC_ED_KEY" ]] || return 1
        ;;
      stable)
        [[ "$FEED_URL" == "https://github.com/Jones-Systems/CodexBar/releases/latest/download/appcast.xml" ]] || return 1
        # Canonical base64 for exactly 32 bytes, including the final padding bits.
        [[ "$PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$ ]] || return 1
        [[ "$PUBLIC_ED_KEY" != "AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=" ]] || return 1
        AUTO_CHECKS=true
        ;;
      *) return 1 ;;
    esac
    JONES_OVERLAY=1
  fi
  WIDGET_BUNDLE_ID="${BUNDLE_ID}.widget"
  ICLOUD_ID="iCloud.${BUNDLE_ID}"
  APP_TEAM_ID="${APP_TEAM_ID:-Y5PE65HELJ}"
  APP_GROUP_ID="${APP_TEAM_ID}.com.steipete.codexbar"
  if [[ "$BUNDLE_ID" == *".debug"* ]]; then
    APP_GROUP_ID="${APP_TEAM_ID}.com.steipete.codexbar.debug"
  fi
  if [[ "$JONES_OVERLAY" == "1" ]]; then
    APP_GROUP_ID="${APP_TEAM_ID}.${BUNDLE_ID}"
    JONES_METADATA="
    <key>JonesSigningMode</key><string>${JONES_SIGNING_MODE}</string>
    <key>JonesStateKey</key><string>jones</string>
    <key>JonesAppBundleID</key><string>${BUNDLE_ID}</string>
    <key>JonesAppGroupID</key><string>${APP_GROUP_ID}</string>
    <key>JonesICloudID</key><string>${ICLOUD_ID}</string>
    <key>JonesUpdateChannel</key><string>${JONES_UPDATE_CHANNEL}</string>
    <key>SUAutomaticallyUpdate</key><${AUTO_CHECKS}/>
    <key>SUAllowsAutomaticUpdates</key><${AUTO_CHECKS}/>
    <key>SURequireSignedFeed</key><true/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>"
    if [[ "$SIGNING_MODE" == "identity" ]]; then
      : "${JONES_SIGNING_IDENTITY:?Fork signing identity must be explicitly supplied}"
      [[ "$JONES_SIGNING_IDENTITY" != *Y5PE65HELJ* ]] || return 1
    fi
  fi
}
# JONES(trial-identity): end pure identity resolution.

# JONES(updates): Git/CI reads stay outside the shell-only identity fixture seam.
prepare_jones_update_metadata() {
  [[ "$JONES_OVERLAY" == "1" ]] || return 0
  local metadata
  metadata=$(python3 "$ROOT/Scripts/jones_update_metadata.py" metadata \
    --repo "$ROOT" --build-number "$BUILD_NUMBER" \
    --origin "${JONES_BUILD_ORIGIN-local}" --build-run "${JONES_BUILD_RUN:-}" \
    --bundle-id "$BUNDLE_ID" --team-id "$APP_TEAM_ID" --state-key "$JONES_STATE_KEY" \
    --display-name "$DISPLAY_NAME" --app-group-id "$APP_GROUP_ID" --icloud-id "$ICLOUD_ID" \
    --signing-mode "${JONES_SIGNING_MODE:-adhoc}" --channel "$JONES_UPDATE_CHANNEL" \
    --feed-url "$FEED_URL" --public-ed-key "$PUBLIC_ED_KEY" \
    --format shell) || return 1
  # Only fixed assignment names and shlex-quoted, validated public values are emitted.
  eval "$metadata"
  JONES_METADATA+="$JONES_PROVENANCE_METADATA"
}

resolve_package_signing_mode() {
  local requested="${CODEXBAR_SIGNING:-adhoc}"
  case "$requested" in
    adhoc|identity) ;;
    *)
      echo "ERROR: Unsupported CODEXBAR_SIGNING: $requested (expected adhoc or identity)" >&2
      return 1
      ;;
  esac
  SIGNING_MODE="$requested"
}

verify_no_quarantine_attribute() {
  local bundle="$1"
  local quarantined
  quarantined="$(xattr -r -p com.apple.quarantine "$bundle" 2>/dev/null || true)"
  if [[ -n "$quarantined" ]]; then
    echo "ERROR: Packaged app still has com.apple.quarantine: ${bundle}" >&2
    return 1
  fi
}

verify_packaged_app_integrity() {
  local bundle="$1"
  local sparkle="$bundle/Contents/Frameworks/Sparkle.framework"

  verify_no_quarantine_attribute "$bundle" || return 1
  codesign --verify --deep --strict --verbose=2 "$sparkle" || return 1
  codesign --verify --deep --strict --verbose=2 "$bundle" || return 1
}

CONF=${1:-release}
ALLOW_LLDB=${CODEXBAR_ALLOW_LLDB:-0}
SIGNING_MODE=
resolve_package_signing_mode
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
LOWER_CONF=$(printf "%s" "$CONF" | tr '[:upper:]' '[:lower:]')
case "$LOWER_CONF" in
  debug|release) ;;
  *)
    echo "ERROR: Unsupported build configuration: $CONF (expected debug or release)" >&2
    exit 1
    ;;
esac

# Load version info
source "$ROOT/version.env"
source "$ROOT/Scripts/package_product_paths.sh"
source "$ROOT/Scripts/sparkle_signing_paths.sh"
resolve_package_identity # JONES(trial-identity): resolve before any build or packaging effects.
prepare_jones_update_metadata # JONES(updates): reject dirty/shallow source and invalid CI claims before builds.
if [[ "${JONES_SIGNING_MODE:-adhoc}" == "developer-id" ]]; then
  python3 -B "$ROOT/Scripts/jones_signing.py" \
    --app-profile "$JONES_PROVISIONING_PROFILE" --widget-profile "$JONES_WIDGET_PROVISIONING_PROFILE" \
    --certificate-sha1 "$JONES_SIGNING_IDENTITY"
fi

# Clean build only when explicitly requested (slower).
if [[ "${CODEXBAR_FORCE_CLEAN:-0}" == "1" ]]; then
  if [[ -d "$ROOT/.build" ]]; then
    if command -v trash >/dev/null 2>&1; then
      if ! trash "$ROOT/.build"; then
        echo "WARN: trash .build failed; continuing with swift package clean." >&2
      fi
    else
      rm -rf "$ROOT/.build" || echo "WARN: rm -rf .build failed; continuing with swift package clean." >&2
    fi
  fi
  swift package clean >/dev/null 2>&1 || true
fi

# Build for host architecture by default; allow overriding via ARCHES (e.g., "arm64 x86_64" for universal).
ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  case "$HOST_ARCH" in
    arm64) ARCH_LIST=(arm64) ;;
    x86_64) ARCH_LIST=(x86_64) ;;
    *) ARCH_LIST=("$HOST_ARCH") ;;
  esac
fi

patch_keyboard_shortcuts() {
  local util_path="$ROOT/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
  if [[ ! -f "$util_path" ]]; then
    return 0
  fi
  if grep -q "keyboardShortcutsSafeBundle" "$util_path"; then
    return 0
  fi

  chmod +w "$util_path" || true
  python3 - "$util_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
if ".keyboardShortcutsSafeBundle" in text:
    sys.exit(0)

preimage = 'NSLocalizedString(self, bundle: .module, comment: self)'
if text.count(preimage) != 1:
    raise SystemExit("Unexpected resource lookup in Utilities.swift; patch failed.")
text = text.replace(
    preimage,
    'NSLocalizedString(self, bundle: .keyboardShortcutsSafeBundle, comment: self)',
)

inject = """
private extension Bundle {
    /// Safe lookup that avoids the fatal trap in the autogenerated `Bundle.module`
    /// when the resource bundle is not placed at the bundle root.
    static let keyboardShortcutsSafeBundle: Bundle = {
        #if os(macOS)
        if let url = Bundle.main.url(forResource: "KeyboardShortcuts_KeyboardShortcuts", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }

        let rootURL = Bundle.main.bundleURL.appendingPathComponent("KeyboardShortcuts_KeyboardShortcuts.bundle")
        if let bundle = Bundle(url: rootURL) {
            return bundle
        }
        #endif

        let devURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Utilities.swift
            .deletingLastPathComponent()  // KeyboardShortcuts
            .deletingLastPathComponent()  // Sources
            .appendingPathComponent("KeyboardShortcuts_KeyboardShortcuts.bundle")
        if let bundle = Bundle(url: devURL) {
            return bundle
        }

        return Bundle.main
    }()
}
"""

marker = "}\n\n\nextension Data {"
if text.count(marker) != 1:
    raise SystemExit("Marker not found in Utilities.swift; patch failed.")

text = text.replace(marker, "}\n\n" + inject + "\n\nextension Data {")
path.write_text(text)
PY
}

KEYBOARD_SHORTCUTS_UTIL="$ROOT/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
PACKAGE_RESOLVED_HASH=$(python3 - "$ROOT/Package.resolved" <<'PY'
import hashlib
import sys
from pathlib import Path
print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
if [[ ! -f "$KEYBOARD_SHORTCUTS_UTIL" ]]; then
  # Resolve the pinned checkout before patching; a product build here would be discarded.
  python3 "$ROOT/Scripts/build_jobs.py" -- swift package resolve --force-resolved-versions
fi
if [[ ! -f "$KEYBOARD_SHORTCUTS_UTIL" ]]; then
  echo "ERROR: Dependency resolution did not provide KeyboardShortcuts/Utilities.swift." >&2
  exit 1
fi
patch_keyboard_shortcuts
python3 - "$ROOT/Package.resolved" "$PACKAGE_RESOLVED_HASH" "$KEYBOARD_SHORTCUTS_UTIL" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

resolved, expected_hash, utility = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
data = resolved.read_bytes()
if hashlib.sha256(data).hexdigest() != expected_hash:
    raise SystemExit("Package.resolved changed during dependency preparation.")
pin = next(item for item in json.loads(data)["pins"] if item["identity"] == "keyboardshortcuts")
revision = subprocess.check_output(
    ["git", "-C", str(utility.parent), "rev-parse", "HEAD"], text=True, timeout=15).strip()
if revision != pin["state"]["revision"]:
    raise SystemExit("KeyboardShortcuts checkout does not match Package.resolved.")
print("Prepared package dependency: " + json.dumps({
    "dependency": "keyboardshortcuts", "revision": revision,
    "resolved_sha256": expected_hash, "patched_source_sha256": hashlib.sha256(utility.read_bytes()).hexdigest(),
}, sort_keys=True), flush=True)
PY

# Resolve SwiftPM's current output path without relying on a fixed build-system layout.
# The output variable keeps the per-arch cache in this shell instead of losing it to
# command substitution.
swiftpm_bin_path() {
  local arch="$1"
  local output_var="$2"
  local cache_var="SWIFTPM_BIN_PATH_${arch//[^A-Za-z0-9]/_}"
  if [[ -z "${!cache_var+set}" ]]; then
    local resolved
    if ! resolved=$(codexbar_swiftpm_bin_path "$CONF" "$arch"); then
      return 1
    fi
    printf -v "$cache_var" '%s' "$resolved"
  fi
  printf -v "$output_var" '%s' "${!cache_var}"
}

binary_has_arch() {
  local binary="$1"
  local arch="$2"
  [[ -f "$binary" ]] && lipo -archs "$binary" 2>/dev/null | tr ' ' '\n' | grep -qx "$arch"
}

# SwiftBuild can reuse one output directory for sequential per-arch builds. Snapshot
# each fresh slice before the next build can replace it.
PRODUCT_STAGE_ROOT="$ROOT/.build/package-products/$LOWER_CONF"
rm -rf "$PRODUCT_STAGE_ROOT"

stage_build_products() {
  local arch="$1"
  local bin_dir stage_dir name product
  swiftpm_bin_path "$arch" bin_dir

  stage_dir="$PRODUCT_STAGE_ROOT/$arch"
  mkdir -p "$stage_dir"
  for name in CodexBar CodexBarCLI CodexBarClaudeWatchdog; do
    if ! product=$(codexbar_require_product_file "$bin_dir" "$name" "$arch"); then
      return 1
    fi
    if ! binary_has_arch "$product" "$arch"; then
      echo "ERROR: ${product} does not contain required architecture: ${arch}" >&2
      return 1
    fi
    cp "$product" "$stage_dir/$name"
  done
  if [[ -d "$bin_dir/CodexBar.dSYM" ]]; then
    cp -R "$bin_dir/CodexBar.dSYM" "$stage_dir/"
  fi
}

for ARCH in "${ARCH_LIST[@]}"; do
  python3 "$ROOT/Scripts/build_jobs.py" -- swift build -c "$CONF" --arch "$ARCH"
  stage_build_products "$ARCH"
done

APP_FINAL="$ROOT/CodexBar.app"
APP_STAGE="$ROOT/.build/package/CodexBar.app"
rm -rf "$APP_STAGE"
APP="$APP_STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/PlugIns"

# Convert new .icon bundle to .icns if present (macOS 14+/IconStudio export)
ICON_SOURCE="$ROOT/Icon.icon"
ICON_TARGET="$ROOT/Icon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
  iconutil --convert icns --output "$ICON_TARGET" "$ICON_SOURCE"
fi

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
APP_ENTITLEMENTS="${ENTITLEMENTS_DIR}/CodexBar.entitlements"
WIDGET_ENTITLEMENTS="${ENTITLEMENTS_DIR}/CodexBarWidget.entitlements"
mkdir -p "$ENTITLEMENTS_DIR"
if [[ "$ALLOW_LLDB" == "1" && "$LOWER_CONF" != "debug" ]]; then
  echo "ERROR: CODEXBAR_ALLOW_LLDB requires debug configuration" >&2
  exit 1
fi
# iCloud sync (CloudKit) requires restricted entitlements authorized by an embedded
# Developer ID provisioning profile. Only identity-signed release builds of the primary
# bundle ID carry them; adhoc/debug builds run with sync unavailable.
PROVISIONING_PROFILE_SOURCE="$ROOT/Scripts/profiles/CodexBar-DeveloperID.provisionprofile"
EMBED_PROVISIONING_PROFILE=0
ICLOUD_ENTITLEMENT_KEYS=""
# JONES(trial-identity): a fork never embeds the upstream provisioning profile.
if [[ "$JONES_OVERLAY" == "1" ]]; then
  PROVISIONING_PROFILE_SOURCE="${JONES_PROVISIONING_PROFILE:-}"
fi
if [[ "$SIGNING_MODE" == "identity" && "$LOWER_CONF" == "release" && ( "$BUNDLE_ID" == "com.steipete.codexbar" || "$JONES_OVERLAY" == "1" ) ]]; then
  if [[ ! -f "$PROVISIONING_PROFILE_SOURCE" ]]; then
    echo "ERROR: Missing $PROVISIONING_PROFILE_SOURCE (required for iCloud entitlements in release builds)" >&2
    exit 1
  fi
  EMBED_PROVISIONING_PROFILE=1
  ICLOUD_ENTITLEMENT_KEYS=$(cat <<ICLOUD
    <key>com.apple.application-identifier</key>
    <string>${APP_TEAM_ID}.${BUNDLE_ID}</string>
    <key>com.apple.developer.team-identifier</key>
    <string>${APP_TEAM_ID}</string>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>${ICLOUD_ID}</string>
    </array>
    <key>com.apple.developer.icloud-container-environment</key>
    <string>Production</string>
ICLOUD
)
fi
cat > "$APP_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>${APP_GROUP_ID}</string>
    </array>
${ICLOUD_ENTITLEMENT_KEYS}
    $(if [[ "$ALLOW_LLDB" == "1" ]]; then echo "    <key>com.apple.security.get-task-allow</key><true/>"; fi)
</dict>
</plist>
PLIST
cat > "$WIDGET_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>${APP_GROUP_ID}</string>
    </array>
</dict>
</plist>
PLIST

if [[ "${JONES_SIGNING_MODE:-adhoc}" == "developer-id" ]]; then
  python3 -B "$ROOT/Scripts/jones_signing.py" \
    --app-profile "$JONES_PROVISIONING_PROFILE" --widget-profile "$JONES_WIDGET_PROVISIONING_PROFILE" \
    --certificate-sha1 "$JONES_SIGNING_IDENTITY" \
    --app-entitlements "$APP_ENTITLEMENTS" --widget-entitlements "$WIDGET_ENTITLEMENTS"
fi
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CodexBar</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME:-CodexBar}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>CodexBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Peter Steinberger. MIT License.</string>
    <key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${PUBLIC_ED_KEY-AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=}</string>
    <key>SUEnableAutomaticChecks</key><${AUTO_CHECKS}/>
    <key>CodexBuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>CodexGitCommit</key><string>${GIT_COMMIT}</string>
    <key>CodexBarTeamID</key><string>${APP_TEAM_ID}</string>${JONES_METADATA:-}
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.steipete.codexbar.menu-layout-item</string>
            <key>UTTypeDescription</key><string>CodexBar menu bar layout token</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict/>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Resolve a built binary from the fresh per-arch snapshot or SwiftPM's reported directory.
resolve_binary_path() {
  local name="$1"
  local arch="$2"
  local bin_dir candidate
  swiftpm_bin_path "$arch" bin_dir
  if ! candidate=$(codexbar_resolve_staged_or_reported_file \
    "$PRODUCT_STAGE_ROOT" "$bin_dir" "$name" "$arch"); then
    return 1
  fi
  if ! binary_has_arch "$candidate" "$arch"; then
    echo "ERROR: ${candidate} does not contain required architecture: ${arch}" >&2
    return 1
  fi
  echo "$candidate"
}

verify_binary_arches() {
  local binary="$1"; shift
  local expected=("$@")
  local actual
  actual=$(lipo -archs "$binary")
  local actual_count expected_count
  actual_count=$(wc -w <<<"$actual" | tr -d ' ')
  expected_count=${#expected[@]}
  if [[ "$actual_count" -ne "$expected_count" ]]; then
    echo "ERROR: $binary arch mismatch (expected: ${expected[*]}, actual: ${actual})" >&2
    exit 1
  fi
  for arch in "${expected[@]}"; do
    if [[ "$actual" != *"$arch"* ]]; then
      echo "ERROR: $binary missing arch $arch (have: ${actual})" >&2
      exit 1
    fi
  done
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    if ! src=$(resolve_binary_path "$name" "$arch"); then
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
  verify_binary_arches "$dest" "${ARCH_LIST[@]}"
}

strip_release_binary() {
  local binary="$1"
  if [[ "$LOWER_CONF" != "release" ]]; then
    return 0
  fi
  if [[ ! -f "$binary" ]]; then
    return 0
  fi
  xcrun strip -x "$binary"
}

ensure_widget_extension_project() {
  local spec="$ROOT/WidgetExtension/project.yml"
  local project_dir="$ROOT/WidgetExtension/CodexBarWidgetExtension.xcodeproj"
  if [[ -f "$project_dir/project.pbxproj" ]]; then
    return
  fi
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: Missing ${project_dir}; install xcodegen or restore the generated project." >&2
    exit 1
  fi

  # The tracked project is authoritative. Regenerating it during packaging records the checkout
  # directory's spelling in a package file reference and leaves release worktrees dirty.
  xcodegen generate --spec "$spec" --project "$ROOT/WidgetExtension" --quiet
}

build_widget_extension() {
  local xcode_conf="Release"
  if [[ "$LOWER_CONF" == "debug" ]]; then
    xcode_conf="Debug"
  fi

  ensure_widget_extension_project

  local derived_dir="$ROOT/.build/xcode-widget-extension-${LOWER_CONF}"
  local project_dir="$ROOT/WidgetExtension/CodexBarWidgetExtension.xcodeproj"
  local build_log="$derived_dir/xcodebuild.log"
  local timeout_seconds="${CODEXBAR_WIDGET_EXTENSION_TIMEOUT_SECONDS:-900}"
  local archs="${ARCH_LIST[*]}"

  mkdir -p "$derived_dir"
  echo "Building CodexBarWidget Xcode extension (${xcode_conf}, ${archs})." >&2
  python3 "$ROOT/Scripts/package_widget.py" --log "$build_log" \
    --products "$derived_dir/Build" --timeout "$timeout_seconds" -- xcodebuild \
    -project "$project_dir" \
    -scheme CodexBarWidgetExtension \
    -configuration "$xcode_conf" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived_dir" \
    -skipPackageUpdates \
    -disableAutomaticPackageResolution \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -showBuildTimingSummary \
    CODEXBAR_WIDGET_BUNDLE_ID="$WIDGET_BUNDLE_ID" \
    CODEXBAR_TEAM_ID="$APP_TEAM_ID" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS="$archs" \
    ONLY_ACTIVE_ARCH=NO \
    build || {
    echo "ERROR: Failed to build CodexBarWidget extension" >&2
    exit 1
  }

  local appex="$derived_dir/Build/Products/${xcode_conf}/CodexBarWidget.appex"
  if [[ ! -f "$appex/Contents/MacOS/CodexBarWidget" ]]; then
    echo "ERROR: Missing Xcode-built CodexBarWidget.appex at ${appex}" >&2
    exit 1
  fi
  echo "$appex"
}

install_widget_extension() {
  local src_appex
  src_appex="$(build_widget_extension)"
  local widget_app="$APP/Contents/PlugIns/CodexBarWidget.appex"
  rm -rf "$widget_app"
  mkdir -p "$APP/Contents/PlugIns"
  cp -R "$src_appex" "$widget_app"
  verify_binary_arches "$widget_app/Contents/MacOS/CodexBarWidget" "${ARCH_LIST[@]}"
}

install_binary "CodexBar" "$APP/Contents/MacOS/CodexBar"
strip_release_binary "$APP/Contents/MacOS/CodexBar"
# Ship CodexBarCLI alongside the app for easy symlinking.
install_binary "CodexBarCLI" "$APP/Contents/Helpers/CodexBarCLI"
strip_release_binary "$APP/Contents/Helpers/CodexBarCLI"
# Watchdog helper: ensures `claude` probes die when CodexBar crashes/gets killed.
install_binary "CodexBarClaudeWatchdog" "$APP/Contents/Helpers/CodexBarClaudeWatchdog"
strip_release_binary "$APP/Contents/Helpers/CodexBarClaudeWatchdog"
install_widget_extension
strip_release_binary "$APP/Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget"

swiftpm_bin_path "${ARCH_LIST[0]}" PREFERRED_BUILD_DIR

# Embed Sparkle.framework
SPARKLE_SOURCE=$(codexbar_require_product_directory "$PREFERRED_BUILD_DIR" Sparkle.framework packaging)
cp -R "$SPARKLE_SOURCE" "$APP/Contents/Frameworks/"
chmod -R a+rX "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/CodexBar"
# Re-sign Sparkle and all nested components with the selected package identity.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  CODESIGN_ID="-"
  CODESIGN_ARGS=(--force --sign "$CODESIGN_ID")
elif [[ "$ALLOW_LLDB" == "1" ]]; then
  CODESIGN_ID="-"
  CODESIGN_ARGS=(--force --sign "$CODESIGN_ID")
else
  CODESIGN_ID="${APP_IDENTITY:-Developer ID Application: Peter Steinberger (Y5PE65HELJ)}"
  if [[ "$JONES_OVERLAY" == "1" ]]; then CODESIGN_ID="$JONES_SIGNING_IDENTITY"; fi # JONES(trial-identity)
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$CODESIGN_ID")
fi
if [[ "${JONES_SIGNING_MODE:-adhoc}" == "developer-id" && -n "${JONES_SIGNING_KEYCHAIN:-}" ]]; then
  CODESIGN_ARGS+=(--keychain "$JONES_SIGNING_KEYCHAIN")
fi
function resign() { codesign "${CODESIGN_ARGS[@]}" "$1"; }
# Validate Sparkle's nested layout before signing so framework layout drift fails clearly.
SPARKLE_SIGNING_TARGETS=$(codexbar_sparkle_signing_targets "$SPARKLE")
while IFS= read -r SPARKLE_TARGET; do
  resign "$SPARKLE_TARGET"
done <<<"$SPARKLE_SIGNING_TARGETS"

if [[ -f "$ICON_TARGET" ]]; then
  cp "$ICON_TARGET" "$APP/Contents/Resources/Icon.icns"
fi

# Bundle app resources (provider icons, etc.).
APP_RESOURCES_DIR="$ROOT/Sources/CodexBar/Resources"
if [[ -d "$APP_RESOURCES_DIR" ]]; then
  cp -R "$APP_RESOURCES_DIR/." "$APP/Contents/Resources/"
fi
if [[ ! -f "$APP/Contents/Resources/Icon-classic.icns" ]]; then
  echo "ERROR: Missing Icon-classic.icns in app bundle resources." >&2
  exit 1
fi

# SwiftPM resource bundles (e.g. KeyboardShortcuts) are emitted next to the built binary.
# Select the Core contract from tracked source inputs, never stale build output.
if [[ "$(git -C "$ROOT" rev-parse --show-toplevel)" != "$ROOT" ]]; then
  echo "ERROR: Core resource contract requires the exact source checkout root." >&2
  exit 1
fi
CORE_RESOURCE_INPUTS="$(git -C "$ROOT" ls-files -- Sources/CodexBarCore/Resources/)"
CORE_RESOURCES_REQUIRED=0
if [[ -n "$CORE_RESOURCE_INPUTS" ]]; then
  CORE_RESOURCES_REQUIRED=1
fi
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    bundle_name="$(basename "$bundle")"
    if [[ "$bundle_name" == "CodexBar_CodexBarCore.bundle" && "$CORE_RESOURCES_REQUIRED" == "0" ]]; then
      continue
    fi
    cp -R "$bundle" "$APP/Contents/Resources/"
  done
fi
if [[ ! -d "$APP/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle" ]]; then
  echo "ERROR: Missing KeyboardShortcuts SwiftPM resource bundle (Settings → Keyboard shortcut will crash)." >&2
  echo "Expected: ${PREFERRED_BUILD_DIR}/KeyboardShortcuts_KeyboardShortcuts.bundle" >&2
  exit 1
fi

# Builds retaining Core resources resolve them beside the helper executable.
# Keep the adjacent copy only while current source still requires that bundle.
CORE_RESOURCE_BUNDLE="${PREFERRED_BUILD_DIR}/CodexBar_CodexBarCore.bundle"
if [[ "$CORE_RESOURCES_REQUIRED" == "1" ]]; then
  if [[ ! -d "$CORE_RESOURCE_BUNDLE" ]]; then
    echo "ERROR: Missing CodexBarCore SwiftPM resource bundle for CodexBarCLI." >&2
    echo "Expected: ${CORE_RESOURCE_BUNDLE}" >&2
    exit 1
  fi
  rm -rf "$APP/Contents/Helpers/CodexBar_CodexBarCore.bundle"
  cp -R "$CORE_RESOURCE_BUNDLE" "$APP/Contents/Helpers/"
fi

# Ensure contents are writable before stripping attributes and signing.
chmod -R u+w "$APP"

# Strip extended attributes to prevent AppleDouble (._*) files that break code sealing
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# Sign helper binaries if present
if [[ -f "${APP}/Contents/Helpers/CodexBarCLI" ]]; then
  codesign "${CODESIGN_ARGS[@]}" "${APP}/Contents/Helpers/CodexBarCLI"
fi
if [[ "$CORE_RESOURCES_REQUIRED" == "1" && -d "${APP}/Contents/Helpers/CodexBar_CodexBarCore.bundle" ]]; then
  codesign "${CODESIGN_ARGS[@]}" "${APP}/Contents/Helpers/CodexBar_CodexBarCore.bundle"
fi
if [[ -f "${APP}/Contents/Helpers/CodexBarClaudeWatchdog" ]]; then
  codesign "${CODESIGN_ARGS[@]}" "${APP}/Contents/Helpers/CodexBarClaudeWatchdog"
fi

# JONES(trial-identity): widget metadata carries the same identity; CLI reads its enclosing app metadata.
if [[ "$JONES_OVERLAY" == "1" && -d "${APP}/Contents/PlugIns/CodexBarWidget.appex" ]]; then
  WIDGET_INFO="${APP}/Contents/PlugIns/CodexBarWidget.appex/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :JonesSigningMode string ${JONES_SIGNING_MODE}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesStateKey string jones" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesAppBundleID string ${BUNDLE_ID}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesAppGroupID string ${APP_GROUP_ID}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesICloudID string ${ICLOUD_ID}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesSourceRevision string ${JONES_SOURCE_REVISION}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesBuildOrigin string ${JONES_BUILD_ORIGIN}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesBuildRun string ${JONES_BUILD_RUN}" "$WIDGET_INFO"
  /usr/libexec/PlistBuddy -c "Add :JonesUpdateChannel string ${JONES_UPDATE_CHANNEL}" "$WIDGET_INFO"
fi

# Sign widget extension if present
if [[ "${JONES_SIGNING_MODE:-adhoc}" == "developer-id" ]]; then
  cp "$JONES_WIDGET_PROVISIONING_PROFILE" "$APP/Contents/PlugIns/CodexBarWidget.appex/Contents/embedded.provisionprofile"
fi
if [[ -d "${APP}/Contents/PlugIns/CodexBarWidget.appex" ]]; then
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP/Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget"
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP/Contents/PlugIns/CodexBarWidget.appex"
fi

# Embed the Developer ID provisioning profile (authorizes the iCloud entitlements;
# Gatekeeper re-validates it at every launch, so it must be sealed into the signature).
if [[ "$EMBED_PROVISIONING_PROFILE" == "1" ]]; then
  cp "$PROVISIONING_PROFILE_SOURCE" "$APP/Contents/embedded.provisionprofile"
fi

# Finally sign the app bundle itself
codesign "${CODESIGN_ARGS[@]}" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP"

rm -rf "$APP_FINAL"
mv "$APP" "$APP_FINAL"
APP="$APP_FINAL"
verify_packaged_app_integrity "$APP"
# Release gate for the 0.48.0 crash class (#2738): launch the packaged binary
# with the build checkout unreadable so a `Bundle.module`-style compile-time
# path dependency fails packaging here instead of on user machines.
if [[ "$LOWER_CONF" == "release" ]]; then
  "$ROOT/Scripts/verify_packaged_app_launch.sh" "$APP"
fi
echo "Created $APP"
