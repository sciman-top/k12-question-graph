from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import uuid
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg import sql
from psycopg.rows import dict_row


CURRICULUM_IMPORT_KEY = "cek009_curriculum_requirements_2022_2025_v1"
PROFILE_IMPORT_KEY = "cek023_regional_exam_profile_candidate_v1"
TARGET_IMPORT_KEY = "cek016_guangzhou_assessment_targets_v1"
EXPECTED_COUNTS = {
    "curriculumAssets": 273,
    "profileAssets": 24,
    "mappings": 94,
    "targets": 444,
    "alignments": 133,
    "migrations": 2,
    "baselineActiveAssets": 452,
}
HISTORICAL_TABLES = (
    "question_items",
    "assessments",
    "score_records",
    "item_scores",
    "paper_baskets",
    "paper_blueprint_reviews",
)


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)


def write_report(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def validate_isolated_database_name(database_name: str) -> None:
    if not re.fullmatch(r"kqg_cek027_\d{8}_\d{6}_\d+", database_name):
        raise ValueError("CEK-27 refuses a database name outside the kqg_cek027_<timestamp>_<pid> pattern")


def validate_isolated_file_store(file_store_root: pathlib.Path) -> None:
    resolved = file_store_root.resolve()
    normalized = str(resolved).replace("/", "\\").lower()
    if "\\kqg_data\\isolated\\cek027-" not in normalized or resolved.name.lower() != "file_store":
        raise ValueError("CEK-27 refuses a FileStore outside D:\\KQG_Data\\isolated\\cek027-*\\file_store")
    marker = resolved.parent / ".cek027-isolated"
    if not marker.is_file():
        raise ValueError(f"CEK-27 isolation marker is missing: {marker}")


def validate_plan(plan: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    if plan.get("schemaVersion") != "cek024-curriculum-exam-c002r-plan.v1" or plan.get("taskId") != "CEK-24":
        blockers.append("cek024_schema_version_mismatch")
    if (
        plan.get("status") != "pass"
        or plan.get("readOnly") is not True
        or plan.get("databaseWrite") is not False
        or plan.get("activeWrite") is not False
        or plan.get("planningSnapshotUnchanged") is not True
    ):
        blockers.append("cek024_candidate_boundary_missing")
    if (
        plan.get("candidateCounts") != 297
        or plan.get("mappingCount") != 94
        or plan.get("profileCount") != 24
        or plan.get("productionEligible") is not False
    ):
        blockers.append("cek024_candidate_count_or_production_boundary_mismatch")
    rollback = plan.get("rollbackRequirements", [])
    if len(rollback) != 6 or not all(item.get("snapshotRequired") is True for item in rollback):
        blockers.append("cek024_rollback_requirements_incomplete")
    if plan.get("historicalReferencePolicy", {}).get("silentRewriteAllowed") is not False:
        blockers.append("cek024_historical_rewrite_guard_missing")
    return blockers


def file_store_fingerprint(root: pathlib.Path) -> dict[str, Any]:
    digest = hashlib.sha256()
    files = sorted(path for path in root.rglob("*") if path.is_file())
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\0")
    return {"fileCount": len(files), "sha256": digest.hexdigest()}


def table_fingerprint(
    conn: psycopg.Connection,
    table_name: str,
    where_clause: str = "true",
    params: tuple[Any, ...] = (),
) -> str:
    query = sql.SQL("select id::text as row_id, to_jsonb(t)::text as payload from {} t where {} order by id").format(
        sql.Identifier(table_name),
        sql.SQL(where_clause),
    )
    digest = hashlib.sha256()
    for row in conn.execute(query, params):
        digest.update(row["row_id"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(row["payload"].encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def database_fingerprints(conn: psycopg.Connection) -> dict[str, str]:
    fingerprints = {
        "revisionAssets": table_fingerprint(
            conn,
            "domain_asset_versions",
            "source_evidence->>'importKey' in (%s, %s)",
            (CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        ),
        "allActiveAssets": table_fingerprint(conn, "domain_asset_versions", "status = 'active'"),
        "revisionMappings": table_fingerprint(
            conn,
            "domain_asset_mappings",
            "evidence->>'importKey' = %s",
            (CURRICULUM_IMPORT_KEY,),
        ),
        "assessmentTargets": table_fingerprint(
            conn,
            "assessment_targets",
            "metadata->>'importKey' = %s",
            (TARGET_IMPORT_KEY,),
        ),
        "curriculumAlignments": table_fingerprint(
            conn,
            "curriculum_alignments",
            "evidence->>'importKey' = %s",
            (TARGET_IMPORT_KEY,),
        ),
        "revisionMigrations": table_fingerprint(
            conn,
            "domain_asset_migrations",
            "migration_key in (%s, %s)",
            (CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        ),
        "reviewQueue": table_fingerprint(conn, "review_queue_items"),
    }
    historical_digest = hashlib.sha256()
    for table_name in HISTORICAL_TABLES:
        value = table_fingerprint(conn, table_name)
        historical_digest.update(table_name.encode("ascii"))
        historical_digest.update(value.encode("ascii"))
    fingerprints["historicalConsumers"] = historical_digest.hexdigest()
    combined = hashlib.sha256(stable_json(fingerprints).encode("utf-8")).hexdigest()
    fingerprints["combined"] = combined
    return fingerprints


def state_counts(conn: psycopg.Connection) -> dict[str, int]:
    row = conn.execute(
        """
        select
          (select count(*) from domain_asset_versions where source_evidence->>'importKey' = %s) as curriculum_assets,
          (select count(*) from domain_asset_versions where source_evidence->>'importKey' = %s) as profile_assets,
          (select count(*) from domain_asset_versions where source_evidence->>'importKey' in (%s, %s) and status = 'candidate') as candidate_assets,
          (select count(*) from domain_asset_versions where source_evidence->>'importKey' in (%s, %s) and status = 'reviewed') as reviewed_assets,
          (select count(*) from domain_asset_versions where source_evidence->>'importKey' in (%s, %s) and status = 'active') as revision_active_assets,
          (select count(*) from domain_asset_versions where status = 'active') as all_active_assets,
          (select count(*) from domain_asset_mappings where evidence->>'importKey' = %s) as mappings,
          (select count(*) from domain_asset_mappings where evidence->>'importKey' = %s and review_status = 'pending_review') as pending_mappings,
          (select count(*) from domain_asset_mappings where evidence->>'importKey' = %s and review_status = 'approved') as approved_mappings,
          (select count(*) from assessment_targets where metadata->>'importKey' = %s) as targets,
          (select count(*) from assessment_targets where metadata->>'importKey' = %s and review_status = 'pending_review') as pending_targets,
          (select count(*) from assessment_targets where metadata->>'importKey' = %s and status = 'reviewed' and review_status = 'approved') as reviewed_targets,
          (select count(*) from assessment_targets where metadata->>'importKey' = %s and status = 'active' and review_status = 'approved' and production_eligible = true) as active_targets,
          (select count(*) from curriculum_alignments where evidence->>'importKey' = %s) as alignments,
          (select count(*) from curriculum_alignments where evidence->>'importKey' = %s and review_status = 'pending_review') as pending_alignments,
          (select count(*) from curriculum_alignments where evidence->>'importKey' = %s and status = 'reviewed' and review_status = 'approved') as reviewed_alignments,
          (select count(*) from curriculum_alignments where evidence->>'importKey' = %s and status = 'active' and review_status = 'approved' and production_eligible = true) as active_alignments,
          (select count(*) from domain_asset_migrations where migration_key in (%s, %s)) as migrations,
          (select count(*) from domain_asset_migrations where migration_key in (%s, %s) and status = 'pending_review') as pending_migrations,
          (select count(*) from domain_asset_migrations where migration_key in (%s, %s) and status = 'dry_run') as dry_run_migrations,
          (select count(*) from domain_asset_migrations where migration_key in (%s, %s) and status = 'applied') as applied_migrations,
          (select count(*) from review_queue_items where status = 'open' and review_type in ('assessment_target','regional_exam_profile')) as open_revision_reviews
        """,
        (
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            TARGET_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
            CURRICULUM_IMPORT_KEY,
            PROFILE_IMPORT_KEY,
        ),
    ).fetchone()
    return {key: int(value) for key, value in row.items()}


def precondition_blockers(counts: dict[str, int]) -> list[str]:
    expected = EXPECTED_COUNTS
    checks = {
        "curriculum_asset_count_mismatch": counts["curriculum_assets"] == expected["curriculumAssets"],
        "profile_asset_count_mismatch": counts["profile_assets"] == expected["profileAssets"],
        "mapping_count_mismatch": counts["mappings"] == expected["mappings"],
        "target_count_mismatch": counts["targets"] == expected["targets"],
        "alignment_count_mismatch": counts["alignments"] == expected["alignments"],
        "migration_count_mismatch": counts["migrations"] == expected["migrations"],
        "revision_assets_not_candidate": counts["candidate_assets"] == 297,
        "mappings_not_pending": counts["pending_mappings"] == expected["mappings"],
        "targets_not_pending": counts["pending_targets"] == expected["targets"],
        "alignments_not_pending": counts["pending_alignments"] == expected["alignments"],
        "migrations_not_pending": counts["pending_migrations"] == expected["migrations"],
        "active_baseline_count_mismatch": counts["all_active_assets"] == expected["baselineActiveAssets"],
    }
    return [name for name, passed in checks.items() if not passed]


def create_snapshots(conn: psycopg.Connection) -> dict[str, str]:
    statements = {
        "cek027_snapshot_assets": (
            "domain_asset_versions",
            "source_evidence->>'importKey' in (%s, %s)",
            (CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        ),
        "cek027_snapshot_mappings": (
            "domain_asset_mappings",
            "evidence->>'importKey' = %s",
            (CURRICULUM_IMPORT_KEY,),
        ),
        "cek027_snapshot_targets": (
            "assessment_targets",
            "metadata->>'importKey' = %s",
            (TARGET_IMPORT_KEY,),
        ),
        "cek027_snapshot_alignments": (
            "curriculum_alignments",
            "evidence->>'importKey' = %s",
            (TARGET_IMPORT_KEY,),
        ),
        "cek027_snapshot_migrations": (
            "domain_asset_migrations",
            "migration_key in (%s, %s)",
            (CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        ),
        "cek027_snapshot_reviews": (
            "review_queue_items",
            "status = 'open' and review_type in ('assessment_target','regional_exam_profile')",
            (),
        ),
    }
    hashes: dict[str, str] = {}
    with conn.transaction():
        for snapshot_name, (source_name, where_clause, params) in statements.items():
            query = sql.SQL("create temp table {} as select * from {} where {}").format(
                sql.Identifier(snapshot_name),
                sql.Identifier(source_name),
                sql.SQL(where_clause),
            )
            conn.execute(query, params)
            hashes[snapshot_name] = table_fingerprint(conn, snapshot_name)
    return hashes


def apply_review_stage(conn: psycopg.Connection, reviewer: str, reason: str) -> str:
    audit = {
        "mode": "isolated_drill_simulation",
        "reviewer": reviewer,
        "reason": reason,
        "teacherAcceptance": False,
        "authenticatedIdentityProven": False,
    }
    payload = stable_json(audit)
    audit_id = str(uuid.uuid4())
    with conn.transaction():
        conn.execute(
            """update domain_asset_versions set status='reviewed', metadata=jsonb_set(metadata,'{cek027Review}',%s::jsonb,true), updated_at=now()
               where source_evidence->>'importKey' in (%s,%s) and status='candidate'""",
            (payload, CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        )
        conn.execute(
            """update domain_asset_mappings set review_status='approved', reviewed_at=now(), evidence=jsonb_set(evidence,'{cek027Review}',%s::jsonb,true)
               where evidence->>'importKey'=%s and review_status='pending_review'""",
            (payload, CURRICULUM_IMPORT_KEY),
        )
        conn.execute(
            """update assessment_targets set status='reviewed', review_status='approved', metadata=jsonb_set(metadata,'{cek027Review}',%s::jsonb,true), updated_at=now()
               where metadata->>'importKey'=%s and status='candidate' and review_status='pending_review'""",
            (payload, TARGET_IMPORT_KEY),
        )
        conn.execute(
            """update curriculum_alignments set status='reviewed', review_status='approved', evidence=jsonb_set(evidence,'{cek027Review}',%s::jsonb,true)
               where evidence->>'importKey'=%s and status='candidate' and review_status='pending_review'""",
            (payload, TARGET_IMPORT_KEY),
        )
        conn.execute(
            """update domain_asset_migrations set status='dry_run', impact_report=jsonb_set(impact_report,'{cek027Review}',%s::jsonb,true)
               where migration_key in (%s,%s) and status='pending_review'""",
            (payload, CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        )
        conn.execute(
            """update review_queue_items set status='resolved', resolved_at=now()
               where status='open' and review_type in ('assessment_target','regional_exam_profile')"""
        )
        conn.execute(
            """insert into review_queue_items(id,review_type,status,payload,created_at,resolved_at)
               values(%s,'curriculum_exam_c002r_drill','resolved',%s::jsonb,now(),now())""",
            (audit_id, payload),
        )
    return audit_id


def apply_active_stage(conn: psycopg.Connection, backup_manifest: str, snapshot_hashes: dict[str, str]) -> None:
    activation = {
        "mode": "isolated_drill_only",
        "activatedAt": datetime.now(timezone.utc).isoformat(),
        "backupManifest": backup_manifest,
        "snapshotHashes": snapshot_hashes,
        "productionSwitchAllowed": False,
    }
    payload = stable_json(activation)
    with conn.transaction():
        conn.execute(
            """update domain_asset_versions set status='active', metadata=jsonb_set(metadata,'{cek027Activation}',%s::jsonb,true), updated_at=now()
               where source_evidence->>'importKey' in (%s,%s) and status='reviewed'""",
            (payload, CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        )
        conn.execute(
            """update assessment_targets set status='active', production_eligible=true, metadata=jsonb_set(metadata,'{cek027Activation}',%s::jsonb,true), updated_at=now()
               where metadata->>'importKey'=%s and status='reviewed' and review_status='approved'""",
            (payload, TARGET_IMPORT_KEY),
        )
        conn.execute(
            """update curriculum_alignments set status='active', production_eligible=true, evidence=jsonb_set(evidence,'{cek027Activation}',%s::jsonb,true)
               where evidence->>'importKey'=%s and status='reviewed' and review_status='approved'""",
            (payload, TARGET_IMPORT_KEY),
        )
        conn.execute(
            """update domain_asset_migrations set status='applied', applied_at=now(),
                 impact_report=jsonb_set(impact_report,'{cek027Activation}',%s::jsonb,true),
                 rollback_snapshot=jsonb_set(rollback_snapshot,'{cek027SnapshotHashes}',%s::jsonb,true)
               where migration_key in (%s,%s) and status='dry_run'""",
            (payload, stable_json(snapshot_hashes), CURRICULUM_IMPORT_KEY, PROFILE_IMPORT_KEY),
        )


def restore_snapshots(conn: psycopg.Connection, audit_id: str) -> None:
    statements = (
        """update domain_asset_versions t set
             (asset_type,stable_id,version,display_name,status,authority,effective_scope,source_evidence,metadata,created_at,updated_at)=
             (s.asset_type,s.stable_id,s.version,s.display_name,s.status,s.authority,s.effective_scope,s.source_evidence,s.metadata,s.created_at,s.updated_at)
           from cek027_snapshot_assets s where t.id=s.id""",
        """update domain_asset_mappings t set
             (source_asset_version_id,target_asset_version_id,mapping_type,confidence,review_status,auto_applied,evidence,migration_id,created_at,reviewed_at)=
             (s.source_asset_version_id,s.target_asset_version_id,s.mapping_type,s.confidence,s.review_status,s.auto_applied,s.evidence,s.migration_id,s.created_at,s.reviewed_at)
           from cek027_snapshot_mappings s where t.id=s.id""",
        """update assessment_targets t set
             (stable_key,batch_key,question_item_id,question_block_id,scope_type,target_statement,is_primary_target,confidence,status,review_status,production_eligible,metadata,created_at,updated_at)=
             (s.stable_key,s.batch_key,s.question_item_id,s.question_block_id,s.scope_type,s.target_statement,s.is_primary_target,s.confidence,s.status,s.review_status,s.production_eligible,s.metadata,s.created_at,s.updated_at)
           from cek027_snapshot_targets s where t.id=s.id""",
        """update curriculum_alignments t set
             (stable_key,assessment_target_id,curriculum_asset_version_id,source_document_id,source_region_id,alignment_type,standard_version,confidence,original_basis,status,review_status,production_eligible,evidence,created_at)=
             (s.stable_key,s.assessment_target_id,s.curriculum_asset_version_id,s.source_document_id,s.source_region_id,s.alignment_type,s.standard_version,s.confidence,s.original_basis,s.status,s.review_status,s.production_eligible,s.evidence,s.created_at)
           from cek027_snapshot_alignments s where t.id=s.id""",
        """update domain_asset_migrations t set
             (migration_key,status,from_asset_version_id,to_asset_version_id,impact_report,rollback_snapshot,created_by,created_at,applied_at,rolled_back_at)=
             (s.migration_key,s.status,s.from_asset_version_id,s.to_asset_version_id,s.impact_report,s.rollback_snapshot,s.created_by,s.created_at,s.applied_at,s.rolled_back_at)
           from cek027_snapshot_migrations s where t.id=s.id""",
        """update review_queue_items t set
             (review_type,status,payload,created_at,resolved_at)=
             (s.review_type,s.status,s.payload,s.created_at,s.resolved_at)
           from cek027_snapshot_reviews s where t.id=s.id""",
    )
    with conn.transaction():
        for statement in statements:
            conn.execute(statement)
        conn.execute("delete from review_queue_items where id=%s", (audit_id,))


def reviewed_stage_valid(counts: dict[str, int]) -> bool:
    return (
        counts["reviewed_assets"] == 297
        and counts["approved_mappings"] == EXPECTED_COUNTS["mappings"]
        and counts["reviewed_targets"] == EXPECTED_COUNTS["targets"]
        and counts["reviewed_alignments"] == EXPECTED_COUNTS["alignments"]
        and counts["dry_run_migrations"] == EXPECTED_COUNTS["migrations"]
        and counts["pending_mappings"] == 0
        and counts["pending_targets"] == 0
        and counts["pending_alignments"] == 0
        and counts["pending_migrations"] == 0
        and counts["open_revision_reviews"] == 0
    )


def active_stage_valid(counts: dict[str, int]) -> bool:
    return (
        counts["revision_active_assets"] == 297
        and counts["all_active_assets"] == EXPECTED_COUNTS["baselineActiveAssets"] + 297
        and counts["active_targets"] == EXPECTED_COUNTS["targets"]
        and counts["active_alignments"] == EXPECTED_COUNTS["alignments"]
        and counts["approved_mappings"] == EXPECTED_COUNTS["mappings"]
        and counts["applied_migrations"] == EXPECTED_COUNTS["migrations"]
    )


def production_decision() -> dict[str, Any]:
    blockers = [
        "drill_review_is_simulated_not_teacher_acceptance",
        "authenticated_identity_and_authorization_not_proven",
        "cek20_error_patterns_not_persisted",
        "enhanced_browser_acceptance_pending_cek33",
        "full_gate_deferred_to_cek34",
        "real005_not_closed",
    ]
    return {
        "decision": "no_go",
        "productionActiveSwitchAllowed": False,
        "blockers": blockers,
        "nextAction": "obtain real teacher review and authenticated administrator approval, then complete CEK-33/34 before any separately authorized production switch",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="CEK-27 isolated curriculum/exam C002R active and rollback drill")
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--database-name", required=True)
    parser.add_argument("--file-store-root", type=pathlib.Path, required=True)
    parser.add_argument("--backup-manifest", type=pathlib.Path, required=True)
    parser.add_argument("--plan-path", type=pathlib.Path, required=True)
    parser.add_argument("--report-path", type=pathlib.Path, required=True)
    parser.add_argument("--reviewer", required=True)
    parser.add_argument("--reason", required=True)
    args = parser.parse_args()

    validate_isolated_database_name(args.database_name)
    validate_isolated_file_store(args.file_store_root)
    if not args.backup_manifest.is_file():
        raise ValueError("verified backup manifest is required")
    if not args.reviewer.strip() or not args.reason.strip():
        raise ValueError("drill reviewer and reason are required")
    plan = json.loads(args.plan_path.read_text(encoding="utf-8-sig"))
    plan_blockers = validate_plan(plan)
    if plan_blockers:
        raise ValueError(f"CEK-24 plan blockers: {', '.join(plan_blockers)}")

    file_store_before = file_store_fingerprint(args.file_store_root)
    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        database_name = conn.execute("select current_database() as name").fetchone()["name"]
        if database_name != args.database_name:
            raise ValueError("connection database does not match the isolated database name")

        before_counts = state_counts(conn)
        blockers = precondition_blockers(before_counts)
        if blockers:
            raise ValueError(f"CEK-27 precondition blockers: {', '.join(blockers)}")
        before_fingerprints = database_fingerprints(conn)
        snapshot_hashes = create_snapshots(conn)

        audit_id = apply_review_stage(conn, args.reviewer.strip(), args.reason.strip())
        reviewed_counts = state_counts(conn)
        if not reviewed_stage_valid(reviewed_counts):
            raise RuntimeError(f"reviewed stage validation failed: {stable_json(reviewed_counts)}")

        apply_active_stage(conn, str(args.backup_manifest.resolve()), snapshot_hashes)
        active_counts = state_counts(conn)
        active_fingerprints = database_fingerprints(conn)
        if not active_stage_valid(active_counts):
            raise RuntimeError(f"active stage validation failed: {stable_json(active_counts)}")
        historical_unchanged_during_active = (
            active_fingerprints["historicalConsumers"] == before_fingerprints["historicalConsumers"]
        )
        if not historical_unchanged_during_active:
            raise RuntimeError("historical consumer fingerprint changed during isolated activation")

        restore_snapshots(conn, audit_id)
        after_counts = state_counts(conn)
        after_fingerprints = database_fingerprints(conn)

    file_store_after = file_store_fingerprint(args.file_store_root)
    rollback_parity = before_fingerprints == after_fingerprints and before_counts == after_counts
    file_store_parity = file_store_before == file_store_after
    if not rollback_parity or not file_store_parity:
        raise RuntimeError("isolated rollback did not restore database/FileStore parity")

    report = {
        "schemaVersion": "cek027-curriculum-exam-c002r-isolated-drill.v1",
        "status": "pass",
        "taskId": "CEK-27",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "isolated_database_and_filestore",
        "isolation": {
            "databaseName": args.database_name,
            "fileStoreRoot": str(args.file_store_root.resolve()),
            "productionDatabaseTouched": False,
        },
        "backup": {"manifest": str(args.backup_manifest.resolve()), "verifiedByWrapper": True},
        "reviewSimulation": {
            "reviewer": args.reviewer.strip(),
            "reason": args.reason.strip(),
            "teacherAcceptance": False,
            "authenticatedIdentityProven": False,
        },
        "stages": {
            "baseline": before_counts,
            "reviewed": reviewed_counts,
            "active": active_counts,
            "rolledBack": after_counts,
        },
        "fingerprints": {
            "baseline": before_fingerprints,
            "active": active_fingerprints,
            "rolledBack": after_fingerprints,
            "snapshotTables": snapshot_hashes,
            "historicalUnchangedDuringActive": historical_unchanged_during_active,
            "rollbackParity": rollback_parity,
        },
        "fileStore": {"baseline": file_store_before, "rolledBack": file_store_after, "parity": file_store_parity},
        "productionDecision": production_decision(),
        "referencesReviewed": [
            {
                "anchor": "official-docs/EntityFramework.Docs",
                "adoptionDecision": "use isolated real database tests and explicit transaction boundaries; do not emulate rollback with an in-memory provider",
            },
            {
                "anchor": "official-docs/npgsql-doc",
                "adoptionDecision": "use one explicit psycopg connection with committed reviewed/active stages and snapshot-based restoration",
            },
            {
                "anchor": "official-docs/PowerShell-Docs",
                "adoptionDecision": "validate exact LiteralPath targets and isolation markers before recursive cleanup",
            },
        ],
        "completionBoundary": "This drill proves isolated reviewed-to-active-to-rollback mechanics only. It does not provide teacher acceptance, authenticated authorization, a production active switch, CEK-33 browser acceptance, CEK-34 full gate, REAL005 closure, or release approval.",
    }
    write_report(args.report_path, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
