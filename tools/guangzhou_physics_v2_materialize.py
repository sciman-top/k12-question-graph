from __future__ import annotations

import csv
import json
import re
import uuid
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from pypdf import PdfReader

from question_scope_normalization import (
    bind_materialized_block_ids,
    build_scope_key,
    normalize_question_scopes,
)


BATCH_KEY = "guangzhou_physics_2015_2025_20260726_v2"
WORKFLOW_KEY = "guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1"
OLD_WORKFLOW_KEY = "guangzhou_2016_2025_reviewed_question_materialize_v1"
C002_IMPORT_KEY = "c002_candidate_import_guangzhou_physics_2016_2025_v1"
YEARS = tuple(range(2015, 2026))
EXPECTED_COUNTS = {year: 24 if year <= 2020 else 18 for year in YEARS}
TABLE_PATTERN = re.compile(r"(表\s*\d+|数据在表|根据表|表格|如下表|表中)")
FORMULA_PATTERN = re.compile(r"(公式|U-I|F=|Q=|v=|R=|I/A|U/V|ρ=)")
QUESTION_ANCHOR = re.compile(r"(?m)(?:^|[\n\r。；;])\s*(\d{1,2})\s*[\.．、)]")
EXAM_INSTRUCTION_MARKERS = (
    "答题前",
    "考生务必",
    "答题卡上对应题目",
    "第一部分每小题选出答案后",
    "选择题每小题选出答案后",
    "答案必须写在答题卡",
    "考生必须保持答题卡",
    "请考生检查题数",
)


@dataclass(frozen=True)
class RegionPlan:
    page_number: int
    bbox_percent: tuple[float, float, float, float]
    relative_path: str | None


@dataclass(frozen=True)
class YearRegionPlan:
    year: int
    source_document_id: uuid.UUID
    source_file: str
    questions: dict[int, tuple[RegionPlan, ...]]
    manual_takeovers: frozenset[int]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def json_load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def stable_id(kind: str, *parts: object) -> uuid.UUID:
    token = ":".join(str(part) for part in (WORKFLOW_KEY, kind, *parts))
    return uuid.uuid5(uuid.NAMESPACE_URL, token)


def normalize_question_type(value: str) -> str:
    aliases = {
        "choice": "single_choice",
        "fill_blank": "fill_blank_or_drawing",
        "analysis_calculation": "experiment_or_calculation",
        "experiment_inquiry": "experiment_or_calculation",
        "comprehensive_calculation": "experiment_or_calculation",
    }
    return aliases.get(value.strip(), value.strip() or "unknown")


def parse_optional_float(value: str | None) -> float | None:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def split_tokens(value: str | None) -> list[str]:
    return [token.strip() for token in re.split(r"[;；|]", str(value or "")) if token.strip()]


def _candidate_text(value: str | dict[str, Any]) -> str:
    if isinstance(value, dict):
        return f"{value.get('question_type', '')} {value.get('stem_summary', '')} {value.get('notes', '')}"
    return str(value)


def is_table_candidate(value: str | dict[str, Any]) -> bool:
    return bool(TABLE_PATTERN.search(_candidate_text(value)))


def is_formula_candidate(value: str | dict[str, Any], question_type: str = "") -> bool:
    text = _candidate_text(value)
    if isinstance(value, dict):
        question_type = str(value.get("question_type") or question_type)
    return question_type in {
        "experiment_or_calculation",
        "calculation",
        "analysis_calculation",
        "experiment_inquiry",
        "comprehensive_calculation",
    } or bool(FORMULA_PATTERN.search(text))


