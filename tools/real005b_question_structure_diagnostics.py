from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_YEARS = list(range(2015, 2026))
REAL001_REPORT_GLOB = "docs/evidence/*-guangzhou-2015-real-ingest-slice-report.json"
REAL002_REPORT = "docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json"
REAL003_REPORT = "docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json"
REAL004_REPORT = "docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json"
REAL005B_SOURCE_REGION_SCREENSHOT_GLOB = "docs/evidence/*-real005b-source-region-screenshots.json"
REAL005B_STRUCTURED_QUESTION_GLOB = "docs/evidence/*-real005b-structured-question-diagnostics.json"
REAL003_SOURCE_MATERIAL_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-source-material.csv"
REAL003_QUESTION_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-question-item-full.csv"
REAL003_ANSWER_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-answer-scoring-point.csv"
REAL005B_QUALITY_QUESTION_CSV = (
    "guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package/c003-question-item-full.csv"
)
REAL005B_ASSET_MAPPING_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-asset-mapping.csv"
REAL005B_EXAM_POINT_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-exam-point-full.csv"
REAL005B_YEAR_OBSERVATION_CSV = (
    "guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package/c003-year-report-observation.csv"
)
REAL005B_QUALITY_REVIEW_EVIDENCE_CSV = (
    "guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package/c003-quality-issue-review-evidence.csv"
)
REAL005B_QUALITY_REVIEW_REGISTRY_CSV = (
    "guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package/c003-quality-issue-registry.csv"
)
REAL005B_TEACHING_SUGGESTION_CSV = "guangzhou-physics-full-research-package-2016-2025/csv/c003-teaching-suggestion.csv"
L004_TAGGING_PILOT_REPORT = "docs/evidence/20260505-l004-knowledge-tagging-suggestion-pilot.md"
S007A_SCHEMA_REPORT = "docs/evidence/20260506-s007a-ai-suggestion-schema-hardening-report.json"
S007B_QUEUE_REPORT = "docs/evidence/20260530-ns504-s007b-source-report.json"
S007C_CONFIRM_REPORT = "docs/evidence/20260530-ns504-s007c-source-report.json"
NS204_NO_ACTIVE_WRITE_REPORT = "docs/evidence/20260529-ns204-no-active-write-guard-report.json"
NS504_TAGGING_REVIEW_REPORT = "docs/evidence/20260530-ns504-ai-suggestion-review-report.json"
S006C_SOURCE_REVIEW_REPORT = "docs/evidence/20260506-s006c-source-review-closure-smoke-report.json"
REAL007_REPORT = "docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json"
REAL008_REPORT = "docs/evidence/20260518-real008-question-asset-smoke-report.json"
REAL009_REPORT = "docs/evidence/20260518-real009-table-structure-smoke-report.json"
REAL010_REPORT = "docs/evidence/20260518-real010-formula-fidelity-smoke-report.json"
REAL011_REPORT = "docs/evidence/20260518-real011-question-edit-smoke-report.json"
REAL005B_REVIEWED_VISIBILITY_GLOB = "docs/evidence/*-real005b-reviewed-question-visibility.json"
REAL005B_REVIEWED_SOURCE_SMOKE_GLOB = "docs/evidence/*-real005b-reviewed-question-source-smoke.json"


def read_json(repo_root: Path, relative_path: str) -> dict[str, Any]:
    return json.loads((repo_root / relative_path).read_text(encoding="utf-8"))


def find_latest_json(repo_root: Path, glob_pattern: str) -> str | None:
    matches = sorted(
        (repo_root / "docs/evidence").glob(Path(glob_pattern).name),
        key=lambda path: path.name,
        reverse=True,
    )
    if not matches:
        return None
    return str(matches[0].relative_to(repo_root)).replace("\\", "/")


def find_latest_json_with_status(repo_root: Path, glob_pattern: str, desired_status: str) -> str | None:
    matches = sorted(
        (repo_root / "docs/evidence").glob(Path(glob_pattern).name),
        key=lambda path: path.name,
        reverse=True,
    )
    for path in matches:
        relative_path = str(path.relative_to(repo_root)).replace("\\", "/")
        try:
            report = read_json(repo_root, relative_path)
        except Exception:
            continue
        if str(report.get("status") or "").strip() == desired_status:
            return relative_path
    return None


def require_latest_json(repo_root: Path, glob_pattern: str, label: str) -> str:
    latest = find_latest_json(repo_root, glob_pattern)
    if latest is None:
        raise FileNotFoundError(f"missing {label} matching {glob_pattern}")
    return latest


def read_csv(repo_root: Path, relative_path: str) -> list[dict[str, str]]:
    with (repo_root / relative_path).open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def question_numbers(rows: list[dict[str, Any]]) -> list[int]:
    values: list[int] = []
    for row in rows:
        value = row.get("questionNo", row.get("question_no"))
        if value is not None:
            values.append(int(value))
    return sorted(values)


def expected_range(expected_count: int) -> list[int]:
    return list(range(1, expected_count + 1))


def split_material_ids(raw_value: str | None) -> list[str]:
    if not raw_value:
        return []
    normalized = raw_value.replace("；", ";").replace(",", ";")
    return [part.strip() for part in normalized.split(";") if part.strip()]


def build_2015_rows(real001: dict[str, Any], real002: dict[str, Any]) -> list[dict[str, Any]]:
    first_batch = list(real001.get("appliedRows") or [])
    second_batch = list(real002.get("created") or [])
    return first_batch + second_batch


def build_year_source_hash_lookup(real003: dict[str, Any]) -> dict[int, dict[str, str]]:
    result: dict[int, dict[str, str]] = {}
    for year_item in real003.get("years") or []:
        year = int(year_item["year"])
        lookup: dict[str, str] = {}
        for source in year_item.get("sourceHashes") or []:
            sha = str(source.get("sha256") or "")
            if not sha:
                continue
            for key in (
                str(source.get("fileName") or "").strip(),
                str(source.get("title") or "").strip(),
            ):
                if key:
                    lookup[key] = sha
        result[year] = lookup
    return result


def group_rows_by_year(rows: list[dict[str, str]]) -> dict[int, list[dict[str, str]]]:
    grouped: dict[int, list[dict[str, str]]] = {}
    for row in rows:
        year_text = str(row.get("year") or "").strip()
        if not year_text.isdigit():
            continue
        year = int(year_text)
        if year not in REQUIRED_YEARS:
            continue
        grouped.setdefault(year, []).append(row)
    return grouped


