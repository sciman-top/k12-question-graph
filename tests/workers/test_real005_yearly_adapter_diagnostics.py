import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import real005_yearly_adapter_diagnostics as diagnostics  # noqa: E402


def source_row(year: int, source_type: str, path: str, source_id: str) -> dict:
    return {
        "source_document_id": source_id,
        "source_type": source_type,
        "source_title": f"{year}-{source_type}",
        "year": year,
        "original_file_name": pathlib.Path(path).name,
        "relative_path": path,
        "sha256": "a" * 64,
        "size_bytes": 100,
    }


class YearlyAdapterDiagnosticsTests(unittest.TestCase):
    def test_build_sources_merges_combined_2020_roles_by_physical_path(self) -> None:
        path = "original/aa/bb/combined.pdf"
        rows = [
            source_row(2020, "local_exam_paper", path, "paper-id"),
            source_row(2020, "answer_or_solution", path, "answer-id"),
            source_row(2020, "exam_analysis_report", "original/cc/dd/report.pdf", "report-id"),
        ]

        sources = diagnostics.build_sources_from_rows(rows)

        self.assertEqual(len(sources[2020]), 2)
        combined = next(source for source in sources[2020] if source["relativePath"] == path)
        self.assertEqual(set(combined["roles"]), {"paper", "answer"})
        self.assertEqual(set(combined["sourceDocumentIds"]), {"paper-id", "answer-id"})

    def test_build_sources_keeps_all_three_required_roles(self) -> None:
        rows = [
            source_row(2025, "local_exam_paper", "original/a/paper.pdf", "paper-id"),
            source_row(2025, "answer_or_solution", "original/b/answer.pdf", "answer-id"),
            source_row(2025, "exam_year_report", "original/c/report.pdf", "report-id"),
        ]

        sources = diagnostics.build_sources_from_rows(rows)

        self.assertEqual({role for source in sources[2025] for role in source["roles"]}, {"paper", "answer", "report"})


if __name__ == "__main__":
    unittest.main()
