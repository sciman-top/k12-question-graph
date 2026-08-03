from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


def _block_content(block: Mapping[str, Any]) -> Mapping[str, Any]:
    content = block.get("content") or {}
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except json.JSONDecodeError:
            return {}
    return content if isinstance(content, Mapping) else {}


def _has_stem_content(block: Mapping[str, Any]) -> bool:
    return block.get("block_type") == "stem" and bool(str(_block_content(block).get("text") or "").strip())


def _has_answer_content(block: Mapping[str, Any]) -> bool:
    if block.get("block_type") != "answer":
        return False
    content = _block_content(block)
    return bool(str(content.get("value") or "").strip() or str(content.get("solution") or "").strip())


def build_index(snapshot: Mapping[str, Any], role_map: Mapping[str, Any]) -> dict[str, Any]:
    roles = dict(role_map["roles"])
    role_by_type = {value: key for key, value in roles.items()}
    sources = {(int(row["year"]), row["source_type"]): row for row in snapshot["sources"]}
    blocks: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in snapshot["blocks"]:
        blocks[str(row["question_item_id"])].append(dict(row))
    blockers: list[str] = []
    corpus_blockers: list[str] = []
    report_blockers: list[str] = []
    reviews: list[dict[str, Any]] = []
    questions: list[dict[str, Any]] = []
    expected_years = {int(year) for year in role_map.get("expectedYears", [])}
    actual_years = {int(row["year"]) for row in snapshot["questions"]}
    if expected_years and actual_years != expected_years:
        blockers.append(
            "question_year_coverage_mismatch:"
            f"expected={','.join(map(str, sorted(expected_years)))}:"
            f"actual={','.join(map(str, sorted(actual_years)))}"
        )
    expected_count = role_map.get("expectedQuestionCount")
    if expected_count is not None and len(snapshot["questions"]) != int(expected_count):
        blockers.append(
            f"question_count_mismatch:expected={int(expected_count)}:actual={len(snapshot['questions'])}"
        )
        corpus_blockers.append(blockers[-1])
    question_keys = [(int(row["year"]), int(row["question_number"])) for row in snapshot["questions"]]
    if len(question_keys) != len(set(question_keys)):
        blockers.append("duplicate_year_question_number")
        corpus_blockers.append("duplicate_year_question_number")
    expected_counts_by_year = {
        int(year): int(count)
        for year, count in dict(role_map.get("expectedQuestionCountsByYear") or {}).items()
    }
    for year, count in expected_counts_by_year.items():
        expected_numbers = set(range(1, count + 1))
        actual_numbers = {number for item_year, number in question_keys if item_year == year}
        if actual_numbers != expected_numbers:
            missing = ",".join(map(str, sorted(expected_numbers - actual_numbers)))
            unexpected = ",".join(map(str, sorted(actual_numbers - expected_numbers)))
            corpus_blockers.append(
                f"question_sequence_mismatch:{year}:missing={missing}:unexpected={unexpected}"
            )
    for question in snapshot["questions"]:
        qid = str(question["question_item_id"]); year = int(question["year"]); number = int(question["question_number"])
        question_blocks = blocks.get(qid, [])
        anchors = {role: [] for role in roles}
        for block in question_blocks:
            role = role_by_type.get(block["source_type"])
            if not role:
                continue
            anchors[role].append({
                "questionBlockId": block["question_block_id"],
                "sourceRegionId": block["source_region_id"],
                "sourceDocumentId": block["source_document_id"],
                "pageNumber": block.get("page_number"),
                "regionType": block.get("region_type"),
            })
        for role in ("paper", "answer"):
            if not anchors[role]:
                value = f"{role}_anchor_missing:{year}:{number}"
                blockers.append(value)
                corpus_blockers.append(value)
        if not anchors["report"]:
            report_blockers.append(f"report_anchor_missing:{year}:{number}")
            reviews.append({"questionItemId": qid, "year": year, "questionNumber": number, "reason": "report_question_anchor_missing", "status": "pending_review"})
        if not any(_has_stem_content(block) for block in question_blocks):
            corpus_blockers.append(f"question_stem_missing:{year}:{number}")
        if not any(_has_answer_content(block) for block in question_blocks):
            corpus_blockers.append(f"answer_content_missing:{year}:{number}")
        if question.get("status") != "pending_review":
            corpus_blockers.append(f"question_status_not_pending_review:{year}:{number}")
        if bool(question.get("production_eligible")):
            corpus_blockers.append(f"question_production_eligible:{year}:{number}")
        questions.append({
            "questionItemId": qid, "year": year, "questionNumber": number,
            "joinKeys": {"questionItemId": qid}, "anchors": anchors,
            "sourceDocuments": {
                role: {
                    "sourceDocumentId": sources[(year, source_type)]["source_document_id"],
                    "fileAssetId": sources[(year, source_type)]["file_asset_id"],
                }
                if (year, source_type) in sources else None
                for role, source_type in roles.items()
            },
            "candidates": {
                "primaryKnowledgeCandidateId": question.get("primary_knowledge_candidate_id"),
                "knowledgeCandidateIds": list(question.get("knowledge_candidate_ids") or []),
                "primaryExamPointCandidateId": question.get("primary_exam_point_candidate_id"),
                "primaryKnowledgeLabel": question.get("primary_knowledge_label") or "",
                "officialExamPointSummary": question.get("official_exam_point_summary") or "",
                "abilityDimensions": list(question.get("ability_dimensions") or []),
                "questionType": question.get("question_type") or "unclassified",
                "scoreWeight": float(question["default_score"]) if question.get("default_score") is not None else None,
                "stemText": next(
                    (str(_block_content(block).get("text") or "") for block in question_blocks if _has_stem_content(block)),
                    "",
                ),
                "blockTypes": list(dict.fromkeys(str(block.get("block_type") or "") for block in question_blocks if block.get("block_type"))),
            },
            "readiness": {
                "stemPresent": any(_has_stem_content(block) for block in question_blocks),
                "answerPresent": any(_has_answer_content(block) for block in question_blocks),
                "paperAnchorPresent": bool(anchors["paper"]),
                "answerAnchorPresent": bool(anchors["answer"]),
                "reportAnchorPresent": bool(anchors["report"]),
                "pendingReview": question.get("status") == "pending_review",
                "productionEligible": bool(question.get("production_eligible")),
            },
            "display": {role: (sources.get((year, source_type), {}).get("source_title") or "") for role, source_type in roles.items()},
        })
    for rule in role_map.get("sharedFileRoleRequirements", []):
        year = int(rule["year"]); left, right = rule["roles"]
        a = sources.get((year, roles[left])); b = sources.get((year, roles[right]))
        if rule.get("requireSameFileAssetId") and (not a or not b or a["file_asset_id"] != b["file_asset_id"]):
            blockers.append(f"shared_file_role_mismatch:{year}:{left}:{right}")
    source_coverage = {
        role: sorted(year for year in actual_years if (year, source_type) in sources)
        for role, source_type in roles.items()
    }
    for role, years in source_coverage.items():
        if expected_years and set(years) != expected_years:
            blockers.append(f"source_year_coverage_mismatch:{role}")
            if role in ("paper", "answer"):
                corpus_blockers.append(f"source_year_coverage_mismatch:{role}")
            else:
                report_blockers.append(f"source_year_coverage_mismatch:{role}")
    corpus_blockers = sorted(set(corpus_blockers))
    report_blockers = sorted(set(report_blockers))
    question_corpus_ready = not corpus_blockers
    report_evidence_ready = not report_blockers
    return {
        "schemaVersion": "cek012-guangzhou-exam-evidence-index.v1",
        "questions": questions,
        "sourceCoverage": source_coverage,
        "blockers": sorted(set(blockers)),
        "readinessBlockers": [*corpus_blockers, *report_blockers],
        "readiness": {
            "questionCorpusReady": question_corpus_ready,
            "assessmentTargetExtractionReady": question_corpus_ready,
            "reportEvidenceReady": report_evidence_ready,
            "allFieldExtractionReady": question_corpus_ready and report_evidence_ready,
            "questionCount": len(questions),
            "stemCount": sum(row["readiness"]["stemPresent"] for row in questions),
            "answerContentCount": sum(row["readiness"]["answerPresent"] for row in questions),
            "paperAnchorCount": sum(row["readiness"]["paperAnchorPresent"] for row in questions),
            "answerAnchorCount": sum(row["readiness"]["answerAnchorPresent"] for row in questions),
            "reportAnchorCount": sum(row["readiness"]["reportAnchorPresent"] for row in questions),
            "corpusBlockers": corpus_blockers,
            "reportBlockers": report_blockers,
        },
        "reviewItems": reviews,
    }