def build_source_material_maps(
    source_material_rows: list[dict[str, str]],
) -> tuple[dict[str, dict[str, str]], dict[int, dict[str, dict[str, str]]]]:
    by_id: dict[str, dict[str, str]] = {}
    by_year: dict[int, dict[str, dict[str, str]]] = {}
    for row in source_material_rows:
        source_material_id = str(row.get("source_material_id") or "").strip()
        year_text = str(row.get("year") or "").strip()
        if not source_material_id or not year_text.isdigit():
            continue
        year = int(year_text)
        by_id[source_material_id] = row
        by_year.setdefault(year, {})[source_material_id] = row
    return by_id, by_year


def has_bound_source_hash(
    question_no: int,
    question_rows_by_number: dict[int, list[dict[str, str]]],
    answer_rows_by_number: dict[int, list[dict[str, str]]],
    source_material_by_id: dict[str, dict[str, str]],
    year_hash_lookup: dict[str, str],
) -> bool:
    def row_binds_to_hash(row: dict[str, str], field_names: tuple[str, ...]) -> bool:
        material_ids: list[str] = []
        for field_name in field_names:
            material_ids.extend(split_material_ids(row.get(field_name)))
        for material_id in material_ids:
            source_material = source_material_by_id.get(material_id)
            if not source_material:
                continue
            source_file = str(source_material.get("source_file") or "").strip()
            if source_file and source_file in year_hash_lookup:
                return True
        source_file = str(row.get("source_file") or "").strip()
        return bool(source_file and source_file in year_hash_lookup)

    for row in question_rows_by_number.get(question_no, []):
        if row_binds_to_hash(row, ("answer_source_id",)):
            return True
    for row in answer_rows_by_number.get(question_no, []):
        if row_binds_to_hash(row, ("source_material_ids",)):
            return True
    return False


def has_per_question_answer_anchor(
    question_no: int,
    question_rows_by_number: dict[int, list[dict[str, str]]],
    answer_rows_by_number: dict[int, list[dict[str, str]]],
    source_material_by_id: dict[str, dict[str, str]],
    year_hash_lookup: dict[str, str],
) -> bool:
    def row_has_anchor(row: dict[str, str], field_names: tuple[str, ...]) -> bool:
        material_ids: list[str] = []
        for field_name in field_names:
            material_ids.extend(split_material_ids(row.get(field_name)))
        has_material_anchor = any(material_id in source_material_by_id for material_id in material_ids)
        has_source_file = bool(str(row.get("source_file") or "").strip())
        has_evidence_location = bool(str(row.get("evidence_locations") or "").strip())
        if has_material_anchor and has_source_file and has_evidence_location:
            return True
        page_or_location = str(row.get("page_or_location") or "").strip()
        if has_source_file and page_or_location and has_material_anchor:
            return True
        source_file = str(row.get("source_file") or "").strip()
        return bool(source_file and source_file in year_hash_lookup and (has_evidence_location or page_or_location))

    for row in question_rows_by_number.get(question_no, []):
        if row_has_anchor(row, ("answer_source_id",)):
            return True
    for row in answer_rows_by_number.get(question_no, []):
        if row_has_anchor(row, ("source_material_ids",)):
            return True
    return False


def visual_region_coverage_2015(real002: dict[str, Any], real007: dict[str, Any]) -> dict[str, Any]:
    visual_rows = list(real002.get("created") or [])
    question_numbers = sorted({int(row.get("questionNo") or 0) for row in visual_rows if str(row.get("questionNo") or "").isdigit()})
    asset_question_numbers = sorted({int(row.get("questionNo") or 0) for row in visual_rows if row.get("hasQuestionAsset")})
    screenshot_pending_question_numbers = sorted(
        {
            int(row.get("questionNo") or 0)
            for row in visual_rows
            if str(row.get("questionNo") or "").isdigit() and str(row.get("answerRegionId") or "").strip()
        }
    )
    placeholder_like_question_numbers = sorted(
        {
            int(row.get("questionNo") or 0)
            for row in visual_rows
            if not row.get("hasQuestionAsset") and int(row.get("questionNo") or 0) in {19}
        }
    )
    source_region_ids = sorted(
        {str(row.get("questionRegionId") or "") for row in visual_rows if str(row.get("questionRegionId") or "").strip()}
    )
    layout_quality_pass = bool(real007.get("status") == "pass" and int(real007.get("placeholderLikeScreenshotCount") or 0) == 0)
    return {
        "questionNumbers": question_numbers,
        "assetQuestionNumbers": asset_question_numbers,
        "screenshotPendingQuestionNumbers": screenshot_pending_question_numbers,
        "placeholderLikeQuestionNumbers": placeholder_like_question_numbers,
        "sourceRegionIds": source_region_ids,
        "layoutQualityPass": layout_quality_pass,
    }


def source_region_coverage_2016_2025(repo_root: Path) -> dict[str, Any]:
    latest_report_path = find_latest_json(repo_root, REAL005B_SOURCE_REGION_SCREENSHOT_GLOB)
    if latest_report_path is None:
        return {
            "status": "blocked",
            "evidencePaths": [],
            "blockers": ["2016_2025_source_region_screenshot_report_missing"],
            "coveredYears": [],
            "blockedYears": list(range(2016, 2026)),
            "sourceRegionCoveragePass": False,
            "visualQuestionCount": 0,
            "renderedPages": 0,
        }

    report = read_json(repo_root, latest_report_path)
    years = report.get("years") or []
    blocked_years = [int(year.get("year")) for year in years if year.get("status") != "pass"]
    return {
        "status": "pass" if report.get("status") == "pass" and not blocked_years else "partial",
        "evidencePaths": [latest_report_path],
        "blockers": sorted({blocker for year in years for blocker in (year.get("blockers") or [])}),
        "coveredYears": [int(year.get("year")) for year in years if year.get("status") == "pass"],
        "blockedYears": blocked_years,
        "sourceRegionCoveragePass": bool(report.get("sourceRegionCoveragePass")),
        "visualQuestionCount": int((report.get("totals") or {}).get("visualQuestions") or 0),
        "renderedPages": int((report.get("totals") or {}).get("renderedPages") or 0),
    }


