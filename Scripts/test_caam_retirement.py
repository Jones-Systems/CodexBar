#!/usr/bin/env python3
"""Check that shipped Swift source has no active CAAM integration; native behavior is tested separately."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CAAMRetirementTests(unittest.TestCase):
    def test_shipped_swift_source_has_no_caam_integration(self):
        references = []
        for path in sorted((ROOT / "Sources").rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            if re.search(r"caam", path.name + "\n" + text, re.IGNORECASE):
                references.append(str(path.relative_to(ROOT)))
        self.assertEqual(references, [], "Active CAAM source must be retired")


if __name__ == "__main__":
    unittest.main()
