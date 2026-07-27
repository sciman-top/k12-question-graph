from __future__ import annotations

import argparse
import csv
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pdfplumber


QUESTION_REPAIRS: dict[tuple[int, int], dict[str, str]] = {
    (2017, 1): {"knowledge": "KPHY-C003-014", "exam": "EPHY-C003-001", "ability": "信息提取;科学推理"},
    (2017, 2): {"knowledge": "KPHY-C003-037", "exam": "EPHY-C003-003", "ability": "信息提取;科学推理"},
    (2017, 3): {"knowledge": "KPHY-C003-043", "exam": "EPHY-C003-012", "ability": "科学推理"},
    (2017, 4): {"knowledge": "KPHY-C003-048", "exam": "EPHY-C003-029", "ability": "信息提取;科学推理"},
    (2017, 5): {"knowledge": "KPHY-C003-055", "exam": "EPHY-C003-017", "ability": "科学推理"},
    (2018, 1): {"knowledge": "KPHY-C003-025", "exam": "EPHY-C003-001", "ability": "信息提取;科学推理"},
    (2018, 2): {"knowledge": "KPHY-C003-023", "exam": "EPHY-C003-007", "ability": "模型建构;科学推理"},
    (2018, 3): {"knowledge": "KPHY-C003-037", "exam": "EPHY-C003-003", "ability": "科学推理"},
    (2018, 4): {"knowledge": "KPHY-C003-072", "exam": "EPHY-C003-039", "ability": "信息提取;科学推理"},
    (2018, 5): {"knowledge": "KPHY-C003-047", "exam": "EPHY-C003-028", "ability": "模型建构;科学推理"},
    (2019, 1): {"knowledge": "KPHY-C003-037", "exam": "EPHY-C003-003", "ability": "信息提取;科学推理"},
    (2019, 2): {"knowledge": "KPHY-C003-018", "exam": "EPHY-C003-011", "ability": "信息提取"},
    (2019, 3): {"knowledge": "KPHY-C003-070", "exam": "EPHY-C003-017", "ability": "科学推理"},
    (2019, 4): {"knowledge": "KPHY-C003-023", "exam": "EPHY-C003-007", "ability": "科学推理"},
    (2019, 5): {"knowledge": "KPHY-C003-033", "exam": "EPHY-C003-021", "ability": "信息提取;科学推理"},
    (2020, 1): {"knowledge": "KPHY-C003-025", "exam": "EPHY-C003-001", "ability": "信息提取;科学推理"},
    (2020, 2): {"knowledge": "KPHY-C003-037", "exam": "EPHY-C003-003", "ability": "信息提取;科学推理"},
    (2020, 3): {"knowledge": "KPHY-C003-006", "exam": "EPHY-C003-005", "ability": "科学推理"},
    (2020, 4): {"knowledge": "KPHY-C003-043", "exam": "EPHY-C003-012", "ability": "科学推理"},
    (2020, 5): {"knowledge": "KPHY-C003-059", "exam": "EPHY-C003-008", "ability": "科学推理"},
    (2022, 1): {"knowledge": "KPHY-C003-026", "exam": "EPHY-C003-002", "ability": "信息提取;数学运算;科学推理"},
    (2022, 2): {"knowledge": "KPHY-C003-005", "exam": "EPHY-C003-005", "ability": "科学推理"},
    (2022, 3): {"knowledge": "KPHY-C003-061", "exam": "EPHY-C003-010", "ability": "信息提取;科学推理"},
    (2022, 4): {"knowledge": "KPHY-C003-044", "exam": "EPHY-C003-026", "ability": "信息提取;科学推理"},
    (2023, 1): {"knowledge": "KPHY-C003-014", "exam": "EPHY-C003-001", "ability": "信息提取;科学推理"},
    (2023, 2): {"knowledge": "KPHY-C003-043", "exam": "EPHY-C003-012", "ability": "科学推理"},
    (2023, 3): {"knowledge": "KPHY-C003-052", "exam": "EPHY-C003-039", "ability": "模型建构;科学推理", "secondary_knowledge": "KPHY-C003-063;KPHY-C003-072"},
    (2023, 4): {"knowledge": "KPHY-C003-049", "exam": "EPHY-C003-030", "ability": "信息提取;科学推理", "secondary_knowledge": "KPHY-C003-041"},
    (2024, 1): {"knowledge": "KPHY-C003-038", "exam": "EPHY-C003-023", "ability": "信息提取;科学推理", "secondary_knowledge": "KPHY-C003-049"},
    (2024, 2): {"knowledge": "KPHY-C003-037", "exam": "EPHY-C003-003", "ability": "信息提取;科学推理"},
    (2024, 3): {"knowledge": "KPHY-C003-072", "exam": "EPHY-C003-039", "ability": "信息提取;科学推理"},
    (2024, 4): {"knowledge": "KPHY-C003-027", "exam": "EPHY-C003-015", "ability": "科学推理"},
    (2025, 1): {"knowledge": "KPHY-C003-037", "exam": "EPHY-C003-003", "ability": "科学推理"},
    (2025, 2): {"knowledge": "KPHY-C003-018", "exam": "EPHY-C003-011", "ability": "信息提取;科学推理", "secondary_knowledge": "KPHY-C003-017"},
    (2025, 3): {"knowledge": "KPHY-C003-049", "exam": "EPHY-C003-030", "ability": "信息提取;科学推理"},
    (2025, 4): {"knowledge": "KPHY-C003-059", "exam": "EPHY-C003-008", "ability": "科学推理"},
}