def structured_question_coverage_2016_2025(repo_root: Path) -> dict[str, Any]:
    latest_report_path = find_latest_json(repo_root, REAL005B_STRUCTURED_QUESTION_GLOB)
    if latest_report_path is None:
        return {
            "status": "blocked",
            "evidencePaths": [],
            "blockers": ["2016_2025_structured_question_report_missing"],
            "coveredYears": [],
            "blockedYears": list(range(2016, 2026)),
            "structuredQuestionCoveragePass": False,
            "questionCount": 0,
            "subquestionCount": 0,
            "answerCount": 0,
            "qualityReviewRows": 0,
        }

    report = read_json(repo_root, latest_report_path)
    years = report.get("years") or []
    blocked_years = [int(year.get("year")) for year in years if year.get("status") != "pass"]
    return {
        "status": "pass" if report.get("status") == "pass" and not blocked_years else "partial",
        "evidencePaths": [latest_report_path],
        "blockers": sorted({blocker for year in years for blocker in (year.get("blockers") or [])}),
        "coveredYears": [int(year.get("year")) for year in years if year.get("status") == "pass"],
        "blockedYears": blocked_years,
        "structuredQuestionCoveragePass": bool(report.get("structuredQuestionCoveragePass")),
        "questionCount": int((report.get("totals") or {}).get("questions") or 0),
        "subquestionCount": int((report.get("totals") or {}).get("subquestions") or 0),
        "answerCount": int((report.get("totals") or {}).get("answers") or 0),
        "qualityReviewRows": int((report.get("totals") or {}).get("qualityReviewRows") or 0),
    }


def tagging_coverage_2016_2025(repo_root: Path) -> dict[str, Any]:
    question_rows = read_csv(repo_root, REAL005B_QUALITY_QUESTION_CSV)
    mapping_rows = read_csv(repo_root, REAL005B_ASSET_MAPPING_CSV)
    exam_point_rows = read_csv(repo_root, REAL005B_EXAM_POINT_CSV)
    teaching_suggestion_rows = read_csv(repo_root, REAL005B_TEACHING_SUGGESTION_CSV)

    s007a = read_json(repo_root, S007A_SCHEMA_REPORT)
    s007b = read_json(repo_root, S007B_QUEUE_REPORT)
    s007c = read_json(repo_root, S007C_CONFIRM_REPORT)
    ns204 = read_json(repo_root, NS204_NO_ACTIVE_WRITE_REPORT)
    ns504 = read_json(repo_root, NS504_TAGGING_REVIEW_REPORT)
    l004_markdown = (repo_root / L004_TAGGING_PILOT_REPORT).read_text(encoding="utf-8")

    question_id_set = {str(row["question_id"]).strip() for row in question_rows}
    exam_points_by_id = {str(row["stable_id"]).strip(): row for row in exam_point_rows}
    teaching_suggestions_by_exam_point: dict[str, list[dict[str, str]]] = {}
    for row in teaching_suggestion_rows:
        exam_point_id = str(row.get("exam_point_id") or "").strip()
        if exam_point_id:
            teaching_suggestions_by_exam_point.setdefault(exam_point_id, []).append(row)

    mappings_by_question: dict[str, list[dict[str, str]]] = {}
    for row in mapping_rows:
        if str(row.get("source_asset_type") or "").strip() != "question":
            continue
        question_id = str(row.get("source_stable_id") or "").strip()
        if question_id in question_id_set:
            mappings_by_question.setdefault(question_id, []).append(row)

    question_count = len(question_rows)
    pending_review_question_count = 0
    question_type_count = 0
    primary_knowledge_count = 0
    primary_exam_point_count = 0
    question_mapping_pair_count = 0
    exam_point_difficulty_count = 0
    referenced_exam_point_ids: set[str] = set()

    for row in question_rows:
        question_id = str(row["question_id"]).strip()
        question_type = str(row.get("question_type") or "").strip()
        primary_knowledge_id = str(row.get("primary_knowledge_id") or "").strip()
        primary_exam_point_id = str(row.get("primary_exam_point_id") or "").strip()
        confidence = str(row.get("confidence") or "").strip()
        review_status = str(row.get("review_status") or "").strip()
        production_eligible = str(row.get("production_eligible") or "").strip().lower()

        if question_type:
            question_type_count += 1
        if primary_knowledge_id:
            primary_knowledge_count += 1
        if primary_exam_point_id:
            primary_exam_point_count += 1
            referenced_exam_point_ids.add(primary_exam_point_id)
        if question_type and primary_knowledge_id and primary_exam_point_id and confidence and review_status == "pending_review" and production_eligible == "false":
            pending_review_question_count += 1

        question_mappings = mappings_by_question.get(question_id, [])
        has_knowledge_mapping = any(
            str(mapping.get("target_asset_type") or "").strip() == "knowledge_point"
            and str(mapping.get("review_status") or "").strip() == "pending_review"
            and str(mapping.get("auto_apply_allowed") or "").strip().lower() == "false"
            for mapping in question_mappings
        )
        has_exam_point_mapping = any(
            str(mapping.get("target_asset_type") or "").strip() == "exam_point"
            and str(mapping.get("review_status") or "").strip() == "pending_review"
            and str(mapping.get("auto_apply_allowed") or "").strip().lower() == "false"
            for mapping in question_mappings
        )
        if has_knowledge_mapping and has_exam_point_mapping:
            question_mapping_pair_count += 1

        exam_point = exam_points_by_id.get(primary_exam_point_id)
        if exam_point is not None:
            difficulty_band = str(exam_point.get("difficulty_band") or "").strip()
            exam_point_review_status = str(exam_point.get("review_status") or "").strip()
            exam_point_production_eligible = str(exam_point.get("production_eligible") or "").strip().lower()
            if difficulty_band and exam_point_review_status == "pending_review" and exam_point_production_eligible == "false":
                exam_point_difficulty_count += 1

    teaching_suggestion_exam_point_count = sum(1 for exam_point_id in referenced_exam_point_ids if exam_point_id in teaching_suggestions_by_exam_point)

    tag_candidate_pass = (
        question_count > 0
        and pending_review_question_count == question_count
        and question_type_count == question_count
        and primary_knowledge_count == question_count
        and primary_exam_point_count == question_count
        and question_mapping_pair_count == question_count
        and exam_point_difficulty_count == question_count
    )
    teacher_confirm_path_pass = (
        s007c.get("status") == "pass"
        and str((s007c.get("confirm") or {}).get("status") or "") == "confirmed"
        and str((s007c.get("undo") or {}).get("status") or "") == "undone"
        and bool((ns504.get("acceptance") or {}).get("teacherConfirmWritesQuestionAndMapping"))
    )
    no_active_write_pass = (
        s007a.get("status") == "pass"
        and {"knowledge_tagging", "question_type", "difficulty_estimation"}.issubset(set(s007a.get("suggestionTypes") or []))
        and s007b.get("status") == "pass"
        and bool((s007b.get("noActiveWriteGuard") or {}).get("changed") is False)
        and ns204.get("status") == "pass"
        and bool((ns204.get("acceptance") or {}).get("aiCandidatesStayPendingReview"))
        and bool((ns204.get("acceptance") or {}).get("dynamicAssetActiveSwitchBlocked"))
        and bool((ns204.get("acceptance") or {}).get("liveClosureNotClaimed"))
        and ns504.get("status") == "pass"
        and bool((ns504.get("acceptance") or {}).get("suggestionsEnterReviewQueue"))
        and bool((ns504.get("acceptance") or {}).get("suggestionsDoNotWriteQuestionBeforeConfirm"))
        and bool((ns504.get("acceptance") or {}).get("realModelCallsStillDisabled"))
        and bool((ns504.get("acceptance") or {}).get("externalAiCallsZero"))
        and bool((ns504.get("acceptance") or {}).get("activeC002NotSwitched"))
        and all(keyword in l004_markdown for keyword in ("AI 标注只作为建议", "绑定 active 知识版本", "pending_review", "未进入 active"))
    )

    blockers: list[str] = []
    if not tag_candidate_pass:
        blockers.append("2016_2025_per_question_tagging_suggestions_not_proven")
    if not teacher_confirm_path_pass:
        blockers.append("teacher_confirmed_tag_terminal_status_not_present")
    if not no_active_write_pass:
        blockers.append("tagging_no_active_write_not_proven")

    return {
        "status": "pass" if not blockers else "blocked",
        "evidencePaths": [
            REAL005B_QUALITY_QUESTION_CSV,
            REAL005B_ASSET_MAPPING_CSV,
            REAL005B_EXAM_POINT_CSV,
            REAL005B_TEACHING_SUGGESTION_CSV,
            L004_TAGGING_PILOT_REPORT,
            S007A_SCHEMA_REPORT,
            S007B_QUEUE_REPORT,
            S007C_CONFIRM_REPORT,
            NS204_NO_ACTIVE_WRITE_REPORT,
            NS504_TAGGING_REVIEW_REPORT,
        ],
        "blockers": blockers,
        "questionCount": question_count,
        "pendingReviewQuestionCount": pending_review_question_count,
        "questionTypeCount": question_type_count,
        "primaryKnowledgeCount": primary_knowledge_count,
        "primaryExamPointCount": primary_exam_point_count,
        "questionMappingPairCount": question_mapping_pair_count,
        "examPointDifficultyCount": exam_point_difficulty_count,
        "referencedExamPointCount": len(referenced_exam_point_ids),
        "teachingSuggestionExamPointCount": teaching_suggestion_exam_point_count,
        "noActiveWritePass": no_active_write_pass,
        "teacherConfirmPathPass": teacher_confirm_path_pass,
    }


