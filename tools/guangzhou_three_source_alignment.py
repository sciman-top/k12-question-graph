from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


def _regime_for(year: int, regimes: Mapping[str, Any]) -> Mapping[str, Any]:
    matches = [row for row in regimes["regimes"] if int(row["fromYear"]) <= year <= int(row["toYear"])]
    if len(matches) != 1:
        raise ValueError(f"curriculum_regime_count:{year}:{len(matches)}")
    return matches[0]


def build_alignment(
    evidence_index: Mapping[str, Any],
    crosswalk: Mapping[str, Any],
    regimes: Mapping[str, Any],
) -> dict[str, Any]:
    mappings_by_knowledge: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for mapping in crosswalk["mappings"]:
        mappings_by_knowledge[str(mapping["target_knowledge_code"])].append(mapping)

    bundles: list[dict[str, Any]] = []
    alignments: list[dict[str, Any]] = []
    review_items: list[dict[str, Any]] = []
    conflicts: list[dict[str, Any]] = []
    for question in evidence_index["questions"]:
        year = int(question["year"])
        regime = _regime_for(year, regimes)
        candidate_fields = question.get("candidates", {})
        knowledge_ids = list(candidate_fields.get("knowledgeCandidateIds") or [])
        primary_id = candidate_fields.get("primaryKnowledgeCandidateId")
        if primary_id:
            knowledge_ids.insert(0, primary_id)
        knowledge_ids = list(dict.fromkeys(value for value in knowledge_ids if value))
        matched = [mapping for knowledge_id in knowledge_ids for mapping in mappings_by_knowledge.get(knowledge_id, [])]

        report_anchors = question["anchors"].get("report", [])
        report_document = question["sourceDocuments"].get("report")
        question_conflicts: list[str] = []
        if not report_anchors:
            question_conflicts.append("report_question_anchor_missing")
        if not matched:
            question_conflicts.append("curriculum_mapping_candidate_missing")
        for reason in question_conflicts:
            conflicts.append({
                "questionItemId": question["questionItemId"],
                "year": year,
                "questionNumber": question["questionNumber"],
                "reason": reason,
                "resolutionStatus": "pending_review",
            })

        question_alignment_ids: list[str] = []
        seen_mapping_keys: set[tuple[str, str]] = set()
        for mapping in matched:
            mapping_key = (str(mapping["source_stable_id"]), str(mapping["target_knowledge_code"]))
            if mapping_key in seen_mapping_keys:
                continue
            seen_mapping_keys.add(mapping_key)
            alignment_id = "CAL-CEK13-" + hashlib.sha256(
                f"{question['questionItemId']}|{mapping_key[0]}|{mapping_key[1]}|{regime['allowedAlignmentType']}".encode()
            ).hexdigest()[:16].upper()
            question_alignment_ids.append(alignment_id)
            alignment = {
                "alignmentId": alignment_id,
                "questionItemId": question["questionItemId"],
                "questionNumber": question["questionNumber"],
                "examYear": year,
                "curriculumRequirementStableId": mapping["parent_requirement_stable_id"],
                "requirementFacetStableId": mapping["source_stable_id"],
                "knowledgeCandidateId": mapping["target_knowledge_code"],
                "alignmentType": regime["allowedAlignmentType"],
                "standardVersion": regime["standardVersion"],
                "originalBasis": False,
                "confidence": min(float(mapping["confidence"]), 0.8),
                "evidence": {
                    "paperAnchors": question["anchors"]["paper"],
                    "answerAnchors": question["anchors"]["answer"],
                    "reportAnchors": report_anchors,
                    "reportDocument": report_document,
                    "curriculumAnchorSha256": mapping["evidence_anchor_sha256"],
                },
                "generationMethod": "deterministic_knowledge_crosswalk",
                "status": "candidate",
                "reviewStatus": "pending_review",
                "productionEligible": False,
            }
            alignments.append(alignment)
            review_items.append({
                "alignmentId": alignment_id,
                "questionItemId": question["questionItemId"],
                "priority": "high" if question_conflicts or len(matched) > 1 else "normal",
                "reasons": list(dict.fromkeys(["candidate_only", *question_conflicts, *(mapping.get("review_reasons") or [])])),
                "status": "pending_review",
            })
        bundles.append({
            "questionItemId": question["questionItemId"],
            "year": year,
            "questionNumber": question["questionNumber"],
            "paperAnchors": question["anchors"]["paper"],
            "answerAnchors": question["anchors"]["answer"],
            "reportAnchors": report_anchors,
            "reportDocument": report_document,
            "curriculumRegime": dict(regime),
            "alignmentCandidateIds": question_alignment_ids,
            "conflictReasons": question_conflicts,
            "questionFacts": dict(candidate_fields),
        })

    return {
        "schemaVersion": "cek013-guangzhou-three-source-alignment.v1",
        "bundles": bundles,
        "alignmentCandidates": alignments,
        "conflicts": conflicts,
        "reviewItems": review_items,
        "invariants": {
            "sourceCitedRequiresExplicitReportAnchor": not any(
                row["alignmentType"] == "source_cited" and not row["evidence"]["reportAnchors"]
                for row in alignments
            ),
            "allOriginalBasisFalse": all(not row["originalBasis"] for row in alignments),
            "allCandidatesPendingReview": all(
                row["status"] == "candidate"
                and row["reviewStatus"] == "pending_review"
                and not row["productionEligible"]
                for row in alignments
            ),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-index", type=Path, required=True)
    parser.add_argument("--crosswalk", type=Path, required=True)
    parser.add_argument("--regimes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    index = json.loads(args.evidence_index.read_text(encoding="utf-8"))
    crosswalk = json.loads(args.crosswalk.read_text(encoding="utf-8"))
    regimes = json.loads(args.regimes.read_text(encoding="utf-8"))
    result = build_alignment(index, crosswalk, regimes)
    content = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    alignment_types: dict[str, int] = defaultdict(int)
    for row in result["alignmentCandidates"]:
        alignment_types[row["alignmentType"]] += 1
    report = {
        "schemaVersion": "cek013-guangzhou-three-source-alignment-report.v1",
        "status": "pass" if all(result["invariants"].values()) else "blocked",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "taskId": "CEK-13",
        "bundles": len(result["bundles"]),
        "alignmentCandidates": len(result["alignmentCandidates"]),
        "alignmentTypes": dict(alignment_types),
        "conflicts": len(result["conflicts"]),
        "reviewItems": len(result["reviewItems"]),
        "manifestSha256": hashlib.sha256(content.encode()).hexdigest(),
        "databaseWrite": False,
        "activeWrite": False,
        "completionBoundary": "Candidate alignment only; historical source gaps and all conflicts remain pending review. REAL005 remains not_closed.",
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