def _year_from_report(item: dict[str, Any]) -> YearRegionPlan:
    questions: dict[int, tuple[RegionPlan, ...]] = {}
    for question in item.get("questions", []):
        number = int(question["questionNumber"])
        regions = tuple(
            RegionPlan(
                page_number=int(region["pageNumber"]),
                bbox_percent=tuple(float(value) for value in region["bboxPercent"]),  # type: ignore[arg-type]
                relative_path=str(region["relativePath"]),
            )
            for region in question.get("regions", [])
        )
        questions[number] = regions
    takeovers = frozenset(
        int(value["questionNumber"] if isinstance(value, dict) else value)
        for value in item.get("manualTakeoverCandidates", [])
    )
    return YearRegionPlan(
        year=int(item["year"]),
        source_document_id=uuid.UUID(str(item["sourceDocumentId"])),
        source_file=str(item["sourceFile"]),
        questions=questions,
        manual_takeovers=takeovers,
    )


def load_question_region_plans(report_2015: Path, report_2016_2025: Path) -> dict[int, YearRegionPlan]:
    first = json_load(report_2015)
    later = json_load(report_2016_2025)
    plans = [_year_from_report(first["year"]), *(_year_from_report(item) for item in later["years"])]
    result = {plan.year: plan for plan in plans}
    blockers: list[str] = []
    for year in YEARS:
        plan = result.get(year)
        if plan is None:
            blockers.append(f"question_region_year_missing:{year}")
            continue
        expected = set(range(1, EXPECTED_COUNTS[year] + 1))
        actual = set(plan.questions)
        if actual != expected:
            blockers.append(f"question_region_sequence_mismatch:{year}:{sorted(expected - actual)}:{sorted(actual - expected)}")
        if any(not regions for regions in plan.questions.values()):
            blockers.append(f"question_region_empty:{year}")
    if blockers:
        raise ValueError(";".join(blockers))
    return result


def load_c003_candidates(csv_root: Path) -> dict[tuple[int, int], dict[str, Any]]:
    questions = read_csv(csv_root / "c003-question-item-full.csv")
    answers = read_csv(csv_root / "c003-answer-scoring-point.csv")
    reviews = read_csv(csv_root / "c003-quality-issue-review-evidence.csv")
    subquestions = read_csv(csv_root / "c003-subquestion-item-full.csv")
    by_question = {row["question_id"]: row for row in questions}
    answers_by_question: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in answers:
        answers_by_question[row["question_id"]].append(row)
    review_by_question = {row["question_id"]: row for row in reviews}
    subs_by_question: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in subquestions:
        subs_by_question[row["question_id"]].append(row)

    result: dict[tuple[int, int], dict[str, Any]] = {}
    for question_id, row in by_question.items():
        year = int(row["year"])
        number = int(row["question_number"])
        answer_rows = answers_by_question.get(question_id, [])
        answer = answer_rows[0] if answer_rows else {}
        review = review_by_question.get(question_id, {})
        result[(year, number)] = {
            "legacyQuestionId": question_id,
            "stem": row.get("stem_summary", "").strip(),
            "questionType": normalize_question_type(row.get("question_type", "")),
            "score": parse_optional_float(row.get("score")),
            "answer": answer.get("answer_value", "").strip(),
            "solution": answer.get("scoring_point_summary", "").strip(),
            "scoringRows": answer_rows,
            "primaryKnowledgeCandidateId": row.get("primary_knowledge_id", "").strip(),
            "knowledgeCandidateIds": split_tokens(row.get("secondary_knowledge_ids")),
            "primaryExamPointCandidateId": row.get("primary_exam_point_id", "").strip(),
            "examPointCandidateIds": split_tokens(row.get("secondary_exam_point_ids")),
            "abilityDimensions": split_tokens(row.get("ability_dimensions")),
            "confidence": parse_optional_float(row.get("confidence")) or 0.0,
            "difficultyObserved": parse_optional_float(review.get("difficulty_value")),
            "discriminationObserved": parse_optional_float(review.get("discrimination_value")),
            "yearReportEvidenceLocation": review.get("year_report_evidence_location", "").strip(),
            "officialExamPointSummary": review.get("official_exam_point_summary", "").strip(),
            "answerEvidenceLocation": answer.get("evidence_locations", "").strip(),
            "subquestions": sorted(subs_by_question.get(question_id, []), key=lambda item: item.get("subquestion_number", "")),
        }
    return result