def review_terminal_coverage_2016_2025(repo_root: Path) -> dict[str, Any]:
    question_rows = read_csv(repo_root, REAL005B_QUALITY_QUESTION_CSV)
    review_rows = read_csv(repo_root, REAL005B_QUALITY_REVIEW_EVIDENCE_CSV)
    registry_rows = read_csv(repo_root, REAL005B_QUALITY_REVIEW_REGISTRY_CSV)
    real004 = read_json(repo_root, REAL004_REPORT)

    question_id_set = {str(row["question_id"]).strip() for row in question_rows}
    registry_by_issue_id = {str(row.get("issue_id") or "").strip(): row for row in registry_rows}
    reviews_by_question: dict[str, list[dict[str, str]]] = {}
    for row in review_rows:
        question_id = str(row.get("question_id") or "").strip()
        if question_id in question_id_set:
            reviews_by_question.setdefault(question_id, []).append(row)

    per_question_terminal_count = 0
    reviewer_count = 0
    reviewed_at_count = 0
    decision_count = 0
    issue_link_count = 0
    resolved_registry_count = 0
    production_eligible_registry_count = 0
    decision_counts: dict[str, int] = {}
    missing_questions: list[str] = []

    for question_id in sorted(question_id_set):
        rows = reviews_by_question.get(question_id, [])
        if not rows:
            missing_questions.append(question_id)
            continue
        row = rows[0]
        reviewer = str(row.get("reviewer") or "").strip()
        reviewed_at = str(row.get("reviewed_at") or "").strip()
        decision = str(row.get("decision") or "").strip()
        issue_id = str(row.get("issue_id") or "").strip()
        registry_row = registry_by_issue_id.get(issue_id)

        if reviewer:
            reviewer_count += 1
        if reviewed_at:
            reviewed_at_count += 1
        if decision:
            decision_count += 1
            decision_counts[decision] = decision_counts.get(decision, 0) + 1
        if issue_id:
            issue_link_count += 1
        if registry_row is not None:
            registry_status = str(registry_row.get("review_status") or "").strip()
            registry_production_eligible = str(registry_row.get("production_eligible") or "").strip().lower()
            if registry_status == "resolved":
                resolved_registry_count += 1
            if registry_production_eligible == "true":
                production_eligible_registry_count += 1

        if reviewer and reviewed_at and decision and issue_id and registry_row is not None and str(registry_row.get("review_status") or "").strip() == "resolved":
            per_question_terminal_count += 1

    verification = real004.get("verification") or {}
    review_actions_pass = (
        bool(verification.get("canConfirmWithAudit"))
        and bool(verification.get("canSubmitTeacherRevisionWithAudit"))
        and bool(verification.get("canReturnWithAudit"))
        and bool(verification.get("restoredRepeatableBaseline"))
    )
    per_question_terminal_pass = (
        len(question_rows) > 0
        and per_question_terminal_count == len(question_rows)
        and reviewer_count == len(question_rows)
        and reviewed_at_count == len(question_rows)
        and decision_count == len(question_rows)
        and issue_link_count == len(question_rows)
        and resolved_registry_count == len(question_rows)
        and production_eligible_registry_count == len(question_rows)
    )

    blockers: list[str] = []
    if not per_question_terminal_pass:
        blockers.append("2016_2025_review_queue_terminal_status_not_present")
        blockers.append("no_per_question_terminal_teacher_review_for_2015_2025")
    if not review_actions_pass:
        blockers.append("2015_review_smoke_restores_open_review_items")

    return {
        "status": "pass" if not blockers else "blocked",
        "evidencePaths": [
            REAL004_REPORT,
            REAL005B_QUALITY_REVIEW_EVIDENCE_CSV,
            REAL005B_QUALITY_REVIEW_REGISTRY_CSV,
        ],
        "blockers": blockers,
        "questionCount": len(question_rows),
        "perQuestionTerminalCount": per_question_terminal_count,
        "reviewerCount": reviewer_count,
        "reviewedAtCount": reviewed_at_count,
        "decisionCount": decision_count,
        "issueLinkCount": issue_link_count,
        "resolvedRegistryCount": resolved_registry_count,
        "productionEligibleRegistryCount": production_eligible_registry_count,
        "decisionCounts": decision_counts,
        "missingQuestionSample": missing_questions[:10],
        "reviewActionsPass": review_actions_pass,
    }


