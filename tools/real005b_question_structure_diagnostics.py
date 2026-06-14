from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REQUIRED_YEARS = list(range(2015, 2026))
REAL001_REPORT = "docs/evidence/20260512-guangzhou-2015-real-ingest-slice-report.json"
REAL002_REPORT = "docs/evidence/20260512-guangzhou-2015-visual-region-slice-report.json"
REAL003_REPORT = "docs/evidence/20260514-real003-guangzhou-physics-year-batch-ingest-report.json"
REAL004_REPORT = "docs/evidence/20260512-real004-guangzhou-2015-review-smoke-report.json"
REAL007_REPORT = "docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json"
REAL008_REPORT = "docs/evidence/20260518-real008-question-asset-smoke-report.json"
REAL009_REPORT = "docs/evidence/20260518-real009-table-structure-smoke-report.json"
REAL010_REPORT = "docs/evidence/20260518-real010-formula-fidelity-smoke-report.json"
REAL011_REPORT = "docs/evidence/20260518-real011-question-edit-smoke-report.json"


def read_json(repo_root: Path, relative_path: str) -> dict[str, Any]:
    return json.loads((repo_root / relative_path).read_text(encoding="utf-8"))


def question_numbers(rows: list[dict[str, Any]]) -> list[int]:
    values: list[int] = []
    for row in rows:
        value = row.get("questionNo", row.get("question_no"))
        if value is not None:
            values.append(int(value))
    return sorted(values)


def expected_range(expected_count: int) -> list[int]:
    return list(range(1, expected_count + 1))


def status_from_blockers(blockers: list[str], partial: bool = False) -> str:
    if blockers:
        return "partial" if partial else "blocked"
    return "pass"


def build_2015_rows(real001: dict[str, Any], real002: dict[str, Any]) -> list[dict[str, Any]]:
    first_batch = list(real001.get("appliedRows") or [])
    second_batch = list(real002.get("created") or [])
    return first_batch + second_batch


def build_rg003(repo_root: Path, real001: dict[str, Any], real002: dict[str, Any], real003: dict[str, Any]) -> dict[str, Any]:
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
            "evidencePaths": [REAL001_REPORT, REAL002_REPORT],
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


def build_rg004(real001: dict[str, Any], real002: dict[str, Any], real003: dict[str, Any]) -> dict[str, Any]:
    details: list[dict[str, Any]] = []
    rows_2015 = build_2015_rows(real001, real002)
    answer_numbers_2015 = question_numbers([row for row in rows_2015 if row.get("answer") or row.get("answerPreview")])
    answer_anchor_numbers_2015 = question_numbers([row for row in rows_2015 if row.get("answerRegionId")])
    details.append(
        {
            "year": 2015,
            "expectedQuestionCount": 24,
            "answerCount": len(answer_numbers_2015),
            "answerQuestionNumbers": answer_numbers_2015,
            "hasPerQuestionAnswerRegionAnchors": len(answer_anchor_numbers_2015) == 24,
            "hasPerQuestionAnswerSourceHashBinding": False,
            "evidencePaths": [REAL001_REPORT, REAL002_REPORT],
            "status": "partial",
            "blockers": ["per_question_answer_source_hash_binding_not_proven"],
        }
    )

    for year in real003.get("years") or []:
        expected = int(year.get("expectedQuestionCount") or 0)
        answer_numbers = [int(value) for value in year.get("answerQuestionNumbers") or []]
        coverage_ok = (
            expected > 0
            and int(year.get("answerCount") or 0) == expected
            and float(year.get("answerCoverage") or 0) == 1.0
            and answer_numbers == expected_range(expected)
        )
        details.append(
            {
                "year": int(year["year"]),
                "expectedQuestionCount": expected,
                "answerCount": int(year.get("answerCount") or 0),
                "answerCoverage": float(year.get("answerCoverage") or 0),
                "answerQuestionNumbers": answer_numbers,
                "hasPerQuestionAnswerRegionAnchors": False,
                "hasPerQuestionAnswerSourceHashBinding": False,
                "evidencePaths": [REAL003_REPORT],
                "status": "partial" if coverage_ok else "blocked",
                "blockers": ["per_question_answer_source_anchor_not_proven_for_year_batch"],
            }
        )

    blocked = [row["year"] for row in details if row["status"] == "blocked"]
    return {
        "criterionId": "RG004",
        "status": "partial" if not blocked else "blocked",
        "coveredYears": sorted(row["year"] for row in details if row["status"] in ("pass", "partial")),
        "blockedYears": blocked,
        "evidencePaths": sorted({path for row in details for path in row["evidencePaths"]}),
        "details": sorted(details, key=lambda item: item["year"]),
        "blockers": sorted({blocker for row in details for blocker in row.get("blockers", [])}),
    }


