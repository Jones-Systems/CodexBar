#!/usr/bin/env python3
"""Render a measurement-only adapter for two exact historical package scripts.

This is deliberately not a new package_app.sh signing mode. The selected blocks
retain the historical assembly, including work that originally followed signing.
The receipt makes every selection and substitution reviewable.
"""

import hashlib
from pathlib import Path
import shlex


BASELINE = "91bd5fb4af704da9181212bea636d527a058e615"
CANDIDATE = "ba523f60b7161e70a3afd201f87d49dd2b0e37fe"
PACKAGE_HASHES = {
    BASELINE: "2969c6c6d3fc3e039a5f107e7eac4c91951911ed757510caf607daa8690d09f9",
    CANDIDATE: "2936801eea2a84a46b661d2d0f4e0efb1e234f17d34a959a7e4abab86233df20",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


class Adapter:
    def __init__(self, source, revision):
        self.source = Path(source)
        self.revision = revision
        data = (self.source / "Scripts/package_app.sh").read_bytes()
        if revision not in PACKAGE_HASHES or digest(data) != PACKAGE_HASHES[revision]:
            raise ValueError("unsupported historical packager bytes/revision")
        self.text = data.decode()
        self.blocks = []

    def block(self, name, start, end, replacements=()):
        if self.text.count(start) != 1 or self.text.count(end) != 1:
            raise ValueError("historical adapter marker is ambiguous: " + name)
        begin = self.text.index(start)
        stop = self.text.index(end, begin)
        original = self.text[begin:stop]
        rendered = original
        for before, after in replacements:
            if rendered.count(before) != 1:
                raise ValueError("historical adapter substitution is ambiguous: " + name)
            rendered = rendered.replace(before, after)
        self.blocks.append({
            "name": name, "start_line": self.text[:begin].count("\n") + 1,
            "end_line_exclusive": self.text[:stop].count("\n") + 1,
            "source_sha256": digest(original.encode()), "rendered_sha256": digest(rendered.encode()),
            "substitutions": [{"before": a, "after": b} for a, b in replacements],
        })
        return rendered

    def prepare(self):
        return "set -euo pipefail\n" + self.block(
            "locked-keyboardshortcuts-preparation", "patch_keyboard_shortcuts() {",
            "# Resolve SwiftPM's current output path", ((
                "swift package resolve --force-resolved-versions",
                'swift package --jobs 2 --cache-path "$MEAS_STATE/cache" '
                '--config-path "$MEAS_STATE/config" --security-path "$MEAS_STATE/security" '
                'resolve --force-resolved-versions',
            ),))

    def identity(self):
        return self.block(
            "identity", "resolve_package_identity() {", "resolve_package_signing_mode() {", (
                ('[[ -f "$ROOT/.mac-release.jones.env" ]]', '[[ -f "$MEAS_OVERLAY" ]]'),
                ('source "$ROOT/.mac-release.jones.env"', 'source "$MEAS_OVERLAY"'),
            ))

    def assemble(self, bin_dir, widget, provenance):
        prefix = "\n".join([
            "set -euo pipefail", "CONF=release", "LOWER_CONF=release", "SIGNING_MODE=adhoc",
            "ALLOW_LLDB=0", "ARCH_LIST=(arm64)",
            'source "$ROOT/version.env"', 'source "$ROOT/Scripts/package_product_paths.sh"',
            'source "$ROOT/Scripts/sparkle_signing_paths.sh"',
            "SWIFTPM_BIN_PATH_arm64=" + shlex.quote(str(bin_dir)),
        ]) + "\n"
        # Resolve the same Jones channel-none metadata before assembling. Historical
        # provenance is collected while source is clean; the common harness is separate.
        identity = self.identity()
        identity += 'resolve_package_identity\n' + provenance + '\nJONES_METADATA+="$JONES_PROVENANCE_METADATA"\n'
        functions = self.block(
            "product-path-and-staging", "swiftpm_bin_path() {", 'for ARCH in "${ARCH_LIST[@]}"; do\n  python3')
        functions += "stage_build_products arm64\n"
        layout = self.block("layout-and-app-metadata", 'APP_FINAL="$ROOT/CodexBar.app"',
                            "# Resolve a built binary", (
                                ('ICON_TARGET="$ROOT/Icon.icns"', 'ICON_TARGET="$MEAS_STATE/Icon.icns"'),
                            ))
        # Keep icon conversion in owned scratch rather than modifying a tracked icon.
        layout = 'if [[ -f "$ROOT/Icon.icns" ]]; then cp "$ROOT/Icon.icns" "$MEAS_STATE/Icon.icns"; fi\n' + layout
        functions2 = self.block("binary-install-and-strip", "resolve_binary_path() {",
                                "ensure_widget_extension_project() {")
        installs = self.block("install-products", 'install_binary "CodexBar"',
                              'swiftpm_bin_path "${ARCH_LIST[0]}" PREFERRED_BUILD_DIR', ((
                                  "install_widget_extension\n",
                                  'cp -R ' + shlex.quote(str(widget))
                                  + ' "$APP/Contents/PlugIns/CodexBarWidget.appex"\n'
                                  'verify_binary_arches '
                                  '"$APP/Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget" arm64\n',
                              ),))
        sparkle = self.block("framework-and-rpath", '# Embed Sparkle.framework', '# Re-sign Sparkle')
        resources = self.block("all-resources-and-attributes", 'if [[ -f "$ICON_TARGET" ]]; then',
                               '# Sign helper binaries')
        metadata = self.block("widget-metadata", '# JONES(trial-identity): widget metadata', '# Sign widget extension')
        return (prefix + identity + functions + layout + functions2 + installs
                + 'PREFERRED_BUILD_DIR=' + shlex.quote(str(bin_dir)) + '\n' + sparkle
                + 'codexbar_sparkle_signing_targets "$APP/Contents/Frameworks/Sparkle.framework" >/dev/null\n'
                + resources + metadata + '\nprintf "Complete non-distributable assembly: %s\\n" "$APP"\n')

    def receipt(self):
        return {"source_revision": self.revision, "historical_packager_sha256": PACKAGE_HASHES[self.revision],
                "adapter_sha256": digest(Path(__file__).read_bytes()), "blocks": self.blocks,
                "new_package_signature": False, "distributable": False,
                "omitted_effects": ["package codesign", "signature verification", "launch/resource smoke",
                                    "provisioning profile", "move to final app", "install/release"]}
