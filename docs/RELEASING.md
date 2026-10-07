---
summary: "CodexBar release checklist: package, sign, notarize, appcast, and asset validation."
read_when:
  - Starting a CodexBar release
  - Updating signing/notarization or appcast steps
  - Validating release assets or Sparkle feed
---

# Release process (CodexBar)

The main app uses SwiftPM; packaging also builds the widget extension through
`WidgetExtension/CodexBarWidgetExtension.xcodeproj`. The checked-in upstream
configuration serves the Sparkle feed from `appcast.xml` on `main` and hosts
enclosures on GitHub Releases.

## Target and authority

This source repository is `Jones-Systems/CodexBar`, but `.mac-release.env` still
targets `steipete/CodexBar`, its download URLs, feed, bundle identity, and signing
configuration. `Scripts/sign-and-notarize.sh` also names the upstream Developer ID
directly. The examples below describe that existing upstream flow; they are not a
configured Jones Systems release route.

Before execution, establish the intended repository, feed, download destination,
bundle identity, signing identity, Sparkle key relationship, tag behavior, and
publication authority. Changing the repository name alone is insufficient.
The manifest includes `MAC_RELEASE_TAG_FORCE=1`; documentation does not authorize
replacing an existing tag.

`Scripts/mac-release` resolves `MAC_RELEASE_TOOL`, a sibling `agent-scripts` checkout,
or `~/Projects/agent-scripts`. Read the release guidance accompanying the exact
resolved helper; the historical location is
`~/Projects/agent-scripts/docs/RELEASING-MAC.md`. Reconcile differences against the
actual CodexBar scripts and the authorized target before starting. This checkout
does not prove the installed helper's revision, availability, or behavior.

## Expectations

An authorized end-to-end release includes version and changelog updates, packaging,
signing, notarization, publication of the requested assets and release, appcast
generation/publication, and direct verification of the intended feed and enclosure.
A package-only request does not include that publication workflow.
`make release` is the package-only Makefile target, though its release packaging
invokes an app-launch smoke check.

Keep the release script in the foreground and wait for it to finish. Access to signing
material, credentials, shared release state, or publication destinations must remain
within the approved operation.

### Release automation notes (Scripts/release.sh)

These notes describe the expected external-helper contract. The local script only
delegates through `Scripts/mac-release`; verify the resolved helper before relying
on its prechecks, key selection, tag handling, or publication behavior.

- Rebuilds both release architectures and notarizes before publishing; set `CODEXBAR_FORCE_CLEAN=1` when a cache-free SwiftPM rebuild is required.
- Fails fast if: git tree is dirty, the top changelog section is still “Unreleased” or mismatched, the target version already exists in the appcast, or the build number is not greater than the latest appcast entry.
- Sparkle key probe runs up front; appcast entry + signature verified automatically after generation.
- Release notes are extracted directly from the current changelog section and passed to the GitHub release (no manual notes flag needed).
- Sparkle appcast notes are generated as HTML from the same changelog section and embedded into the appcast entry.
- The existing flow expects `swiftformat`, `swiftlint`, `swift`, Sparkle signing/appcast
  tools, `gh`, `python3`, `zip`, and `curl`, plus authorized notarization credentials.
  Verify exact prerequisites against the resolved helper. Sparkle key selection must
  follow the manifest and helper; do not assume Keychain is the default source.

## Prereqs
- Xcode 26+ installed at `/Applications/Xcode.app` (for ictool/iconutil and SDKs).
- Developer ID Application cert installed: `Developer ID Application: Peter Steinberger (Y5PE65HELJ)`.
- ASC API creds in env: `APP_STORE_CONNECT_API_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`.
- Sparkle: for the configured upstream release, preserve the manifest's legacy public
  key `AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI=` and matching
  `MAC_RELEASE_SIGNING_KEY_FILE`. The manifest comments specify
  `SPARKLE_PRIVATE_KEY_FILE` precedence and Keychain use when the configured local file
  is absent; verify that behavior in the resolved external helper. Do not use
  `sparkle-private-key-KEEP-SECURE.txt`, which belongs to VibeTunnel. A different release
  target requires its own verified key relationship, not reuse inferred from a filename
  or this guidance.
- Supply only the environment and credential access required by the authorized release;
  do not load an entire shell profile merely because it is mentioned in this guide.
- Shared release helper: `Scripts/mac-release` resolves `MAC_RELEASE_TOOL`, sibling `../agent-scripts`, or `~/Projects/agent-scripts`.

