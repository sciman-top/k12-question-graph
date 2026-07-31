from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping


ZERO_UUID = "00000000-0000-0000-0000-000000000000"


class RegionalExamProfileAggregationError(RuntimeError):
    pass


def normalize_config(value: Mapping[str, Any]) -> dict[str, Any]:
    if "yearly_exam_facts" not in value:
        return dict(value)
    facts = [dict(row) for row in value.get("yearly_exam_facts", [])]
    if not facts:
        raise RegionalExamProfileAggregationError("yearly exam facts required")
    windows = [dict(row) for row in value.get("windows", [])]
    if len(windows) != 2:
        raise RegionalExamProfileAggregationError("full and recent windows required")
    full = max(windows, key=lambda row: len(row.get("exam_years", [])))
    recent = min(windows, key=lambda row: len(row.get("exam_years", [])))
    rules = dict(value.get("rules", {}))
    regime_ids = sorted({str(row["standard_version"]) for row in facts})
    standard_regimes = {
        regime_id: {
            "standardVersions": [regime_id],
            "interpretationGuard": (
                "Retrospective crosswalk only; do not claim this was the original exam-setting basis."
                if regime_id == "unverified_historical_or_pre_revision_standard"
                else "Contemporaneous inference still requires teacher review and is not original-basis evidence."
            ),
        }
        for regime_id in regime_ids
    }
    return {
        "region": value["region"],
        "subject": value["subject"],
        "stage": value["stage"],
        "materialBatchKey": value.get("material_batch_key"),
        "expectedQuestionCount": sum(int(row["question_count"]) for row in facts),
        "expectedQuestionCountsByYear": {str(row["year"]): int(row["question_count"]) for row in facts},
        "windows": {
            "full": {"id": full["window_id"], "years": list(full["exam_years"])},
            "recentComparable": {
                "id": recent["window_id"],
                "years": list(recent["exam_years"]),
                "maximumYears": len(recent["exam_years"]),
                "minimumYears": int(rules.get("minimum_comparable_years_for_trend", 3)),
            },
        },
        "papers": [
            {
                "year": int(row["year"]),
                "totalScore": float(row["total_exam_score"]),
                "scoreRegime": f"physics_{row['total_exam_score']}",
                "standardRegime": str(row["standard_version"]),
                "fileName": row["paper_file_name"],
                "sha256": row["paper_sha256"],
                "sourceDocumentId": row["paper_source_document_id"],
                "scoreProof": row["score_basis"],
                "scoreLiteral": row["score_literal"],
                "scoreEvidence": {
                    "sourceDocumentId": row["paper_source_document_id"],
                    "pdfPageNumbers": list(row.get("paper_pdf_page_numbers", [])),
                    "sourceLiteral": row["score_literal"],
                    "basis": row["score_basis"],
                },
            }
            for row in facts
        ],
        "standardRegimes": standard_regimes,
        "difficultyBuckets": [
            {
                "label": row["label"],
                "minimumInclusive": row["minimum_inclusive"],
                "maximumExclusive": row["maximum_exclusive"],
                "includeMaximum": row.get("include_maximum", False),
            }
            for row in value.get("difficulty_buckets", [])
        ],
        "trend": {
            "minimumComparableYears": int(rules.get("minimum_comparable_years_for_trend", 3)),
            "slopeThreshold": float(rules.get("trend_slope_threshold", 0.15)),
        },
        "rules": {
            "requireCompleteScoreNumerator": bool(rules.get("require_complete_score_numerator", True)),
            "requireObservedDifficulty": bool(rules.get("require_observed_difficulty", True)),
            "requirePaperAnswerReportAnchors": bool(rules.get("require_paper_answer_report_anchors", True)),
        },
    }


def _json_object(value: Any, field: str) -> dict[str, Any]:
    if value is None or value == "":
        return {}
    if isinstance(value, Mapping):
        return dict(value)
    try:
        parsed = json.loads(value)
    except (TypeError, json.JSONDecodeError) as exc:
        raise RegionalExamProfileAggregationError(f"invalid json field:{field}") from exc
    if not isinstance(parsed, dict):
        raise RegionalExamProfileAggregationError(f"json object required:{field}")
    return parsed


def _json_value(value: Any) -> Any:
    if value is None or value == "":
        return None
    if isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return None


