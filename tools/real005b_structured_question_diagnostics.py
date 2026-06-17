from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from real005b_reviewed_question_materialize import is_formula_candidate, is_table_candidate


CSV_ROOT = Path("guangzhou-physics-full-research-package-2016-2025/csv")
QUALITY_ROOT = Path("guangzhou-physics-full-research-package-2016-2025/quality-review-complete-csv-package")
YEARS = list(range(2016, 2026))


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def grouped(rows: list[dict[str, str]], key: str) -> dict[str, list[dict[str, str]]]:
    result: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        value = str(row.get(key) or "").strip()
        if value:
            result[value].append(row)
    return result


def is_image_like(row: dict[str, str]) -> bool:
    text = f"{row.get('question_type','')} {row.get('stem_summary','')} {row.get('notes','')}"
    return any(token in text for token in ("图", "示意图", "作图", "画出", "实验", "描点", "连线"))


def build_block_summary(row: dict[str, str], sub_rows: list[dict[str, str]], answer_rows: list[dict[str, str]]) -> dict[str, Any]:
    block_types: list[str] = ["stem"]
    if row.get("question_type") == "choice":
        block_types.append("option")
    if sub_rows:
        block_types.append("subquestion")
    if answer_rows:
        block_types.append("answer")
    if is_table_candidate(row):
        block_types.append("table_candidate")
    if is_formula_candidate(row):
        block_types.append("formula_candidate")
    if is_image_like(row):
        block_types.append("image_candidate")
    return {
        "questionId": row["question_id"],
        "year": int(row["year"]),
        "questionNumber": int(row["question_number"]),
        "questionType": row["question_type"],
        "pageOrLocation": row["page_or_location"],
        "reviewStatus": row["review_status"],
        "productionEligible": row["production_eligible"],
        "blockTypes": block_types,
        "stemPresent": bool(row.get("stem_summary", "").strip()),
        "subquestionCount": len(sub_rows),
        "answerCount": len(answer_rows),
        "imageLike": is_image_like(row),
        "tableLike": is_table_candidate(row),
        "formulaLike": is_formula_candidate(row),
        "notes": row.get("notes", ""),
    }


