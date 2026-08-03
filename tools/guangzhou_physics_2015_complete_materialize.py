"""Transactionally materialize the strictly validated 2015 paper structure."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row

from guangzhou_physics_2015_complete_extraction import run_extraction
from guangzhou_physics_v2_materialize import WORKFLOW_KEY, stable_id
from real005b_reviewed_question_materialize import workflow_fingerprint


CONTRACT = "guangzhou-physics-2015-complete-extraction.v1"
STRUCTURE_TYPES = ("context", "stem", "option", "subquestion", "formula", "table", "image")


def verify_backup(repo_root: Path, manifest: Path) -> None:
    if not manifest.is_file():
        raise ValueError(f"backup_manifest_missing:{manifest}")
    completed = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(repo_root / "tools/verify-backup.ps1"),
            "-ManifestPath",
            str(manifest),
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )
    if completed.returncode != 0:
        raise ValueError(f"backup_verification_failed:{completed.stderr or completed.stdout}")
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    payload = json.loads(lines[-1]) if lines else {}
    if payload.get("status") != "ok":
        raise ValueError(f"backup_verification_failed:{payload}")


def question_rows(conn: psycopg.Connection[Any]) -> dict[int, dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            select id, custom_fields, quality_signals
            from question_items
            where custom_fields->>'sourceWorkflowKey'=%s
              and custom_fields->>'year'='2015'
            order by (custom_fields->>'questionNo')::int
            """,
            (WORKFLOW_KEY,),
        )
        result = {int(row["custom_fields"]["questionNo"]): dict(row) for row in cursor.fetchall()}
    if set(result) != set(range(1, 25)):
        raise ValueError(f"2015_candidate_sequence_mismatch:{sorted(result)}")
    return result


def block_identity(block: dict[str, Any], index: int) -> str:
    return str(
        block.get("optionLabel")
        or block.get("subquestionLabel")
        or (block.get("figure") or {}).get("id")
        or index
    )