def load_snapshot(connection_string: str, batch_key: str, workflow_key: str) -> dict[str, Any]:
    import psycopg
    from psycopg.rows import dict_row
    with psycopg.connect(connection_string, row_factory=dict_row) as conn:
        with conn.transaction():
            conn.execute("set transaction read only")
            questions = conn.execute("""select id::text as question_item_id,(custom_fields->>'year')::int as year,(custom_fields->>'questionNo')::int as question_number,status,question_type,default_score,coalesce((custom_fields->>'productionEligible')::boolean,false) as production_eligible,custom_fields->>'primaryKnowledgeCandidateId' as primary_knowledge_candidate_id,coalesce(custom_fields->'knowledgeCandidateIds','[]'::jsonb) as knowledge_candidate_ids,custom_fields->>'primaryExamPointCandidateId' as primary_exam_point_candidate_id,coalesce(nullif(custom_fields->>'primaryKnowledgeLabel',''),(select dav.display_name from domain_asset_versions dav where dav.asset_type='knowledge_point' and dav.status='active' and dav.stable_id=custom_fields->>'primaryKnowledgeCandidateId' limit 1),'') as primary_knowledge_label,custom_fields->>'officialExamPointSummary' as official_exam_point_summary,coalesce(custom_fields->'abilityDimensions','[]'::jsonb) as ability_dimensions from question_items where custom_fields->>'sourceWorkflowKey'=%s order by year,question_number""", (workflow_key,)).fetchall()
            sources = conn.execute("""select sd.year,sd.source_type,sd.id::text source_document_id,sd.file_asset_id::text file_asset_id,sd.source_title from source_documents sd where sd.material_batch_key=%s and sd.year between 2015 and 2025 and sd.source_type in ('local_exam_paper','answer_or_solution','exam_analysis_report')""", (batch_key,)).fetchall()
            blocks = conn.execute("""select qb.question_item_id::text,qb.id::text question_block_id,qb.block_type,qb.content,qb.source_region_id::text,sr.source_document_id::text,sr.page_number,sr.region_type,sd.source_type from question_blocks qb join question_items qi on qi.id=qb.question_item_id join source_regions sr on sr.id=qb.source_region_id join source_documents sd on sd.id=sr.source_document_id where qi.custom_fields->>'sourceWorkflowKey'=%s""", (workflow_key,)).fetchall()
    return {"questions": list(map(dict, questions)), "sources": list(map(dict, sources)), "blocks": list(map(dict, blocks))}


