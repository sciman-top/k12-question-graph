from __future__ import annotations

import argparse
import hashlib
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

import psycopg
from psycopg.rows import dict_row

from curriculum_candidate_import import active_fingerprint, stable_json


IMPORT_KEY = "cek016_guangzhou_assessment_targets_v1"
ID_NAMESPACE = uuid.UUID("2a295d7e-0f66-45a5-8ce1-7b5739cd34bf")


class AssessmentTargetImportError(RuntimeError):
    pass


def deterministic_id(value: str) -> str:
    return str(uuid.uuid5(ID_NAMESPACE, value))


def validate_package(package: Mapping[str, Any]) -> None:
    governance = package.get("governance", {})
    if (
        governance.get("status") != "candidate"
        or governance.get("review_status") != "pending_review"
        or governance.get("production_eligible") is not False
        or governance.get("active_write") is not False
    ):
        raise AssessmentTargetImportError("unsafe assessment target package")
    scope_keys = [row["question_scope"]["scope_key"] for row in package.get("targets", [])]
    if not scope_keys or len(scope_keys) != len(set(scope_keys)):
        raise AssessmentTargetImportError("missing or duplicate target scope keys")
    if any(row.get("review_status") != "pending_review" or row.get("production_eligible") is not False for row in package["targets"]):
        raise AssessmentTargetImportError("target package contains non-candidate rows")


def _resolve_question_scope(conn: psycopg.Connection, target: Mapping[str, Any]) -> None:
    scope = target["question_scope"]
    row = conn.execute("select id from question_items where id=%s", (scope["question_item_id"],)).fetchone()
    if not row:
        raise AssessmentTargetImportError(f"question missing:{scope['question_item_id']}")
    block_id = scope.get("question_block_id")
    if scope["scope_type"] == "whole_question":
        if block_id is not None:
            raise AssessmentTargetImportError(f"whole scope has block:{scope['scope_key']}")
        return
    block = conn.execute(
        "select question_item_id::text,block_type from question_blocks where id=%s",
        (block_id,),
    ).fetchone()
    if not block or block["question_item_id"] != scope["question_item_id"] or block["block_type"] != scope["scope_type"]:
        raise AssessmentTargetImportError(f"scope block mismatch:{scope['scope_key']}")