def materialized_structure_blocks(qid: uuid.UUID, question: dict[str, Any]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    type_map = {"shared_prompt": "context"}
    for index, extracted in enumerate(question["blocks"]):
        block_type = type_map.get(extracted["blockType"], extracted["blockType"])
        content = {
            key: value
            for key, value in extracted.items()
            if key
            not in {
                "blockType",
                "readingOrder",
                "pageNumber",
                "bboxPercent",
                "sourceRegionId",
                "assetReference",
            }
        }
        content.update(
            {
                "reviewStatus": "pending_review",
                "productionEligible": False,
                "extractionContract": CONTRACT,
                "pageNumber": extracted["pageNumber"],
                "bboxPercent": extracted["bboxPercent"],
                "assetReference": extracted["assetReference"],
            }
        )
        if "optionLabel" in content:
            content["label"] = content.pop("optionLabel")
        if "subquestionLabel" in content:
            content["label"] = content.pop("subquestionLabel")
        if block_type == "image":
            content["status"] = "extracted"
        result.append(
            {
                "id": stable_id("2015-complete-block", qid, block_type, block_identity(extracted, index)),
                "type": block_type,
                "order": len(result),
                "sourceRegionId": uuid.UUID(extracted["sourceRegionId"]),
                "content": content,
            }
        )
    return result


def existing_preserved_blocks(conn: psycopg.Connection[Any], qid: uuid.UUID) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(
            """
            select id, block_type, sort_order, content, source_region_id
            from question_blocks
            where question_item_id=%s and block_type in ('answer','scoring_point')
            order by sort_order, id
            """,
            (qid,),
        )
        return [dict(row) for row in cursor.fetchall()]


def upsert_question(
    conn: psycopg.Connection[Any],
    row: dict[str, Any],
    question: dict[str, Any],
    evidence_path: str,
) -> tuple[int, int]:
    qid = uuid.UUID(str(row["id"]))
    structure = materialized_structure_blocks(qid, question)
    preserved = existing_preserved_blocks(conn, qid)
    answers = [block for block in preserved if block["block_type"] == "answer"]
    if len(answers) != 1:
        raise ValueError(f"expected_single_answer_block:{question['questionNumber']}:{len(answers)}")
    answer = answers[0]
    answer_content = dict(answer["content"])
    answer_content.update(
        {
            "value": question["answer"],
            "reviewStatus": "pending_review",
            "productionEligible": False,
            "extractionContract": CONTRACT,
        }
    )
    final_blocks = list(structure)
    final_blocks.append(
        {
            "id": answer["id"],
            "type": "answer",
            "order": len(final_blocks),
            "sourceRegionId": answer["source_region_id"],
            "content": answer_content,
        }
    )
    for scoring in (block for block in preserved if block["block_type"] == "scoring_point"):
        content = dict(scoring["content"])
        content.update({"reviewStatus": "pending_review", "productionEligible": False})
        final_blocks.append(
            {
                "id": scoring["id"],
                "type": "scoring_point",
                "order": len(final_blocks),
                "sourceRegionId": scoring["source_region_id"],
                "content": content,
            }
        )

    generated_ids = [block["id"] for block in final_blocks]
    with conn.cursor() as cursor:
        referenced = cursor.execute(
            """
            select qb.id
            from question_blocks qb
            where qb.question_item_id=%s
              and not (qb.id=any(%s::uuid[]))
              and exists (select 1 from assessment_targets at where at.question_block_id=qb.id)
            order by qb.id
            """,
            (qid, generated_ids),
        ).fetchall()
        if referenced:
            raise ValueError(f"referenced_structure_block_would_be_replaced:{question['questionNumber']}:{referenced}")
        cursor.execute(
            "delete from question_blocks where question_item_id=%s and not (id=any(%s::uuid[]))",
            (qid, generated_ids),
        )
        for block in final_blocks:
            cursor.execute(
                """
                insert into question_blocks (
                    id, question_item_id, block_type, sort_order, content, source_region_id, created_at
                ) values (%s,%s,%s,%s,%s::jsonb,%s,now())
                on conflict (id) do update set
                    question_item_id=excluded.question_item_id,
                    block_type=excluded.block_type,
                    sort_order=excluded.sort_order,
                    content=excluded.content,
                    source_region_id=excluded.source_region_id
                """,
                (
                    block["id"],
                    qid,
                    block["type"],
                    block["order"],
                    json.dumps(block["content"], ensure_ascii=False),
                    block["sourceRegionId"],
                ),
            )

        cursor.execute(
            "delete from question_assets where question_item_id=%s and metadata->>'extractionContract'=%s",
            (qid, CONTRACT),
        )
        image_blocks = [block for block in final_blocks if block["type"] == "image"]
        for index, block in enumerate(image_blocks, start=1):
            cursor.execute(
                """
                insert into question_assets (
                    id, question_item_id, file_asset_id, source_region_id,
                    asset_type, purpose, metadata, created_at
                ) values (%s,%s,null,%s,'image','question_content',%s::jsonb,now())
                """,
                (
                    stable_id("2015-complete-figure-asset", qid, index),
                    qid,
                    block["sourceRegionId"],
                    json.dumps(
                        {
                            "extractionContract": CONTRACT,
                            "figure": block["content"]["figure"],
                            "reviewStatus": "pending_review",
                            "productionEligible": False,
                        },
                        ensure_ascii=False,
                    ),
                ),
            )

        custom_fields = dict(row["custom_fields"])
        custom_fields.update(
            {
                "answer": {"value": question["answer"], "status": "pending_review"},
                "structuredExtraction": {
                    "contract": CONTRACT,
                    "status": "strict_validation_pass",
                    "evidence": evidence_path,
                    "sourceRegionIds": [region["sourceRegionId"] for region in question["sourceRegions"]],
                    "blockCount": len(structure),
                    "teacherValidationRequired": True,
                    "productionEligible": False,
                },
                "teacherValidationRequired": True,
                "productionEligible": False,
            }
        )
        quality_signals = dict(row["quality_signals"])
        quality_signals.update(
            {
                "reviewStatus": "pending_review",
                "productionEligible": False,
                "teacherValidationRequired": True,
                "structuredExtractionContract": CONTRACT,
                "strictStructureValidationPassed": True,
                "structuredBlockCount": len(structure),
            }
        )
        serialized_blocks = [
            {
                "type": block["type"],
                "order": block["order"],
                "sourceRegionId": str(block["sourceRegionId"]),
                "content": block["content"],
            }
            for block in final_blocks
        ]
        cursor.execute(
            """
            update question_items
            set blocks=%s::jsonb, custom_fields=%s::jsonb, quality_signals=%s::jsonb,
                status='pending_review', updated_at=now()
            where id=%s
            """,
            (
                json.dumps(serialized_blocks, ensure_ascii=False),
                json.dumps(custom_fields, ensure_ascii=False),
                json.dumps(quality_signals, ensure_ascii=False),
                qid,
            ),
        )
        review_row = cursor.execute(
            """
            select id, payload
            from review_queue_items
            where review_type='guangzhou_v2_question_candidate_review'
              and payload->>'questionItemId'=%s
            """,
            (str(qid),),
        ).fetchone()
        if not review_row:
            raise ValueError(f"candidate_review_item_missing:{question['questionNumber']}")
        review_payload = dict(review_row[1])
        review_payload.update(
            {
                "textPreview": next(block["content"]["text"] for block in final_blocks if block["type"] == "stem"),
                "answer": question["answer"],
                "productionEligible": False,
                "teacherValidationRequired": True,
                "structuredExtractionContract": CONTRACT,
            }
        )
        cursor.execute(
            "update review_queue_items set payload=%s::jsonb where id=%s",
            (json.dumps(review_payload, ensure_ascii=False), review_row[0]),
        )
    return len(structure), len(image_blocks)


def database_invariants(conn: psycopg.Connection[Any]) -> dict[str, int]:
    query = """
    with q as (
      select id from question_items
      where custom_fields->>'sourceWorkflowKey'=%s and custom_fields->>'year'='2015'
    )
    select
      (select count(*) from q) questions,
      (select count(*) from question_items where id in (select id from q) and status='pending_review') pending,
      (select count(*) from question_items where id in (select id from q) and coalesce((custom_fields->>'productionEligible')::boolean,false)) production_eligible,
      (select count(*) from question_items where id in (select id from q) and custom_fields#>>'{structuredExtraction,contract}'=%s) contracted,
      (select count(*) from question_blocks where question_item_id in (select id from q) and block_type='stem') stems,
      (select count(*) from question_blocks where question_item_id in (select id from q) and block_type='option') options,
      (select count(*) from question_blocks where question_item_id in (select id from q) and block_type='subquestion') subquestions,
      (select count(*) from question_blocks where question_item_id in (select id from q) and block_type='table') tables,
      (select count(*) from question_blocks where question_item_id in (select id from q) and block_type='formula') formulas,
      (select count(*) from question_blocks where question_item_id in (select id from q) and block_type='image') images
    """
    with conn.cursor(row_factory=dict_row) as cursor:
        row = cursor.execute(query, (WORKFLOW_KEY, CONTRACT)).fetchone()
    return {key: int(value) for key, value in dict(row or {}).items()}


def run_materialize(args: argparse.Namespace) -> dict[str, Any]:
    repo_root = Path(__file__).resolve().parents[1]
    if args.apply:
        verify_backup(repo_root, Path(args.backup_manifest).resolve())
    extraction = run_extraction(
        Path(args.source_root).resolve(),
        (repo_root / args.fixture).resolve(),
        (repo_root / args.question_region_report_2015).resolve(),
        (repo_root / args.question_region_report_2016_2025).resolve(),
    )
    if extraction["status"] != "pass":
        raise ValueError("strict_2015_extraction_not_passed")

    connection_args: dict[str, Any] = {
        "host": args.host,
        "port": args.port,
        "dbname": args.database,
        "user": args.user,
    }
    if args.password:
        connection_args["password"] = args.password
    conn = psycopg.connect(**connection_args)
    try:
        before = workflow_fingerprint(conn)
        rows = question_rows(conn)
        structure_count = 0
        image_count = 0
        for question in extraction["questions"]:
            number = int(question["questionNumber"])
            blocks, images = upsert_question(conn, rows[number], question, args.extraction_evidence)
            structure_count += blocks
            image_count += images
        inside = database_invariants(conn)
        expected = {
            "questions": 24,
            "pending": 24,
            "production_eligible": 0,
            "contracted": 24,
            "stems": 24,
            "options": 48,
            "subquestions": 24,
            "tables": 1,
        }
        mismatches = {key: {"expected": value, "actual": inside.get(key)} for key, value in expected.items() if inside.get(key) != value}
        if mismatches or inside.get("formulas", 0) < 1 or inside.get("images", 0) < 1:
            raise ValueError(f"2015_materialize_invariant_failed:{mismatches}:{inside}")
        if args.apply:
            conn.commit()
        else:
            conn.rollback()
        after = workflow_fingerprint(conn)
        if not args.apply and after != before:
            raise ValueError("dry_run_fingerprint_changed")
        return {
            "status": "pass" if args.apply else "dry_run_pass",
            "taskId": "GUANGZHOU_PHYSICS_2015_COMPLETE_MATERIALIZE",
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "mode": "apply" if args.apply else "transaction_rollback_dry_run",
            "contractVersion": CONTRACT,
            "backupManifest": str(Path(args.backup_manifest).resolve()) if args.apply else None,
            "extractionEvidence": args.extraction_evidence,
            "totals": {**inside, "structureBlocks": structure_count, "figureAssets": image_count},
            "database": {
                "fingerprintBefore": before,
                "fingerprintAfter": after,
                "dryRunRolledBack": None if args.apply else before == after,
            },
            "databaseWrites": 24 if args.apply else 0,
            "activeWrite": False,
            "productionEligible": False,
            "reviewStatus": "pending_review",
            "real005": "not_closed",
            "rollback": {
                "primary": f"restore database from {args.backup_manifest}" if args.apply else "transaction rollback completed",
                "restoreCommand": (
                    f"pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore.ps1 -ManifestPath '{args.backup_manifest}' -ApplyDatabase -ApplyFileStore -DryRun:$false"
                    if args.apply
                    else None
                ),
            },
            "boundary": "2015 candidate structures were materialized for teacher review only; no approval or active switch occurred.",
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize strict 2015 Guangzhou question structures")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default=os.environ.get("PGPASSWORD", ""))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument(
        "--source-root",
        default=r"D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw",
    )
    parser.add_argument("--fixture", default="tests/fixtures/guangzhou-physics-2015-complete.json")
    parser.add_argument("--question-region-report-2015", default="docs/evidence/20260726-guangzhou-physics-v2-2015-question-regions.json")
    parser.add_argument("--question-region-report-2016-2025", default="docs/evidence/20260726-guangzhou-physics-v2-question-regions.json")
    parser.add_argument("--extraction-evidence", default="docs/evidence/20260801-guangzhou-physics-2015-complete-extraction.json")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.apply and not args.backup_manifest:
        raise ValueError("apply_requires_verified_backup_manifest")
    report = run_materialize(args)
    output = (Path(__file__).resolve().parents[1] / args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "totals": report["totals"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
