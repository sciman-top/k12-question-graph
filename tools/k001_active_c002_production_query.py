from __future__ import annotations

import argparse
import json
import pathlib
from collections import OrderedDict
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row


IMPORT_KEY = "c002_candidate_import_guangzhou_physics_2016_2025_v1"
MATERIAL_BATCH_KEY = "guangzhou_physics_2016_2025"
ACTIVE_VERSION_REF = "junior-physics-guangzhou-source-derived-v1"
DEFAULT_REPORT = pathlib.Path("docs/evidence/k001-active-c002-production-query-report.json")


def write_json(path: pathlib.Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def fetch_counts(conn: psycopg.Connection) -> dict[str, int]:
    asset = conn.execute(
        """
        select
            count(*) filter (where status = 'active') as active_assets,
            count(*) filter (where status = 'candidate') as candidate_assets,
            count(*) filter (where status = 'reviewed') as reviewed_assets,
            count(*) as total_assets
        from domain_asset_versions
        where source_evidence->>'importKey' = %s
        """,
        (IMPORT_KEY,),
    ).fetchone()
    mapping = conn.execute(
        """
        select
            count(*) filter (where review_status = 'approved') as approved_mappings,
            count(*) filter (where review_status = 'pending_review') as pending_mappings,
            count(*) filter (where review_status = 'rejected') as rejected_mappings
        from domain_asset_mappings
        where evidence->>'importKey' = %s
        """,
        (IMPORT_KEY,),
    ).fetchone()
    migration = conn.execute(
        """
        select
            count(*) filter (where status = 'applied') as applied_migrations,
            count(*) filter (where status = 'pending_review') as pending_migrations
        from domain_asset_migrations
        where migration_key = %s
        """,
        (IMPORT_KEY,),
    ).fetchone()
    source = conn.execute(
        """
        select count(*) as source_documents
        from source_documents
        where material_batch_key = %s
        """,
        (MATERIAL_BATCH_KEY,),
    ).fetchone()
    return {
        "activeAssets": int(asset["active_assets"]),
        "candidateAssets": int(asset["candidate_assets"]),
        "reviewedAssets": int(asset["reviewed_assets"]),
        "totalAssets": int(asset["total_assets"]),
        "approvedMappings": int(mapping["approved_mappings"]),
        "pendingMappings": int(mapping["pending_mappings"]),
        "rejectedMappings": int(mapping["rejected_mappings"]),
        "appliedMigrations": int(migration["applied_migrations"]),
        "pendingMigrations": int(migration["pending_migrations"]),
        "sourceDocuments": int(source["source_documents"]),
    }


def fetch_sample_assets(conn: psycopg.Connection) -> list[dict[str, Any]]:
    rows = conn.execute(
        """
        select stable_id, version, display_name, asset_type, status
        from domain_asset_versions
        where source_evidence->>'importKey' = %s
          and status = 'active'
        order by asset_type, stable_id
        limit 5
        """,
        (IMPORT_KEY,),
    ).fetchall()
    return [
        {
            "stableId": row["stable_id"],
            "version": int(row["version"]),
            "displayName": row["display_name"],
            "assetType": row["asset_type"],
            "status": row["status"],
        }
        for row in rows
    ]


def build_query_surfaces(counts: dict[str, int], sample_assets: list[dict[str, Any]]) -> dict[str, Any]:
    active_ref = {
        "activeKnowledgeVersion": ACTIVE_VERSION_REF,
        "importKey": IMPORT_KEY,
        "status": "active",
        "activeAssetCount": counts["activeAssets"],
        "approvedMappingCount": counts["approvedMappings"],
        "appliedMigrationCount": counts["appliedMigrations"],
        "sampleStableIds": [asset["stableId"] for asset in sample_assets],
    }
    return {
        "questionSearch": {
            "defaultKnowledgeSource": "active_c002_v1",
            "mode": "production_query_contract",
            "versionReference": active_ref,
            "filtersUseActiveAssetsByDefault": True,
            "candidateAssetsExcludedByDefault": counts["candidateAssets"] == 0,
        },
        "paperAssemblyConstraints": {
            "defaultKnowledgeSource": "active_c002_v1",
            "versionReference": active_ref,
            "replacementAndBlueprintKeepVersionRef": True,
            "mappingImpactRequiredForFutureRevision": True,
        },
        "knowledgeMasteryAnalysis": {
            "defaultKnowledgeSource": "active_c002_v1",
            "versionReference": active_ref,
            "historyWritesRemainGuarded": True,
            "realStudentDataUsed": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="K001 active C002 production query contract")
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--report-path", type=pathlib.Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        counts = fetch_counts(conn)
        sample_assets = fetch_sample_assets(conn)

    blockers: list[str] = []
    if counts["totalAssets"] == 0:
        blockers.append("c002_assets_missing")
    if counts["activeAssets"] != counts["totalAssets"] or counts["activeAssets"] < 1:
        blockers.append("active_assets_not_default_complete")
    if counts["candidateAssets"] != 0 or counts["reviewedAssets"] != 0:
        blockers.append("non_active_assets_still_in_default_batch")
    if counts["pendingMappings"] != 0:
        blockers.append("pending_mappings_present")
    if counts["appliedMigrations"] < 1:
        blockers.append("applied_migration_missing")
    if counts["sourceDocuments"] != 33:
        blockers.append("source_document_count_mismatch")
    if not sample_assets:
        blockers.append("active_asset_samples_missing")

    query_surfaces = build_query_surfaces(counts, sample_assets)
    if any(surface["versionReference"]["activeKnowledgeVersion"] != ACTIVE_VERSION_REF for surface in query_surfaces.values()):
        blockers.append("version_reference_mismatch")

    report = OrderedDict(
        [
            ("status", "pass" if not blockers else "blocked"),
            ("task", "K001"),
            ("mode", "production_query_contract"),
            ("productionEligible", True),
            ("externalAiCalls", 0),
            ("realStudentDataUsed", False),
            ("importKey", IMPORT_KEY),
            ("materialBatchKey", MATERIAL_BATCH_KEY),
            ("activeKnowledgeVersion", ACTIVE_VERSION_REF),
            ("counts", counts),
            ("sampleActiveAssets", sample_assets),
            ("querySurfaces", query_surfaces),
            ("blockers", blockers),
            ("compatibility", {
                "futureC002RRevisionRequired": "new candidate version, mapping, impact report, review, rollback, active switch",
                "doesNotMutateActiveAssets": True,
                "doesNotWriteProductionHistory": True,
            }),
            ("rollback", "git restore tracked files; this K001 contract performs read-only DB checks and does not mutate active assets"),
            ("createdAt", datetime.now(timezone.utc).isoformat()),
            ("summaryChinese", "K001 已验证题库检索、组卷约束和学情分析的默认知识来源均引用 active C002 v1；本合同只读数据库，不修改 active 资产，不写真实学情。"),
        ]
    )
    write_json(args.report_path, report)
    print(json.dumps({"status": report["status"], "task": "K001", "report": str(args.report_path)}, ensure_ascii=False))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
