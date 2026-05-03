from __future__ import annotations

import argparse
import json
import pathlib
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row


def scalar(conn: psycopg.Connection, sql: str, params: tuple[Any, ...]) -> int:
    row = conn.execute(sql, params).fetchone()
    return int(row["count"])


def grouped(conn: psycopg.Connection, sql: str, params: tuple[Any, ...]) -> dict[str, int]:
    rows = conn.execute(sql, params).fetchall()
    return {str(row["key"]): int(row["count"]) for row in rows}


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--import-key", required=True)
    parser.add_argument("--material-batch-key", required=True)
    parser.add_argument("--report-path", default="docs/evidence/c002l-candidate-review-readiness-report.json")
    args = parser.parse_args()

    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        candidate_assets = scalar(
            conn,
            """
            select count(*) from domain_asset_versions
            where source_evidence->>'importKey' = %s and status = 'candidate'
            """,
            (args.import_key,),
        )
        active_imported_assets = scalar(
            conn,
            """
            select count(*) from domain_asset_versions
            where source_evidence->>'importKey' = %s and status = 'active'
            """,
            (args.import_key,),
        )
        reviewed_imported_assets = scalar(
            conn,
            """
            select count(*) from domain_asset_versions
            where source_evidence->>'importKey' = %s and status = 'reviewed'
            """,
            (args.import_key,),
        )
        assets_by_type = grouped(
            conn,
            """
            select asset_type as key, count(*) from domain_asset_versions
            where source_evidence->>'importKey' = %s
            group by asset_type
            order by asset_type
            """,
            (args.import_key,),
        )
        pending_mappings = scalar(
            conn,
            """
            select count(*) from domain_asset_mappings
            where evidence->>'importKey' = %s and review_status = 'pending_review'
            """,
            (args.import_key,),
        )
        auto_applied_mappings = scalar(
            conn,
            """
            select count(*) from domain_asset_mappings
            where evidence->>'importKey' = %s and auto_applied = true
            """,
            (args.import_key,),
        )
        mappings_by_type = grouped(
            conn,
            """
            select mapping_type as key, count(*) from domain_asset_mappings
            where evidence->>'importKey' = %s
            group by mapping_type
            order by mapping_type
            """,
            (args.import_key,),
        )
        pending_migrations = scalar(
            conn,
            """
            select count(*) from domain_asset_migrations
            where migration_key = %s and status = 'pending_review'
            """,
            (args.import_key,),
        )
        rollback_snapshots = scalar(
            conn,
            """
            select count(*) from domain_asset_migrations
            where migration_key = %s and rollback_snapshot <> '{}'::jsonb
            """,
            (args.import_key,),
        )
        open_review_items = scalar(
            conn,
            """
            select count(*) from review_queue_items
            where review_type = 'c002_candidate_import'
              and status = 'open'
              and payload->>'importKey' = %s
            """,
            (args.import_key,),
        )
        source_documents = scalar(
            conn,
            """
            select count(*) from source_documents
            where material_batch_key = %s
            """,
            (args.material_batch_key,),
        )
        source_documents_with_hash = scalar(
            conn,
            """
            select count(*) from source_documents sd
            join file_assets fa on fa.id = sd.file_asset_id
            where sd.material_batch_key = %s
              and fa.sha256 is not null
              and fa.sha256 <> ''
            """,
            (args.material_batch_key,),
        )
        source_by_type = grouped(
            conn,
            """
            select source_type as key, count(*) from source_documents
            where material_batch_key = %s
            group by source_type
            order by source_type
            """,
            (args.material_batch_key,),
        )

    blockers = []
    if candidate_assets > 0:
        blockers.append(
            {
                "blockerId": "candidate_assets_pending_review",
                "severity": "hard",
                "count": candidate_assets,
                "nextAction": "review candidate assets and mark approved/rejected before active activation",
            }
        )
    if pending_mappings > 0:
        blockers.append(
            {
                "blockerId": "pending_review_mappings",
                "severity": "hard",
                "count": pending_mappings,
                "nextAction": "approve/reject or revise mapping edges before active activation",
            }
        )
    if pending_migrations > 0:
        blockers.append(
            {
                "blockerId": "migration_plan_pending_review",
                "severity": "hard",
                "count": pending_migrations,
                "nextAction": "review impact report and rollback snapshot before active activation",
            }
        )
    if open_review_items > 0:
        blockers.append(
            {
                "blockerId": "review_queue_open",
                "severity": "hard",
                "count": open_review_items,
                "nextAction": "close review queue item with explicit decision evidence",
            }
        )
    if source_documents == 0 or source_documents != source_documents_with_hash:
        blockers.append(
            {
                "blockerId": "source_evidence_incomplete",
                "severity": "hard",
                "count": source_documents - source_documents_with_hash,
                "nextAction": "fix source evidence and sha256 coverage before active activation",
            }
        )
    if rollback_snapshots == 0:
        blockers.append(
            {
                "blockerId": "rollback_snapshot_missing",
                "severity": "hard",
                "count": 1,
                "nextAction": "create rollback snapshot before active activation",
            }
        )
    if active_imported_assets > 0:
        blockers.append(
            {
                "blockerId": "unexpected_active_assets",
                "severity": "hard",
                "count": active_imported_assets,
                "nextAction": "investigate and roll back unintended activation",
            }
        )
    if reviewed_imported_assets > 0:
        blockers.append(
            {
                "blockerId": "reviewed_assets_not_fully_activated",
                "severity": "medium",
                "count": reviewed_imported_assets,
                "nextAction": "confirm reviewed assets are ready for activation guard",
            }
        )
    if auto_applied_mappings > 0:
        blockers.append(
            {
                "blockerId": "unexpected_auto_applied_mappings",
                "severity": "hard",
                "count": auto_applied_mappings,
                "nextAction": "candidate import mappings must remain manual pending_review",
            }
        )

    activation_allowed = len([x for x in blockers if x["severity"] == "hard"]) == 0
    report = {
        "status": "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "task": "C002L",
        "importKey": args.import_key,
        "materialBatchKey": args.material_batch_key,
        "activationAllowed": activation_allowed,
        "formalCompletionDefinition": {
            "meaning": "C002 complete means junior physics ontology v1 is active and governed, not permanently frozen.",
            "requires": [
                "source evidence complete",
                "candidate assets reviewed",
                "mapping decisions reviewed",
                "impact report accepted",
                "rollback snapshot present",
                "active guard passed",
            ],
            "futureChanges": "Create a new candidate version, mapping plan, impact report, review decision, rollback snapshot, then switch active through guard.",
            "oldVersionsRemainFor": ["historical questions", "old papers", "learning analytics explanations", "rollback"],
        },
        "counts": {
            "candidateAssets": candidate_assets,
            "reviewedImportedAssets": reviewed_imported_assets,
            "activeImportedAssets": active_imported_assets,
            "pendingReviewMappings": pending_mappings,
            "autoAppliedMappings": auto_applied_mappings,
            "pendingReviewMigrations": pending_migrations,
            "rollbackSnapshots": rollback_snapshots,
            "openReviewQueueItems": open_review_items,
            "sourceDocuments": source_documents,
            "sourceDocumentsWithSha256": source_documents_with_hash,
        },
        "assetsByType": assets_by_type,
        "mappingsByType": mappings_by_type,
        "sourcesByType": source_by_type,
        "blockers": blockers,
        "requiredBeforeActivation": {
            "candidateAssets": 0,
            "pendingReviewMappings": 0,
            "pendingReviewMigrations": 0,
            "openReviewQueueItems": 0,
            "activeImportedAssetsBeforeGuard": 0,
            "sourceDocumentsEqualSha256Count": True,
            "rollbackSnapshotReady": True,
        },
    }

    if candidate_assets < 1:
        report["status"] = "fail"
        report["error"] = "candidate_assets_missing"
    if source_documents != 33 or source_documents_with_hash != 33:
        report["status"] = "fail"
        report["error"] = "source_document_count_mismatch"
    if active_imported_assets != 0:
        report["status"] = "fail"
        report["error"] = "active_assets_must_not_exist_before_guard"
    if auto_applied_mappings != 0:
        report["status"] = "fail"
        report["error"] = "auto_applied_mappings_forbidden"
    if not blockers:
        report["status"] = "fail"
        report["error"] = "sample_should_still_block_activation_until_review"

    write_report(pathlib.Path(args.report_path), report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
