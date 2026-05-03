from __future__ import annotations

import argparse
import json
import pathlib
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row


ALLOWED_DECISIONS = {"approve", "reject", "keep_pending"}


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def load_decisions(path: str) -> dict[str, list[dict[str, Any]]]:
    if not path:
        return {"assetDecisions": [], "mappingDecisions": [], "migrationDecision": []}
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8-sig"))
    return {
        "assetDecisions": list(data.get("assetDecisions", [])),
        "mappingDecisions": list(data.get("mappingDecisions", [])),
        "migrationDecision": list(data.get("migrationDecision", [])),
    }


def sample_assets(conn: psycopg.Connection, import_key: str) -> list[dict[str, Any]]:
    rows = conn.execute(
        """
        select id, asset_type, stable_id, display_name, status
        from domain_asset_versions
        where source_evidence->>'importKey' = %s
        order by asset_type, stable_id
        limit 3
        """,
        (import_key,),
    ).fetchall()
    decisions = ["approve", "reject", "keep_pending"]
    return [
        {
            "assetId": str(row["id"]),
            "assetType": row["asset_type"],
            "stableId": row["stable_id"],
            "displayName": row["display_name"],
            "currentStatus": row["status"],
            "decision": decisions[index],
            "reviewReason": f"C002M sample {decisions[index]} decision for contract coverage.",
        }
        for index, row in enumerate(rows)
    ]


