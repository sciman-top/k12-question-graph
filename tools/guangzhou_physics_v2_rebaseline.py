from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


EXPECTED_QUESTION_COUNT = 210
OLD_BATCH_KEY = "guangzhou_physics_2016_2025"
NEW_BATCH_KEY = "guangzhou_physics_2015_2025_20260726_v2"
ROLES = ("exam_paper", "answer_solution", "exam_year_report")


class RebaselineError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def roles_for(source_type: str, file_name: str) -> list[str]:
    if source_type in {"exam_analysis_report", "exam_year_report"} or "年报" in file_name:
        return ["exam_year_report"]
    if source_type == "answer_or_solution":
        return ["answer_solution"]
    if "含答案" in file_name:
        return ["exam_paper", "answer_solution"]
    if "解析版" in file_name or "答案" in file_name:
        return ["answer_solution"]
    if source_type == "local_exam_paper" or "广州中考" in file_name:
        return ["exam_paper"]
    return []


def build_source_index(rows: Iterable[dict[str, Any]], batch_key: str) -> dict[tuple[int, str], set[str]]:
    index: dict[tuple[int, str], set[str]] = defaultdict(set)
    for row in rows:
        row_batch = str(row.get("materialBatchKey") or "")
        if row_batch != batch_key:
            continue
        year_value = row.get("year")
        if year_value is None or str(year_value).strip() == "":
            continue
        year = int(year_value)
        file_name = str(row.get("originalFileName") or Path(str(row.get("path") or "")).name)
        source_type = str(row.get("sourceType") or "")
        source_hash = str(row.get("sha256") or "").lower()
        for role in roles_for(source_type, file_name):
            if source_hash:
                index[(year, role)].add(source_hash)
    return index


def import_rows(report: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        {
            "materialBatchKey": row.get("materialBatchKey"),
            "year": next(
                (item.get("year") for item in report.get("plan", []) if item.get("path") == row.get("path") and item.get("sourceType") == row.get("sourceType")),
                None,
            ),
            "sourceType": row.get("sourceType"),
            "originalFileName": Path(str(row.get("path") or "")).name,
            "sha256": row.get("sha256"),
        }
        for row in report.get("uploaded", [])
    ]


def single_hash(index: dict[tuple[int, str], set[str]], year: int, role: str) -> tuple[str | None, str | None]:
    hashes = index.get((year, role), set())
    if len(hashes) == 1:
        return next(iter(hashes)), None
    if not hashes:
        return None, f"missing_{role}"
    return None, f"ambiguous_{role}"


def classify_questions(
    questions: list[dict[str, str]],
    answers: list[dict[str, str]],
    old_index: dict[tuple[int, str], set[str]],
    new_index: dict[tuple[int, str], set[str]],
) -> list[dict[str, Any]]:
    answer_keys = {(row["year"], row["question_number"]) for row in answers}
    results: list[dict[str, Any]] = []
    for question in questions:
        year = int(question["year"])
        question_number = question["question_number"]
        blockers: list[str] = []
        changed_roles: list[str] = []
        hashes: dict[str, dict[str, str | None]] = {}
        if (question["year"], question_number) not in answer_keys:
            blockers.append("candidate_answer_row_missing")

        for role in ROLES:
            old_hash, old_error = single_hash(old_index, year, role)
            new_hash, new_error = single_hash(new_index, year, role)
            if old_error:
                blockers.append(f"old_{old_error}")
            if new_error:
                blockers.append(f"new_{new_error}")
            if old_hash and new_hash and old_hash != new_hash:
                changed_roles.append(role)
            hashes[role] = {"oldSha256": old_hash, "newSha256": new_hash}

        if blockers:
            classification = "blocked"
        elif changed_roles:
            classification = "changed_pending_review"
        else:
            classification = "matched"
        results.append(
            {
                "questionId": question["question_id"],
                "year": year,
                "questionNumber": question_number,
                "classification": classification,
                "changedRoles": changed_roles,
                "blockers": blockers,
                "sourceHashes": hashes,
                "reviewStatus": question.get("review_status"),
                "productionEligible": question.get("production_eligible"),
            }
        )
    return results


