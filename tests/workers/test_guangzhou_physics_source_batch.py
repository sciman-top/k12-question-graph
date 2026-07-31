import csv
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

from pypdf import PdfWriter


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import guangzhou_physics_source_batch as batch  # noqa: E402


def write_pdf(path: pathlib.Path, marker: str) -> None:
    writer = PdfWriter()
    writer.add_blank_page(width=72, height=72)
    writer.add_metadata({"/Subject": marker})
    with path.open("wb") as stream:
        writer.write(stream)


def create_complete_batch(root: pathlib.Path) -> None:
    for year in batch.YEARS:
        names = [f"{year}广州中考.pdf", f"{year}广州中考答案.pdf", f"{year}广州中考年报.pdf"]
        for name in names:
            write_pdf(root / name, name)


class SourceBatchTests(unittest.TestCase):
    def test_flat_file_roles_support_split_and_legacy_combined_sources(self) -> None:
        self.assertEqual(batch.classify_file_name("2019广州中考.pdf"), (2019, ["exam_paper"]))
        self.assertEqual(batch.classify_file_name("2021广州中考-参考答案.pdf"), (2021, ["answer_solution"]))
        self.assertEqual(batch.classify_file_name("2024广州中考（解析版）.pdf"), (2024, ["answer_solution"]))
        self.assertEqual(batch.classify_file_name("2020广州中考（含答案）.pdf"), (2020, ["exam_paper", "answer_solution"]))
        self.assertEqual(batch.classify_file_name("2025广州中考年报.pdf"), (2025, ["exam_year_report"]))

    def test_dry_run_inventory_has_full_coverage_and_csv_is_parseable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source"
            destination = root / "destination" / "raw"
            source.mkdir()
            create_complete_batch(source)
            report_path = root / "report.json"
            csv_path = root / "inventory.csv"

            report = batch.run_stage(source, destination, "dry_run", report_path, csv_path)

            self.assertEqual(report["physicalFileCount"], 33)
            self.assertEqual(report["logicalSourceCount"], 33)
            self.assertEqual(report["logicalRoleCounts"]["exam_paper"], 11)
            self.assertFalse(report["hashParityChecked"])
            self.assertIsNone(report["hashParityPass"])
            self.assertFalse(destination.exists())
            self.assertEqual(len(list(source.glob("*.pdf"))), 33)
            with csv_path.open("r", encoding="utf-8-sig", newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 33)
            self.assertTrue(all(row["sha256"] and row["pageCount"] == "1" for row in rows))

    def test_apply_and_rollback_preserve_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source"
            destination = root / "batch" / "raw"
            source.mkdir()
            create_complete_batch(source)
            report_path = root / "report.json"
            csv_path = root / "inventory.csv"

            apply_report = batch.run_stage(source, destination, "apply", report_path, csv_path)
            self.assertEqual(len(list(source.glob("*.pdf"))), 0)
            self.assertEqual(len(list(destination.glob("*.pdf"))), 33)
            self.assertTrue((destination.parent / "source-batch-inventory.json").exists())

            refreshed = batch.run_stage(source, destination, "refresh_inventory", report_path, csv_path)
            self.assertEqual(refreshed["mode"], "refresh_inventory")
            self.assertEqual(refreshed["inventoryState"], "current_destination")
            self.assertEqual(refreshed["physicalFileCount"], 33)

            rollback_dry_run = batch.run_stage(source, destination, "rollback_dry_run", report_path, csv_path)
            self.assertEqual(rollback_dry_run["mode"], "rollback_dry_run")
            self.assertFalse(rollback_dry_run["hashParityChecked"])
            self.assertEqual(len(list(destination.glob("*.pdf"))), 33)

            rollback_report = batch.run_stage(source, destination, "rollback", report_path, csv_path)
            self.assertEqual(apply_report["inventoryDigest"], rollback_report["inventoryDigest"])
            self.assertEqual(len(list(source.glob("*.pdf"))), 33)
            self.assertEqual(len(list(destination.glob("*.pdf"))), 0)

    def test_final_digest_failure_rolls_back_the_entire_apply(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source"
            destination = root / "batch" / "raw"
            source.mkdir()
            create_complete_batch(source)

            with mock.patch.object(batch, "inventory_digest", side_effect=["before", "after"]):
                with self.assertRaisesRegex(batch.BatchStageError, "inventory digest changed"):
                    batch.run_stage(source, destination, "apply", root / "report.json", root / "inventory.csv")

            self.assertEqual(len(list(source.glob("*.pdf"))), 33)
            self.assertEqual(len(list(destination.glob("*.pdf"))), 0)

    def test_destination_conflict_blocks_before_any_move(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            create_complete_batch(source)
            write_pdf(destination / "2015广州中考.pdf", "conflict")

            with self.assertRaisesRegex(batch.BatchStageError, "both contain"):
                batch.run_stage(source, destination, "apply", root / "report.json", root / "inventory.csv")
            self.assertEqual(len(list(source.glob("*.pdf"))), 33)

    def test_missing_year_role_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source"
            source.mkdir()
            create_complete_batch(source)
            (source / "2025广州中考年报.pdf").unlink()

            with self.assertRaisesRegex(batch.BatchStageError, "expected 33 physical PDFs"):
                batch.run_stage(source, root / "destination", "dry_run", root / "report.json", root / "inventory.csv")


if __name__ == "__main__":
    unittest.main()