def validate_candidate_coverage(candidates: dict[tuple[int, int], dict[str, Any]]) -> None:
    blockers: list[str] = []
    for year in YEARS:
        expected = set(range(1, EXPECTED_COUNTS[year] + 1))
        actual = {number for candidate_year, number in candidates if candidate_year == year}
        if actual != expected:
            blockers.append(f"candidate_sequence_mismatch:{year}:{sorted(expected - actual)}:{sorted(actual - expected)}")
    if blockers:
        raise ValueError(";".join(blockers))


def validate_candidate_content(candidates: dict[tuple[int, int], dict[str, Any]]) -> None:
    blockers: list[str] = []
    for (year, number), candidate in sorted(candidates.items()):
        stem = re.sub(r"\s+", " ", str(candidate.get("stem") or "")).strip()
        if not stem:
            blockers.append(f"candidate_stem_missing:{year}:{number}")
            continue
        if any(marker in stem[:400] for marker in EXAM_INSTRUCTION_MARKERS):
            blockers.append(f"candidate_exam_instruction_stem:{year}:{number}")
    if blockers:
        raise ValueError(";".join(blockers))


def pdf_page_count(path: Path) -> int:
    return len(PdfReader(str(path)).pages)


def locate_answer_pages(path: Path, expected_count: int, minimum_page: int = 1) -> dict[int, tuple[int, ...]]:
    reader = PdfReader(str(path))
    page_text = [page.extract_text() or "" for page in reader.pages]
    return locate_answer_pages_from_texts(page_text, expected_count, minimum_page)


def locate_answer_pages_from_texts(
    page_text: list[str], expected_count: int, minimum_page: int = 1
) -> dict[int, tuple[int, ...]]:
    eligible_pages = tuple(range(max(1, minimum_page), len(page_text) + 1))
    if not eligible_pages:
        raise ValueError("answer_pdf_has_no_eligible_pages")

    anchors: dict[int, list[int]] = defaultdict(list)
    for page_number in eligible_pages:
        for match in QUESTION_ANCHOR.finditer(page_text[page_number - 1]):
            number = int(match.group(1))
            if 1 <= number <= expected_count:
                anchors[number].append(page_number)

    result: dict[int, tuple[int, ...]] = {}
    for number in range(1, expected_count + 1):
        unique = tuple(dict.fromkeys(anchors.get(number, [])))
        result[number] = unique if unique else eligible_pages
    return result


def extract_numbered_answer_sections(
    page_text: list[str], expected_count: int, minimum_page: int = 1
) -> dict[int, str]:
    eligible = page_text[max(0, minimum_page - 1) :]
    joined_parts: list[str] = []
    for page in eligible:
        joined_parts.append(page)
    joined = "\n\f\n".join(joined_parts)
    anchors = [
        (int(match.group(1)), match.start(), match.end())
        for match in QUESTION_ANCHOR.finditer(joined)
        if 1 <= int(match.group(1)) <= expected_count
    ]
    first_anchor: dict[int, tuple[int, int]] = {}
    for number, start, end in anchors:
        first_anchor.setdefault(number, (start, end))

    result: dict[int, str] = {}
    for number, (start, end) in first_anchor.items():
        next_starts = [candidate_start for _, candidate_start, _ in anchors if candidate_start > start]
        section_end = min(next_starts) if next_starts else len(joined)
        section = joined[start:section_end].strip()
        answer_marker = re.search(r"【\s*答案\s*】|\[\s*答案\s*\]|答案\s*[:：]", section)
        if answer_marker:
            section = section[answer_marker.end() :].strip()
        section = re.sub(r"\s+", " ", section).strip()
        if section:
            result[number] = section[:4000]
    return result