def write_classification_csv(rows: list[dict[str, Any]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ("questionId", "year", "questionNumber", "classification", "changedRoles", "blockers")
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    "questionId": row["questionId"],
                    "year": row["year"],
                    "questionNumber": row["questionNumber"],
                    "classification": row["classification"],
                    "changedRoles": "|".join(row["changedRoles"]),
                    "blockers": "|".join(row["blockers"]),
                }
            )


def build_report(
    questions: list[dict[str, str]],
    answers: list[dict[str, str]],
    old_rows: list[dict[str, Any]],
    new_report: dict[str, Any],
) -> dict[str, Any]:
    if len(questions) != EXPECTED_QUESTION_COUNT or len(answers) != EXPECTED_QUESTION_COUNT:
        raise RebaselineError(f"expected 210 questions and answers, got {len(questions)} and {len(answers)}")
    old_index = build_source_index(old_rows, OLD_BATCH_KEY)
    new_index = build_source_index(import_rows(new_report), NEW_BATCH_KEY)
    classifications = classify_questions(questions, answers, old_index, new_index)
    counts = Counter(row["classification"] for row in classifications)
    classification_counts = {
        key: counts[key]
        for key in ("matched", "changed_pending_review", "blocked")
    }
    invalid_candidate_rows = [
        row["questionId"]
        for row in classifications
        if row["reviewStatus"] != "pending_review" or row["productionEligible"] != "false"
    ]
    by_year = []
    for year in sorted({int(row["year"]) for row in classifications}):
        year_rows = [row for row in classifications if row["year"] == year]
        year_counts = Counter(row["classification"] for row in year_rows)
        by_year.append(
            {
                "year": year,
                "questionCount": len(year_rows),
                "classifications": {
                    key: year_counts[key]
                    for key in ("matched", "changed_pending_review", "blocked")
                },
            }
        )
    source_comparisons = []
    for year in sorted({int(row["year"]) for row in classifications}):
        roles = {}
        for role in ROLES:
            old_hash, old_error = single_hash(old_index, year, role)
            new_hash, new_error = single_hash(new_index, year, role)
            roles[role] = {
                "oldSha256": old_hash,
                "newSha256": new_hash,
                "status": "blocked" if old_error or new_error else "changed" if old_hash != new_hash else "matched",
                "errors": [error for error in (old_error, new_error) if error],
            }
        source_comparisons.append({"year": year, "roles": roles})
    blockers = []
    if counts["blocked"]:
        blockers.append("source_or_answer_coverage_blocked")
    if invalid_candidate_rows:
        blockers.append("candidate_safety_state_changed")
    return {
        "status": "blocked" if blockers else "review_required" if counts["changed_pending_review"] else "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "task": "Guangzhou physics C003 v2 source rebaseline",
        "oldMaterialBatchKey": OLD_BATCH_KEY,
        "newMaterialBatchKey": NEW_BATCH_KEY,
        "questionCount": len(classifications),
        "answerCount": len(answers),
        "classificationCounts": classification_counts,
        "byYear": by_year,
        "sourceComparisons": source_comparisons,
        "blockers": blockers,
        "invalidCandidateSafetyRows": invalid_candidate_rows,
        "activeWrite": False,
        "activationAllowed": False,
        "classifications": classifications,
        "next": "Reparse and review changed_pending_review rows before any candidate replacement; blocked rows require source repair.",
        "completionBoundary": "This report classifies the existing 210 C003 candidates against v2 source hashes; it does not approve candidates or modify C002 active assets.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Rebaseline C003 candidates against the Guangzhou physics v2 source batch")
    parser.add_argument("--csv-root", required=True)
    parser.add_argument("--old-source-snapshot", required=True)
    parser.add_argument("--new-import-report", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--classification-csv", required=True)
    args = parser.parse_args()

    csv_root = Path(args.csv_root)
    report = build_report(
        read_csv(csv_root / "c003-question-item-full.csv"),
        read_csv(csv_root / "c003-answer-scoring-point.csv"),
        list(read_json(Path(args.old_source_snapshot)).get("sourceDocuments", [])),
        read_json(Path(args.new_import_report)),
    )
    classification_rows = report.pop("classifications")
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_classification_csv(classification_rows, Path(args.classification_csv))
    print(json.dumps({key: report[key] for key in ("status", "questionCount", "classificationCounts", "blockers")}, ensure_ascii=False, indent=2))
    return 2 if report["status"] == "blocked" else 0


if __name__ == "__main__":
    raise SystemExit(main())
