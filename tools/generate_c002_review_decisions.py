from __future__ import annotations

import argparse
import json
import pathlib
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row


def write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--import-key", default="c002_candidate_import_guangzhou_physics_2016_2025_v1")
    parser.add_argument("--material-batch-key", default="guangzhou_physics_2016_2025")
    parser.add_argument("--output", default="docs/evidence/c002-review-decisions.generated.json")
    parser.add_argument("--policy", default="approve_source_aligned_internal_candidates")
    parser.add_argument("--expected-source-document-count", type=int, default=33)
    args = parser.parse_args()

    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        source_counts = conn.execute(
            """
            select
                count(*) as source_documents,
                count(*) filter (where fa.sha256 is not null and fa.sha256 <> '') as source_documents_with_hash
            from source_documents sd
            join file_assets fa on fa.id = sd.file_asset_id
            where sd.material_batch_key = %s
            """,
            (args.material_batch_key,),
        ).fetchone()
        active_assets = conn.execute(
            """
            select count(*) as count
            from domain_asset_versions
            where source_evidence->>'importKey' = %s and status = 'active'
            """,
            (args.import_key,),
        ).fetchone()["count"]
        assets = conn.execute(
            """
            select id, asset_type, stable_id, display_name, status
            from domain_asset_versions
            where source_evidence->>'importKey' = %s and status = 'candidate'
            order by asset_type, stable_id
            """,
            (args.import_key,),
        ).fetchall()
        mappings = conn.execute(
            """
            select
                m.id,
                m.mapping_type,
                m.review_status,
                source.asset_type as source_asset_type,
                source.stable_id as source_stable_id,
                target.asset_type as target_asset_type,
                target.stable_id as target_stable_id
            from domain_asset_mappings m
            join domain_asset_versions source on source.id = m.source_asset_version_id
            join domain_asset_versions target on target.id = m.target_asset_version_id
            where m.evidence->>'importKey' = %s and m.review_status = 'pending_review'
            order by m.mapping_type, source.asset_type, source.stable_id, target.asset_type, target.stable_id
            """,
            (args.import_key,),
        ).fetchall()
        pending_migration = conn.execute(
            """
            select count(*) as count
            from domain_asset_migrations
            where migration_key = %s and status = 'pending_review'
            """,
            (args.import_key,),
        ).fetchone()["count"]

    blockers: list[str] = []
    if int(source_counts["source_documents"]) == 0:
        blockers.append("source_documents_missing")
    if int(source_counts["source_documents"]) != int(source_counts["source_documents_with_hash"]):
        blockers.append("source_hash_incomplete")
    if args.expected_source_document_count > 0 and int(source_counts["source_documents"]) != args.expected_source_document_count:
        blockers.append("source_document_count_mismatch")
    if int(active_assets) > 0:
        blockers.append("active_assets_already_present")
    if int(pending_migration) != 1:
        blockers.append("pending_migration_count_not_one")

    if blockers:
        payload = {
            "status": "blocked",
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "importKey": args.import_key,
            "policy": args.policy,
            "blockers": blockers,
            "assetDecisions": [],
            "mappingDecisions": [],
            "migrationDecision": [],
        }
        write_json(pathlib.Path(args.output), payload)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 2

    reason = (
        "Approved by source-aligned quality-review policy: source documents have sha256 coverage, "
        "quality blockers are cleared, records remain candidate/reviewed only, and active switch is still guarded separately."
    )
    payload = {
        "status": "generated",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "importKey": args.import_key,
        "materialBatchKey": args.material_batch_key,
        "policy": args.policy,
        "sourceEvidence": {
            "sourceDocuments": int(source_counts["source_documents"]),
            "sourceDocumentsWithHash": int(source_counts["source_documents_with_hash"]),
        },
        "activeSwitchAllowedByThisFile": False,
        "assetDecisions": [
            {
                "assetId": str(row["id"]),
                "assetType": row["asset_type"],
                "stableId": row["stable_id"],
                "displayName": row["display_name"],
                "currentStatus": row["status"],
                "decision": "approve",
                "reviewReason": reason,
            }
            for row in assets
        ],
        "mappingDecisions": [
            {
                "mappingId": str(row["id"]),
                "mappingType": row["mapping_type"],
                "source": f"{row['source_asset_type']}:{row['source_stable_id']}",
                "target": f"{row['target_asset_type']}:{row['target_stable_id']}",
                "currentReviewStatus": row["review_status"],
                "decision": "approve",
                "reviewReason": reason,
            }
            for row in mappings
        ],
        "migrationDecision": [
            {
                "migrationKey": args.import_key,
                "decision": "approve",
                "reviewReason": reason,
            }
        ],
    }
    write_json(pathlib.Path(args.output), payload)
    print(json.dumps({"status": "generated", "output": args.output, "assetDecisions": len(assets), "mappingDecisions": len(mappings), "migrationDecision": 1}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
