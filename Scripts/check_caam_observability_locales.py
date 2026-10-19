#!/usr/bin/env python3
"""Check feature literal-key coverage without requiring Apple's plutil.

This bounded source/catalog check does not replace native strings parsing or Swift tests.
The explicit --sync-locales maintenance mode adds only missing keys, with labeled English
fallbacks; it never claims to translate text or changes existing translations.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/CodexBar/Resources"
SOURCE_NAMES = (
    "CAAMEnvironmentControlsView.swift",
    "CAAMEnvironmentCoordinator.swift",
    "CodexObservabilityHubView.swift",
    "PreferencesCodexEnvironmentsSection.swift",
    "PreferencesProvidersPane.swift",
)
LOCALES = (
    "en", "ar", "ca", "de", "es", "fa", "fr", "gl", "id", "it", "ja", "ko", "nl",
    "pl", "pt-BR", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
)
LITERAL = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', re.MULTILINE)
PLACEHOLDER = re.compile(r'%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGaAcsp]')


def bounded_read(path: Path) -> str:
    if not path.resolve().is_relative_to(ROOT) or path.stat().st_size > 1024 * 1024:
        raise ValueError("Source or catalog is outside the repository or exceeds the size limit")
    return path.read_text(encoding="utf-8")


def signature(value: str) -> list[str]:
    value = value.replace("%%", "")
    return sorted(re.sub(r'^%\d+\$', "%", match.group(0)) for match in PLACEHOLDER.finditer(value))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sync-locales", action="store_true", help="append explicitly labeled English fallback keys")
    options = parser.parse_args()
    keys: set[str] = set()
    for name in SOURCE_NAMES:
        keys.update(LITERAL.findall(bounded_read(ROOT / "Sources/CodexBar" / name)))
    english_path = RESOURCES / "en.lproj/Localizable.strings"
    english = dict(ENTRY.findall(bounded_read(english_path)))
    new_keys = sorted(keys - english.keys())
    if options.sync_locales:
        for locale in LOCALES:
            path = RESOURCES / f"{locale}.lproj/Localizable.strings"
            text = bounded_read(path)
            existing = dict(ENTRY.findall(text))
            # Reconcile every feature key so interruption after the English write is restart-safe.
            missing = sorted(keys - existing.keys())
            if missing:
                addition = "\n/* CAAM observability: English fallback pending translation review. */\n"
                addition += "".join(f'"{key}" = "{english.get(key, key)}";\n' for key in missing)
                path.write_text(text.rstrip() + "\n" + addition, encoding="utf-8")
        print(f"Registered {len(new_keys)} new English keys across {len(LOCALES)} catalogs (not translations).")
        english = dict(ENTRY.findall(bounded_read(english_path)))
    failures: list[str] = []
    for locale in LOCALES:
        entries = dict(ENTRY.findall(bounded_read(RESOURCES / f"{locale}.lproj/Localizable.strings")))
        for key in sorted(keys):
            value = entries.get(key)
            if value is None:
                failures.append(f"{locale}: missing {key}")
            elif signature(value) != signature(english.get(key, key)):
                failures.append(f"{locale}: placeholder mismatch {key}")
    if failures:
        print("\n".join(failures[:30]))
        print(f"FAILED: {len(failures)} coverage/placeholder issues.")
        return 1
    print(f"PASS: {len(keys)} feature literal keys covered in {len(LOCALES)} catalogs; placeholders match.")
    print("Native plutil parsing, linguistic review, and Swift execution are separate checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
