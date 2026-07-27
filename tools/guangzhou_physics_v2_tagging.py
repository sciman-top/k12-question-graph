from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row

from guangzhou_physics_v2_materialize import C002_IMPORT_KEY, WORKFLOW_KEY


DIFFICULTY_BAND_HARDNESS = {
    "easy": 0.25,
    "easy-to-medium": 0.40,
    "medium": 0.55,
    "medium-to-hard": 0.70,
    "hard": 0.85,
}

# 2015 predates the C003 package. This reviewed-candidate crosswalk maps its
# existing deterministic labels to the closest active C002 exam-point assets.
EXAM_POINT_CROSSWALK_2015: dict[int, tuple[str, ...]] = {
    1: ("EPHY-C003-007",),
    2: ("EPHY-C003-033", "EPHY-C003-032"),
    3: ("EPHY-C003-012",),
    4: ("EPHY-C003-030",),
    5: ("EPHY-C003-003", "EPHY-C003-004"),
    6: ("EPHY-C003-008",),
    7: ("EPHY-C003-028",),
    8: ("EPHY-C003-006",),
    9: ("EPHY-C003-021",),
    10: ("EPHY-C003-001",),
    11: ("EPHY-C003-019",),
    12: ("EPHY-C003-027",),
    13: ("EPHY-C003-024",),
    14: ("EPHY-C003-025",),
    15: ("EPHY-C003-025",),
    16: ("EPHY-C003-017",),
    17: ("EPHY-C003-021",),
    18: ("EPHY-C003-020",),
    19: ("EPHY-C003-018",),
    20: ("EPHY-C003-018", "EPHY-C003-014"),
    21: ("EPHY-C003-037", "EPHY-C003-036", "EPHY-C003-009"),
    22: ("EPHY-C003-041",),
    23: ("EPHY-C003-036", "EPHY-C003-034", "EPHY-C003-035", "EPHY-C003-042"),
    24: ("EPHY-C003-022", "EPHY-C003-042"),
}

PRIMARY_KNOWLEDGE_OVERRIDE_2015 = {10: "KPHY-C003-015"}


