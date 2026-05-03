from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_CSV_ROOT = Path("guangzhou-physics-full-research-package-2016-2025/csv")
DEFAULT_OUTPUT = Path("docs/evidence/c002s-formalization-precheck-report.json")
SAMPLE_YEARS = [str(year) for year in range(2016, 2026)]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def split_refs(value: str) -> list[str]:
    if not value:
        return []
    return [part.strip() for part in re.split(r"[;；,，]", value) if part.strip()]


def pick_year_sample(rows: list[dict[str, str]], sample_per_year: int) -> list[dict[str, str]]:
    samples: list[dict[str, str]] = []
    for year in SAMPLE_YEARS:
        year_rows = [row for row in rows if row["year"] == year]
        require(year_rows, f"missing C002S question rows for year {year}")
        year_rows.sort(key=lambda row: int(row["question_number"]))
        if len(year_rows) <= sample_per_year:
            samples.extend(year_rows)
            continue

        indexes = [0, len(year_rows) // 2, len(year_rows) - 1]
        if sample_per_year == 2:
            indexes = [0, len(year_rows) - 1]
        selected: list[int] = []
        for index in indexes[:sample_per_year]:
            if index not in selected:
                selected.append(index)
        samples.extend(year_rows[index] for index in selected)
    return samples


def page_number(value: str) -> str:
    match = re.search(r"年报p(\d+)", value or "")
    return match.group(1) if match else ""


def main() -> int:
    parser = argparse.ArgumentParser(description="C002S formalization precheck guard")
    parser.add_argument("--csv-root", type=Path, default=DEFAULT_CSV_ROOT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--sample-per-year", type=int, default=3)
    parser.add_argument("--expected-quality-issues", type=int, default=210)
    args = parser.parse_args()

    csv_root = args.csv_root
    require(csv_root.exists(), f"C002S CSV root does not exist: {csv_root}")
    require(2 <= args.sample_per_year <= 3, "C002S sample-per-year must be 2 or 3")

    questions = read_csv(csv_root / "c003-question-item-full.csv")
    answers = read_csv(csv_root / "c003-answer-scoring-point.csv")
    year_reports = read_csv(csv_root / "c003-year-report-observation.csv")
    quality_issues = read_csv(csv_root / "c003-quality-issue-registry.csv")
    knowledge_nodes = read_csv(csv_root / "c003-knowledge-node-full.csv")
    exam_points = read_csv(csv_root / "c003-exam-point-full.csv")
    curriculum_items = read_csv(csv_root / "c003-curriculum-standard-full.csv")
    textbook_nodes = read_csv(csv_root / "c003-textbook-node-full.csv")
    source_materials = read_csv(csv_root / "c003-source-material.csv")

    answer_question_ids = {row["question_id"] for row in answers}
    report_by_question = {row["question_id"]: row for row in year_reports}
    knowledge_ids = {row["stable_id"] for row in knowledge_nodes}
    exam_point_ids = {row["stable_id"] for row in exam_points}
    curriculum_ids = {row["stable_id"] for row in curriculum_items}
    textbook_ids = {row["stable_id"] for row in textbook_nodes}
    source_ids = {row["source_material_id"] for row in source_materials}

    sample_results: list[OrderedDict[str, Any]] = []
    for question in pick_year_sample(questions, args.sample_per_year):
        failures: list[str] = []
        report = report_by_question.get(question["question_id"])
        page = page_number(report["evidence_locations"] if report else "")

        if not question["stem_summary"].strip():
            failures.append("stem_summary_missing")
        if question["answer_source_id"] not in source_ids or question["question_id"] not in answer_question_ids:
            failures.append("answer_source_missing")
        if not report:
            failures.append("year_report_observation_missing")
        if not page:
            failures.append("year_report_page_anchor_missing")
        if question["primary_knowledge_id"] not in knowledge_ids:
            failures.append("primary_knowledge_ref_missing")
        if question["primary_exam_point_id"] not in exam_point_ids:
            failures.append("primary_exam_point_ref_missing")

        curriculum_missing = [ref for ref in split_refs(question["curriculum_item_ids"]) if ref not in curriculum_ids]
        textbook_missing = [ref for ref in split_refs(question["textbook_node_ids"]) if ref not in textbook_ids]
        if curriculum_missing:
            failures.append("curriculum_refs_missing")
        if textbook_missing:
            failures.append("textbook_refs_missing")

        sample_results.append(
            OrderedDict(
                [
                    ("questionId", question["question_id"]),
                    ("year", question["year"]),
                    ("questionNumber", question["question_number"]),
                    ("stemFoundInExamText", bool(question["stem_summary"].strip())),
                    ("answerSourceFileExists", question["answer_source_id"] in source_ids and question["question_id"] in answer_question_ids),
                    ("yearReportPage", page),
                    ("yearReportPageAnchorVerified", bool(page)),
                    ("primaryKnowledgeRefExists", question["primary_knowledge_id"] in knowledge_ids),
                    ("primaryExamPointRefExists", question["primary_exam_point_id"] in exam_point_ids),
                    ("curriculumRefsMissing", curriculum_missing),
                    ("textbookRefsMissing", textbook_missing),
                    ("status", "pass" if not failures else "fail"),
                    ("failures", failures),
                ]
            )
        )

    open_issues = [row for row in quality_issues if row["review_status"] != "resolved" or row["production_eligible"].lower() != "true"]
    issue_type_counts = Counter(row["issue_type"] for row in open_issues)
    sample_failures = sum(1 for row in sample_results if row["status"] != "pass")

    blockers: list[OrderedDict[str, Any]] = []
    if sample_failures:
        blockers.append(
            OrderedDict(
                [
                    ("blockerId", "c002s_sample_audit_failures"),
                    ("count", sample_failures),
                    ("nextAction", "fix sample source, answer, year-report page, knowledge, exam point, curriculum, or textbook evidence before active"),
                ]
            )
        )
    if open_issues:
        blockers.append(
            OrderedDict(
                [
                    ("blockerId", "c003_year_report_quality_issues_open"),
                    ("count", len(open_issues)),
                    ("nextAction", f"close {len(open_issues)} year-report page/metric review issues with explicit evidence before active"),
                ]
            )
        )

    require(len(quality_issues) == args.expected_quality_issues, f"expected {args.expected_quality_issues} C003 quality issues, got {len(quality_issues)}")
    require(len(sample_results) == len(SAMPLE_YEARS) * args.sample_per_year, "unexpected C002S sample size")

    if blockers:
        summary_result = "抽样来源核对通过，但年报页码/指标质量问题仍未清零，正式 C002 active 必须继续阻断。"
        summary_next = "逐条关闭 c003-quality-issue-registry.csv 中的 pending_review 问题，再运行 candidate DB dry-run、backup manifest、C002L readiness 和 active guard。"
    else:
        summary_result = "抽样来源核对通过，210 条年报页码/指标质量问题已清零，C002S 正式化前审查通过。"
        summary_next = "继续运行 candidate DB dry-run、backup manifest、C002L readiness、C002M 审核决策和 active guard；未完成审核前仍不得直接 active。"

    report = OrderedDict(
        [
            ("status", "pass" if not blockers else "blocked"),
            ("task", "C002S"),
            ("checkedAt", datetime.now(timezone.utc).isoformat()),
            ("samplePolicy", f"{args.sample_per_year} questions per year from 2016-2025: first/middle/last available question numbers"),
            ("sampleSize", len(sample_results)),
            ("sampleFailures", sample_failures),
            ("qualityIssuesTotal", len(quality_issues)),
            ("qualityIssuesOpenForProduction", len(open_issues)),
            ("qualityIssuesByType", dict(issue_type_counts)),
            ("productionActivationAllowed", not blockers),
            ("candidateBoundary", "candidate/pending_review/production_eligible=false until C002S blockers, review readiness, backup, and active guard are cleared"),
            ("blockers", blockers),
            ("sampleResults", sample_results),
            (
                "summaryChinese",
                OrderedDict(
                    [
                        ("title", "C002S 广州物理正式化前审查闭环报告"),
                        ("result", summary_result),
                        ("next", summary_next),
                    ]
                ),
            ),
        ]
    )

    write_json(args.output, report)
    print(json.dumps({"status": report["status"], "task": "C002S", "output": str(args.output), "blockerCount": len(blockers)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
