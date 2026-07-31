from __future__ import annotations

"""Coordinate-preserving extraction from already reviewed question regions."""

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import fitz


QUESTION_PATTERN = re.compile(r"^\s*(\d{1,2})\s*[\.．、)]\s*(.*)$")
OPTION_PATTERN = re.compile(r"(?:^|\s)([A-D])\s*[\.．、]\s*")
EXPECTED_LABELS = ["A", "B", "C", "D"]
NOISE_PATTERN = re.compile(
    r"(?:考生号|姓名|物理试卷\s*第\s*\d+\s*页|装订线|^[\.．…]+$)"
)
FIGURE_LABEL_PATTERN = re.compile(r"^(?:图\s*\d+|[A-Z]\d*|[甲乙丙丁戊己])$")
TABLE_REFERENCE_PATTERN = re.compile(r"(?:下表|如下表|表中|表格|根据表)")


@dataclass(frozen=True)
class RegionChoiceExtraction:
    draft: dict[str, Any] | None
    blocker: str | None


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def bbox(line: dict[str, Any]) -> tuple[float, float, float, float]:
    values = line.get("bbox") or (0, 0, 0, 0)
    return tuple(float(value) for value in values[:4])  # type: ignore[return-value]


def positioned_lines_from_regions(
    pdf_path: Path,
    regions: Iterable[Any],
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    with fitz.open(pdf_path) as document:
        for region_index, region in enumerate(regions):
            page_number = int(region.page_number)
            page = document[page_number - 1]
            x, y, width, height = region.bbox_percent
            clip = fitz.Rect(
                page.rect.width * x / 100,
                page.rect.height * y / 100,
                page.rect.width * (x + width) / 100,
                page.rect.height * (y + height) / 100,
            )
            data = page.get_text("dict", clip=clip, sort=True)
            for block in data.get("blocks", []):
                if block.get("type") != 0:
                    continue
                for line in block.get("lines", []):
                    text = normalize_text("".join(str(span.get("text") or "") for span in line.get("spans", [])))
                    if not text:
                        continue
                    line_bbox = tuple(round(float(value), 3) for value in line.get("bbox", (0, 0, 0, 0)))
                    key = (page_number, *line_bbox, text)
                    if key in seen:
                        continue
                    seen.add(key)
                    result.append(
                        {
                            "text": text,
                            "pageNumber": page_number,
                            "bbox": list(line_bbox),
                            "regionIndex": region_index,
                        }
                    )
    return sorted(result, key=lambda line: (line["pageNumber"], line["regionIndex"], bbox(line)[1], bbox(line)[0]))


def split_option_line(text: str) -> list[tuple[str, str]]:
    matches = list(OPTION_PATTERN.finditer(text))
    options: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        options.append((match.group(1), normalize_text(text[match.end() : end])))
    return options


def is_prose_continuation(line: dict[str, Any], anchor_x: float) -> bool:
    text = normalize_text(str(line.get("text") or ""))
    x0, _, _, _ = bbox(line)
    return (
        len(re.sub(r"\W", "", text)) >= 6
        and not NOISE_PATTERN.search(text)
        and not FIGURE_LABEL_PATTERN.fullmatch(text)
        and x0 <= anchor_x + 24
    )


def extract_choice_from_positioned_lines(
    lines: list[dict[str, Any]], question_number: int
) -> RegionChoiceExtraction:
    anchor_index = None
    anchor_match: re.Match[str] | None = None
    for index, line in enumerate(lines):
        match = QUESTION_PATTERN.match(normalize_text(str(line.get("text") or "")))
        if match and int(match.group(1)) == question_number:
            anchor_index = index
            anchor_match = match
            break
    if anchor_index is None or anchor_match is None:
        return RegionChoiceExtraction(None, "question_anchor_not_found_in_source_region")

    segment: list[dict[str, Any]] = []
    for line in lines[anchor_index:]:
        match = QUESTION_PATTERN.match(normalize_text(str(line.get("text") or "")))
        if segment and match and int(match.group(1)) != question_number:
            break
        if not NOISE_PATTERN.search(normalize_text(str(line.get("text") or ""))):
            segment.append(line)

    anchor_x = bbox(segment[0])[0]
    stem_parts = [normalize_text(anchor_match.group(2))]
    option_rows: list[tuple[str, str, dict[str, Any]]] = []
    options_started = False
    visual_asset_required = "图" in stem_parts[0]
    for line in segment[1:]:
        text = normalize_text(str(line.get("text") or ""))
        parsed = split_option_line(text)
        if parsed:
            options_started = True
            option_rows.extend((label, value, line) for label, value in parsed)
            continue
        if FIGURE_LABEL_PATTERN.fullmatch(text):
            visual_asset_required = True
            continue
        if not options_started and is_prose_continuation(line, anchor_x):
            stem_parts.append(text)

    stem = normalize_text(" ".join(stem_parts))
    labels = [label for label, _, _ in option_rows]
    if TABLE_REFERENCE_PATTERN.search(stem):
        return RegionChoiceExtraction(None, "table_requires_structure_adapter")
    if labels != EXPECTED_LABELS:
        return RegionChoiceExtraction(None, "choice_option_order_ambiguous")
    if any(not value for _, value, _ in option_rows):
        return RegionChoiceExtraction(None, "choice_options_incomplete")

    source_regions = [
        {"pageNumber": int(line["pageNumber"]), "bbox": list(bbox(line)), "unit": "point"}
        for line in segment
    ]
    return RegionChoiceExtraction(
        {
            "stem": stem,
            "options": [
                {
                    "label": label,
                    "text": value,
                    "reviewStatus": "pending_review",
                    "sourceRegion": {
                        "pageNumber": int(line["pageNumber"]),
                        "bbox": list(bbox(line)),
                        "unit": "point",
                    },
                }
                for label, value, line in option_rows
            ],
            "structuredExtraction": {
                "adapter": "pymupdf_source_region_text",
                "reviewStatus": "pending_review",
                "visualAssetRequired": visual_asset_required,
                "sourceRegions": source_regions,
            },
        },
        None,
    )


def extract_choice_from_regions(
    pdf_path: Path,
    regions: Iterable[Any],
    question_number: int,
) -> RegionChoiceExtraction:
    return extract_choice_from_positioned_lines(
        positioned_lines_from_regions(pdf_path, regions),
        question_number,
    )


def write_evaluation_report(
    source_root: Path,
    report_2015: Path,
    report_2016_2025: Path,
    output: Path,
) -> dict[str, Any]:
    from guangzhou_physics_v2_materialize import YEARS, load_question_region_plans

    plans = load_question_region_plans(report_2015, report_2016_2025)
    years: list[dict[str, Any]] = []
    eligible_total = 0
    for year in YEARS:
        expected_choice_count = 12 if year <= 2020 else 10
        pdf_path = source_root / f"{year}广州中考.pdf"
        drafts: dict[str, Any] = {}
        blockers: dict[str, str] = {}
        for number in range(1, expected_choice_count + 1):
            result = extract_choice_from_regions(pdf_path, plans[year].questions[number], number)
            if result.draft is not None:
                drafts[str(number)] = result.draft
            else:
                blockers[str(number)] = result.blocker or "unknown_blocker"
        eligible_total += len(drafts)
        years.append(
            {
                "year": year,
                "choiceQuestionCount": expected_choice_count,
                "candidateCount": len(drafts),
                "drafts": drafts,
                "blockers": blockers,
            }
        )
    report = {
        "status": "review_required",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "adapter": "pymupdf_source_region_text",
        "sourceRoot": str(source_root),
        "totals": {
            "choiceQuestions": 122,
            "coordinateDraftCandidates": eligible_total,
            "blocked": 122 - eligible_total,
        },
        "years": years,
        "productionEligible": False,
        "databaseWrites": 0,
        "boundary": (
            "Coordinate drafts preserve line source boxes and are evaluation candidates only. "
            "They are not database-write eligible until visual golden review or an admitted layout adapter "
            "confirms complete stems, options, figures, tables and formulas."
        ),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate coordinate-preserving Guangzhou choice extraction")
    parser.add_argument(
        "--source-root",
        default=r"D:\KQG_Data\source_materials\imported\guangzhou_physics_2015_2025\20260726-v2\raw",
    )
    parser.add_argument(
        "--question-region-report-2015",
        default="docs/evidence/20260726-guangzhou-physics-v2-2015-question-regions.json",
    )
    parser.add_argument(
        "--question-region-report-2016-2025",
        default="docs/evidence/20260726-guangzhou-physics-v2-question-regions.json",
    )
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    report = write_evaluation_report(
        Path(args.source_root).resolve(),
        (repo_root / args.question_region_report_2015).resolve(),
        (repo_root / args.question_region_report_2016_2025).resolve(),
        (repo_root / args.output).resolve(),
    )
    print(json.dumps(report["totals"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
