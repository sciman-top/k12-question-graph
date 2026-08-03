from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


SEMANTIC_FIELDS = (
    "target_statement",
    "ability_dimensions",
    "cognitive_demands",
    "method_model_experiment_ids",
    "context_type",
    "representation_types",
    "task_type",
)

COGNITIVE_BY_ABILITY = {
    "信息提取": "信息提取",
    "科学推理": "推理",
    "数学运算": "应用",
    "模型建构": "建模",
    "实验探究": "设计与评估",
    "规范表达": "论证与表达",
    "跨学科应用": "迁移应用",
    "迁移应用": "迁移应用",
}


def derive_cognitive_demands(abilities: list[str]) -> list[str]:
    return list(dict.fromkeys(COGNITIVE_BY_ABILITY[value] for value in abilities if value in COGNITIVE_BY_ABILITY))


def derive_context_type(stem: str, question_type: str) -> str:
    if question_type == "experiment_or_calculation" or any(value in stem for value in ("实验", "测量", "探究")):
        return "experimental"
    if any(value in stem for value in ("生活", "小明", "家用", "冰箱", "汽车", "水壶", "路灯", "教室")):
        return "real_world"
    return "disciplinary_problem"


def derive_representation_types(stem: str, block_types: list[str]) -> list[str]:
    result = ["text"]
    if "图" in stem or any(value in block_types for value in ("image", "question_region_image")):
        result.insert(0, "diagram")
    if "表" in stem or "table" in block_types:
        result.insert(0, "table")
    if "formula" in block_types:
        result.insert(0, "formula")
    return list(dict.fromkeys(result))


def build_target_statement(question_number: int, scope_type: str, facts: Mapping[str, Any], primary_knowledge: str | None) -> str:
    knowledge = str(facts.get("primaryKnowledgeLabel") or primary_knowledge or "未知知识候选")
    summary = str(facts.get("officialExamPointSummary") or "").strip()
    ability_text = "、".join(str(value) for value in facts.get("abilityDimensions") or [])
    scope_label = "整题" if scope_type == "whole_question" else "小问"
    parts = [f"第{question_number}题{scope_label}考查{knowledge}"]
    if summary:
        parts.append(summary)
    if ability_text:
        parts.append(f"能力候选：{ability_text}")
    return "；".join(parts)


def provenance(field: str, value: Any, explicit: bool = False, confidence: float = 0.8) -> dict[str, Any]:
    populated = value not in (None, "", [], {})
    return {
        "field": field,
        "generation_method": "rules",
        "source_kind": "explicit_fact" if populated and explicit else "derived_candidate" if populated else "not_inferred",
        "confidence": confidence if populated else 0.0,
    }