def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument('--role-map',type=Path,required=True); p.add_argument('--connection-string',required=True); p.add_argument('--output',type=Path,required=True); p.add_argument('--report',type=Path,required=True); a=p.parse_args()
    role_map=json.loads(a.role_map.read_text(encoding='utf-8'))
    result=build_index(
        load_snapshot(a.connection_string, role_map['materialBatchKey'], role_map['questionWorkflowKey']),
        role_map,
    )
    content=json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n'; a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(content,encoding='utf-8')
    a.report.parent.mkdir(parents=True, exist_ok=True)
    report={"schemaVersion":"cek012-guangzhou-exam-evidence-index-report.v1","status":"pass" if not result['blockers'] else "blocked","checkedAt":datetime.now(timezone.utc).isoformat(),"taskId":"CEK-12","questions":len(result['questions']),"blockers":result['blockers'],"readiness":result['readiness'],"reviewItemCount":len(result['reviewItems']),"manifestSha256":hashlib.sha256(content.encode()).hexdigest(),"databaseWrite":False,"activeWrite":False,"completionBoundary":"The 2015-2025 question corpus is a candidate-only prerequisite. Assessment-target extraction may proceed only when questionCorpusReady=true; report-derived fields additionally require reportEvidenceReady=true. REAL005 remains not_closed."}
    a.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return 0 if report["status"] == "pass" else 1

if __name__ == '__main__': raise SystemExit(main())