def _candidate_only(row: Mapping[str, Any], metadata: Mapping[str, Any]) -> bool:
    return (
        row.get("status") == "candidate"
        and row.get("reviewStatus") == "pending_review"
        and row.get("productionEligible") is False
        and metadata.get("candidateOnly") is True
    )


def source_state(row: Mapping[str, Any], metadata: Mapping[str, Any]) -> str | None:
    if _candidate_only(row, metadata):
        return "explicit_candidate"
    if (
        row.get("reviewStatus") == "approved"
        and row.get("status") in {"candidate", "reviewed"}
        and row.get("productionEligible") is False
    ):
        return "reviewed"
    return None


def _fetch_json(url: str) -> dict[str, Any]:
    with urllib.request.urlopen(url, timeout=30) as response:  # noqa: S310 - local URL is caller-controlled
        value = json.loads(response.read().decode("utf-8"))
    if not isinstance(value, dict):
        raise RegionalExamProfileAggregationError(f"API object required:{url}")
    return value


def load_live_inputs(api_base_url: str, workers: int = 12) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    base = api_base_url.rstrip("/")
    target_responses: list[dict[str, Any]] = []
    observed_responses: list[dict[str, Any]] = []
    for review_status in ("pending_review", "approved"):
        target_responses.append(_fetch_json(
            f"{base}/knowledge-evidence/assessment-targets?reviewStatus={review_status}&take=500"
        ))
        observed_responses.append(_fetch_json(
            f"{base}/knowledge-evidence/observed-exam-evidence?reviewStatus={review_status}&take=500"
        ))

    targets = [item for response in target_responses for item in response.get("items", [])]
    question_ids = sorted({str(item["questionItemId"]) for item in targets})
    with ThreadPoolExecutor(max_workers=workers) as executor:
        question_rows = executor.map(lambda item_id: _fetch_json(f"{base}/questions/{item_id}"), question_ids)
    questions = {str(row["id"]): row for row in question_rows}
    observed = {
        "performance": [row for response in observed_responses for row in response.get("performance", [])],
        "errors": [row for response in observed_responses for row in response.get("errors", [])],
        "teachingRecommendations": [
            row for response in observed_responses for row in response.get("teachingRecommendations", [])
        ],
    }
    return {"items": targets}, observed, questions


def _paper_index(config: Mapping[str, Any]) -> dict[int, dict[str, Any]]:
    rows = {int(row["year"]): dict(row) for row in config.get("papers", [])}
    full_years = [int(year) for year in config["windows"]["full"]["years"]]
    if sorted(rows) != sorted(full_years):
        raise RegionalExamProfileAggregationError("paper evidence must cover the full window exactly")
    for year, row in rows.items():
        if (
            int(row.get("questionCount", 0)) <= 0
            or float(row.get("totalScore", 0)) <= 0
            or len(str(row.get("sha256", ""))) != 64
            or not row.get("scoreRegime")
            or not row.get("standardRegime")
        ):
            raise RegionalExamProfileAggregationError(f"invalid paper evidence:{year}")
        score_evidence = row.get("scoreEvidence")
        if not isinstance(score_evidence, Mapping) or (
            not score_evidence.get("sourceDocumentId")
            or not score_evidence.get("pdfPageNumbers")
            or not score_evidence.get("sourceLiteral")
            or not score_evidence.get("basis")
        ):
            raise RegionalExamProfileAggregationError(f"score evidence incomplete:{year}")
    return rows


def _comparability_key(paper: Mapping[str, Any]) -> tuple[str, str]:
    return str(paper["scoreRegime"]), str(paper["standardRegime"])


def select_recent_comparable_years(config: Mapping[str, Any]) -> list[int]:
    config = normalize_config(config)
    papers = _paper_index(config)
    policy = config["windows"]["recentComparable"]
    if policy.get("years"):
        return [int(year) for year in policy["years"]]
    cohorts: dict[tuple[str, str], list[int]] = defaultdict(list)
    for year, paper in papers.items():
        cohorts[_comparability_key(paper)].append(year)
    minimum = int(policy["minimumYears"])
    maximum = int(policy["maximumYears"])
    eligible = [sorted(years) for years in cohorts.values() if len(years) >= minimum]
    if not eligible:
        most_informative = max(
            (sorted(years) for years in cohorts.values()),
            key=lambda years: (len(years), years[-1]),
        )
        return most_informative[-maximum:]
    selected = max(eligible, key=lambda years: years[-1])
    return selected[-maximum:]