def split_tokens(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [item.strip() for item in str(value or "").replace("；", ";").split(";") if item.strip()]


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cursor:
        cursor.execute(sql, params)
        return list(cursor.fetchall())


def scalar(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor() as cursor:
        cursor.execute(sql, params)
        row = cursor.fetchone()
        return int(row[0]) if row else 0


def workflow_fingerprint(conn: psycopg.Connection[Any]) -> str:
    with conn.cursor() as cursor:
        cursor.execute(
            """
            select md5(coalesce(string_agg(id::text || ':' || row_to_json(q)::text, E'\n' order by id),''))
            from question_items q where custom_fields->>'sourceWorkflowKey'=%s
            """,
            (WORKFLOW_KEY,),
        )
        row = cursor.fetchone()
        return str(row[0] or "")


def load_active_assets(conn: psycopg.Connection[Any]) -> dict[str, dict[str, Any]]:
    asset_rows = rows(
        conn,
        """
        select stable_id, asset_type, display_name, metadata
        from domain_asset_versions
        where source_evidence->>'importKey'=%s and status='active'
        order by stable_id
        """,
        (C002_IMPORT_KEY,),
    )
    if len(asset_rows) != 452:
        raise ValueError(f"c002_active_asset_count_mismatch:{len(asset_rows)}")
    return {str(row["stable_id"]): row for row in asset_rows}


def derive_2015_tags(question_number: int, assets: dict[str, dict[str, Any]]) -> dict[str, Any]:
    exam_point_ids = list(EXAM_POINT_CROSSWALK_2015[question_number])
    knowledge_ids: list[str] = []
    ability_dimensions: list[str] = []
    for exam_point_id in exam_point_ids:
        asset = assets.get(exam_point_id)
        if not asset or asset["asset_type"] != "exam_point":
            raise ValueError(f"2015_exam_point_crosswalk_not_active:{question_number}:{exam_point_id}")
        metadata = asset["metadata"] or {}
        for knowledge_id in split_tokens(metadata.get("knowledge_stable_ids")):
            if knowledge_id not in knowledge_ids:
                knowledge_ids.append(knowledge_id)
        for ability in split_tokens(metadata.get("ability_dimensions")):
            if ability not in ability_dimensions:
                ability_dimensions.append(ability)

    override = PRIMARY_KNOWLEDGE_OVERRIDE_2015.get(question_number)
    if override:
        knowledge_ids = [override, *[item for item in knowledge_ids if item != override]]
    if not knowledge_ids:
        raise ValueError(f"2015_knowledge_crosswalk_empty:{question_number}")
    return {
        "primaryKnowledgeCandidateId": knowledge_ids[0],
        "knowledgeCandidateIds": knowledge_ids[1:],
        "primaryExamPointCandidateId": exam_point_ids[0],
        "examPointCandidateIds": exam_point_ids[1:],
        "abilityDimensions": ability_dimensions,
        "confidence": 0.64 if question_number == 10 else 0.72,
        "generationMethod": "deterministic_2015_seed_to_active_c002_crosswalk",
        "source": "2015 deterministic labels + question source regions + active C002 exam-point metadata",
        "crosswalkNeedsReview": question_number == 10,
    }


def validate_asset_refs(tag: dict[str, Any], assets: dict[str, dict[str, Any]]) -> None:
    refs = [
        (tag["primaryKnowledgeCandidateId"], "knowledge_point"),
        *[(item, "knowledge_point") for item in tag["knowledgeCandidateIds"]],
        (tag["primaryExamPointCandidateId"], "exam_point"),
        *[(item, "exam_point") for item in tag["examPointCandidateIds"]],
    ]
    for stable_id, expected_type in refs:
        asset = assets.get(stable_id)
        if not asset or asset["asset_type"] != expected_type:
            raise ValueError(f"inactive_or_wrong_tag_asset:{stable_id}:{expected_type}")


def difficulty_candidate(
    observed: float | None, year_report_location: str, exam_point: dict[str, Any]
) -> tuple[float, dict[str, Any]]:
    metadata = exam_point["metadata"] or {}
    band = str(metadata.get("difficulty_band") or "").strip()
    if band not in DIFFICULTY_BAND_HARDNESS:
        raise ValueError(f"unsupported_exam_point_difficulty_band:{exam_point['stable_id']}:{band}")
    estimated = DIFFICULTY_BAND_HARDNESS[band]
    normalized_observed = round(1.0 - observed, 4) if observed is not None else None
    delta = round(abs(normalized_observed - estimated), 4) if normalized_observed is not None else None
    return estimated, {
        "estimated": {
            "value": estimated,
            "band": band,
            "scale": "0_easy_to_1_hard",
            "source": f"active C002 exam point {exam_point['stable_id']}",
            "generationMethod": "deterministic_difficulty_band_mapping",
        },
        "observed": {
            "value": observed,
            "scale": "exam_report_difficulty_coefficient_higher_is_easier",
            "normalizedHardness": normalized_observed,
            "source": year_report_location if observed is not None else None,
            "generationMethod": "exam_analysis_report_extraction_candidate" if observed is not None else None,
        },
        "comparison": {
            "absoluteHardnessDelta": delta,
            "conflictRequiresReview": delta is not None and delta > 0.25,
            "resolutionStatus": "pending_review",
        },
        "reviewStatus": "pending_review",
    }


def write_reports(report: dict[str, Any], json_path: Path, markdown_path: Path) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# Guangzhou Physics v2 Tagging",
        "",
        f"- status: {report['status']}",
        f"- mode: {report['mode']}",
        f"- questions: {report['counts']['questions']}",
        f"- complete_tag_candidates: {report['counts']['completeTagCandidates']}",
        f"- observed_difficulty_candidates: {report['counts']['observedDifficultyCandidates']}",
        f"- estimated_difficulty_candidates: {report['counts']['estimatedDifficultyCandidates']}",
        f"- difficulty_conflicts_pending_review: {report['counts']['difficultyConflictsPendingReview']}",
        f"- c002_active_count: {report['counts']['c002ActiveCount']}",
        "",
        "## Boundary",
        report["boundary"],
    ]
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Materialize Guangzhou physics v2 tag candidates")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if args.apply and (not args.backup_manifest or not Path(args.backup_manifest).is_file()):
        raise ValueError("verified_backup_manifest_required_for_apply")
    password = os.environ.get("PGPASSWORD", "")
    if not password:
        raise ValueError("PGPASSWORD_required")

    conn = psycopg.connect(host=args.host, port=args.port, dbname=args.database, user=args.user, password=password)
    conn.autocommit = False
    try:
        assets = load_active_assets(conn)
        questions = rows(
            conn,
            """
            select id, difficulty_observed, custom_fields, quality_signals
            from question_items where custom_fields->>'sourceWorkflowKey'=%s
            order by (custom_fields->>'year')::int, (custom_fields->>'questionNo')::int
            """,
            (WORKFLOW_KEY,),
        )
        if len(questions) != 234:
            raise ValueError(f"tagging_question_count_mismatch:{len(questions)}")

        fingerprint_before = workflow_fingerprint(conn)
        active_before = scalar(conn, "select count(*) from domain_asset_versions where source_evidence->>'importKey'=%s and status='active'", (C002_IMPORT_KEY,))
        updated_question_count = 0
        for question in questions:
            custom = question["custom_fields"] or {}
            quality = question["quality_signals"] or {}
            year = int(custom["year"])
            number = int(custom["questionNo"])
            if year == 2015:
                tag = derive_2015_tags(number, assets)
            else:
                tag = {
                    "primaryKnowledgeCandidateId": str(custom.get("primaryKnowledgeCandidateId") or ""),
                    "knowledgeCandidateIds": split_tokens(custom.get("knowledgeCandidateIds")),
                    "primaryExamPointCandidateId": str(custom.get("primaryExamPointCandidateId") or ""),
                    "examPointCandidateIds": split_tokens(custom.get("examPointCandidateIds")),
                    "abilityDimensions": split_tokens(custom.get("abilityDimensions")),
                    "confidence": float(quality.get("candidateConfidence") or 0.0),
                    "generationMethod": "c003_quality_review_candidate_mapping",
                    "source": "C003 question package + question/answer/year-report source evidence",
                    "crosswalkNeedsReview": False,
                }
            validate_asset_refs(tag, assets)
            if not tag["abilityDimensions"]:
                raise ValueError(f"ability_dimensions_empty:{year}:{number}")

            primary_exam_point = assets[tag["primaryExamPointCandidateId"]]
            estimated, difficulty = difficulty_candidate(
                float(question["difficulty_observed"]) if question["difficulty_observed"] is not None else None,
                str(custom.get("yearReportEvidenceLocation") or ""),
                primary_exam_point,
            )
            custom.update(
                {
                    "primaryKnowledgeCandidateId": tag["primaryKnowledgeCandidateId"],
                    "knowledgeCandidateIds": tag["knowledgeCandidateIds"],
                    "primaryExamPointCandidateId": tag["primaryExamPointCandidateId"],
                    "examPointCandidateIds": tag["examPointCandidateIds"],
                    "abilityDimensions": tag["abilityDimensions"],
                    "taggingStatus": "pending_review",
                    "tagCandidateProvenance": {
                        "source": tag["source"],
                        "generationMethod": tag["generationMethod"],
                        "confidence": tag["confidence"],
                        "reviewStatus": "pending_review",
                        "productionEligible": False,
                        "knowledgeAssetImportKey": C002_IMPORT_KEY,
                        "knowledgeAssetStatus": "active_reference_only",
                        "sourceDocumentId": custom.get("sourceDocumentId"),
                        "sourceRegionIds": custom.get("questionSourceRegionIds", []),
                        "crosswalkNeedsReview": tag["crosswalkNeedsReview"],
                    },
                    "difficultyCandidate": difficulty,
                }
            )
            quality.update(
                {
                    "reviewStatus": "pending_review",
                    "productionEligible": False,
                    "teacherValidationRequired": True,
                    "candidateConfidence": tag["confidence"],
                    "tagCandidateGenerationMethod": tag["generationMethod"],
                    "difficultyReviewStatus": "pending_review",
                }
            )
            with conn.cursor() as cursor:
                custom_json = json.dumps(custom, ensure_ascii=False)
                quality_json = json.dumps(quality, ensure_ascii=False)
                cursor.execute(
                    """
                    update question_items set difficulty_estimated=%s, primary_knowledge_id=null,
                        custom_fields=%s::jsonb, quality_signals=%s::jsonb,
                        status='pending_review', updated_at=now()
                    where id=%s
                      and (
                        difficulty_estimated is distinct from %s
                        or primary_knowledge_id is not null
                        or custom_fields is distinct from %s::jsonb
                        or quality_signals is distinct from %s::jsonb
                        or status is distinct from 'pending_review'
                      )
                    """,
                    (
                        estimated,
                        custom_json,
                        quality_json,
                        question["id"],
                        estimated,
                        custom_json,
                        quality_json,
                    ),
                )
                updated_question_count += cursor.rowcount

        counts = {
            "questions": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s", (WORKFLOW_KEY,)),
            "completeTagCandidates": scalar(conn, """
                select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s
                  and coalesce(custom_fields->>'primaryKnowledgeCandidateId','')<>''
                  and coalesce(custom_fields->>'primaryExamPointCandidateId','')<>''
                  and jsonb_array_length(coalesce(custom_fields->'abilityDimensions','[]'::jsonb))>0
                  and custom_fields#>>'{tagCandidateProvenance,reviewStatus}'='pending_review'
                """, (WORKFLOW_KEY,)),
            "observedDifficultyCandidates": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and difficulty_observed is not null", (WORKFLOW_KEY,)),
            "estimatedDifficultyCandidates": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and difficulty_estimated is not null", (WORKFLOW_KEY,)),
            "difficultyConflictsPendingReview": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and coalesce((custom_fields#>>'{difficultyCandidate,comparison,conflictRequiresReview}')::boolean,false)", (WORKFLOW_KEY,)),
            "pendingReviewQuestions": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and status='pending_review'", (WORKFLOW_KEY,)),
            "productionEligibleQuestions": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and coalesce((custom_fields->>'productionEligible')::boolean,false)", (WORKFLOW_KEY,)),
            "primaryKnowledgeIdWrites": scalar(conn, "select count(*) from question_items where custom_fields->>'sourceWorkflowKey'=%s and primary_knowledge_id is not null", (WORKFLOW_KEY,)),
            "c002ActiveCount": scalar(conn, "select count(*) from domain_asset_versions where source_evidence->>'importKey'=%s and status='active'", (C002_IMPORT_KEY,)),
        }
        expected = {
            "questions": 234,
            "completeTagCandidates": 234,
            "observedDifficultyCandidates": 150,
            "estimatedDifficultyCandidates": 234,
            "pendingReviewQuestions": 234,
            "productionEligibleQuestions": 0,
            "primaryKnowledgeIdWrites": 0,
            "c002ActiveCount": 452,
        }
        failures = [f"{name}:{counts[name]}!=expected:{value}" for name, value in expected.items() if counts[name] != value]
        if failures or active_before != counts["c002ActiveCount"]:
            raise ValueError(f"tagging_invariant_failed:{failures}:active_before={active_before}")

        if args.apply:
            conn.commit()
        else:
            conn.rollback()
        fingerprint_after = workflow_fingerprint(conn)
        report = {
            "status": "pass" if args.apply else "dry_run_pass",
            "taskId": "GUANGZHOU_PHYSICS_V2_TAGGING",
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "mode": "apply" if args.apply else "transaction_rollback_dry_run",
            "workflowKey": WORKFLOW_KEY,
            "backupManifest": args.backup_manifest if args.apply else None,
            "updatedQuestionCount": updated_question_count,
            "counts": counts,
            "stateFingerprintBefore": fingerprint_before,
            "stateFingerprintAfter": fingerprint_after,
            "dryRunRolledBack": None if args.apply else fingerprint_before == fingerprint_after,
            "activeAssetWrite": False,
            "questionCandidateWriteApplied": args.apply and updated_question_count > 0,
            "externalAiCalls": 0,
            "realStudentDataUsed": False,
            "boundary": "Tag and difficulty candidates only. C002 assets are referenced but not modified; primary_knowledge_id remains null, all questions remain pending_review/productionEligible=false, and teacher validation is still required.",
            "rollback": f"restore database from {args.backup_manifest}" if args.apply else "transaction rollback completed",
        }
        write_reports(report, Path(args.output), Path(args.markdown_output))
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
