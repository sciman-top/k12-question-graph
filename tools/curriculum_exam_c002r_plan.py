from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


CEK09_KEY = "cek009_curriculum_requirements_2022_2025_v1"
CEK23_KEY = "cek023_regional_exam_profile_candidate_v1"
PLAN_ID = "CEK024-CURRICULUM-EXAM-C002R-2026"


def stable_hash(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def build_plan(snapshot: dict[str, Any], cek20: dict[str, Any], cek23: dict[str, Any]) -> dict[str, Any]:
    if cek20.get("status") != "pass" or cek23.get("status") != "pass":
        raise ValueError("passing CEK-20 and CEK-23 evidence required")
    if not cek20.get("governance", {}).get("requiresC002RImpactReport"):
        raise ValueError("CEK-20 must require a C002R impact report")
    if cek23.get("governance", {}).get("candidateOnly") is not True:
        raise ValueError("candidate-only CEK-23 evidence required")
    evidence_profile_count = cek23.get("import", {}).get("counts", {}).get("profileAssets")
    if evidence_profile_count != snapshot.get("candidateAssets", {}).get("profiles"):
        raise ValueError("CEK-23 profile count does not match the live candidate snapshot")
    baseline = snapshot["activeBaseline"]
    mappings = []
    for row in snapshot["mappings"]:
        mapping_type = row["mappingType"]
        confidence = float(row["confidence"])
        complex_mapping = mapping_type in {"split", "merge", "broader", "narrower", "deprecated"}
        requires_review = complex_mapping or confidence < 0.85
        mappings.append({
            **row,
            "impactLevel": "high" if complex_mapping else "low",
            "requiresHumanReview": requires_review,
            "requiresReviewReason": requires_review,
            "noDirectActiveApply": True,
        })

    profiles = snapshot["profileSummaries"]
    references = snapshot["references"]
    impact_specs = [
        ("question_binding", references["questionBindings"], "update_after_review", True),
        ("paper_blueprint", references["paperBlueprints"], "preserve_version_binding", True),
        ("search_index", references["searchAssets"], "rebuild_derived_index", False),
        ("analysis_metric", references["analyses"], "freeze_historical_snapshot", True),
        ("export_template", references["exports"], "preserve_version_binding", True),
        ("score_import_template", references["scoreTemplates"], "hold_for_review", True),
    ]
    impacts = [{
        "impactType": impact_type,
        "affectedCount": count,
        "action": action,
        "requiresHumanReview": human_review,
        "requiresRollbackSnapshot": True,
        "rollbackKey": f"cek024:{impact_type}:{baseline['fingerprint'][:12]}",
    } for impact_type, count, action, human_review in impact_specs]

    complex_count = sum(item["mappingType"] in {"split", "merge", "broader", "narrower", "deprecated"} for item in mappings)
    low_confidence_count = sum(float(item["confidence"]) < 0.85 for item in mappings)
    cross_regime_count = sum(item.get("regimeType") == "transition" for item in profiles)
    error_patterns_persisted = bool(cek20.get("governance", {}).get("databaseWrite"))
    return {
        "schemaVersion": "curriculum-exam-c002r-plan.v1",
        "planId": PLAN_ID,
        "mode": "dry_run",
        "status": "candidate",
        "reviewStatus": "pending_review",
        "productionEligible": False,
        "noActiveWrite": True,
        "activeBaseline": baseline,
        "sourceGroups": [
            {"taskId": "CEK-09", "importKey": CEK09_KEY, "candidateCount": snapshot["candidateAssets"]["curriculum"], "mappingCount": len(mappings), "status": "candidate"},
            {"taskId": "CEK-20", "importKey": None, "candidateCount": 0, "status": "blocked_no_persisted_candidates", "requiresC002RImpactReport": bool(cek20.get("governance", {}).get("requiresC002RImpactReport"))},
            {"taskId": "CEK-23", "importKey": CEK23_KEY, "candidateCount": snapshot["candidateAssets"]["profiles"], "status": "candidate"},
        ],
        "candidateVersion": {
            "revisionKey": "cek024_curriculum_exam_candidate_v1",
            "status": "candidate",
            "reviewStatus": "pending_review",
            "productionEligible": False,
            "basedOnActiveVersion": baseline["activeVersionLabel"],
            "basedOnActiveImportKey": baseline["activeImportKey"],
            "assetCount": snapshot["candidateAssets"]["curriculum"] + snapshot["candidateAssets"]["profiles"],
            "noInPlaceActiveEdit": True,
            "requiredEvidenceFields": ["sourceEvidence", "mappingEvidence", "impactReport", "reviewDecision", "rollbackSnapshotKey"],
        },
        "mappingPlan": {"planId": "CEK024-MAPPINGS", "mappings": mappings},
        "profilePlan": {"profiles": profiles, "crossRegimeProfiles": cross_regime_count, "allRequireHumanReview": True},
        "errorPatternPlan": {
            "status": "ready" if error_patterns_persisted else "blocked_no_persisted_candidates",
            "candidateCount": 0,
            "promotionContractPassed": cek20.get("status") == "pass",
            "autoApplyAllowed": False,
        },
        "reviewGroups": [
            {"groupId": "complex_mappings", "status": "pending_review", "itemCount": complex_count, "reason": "split_merge_or_non_equivalent_mapping"},
            {"groupId": "low_confidence_mappings", "status": "pending_review", "itemCount": low_confidence_count, "reason": "confidence_below_0.85"},
            {"groupId": "regional_profiles", "status": "pending_review", "itemCount": len(profiles), "crossRegimeItemCount": cross_regime_count, "reason": "teacher_review_required_for_regional_profile"},
            {"groupId": "error_patterns", "status": "ready" if error_patterns_persisted else "blocked_no_persisted_candidates", "itemCount": 0, "reason": "CEK-20 contract has no persisted candidates"},
            {"groupId": "high_impact_consumers", "status": "pending_review", "itemCount": sum(item["requiresHumanReview"] for item in impacts), "reason": "historical_or_user_workflow_impact"},
        ],
        "impactReport": {"reportId": "CEK024-IMPACT", "impacts": impacts},
        "historicalReferencePolicy": {
            "silentRewriteAllowed": False,
            "questionListAction": "preserve_version_binding",
            "analysisAction": "freeze_historical_snapshot",
            "exportAction": "preserve_version_binding",
        },
        "reviewWorkflow": {
            "initialStatus": "pending_review",
            "requiresReviewReason": True,
            "requiresRollbackSnapshotBeforeApproval": True,
            "activeSwitchRole": "administrator",
            "teacherCanApplyActive": False,
        },
        "rollbackRequirements": [{"impactType": item["impactType"], "rollbackKey": item["rollbackKey"], "snapshotRequired": True} for item in impacts],
        "rollbackDrill": {"requiredSteps": ["restore_active_version", "restore_mapping_edges", "restore_impact_targets", "verify_historical_analysis"], "verifyAfterRollback": True},
        "inputEvidence": {"cek20Status": cek20.get("status"), "cek23Status": cek23.get("status"), "questionFingerprint": snapshot["questionFingerprint"]},
    }


def validate_plan(plan: dict[str, Any]) -> None:
    if plan["activeBaseline"]["status"] != "active" or not plan["candidateVersion"]["basedOnActiveVersion"]:
        raise ValueError("active baseline required")
    if not plan["noActiveWrite"] or not plan["candidateVersion"]["noInPlaceActiveEdit"]:
        raise ValueError("in-place or active write forbidden")
    impacts = plan["impactReport"]["impacts"]
    required = {"question_binding", "paper_blueprint", "search_index", "analysis_metric", "export_template", "score_import_template"}
    if {item["impactType"] for item in impacts} != required:
        raise ValueError("impact coverage incomplete")
    keys = [item["rollbackKey"] for item in impacts]
    if len(keys) != len(set(keys)) or not all(item["requiresRollbackSnapshot"] for item in impacts):
        raise ValueError("rollback coverage invalid")
    for mapping in plan["mappingPlan"]["mappings"]:
        if (mapping["mappingType"] in {"split", "merge", "broader", "narrower", "deprecated"} or float(mapping["confidence"]) < 0.85) and not mapping["requiresHumanReview"]:
            raise ValueError("risky mapping bypassed review")
    if plan["historicalReferencePolicy"]["silentRewriteAllowed"]:
        raise ValueError("historical silent rewrite forbidden")


def read_snapshot(conn: psycopg.Connection, active_version_label: str) -> dict[str, Any]:
    active = conn.execute("""select count(*) c,count(distinct source_evidence->>'importKey') import_keys,min(source_evidence->>'importKey') import_key,md5(string_agg(concat_ws('|',id::text,asset_type,stable_id,version::text,status,effective_scope::text,source_evidence::text,metadata::text),E'\n' order by id)) fingerprint from domain_asset_versions where status='active'""").fetchone()
    if active["import_keys"] != 1 or not active["import_key"]:
        raise ValueError("exactly one active import key required")
    mappings = conn.execute("""select m.id::text mapping_id,m.mapping_type,m.confidence,s.stable_id from_stable_id,t.stable_id to_stable_id from domain_asset_mappings m join domain_asset_versions s on s.id=m.source_asset_version_id join domain_asset_versions t on t.id=m.target_asset_version_id where m.review_status='pending_review' and s.source_evidence->>'importKey'=%s order by m.id""", (CEK09_KEY,)).fetchall()
    profiles = conn.execute("""select stable_id,metadata->'standard_regime'->>'regime_type' regime_type,metadata->'trend'->>'status' trend_status from domain_asset_versions where status='candidate' and source_evidence->>'importKey'=%s order by stable_id""", (CEK23_KEY,)).fetchall()
    counts = conn.execute("""select json_build_object('questionBindings',(select count(*) from assessment_target_knowledge_mappings),'paperBlueprints',(select count(*) from paper_blueprint_reviews),'searchAssets',(select count(*) from domain_asset_versions where status='active'),'analyses',(select count(*) from assessments),'exports',(select count(*) from paper_baskets),'scoreTemplates',(select count(*) from score_import_templates),'curriculum',(select count(*) from domain_asset_versions where status='candidate' and source_evidence->>'importKey'=%s),'profiles',(select count(*) from domain_asset_versions where status='candidate' and source_evidence->>'importKey'=%s),'questionFingerprint',(select md5(string_agg(to_jsonb(q)::text,E'\n' order by id)) from question_items q)) value""", (CEK09_KEY, CEK23_KEY)).fetchone()["value"]
    return {
        "activeBaseline": {"status": "active", "activeImportKey": active["import_key"], "activeVersionLabel": active_version_label, "activeAssetCount": active["c"], "fingerprint": active["fingerprint"]},
        "candidateAssets": {"curriculum": counts["curriculum"], "profiles": counts["profiles"]},
        "mappings": [{"mappingId": row["mapping_id"], "mappingType": row["mapping_type"], "fromStableId": row["from_stable_id"], "toStableId": row["to_stable_id"], "confidence": float(row["confidence"])} for row in mappings],
        "profileSummaries": [{"stableId": row["stable_id"], "regimeType": row["regime_type"], "trendStatus": row["trend_status"]} for row in profiles],
        "references": {key: counts[key] for key in ("questionBindings", "paperBlueprints", "searchAssets", "analyses", "exports", "scoreTemplates")},
        "questionFingerprint": counts["questionFingerprint"],
    }


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--cek20", type=Path, default=Path("docs/evidence/cek020-error-pattern-promotion-guard.json"))
    parser.add_argument("--cek23", type=Path, default=Path("docs/evidence/cek023-regional-exam-profile-query-smoke.json"))
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--active-version-label", default="junior-physics-guangzhou-source-derived-v1")
    args = parser.parse_args()
    cek20 = json.loads(args.cek20.read_text(encoding="utf-8-sig"))
    cek23 = json.loads(args.cek23.read_text(encoding="utf-8-sig"))
    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        before = read_snapshot(conn, args.active_version_label)
        plan = build_plan(before, cek20, cek23)
        validate_plan(plan)
        after = read_snapshot(conn, args.active_version_label)
    if stable_hash(before) != stable_hash(after):
        raise RuntimeError("CEK-24 read-only planner changed or observed unstable database state")
    write_json(args.plan, plan)
    report = {"schemaVersion": "cek024-curriculum-exam-c002r-plan.v1", "status": "pass", "checkedAt": datetime.now(timezone.utc).isoformat(), "taskId": "CEK-24", "planId": PLAN_ID, "readOnly": True, "databaseWrite": False, "planningSnapshotUnchanged": True, "snapshotHashBefore": stable_hash(before), "snapshotHashAfter": stable_hash(after), "activeBaseline": before["activeBaseline"], "candidateCounts": plan["candidateVersion"]["assetCount"], "mappingCount": len(plan["mappingPlan"]["mappings"]), "profileCount": len(plan["profilePlan"]["profiles"]), "reviewGroups": plan["reviewGroups"], "impacts": plan["impactReport"]["impacts"], "rollbackRequirements": plan["rollbackRequirements"], "errorPatternBoundary": plan["errorPatternPlan"], "historicalReferencePolicy": plan["historicalReferencePolicy"], "planSha256": stable_hash(plan), "productionEligible": False, "activeWrite": False, "completionBoundary": "CEK-24 proves read-only parity only for the planning inputs captured by this report and produces a C002R candidate revision/impact plan; no candidate is reviewed, migrated, or activated, and REAL005 remains not_closed."}
    write_json(args.report, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