def extract_compact_choice_sequence(page_text: list[str], expected_count: int) -> dict[int, str]:
    for page in page_text:
        for line in page.splitlines():
            if not re.fullmatch(r"[A-D\s]+", line.strip()):
                continue
            letters = re.findall(r"[A-D]", line)
            if len(letters) == expected_count:
                return {index: value for index, value in enumerate(letters, start=1)}
    return {}


def answer_region_mode(pages: tuple[int, ...], eligible_page_count: int) -> str:
    return "question_anchor_page_candidate" if len(pages) < eligible_page_count else "whole_answer_document_pending_review"


def build_blocks(
    candidate: dict[str, Any],
    question_region_id: uuid.UUID,
    answer_region_id: uuid.UUID,
    question_id: str | uuid.UUID | None = None,
    materialized_blocks: Iterable[dict[str, Any]] = (),
) -> list[dict[str, Any]]:
    question_key = str(question_id or candidate.get("legacyQuestionId") or "").strip()
    normalized = normalize_question_scopes(
        question_key,
        candidate.get("subquestions", []),
        candidate.get("scoringRows", []),
    )
    existing_blocks = list(materialized_blocks)
    if existing_blocks:
        bind_materialized_block_ids(normalized, existing_blocks)
    whole_scope_key = build_scope_key(question_key, "whole_question")
    blocks: list[dict[str, Any]] = [
        {
            "type": "stem",
            "order": 0,
            "sourceRegionId": str(question_region_id),
            "content": {
                "text": candidate.get("stem", ""),
                "scopeKey": whole_scope_key,
                "reviewStatus": "pending_review",
            },
        }
    ]
    order = 1
    for block_candidate in normalized["blockCandidates"]:
        if block_candidate["type"] != "subquestion":
            continue
        blocks.append(
            {
                "type": "subquestion",
                "order": order,
                "sourceRegionId": str(question_region_id),
                "content": {
                    "stableKey": block_candidate["stableKey"],
                    "scopeKey": block_candidate["scopeKey"],
                    "questionBlockId": block_candidate["questionBlockId"],
                    "label": block_candidate["label"],
                    "text": block_candidate["text"],
                    "reviewStatus": "pending_review",
                    "productionEligible": False,
                },
            }
        )
        order += 1
    blocks.append(
        {
            "type": "answer",
            "order": order,
            "sourceRegionId": str(answer_region_id),
            "content": {
                "value": candidate.get("answer", ""),
                "solution": candidate.get("solution", ""),
                "scopeKey": whole_scope_key,
                "reviewStatus": "pending_review",
            },
        }
    )
    order += 1
    for block_candidate in normalized["blockCandidates"]:
        if block_candidate["type"] != "scoring_point":
            continue
        blocks.append(
            {
                "type": "scoring_point",
                "order": order,
                "sourceRegionId": str(answer_region_id),
                "content": {
                    "stableKey": block_candidate["stableKey"],
                    "scopeKey": block_candidate["scopeKey"],
                    "questionBlockId": block_candidate["questionBlockId"],
                    "label": block_candidate["label"],
                    "text": block_candidate["text"],
                    "reviewStatus": "pending_review",
                    "productionEligible": False,
                },
            }
        )
        order += 1
    text = str(candidate.get("stem", ""))
    if is_table_candidate(text):
        blocks.append(
            {
                "type": "table",
                "order": order,
                "sourceRegionId": str(question_region_id),
                "content": {
                    "status": "candidate",
                    "scopeKey": whole_scope_key,
                    "reviewStatus": "pending_review",
                    "sourceText": text,
                },
            }
        )
        order += 1
    if is_formula_candidate(text, str(candidate.get("questionType", ""))):
        blocks.append(
            {
                "type": "formula",
                "order": order,
                "sourceRegionId": str(question_region_id),
                "content": {
                    "status": "candidate",
                    "scopeKey": whole_scope_key,
                    "reviewStatus": "pending_review",
                    "sourceText": text,
                },
            }
        )
    return blocks


def flatten_question_regions(plans: Iterable[YearRegionPlan]) -> int:
    return sum(len(regions) for plan in plans for regions in plan.questions.values())