def sample_mappings(conn: psycopg.Connection, import_key: str) -> list[dict[str, Any]]:
    rows = conn.execute(
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
        where m.evidence->>'importKey' = %s
        order by m.mapping_type, source.stable_id, target.stable_id
        limit 3
        """,
        (import_key,),
    ).fetchall()
    decisions = ["approve", "reject", "keep_pending"]
    return [
        {
            "mappingId": str(row["id"]),
            "mappingType": row["mapping_type"],
            "source": f"{row['source_asset_type']}:{row['source_stable_id']}",
            "target": f"{row['target_asset_type']}:{row['target_stable_id']}",
            "currentReviewStatus": row["review_status"],
            "decision": decisions[index],
            "reviewReason": f"C002M sample {decisions[index]} mapping decision for contract coverage.",
        }
        for index, row in enumerate(rows)
    ]


def validate_decisions(decisions: dict[str, list[dict[str, Any]]]) -> list[str]:
    errors: list[str] = []
    for group_name, key_name in (("assetDecisions", "assetId"), ("mappingDecisions", "mappingId")):
        seen: set[str] = set()
        for item in decisions[group_name]:
            decision = str(item.get("decision", ""))
            item_key = str(item.get(key_name, ""))
            reason = str(item.get("reviewReason", ""))
            if decision not in ALLOWED_DECISIONS:
                errors.append(f"{group_name}:{item_key} invalid decision: {decision}")
            if not item_key:
                errors.append(f"{group_name} missing {key_name}")
            if item_key in seen:
                errors.append(f"{group_name}:{item_key} duplicated")
            seen.add(item_key)
            if decision in {"approve", "reject"} and not reason.strip():
                errors.append(f"{group_name}:{item_key} reviewReason required")

    for item in decisions["migrationDecision"]:
        decision = str(item.get("decision", ""))
        if decision not in ALLOWED_DECISIONS:
            errors.append(f"migrationDecision invalid decision: {decision}")
        if decision in {"approve", "reject"} and not str(item.get("reviewReason", "")).strip():
            errors.append("migrationDecision reviewReason required")
    return errors


def before_counts(conn: psycopg.Connection, import_key: str) -> dict[str, int]:
    row = conn.execute(
        """
        select
            count(*) filter (where status = 'candidate') as candidate_assets,
            count(*) filter (where status = 'reviewed') as reviewed_assets,
            count(*) filter (where status = 'active') as active_assets
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
            count(*) filter (where status = 'applied') as applied_migrations,
            count(*) filter (where status = 'rejected') as rejected_migrations
        from domain_asset_migrations
        where migration_key = %s
        """,
        (import_key,),
    ).fetchone()
    review_row = conn.execute(
        """
        select count(*) as open_review_items
        from review_queue_items
        where review_type = 'c002_candidate_import'
          and status = 'open'
          and payload->>'importKey' = %s
        """,
        (import_key,),
    ).fetchone()
    return {
        "candidateAssets": int(row["candidate_assets"]),
        "reviewedAssets": int(row["reviewed_assets"]),
        "activeAssets": int(row["active_assets"]),
        "pendingMappings": int(mapping_row["pending_mappings"]),
        "approvedMappings": int(mapping_row["approved_mappings"]),
        "rejectedMappings": int(mapping_row["rejected_mappings"]),
        "autoAppliedMappings": int(mapping_row["auto_applied_mappings"]),
        "pendingMigrations": int(migration_row["pending_migrations"]),
        "appliedMigrations": int(migration_row["applied_migrations"]),
        "rejectedMigrations": int(migration_row["rejected_migrations"]),
        "openReviewItems": int(review_row["open_review_items"]),
    }


def apply_decisions(conn: psycopg.Connection, decisions: dict[str, list[dict[str, Any]]], import_key: str) -> None:
    for item in decisions["assetDecisions"]:
        decision = item["decision"]
        if decision == "keep_pending":
            continue
        next_status = "reviewed" if decision == "approve" else "deprecated"
        conn.execute(
            """
            update domain_asset_versions
            set status = %s,
                metadata = jsonb_set(
                    jsonb_set(metadata, '{reviewDecision}', to_jsonb(%s::text), true),
                    '{reviewReason}', to_jsonb(%s::text), true
                ),
                updated_at = now()
            where id = %s
              and source_evidence->>'importKey' = %s
              and status = 'candidate'
            """,
            (next_status, decision, item["reviewReason"], item["assetId"], import_key),
        )

    for item in decisions["mappingDecisions"]:
        decision = item["decision"]
        if decision == "keep_pending":
            continue
        next_status = "approved" if decision == "approve" else "rejected"
        conn.execute(
            """
            update domain_asset_mappings
            set review_status = %s,
                auto_applied = false,
                evidence = jsonb_set(
                    jsonb_set(evidence, '{reviewDecision}', to_jsonb(%s::text), true),
                    '{reviewReason}', to_jsonb(%s::text), true
                ),
                reviewed_at = now()
            where id = %s
              and evidence->>'importKey' = %s
              and review_status = 'pending_review'
            """,
            (next_status, decision, item["reviewReason"], item["mappingId"], import_key),
        )

    for item in decisions["migrationDecision"]:
        decision = item["decision"]
        if decision == "keep_pending":
            continue
        next_status = "dry_run" if decision == "approve" else "rejected"
        conn.execute(
            """
            update domain_asset_migrations
            set status = %s,
                impact_report = jsonb_set(
                    jsonb_set(impact_report, '{reviewDecision}', to_jsonb(%s::text), true),
                    '{reviewReason}', to_jsonb(%s::text), true
                )
            where migration_key = %s
              and status = 'pending_review'
            """,
            (next_status, decision, item["reviewReason"], import_key),
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--import-key", required=True)
    parser.add_argument("--report-path", default="docs/evidence/c002m-candidate-review-apply-contract-report.json")
    parser.add_argument("--decision-file", default="")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        counts_before = before_counts(conn, args.import_key)
        if args.decision_file:
            decisions = load_decisions(args.decision_file)
            decision_source = args.decision_file
        else:
            decisions = {
                "assetDecisions": sample_assets(conn, args.import_key),
                "mappingDecisions": sample_mappings(conn, args.import_key),
                "migrationDecision": [
                    {
                        "migrationKey": args.import_key,
                        "decision": "keep_pending",
                        "reviewReason": "C002M sample keeps migration pending until real human review.",
                    }
                ],
            }
            decision_source = "generated_sample_contract"

        errors = validate_decisions(decisions)
        blockers = []
        if counts_before["activeAssets"] > 0:
            blockers.append("active_assets_already_present")
        if counts_before["autoAppliedMappings"] > 0:
            blockers.append("auto_applied_mappings_already_present")
        if args.apply and not args.decision_file:
            blockers.append("decision_file_required_for_apply")
        if args.apply and errors:
            blockers.append("decision_validation_failed")

        applied = False
        if args.apply and not blockers:
            with conn.transaction():
                apply_decisions(conn, decisions, args.import_key)
            applied = True
            counts_after = before_counts(conn, args.import_key)
        else:
            counts_after = counts_before

    report = {
        "status": "pass" if not errors else "blocked",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "task": "C002M",
        "importKey": args.import_key,
        "mode": "apply" if args.apply else "dry_run",
        "applied": applied,
        "decisionSource": decision_source,
        "decisionCoverage": {
            "assetDecisions": len(decisions["assetDecisions"]),
            "mappingDecisions": len(decisions["mappingDecisions"]),
            "migrationDecision": len(decisions["migrationDecision"]),
            "coveredDecisionTypes": sorted(
                {
                    str(item["decision"])
                    for group in decisions.values()
                    for item in group
                    if "decision" in item
                }
            ),
        },
        "before": counts_before,
        "after": counts_after,
        "validationErrors": errors,
        "blockers": blockers,
        "activeActivationAllowed": False,
        "rollbackContract": {
            "requiresBackupManifestBeforeRealApply": True,
            "assetRollback": "restore status and metadata from backup snapshot or previous report before active guard",
            "mappingRollback": "restore review_status auto_applied evidence reviewed_at from backup snapshot",
            "migrationRollback": "restore status impact_report rollback_snapshot from backup snapshot",
            "reviewQueueRollback": "reopen c002_candidate_import review item if decisions are reverted",
        },
    }
    if blockers:
        report["status"] = "blocked"

    write_report(pathlib.Path(args.report_path), report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] in {"pass", "blocked"} and (not args.apply or applied) else 1


if __name__ == "__main__":
    raise SystemExit(main())
