from __future__ import annotations

"""Fail-closed text-layer extraction for Guangzhou physics single-choice questions.

This adapter intentionally handles only the reliable part of a PDF text layer:
question stems followed by an unambiguous A/B/C/D sequence.  Images, tables,
formulae and ambiguous reading order remain source-image review work rather
than being silently converted into incorrect text blocks.
"""

import importlib.util
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


QUESTION_PATTERN = re.compile(r"^\s*(\d{1,2})\s*[\.．、)]\s*(.*)$")
OPTION_PATTERN = re.compile(r"(?<!\S)([A-D])\s*[\.．、]\s*")
OPTION_LABELS = ("A", "B", "C", "D")
SINGLE_CHOICE_TYPES = frozenset({"choice", "single_choice"})
VISUAL_OR_SECTION_TAIL_PATTERN = re.compile(r"(?:图\s*\d+|第\s*[一二三四]部分|填空\s*作图题)")
VISUAL_REFERENCE_PATTERN = re.compile(r"(?:如?图\s*\d*|图示|下图)")
TABLE_REFERENCE_PATTERN = re.compile(r"(?:下表|如下表|表中|表格|根据表)")
SHARED_VISUAL_REFERENCE_PATTERN = re.compile(r"\b(?:MN|OP|OQ|PQ|AB|CD)\b")
LAYOUT_NOISE_PATTERN = re.compile(
    r"(?:考生|物理试卷|第\s*\d+\s*页|第\s*\d+\s*页/共\s*\d+\s*页|学科网|股份有限公司|"
    r"装订|密封|第二部分|二、\s*非选择题|非选择题|[\u4e00-\u9fff]+/[A-Za-z]+\d*)"
)
NOISE_PATTERNS = (
    re.compile(r"^第\s*\d+\s*页"),
    re.compile(r"^\[PAGE\s*\d+\]", re.IGNORECASE),
    re.compile(r"^(?:物理试卷|考生号|装订线)"),
)


@dataclass(frozen=True)
class ChoiceExtractionResult:
    drafts: dict[int, dict[str, Any]]
    blockers: dict[int, str]


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def clean_layout_artifacts(value: str) -> str:
    """Remove only known margin/header remnants from the text-layer output."""
    cleaned = normalize_text(value)
    cleaned = re.sub(r"\s*(?:考生号|姓名|装订线|密封线)\s*[：:].*$", "", cleaned)
    cleaned = re.sub(r"\s*物理试卷\s*第\s*\d+\s*页.*$", "", cleaned)
    cleaned = re.sub(r"\s*(?:订|线|封)\s*$", "", cleaned)
    return normalize_text(cleaned)


def is_single_choice(question_type: str) -> bool:
    return normalize_text(question_type).lower() in SINGLE_CHOICE_TYPES


def is_noise_block(block: dict[str, Any]) -> bool:
    text = normalize_text(str(block.get("textPreview") or ""))
    return not text or any(pattern.search(text) for pattern in NOISE_PATTERNS)