def import_package(
    conn: psycopg.Connection,
    package: Mapping[str, Any],
    alignment_package: Mapping[str, Any],
    backup_manifest: str,
) -> dict[str, int]:
    validate_package(package)
    alignment_by_id = {row["alignmentId"]: row for row in alignment_package["alignmentCandidates"]}
    counts = {"targets": 0, "knowledgeMappings": 0, "curriculumAlignments": 0, "reviewItems": 0}
    for target in package["targets"]:
        _resolve_question_scope(conn, target)
        scope = target["question_scope"]
        metadata = {
            "importKey": IMPORT_KEY,
            "backupManifest": backup_manifest,
            "curriculumAlignmentIds": target["curriculum_alignment_ids"],
            "abilityDimensions": target["ability_dimensions"],
            "cognitiveDemands": target["cognitive_demands"],
            "methodModelExperimentIds": target["method_model_experiment_ids"],
            "contextType": target["context_type"],
            "representationTypes": target["representation_types"],
            "taskType": target["task_type"],
            "scoreWeight": target.get("score_weight"),
            "fieldProvenance": target["field_provenance"],
            "evidenceRefs": target["evidence_refs"],
            "candidateOnly": True,
        }
        row = conn.execute(
            """insert into assessment_targets
            (id,stable_key,batch_key,question_item_id,question_block_id,scope_type,target_statement,is_primary_target,confidence,status,review_status,production_eligible,metadata,created_at,updated_at)
            values (%s,%s,%s,%s,%s,%s,%s,true,%s,'candidate','pending_review',false,%s::jsonb,now(),now())
            on conflict (stable_key) do update set
              batch_key=excluded.batch_key,question_item_id=excluded.question_item_id,
              question_block_id=excluded.question_block_id,scope_type=excluded.scope_type,
              target_statement=excluded.target_statement,is_primary_target=true,
              confidence=excluded.confidence,status='candidate',review_status='pending_review',
              production_eligible=false,metadata=excluded.metadata,updated_at=now()
            returning id""",
            (
                deterministic_id(target["target_id"]), target["target_id"], IMPORT_KEY,
                scope["question_item_id"], scope.get("question_block_id"), scope["scope_type"],
                target["target_statement"], target["confidence"], stable_json(metadata),
            ),
        ).fetchone()
        target_id = str(row["id"])
        conn.execute("delete from assessment_target_knowledge_mappings where assessment_target_id=%s", (target_id,))
        conn.execute("delete from curriculum_alignments where assessment_target_id=%s", (target_id,))

        knowledge_stable_id = target.get("primary_knowledge_id")
        if knowledge_stable_id:
            knowledge = conn.execute(
                """select id from domain_asset_versions
                where asset_type='knowledge_point' and stable_id=%s and status='active'""",
                (knowledge_stable_id,),
            ).fetchone()
            if not knowledge:
                raise AssessmentTargetImportError(f"active knowledge missing:{knowledge_stable_id}")
            conn.execute(
                """insert into assessment_target_knowledge_mappings
                (assessment_target_id,domain_asset_version_id,role,confidence,status,review_status,production_eligible,evidence,created_at)
                values (%s,%s,'primary',%s,'candidate','pending_review',false,%s::jsonb,now())""",
                (target_id, knowledge["id"], target["confidence"], stable_json({"importKey": IMPORT_KEY, "stableId": knowledge_stable_id})),
            )
            counts["knowledgeMappings"] += 1

        for alignment_id in target["curriculum_alignment_ids"]:
            alignment = alignment_by_id.get(alignment_id)
            if not alignment:
                raise AssessmentTargetImportError(f"alignment missing:{alignment_id}")
            curriculum = conn.execute(
                """select id from domain_asset_versions
                where asset_type='requirement_facet' and stable_id=%s and status='candidate'""",
                (alignment["requirementFacetStableId"],),
            ).fetchone()
            if not curriculum:
                raise AssessmentTargetImportError(f"curriculum facet missing:{alignment['requirementFacetStableId']}")
            paper_anchors = alignment["evidence"]["paperAnchors"]
            if not paper_anchors:
                raise AssessmentTargetImportError(f"paper anchor missing:{alignment_id}")
            paper = paper_anchors[0]
            stable_key = f"{alignment_id}:{target['target_id']}"
            conn.execute(
                """insert into curriculum_alignments
                (id,stable_key,assessment_target_id,curriculum_asset_version_id,source_document_id,source_region_id,alignment_type,standard_version,confidence,original_basis,status,review_status,production_eligible,evidence,created_at)
                values (%s,%s,%s,%s,%s,%s,%s,%s,%s,false,'candidate','pending_review',false,%s::jsonb,now())""",
                (
                    deterministic_id(stable_key), stable_key, target_id, curriculum["id"],
                    paper["sourceDocumentId"], paper["sourceRegionId"], alignment["alignmentType"],
                    alignment["standardVersion"], alignment["confidence"], stable_json({"importKey": IMPORT_KEY, **alignment["evidence"]}),
                ),
            )
            counts["curriculumAlignments"] += 1

        review = next(row for row in package["review_queue"] if row["target_id"] == target["target_id"])
        review_id = deterministic_id(f"review:{target['target_id']}")
        payload = {
            "importKey": IMPORT_KEY,
            "assessmentTargetId": target_id,
            "assessmentTargetStableKey": target["target_id"],
            "questionItemId": scope["question_item_id"],
            "questionBlockId": scope.get("question_block_id"),
            "scopeType": scope["scope_type"],
            "scopeKey": scope["scope_key"],
            "riskLevel": review["priority"],
            "reasons": review["reasons"],
            "sourceEvidence": target["evidence_refs"],
            "productionEligible": False,
        }
        conn.execute(
            """insert into review_queue_items(id,review_type,status,payload,created_at,resolved_at)
            values (%s,'assessment_target','open',%s::jsonb,now(),null)
            on conflict (id) do update set review_type='assessment_target',status='open',payload=excluded.payload,resolved_at=null""",
            (review_id, stable_json(payload)),
        )
        counts["targets"] += 1
        counts["reviewItems"] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", type=Path, required=True)
    parser.add_argument("--alignments", type=Path, required=True)
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--backup-manifest", type=Path, required=True)
    parser.add_argument("--backup-verified", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.apply and (not args.backup_verified or not args.backup_manifest.is_file()):
        raise AssessmentTargetImportError("apply requires a backup verified in the current run")
    package = json.loads(args.targets.read_text(encoding="utf-8"))
    alignments = json.loads(args.alignments.read_text(encoding="utf-8"))
    validate_package(package)
    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        before = active_fingerprint(conn)
        counts = {"targets": len(package["targets"]), "knowledgeMappings": 0, "curriculumAlignments": 0, "reviewItems": len(package["review_queue"])}
        status = "dry_run"
        if args.apply:
            with conn.transaction():
                counts = import_package(conn, package, alignments, str(args.backup_manifest))
            status = "applied"
        after = active_fingerprint(conn)
        if before != after:
            raise AssessmentTargetImportError("active fingerprint changed")
    report = {
        "schemaVersion": "cek016-assessment-target-import.v1",
        "status": status,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "importKey": IMPORT_KEY,
        "counts": counts,
        "activeBefore": before,
        "activeAfter": after,
        "activeUnchanged": True,
        "backupManifest": str(args.backup_manifest),
        "candidateOnly": True,
        "productionEligible": False,
        "reportSha256": hashlib.sha256(stable_json(counts).encode()).hexdigest(),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
