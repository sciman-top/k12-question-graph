import csv
import json
import pathlib
import sys
import tempfile
import unittest

from pypdf import PdfWriter


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOLS_ROOT = REPO_ROOT / "tools"
if str(TOOLS_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOLS_ROOT))

import curriculum_standard_source_batch as batch  # noqa: E402


def write_pdf(path: pathlib.Path, page_count: int = 1) -> None:
    writer = PdfWriter()
    for _ in range(page_count):
        writer.add_blank_page(width=596, height=842)
    with path.open("wb") as stream:
        writer.write(stream)


def facts_for(path: pathlib.Path) -> batch.MaterialFacts:
    inspected = batch.inspect_pdf(path)
    return batch.MaterialFacts(
        material_id="curriculum-physics-junior-2022-2025-revision",
        file_name=path.name,
        size_bytes=inspected["sizeBytes"],
        modified_at_utc=inspected["modifiedAtUtc"],
        sha256=inspected["sha256"],
        page_count=inspected["pageCount"],
        text_character_count=inspected["textCharacterCount"],
        non_empty_page_count=inspected["nonEmptyPageCount"],
        require_text_layer=False,
    )


class CurriculumStandardSourceBatchTests(unittest.TestCase):
    def test_production_identity_is_fixed_and_not_inferred_from_filename(self) -> None:
        self.assertEqual(
            batch.EXPECTED_MATERIAL.material_id,
            "curriculum-physics-junior-2022-2025-revision",
        )
        self.assertEqual(batch.EXPECTED_MATERIAL.page_count, 67)
        self.assertEqual(batch.EXPECTED_MATERIAL.text_character_count, 37615)
        self.assertTrue(batch.EXPECTED_MATERIAL.require_text_layer)

    def test_dry_run_records_inventory_without_moving_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source.pdf"
            destination_root = root / "version" / "raw"
            report_path = root / "report.json"
            csv_path = root / "inventory.csv"
            manifest_path = root / "manifest.local.json"
            write_pdf(source)
            expected = facts_for(source)

            report = batch.run_stage(
                source,
                destination_root,
                "dry_run",
                report_path,
                csv_path,
                manifest_path,
                expected=expected,
            )

            self.assertEqual(report["status"], "pass")
            self.assertEqual(report["physicalFileCount"], 1)
            self.assertEqual(report["materialId"], expected.material_id)
            self.assertFalse(report["hashParityChecked"])
            self.assertTrue(source.exists())
            self.assertFalse(destination_root.exists())
            self.assertFalse(manifest_path.exists())
            with csv_path.open("r", encoding="utf-8-sig", newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["materialId"], expected.material_id)
            self.assertEqual(json.loads(report_path.read_text(encoding="utf-8"))["mode"], "dry_run")

    def test_apply_validate_and_rollback_preserve_hash_and_manifest_state(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source.pdf"
            destination_root = root / "version" / "raw"
            report_path = root / "report.json"
            csv_path = root / "inventory.csv"
            manifest_path = root / "manifest.local.json"
            write_pdf(source)
            expected = facts_for(source)

            apply_report = batch.run_stage(
                source,
                destination_root,
                "apply",
                report_path,
                csv_path,
                manifest_path,
                expected=expected,
            )

            destination = destination_root / source.name
            self.assertFalse(source.exists())
            self.assertTrue(destination.exists())
            self.assertTrue(apply_report["hashParityPass"])
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            material = next(item for item in manifest["materials"] if item["materialId"] == expected.material_id)
            self.assertTrue(material["mayUseForKnowledgeExtraction"])
            self.assertFalse(material["mayUseForExamPointExtraction"])
            self.assertFalse(material["mayUseForTrendAnalysis"])
            self.assertEqual(material["sha256"], expected.sha256)

            validation = batch.run_stage(
                source,
                destination_root,
                "rollback_dry_run",
                report_path,
                csv_path,
                manifest_path,
                expected=expected,
            )
            self.assertTrue(validation["rollbackReady"])
            self.assertTrue(destination.exists())

            rollback_report = batch.run_stage(
                source,
                destination_root,
                "rollback",
                report_path,
                csv_path,
                manifest_path,
                expected=expected,
            )
            self.assertTrue(rollback_report["hashParityPass"])
            self.assertTrue(source.exists())
            self.assertFalse(destination.exists())
            self.assertFalse(manifest_path.exists())
            self.assertEqual(apply_report["inventoryDigest"], rollback_report["inventoryDigest"])

    def test_apply_and_rollback_restore_an_existing_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source.pdf"
            destination_root = root / "version" / "raw"
            report_path = root / "report.json"
            csv_path = root / "inventory.csv"
            manifest_path = root / "manifest.local.json"
            original_manifest = {
                "manifestVersion": "knowledge-source-materials.v1",
                "purpose": "existing local materials",
                "subject": "physics",
                "stage": "junior_middle_school",
                "region": "local",
                "reviewOwner": "teacher",
                "materials": [{"materialId": "existing-material"}],
            }
            manifest_path.write_text(json.dumps(original_manifest), encoding="utf-8")
            write_pdf(source)
            expected = facts_for(source)

            batch.run_stage(
                source,
                destination_root,
                "apply",
                report_path,
                csv_path,
                manifest_path,
                expected=expected,
            )
            batch.run_stage(
                source,
                destination_root,
                "rollback",
                report_path,
                csv_path,
                manifest_path,
                expected=expected,
            )

            self.assertEqual(json.loads(manifest_path.read_text(encoding="utf-8")), original_manifest)

    def test_destination_conflict_blocks_before_move(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source.pdf"
            destination_root = root / "version" / "raw"
            destination_root.mkdir(parents=True)
            write_pdf(source)
            write_pdf(destination_root / source.name)
            expected = facts_for(source)

            with self.assertRaisesRegex(batch.SourceBatchError, "both source and destination"):
                batch.run_stage(
                    source,
                    destination_root,
                    "apply",
                    root / "report.json",
                    root / "inventory.csv",
                    root / "manifest.local.json",
                    expected=expected,
                )
            self.assertTrue(source.exists())

    def test_hash_drift_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source.pdf"
            write_pdf(source)
            expected = facts_for(source)
            source.write_bytes(source.read_bytes() + b"drift")

            with self.assertRaisesRegex(batch.SourceBatchError, "fact drift.*sha256"):
                batch.run_stage(
                    source,
                    root / "version" / "raw",
                    "dry_run",
                    root / "report.json",
                    root / "inventory.csv",
                    root / "manifest.local.json",
                    expected=expected,
                )

    def test_non_pdf_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            source = root / "source.pdf"
            source.write_text("not a pdf", encoding="utf-8")
            expected = batch.MaterialFacts(
                material_id="curriculum-physics-junior-2022-2025-revision",
                file_name=source.name,
                size_bytes=source.stat().st_size,
                modified_at_utc=batch.utc_iso(source.stat().st_mtime),
                sha256=batch.sha256_file(source),
                page_count=1,
                text_character_count=1,
                non_empty_page_count=1,
                require_text_layer=True,
            )

            with self.assertRaisesRegex(batch.SourceBatchError, "invalid PDF magic"):
                batch.run_stage(
                    source,
                    root / "version" / "raw",
                    "dry_run",
                    root / "report.json",
                    root / "inventory.csv",
                    root / "manifest.local.json",
                    expected=expected,
                )


if __name__ == "__main__":
    unittest.main()