INSTRUCTION_MARKERS = (
    "答题前",
    "考生务必",
    "答题卡上对应题目",
    "第一部分每小题选出答案后",
    "选择题每小题选出答案后",
    "答案必须写在答题卡",
    "考生必须保持答题卡",
    "请考生检查题数",
)

SECTION_BOUNDARY_PATTERN = re.compile(
    r"(?:第一|第二)部分\s*[（(][^）)]*[）)]"
    r"|[一二三四五六]\s*[、.]\s*(?:选择题|非选择题|填空\s*作图题|解析题|实验\s*探究题)"
    r"|第\s*\d+\s*[、,，]\s*\d+\s*题结合题目要求"
    r"|\d+\s*[~～—-]\s*\d+\s*题结合题目要求"
)


def read_csv(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader), list(reader.fieldnames or [])


def write_csv(path: Path, rows: list[dict[str, str]], headers: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def append_note(row: dict[str, str], note: str) -> None:
    existing = row.get("notes", "").strip()
    if note not in existing:
        row["notes"] = f"{existing}; {note}" if existing else note


def collapse_region_text(value: str) -> str:
    value = re.sub(r"学科网（北京）股份有限公司", "", value)
    value = re.sub(r"物理试卷\s*第\s*\d+\s*页\s*共\s*\d+\s*页", "", value)
    value = re.sub(r"物理试卷\s*第\s*\d+\s*页\s*[（(]\s*共\s*\d+\s*页\s*[）)]", "", value)
    value = re.sub(r"物理试卷\s*\d+", "", value)
    value = re.sub(r"第\s*\d+\s*页\s*/\s*共\s*\d+\s*页", "", value)
    value = re.sub(r"\[PAGE\s+\d+\]", "", value, flags=re.IGNORECASE)
    value = re.sub(r"考生号\s*[:：]?", "", value)
    separator = r"(?:\s*[.…·])*\s*"
    value = re.sub(rf"姓{separator}名\s*[:：]?{separator}号{separator}生{separator}考", "", value)
    value = re.sub(rf"[:：]?{separator}号{separator}生{separator}考", "", value)
    value = re.sub(rf"装{separator}订{separator}线", "", value)
    value = re.sub(r"[.…]{4,}", " ", value)
    value = re.sub(r"(?<!\S)(?:订|线|：号生考)(?!\S)", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def is_exam_instruction_stem(value: str) -> bool:
    collapsed = collapse_region_text(value)
    return any(marker in collapsed[:400] for marker in INSTRUCTION_MARKERS)


def extract_question_stem_from_region_text(value: str, question_number: int) -> str:
    collapsed = collapse_region_text(value)
    anchors = re.finditer(rf"(?<!\d){question_number}\s*[.．、，,]\s*", collapsed)
    anchor = next(
        (
            match
            for match in anchors
            if not re.match(r"\d+\s*题", collapsed[match.end() :])
        ),
        None,
    )
    if anchor is None:
        raise ValueError(f"question_anchor_missing:{question_number}")
    stem = collapsed[anchor.start() :].strip()
    next_anchor = re.search(
        rf"(?:(?<=[。！？?])|(?<=\s)){question_number + 1}\s*[.．、，,]\s*",
        stem[anchor.end() - anchor.start() :],
    )
    boundaries = [match.start() for match in SECTION_BOUNDARY_PATTERN.finditer(stem)]
    if next_anchor is not None:
        boundaries.append(anchor.end() - anchor.start() + next_anchor.start())
    if boundaries:
        stem = stem[: min(boundaries)].strip()
    if len(stem) < 12:
        raise ValueError(f"question_stem_too_short:{question_number}")
    if is_exam_instruction_stem(stem):
        raise ValueError(f"question_stem_is_exam_instruction:{question_number}")
    return stem


def load_region_stems(
    file_root: Path,
    source_report_path: Path,
    region_report_path: Path,
) -> dict[tuple[int, int], str]:
    source_report = json.loads(source_report_path.read_text(encoding="utf-8"))
    region_report = json.loads(region_report_path.read_text(encoding="utf-8"))
    source_paths = {
        int(year["year"]): str(year["sourceDocuments"][0]["relativePath"])
        for year in source_report["years"]
    }
    regions = {
        (int(year["year"]), int(question["questionNumber"])): list(question["regions"])
        for year in region_report["years"]
        for question in year["questions"]
    }
    result: dict[tuple[int, int], str] = {}
    by_year: dict[int, list[int]] = {}
    for year, number in regions:
        if 2016 <= year <= 2025:
            by_year.setdefault(year, []).append(number)

    for year, numbers in sorted(by_year.items()):
        pdf_path = file_root / Path(source_paths[year])
        with pdfplumber.open(pdf_path) as pdf:
            for number in sorted(numbers):
                segments: list[str] = []
                for region in regions[(year, number)]:
                    page = pdf.pages[int(region["pageNumber"]) - 1]
                    x, y, width, height = (float(value) for value in region["bboxPercent"])
                    crop = page.crop(
                        (
                            page.width * x / 100,
                            page.height * y / 100,
                            page.width * (x + width) / 100,
                            page.height * (y + height) / 100,
                        )
                    )
                    segment = crop.extract_text(x_tolerance=2, y_tolerance=3) or ""
                    normalized_segment = collapse_region_text(segment)
                    current_anchor = re.search(rf"(?<!\d){number}\s*[.．、，,]\s*", normalized_segment)
                    if current_anchor is None and re.search(r"完成第\s*\d+\s*[、,，]\s*\d+\s*题", normalized_segment):
                        continue
                    segments.append(normalized_segment)
                result[(year, number)] = extract_question_stem_from_region_text(" ".join(segments), number)
    return result


def repair_package(csv_root: Path, stems: dict[tuple[int, int], str], apply: bool) -> dict[str, Any]:
    question_rows, question_headers = read_csv(csv_root / "c003-question-item-full.csv")
    subquestion_path = csv_root / "c003-subquestion-item-full.csv"
    evidence_path = csv_root / "c003-evidence-index.csv"
    mapping_path = csv_root / "c003-asset-mapping.csv"
    subquestion_rows, subquestion_headers = read_csv(subquestion_path) if subquestion_path.exists() else ([], [])
    evidence_rows, evidence_headers = read_csv(evidence_path) if evidence_path.exists() else ([], [])
    mapping_rows, mapping_headers = read_csv(mapping_path) if mapping_path.exists() else ([], [])
    changed_ids: set[str] = set()
    mapping_repaired_ids: set[str] = set()
    stem_by_question_id: dict[str, str] = {}

    for row in question_rows:
        key = (int(row["year"]), int(row["question_number"]))
        stem = stems.get(key)
        if stem is None:
            continue
        row["stem_summary"] = stem
        append_note(row, "stem repaired from verified source region")
        changed_ids.add(row["question_id"])
        stem_by_question_id[row["question_id"]] = stem
        repair = QUESTION_REPAIRS.get(key)
        if repair is None:
            continue
        row["primary_knowledge_id"] = repair["knowledge"]
        row["secondary_knowledge_ids"] = repair.get("secondary_knowledge", "")
        row["primary_exam_point_id"] = repair["exam"]
        row["secondary_exam_point_ids"] = repair.get("secondary_exam", "")
        row["ability_dimensions"] = repair["ability"]
        row["confidence"] = "0.82"
        append_note(row, "candidate mapping repaired from verified source region")
        mapping_repaired_ids.add(row["question_id"])

    for row in subquestion_rows:
        if row.get("question_id") not in changed_ids:
            continue
        if str(row.get("subquestion_number") or "") in {"whole", "1"}:
            row["stem_summary"] = stem_by_question_id[row["question_id"]]
            append_note(row, "stem repaired from verified source region")
        if row.get("question_id") in mapping_repaired_ids:
            key = (int(row["year"]), int(row["question_number"]))
            repair = QUESTION_REPAIRS[key]
            row["primary_knowledge_id"] = repair["knowledge"]
            row["primary_exam_point_id"] = repair["exam"]
            row["ability_dimensions"] = repair["ability"]
            row["confidence"] = "0.82"
            append_note(row, "candidate mapping repaired from verified source region")

    for row in evidence_rows:
        if row.get("entity_id") not in changed_ids:
            continue
        row["evidence_summary"] = stem_by_question_id[row["entity_id"]]
        row["parse_quality"] = "text_repaired_from_verified_source_region"
        row["confidence"] = "0.88"
        append_note(row, "question stem repaired from verified source region")

    mapping_targets: dict[tuple[str, str], str] = {}
    for (year, number), repair in QUESTION_REPAIRS.items():
        question_id = f"QPHY-C003-{year}-{number:02d}"
        mapping_targets[(question_id, "knowledge_point")] = repair["knowledge"]
        mapping_targets[(question_id, "exam_point")] = repair["exam"]
    mapping_count = 0
    for row in mapping_rows:
        target = mapping_targets.get((row.get("source_stable_id", ""), row.get("target_asset_type", "")))
        if target is None:
            continue
        row["target_stable_id"] = target
        row["confidence"] = "0.82"
        append_note(row, "target repaired after verified source-region stem correction")
        mapping_count += 1

    remaining_instruction_rows = [
        row["question_id"] for row in question_rows if is_exam_instruction_stem(row.get("stem_summary", ""))
    ]
    if remaining_instruction_rows:
        raise ValueError(f"exam_instruction_stems_remain:{remaining_instruction_rows}")
    if len(changed_ids) != 210:
        raise ValueError(f"repair_coverage_mismatch:{len(changed_ids)}:210")

    if apply:
        write_csv(csv_root / "c003-question-item-full.csv", question_rows, question_headers)
        if subquestion_headers:
            write_csv(subquestion_path, subquestion_rows, subquestion_headers)
        if evidence_headers:
            write_csv(evidence_path, evidence_rows, evidence_headers)
        if mapping_headers:
            write_csv(mapping_path, mapping_rows, mapping_headers)

    return {
        "csvRoot": str(csv_root.resolve()),
        "mode": "apply" if apply else "dry_run",
        "questionRowsRepaired": len(changed_ids),
        "candidateMappingRowsRepaired": len(mapping_repaired_ids),
        "subquestionRowsRepaired": sum(
            1
            for row in subquestion_rows
            if row.get("question_id") in changed_ids and str(row.get("subquestion_number") or "") in {"whole", "1"}
        ),
        "evidenceRowsRepaired": sum(1 for row in evidence_rows if row.get("entity_id") in changed_ids),
        "mappingRowsRepaired": mapping_count,
        "optionalFilesPresent": {
            "subquestions": bool(subquestion_headers),
            "evidenceIndex": bool(evidence_headers),
            "assetMapping": bool(mapping_headers),
        },
        "remainingInstructionStemCount": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Repair C003 question stems from verified PDF source regions")
    parser.add_argument("--csv-root", action="append", required=True)
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument(
        "--source-report",
        default="docs/evidence/20260726-guangzhou-physics-v2-source-region-screenshots.json",
    )
    parser.add_argument(
        "--region-report",
        default="docs/evidence/20260726-guangzhou-physics-v2-question-regions.json",
    )
    parser.add_argument(
        "--output",
        default="docs/evidence/20260728-guangzhou-c003-question-stem-region-repair.json",
    )
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    stems = load_region_stems(
        Path(args.file_root),
        Path(args.source_report),
        Path(args.region_report),
    )
    packages = [repair_package(Path(value), stems, args.apply) for value in args.csv_root]
    report = {
        "status": "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "apply" if args.apply else "dry_run",
        "candidateOnly": True,
        "productionEligible": False,
        "activeWrite": False,
        "repairCount": len(stems),
        "packages": packages,
        "boundary": "Repairs pending-review C003 candidate text and candidate mappings only; no database, active C002, review resolution, or teacher acceptance write.",
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
