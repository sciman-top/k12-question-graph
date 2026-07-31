from __future__ import annotations

import argparse
import csv
import json
import os
import re
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pdfplumber
import psycopg
from PIL import Image
from psycopg.rows import dict_row

from guangzhou_physics_2016_2025_source_region_screenshots import image_quality


YEARS = list(range(2016, 2026))
DEFAULT_MATERIAL_BATCH_KEY = "guangzhou_physics_2015_2025_20260726_v2"
ANCHOR_PATTERN = re.compile(r"(?:^|[^0-9])(\d{1,2})[.．、](?=[^0-9]|$)")
MULTI_QUESTION_HEADING_PATTERN = re.compile(r"\d{1,2}\s*[、,，]\s*\d{1,2}\s*题")
SECTION_BOUNDARY_PATTERN = re.compile(
    r"^\s*(?:第[一二三四五六七八九十]+部分|[一二三四五六七八九十]+[、.．]\s*(?:选择题|填空|作图|解析题|实验|探究题)|解析题应写出)"
)
PAGE_NUMBER_ONLY_PATTERN = re.compile(r"^\s*第\s*\d+\s*页\s*$")


@dataclass(frozen=True)
class Anchor:
    question_number: int
    page_number: int
    top: float
    x0: float
    text: str

    @property
    def position(self) -> tuple[int, float]:
        return self.page_number, self.top


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def expected_counts(rows: list[dict[str, str]]) -> dict[int, int]:
    grouped: dict[int, set[int]] = defaultdict(set)
    for row in rows:
        year_text = str(row.get("year") or "").strip()
        number_text = str(row.get("question_number") or "").strip()
        if year_text.isdigit() and number_text.isdigit():
            grouped[int(year_text)].add(int(number_text))
    return {year: len(grouped[year]) for year in YEARS}


def read_paper_sources(connection: str, material_batch_key: str) -> dict[int, dict[str, Any]]:
    with psycopg.connect(connection, row_factory=dict_row) as conn:
        rows = list(
            conn.execute(
                """
                select
                    sd.id as source_document_id,
                    sd.year,
                    sd.source_title,
                    fa.original_file_name,
                    fa.relative_path,
                    fa.sha256
                from source_documents sd
                join file_assets fa on fa.id = sd.file_asset_id
                where sd.material_batch_key = %s
                  and sd.source_type = 'local_exam_paper'
                  and sd.year between 2016 and 2025
                order by sd.year, sd.id
                """,
                (material_batch_key,),
            ).fetchall()
        )
    by_year: dict[int, dict[str, Any]] = {}
    for row in rows:
        year = int(row["year"])
        if year in by_year:
            raise RuntimeError(f"ambiguous paper source for {year} in {material_batch_key}")
        by_year[year] = dict(row)
    return by_year


def anchor_numbers(text: str) -> list[int]:
    if MULTI_QUESTION_HEADING_PATTERN.search(text):
        return []
    return [int(match.group(1)) for match in ANCHOR_PATTERN.finditer(text)]


def extract_anchors(pdf: pdfplumber.PDF, expected_count: int) -> tuple[list[Anchor], dict[int, float]]:
    anchors: list[Anchor] = []
    section_tops: dict[int, float] = {}
    for page_number, page in enumerate(pdf.pages, start=1):
        words = page.extract_words(x_tolerance=2, y_tolerance=3, keep_blank_chars=False)
        for word in words:
            text = str(word.get("text") or "")
            if "选择题" in text:
                section_tops[page_number] = max(section_tops.get(page_number, 0.0), float(word["top"]))
            if float(word["x0"]) > float(page.width) * 0.36:
                continue
            for number in anchor_numbers(text):
                if 1 <= number <= expected_count:
                    anchors.append(
                        Anchor(
                            question_number=number,
                            page_number=page_number,
                            top=float(word["top"]),
                            x0=float(word["x0"]),
                            text=text,
                        )
                    )
    return sorted(anchors, key=lambda item: item.position), section_tops


