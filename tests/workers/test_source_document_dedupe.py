from __future__ import annotations

import sys
import unittest
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS_ROOT))

import source_document_dedupe as dedupe  # noqa: E402


class SourceDocumentDedupeTests(unittest.TestCase):
    def test_all_source_document_foreign_keys_are_redirected_before_delete(self) -> None:
        references = {(table, column, key) for table, column, key in dedupe.REFERENCE_COLUMNS}
        self.assertIn(
            ("curriculum_alignments", "source_document_id", "curriculumAlignmentsUpdated"),
            references,
        )
        self.assertIn(("source_regions", "source_document_id", "sourceRegionsUpdated"), references)


if __name__ == "__main__":
    unittest.main()