def reviewed_source_detail_coverage_2016_2025(repo_root: Path) -> dict[str, Any]:
    question_rows = read_csv(repo_root, REAL005B_QUALITY_QUESTION_CSV)
    review_rows = read_csv(repo_root, REAL005B_QUALITY_REVIEW_EVIDENCE_CSV)
    s006c = read_json(repo_root, S006C_SOURCE_REVIEW_REPORT)
    real004 = read_json(repo_root, REAL004_REPORT)
    latest_visibility_report_path = find_latest_json(repo_root, REAL005B_REVIEWED_VISIBILITY_GLOB)
    visibility_report = read_json(repo_root, latest_visibility_report_path) if latest_visibility_report_path else None
    latest_source_smoke_report_path = find_latest_json_with_status(repo_root, REAL005B_REVIEWED_SOURCE_SMOKE_GLOB, "pass")
    source_smoke_report = read_json(repo_root, latest_source_smoke_report_path) if latest_source_smoke_report_path else None

    question_id_set = {str(row["question_id"]).strip() for row in question_rows}
    reviews_by_question: dict[str, list[dict[str, str]]] = {}
    for row in review_rows:
        question_id = str(row.get("question_id") or "").strip()
        if question_id in question_id_set:
            reviews_by_question.setdefault(question_id, []).append(row)

    required_fields = [
        "source_file",
        "page",
        "question_anchor",
        "original_paper_file",
        "original_paper_page",
        "answer_source_file",
        "answer_evidence_location",
        "year_report_evidence_location",
        "official_exam_point_summary",
        "evidence_note",
        "decision",
    ]
    per_question_source_detail_count = 0
    missing_source_detail_questions: list[str] = []
    for question_id in sorted(question_id_set):
        rows = reviews_by_question.get(question_id, [])
        if not rows:
            missing_source_detail_questions.append(question_id)
            continue
        row = rows[0]
        if all(str(row.get(field) or "").strip() for field in required_fields):
            per_question_source_detail_count += 1
        else:
            missing_source_detail_questions.append(question_id)

    real004_verification = real004.get("verification") or {}
    real2015_source_review_pass = (
        bool(real004_verification.get("canLoadQuestionSources"))
        and bool(real004_verification.get("allReviewItemsHaveSourceScreenshotUrls"))
        and bool(real004_verification.get("allReviewItemsHavePageScreenshotUrls"))
    )
    s006c_fallback_pass = (
        s006c.get("status") == "pass"
        and int(((s006c.get("fallbackCases") or {}).get("missingScreenshotStatus") or 0)) == 409
        and int(((s006c.get("fallbackCases") or {}).get("notFoundStatus") or 0)) == 404
    )
    per_question_source_detail_pass = len(question_rows) > 0 and per_question_source_detail_count == len(question_rows)
    reviewed_question_visibility_pass = bool(
        visibility_report
        and visibility_report.get("status") == "pass"
        and visibility_report.get("hasApiVisible2016_2025ReviewedQuestions") is True
    )
    reviewed_question_source_smoke_pass = bool(
        source_smoke_report
        and source_smoke_report.get("status") == "pass"
        and int(source_smoke_report.get("questionCount") or 0) == len(question_rows)
        and bool(source_smoke_report.get("sourceReviewPass"))
    )

    blockers: list[str] = []
    if not per_question_source_detail_pass:
        blockers.append("all_years_reviewed_question_terminal_status_required_before_save_source_review_closure")
    if not reviewed_question_visibility_pass:
        blockers.append("2016_2025_reviewed_questions_not_materialized_for_api_source_review")
    if not (real2015_source_review_pass and s006c_fallback_pass and reviewed_question_source_smoke_pass):
        blockers.append("2016_2025_reviewed_question_save_and_source_detail_smoke_not_present")

    return {
        "status": "pass" if not blockers else "blocked",
        "evidencePaths": [
            REAL004_REPORT,
            S006C_SOURCE_REVIEW_REPORT,
            REAL005B_QUALITY_REVIEW_EVIDENCE_CSV,
            *([latest_visibility_report_path] if latest_visibility_report_path else []),
            *([latest_source_smoke_report_path] if latest_source_smoke_report_path else []),
        ],
        "blockers": blockers,
        "questionCount": len(question_rows),
        "perQuestionSourceDetailCount": per_question_source_detail_count,
        "missingSourceDetailQuestionSample": missing_source_detail_questions[:10],
        "real2015SourceReviewPass": real2015_source_review_pass,
        "s006cFallbackPass": s006c_fallback_pass,
        "reviewedQuestionVisibilityPass": reviewed_question_visibility_pass,
        "reviewedQuestionVisibilityEvidencePath": latest_visibility_report_path,
        "reviewedQuestionSourceSmokePass": reviewed_question_source_smoke_pass,
        "reviewedQuestionSourceSmokeEvidencePath": latest_source_smoke_report_path,
    }


def build_rg003(
    repo_root: Path,
    real001_report_path: str,
    real001: dict[str, Any],
    real002: dict[str, Any],
    real003: dict[str, Any],
) -> dict[str, Any]:
    details: list[dict[str, Any]] = []
    rows_2015 = build_2015_rows(real001, real002)
    numbers_2015 = question_numbers(rows_2015)
    missing_2015 = sorted(set(expected_range(24)) - set(numbers_2015))
    details.append(
        {
            "year": 2015,
            "expectedQuestionCount": 24,
            "actualQuestionCount": len(numbers_2015),
            "questionNumbers": numbers_2015,
            "missingQuestionNumbers": missing_2015,
            "evidencePaths": [real001_report_path, REAL002_REPORT],
            "status": "pass" if len(numbers_2015) == 24 and not missing_2015 else "blocked",
        }
    )

    for year in real003.get("years") or []:
        expected = int(year.get("expectedQuestionCount") or 0)
        numbers = [int(value) for value in year.get("questionNumbers") or []]
        missing = sorted(set(expected_range(expected)) - set(numbers))
        details.append(
            {
                "year": int(year["year"]),
                "expectedQuestionCount": expected,
                "actualQuestionCount": int(year.get("questionCount") or 0),
                "questionNumbers": numbers,
                "missingQuestionNumbers": missing,
                "evidencePaths": [REAL003_REPORT],
                "status": "pass"
                if expected > 0 and int(year.get("questionCount") or 0) == expected and not missing
                else "blocked",
            }
        )

    blocked = [row["year"] for row in details if row["status"] != "pass"]
    return {
        "criterionId": "RG003",
        "status": "pass" if not blocked and len(details) == len(REQUIRED_YEARS) else "blocked",
        "coveredYears": sorted(row["year"] for row in details if row["status"] == "pass"),
        "blockedYears": blocked,
        "evidencePaths": sorted({path for row in details for path in row["evidencePaths"]}),
        "details": sorted(details, key=lambda item: item["year"]),
        "blockers": [] if not blocked and len(details) == len(REQUIRED_YEARS) else ["question_count_coverage_incomplete"],
    }