def select_question_anchors(
    anchors: list[Anchor],
    section_tops: dict[int, float],
    expected_count: int,
) -> tuple[dict[int, Anchor], list[dict[str, Any]]]:
    selected: dict[int, Anchor] = {}
    takeovers: list[dict[str, Any]] = []
    first_page_section_top = section_tops.get(1, 0.0)
    first_candidates = [
        anchor
        for anchor in anchors
        if anchor.question_number == 1 and anchor.page_number == 1 and anchor.top > first_page_section_top
    ]
    if first_candidates:
        selected[1] = first_candidates[0]
    else:
        inferred_top = first_page_section_top + 18.0 if first_page_section_top else 0.0
        selected[1] = Anchor(1, 1, inferred_top, 0.0, "inferred_after_choice_section")
        takeovers.append(
            {
                "questionNumber": 1,
                "reason": "question_anchor_missing_inferred_after_choice_section",
                "pageNumber": 1,
            }
        )

    previous = selected[1].position
    for number in range(2, expected_count + 1):
        candidates = [
            anchor
            for anchor in anchors
            if anchor.question_number == number and anchor.position > previous
        ]
        if not candidates:
            takeovers.append(
                {
                    "questionNumber": number,
                    "reason": "question_anchor_missing",
                    "afterPageNumber": previous[0],
                }
            )
            continue
        selected[number] = candidates[0]
        previous = candidates[0].position
    return selected, takeovers


def following_question_sequence_start(anchors: list[Anchor], last_anchor: Anchor, minimum_length: int = 3) -> Anchor | None:
    later = [anchor for anchor in anchors if anchor.position > last_anchor.position]
    for index, candidate in enumerate(later):
        expected = candidate.question_number
        sequence_length = 1
        for following in later[index + 1 :]:
            if following.question_number == expected:
                continue
            if following.question_number != expected + 1:
                break
            expected = following.question_number
            sequence_length += 1
            if sequence_length >= minimum_length:
                return candidate
    return None


def is_section_boundary_segment(text: str) -> bool:
    return bool(SECTION_BOUNDARY_PATTERN.search(text.replace("\n", " ")))


def is_trailing_page_number_only(page: pdfplumber.page.Page) -> bool:
    text = str(page.extract_text() or "")
    has_visual_content = bool(page.images or page.rects or page.curves or page.lines)
    return not has_visual_content and bool(PAGE_NUMBER_ONLY_PATTERN.fullmatch(text))