## Icon (glass .icon → .icns)
```
./Scripts/build_icon.sh Icon.icon CodexBar
```
Uses Xcode’s `ictool` + transparent padding + iconset → Icon.icns.

## Build, sign, notarize (universal: arm64 + x86_64)
```
./Scripts/sign-and-notarize.sh
```
What it does:
- `swift build -c release --arch arm64` and `swift build -c release --arch x86_64`
- Packages `CodexBar.app` with Info.plist and Icon.icns
- Embeds Sparkle.framework, Updater, Autoupdate, XPCs
- Codesigns **everything** with runtime + timestamp (deep) and adds rpath
- Zips to `CodexBar-macos-universal-<version>.zip`
- Submits to notarytool, waits, staples, validates

Gotchas fixed:
- Sparkle needs signing for framework, Autoupdate, Updater, XPCs (Downloader/Installer) or notarization fails.
- Use `--timestamp` and `--deep` when signing the app to avoid invalid signature errors.
- Avoid `unzip` — it can add AppleDouble `._*` files that break the sealed signature and trigger “app is damaged”. Use Finder or `ditto -x -k CodexBar-<ver>.zip /Applications`. If Gatekeeper complains, delete the app bundle, re-extract with `ditto`, then `spctl -a -t exec` to verify.
- Manual sanity check before uploading: `find CodexBar.app -name '._*'` should return nothing; then `spctl --assess --type execute --verbose CodexBar.app` and `codesign --verify --deep --strict --verbose CodexBar.app` should both pass on the packaged bundle.

## iCloud sync (CloudKit)
Release builds embed `Scripts/profiles/CodexBar-DeveloperID.provisionprofile` at `Contents/embedded.provisionprofile` and claim the iCloud entitlements (`Scripts/package_app.sh` does both automatically; it fails hard if the profile file is missing). The profile expires 2044-07-29; Gatekeeper re-validates it at every launch.

Schema changes: any new record type or field in `Sources/CodexBar*/Sync/` must be reflected in `Scripts/cloudkit/schema.ckdb` and deployed **before** shipping the build:
```
CLOUDKIT_MANAGEMENT_TOKEN=… Scripts/cloudkit/deploy_schema.sh development   # validate
CLOUDKIT_MANAGEMENT_TOKEN=… Scripts/cloudkit/deploy_schema.sh production
```
Tokens come from the CloudKit Console (icloud.developer.apple.com → account → Tokens). Developer ID builds can only reach the Production environment — an undeployed schema means every sync save fails with "unknown record type".

## Appcast (Sparkle)
After notarization, or let `Scripts/release.sh` do this:
```
./Scripts/make_appcast.sh CodexBar-macos-universal-0.1.0.zip \
  https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml
```
Generates HTML release notes from `CHANGELOG.md` (via `Scripts/changelog-to-html.sh`) and embeds them into the appcast entry.
Uploads not handled automatically—commit/publish appcast + zip to the feed location (GitHub Releases/raw URL).

## Tag & release
```
./Scripts/release.sh
```

## Homebrew (Cask)
CodexBar ships a Homebrew **Cask** in `../homebrew-tap`. When installed via Homebrew, CodexBar disables Sparkle and the app
must be updated via `brew`.

After publishing the GitHub release, `.github/workflows/release-cli.yml` builds the macOS, glibc Linux, and static musl Linux CLI tarballs for arm64 and x86_64, uploads them plus checksums, then dispatches the Homebrew tap update for both the CLI formula and app cask. Homebrew continues to use the glibc Linux assets. If the final dispatch is rate-limited, the tarballs and app zip may still be present; rerun or manually update the tap formula/cask from the published assets.

## Checklist (quick)
- [ ] Verify the authorized release target and the exact resolved external helper; read
  its accompanying guide and reconcile it with the current CodexBar source.
- [ ] Update `version.env`, CHANGELOG, and any affected displayed version text. Finalize
  the changelog section expected by the resolved helper.