def question_segments(pages: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
    """Group worker layout blocks from one numbered stem through the next stem."""
    segments: dict[int, list[dict[str, Any]]] = {}
    current_number: int | None = None
    for page in pages:
        for block in page.get("layoutBlocks") or []:
            if is_noise_block(block):
                continue
            text = normalize_text(str(block.get("textPreview") or ""))
            match = QUESTION_PATTERN.match(text) if block.get("blockType") == "question_stem" else None
            if match:
                current_number = int(match.group(1))
                segments[current_number] = [block]
            elif current_number is not None:
                segments[current_number].append(block)
    return segments


def extract_parts(blocks: list[dict[str, Any]]) -> tuple[str, list[tuple[str, str]], list[dict[str, Any]]]:
    """Return stem, labelled options and source blocks without inferring any layout."""
    source_text = " ".join(normalize_text(str(block.get("textPreview") or "")) for block in blocks)
    question_match = QUESTION_PATTERN.match(source_text)
    if not question_match:
        return "", [], blocks
    remainder = question_match.group(2)
    markers = list(OPTION_PATTERN.finditer(remainder))
    stem = clean_layout_artifacts(remainder[: markers[0].start()] if markers else remainder)
    options: list[tuple[str, str]] = []
    for index, marker in enumerate(markers):
        value_end = markers[index + 1].start() if index + 1 < len(markers) else len(remainder)
        value = clean_layout_artifacts(remainder[marker.end() : value_end])
        options.append((marker.group(1), value))
    return stem, options, blocks


def build_draft(stem: str, options: list[tuple[str, str]], blocks: list[dict[str, Any]]) -> dict[str, Any]:
    source_regions = [
        block.get("sourceRegion")
        for block in blocks
        if isinstance(block.get("sourceRegion"), dict)
    ]
    return {
        "stem": stem,
        "options": [
            {
                "label": label,
                "text": text,
                "reviewStatus": "pending_review",
            }
            for label, text in options
        ],
        "structuredExtraction": {
            "adapter": "pdftotext_layout",
            "reviewStatus": "pending_review",
            "sourceRegions": source_regions,
        },
    }


def extract_single_choice_drafts(
    pages: list[dict[str, Any]], question_types: dict[int, str]
) -> ChoiceExtractionResult:
    """Extract only complete and ordered A/B/C/D sequences for choice questions."""
    drafts: dict[int, dict[str, Any]] = {}
    blockers: dict[int, str] = {}
    for number, question_type in sorted(question_types.items()):
        if not is_single_choice(question_type):
            continue
        blocks = question_segments(pages).get(number)
        if not blocks:
            blockers[number] = "question_stem_not_found_in_pdf_text_layer"
            continue
        stem, options, source_blocks = extract_parts(blocks)
        labels = [label for label, _ in options]
        if not stem:
            blockers[number] = "choice_stem_empty"
        elif labels != list(OPTION_LABELS):
            blockers[number] = "choice_option_order_ambiguous"
        elif any(not text for _, text in options):
            blockers[number] = "choice_options_incomplete"
        elif VISUAL_REFERENCE_PATTERN.search(stem):
            blockers[number] = "visual_content_requires_layout_adapter"
        elif TABLE_REFERENCE_PATTERN.search(stem):
            blockers[number] = "table_requires_structure_adapter"
        elif SHARED_VISUAL_REFERENCE_PATTERN.search(stem):
            blockers[number] = "shared_visual_context_requires_layout_adapter"
        elif len(re.sub(r"\W", "", stem)) < 6:
            blockers[number] = "choice_stem_too_short"
        elif LAYOUT_NOISE_PATTERN.search(stem):
            blockers[number] = "choice_text_contains_layout_noise"
        elif any(VISUAL_OR_SECTION_TAIL_PATTERN.search(text) for _, text in options):
            blockers[number] = "visual_content_requires_layout_adapter"
        elif any(LAYOUT_NOISE_PATTERN.search(text) or re.search(r"\s\d{1,2}$", text) for _, text in options):
            blockers[number] = "choice_text_contains_layout_noise"
        else:
            drafts[number] = build_draft(stem, options, source_blocks)
    return ChoiceExtractionResult(drafts=drafts, blockers=blockers)


def parse_pdf_text_layer(path: Path) -> list[dict[str, Any]]:
    worker_path = Path(__file__).resolve().parents[1] / "workers" / "document" / "worker.py"
    spec = importlib.util.spec_from_file_location("kqg_document_worker_for_choice_extraction", worker_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"document_worker_import_failed:{worker_path}")
    worker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(worker)
    pages, warnings = worker.parse_pdf_with_pdftotext(path)
    if warnings:
        raise ValueError("pdf_text_layer_unavailable:" + ";".join(warnings))
    return pages


def write_report(result: ChoiceExtractionResult, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "status": "pass",
        "adapter": "pdftotext_layout",
        "reviewStatus": "pending_review",
        "eligibleQuestions": sorted(result.drafts),
        "blockers": result.blockers,
        "drafts": result.drafts,
        "boundary": "Only complete A/B/C/D sequences are drafts. Visual, table, formula and ambiguous layout content remains source-image review work.",
    }
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