def crop_percent(source: Path, target: Path, left: float, top: float, right: float, bottom: float) -> dict[str, Any]:
    with Image.open(source) as image:
        width, height = image.size
        box = (
            max(0, int(width * left / 100)),
            max(0, int(height * top / 100)),
            min(width, int(width * right / 100)),
            min(height, int(height * bottom / 100)),
        )
        if box[2] <= box[0] or box[3] <= box[1]:
            raise RuntimeError(f"invalid crop box {box} for {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        image.crop(box).save(target, format="PNG", optimize=True)
    return image_quality(target)


def page_screenshot_index(screenshot_report: dict[str, Any], year: int) -> dict[int, str]:
    if "years" in screenshot_report:
        year_row = next((row for row in screenshot_report["years"] if int(row["year"]) == year), None)
        if year_row is None:
            return {}
        return {int(row["pageNumber"]): str(row["relativePath"]) for row in year_row["renderedPages"]}

    document = next(
        (
            row
            for row in screenshot_report.get("documents", [])
            if int(row.get("year") or 0) == year and row.get("sourceType") == "local_exam_paper"
        ),
        None,
    )
    if document is None:
        return {}
    return {int(row["pageNumber"]): str(row["relativePath"]) for row in document.get("pages", [])}


def source_page_report_matches_batch(screenshot_report: dict[str, Any], material_batch_key: str) -> bool:
    if screenshot_report.get("status") != "pass":
        return False
    if screenshot_report.get("materialBatchKey") == material_batch_key:
        return True
    documents = screenshot_report.get("documents", [])
    return bool(documents) and all(row.get("materialBatchKey") == material_batch_key for row in documents)


def build_question_regions(
    file_root: Path,
    material_batch_key: str,
    source: dict[str, Any],
    screenshot_report: dict[str, Any],
    expected_count: int,
) -> dict[str, Any]:
    year = int(source["year"])
    pdf_path = file_root / Path(str(source["relative_path"]))
    page_images = page_screenshot_index(screenshot_report, year)
    blockers: list[str] = []
    with pdfplumber.open(pdf_path) as pdf:
        anchors, section_tops = extract_anchors(pdf, expected_count)
        selected, takeovers = select_question_anchors(anchors, section_tops, expected_count)
        last_selected = selected.get(expected_count)
        following_sequence = following_question_sequence_start(anchors, last_selected) if last_selected else None
        question_end_page = following_sequence.page_number - 1 if following_sequence else len(pdf.pages)
        if last_selected and not following_sequence:
            while (
                question_end_page > last_selected.page_number
                and is_trailing_page_number_only(pdf.pages[question_end_page - 1])
            ):
                question_end_page -= 1
        if last_selected and question_end_page < last_selected.page_number:
            blockers.append("question_section_boundary_before_last_question")
            question_end_page = last_selected.page_number
        questions: list[dict[str, Any]] = []
        namespace = material_batch_key.replace("_", "-")
        for question_number in range(1, expected_count + 1):
            start = selected.get(question_number)
            if start is None:
                blockers.append(f"question_anchor_missing:{question_number}")
                questions.append({"questionNumber": question_number, "status": "blocked", "regions": []})
                continue
            next_anchor = selected.get(question_number + 1)
            last_page = next_anchor.page_number if next_anchor else question_end_page
            regions: list[dict[str, Any]] = []
            skipped_blank_segments: list[int] = []
            skipped_section_segments: list[int] = []
            for page_number in range(start.page_number, last_page + 1):
                screenshot_relative_path = page_images.get(page_number)
                if not screenshot_relative_path:
                    blockers.append(f"source_page_screenshot_missing:q{question_number}:p{page_number}")
                    continue
                page_height = float(pdf.pages[page_number - 1].height)
                anchor_padding = 0.5 if question_number == 1 and not start.text.startswith("inferred_") else 1.5
                top = max(3.0, (start.top / page_height * 100) - anchor_padding) if page_number == start.page_number else 3.0
                bottom = (
                    min(97.0, (next_anchor.top / page_height * 100) - 0.8)
                    if next_anchor and page_number == next_anchor.page_number
                    else 97.0
                )
                if page_number != start.page_number and next_anchor and page_number == next_anchor.page_number:
                    page = pdf.pages[page_number - 1]
                    segment_text = page.crop((0, page.height * top / 100, page.width, page.height * bottom / 100)).extract_text() or ""
                    if is_section_boundary_segment(segment_text):
                        skipped_section_segments.append(page_number)
                        continue
                target_relative_path = (
                    f"generated/{namespace}/question-regions/{year}/{source['source_document_id']}/"
                    f"q{question_number:02d}-p{page_number:03d}.png"
                )
                quality = crop_percent(
                    file_root / Path(screenshot_relative_path),
                    file_root / Path(target_relative_path),
                    5.0,
                    top,
                    95.0,
                    bottom,
                )
                if not quality["nonBlank"]:
                    skipped_blank_segments.append(page_number)
                    (file_root / Path(target_relative_path)).unlink(missing_ok=True)
                else:
                    regions.append(
                        {
                            "pageNumber": page_number,
                            "bboxPercent": [5.0, round(top, 4), 90.0, round(bottom - top, 4)],
                            "relativePath": target_relative_path,
                            "imageQuality": quality,
                        }
                    )
            if not regions:
                blockers.append(f"question_regions_empty:{question_number}")
            questions.append(
                {
                    "questionNumber": question_number,
                    "status": "candidate" if regions else "blocked",
                    "anchor": {
                        "pageNumber": start.page_number,
                        "top": round(start.top, 3),
                        "text": start.text,
                        "mode": "inferred" if start.text.startswith("inferred_") else "pdf_text_anchor",
                    },
                    "regions": regions,
                    "skippedBlankPageSegments": skipped_blank_segments,
                    "skippedSectionBoundarySegments": skipped_section_segments,
                }
            )
    return {
        "year": year,
        "status": "blocked" if blockers else "review_required" if takeovers else "pass",
        "sourceDocumentId": str(source["source_document_id"]),
        "sourceFile": str(source["original_file_name"]),
        "sourceSha256": str(source["sha256"]),
        "expectedQuestionCount": expected_count,
        "selectedAnchorCount": len(selected),
        "regionCount": sum(len(question["regions"]) for question in questions),
        "manualTakeoverCandidates": takeovers,
        "questionSectionBoundary": {
            "endPageNumber": question_end_page,
            "mode": "following_question_sequence" if following_sequence else "document_end",
            "followingSequenceStart": (
                {
                    "questionNumber": following_sequence.question_number,
                    "pageNumber": following_sequence.page_number,
                    "top": round(following_sequence.top, 3),
                    "text": following_sequence.text,
                }
                if following_sequence
                else None
            ),
        },
        "blockers": blockers,
        "questions": questions,
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# Guangzhou Physics v2 Question Region Candidates",
        "",
        f"- status: {report['status']}",
        f"- material_batch_key: `{report['materialBatchKey']}`",
        f"- question_candidates: {report['totals']['questionCandidates']}",
        f"- region_candidates: {report['totals']['regionCandidates']}",
        f"- manual_takeovers: {report['totals']['manualTakeovers']}",
        "",
        "## Years",
    ]
    for year in report["years"]:
        lines.append(
            f"- {year['year']}: status={year['status']}; questions={year['expectedQuestionCount']}; "
            f"anchors={year['selectedAnchorCount']}; regions={year['regionCount']}; "
            f"takeovers={len(year['manualTakeoverCandidates'])}; blockers={' | '.join(year['blockers']) or 'none'}"
        )
    lines.extend(
        [
            "",
            "## Boundary",
            "These are machine-generated v2 question-region candidates. They do not replace teacher review, write database rows, or change C002 active assets.",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build v2 Guangzhou 2016-2025 question-region candidates")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default=os.environ.get("PGPASSWORD", ""))
    parser.add_argument("--material-batch-key", default=DEFAULT_MATERIAL_BATCH_KEY)
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--csv-root", default="guangzhou-physics-full-research-package-2016-2025/csv")
    parser.add_argument("--source-page-report", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--markdown-output", required=True)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    file_root = Path(args.file_root)
    counts = expected_counts(read_csv(repo_root / args.csv_root / "c003-question-item-full.csv"))
    screenshot_report = json.loads(Path(args.source_page_report).read_text(encoding="utf-8"))
    if not source_page_report_matches_batch(screenshot_report, args.material_batch_key):
        raise RuntimeError("source-page report must be a passing report for the requested material batch")
    connection = f"host={args.host} port={args.port} dbname={args.database} user={args.user} password={args.password}"
    sources = read_paper_sources(connection, args.material_batch_key)
    years = [
        build_question_regions(file_root, args.material_batch_key, sources[year], screenshot_report, counts[year])
        for year in YEARS
    ]
    blockers = [f"{year['year']}:{blocker}" for year in years for blocker in year["blockers"]]
    report = {
        "status": "blocked" if blockers else "review_required" if any(year["manualTakeoverCandidates"] for year in years) else "pass",
        "taskId": "GUANGZHOU_PHYSICS_V2_QUESTION_REGIONS",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "materialBatchKey": args.material_batch_key,
        "fileRoot": str(file_root),
        "sourcePageReport": args.source_page_report,
        "activeWrite": False,
        "externalAiCalls": 0,
        "realStudentDataUsed": False,
        "totals": {
            "questionCandidates": sum(year["expectedQuestionCount"] for year in years),
            "regionCandidates": sum(year["regionCount"] for year in years),
            "manualTakeovers": sum(len(year["manualTakeoverCandidates"]) for year in years),
            "blockedItems": len(blockers),
        },
        "blockers": blockers,
        "years": years,
        "boundary": "candidate-only question crops from v2 paper coordinates; no database write, no approval, no active switch",
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    write_markdown(report, Path(args.markdown_output))
    print(json.dumps({"status": report["status"], "totals": report["totals"], "blockers": blockers}, ensure_ascii=False, indent=2))
    return 2 if blockers else 0


if __name__ == "__main__":
    raise SystemExit(main())