def _ordered_values(values: Iterable[str]) -> list[str]:
    counts = Counter(value for value in values if value)
    return [value for value, _ in sorted(counts.items(), key=lambda item: (-item[1], item[0]))]


def _target_knowledge_id(target: Mapping[str, Any], question: Mapping[str, Any]) -> str | None:
    custom = question.get("customFields") or {}
    stable_id = custom.get("primaryKnowledgeCandidateId")
    if stable_id:
        return str(stable_id)
    version_id = target.get("primaryKnowledgeAssetVersionId")
    return str(version_id) if version_id and str(version_id) != ZERO_UUID else None


def _anchor(role: str, source_region_id: Any, source_document_id: Any = None, **extra: Any) -> dict[str, Any] | None:
    if not source_region_id:
        return None
    result = {"role": role, "sourceRegionId": str(source_region_id)}
    if source_document_id:
        result["sourceDocumentId"] = str(source_document_id)
    result.update({key: value for key, value in extra.items() if value is not None})
    return result


def _target_anchors(target: Mapping[str, Any], question: Mapping[str, Any], metadata: Mapping[str, Any]) -> list[dict[str, Any]]:
    anchors: list[dict[str, Any]] = []
    for ref in metadata.get("evidenceRefs", []):
        role = str(ref.get("role", "target_source"))
        normalized = "paper" if role == "question_stem_source" else "answer" if role == "answer_or_solution_source" else role
        value = _anchor(normalized, ref.get("source_region_id"), ref.get("source_document_id"))
        if value:
            anchors.append(value)
    for block in question.get("blocks", []):
        if block.get("blockType") != "year_report_evidence":
            continue
        content = block.get("content") or {}
        value = _anchor(
            "report",
            block.get("sourceRegionId"),
            content.get("sourceDocumentId"),
            sourceDocumentSha256=content.get("sourceDocumentSha256"),
            pageNumber=content.get("pageNumber"),
        )
        if value:
            anchors.append(value)
    unique = {json.dumps(item, ensure_ascii=False, sort_keys=True): item for item in anchors}
    return list(unique.values())


def _observed_anchor(row: Mapping[str, Any]) -> list[dict[str, Any]]:
    evidence = _json_object(row.get("evidence"), "observed.evidence")
    values = evidence.get("anchors") or ([evidence["anchor"]] if evidence.get("anchor") else [])
    anchors = []
    for value in values:
        anchor = _anchor(
            "report",
            value.get("source_region_id") or value.get("sourceRegionId"),
            value.get("source_document_id") or value.get("sourceDocumentId"),
            pageNumber=value.get("pdf_page_number") or value.get("pageNumber"),
            textBlockSha256=value.get("text_block_sha256"),
        )
        if anchor:
            anchors.append(anchor)
    return anchors


def _trend_status(years: list[int], occurrence_years: set[int], config: Mapping[str, Any], comparable: bool) -> str:
    policy = config["trend"]
    minimum = int(policy["minimumComparableYears"])
    if not comparable or len(years) < minimum or len(occurrence_years) < minimum:
        return "insufficient_evidence"
    values = [1.0 if year in occurrence_years else 0.0 for year in years]
    mean_x = sum(years) / len(years)
    mean_y = sum(values) / len(values)
    denominator = sum((year - mean_x) ** 2 for year in years)
    slope = 0.0 if denominator == 0 else sum((year - mean_x) * (value - mean_y) for year, value in zip(years, values)) / denominator
    threshold = float(policy["slopeThreshold"])
    if slope > threshold:
        return "rising"
    if slope < -threshold:
        return "falling"
    return "stable"


def _difficulty_buckets(values: list[float], config: Mapping[str, Any]) -> list[dict[str, Any]]:
    result = []
    for bucket in config["difficultyBuckets"]:
        minimum = float(bucket["minimumInclusive"])
        maximum = float(bucket["maximumExclusive"])
        include_maximum = bool(bucket.get("includeMaximum", False))
        count = sum(minimum <= value <= maximum if include_maximum else minimum <= value < maximum for value in values)
        result.append({
            "label": str(bucket["label"]),
            "count": count,
            "minimum_inclusive": minimum,
            "maximum_exclusive": maximum,
        })
    if sum(row["count"] for row in result) != len(values):
        raise RegionalExamProfileAggregationError("difficulty value outside configured buckets")
    return result