def build_rg004(
    repo_root: Path,
    real001_report_path: str,
    real001: dict[str, Any],
    real002: dict[str, Any],
    real003: dict[str, Any],
) -> dict[str, Any]:
    details: list[dict[str, Any]] = []
    source_material_rows = read_csv(repo_root, REAL003_SOURCE_MATERIAL_CSV)
    question_rows = read_csv(repo_root, REAL003_QUESTION_CSV)
    answer_rows = read_csv(repo_root, REAL003_ANSWER_CSV)
    source_material_by_id, source_materials_by_year = build_source_material_maps(source_material_rows)
    question_rows_by_year = group_rows_by_year(question_rows)
    answer_rows_by_year = group_rows_by_year(answer_rows)
    year_hash_lookup = build_year_source_hash_lookup(real003)

    rows_2015 = build_2015_rows(real001, real002)
    answer_numbers_2015 = question_numbers([row for row in rows_2015 if row.get("answer") or row.get("answerPreview")])
    answer_anchor_numbers_2015 = question_numbers([row for row in rows_2015 if row.get("answerRegionId")])
    has_2015_answer_source_hash = bool(
        ((real001.get("sourceDocuments") or {}).get("answer") or {}).get("sha256")
        and len(answer_anchor_numbers_2015) == 24
    )
    has_2015_answer_anchor = len(answer_anchor_numbers_2015) == 24
    details_2015_status = "pass" if has_2015_answer_anchor and has_2015_answer_source_hash else "partial"
    details_2015_blockers: list[str] = []
    if not has_2015_answer_anchor:
        details_2015_blockers.append("per_question_answer_anchor_incomplete")
    if not has_2015_answer_source_hash:
        details_2015_blockers.append("per_question_answer_source_hash_binding_not_proven")
    details.append(
        {
            "year": 2015,
            "expectedQuestionCount": 24,
            "answerCount": len(answer_numbers_2015),
            "answerQuestionNumbers": answer_numbers_2015,
            "hasPerQuestionAnswerRegionAnchors": len(answer_anchor_numbers_2015) == 24,
            "hasPerQuestionAnswerSourceHashBinding": has_2015_answer_source_hash,
            "evidencePaths": [real001_report_path, REAL002_REPORT],
            "status": details_2015_status,
            "blockers": details_2015_blockers,
        }
    )

    for year in real003.get("years") or []:
        expected = int(year.get("expectedQuestionCount") or 0)
        answer_numbers = [int(value) for value in year.get("answerQuestionNumbers") or []]
        question_rows_for_year = question_rows_by_year.get(int(year["year"]), [])
        answer_rows_for_year = answer_rows_by_year.get(int(year["year"]), [])
        question_rows_by_number: dict[int, list[dict[str, str]]] = {}
        answer_rows_by_number: dict[int, list[dict[str, str]]] = {}
        for row in question_rows_for_year:
            question_number = str(row.get("question_number") or "").strip()
            if question_number.isdigit():
                question_rows_by_number.setdefault(int(question_number), []).append(row)
        for row in answer_rows_for_year:
            question_number = str(row.get("question_number") or "").strip()
            if question_number.isdigit():
                answer_rows_by_number.setdefault(int(question_number), []).append(row)
        bound_question_numbers = [
            number
            for number in answer_numbers
            if has_bound_source_hash(
                number,
                question_rows_by_number,
                answer_rows_by_number,
                source_material_by_id,
                year_hash_lookup.get(int(year["year"]), {}),
            )
        ]
        anchored_question_numbers = [
            number
            for number in answer_numbers
            if has_per_question_answer_anchor(
                number,
                question_rows_by_number,
                answer_rows_by_number,
                source_material_by_id,
                year_hash_lookup.get(int(year["year"]), {}),
            )
        ]
        has_source_hash_binding = expected > 0 and bound_question_numbers == expected_range(expected)
        has_anchor_binding = expected > 0 and anchored_question_numbers == expected_range(expected)
        coverage_ok = (
            expected > 0
            and int(year.get("answerCount") or 0) == expected
            and float(year.get("answerCoverage") or 0) == 1.0
            and answer_numbers == expected_range(expected)
        )
        year_blockers: list[str] = []
        if not coverage_ok:
            year_blockers.append("per_question_answer_source_anchor_not_proven_for_year_batch")
        else:
            if not has_anchor_binding:
                year_blockers.append("per_question_answer_source_anchor_not_proven_for_year_batch")
            if not has_source_hash_binding:
                year_blockers.append("per_question_answer_source_hash_binding_not_proven_for_year_batch")
        details.append(
            {
                "year": int(year["year"]),
                "expectedQuestionCount": expected,
                "answerCount": int(year.get("answerCount") or 0),
                "answerCoverage": float(year.get("answerCoverage") or 0),
                "answerQuestionNumbers": answer_numbers,
                "sourceMaterialRows": len(source_materials_by_year.get(int(year["year"]), {})),
                "anchoredAnswerQuestionNumbers": anchored_question_numbers,
                "boundAnswerSourceHashQuestionNumbers": bound_question_numbers,
                "hasPerQuestionAnswerRegionAnchors": has_anchor_binding,
                "hasPerQuestionAnswerSourceHashBinding": has_source_hash_binding,
                "evidencePaths": [REAL003_REPORT],
                "status": "pass" if coverage_ok and has_anchor_binding and has_source_hash_binding else ("partial" if coverage_ok else "blocked"),
                "blockers": year_blockers,
            }
        )

    blocked = [row["year"] for row in details if row["status"] == "blocked"]
    has_partial = any(row["status"] == "partial" for row in details)
    return {
        "criterionId": "RG004",
        "status": "blocked" if blocked else ("partial" if has_partial else "pass"),
        "coveredYears": sorted(row["year"] for row in details if row["status"] in ("pass", "partial")),
        "blockedYears": blocked,
        "evidencePaths": sorted({path for row in details for path in row["evidencePaths"]}),
        "details": sorted(details, key=lambda item: item["year"]),
        "blockers": sorted({blocker for row in details for blocker in row.get("blockers", [])}),
    }