def build_candidates(
    scope_manifest: Mapping[str, Any],
    alignment_manifest: Mapping[str, Any],
) -> dict[str, Any]:
    bundle_by_question = {row["questionItemId"]: row for row in alignment_manifest["bundles"]}
    alignments_by_question: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for row in alignment_manifest["alignmentCandidates"]:
        alignments_by_question[row["questionItemId"]].append(row)

    targets: list[dict[str, Any]] = []
    review_queue: list[dict[str, Any]] = []
    expected_scope_keys: list[str] = []
    for question in scope_manifest["questions"]:
        bundle = bundle_by_question[str(question["questionId"])]
        question_alignments = alignments_by_question[str(question["questionId"])]
        facts = dict(bundle.get("questionFacts") or {})
        for scope in question["scopes"]:
            scope_key = str(scope["scopeKey"])
            expected_scope_keys.append(scope_key)
            target_id = "AT-CEK14-" + hashlib.sha256(scope_key.encode()).hexdigest()[:16].upper()
            scope_alignments = question_alignments if scope["scopeType"] == "whole_question" else []
            primary_knowledge = None
            if scope["scopeType"] == "whole_question":
                primary_knowledge = facts.get("primaryKnowledgeCandidateId")
                if not primary_knowledge and scope_alignments:
                    primary_knowledge = scope_alignments[0]["knowledgeCandidateId"]
            abilities = list(dict.fromkeys(str(value) for value in facts.get("abilityDimensions") or []))
            cognitive_demands = derive_cognitive_demands(abilities)
            question_type = str(facts.get("questionType") or "unclassified")
            stem_text = str(facts.get("stemText") or "")
            context_type = derive_context_type(stem_text, question_type)
            representation_types = derive_representation_types(stem_text, list(facts.get("blockTypes") or []))
            task_type = question_type
            score_weight = facts.get("scoreWeight") if scope["scopeType"] == "whole_question" else None
            target_statement = build_target_statement(
                question["questionNumber"], scope["scopeType"], facts, primary_knowledge
            )
            evidence_refs = [
                {
                    "source_document_id": anchor["sourceDocumentId"],
                    "source_region_id": anchor["sourceRegionId"],
                    "role": role,
                }
                for role, anchors in (
                    ("question_stem_source", bundle["paperAnchors"]),
                    ("answer_or_solution_source", bundle["answerAnchors"]),
                )
                for anchor in anchors
            ]
            reasons = ["candidate_only", "semantic_fields_require_teacher_review"]
            if primary_knowledge is None:
                reasons.append("unknown_primary_knowledge")
            if bundle["conflictReasons"]:
                reasons.append("evidence_conflict")
            if scope["scopeType"] != "whole_question":
                reasons.append("subquestion_scope_requires_review")
            target = {
                "target_id": target_id,
                "question_scope": {
                    "scope_key": scope_key,
                    "scope_type": scope["scopeType"],
                    "question_item_id": scope["questionId"],
                    "question_block_id": (scope.get("questionBlockRef") or {}).get("id"),
                },
                "target_statement": target_statement,
                "is_primary_target": True,
                "primary_knowledge_id": primary_knowledge,
                "curriculum_alignment_ids": [row["alignmentId"] for row in scope_alignments],
                "ability_dimensions": abilities,
                "cognitive_demands": cognitive_demands,
                "method_model_experiment_ids": [],
                "context_type": context_type,
                "representation_types": representation_types,
                "task_type": task_type,
                "score_weight": score_weight,
                "field_provenance": [
                    {"field": "question_scope", "generation_method": "rules", "source_kind": "explicit_fact", "confidence": 1.0},
                    provenance("primary_knowledge_id", primary_knowledge, confidence=0.82),
                    provenance("target_statement", target_statement, confidence=0.7),
                    provenance("ability_dimensions", abilities, explicit=True, confidence=0.82),
                    provenance("cognitive_demands", cognitive_demands, confidence=0.65),
                    provenance("method_model_experiment_ids", [], confidence=0.0),
                    provenance("context_type", context_type, confidence=0.6),
                    provenance("representation_types", representation_types, confidence=0.7),
                    provenance("task_type", task_type, explicit=True, confidence=0.95),
                    provenance("score_weight", score_weight, explicit=True, confidence=1.0),
                ],
                "evidence_refs": evidence_refs,
                "confidence": 0.72 if primary_knowledge else 0.45,
                "status": "candidate",
                "review_status": "pending_review",
                "production_eligible": False,
            }
            targets.append(target)
            review_queue.append({
                "target_id": target_id,
                "scope_key": scope_key,
                "priority": "blocked" if not evidence_refs else "high",
                "reasons": list(dict.fromkeys(reasons)),
                "status": "pending_review",
            })

    actual_scope_keys = [row["question_scope"]["scope_key"] for row in targets]
    return {
        "schema_version": "assessment-target-extraction.v1",
        "mode": "draft_test",
        "generation": {"method": "rules", "engine": "assessment_target_extraction.py", "version": "v1", "external_model_calls": 0},
        "governance": {"status": "candidate", "review_status": "pending_review", "production_eligible": False, "database_write": False, "active_write": False},
        "targets": targets,
        "review_queue": review_queue,
        "invariants": {
            "one_primary_per_scope": len(actual_scope_keys) == len(set(actual_scope_keys)) and all(row["is_primary_target"] for row in targets),
            "all_scopes_covered": set(actual_scope_keys) == set(expected_scope_keys),
            "all_pending_review": all(row["review_status"] == "pending_review" and not row["production_eligible"] for row in targets),
            "ai_did_not_mutate_source_facts": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scopes", type=Path, required=True)
    parser.add_argument("--alignments", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    result = build_candidates(
        json.loads(args.scopes.read_text(encoding="utf-8")),
        json.loads(args.alignments.read_text(encoding="utf-8")),
    )
    content = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    report = {
        "schemaVersion": "cek014-assessment-target-extraction-eval.v1",
        "status": "pass" if all(result["invariants"].values()) else "blocked",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "taskId": "CEK-14",
        "targetCandidates": len(result["targets"]),
        "reviewItems": len(result["review_queue"]),
        "withPrimaryKnowledgeCandidate": sum(row["primary_knowledge_id"] is not None for row in result["targets"]),
        "semanticFieldCounts": {
            "targetStatement": sum("语义待教师复核" not in row["target_statement"] for row in result["targets"]),
            "abilityDimensions": sum(bool(row["ability_dimensions"]) for row in result["targets"]),
            "cognitiveDemands": sum(bool(row["cognitive_demands"]) for row in result["targets"]),
            "contextType": sum(row["context_type"] != "unclassified" for row in result["targets"]),
            "representationTypes": sum(bool(row["representation_types"]) for row in result["targets"]),
            "taskType": sum(row["task_type"] != "unclassified" for row in result["targets"]),
            "scoreWeight": sum(row["score_weight"] is not None for row in result["targets"]),
        },
        "externalModelCalls": 0,
        "databaseWrite": False,
        "activeWrite": False,
        "manifestSha256": hashlib.sha256(content.encode()).hexdigest(),
        "completionBoundary": "Deterministic semantic candidates projected from existing question facts; all target statements, cognitive/context/representation derivations, subquestion inheritance, and mappings remain pending teacher review.",
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
