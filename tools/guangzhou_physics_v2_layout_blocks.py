"""Minimal coordinate-preserving layout contract for Guangzhou exam questions."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Iterable

import fitz

from guangzhou_physics_v2_materialize import RegionPlan, YearRegionPlan, stable_id


QUESTION_PATTERN = re.compile(r"^\s*(\d{1,2})\s*[.．、)]\s*(.*)$")
OPTION_PATTERN = re.compile(r"(?:^|\s)([A-D])\s*[.．、]\s*")
SUBQUESTION_PATTERN = re.compile(r"[（(]([1-9一二三四五六七八九十]+)[）)]|([①②③④⑤⑥⑦⑧⑨⑩])")
FORMULA_PATTERN = re.compile(
    r"(?:[ρpPUIRQFvsm]\s*[₁₂12']*\s*=|=\s*[0-9_]+|×\s*10|N/kg|kg/m|J/|W/|Ω|公式\s*[_＿]+)",
    re.IGNORECASE,
)
VISUAL_REFERENCE_PATTERN = re.compile(r"(?:如?图\s*\d*|图示|下图)")
TABLE_REFERENCE_PATTERN = re.compile(r"(?:下表|如下表|表中|表格|根据表)")
NOISE_PATTERNS = (
    re.compile(r"^第\s*\d+\s*页(?:\s*/\s*共\s*\d+\s*页|\s*共\s*\d+\s*页)?$"),
    re.compile(r"^物理试卷\s*第?\s*\d+\s*页"),
    re.compile(r"^学科网（北京）股份有限公司$"),
    re.compile(r"^(?:考生号[:：]?|姓名[:：]?|装订线|密封线|订|线|封)$"),
    re.compile(r"^[.．…]+$"),
)


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def point_bbox(rect: fitz.Rect) -> dict[str, Any]:
    return {
        "x": round(float(rect.x0), 3),
        "y": round(float(rect.y0), 3),
        "width": round(float(max(0, rect.width)), 3),
        "height": round(float(max(0, rect.height)), 3),
        "unit": "point",
    }


def region_rect(page: fitz.Page, region: RegionPlan) -> fitz.Rect:
    x, y, width, height = region.bbox_percent
    return fitz.Rect(
        page.rect.width * x / 100,
        page.rect.height * y / 100,
        page.rect.width * (x + width) / 100,
        page.rect.height * (y + height) / 100,
    )


def is_noise(text: str) -> bool:
    normalized = normalize_text(text)
    return not normalized or any(pattern.fullmatch(normalized) for pattern in NOISE_PATTERNS)


def option_parts(text: str) -> list[tuple[str, str]]:
    matches = list(OPTION_PATTERN.finditer(normalize_text(text)))
    result: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        value = normalize_text(text[match.end() : end])
        if value:
            result.append((match.group(1), value))
    return result


def subquestion_labels(text: str) -> list[str]:
    return [match.group(1) or match.group(2) for match in SUBQUESTION_PATTERN.finditer(text)]


def source_region_id(year: int, question_number: int, region_index: int) -> str:
    return str(stable_id("question-region", year, question_number, region_index))


def asset_reference(region: RegionPlan, region_index: int) -> dict[str, Any]:
    return {
        "kind": "question_crop",
        "regionIndex": region_index,
        "relativePath": region.relative_path,
    }


def text_lines(page: fitz.Page, clip: fitz.Rect) -> list[tuple[fitz.Rect, str]]:
    result: list[tuple[fitz.Rect, str]] = []
    data = page.get_text("dict", clip=clip, sort=True)
    for block in data.get("blocks", []):
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            text = normalize_text("".join(str(span.get("text") or "") for span in line.get("spans", [])))
            if text:
                result.append((fitz.Rect(line.get("bbox", (0, 0, 0, 0))), text))
    return result


def table_blocks(page: fitz.Page, clip: fitz.Rect) -> list[tuple[fitz.Rect, list[list[str | None]]]]:
    try:
        tables = page.find_tables(clip=clip).tables
    except Exception:
        return []
    return [(fitz.Rect(table.bbox), table.extract()) for table in tables]


def _base_block(
    *,
    year: int,
    question_number: int,
    region_index: int,
    page_number: int,
    rect: fitz.Rect,
    block_type: str,
    region: RegionPlan,
    text: str = "",
) -> dict[str, Any]:
    return {
        "paper": f"guangzhou-physics-{year}",
        "year": year,
        "questionNumber": question_number,
        "sourceRegionId": source_region_id(year, question_number, region_index),
        "pageNumber": page_number,
        "bbox": point_bbox(rect),
        "blockType": block_type,
        "readingOrder": -1,
        "text": text,
        "assetReference": asset_reference(region, region_index),
        "_sort": (page_number, region_index, round(rect.y0, 3), round(rect.x0, 3)),
    }


def build_question_layout(
    pdf_path: Path,
    plan: YearRegionPlan,
    question_number: int,
) -> dict[str, Any]:
    """Build blocks only inside the already reviewed question regions."""
    blocks: list[dict[str, Any]] = []
    labels: list[str] = []
    source_regions: list[dict[str, Any]] = []
    with fitz.open(pdf_path) as document:
        for region_index, region in enumerate(plan.questions[question_number], start=1):
            page = document[region.page_number - 1]
            clip = region_rect(page, region)
            region_id = source_region_id(plan.year, question_number, region_index)
            reference = asset_reference(region, region_index)
            source_regions.append(
                {
                    "sourceRegionId": region_id,
                    "pageNumber": region.page_number,
                    "bboxPercent": list(region.bbox_percent),
                    "assetReference": reference,
                }
            )

            lines = text_lines(page, clip)
            region_text = " ".join(text for _, text in lines)
            detected_tables = table_blocks(page, clip) if TABLE_REFERENCE_PATTERN.search(region_text) else []
            for table_rect, rows in detected_tables:
                block = _base_block(
                    year=plan.year,
                    question_number=question_number,
                    region_index=region_index,
                    page_number=region.page_number,
                    rect=table_rect,
                    block_type="table",
                    region=region,
                )
                block["table"] = {"rows": rows}
                blocks.append(block)

            for rect, text in lines:
                labels.extend(subquestion_labels(text))
                if is_noise(text):
                    blocks.append(
                        _base_block(
                            year=plan.year,
                            question_number=question_number,
                            region_index=region_index,
                            page_number=region.page_number,
                            rect=rect,
                            block_type="noise",
                            region=region,
                            text=text,
                        )
                    )
                    continue
                options = option_parts(text)
                if options:
                    for option_index, (label, value) in enumerate(options):
                        block = _base_block(
                            year=plan.year,
                            question_number=question_number,
                            region_index=region_index,
                            page_number=region.page_number,
                            rect=rect,
                            block_type="option",
                            region=region,
                            text=value,
                        )
                        block["optionLabel"] = label
                        block["_sort"] = (*block["_sort"], option_index)
                        blocks.append(block)
                    prefix = normalize_text(text[: OPTION_PATTERN.search(text).start()]) if OPTION_PATTERN.search(text) else ""
                    if not prefix:
                        continue
                    text = prefix

                match = QUESTION_PATTERN.match(text)
                block_type = "stem" if match and int(match.group(1)) == question_number else "text"
                if FORMULA_PATTERN.search(text):
                    block_type = "formula"
                elif subquestion_labels(text) and block_type != "stem":
                    block_type = "subquestion"
                block = _base_block(
                    year=plan.year,
                    question_number=question_number,
                    region_index=region_index,
                    page_number=region.page_number,
                    rect=rect,
                    block_type=block_type,
                    region=region,
                    text=text,
                )
                if match:
                    block["originalQuestionNumber"] = int(match.group(1))
                blocks.append(block)

            if VISUAL_REFERENCE_PATTERN.search(region_text):
                block = _base_block(
                    year=plan.year,
                    question_number=question_number,
                    region_index=region_index,
                    page_number=region.page_number,
                    rect=clip,
                    block_type="image",
                    region=region,
                )
                block["image"] = {"mode": "full_question_crop", "ownership": "question"}
                block["_sort"] = (region.page_number, region_index, clip.y1, clip.x0)
                blocks.append(block)

    blocks.sort(key=lambda block: block["_sort"])
    for reading_order, block in enumerate(blocks):
        block["readingOrder"] = reading_order
        block.pop("_sort", None)

    content_blocks = [block for block in blocks if block["blockType"] != "noise"]
    return {
        "contractVersion": "guangzhou-question-layout.v1",
        "paper": f"guangzhou-physics-{plan.year}",
        "year": plan.year,
        "questionNumber": question_number,
        "originalQuestionNumber": question_number,
        "sourceDocumentId": str(plan.source_document_id),
        "sourceRegions": source_regions,
        "blocks": blocks,
        "contentText": normalize_text(" ".join(block["text"] for block in content_blocks if block.get("text"))),
        "noiseText": normalize_text(" ".join(block["text"] for block in blocks if block["blockType"] == "noise")),
        "subquestionLabels": labels,
        "reviewStatus": "pending_review",
        "productionEligible": False,
    }


def build_layouts(
    source_root: Path,
    plans: dict[int, YearRegionPlan],
    questions: Iterable[tuple[int, int]],
) -> dict[tuple[int, int], dict[str, Any]]:
    return {
        (year, question_number): build_question_layout(
            source_root / plans[year].source_file,
            plans[year],
            question_number,
        )
        for year, question_number in questions
    }