def build_year_report(
    year: int,
    question_rows: list[dict[str, str]],
    sub_rows_by_question: dict[str, list[dict[str, str]]],
    answer_rows_by_question: dict[str, list[dict[str, str]]],
    review_rows_by_question: dict[str, list[dict[str, str]]],
) -> dict[str, Any]:
    blocks = [
        build_block_summary(
            row,
            sub_rows_by_question.get(row["question_id"], []),
            answer_rows_by_question.get(row["question_id"], []),
        )
        for row in question_rows
    ]
    blockers: list[str] = []

    missing_stem = [item for item in blocks if not item["stemPresent"]]
    if missing_stem:
        blockers.append("stem_summary_missing")

    missing_answers = [item for item in blocks if item["answerCount"] == 0]
    if missing_answers:
        blockers.append("answer_row_missing")

    missing_subquestions = [
        item
        for item in blocks
        if item["questionType"] != "choice" and item["subquestionCount"] == 0
    ]
    if missing_subquestions:
        blockers.append("subquestion_rows_missing_for_non_choice")

    non_pending_review = [item for item in blocks if item["reviewStatus"] != "pending_review"]
    if non_pending_review:
        blockers.append("review_status_not_pending_review")

    production_eligible_rows = [item for item in blocks if item["productionEligible"] != "false"]
    if production_eligible_rows:
        blockers.append("production_eligible_not_false")

    missing_review_evidence = [item for item in blocks if not review_rows_by_question.get(item["questionId"])]
    if missing_review_evidence:
        blockers.append("quality_review_evidence_missing")

    table_candidates = [item for item in blocks if item["tableLike"]]
    formula_candidates = [item for item in blocks if item["formulaLike"]]
    image_candidates = [item for item in blocks if item["imageLike"]]

    return {
        "year": year,
        "status": "pass" if not blockers else "blocked",
        "questionCount": len(blocks),
        "blockTypeCounts": dict(Counter(block_type for item in blocks for block_type in item["blockTypes"])),
        "tableCandidateCount": len(table_candidates),
        "formulaCandidateCount": len(formula_candidates),
        "imageCandidateCount": len(image_candidates),
        "pendingReviewCount": sum(1 for item in blocks if item["reviewStatus"] == "pending_review"),
        "qualityReviewEvidenceCount": sum(1 for item in blocks if review_rows_by_question.get(item["questionId"])),
        "blockers": blockers,
        "samples": {
            "missingStem": missing_stem[:5],
            "missingAnswers": missing_answers[:5],
            "missingSubquestions": missing_subquestions[:5],
        },
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# REAL005B Structured Question Diagnostics",
        "",
        f"- status: {report['status']}",
        f"- checked_at: {report['checkedAt']}",
        f"- question_count: {report['totals']['questions']}",
        f"- subquestion_count: {report['totals']['subquestions']}",
        f"- answer_count: {report['totals']['answers']}",
        f"- quality_review_count: {report['totals']['qualityReviewRows']}",
        "",
        "## Years",
    ]
    for year in report["years"]:
        blockers = "none" if not year["blockers"] else " | ".join(year["blockers"])
        lines.append(
            f"- {year['year']}: status={year['status']}; "
            f"questions={year['questionCount']}; "
            f"tables={year['tableCandidateCount']}; "
            f"formulas={year['formulaCandidateCount']}; "
            f"images={year['imageCandidateCount']}; blockers={blockers}"
        )
    lines.extend(
        [
            "",
            "## Boundary",
            "This report reads the 2016-2025 quality-review package only. It does not write database rows, close review items, call external AI, or change active state.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="REAL005B structured question diagnostics for Guangzhou 2016-2025")
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    question_rows = read_csv(QUALITY_ROOT / "c003-question-item-full.csv")
    subquestion_rows = read_csv(CSV_ROOT / "c003-subquestion-item-full.csv")
    answer_rows = read_csv(QUALITY_ROOT / "c003-answer-scoring-point.csv")
    review_rows = read_csv(QUALITY_ROOT / "c003-quality-issue-review-evidence.csv")

    sub_rows_by_question = grouped(subquestion_rows, "question_id")
    answer_rows_by_question = grouped(answer_rows, "question_id")
    review_rows_by_question = grouped(review_rows, "question_id")

    question_rows_by_year: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in question_rows:
        year = int(row["year"])
        if year in YEARS:
            question_rows_by_year[year].append(row)

    years = [
        build_year_report(
            year,
            sorted(question_rows_by_year[year], key=lambda row: int(row["question_number"])),
            sub_rows_by_question,
            answer_rows_by_question,
            review_rows_by_question,
        )
        for year in YEARS
    ]

    blocked_years = [year["year"] for year in years if year["status"] != "pass"]
    report = {
        "status": "pass" if not blocked_years else "blocked",
        "taskId": "REAL005B_STRUCTURED_QUESTION_DIAGNOSTICS",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "blockedYears": blocked_years,
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "sourceEvidence": [
            str((QUALITY_ROOT / "c003-question-item-full.csv").as_posix()),
            str((CSV_ROOT / "c003-subquestion-item-full.csv").as_posix()),
            str((QUALITY_ROOT / "c003-answer-scoring-point.csv").as_posix()),
            str((QUALITY_ROOT / "c003-quality-issue-review-evidence.csv").as_posix()),
            str((QUALITY_ROOT / "c003-formalization-precheck-result.csv").as_posix()),
        ],
        "totals": {
            "questions": len(question_rows),
            "subquestions": len(subquestion_rows),
            "answers": len(answer_rows),
            "qualityReviewRows": len(review_rows),
        },
        "years": years,
        "structuredQuestionCoveragePass": len(blocked_years) == 0,
        "boundary": "read-only REAL005B structured question diagnostics; no database write, no teacher-review closure, no external AI",
        "rollback": "git clean -f -- docs/evidence/<date>-real005b-structured-question-diagnostics.json docs/evidence/<date>-real005b-structured-question-diagnostics.md",
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    write_markdown(report, Path(args.markdown_output))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())