def _profile_id(knowledge_id: str, state: str, window_id: str) -> str:
    digest = hashlib.sha256(f"{knowledge_id}|{state}|{window_id}".encode("utf-8")).hexdigest()[:16].upper()
    return f"EPHY-GUANGZHOU-{digest}"


def _standard_regime(years: list[int], papers: Mapping[int, Mapping[str, Any]], config: Mapping[str, Any]) -> dict[str, Any]:
    regime_ids = sorted({str(papers[year]["standardRegime"]) for year in years})
    versions: set[str] = set()
    guards = []
    for regime_id in regime_ids:
        regime = config["standardRegimes"][regime_id]
        versions.update(str(value) for value in regime["standardVersions"])
        guards.append(str(regime["interpretationGuard"]))
    return {
        "regime_id": "+".join(regime_ids),
        "regime_type": "single_standard" if len(regime_ids) == 1 else "transition",
        "standard_versions": sorted(versions),
        "exam_years": years,
        "interpretation_guard": " ".join(guards),
    }


def aggregate_profiles(
    targets_response: Mapping[str, Any],
    observed_response: Mapping[str, Any],
    questions: Mapping[str, Mapping[str, Any]],
    config: Mapping[str, Any],
) -> dict[str, Any]:
    config = normalize_config(config)
    papers = _paper_index(config)
    full_years = [int(year) for year in config["windows"]["full"]["years"]]
    recent_years = select_recent_comparable_years(config)
    recent_window_id = str(config["windows"]["recentComparable"].get("id", "recent_comparable"))
    windows = ((str(config["windows"]["full"]["id"]), full_years), (recent_window_id, recent_years))

    rejected_targets: list[dict[str, str]] = []
    target_rows: list[dict[str, Any]] = []
    for target in targets_response.get("items", []):
        metadata = _json_object(target.get("metadata"), "target.metadata")
        state = source_state(target, metadata)
        question_id = str(target.get("questionItemId", ""))
        question = questions.get(question_id)
        if state is None:
            rejected_targets.append({"targetId": str(target.get("id")), "reason": "state_not_accepted"})
            continue
        if question is None:
            rejected_targets.append({"targetId": str(target.get("id")), "reason": "question_missing"})
            continue
        if target.get("scopeType") != "whole_question":
            rejected_targets.append({"targetId": str(target.get("id")), "reason": "non_whole_question_scope"})
            continue
        custom_fields = question.get("customFields") or {}
        if (
            (config.get("materialBatchKey") and custom_fields.get("materialBatchKey") != config.get("materialBatchKey"))
            or (question.get("subject") and question.get("subject") != config.get("subject"))
            or (question.get("stage") and question.get("stage") != config.get("stage"))
        ):
            rejected_targets.append({"targetId": str(target.get("id")), "reason": "question_outside_configured_corpus"})
            continue
        year = int(custom_fields.get("year", 0))
        knowledge_id = _target_knowledge_id(target, question)
        if year not in papers or not knowledge_id:
            rejected_targets.append({"targetId": str(target.get("id")), "reason": "year_or_primary_knowledge_missing"})
            continue
        target_rows.append({
            "target": target,
            "metadata": metadata,
            "question": question,
            "year": year,
            "state": state,
            "knowledgeId": knowledge_id,
            "anchors": _target_anchors(target, question, metadata),
        })

    target_by_id = {str(row["target"]["id"]): row for row in target_rows}
    observed_by_target: dict[str, list[dict[str, Any]]] = defaultdict(list)
    rejected_observed = 0
    for observed in observed_response.get("performance", []):
        evidence = _json_object(observed.get("evidence"), "observed.evidence")
        state = source_state(observed, evidence)
        target_id = str(observed.get("assessmentTargetId", ""))
        target_row = target_by_id.get(target_id)
        if state is None or target_row is None or state != target_row["state"]:
            rejected_observed += 1
            continue
        value = observed.get("difficultyObserved")
        if value is None:
            continue
        number = float(value)
        if observed.get("difficultyDirection") != "higher_is_easier" or not 0 <= number <= 1:
            rejected_observed += 1
            continue
        observed_by_target[target_id].append({"value": number, "anchors": _observed_anchor(observed)})

    question_knowledge: dict[str, set[str]] = defaultdict(set)
    for row in target_rows:
        question_id = str(row["target"]["questionItemId"])
        question_knowledge[question_id].add(str(row["knowledgeId"]))
        custom_fields = row["question"].get("customFields") or {}
        question_knowledge[question_id].update(str(value) for value in custom_fields.get("knowledgeCandidateIds", []) if value)

    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in target_rows:
        grouped[(str(row["knowledgeId"]), str(row["state"]))].append(row)

    profiles: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []
    for (knowledge_id, state), group_rows in sorted(grouped.items()):
        for window_id, years in windows:
            rows = [row for row in group_rows if row["year"] in years]
            if not rows:
                continue
            target_ids = sorted({str(row["target"]["id"]) for row in rows})
            occurrence_years = {int(row["year"]) for row in rows}
            score_rows = [row for row in rows if isinstance(row["metadata"].get("scoreWeight"), (int, float))]
            difficulty_pairs = [
                (row, evidence)
                for row in rows
                for evidence in observed_by_target.get(str(row["target"]["id"]), [])
            ]
            abilities = _ordered_values(value for row in rows for value in row["metadata"].get("abilityDimensions", []))
            cognitive = _ordered_values(value for row in rows for value in row["metadata"].get("cognitiveDemands", []))
            task_types = _ordered_values(str(row["metadata"].get("taskType", "")) for row in rows)
            context_types = _ordered_values(str(row["metadata"].get("contextType", "")) for row in rows)
            representations = _ordered_values(value for row in rows for value in row["metadata"].get("representationTypes", []))
            missing = []
            if not score_rows:
                missing.append("score_evidence")
            elif config.get("rules", {}).get("requireCompleteScoreNumerator", True) and len(score_rows) < len(rows):
                missing.append("incomplete_score_numerator")
            if not difficulty_pairs:
                missing.append("observed_difficulty")
            if not abilities or not cognitive or not task_types or not context_types or not representations:
                missing.append("dimension_metadata")
            if missing:
                blocked.append({
                    "knowledgeId": knowledge_id,
                    "sourceState": state,
                    "windowId": window_id,
                    "targetIds": target_ids,
                    "reasons": missing,
                })
                continue

            comparison_keys = {_comparability_key(papers[year]) for year in years}
            comparable = len(comparison_keys) == 1
            score_by_question: dict[str, float] = {}
            score_targets = []
            for row in score_rows:
                question_id = str(row["target"]["questionItemId"])
                score_by_question[question_id] = max(
                    score_by_question.get(question_id, 0.0), float(row["metadata"]["scoreWeight"])
                )
                score_targets.append(str(row["target"]["id"]))
            score_numerator = sum(score_by_question.values())
            score_denominator = sum(float(papers[year]["totalScore"]) for year in years)
            if score_numerator > score_denominator:
                blocked.append({
                    "knowledgeId": knowledge_id,
                    "sourceState": state,
                    "windowId": window_id,
                    "targetIds": target_ids,
                    "reasons": ["score_numerator_exceeds_denominator"],
                })
                continue

            difficulty_values = [pair[1]["value"] for pair in difficulty_pairs]
            difficulty_target_ids = sorted({str(pair[0]["target"]["id"]) for pair in difficulty_pairs})
            cooccurring = Counter()
            for row in rows:
                question_id = str(row["target"]["questionItemId"])
                for other in question_knowledge[question_id] - {knowledge_id}:
                    cooccurring[other] += 1
            knowledge_ids = [knowledge_id] + [key for key, _ in cooccurring.most_common(10)]

            anchors = [anchor for row in rows for anchor in row["anchors"]]
            anchors.extend(anchor for _, evidence in difficulty_pairs for anchor in evidence["anchors"])
            unique_anchors = {
                json.dumps(anchor, ensure_ascii=False, sort_keys=True): anchor for anchor in anchors
            }
            anchor_values = list(unique_anchors.values())
            anchor_roles = sorted({str(anchor["role"]) for anchor in anchor_values})
            if (
                config.get("rules", {}).get("requirePaperAnswerReportAnchors", True)
                and not {"paper", "answer", "report"}.issubset(anchor_roles)
            ):
                blocked.append({
                    "knowledgeId": knowledge_id,
                    "sourceState": state,
                    "windowId": window_id,
                    "targetIds": target_ids,
                    "reasons": ["paper_answer_report_traceability_incomplete"],
                })
                continue
            status_flags = []
            if not comparable:
                status_flags.append("multiple_score_or_standard_regimes")
            if len(score_rows) < len(rows):
                status_flags.append("partial_score_evidence")
            if len(difficulty_target_ids) < len(target_ids):
                status_flags.append("partial_observed_difficulty")
            trend = _trend_status(years, occurrence_years, config, comparable)
            profile = {
                "schema_version": "regional-exam-point-profile.v1",
                "semantic_type": "RegionalExamPointProfile",
                "storage_asset_type": "exam_point",
                "stable_id": _profile_id(knowledge_id, state, window_id),
                "region": str(config["region"]),
                "subject": str(config["subject"]),
                "stage": str(config["stage"]),
                "year_range": {
                    "start_year": min(years),
                    "end_year": max(years),
                    "comparable_exam_years": years,
                },
                "standard_regime": _standard_regime(years, papers, config),
                "knowledge_stable_ids": knowledge_ids,
                "curriculum_alignments": [],
                "ability_dimensions": abilities,
                "cognitive_dimensions": cognitive,
                "common_task_types": task_types,
                "common_context_types": context_types,
                "common_representation_types": representations,
                "frequency_weight": {
                    "numerator_occurrences": len(occurrence_years),
                    "denominator_comparable_exam_papers": len(years),
                    "value": round(len(occurrence_years) / len(years), 4),
                    "comparable_exam_years": years,
                    "evidence_target_ids": target_ids,
                },
                "score_weight": {
                    "numerator_profile_score": round(score_numerator, 4),
                    "denominator_total_exam_score": score_denominator,
                    "value": round(score_numerator / score_denominator, 4),
                    "comparable_exam_years": years,
                    "evidence_target_ids": sorted(set(score_targets)),
                },
                "difficulty_distribution": {
                    "direction": "higher_is_easier",
                    "denominator_observed_items": len(difficulty_values),
                    "buckets": _difficulty_buckets(difficulty_values, config),
                    "comparable_exam_years": sorted({int(pair[0]["year"]) for pair in difficulty_pairs}),
                    "evidence_target_ids": difficulty_target_ids,
                },
                "trend": {
                    "status": trend,
                    "minimum_comparable_years": int(config["trend"]["minimumComparableYears"]),
                    "comparable_exam_years": years,
                    "evidence_target_ids": target_ids,
                },
                "version": 1,
                "status": "candidate",
                "review_status": "pending_review",
                "production_eligible": False,
            }
            profiles.append({
                "profile": profile,
                "diagnostics": {
                    "windowId": window_id,
                    "sourceState": state,
                    "comparability": "comparable" if comparable else "degraded",
                    "statusFlags": status_flags,
                    "occurrenceYears": sorted(occurrence_years),
                    "scoreEvidenceCoverage": round(len(score_rows) / len(rows), 4),
                    "difficultyEvidenceCoverage": round(len(difficulty_target_ids) / len(target_ids), 4),
                    "cooccurrenceCounts": dict(sorted(cooccurring.items())),
                    "abilityDistribution": dict(sorted(Counter(
                        value for row in rows for value in row["metadata"].get("abilityDimensions", [])
                    ).items())),
                    "cognitiveDistribution": dict(sorted(Counter(
                        value for row in rows for value in row["metadata"].get("cognitiveDemands", [])
                    ).items())),
                    "taskTypeDistribution": dict(sorted(Counter(
                        str(row["metadata"].get("taskType", "")) for row in rows if row["metadata"].get("taskType")
                    ).items())),
                    "contextTypeDistribution": dict(sorted(Counter(
                        str(row["metadata"].get("contextType", "")) for row in rows if row["metadata"].get("contextType")
                    ).items())),
                    "representationTypeDistribution": dict(sorted(Counter(
                        value for row in rows for value in row["metadata"].get("representationTypes", [])
                    ).items())),
                },
                "traceability": {
                    "assessmentTargetIds": target_ids,
                    "questionItemIds": sorted({str(row["target"]["questionItemId"]) for row in rows}),
                    "anchorRoles": anchor_roles,
                    "anchors": anchor_values,
                },
            })

    state_profile_counts = Counter(item["diagnostics"]["sourceState"] for item in profiles)
    full_profiles = [item for item in profiles if item["diagnostics"]["windowId"] == config["windows"]["full"]["id"]]
    recent_profiles = [item for item in profiles if item["diagnostics"]["windowId"] == recent_window_id]
    traceable_profiles = sum(
        {"paper", "answer", "report"}.issubset(set(item["traceability"]["anchorRoles"])) for item in profiles
    )
    accepted_questions = {str(row["target"]["questionItemId"]): row["question"] for row in target_rows}
    question_counts = Counter(int((question.get("customFields") or {})["year"]) for question in accepted_questions.values())
    expected_counts = {
        int(year): int(count) for year, count in config.get("expectedQuestionCountsByYear", {}).items()
    }
    corpus_complete = len(accepted_questions) == int(config.get("expectedQuestionCount", len(accepted_questions)))
    if expected_counts:
        corpus_complete = corpus_complete and dict(sorted(question_counts.items())) == dict(sorted(expected_counts.items()))
    recent_comparable_complete = (
        len(recent_years) == int(config["windows"]["recentComparable"]["maximumYears"])
        and len({_comparability_key(papers[year]) for year in recent_years}) == 1
    )
    return {
        "schemaVersion": "cek022-regional-exam-profile-aggregation.v1",
        "status": "pass" if profiles and corpus_complete else "blocked",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "taskId": "CEK-22",
        "input": {
            "assessmentTargetsReturned": len(targets_response.get("items", [])),
            "acceptedAssessmentTargets": len(target_rows),
            "rejectedAssessmentTargets": len(rejected_targets),
            "questionsReturned": len(questions),
            "acceptedQuestions": len(accepted_questions),
            "questionCountsByYear": {str(year): count for year, count in sorted(question_counts.items())},
            "corpusComplete": corpus_complete,
            "observedPerformanceReturned": len(observed_response.get("performance", [])),
            "rejectedObservedPerformance": rejected_observed,
        },
        "windows": {
            "full": full_years,
            "recentComparable": recent_years,
            "recentComparableComplete": recent_comparable_complete,
        },
        "scoreRegimes": {
            str(year): {"totalScore": papers[year]["totalScore"], "scoreRegime": papers[year]["scoreRegime"], "paperSha256": papers[year]["sha256"]}
            for year in full_years
        },
        "paperEvidence": {
            "configuredPapers": len(papers),
            "allHashesRecorded": all(len(str(row.get("sha256", ""))) == 64 for row in papers.values()),
        },
        "aggregation": {
            "profileCandidates": len(profiles),
            "fullWindowProfiles": len(full_profiles),
            "recentComparableProfiles": len(recent_profiles),
            "blockedProfiles": len(blocked),
            "stateProfileCounts": dict(sorted(state_profile_counts.items())),
            "crossStateMixes": 0,
            "traceablePaperAnswerReportProfiles": traceable_profiles,
        },
        "profiles": profiles,
        "blocked": blocked,
        "rejectedTargets": rejected_targets,
        "governance": {
            "status": "candidate",
            "reviewStatus": "pending_review",
            "productionEligible": False,
            "databaseWrite": False,
            "activeWrite": False,
            "externalModelCalls": 0,
        },
        "referencesReviewed": [
            "configs/knowledge/curriculum-standard-regimes.json",
            "schemas/regional_exam_point_profile.schema.json",
            "local 2015-2025 Guangzhou physics paper score statements verified by PDF render/text extraction",
        ],
        "adoptionDecision": "Use deterministic, denominator-preserving aggregation and split states; downgrade cross score/standard regimes and sparse evidence instead of inferring comparability.",
        "rollback": "Delete the CEK-22 derived report/cache only; the aggregator performs no database or active asset write.",
        "completionBoundary": "CEK-22 produces read-only RegionalExamPointProfile candidates and diagnostics only; no profile is persisted, teacher-approved, production eligible, or active, and REAL005 remains not_closed.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--api-base-url", default="http://127.0.0.1:5275")
    parser.add_argument("--targets", type=Path)
    parser.add_argument("--observed", type=Path)
    parser.add_argument("--questions", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    if any((args.targets, args.observed, args.questions)):
        if not all((args.targets, args.observed, args.questions)):
            raise RegionalExamProfileAggregationError("fixture mode requires targets, observed, and questions")
        targets = json.loads(args.targets.read_text(encoding="utf-8"))
        observed = json.loads(args.observed.read_text(encoding="utf-8"))
        question_rows = json.loads(args.questions.read_text(encoding="utf-8"))
        questions = {str(row["id"]): row for row in question_rows}
    else:
        targets, observed, questions = load_live_inputs(args.api_base_url)
    report = aggregate_profiles(targets, observed, questions, config)
    if report["status"] != "pass":
        raise RegionalExamProfileAggregationError("no schema-capable profile candidates generated")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