def build_static_criteria(real001: dict[str, Any], real002: dict[str, Any], real003: dict[str, Any], real004: dict[str, Any]) -> dict[str, dict[str, Any]]:
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

    return {
        "RG005": {
            "criterionId": "RG005",
            "status": "blocked",
            "evidencePaths": [REAL001_REPORT, REAL002_REPORT, REAL003_REPORT, REAL004_REPORT, REAL007_REPORT, REAL008_REPORT],
            "coveredScope": "2015 smoke/source-region evidence only",
            "blockers": [
                "2015_q1_q18_use_text_group_placeholder_coordinates",
                "2015_q19_q24_screenshot_manifest_pending_teacher_review",
                "2016_2025_screenshot_level_source_regions_not_created_by_REAL003_dry_run",
            ],
            "signals": {
                "real001HasQuestionAndAnswerRegions": bool(real001_verification.get("hasQuestionAndAnswerRegions")),
                "real002AllHaveVisualRegionStatus": bool(real002_verification.get("allHaveVisualRegionStatus")),
                "real004AllReviewItemsHaveSourceScreenshotUrls": bool(
                    real004_verification.get("allReviewItemsHaveSourceScreenshotUrls")
                ),
                "manualTakeoverPoints": real003_manual_takeovers,
            },
        },
        "RG006": {
            "criterionId": "RG006",
            "status": "blocked",
            "evidencePaths": [REAL001_REPORT, REAL002_REPORT, REAL003_REPORT, REAL009_REPORT, REAL010_REPORT],
            "coveredScope": "2015 structured/pending_review smoke only",
            "blockers": [
                "2016_2025_per_question_structured_blocks_not_emitted_in_year_batch_report",
                "2015_questions_remain_pending_review",
                "formula_table_image_fields_are_smoke_coverage_not_every_question_closure",
            ],
            "signals": {
                "real001AllHaveAnswers": bool(real001_verification.get("allHaveAnswers")),
                "real001AllHaveKnowledgeTags": bool(real001_verification.get("allHaveKnowledgeTags")),
                "real002AllHaveAnswers": bool(real002_verification.get("allHaveAnswers")),
                "real002AllHaveKnowledgeTags": bool(real002_verification.get("allHaveKnowledgeTags")),
            },
        },
        "RG007": {
            "criterionId": "RG007",
            "status": "blocked",
            "evidencePaths": [REAL001_REPORT, REAL002_REPORT, REAL003_REPORT],
            "coveredScope": "2015 deterministic seed tags only",
            "blockers": [
                "2015_tags_remain_pending_review",
                "2016_2025_per_question_tagging_suggestions_not_proven",
                "teacher_confirmed_tag_terminal_status_not_present",
            ],
            "signals": {
                "real001AllHaveKnowledgeTags": bool(real001_verification.get("allHaveKnowledgeTags")),
                "real002AllHaveKnowledgeTags": bool(real002_verification.get("allHaveKnowledgeTags")),
                "noActiveWrite": any("no_active_write" in value for value in real003_manual_takeovers),
            },
        },
        "RG008": {
            "criterionId": "RG008",
            "status": "blocked",
            "evidencePaths": [REAL004_REPORT, REAL011_REPORT],
            "coveredScope": "2015 review action smoke only",
            "blockers": [
                "no_per_question_terminal_teacher_review_for_2015_2025",
                "2015_review_smoke_restores_open_review_items",
                "2016_2025_review_queue_terminal_status_not_present",
            ],
            "signals": {
                "canConfirmWithAudit": bool(real004_verification.get("canConfirmWithAudit")),
                "canSubmitTeacherRevisionWithAudit": bool(real004_verification.get("canSubmitTeacherRevisionWithAudit")),
                "canReturnWithAudit": bool(real004_verification.get("canReturnWithAudit")),
            },
        },
        "RG009": {
            "criterionId": "RG009",
            "status": "blocked",
            "evidencePaths": [REAL004_REPORT, REAL008_REPORT, REAL011_REPORT],
            "coveredScope": "2015 source review/detail smoke only",
            "blockers": [
                "2016_2025_reviewed_question_save_and_source_detail_smoke_not_present",
                "all_years_reviewed_question_terminal_status_required_before_save_source_review_closure",
            ],
            "signals": {
                "canLoadQuestionSources": bool(real004_verification.get("canLoadQuestionSources")),
                "allReviewItemsHaveSourceScreenshotUrls": bool(
                    real004_verification.get("allReviewItemsHaveSourceScreenshotUrls")
                ),
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
    real001 = read_json(repo_root, REAL001_REPORT)
    real002 = read_json(repo_root, REAL002_REPORT)
    real003 = read_json(repo_root, REAL003_REPORT)
    real004 = read_json(repo_root, REAL004_REPORT)

    criteria: dict[str, dict[str, Any]] = {
        "RG003": build_rg003(repo_root, real001, real002, real003),
        "RG004": build_rg004(real001, real002, real003),
    }
    criteria.update(build_static_criteria(real001, real002, real003, real004))

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
        "sourceEvidence": [
            REAL001_REPORT,
            REAL002_REPORT,
            REAL003_REPORT,
            REAL004_REPORT,
            REAL007_REPORT,
            REAL008_REPORT,
            REAL009_REPORT,
            REAL010_REPORT,
            REAL011_REPORT,
        ],
        "boundary": "read-only REAL005B diagnostics; no database write, no teacher-review closure, no external AI",
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
