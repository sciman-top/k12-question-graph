from __future__ import annotations

import argparse
import json
import pathlib
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def scalar(conn: psycopg.Connection, sql: str, params: tuple[Any, ...]) -> int:
    row = conn.execute(sql, params).fetchone()
    return int(row["count"])


def counts(conn: psycopg.Connection, import_key: str, material_batch_key: str) -> dict[str, int]:
    asset_row = conn.execute(
        """
        select
            count(*) filter (where status = 'candidate') as candidate_assets,
            count(*) filter (where status = 'reviewed') as reviewed_assets,
            count(*) filter (where status = 'active') as active_assets,
            count(*) as total_assets
        from domain_asset_versions
        where source_evidence->>'importKey' = %s
        """,
        (import_key,),
    ).fetchone()
    mapping_row = conn.execute(
        """
        select
            count(*) filter (where review_status = 'pending_review') as pending_mappings,
            count(*) filter (where review_status = 'approved') as approved_mappings,
            count(*) filter (where review_status = 'rejected') as rejected_mappings,
            count(*) filter (where auto_applied = true) as auto_applied_mappings
        from domain_asset_mappings
        where evidence->>'importKey' = %s
        """,
        (import_key,),
    ).fetchone()
    migration_row = conn.execute(
        """
        select
            count(*) filter (where status = 'pending_review') as pending_migrations,
            count(*) filter (where status = 'dry_run') as dry_run_migrations,
            count(*) filter (where status = 'applied') as applied_migrations,
            count(*) filter (where rollback_snapshot <> '{}'::jsonb) as rollback_snapshots
        from domain_asset_migrations
        where migration_key = %s
        """,
        (import_key,),
    ).fetchone()
    review_items = scalar(
        conn,
        """
        select count(*) from review_queue_items
        where review_type = 'c002_candidate_import'
          and status = 'open'
          and payload->>'importKey' = %s
        """,
        (import_key,),
    )
    source_documents = scalar(
        conn,
        "select count(*) from source_documents where material_batch_key = %s",
        (material_batch_key,),
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
        (material_batch_key,),
    )
    return {
        "candidateAssets": int(asset_row["candidate_assets"]),
        "reviewedAssets": int(asset_row["reviewed_assets"]),
        "activeAssets": int(asset_row["active_assets"]),
        "totalAssets": int(asset_row["total_assets"]),
        "pendingMappings": int(mapping_row["pending_mappings"]),
        "approvedMappings": int(mapping_row["approved_mappings"]),
        "rejectedMappings": int(mapping_row["rejected_mappings"]),
        "autoAppliedMappings": int(mapping_row["auto_applied_mappings"]),
        "pendingMigrations": int(migration_row["pending_migrations"]),
        "dryRunMigrations": int(migration_row["dry_run_migrations"]),
        "appliedMigrations": int(migration_row["applied_migrations"]),
        "rollbackSnapshots": int(migration_row["rollback_snapshots"]),
        "openReviewItems": review_items,
        "sourceDocuments": source_documents,
        "sourceDocumentsWithSha256": source_documents_with_hash,
    }


def build_blockers(current: dict[str, int], backup_manifest: str, apply: bool) -> list[str]:
    blockers: list[str] = []
    if current["totalAssets"] == 0:
        blockers.append("imported_assets_missing")
    if current["candidateAssets"] != 0:
        blockers.append("candidate_assets_still_pending")
    if current["reviewedAssets"] == 0 and current["activeAssets"] == 0:
        blockers.append("reviewed_assets_missing")
    if current["pendingMappings"] != 0:
        blockers.append("pending_review_mappings")
    if current["autoAppliedMappings"] != 0:
        blockers.append("auto_applied_mappings_forbidden")
    if current["pendingMigrations"] != 0:
        blockers.append("pending_review_migrations")
    if current["dryRunMigrations"] != 1 and current["activeAssets"] == 0:
        blockers.append("approved_dry_run_migration_missing")
    if current["openReviewItems"] != 0:
        blockers.append("review_queue_open")
    if current["sourceDocuments"] != 33 or current["sourceDocumentsWithSha256"] != 33:
        blockers.append("source_evidence_incomplete")
    if current["rollbackSnapshots"] < 1:
        blockers.append("rollback_snapshot_missing")
    if apply and not backup_manifest:
        blockers.append("backup_manifest_required_for_apply")
    if backup_manifest and not pathlib.Path(backup_manifest).exists():
        blockers.append("backup_manifest_missing")
    if current["activeAssets"] > 0 and current["activeAssets"] != current["totalAssets"]:
        blockers.append("partial_active_transition")
    return blockers


def apply_active_switch(conn: psycopg.Connection, import_key: str, backup_manifest: str) -> None:
    activation = {
        "decision": "activate",
        "activatedAt": datetime.now(timezone.utc).isoformat(),
        "activationGuard": "C002N",
        "backupManifest": backup_manifest,
        "rollbackMode": "restore database from backup manifest or set imported active assets back to reviewed before downstream production use",
    }
    with conn.transaction():
        conn.execute(
            """
            update domain_asset_versions
            set status = 'active',
                metadata = jsonb_set(metadata, '{activation}', %s::jsonb, true),
                updated_at = now()
            where source_evidence->>'importKey' = %s
              and status = 'reviewed'
            """,
            (stable_json(activation), import_key),
        )
        conn.execute(
            """
            update domain_asset_migrations
            set status = 'applied',
                applied_at = now(),
                impact_report = jsonb_set(impact_report, '{activeActivation}', %s::jsonb, true),
                rollback_snapshot = jsonb_set(rollback_snapshot, '{activeActivationBackupManifest}', to_jsonb(%s::text), true)
            where migration_key = %s
              and status = 'dry_run'
            """,
            (stable_json(activation), backup_manifest, import_key),
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--import-key", required=True)
    parser.add_argument("--material-batch-key", required=True)
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument("--report-path", default="docs/evidence/c002t-active-switch-report.json")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        before = counts(conn, args.import_key, args.material_batch_key)
        blockers = build_blockers(before, args.backup_manifest, args.apply)
        already_active = before["activeAssets"] == before["totalAssets"] and before["totalAssets"] > 0
        applied = False

        if args.apply and not blockers and not already_active:
            apply_active_switch(conn, args.import_key, args.backup_manifest)
            applied = True
            after = counts(conn, args.import_key, args.material_batch_key)
        else:
            after = before

    report = {
        "status": "pass" if not blockers else "blocked",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "task": "C002T",
        "mode": "apply" if args.apply else "dry_run",
        "importKey": args.import_key,
        "materialBatchKey": args.material_batch_key,
        "backupManifest": args.backup_manifest,
        "activationGuardPassed": not blockers,
        "alreadyActive": already_active,
        "applied": applied,
        "before": before,
        "after": after,
        "blockers": blockers,
        "rollback": {
            "primary": "restore database from backup manifest before downstream production use",
            "manualFallback": "set imported active domain_asset_versions back to reviewed and domain_asset_migrations status back to dry_run using the activation report importKey",
        },
    }
    write_report(pathlib.Path(args.report_path), report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "pass" and (not args.apply or applied or already_active) else 1


if __name__ == "__main__":
    raise SystemExit(main())