- [ ] `swiftformat`, `swiftlint`, `make test` (zero warnings/errors)
- [ ] `./Scripts/build_icon.sh` if icon changed
- [ ] `./Scripts/sign-and-notarize.sh`
- [ ] Generate the Sparkle appcast through the verified helper, preserving the authorized
  target’s matching public/private key configuration. Confirm actual precedence for
  `SPARKLE_PRIVATE_KEY_FILE`, `MAC_RELEASE_SIGNING_KEY_FILE`, and Keychain fallback.
  - Upload the dSYM archive alongside the app zip on the GitHub release; the release script now automates this and will fail if it’s missing.
  - After publishing the release and the Release CLI workflow finishes, run `Scripts/check-release-assets.sh <tag>` to confirm the app zip, dSYM zip, CLI tarballs, and CLI checksums are present on GitHub.
  - Generate the appcast + HTML release notes: `./Scripts/make_appcast.sh CodexBar-macos-universal-<ver>.zip https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml`
  - Beta channel: prefix the command with `SPARKLE_CHANNEL=beta` to tag the entry.
  - Verify the enclosure signature + size: `./Scripts/verify_appcast.sh <ver>`
- [ ] Publish the tag and GitHub release with the app zip and dSYM, then push the generated `appcast.xml` commit to `main` so the Sparkle feed and enclosure URL are both live (avoid 404s)
- [ ] Homebrew tap: wait for the Release CLI workflow to update `../homebrew-tap/Casks/codexbar.rb` (app zip url + sha256) and `../homebrew-tap/Formula/codexbar.rb` (CLI tarball urls + sha256), then verify:
  - `gh run watch <release-cli-run-id> --exit-status`
  - `Scripts/check-release-assets.sh v<version>`
  - `brew uninstall --cask codexbar || true`
  - `brew untap steipete/tap || true; brew tap steipete/tap`
  - `brew install --cask steipete/tap/codexbar && open -a CodexBar`
- [ ] Version continuity: confirm the new version is the immediate next patch/minor (no gaps) and CHANGELOG has no skipped numbers (e.g., after 0.2.0 use 0.2.1, not 0.2.2)
- [ ] Changelog sanity: single top-level title, no duplicate version sections, versions strictly descending with no repeats
- [ ] Release pages: title format `CodexBar <version>`, notes as Markdown list (no stray blank lines)
- [ ] Changelog/release notes are user-facing: avoid internal-only bullets (build numbers, script bumps) and keep entries concise
- [ ] Download uploaded `CodexBar-macos-universal-<ver>.zip`, unzip via `ditto`, run, and verify signature (`spctl -a -t exec -vv CodexBar.app` + `stapler validate`)
- [ ] Confirm `appcast.xml` points to the new zip/version and renders the HTML release notes (not escaped tags)
- [ ] Verify on GitHub Releases: app zip, dSYM, CLI archives, and checksums are present; release notes match the changelog and the version/tag are correct
- [ ] Open the appcast URL in browser to confirm the new entry is visible and enclosure URL is reachable
- [ ] Manually visit the enclosure URL (curl -I) to ensure 200/OK (no 404) after publishing assets/release
- [ ] Ensure `sparkle:edSignature` is present for the enclosure in appcast (generated by `generate_appcast` with the ed25519 key)
- [ ] When creating the GitHub release, paste the CHANGELOG entry as Markdown list (one `-` per line, blank line between sections); visually confirm bullets render correctly after publishing
- [ ] Keep a previous signed build in `/Applications/CodexBar.app` to test Sparkle delta/full update to the new release
- [ ] Manual Gatekeeper sanity: after packaging, `find CodexBar.app -name '._*'` is empty, `spctl --assess --type execute --verbose CodexBar.app` and `codesign --verify --deep --strict --verbose CodexBar.app` succeed
- [ ] For Sparkle verification: if replacing `/Applications/CodexBar.app`, quit first, replace, relaunch, and test update
- **Definition of “done” for a release:** all of the above are complete, the appcast/enclosure link resolves, Homebrew cask
  installs, and a previous public build can update to the new one via Sparkle. Anything short of that is not a finished release.

## Troubleshooting
- **White plate icon**: regenerate icns via `build_icon.sh` (ictool) to ensure transparent padding.
- **Notarization invalid**: verify deep+timestamp signing, especially Sparkle’s Autoupdate/Updater and XPCs; rerun package + sign-and-notarize.
- **App won’t launch**: ensure Sparkle.framework is embedded under `Contents/Frameworks` and rpath added; codesign deep.
- **App “damaged” dialog after unzip**: re-extract with `ditto -x -k`, removing any `._*` files, then re-verify with `spctl`.
- **Update download fails (404)**: ensure the release asset referenced in appcast exists and is published in the corresponding GitHub release; verify with `curl -I <enclosure-url>`.