def build_static_criteria(
    real001_report_path: str,
    real001: dict[str, Any],
    real002: dict[str, Any],
    real003: dict[str, Any],
    real004: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    real001_verification = real001.get("verification") or {}
    real002_verification = real002.get("verification") or {}
    real003_manual_takeovers = sorted(
        {
            takeover
            for year in real003.get("years") or []
            for takeover in (year.get("manualTakeoverPoints") or [])
        }
    )
    real004_verification = real004.get("verification") or {}
    real007 = read_json(Path(__file__).resolve().parents[1], REAL007_REPORT)
    real005b_coverage = visual_region_coverage_2015(real002, real007)
    real005b_source_region_coverage = source_region_coverage_2016_2025(Path(__file__).resolve().parents[1])
    real005b_structured_coverage = structured_question_coverage_2016_2025(Path(__file__).resolve().parents[1])
    real005b_tagging_coverage = tagging_coverage_2016_2025(Path(__file__).resolve().parents[1])
    real005b_review_terminal_coverage = review_terminal_coverage_2016_2025(Path(__file__).resolve().parents[1])
    real005b_reviewed_source_detail_coverage = reviewed_source_detail_coverage_2016_2025(Path(__file__).resolve().parents[1])

    return {
        "RG005": {
            "criterionId": "RG005",
            "status": "pass"
            if real005b_coverage["layoutQualityPass"] and real005b_source_region_coverage["sourceRegionCoveragePass"]
            else ("partial" if real005b_coverage["layoutQualityPass"] else "blocked"),
            "evidencePaths": [
                real001_report_path,
                REAL002_REPORT,
                REAL003_REPORT,
                REAL004_REPORT,
                REAL007_REPORT,
                REAL008_REPORT,
                *real005b_source_region_coverage["evidencePaths"],
            ],
            "coveredScope": "2015 smoke/source-region evidence plus 2016-2025 page screenshot coverage",
            "blockers": []
            if real005b_source_region_coverage["sourceRegionCoveragePass"]
            else real005b_source_region_coverage["blockers"],
            "signals": {
                "real001HasQuestionAndAnswerRegions": bool(real001_verification.get("hasQuestionAndAnswerRegions")),
                "real002AllHaveVisualRegionStatus": bool(real002_verification.get("allHaveVisualRegionStatus")),
                "real004AllReviewItemsHaveSourceScreenshotUrls": bool(
                    real004_verification.get("allReviewItemsHaveSourceScreenshotUrls")
                ),
                "real007LayoutQualityPass": real005b_coverage["layoutQualityPass"],
                "real002QuestionNumbers": real005b_coverage["questionNumbers"],
                "real002AssetQuestionNumbers": real005b_coverage["assetQuestionNumbers"],
                "real2016_2025SourceRegionCoveragePass": real005b_source_region_coverage["sourceRegionCoveragePass"],
                "real2016_2025VisualQuestionCount": real005b_source_region_coverage["visualQuestionCount"],
                "real2016_2025RenderedPages": real005b_source_region_coverage["renderedPages"],
                "manualTakeoverPoints": real003_manual_takeovers,
            },
        },
        "RG006": {
            "criterionId": "RG006",
            "status": "pass" if real005b_structured_coverage["structuredQuestionCoveragePass"] else "blocked",
            "evidencePaths": [
                real001_report_path,
                REAL002_REPORT,
                REAL003_REPORT,
                REAL009_REPORT,
                REAL010_REPORT,
                *real005b_structured_coverage["evidencePaths"],
            ],
            "coveredScope": "2015 pending_review smoke plus 2016-2025 structured candidate coverage",
            "blockers": []
            if real005b_structured_coverage["structuredQuestionCoveragePass"]
            else real005b_structured_coverage["blockers"],
            "signals": {
                "real001AllHaveAnswers": bool(real001_verification.get("allHaveAnswers")),
                "real001AllHaveKnowledgeTags": bool(real001_verification.get("allHaveKnowledgeTags")),
                "real002AllHaveAnswers": bool(real002_verification.get("allHaveAnswers")),
                "real002AllHaveKnowledgeTags": bool(real002_verification.get("allHaveKnowledgeTags")),
                "real2016_2025QuestionCount": real005b_structured_coverage["questionCount"],
                "real2016_2025SubquestionCount": real005b_structured_coverage["subquestionCount"],
                "real2016_2025AnswerCount": real005b_structured_coverage["answerCount"],
                "real2016_2025QualityReviewRows": real005b_structured_coverage["qualityReviewRows"],
            },
        },
        "RG007": {
            "criterionId": "RG007",
            "status": "pass" if real005b_tagging_coverage["status"] == "pass" else "blocked",
            "evidencePaths": [
                real001_report_path,
                REAL002_REPORT,
                REAL003_REPORT,
                *real005b_tagging_coverage["evidencePaths"],
            ],
            "coveredScope": "2015 deterministic seed tags plus 2016-2025 candidate knowledge/question-type/difficulty coverage",
            "blockers": [] if real005b_tagging_coverage["status"] == "pass" else real005b_tagging_coverage["blockers"],
            "signals": {
                "real001AllHaveKnowledgeTags": bool(real001_verification.get("allHaveKnowledgeTags")),
                "real002AllHaveKnowledgeTags": bool(real002_verification.get("allHaveKnowledgeTags")),
                "noActiveWrite": any("no_active_write" in value for value in real003_manual_takeovers),
                "real2016_2025QuestionCount": real005b_tagging_coverage["questionCount"],
                "real2016_2025PendingReviewQuestionCount": real005b_tagging_coverage["pendingReviewQuestionCount"],
                "real2016_2025QuestionTypeCount": real005b_tagging_coverage["questionTypeCount"],
                "real2016_2025PrimaryKnowledgeCount": real005b_tagging_coverage["primaryKnowledgeCount"],
                "real2016_2025PrimaryExamPointCount": real005b_tagging_coverage["primaryExamPointCount"],
                "real2016_2025QuestionMappingPairCount": real005b_tagging_coverage["questionMappingPairCount"],
                "real2016_2025ExamPointDifficultyCount": real005b_tagging_coverage["examPointDifficultyCount"],
                "real2016_2025ReferencedExamPointCount": real005b_tagging_coverage["referencedExamPointCount"],
                "real2016_2025TeachingSuggestionExamPointCount": real005b_tagging_coverage["teachingSuggestionExamPointCount"],
                "real2016_2025NoActiveWritePass": real005b_tagging_coverage["noActiveWritePass"],
                "real2016_2025TeacherConfirmPathPass": real005b_tagging_coverage["teacherConfirmPathPass"],
            },
        },
        "RG008": {
            "criterionId": "RG008",
            "status": "pass" if real005b_review_terminal_coverage["status"] == "pass" else "blocked",
            "evidencePaths": [
                REAL004_REPORT,
                REAL011_REPORT,
                *real005b_review_terminal_coverage["evidencePaths"],
            ],
            "coveredScope": "2015 review action smoke plus 2016-2025 per-question terminal review evidence",
            "blockers": []
            if real005b_review_terminal_coverage["status"] == "pass"
            else real005b_review_terminal_coverage["blockers"],
            "signals": {
                "canConfirmWithAudit": bool(real004_verification.get("canConfirmWithAudit")),
                "canSubmitTeacherRevisionWithAudit": bool(real004_verification.get("canSubmitTeacherRevisionWithAudit")),
                "canReturnWithAudit": bool(real004_verification.get("canReturnWithAudit")),
                "real2016_2025QuestionCount": real005b_review_terminal_coverage["questionCount"],
                "real2016_2025PerQuestionTerminalCount": real005b_review_terminal_coverage["perQuestionTerminalCount"],
                "real2016_2025ReviewerCount": real005b_review_terminal_coverage["reviewerCount"],
                "real2016_2025ReviewedAtCount": real005b_review_terminal_coverage["reviewedAtCount"],
                "real2016_2025DecisionCount": real005b_review_terminal_coverage["decisionCount"],
                "real2016_2025ResolvedRegistryCount": real005b_review_terminal_coverage["resolvedRegistryCount"],
                "real2016_2025ReviewActionsPass": real005b_review_terminal_coverage["reviewActionsPass"],
            },
        },
        "RG009": {
            "criterionId": "RG009",
            "status": "pass" if real005b_reviewed_source_detail_coverage["status"] == "pass" else "blocked",
            "evidencePaths": [
                REAL004_REPORT,
                REAL008_REPORT,
                REAL011_REPORT,
                *real005b_reviewed_source_detail_coverage["evidencePaths"],
            ],
            "coveredScope": "2015 source review/detail smoke plus 2016-2025 reviewed-question source detail evidence",
            "blockers": []
            if real005b_reviewed_source_detail_coverage["status"] == "pass"
            else real005b_reviewed_source_detail_coverage["blockers"],
            "signals": {
                "canLoadQuestionSources": bool(real004_verification.get("canLoadQuestionSources")),
                "allReviewItemsHaveSourceScreenshotUrls": bool(
                    real004_verification.get("allReviewItemsHaveSourceScreenshotUrls")
                ),
                "real2016_2025QuestionCount": real005b_reviewed_source_detail_coverage["questionCount"],
                "real2016_2025PerQuestionSourceDetailCount": real005b_reviewed_source_detail_coverage["perQuestionSourceDetailCount"],
                "real2016_2025SourceDetailFallbackPass": real005b_reviewed_source_detail_coverage["s006cFallbackPass"],
                "real2016_2025SourceReviewPass": real005b_reviewed_source_detail_coverage["real2015SourceReviewPass"],
                "real2016_2025ReviewedQuestionVisibilityPass": real005b_reviewed_source_detail_coverage["reviewedQuestionVisibilityPass"],
            },
        },
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# REAL005B Question Structure Diagnostics",
        "",
        f"- status: {report['status']}",
        f"- real005b_status: {report['real005BStatus']}",
        f"- checked_at: {report['checkedAt']}",
        f"- active_write: {str(report['activeWrite']).lower()}",
        f"- external_ai_calls: {report['externalAiCalls']}",
        "",
        "## Criteria",
    ]
    for criterion_id, criterion in report["criteria"].items():
        blockers = "none" if not criterion["blockers"] else " | ".join(criterion["blockers"])
        lines.append(f"- {criterion_id}: status={criterion['status']}; blockers={blockers}")

    lines.extend(
        [
            "",
            "## Boundary",
            "This diagnostic only reads existing REAL001-REAL004 and REAL007-REAL011 evidence. It does not write database rows, close review items, call external AI, use student data, or replace teacher review.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="REAL005B question structure and review diagnostics")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    real001_report_path = require_latest_json(repo_root, REAL001_REPORT_GLOB, "REAL001 report")
    real001 = read_json(repo_root, real001_report_path)
    real002 = read_json(repo_root, REAL002_REPORT)
    real003 = read_json(repo_root, REAL003_REPORT)
    real004 = read_json(repo_root, REAL004_REPORT)
    real005b_source_region_coverage = source_region_coverage_2016_2025(repo_root)
    real005b_structured_coverage = structured_question_coverage_2016_2025(repo_root)

    criteria: dict[str, dict[str, Any]] = {
        "RG003": build_rg003(repo_root, real001_report_path, real001, real002, real003),
        "RG004": build_rg004(repo_root, real001_report_path, real001, real002, real003),
    }
    criteria.update(build_static_criteria(real001_report_path, real001, real002, real003, real004))
    source_evidence = sorted(
        {
            REAL003_SOURCE_MATERIAL_CSV,
            REAL003_QUESTION_CSV,
            REAL003_ANSWER_CSV,
            *(path for criterion in criteria.values() for path in criterion.get("evidencePaths", [])),
        }
    )

    blockers = [
        f"{criterion_id}:{blocker}"
        for criterion_id, criterion in criteria.items()
        if criterion["status"] != "pass"
        for blocker in criterion["blockers"]
    ]
    real005b_status = "pass" if all(criterion["status"] == "pass" for criterion in criteria.values()) else "partial"

    report: dict[str, Any] = {
        "status": "pass",
        "taskId": "REAL005B_QUESTION_STRUCTURE_DIAGNOSTICS",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "real005BStatus": real005b_status,
        "criteriaIds": list(criteria.keys()),
        "criteria": criteria,
        "blockers": blockers,
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "sourceEvidence": source_evidence,
        "boundary": "read-only REAL005B diagnostics; no database write, no teacher-review closure, no external AI; candidate CSVs are read only to trace answer-source hash bindings",
        "rollback": "git clean -f -- docs/evidence/<date>-real005b-question-structure-diagnostics.json docs/evidence/<date>-real005b-question-structure-diagnostics.md",
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    write_markdown(report, Path(args.markdown_output))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
