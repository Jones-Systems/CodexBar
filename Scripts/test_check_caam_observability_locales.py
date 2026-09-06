#!/usr/bin/env python3
"""Portable fixture tests for the feature's catalog maintenance helper, not Swift behavior."""

import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_caam_observability_locales as checker


class CatalogHelperTests(unittest.TestCase):
    def test_literal_keys_include_multiline_calls_and_escaped_quotes(self):
        text = 'L("One")\nL(\n "Two"\n)\nL("A \\"quote\\"")\nL(variable)'
        self.assertEqual(checker.LITERAL.findall(text), ["One", "Two", 'A \\"quote\\"'])

    def test_placeholder_positions_normalize_without_counting_literal_percent(self):
        self.assertEqual(checker.signature("%2$d · %1$@ · 100%%"), checker.signature("%@ · %d"))
        self.assertNotEqual(checker.signature("%.1f"), checker.signature("%d"))

    def test_bounded_read_rejects_outside_root(self):
        with tempfile.TemporaryDirectory() as directory:
            outside = Path(directory) / "outside"
            outside.write_text("fixture", encoding="utf-8")
            with self.assertRaises(ValueError):
                checker.bounded_read(outside)

    def test_bounded_read_rejects_oversized_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "large"
            fixture.write_bytes(b"x" * (1024 * 1024 + 1))
            with patch.object(checker, "ROOT", root), self.assertRaises(ValueError):
                checker.bounded_read(fixture)

    def test_sync_recovers_after_english_written_and_preserves_translation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / "Sources/CodexBar/Resources"
            for locale in ("en", "de"):
                (resources / f"{locale}.lproj").mkdir(parents=True)
            source = root / "Sources/CodexBar/Fixture.swift"
            source.write_text('L("Existing")\nL("Missing %@")', encoding="utf-8")
            english = resources / "en.lproj/Localizable.strings"
            german = resources / "de.lproj/Localizable.strings"
            english.write_text('"Existing" = "Existing";\n"Missing %@" = "Missing %@";\n', encoding="utf-8")
            german.write_text('"Existing" = "Vorhanden";\n', encoding="utf-8")
            with (
                patch.object(checker, "ROOT", root),
                patch.object(checker, "RESOURCES", resources),
                patch.object(checker, "SOURCE_NAMES", ("Fixture.swift",)),
                patch.object(checker, "LOCALES", ("en", "de")),
                patch("sys.argv", ["check", "--sync-locales"]),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(checker.main(), 0)
                first = german.read_bytes()
                self.assertEqual(checker.main(), 0)
                self.assertEqual(german.read_bytes(), first)
                self.assertIn('"Existing" = "Vorhanden";', first.decode("utf-8"))
                self.assertIn('"Missing %@" = "Missing %@";', first.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
