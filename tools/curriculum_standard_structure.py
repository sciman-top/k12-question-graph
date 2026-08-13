from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
import re
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from pypdf import PdfReader


SCHEMA_VERSION = "curriculum-standard-structure.v1"
REPORT_SCHEMA_VERSION = "cek006-curriculum-standard-structure.v1"
FIXTURE_SCHEMA_VERSION = "curriculum-standard-structure-fixture.v1"
REQUIREMENT_SCHEMA_VERSION = "curriculum-requirement.v1"
STABLE_ID_PREFIX = "CR-PHY-JM-2022R2025"
HIERARCHY_ID_PREFIX = "CS-PHY-JM-2022R2025"
DEFAULT_PAGE_MAPPING = {
    "coverPdfPage": 1,
    "explicitPrintedPages": {"2": 1, "3": 2},
    "stableOffset": {"pdfPageStart": 4, "printedPageOffset": -3},
}
PRIMARY_TITLES = {
    "一": ("1", "物质"),
    "二": ("2", "运动和相互作用"),
    "三": ("3", "能量"),
    "四": ("4", "实验探究"),
    "五": ("5", "跨学科实践"),
}
REQUIREMENT_TYPES = {
    "1": "content_requirement",
    "2": "content_requirement",
    "3": "content_requirement",
    "4": "required_experiment",
    "5": "cross_disciplinary_practice",
}
PRIMARY_HEADING_RE = re.compile(r"^\(([一二三四五])\)(.+)$")
TERTIARY_RE = re.compile(
    r"^\s*([1-5])\s*[.]\s*([0-9]+)\s*[.]\s*([0-9]+)\s*(.*)$"
)
SECONDARY_RE = re.compile(r"^\s*([1-5])\s*[.]\s*([0-9]+)\s*(.*)$")
EXAMPLE_RE = re.compile(r"^例\s+")


class StructureExtractionError(RuntimeError):
    pass


@dataclass
class RequirementAccumulator:
    code: str
    primary_code: str | None
    primary_title: str | None
    secondary_code: str | None
    secondary_title: str | None
    fragments: list[dict[str, Any]] = field(default_factory=list)

    def add_line(self, page_number: int, text: str) -> None:
        if not text.strip():
            return
        if not self.fragments or self.fragments[-1]["pdf_page_number"] != page_number:
            self.fragments.append({"pdf_page_number": page_number, "lines": []})
        self.fragments[-1]["lines"].append(text)


def normalize_lf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def compact_text(text: str) -> str:
    return "".join(text.split())


def sha256_text(text: str) -> str:
    return hashlib.sha256(normalize_lf(text).encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def printed_page_number(pdf_page_number: int, mapping: dict[str, Any]) -> int | None:
    explicit = mapping.get("explicitPrintedPages", {})
    if str(pdf_page_number) in explicit:
        return int(explicit[str(pdf_page_number)])
    stable = mapping.get("stableOffset", {})
    start = int(stable.get("pdfPageStart", 0))
    if pdf_page_number >= start:
        return pdf_page_number + int(stable.get("printedPageOffset", 0))
    return None


def _is_page_footer(raw: str, page_number: int, mapping: dict[str, Any]) -> bool:
    printed = printed_page_number(page_number, mapping)
    return printed is not None and compact_text(raw) == str(printed)


def _is_supplemental_boundary(raw: str) -> bool:
    stripped = raw.strip()
    compact = compact_text(raw)
    return bool(EXAMPLE_RE.match(stripped)) or compact.startswith("活动建议：")


def _evidence_anchor(
    *,
    source: dict[str, str],
    page_number: int,
    mapping: dict[str, Any],
    section_path: list[str],
    official_item_code: str | None,
    block_text: str,
) -> dict[str, Any]:
    return {
        "source_document_id": source["source_document_id"],
        "source_region_id": None,
        "source_document_version": source["source_document_version"],
        "source_document_sha256": source["source_document_sha256"],
        "pdf_page_number": page_number,
        "printed_page_number": printed_page_number(page_number, mapping),
        "section_path": section_path,
        "official_item_code": official_item_code,
        "text_block_sha256": sha256_text(block_text),
        "evidence_role": "curriculum_requirement_source",
    }


def _hierarchy_node(
    *,
    level: int,
    code: str,
    title: str,
    parent_stable_id: str | None,
    page_number: int,
    source: dict[str, str],
    mapping: dict[str, Any],
    section_path: list[str],
) -> dict[str, Any]:
    return {
        "record_type": "curriculum_theme",
        "level": level,
        "stable_id": f"{HIERARCHY_ID_PREFIX}-{code}",
        "parent_stable_id": parent_stable_id,
        "official_item_code": code,
        "title": title,
        "evidence_anchor": _evidence_anchor(
            source=source,
            page_number=page_number,
            mapping=mapping,
            section_path=section_path,
            official_item_code=code,
            block_text=title,
        ),
    }


def _build_requirement(
    accumulator: RequirementAccumulator,
    source: dict[str, str],
    mapping: dict[str, Any],
) -> dict[str, Any]:
    if not accumulator.secondary_code or not accumulator.secondary_title:
        raise StructureExtractionError(
            f"official item {accumulator.code} has no secondary theme parent"
        )
    fragment_texts: list[str] = []
    anchors: list[dict[str, Any]] = []
    section_path = [
        "四、课程内容",
        accumulator.primary_title or accumulator.primary_code or "unknown",
        accumulator.secondary_title,
        accumulator.code,
    ]
    for fragment in accumulator.fragments:
        fragment_text = compact_text("".join(fragment["lines"]))
        if not fragment_text:
            continue
        fragment_texts.append(fragment_text)
        anchors.append(
            _evidence_anchor(
                source=source,
                page_number=int(fragment["pdf_page_number"]),
                mapping=mapping,
                section_path=section_path,
                official_item_code=accumulator.code,
                block_text=fragment_text,
            )
        )
    source_text = "".join(fragment_texts)
    if not source_text or not anchors:
        raise StructureExtractionError(f"official item {accumulator.code} has no source text")
    return {
        "schema_version": REQUIREMENT_SCHEMA_VERSION,
        "record_type": "curriculum_requirement",
        "stable_id": f"{STABLE_ID_PREFIX}-{accumulator.code}",
        "parent_stable_id": f"{HIERARCHY_ID_PREFIX}-{accumulator.secondary_code}",
        "standard_version": source["source_document_version"],
        "official_item_code": accumulator.code,
        "requirement_type": REQUIREMENT_TYPES.get(
            accumulator.primary_code or "", "content_requirement"
        ),
        "source_text": source_text,
        "behavior_verbs": [],
        "cognitive_demands": [],
        "ability_dimensions": [],
        "knowledge_stable_ids": [],
        "evidence_anchors": anchors,
        "confidence": 0.95,
        "status": "candidate",
        "review_status": "pending_review",
        "production_eligible": False,
        "facets": [],
    }


def parse_curriculum_content(
    page_texts: list[str],
    source: dict[str, str],
    mapping: dict[str, Any] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    mapping = mapping or DEFAULT_PAGE_MAPPING
    primary_nodes: list[dict[str, Any]] = []
    secondary_nodes: list[dict[str, Any]] = []
    requirements: list[dict[str, Any]] = []
    current_primary: dict[str, Any] | None = None
    current_secondary: dict[str, Any] | None = None
    current_requirement: RequirementAccumulator | None = None
    in_content_requirements = False

    def finalize_requirement() -> None:
        nonlocal current_requirement
        if current_requirement is not None:
            requirements.append(_build_requirement(current_requirement, source, mapping))
            current_requirement = None

    for page_number, page_text in enumerate(page_texts, 1):
        for raw in page_text.splitlines():
            compact = compact_text(raw)
            if not compact or _is_page_footer(raw, page_number, mapping):
                continue

            primary_match = PRIMARY_HEADING_RE.match(compact) if page_number >= 4 else None
            if primary_match:
                expected = PRIMARY_TITLES.get(primary_match.group(1))
                if expected and primary_match.group(2) == expected[1]:
                    finalize_requirement()
                    primary_code, primary_title = expected
                    current_primary = _hierarchy_node(
                        level=1,
                        code=primary_code,
                        title=primary_title,
                        parent_stable_id=None,
                        page_number=page_number,
                        source=source,
                        mapping=mapping,
                        section_path=["四、课程内容", primary_title],
                    )
                    primary_nodes.append(current_primary)
                    current_secondary = None
                    in_content_requirements = False
                    continue

            if compact == "【内容要求】":
                finalize_requirement()
                in_content_requirements = current_primary is not None
                current_secondary = None
                continue
            if compact.startswith("【") and compact != "【内容要求】":
                finalize_requirement()
                in_content_requirements = False
                current_secondary = None
                continue
            if not in_content_requirements:
                continue

            tertiary_match = TERTIARY_RE.match(raw)
            if tertiary_match:
                finalize_requirement()
                code = ".".join(tertiary_match.group(index) for index in (1, 2, 3))
                current_requirement = RequirementAccumulator(
                    code=code,
                    primary_code=current_primary["official_item_code"] if current_primary else None,
                    primary_title=current_primary["title"] if current_primary else None,
                    secondary_code=(
                        current_secondary["official_item_code"] if current_secondary else None
                    ),
                    secondary_title=current_secondary["title"] if current_secondary else None,
                )
                current_requirement.add_line(page_number, tertiary_match.group(4))
                continue

            secondary_match = SECONDARY_RE.match(raw)
            if secondary_match and not secondary_match.group(3).lstrip().startswith("."):
                title = compact_text(secondary_match.group(3))
                if title:
                    finalize_requirement()
                    code = f"{secondary_match.group(1)}.{secondary_match.group(2)}"
                    current_secondary = _hierarchy_node(
                        level=2,
                        code=code,
                        title=title,
                        parent_stable_id=(
                            current_primary["stable_id"] if current_primary else None
                        ),
                        page_number=page_number,
                        source=source,
                        mapping=mapping,
                        section_path=[
                            "四、课程内容",
                            current_primary["title"] if current_primary else "unknown",
                            title,
                        ],
                    )
                    secondary_nodes.append(current_secondary)
                    continue

            if _is_supplemental_boundary(raw):
                finalize_requirement()
                continue
            if current_requirement is not None:
                current_requirement.add_line(page_number, raw)

    finalize_requirement()
    return {
        "primary_themes": primary_nodes,
        "secondary_themes": secondary_nodes,
        "requirements": requirements,
    }


def _duplicates(values: list[str]) -> list[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return sorted(duplicates)


def requirement_set_digest(requirements: list[dict[str, Any]]) -> str:
    rows = []
    for requirement in sorted(
        requirements,
        key=lambda item: tuple(
            int(part) for part in item["official_item_code"].split(".")
        ),
    ):
        rows.append(
            {
                "officialItemCode": requirement["official_item_code"],
                "sourceTextSha256": sha256_text(requirement["source_text"]),
                "pdfPageNumbers": [
                    anchor["pdf_page_number"]
                    for anchor in requirement["evidence_anchors"]
                ],
                "printedPageNumbers": [
                    anchor["printed_page_number"]
                    for anchor in requirement["evidence_anchors"]
                ],
                "textBlockSha256": [
                    anchor["text_block_sha256"]
                    for anchor in requirement["evidence_anchors"]
                ],
            }
        )
    payload = json.dumps(
        rows,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return sha256_text(payload)


def _validate_hierarchy(
    parsed: dict[str, list[dict[str, Any]]],
    fixture: dict[str, Any],
) -> list[str]:
    expected = fixture["expected"]
    issues: list[str] = []
    primary_nodes = parsed["primary_themes"]
    secondary_nodes = parsed["secondary_themes"]
    requirements = parsed["requirements"]
    primary_codes = [item["official_item_code"] for item in primary_nodes]
    secondary_codes = [item["official_item_code"] for item in secondary_nodes]
    requirement_codes = [item["official_item_code"] for item in requirements]

    for code in _duplicates(primary_codes):
        issues.append(f"duplicate primary theme code: {code}")
    for code in _duplicates(secondary_codes):
        issues.append(f"duplicate secondary theme code: {code}")
    for code in _duplicates(requirement_codes):
        issues.append(f"duplicate official item code: {code}")

    actual_primary = {
        item["official_item_code"]: (
            item["title"],
            item["evidence_anchor"]["pdf_page_number"],
        )
        for item in primary_nodes
    }
    expected_primary = {
        item["code"]: (item["title"], item["headingPdfPage"])
        for item in expected["primaryThemes"]
    }
    if actual_primary != expected_primary:
        issues.append(
            f"primary theme mismatch: expected {expected_primary}, actual {actual_primary}"
        )

    actual_secondary = {
        item["official_item_code"]: (
            item["title"],
            item["parent_stable_id"],
            item["evidence_anchor"]["pdf_page_number"],
        )
        for item in secondary_nodes
    }
    expected_secondary = {
        item["code"]: (
            item["title"],
            f"{HIERARCHY_ID_PREFIX}-{item['parentCode']}",
            item["headingPdfPage"],
        )
        for item in expected["secondaryThemes"]
    }
    if actual_secondary != expected_secondary:
        issues.append(
            f"secondary theme mismatch: expected {expected_secondary}, actual {actual_secondary}"
        )

    expected_codes: set[str] = set()
    for secondary in expected["secondaryThemes"]:
        code = secondary["code"]
        count = int(secondary["officialRequirementCount"])
        expected_codes.update(f"{code}.{index}" for index in range(1, count + 1))
        actual_count = sum(
            requirement["parent_stable_id"] == f"{HIERARCHY_ID_PREFIX}-{code}"
            for requirement in requirements
        )
        if actual_count != count:
            issues.append(
                f"secondary theme {code} expected {count} official items, found {actual_count}"
            )
    missing = sorted(expected_codes - set(requirement_codes))
    unexpected = sorted(set(requirement_codes) - expected_codes)
    if missing:
        issues.append(f"missing official item codes: {', '.join(missing)}")
    if unexpected:
        issues.append(f"unexpected official item codes: {', '.join(unexpected)}")

    counts = {
        "primary": len(primary_nodes),
        "secondary": len(secondary_nodes),
        "requirements": len(requirements),
    }
    expected_counts = {
        "primary": int(expected["primaryThemeCount"]),
        "secondary": int(expected["secondaryThemeCount"]),
        "requirements": int(expected["officialRequirementCount"]),
    }
    if counts != expected_counts:
        issues.append(f"structure count mismatch: expected {expected_counts}, actual {counts}")

    if "requirementSetSha256" in expected:
        actual_digest = requirement_set_digest(requirements)
        if actual_digest != expected["requirementSetSha256"]:
            issues.append(
                "official requirement set digest drift: "
                f"expected {expected['requirementSetSha256']}, actual {actual_digest}"
            )

    if "multiPageRequirementCodes" in expected:
        actual_multi_page = sorted(
            item["official_item_code"]
            for item in requirements
            if len(item["evidence_anchors"]) > 1
        )
        expected_multi_page = sorted(expected["multiPageRequirementCodes"])
        if actual_multi_page != expected_multi_page:
            issues.append(
                "multi-page requirement mismatch: "
                f"expected {expected_multi_page}, actual {actual_multi_page}"
            )

    requirement_by_code = {
        item["official_item_code"]: item for item in requirements
    }
    for golden in fixture.get("selectedRequirementAnchors", []):
        code = golden["officialItemCode"]
        requirement = requirement_by_code.get(code)
        if requirement is None:
            issues.append(f"selected golden requirement is missing: {code}")
            continue
        actual = {
            "sourceTextSha256": sha256_text(requirement["source_text"]),
            "pdfPageNumbers": [
                anchor["pdf_page_number"]
                for anchor in requirement["evidence_anchors"]
            ],
            "printedPageNumbers": [
                anchor["printed_page_number"]
                for anchor in requirement["evidence_anchors"]
            ],
            "textBlockSha256": [
                anchor["text_block_sha256"]
                for anchor in requirement["evidence_anchors"]
            ],
        }
        expected_anchor = {
            key: golden[key]
            for key in (
                "sourceTextSha256",
                "pdfPageNumbers",
                "printedPageNumbers",
                "textBlockSha256",
            )
        }
        if actual != expected_anchor:
            issues.append(
                f"selected golden requirement drift for {code}: "
                f"expected {expected_anchor}, actual {actual}"
            )

    known_parents = {item["stable_id"] for item in primary_nodes + secondary_nodes}
    for secondary in secondary_nodes:
        if secondary["parent_stable_id"] not in {
            item["stable_id"] for item in primary_nodes
        }:
            issues.append(
                f"secondary theme {secondary['official_item_code']} has an unknown parent"
            )
    for requirement in requirements:
        if requirement["parent_stable_id"] not in known_parents:
            issues.append(
                f"official item {requirement['official_item_code']} has an unknown parent"
            )
        if not requirement["source_text"] or not requirement["evidence_anchors"]:
            issues.append(
                f"official item {requirement['official_item_code']} lacks source evidence"
            )
    return issues


def _build_hierarchy(
    primary_nodes: list[dict[str, Any]],
    secondary_nodes: list[dict[str, Any]],
    requirements: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    hierarchy: list[dict[str, Any]] = []
    for primary in primary_nodes:
        primary_copy = dict(primary)
        primary_copy["children"] = []
        for secondary in secondary_nodes:
            if secondary["parent_stable_id"] != primary["stable_id"]:
                continue
            secondary_copy = dict(secondary)
            secondary_copy["requirement_stable_ids"] = [
                requirement["stable_id"]
                for requirement in requirements
                if requirement["parent_stable_id"] == secondary["stable_id"]
            ]
            primary_copy["children"].append(secondary_copy)
        hierarchy.append(primary_copy)
    return hierarchy


def _page_diagnostics(
    page_texts: list[str], mapping: dict[str, Any]
) -> list[dict[str, Any]]:
    return [
        {
            "pdf_page_number": page_number,
            "printed_page_number": printed_page_number(page_number, mapping),
            "text_character_count": len(text),
            "non_empty": bool(text.strip()),
            "normalized_text_sha256": sha256_text(text),
        }
        for page_number, text in enumerate(page_texts, 1)
    ]


def _base_result(
    source: dict[str, str],
    page_texts: list[str],
    mapping: dict[str, Any],
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "material_id": source["material_id"],
        "source": {
            "source_document_id": source["source_document_id"],
            "source_document_version": source["source_document_version"],
            "source_document_sha256": source["source_document_sha256"],
        },
        "extraction": {
            "adapter": "pypdf_text_layer",
            "extractor": f"pypdf=={importlib.metadata.version('pypdf')}",
            "status": "pass",
            "manual_takeover_required": False,
            "issues": [],
        },
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "ai_run": False,
            "database_write": False,
            "source_region_write": False,
            "knowledge_asset_write": False,
            "c002_active_write": False,
        },
        "page_mapping": mapping,
        "page_diagnostics": _page_diagnostics(page_texts, mapping),
        "hierarchy": [],
        "curriculum_requirements": [],
    }


def extract_structure_from_pages(
    page_texts: list[str],
    source: dict[str, str],
    fixture: dict[str, Any],
    *,
    preflight_issues: list[str] | None = None,
) -> dict[str, Any]:
    mapping = fixture.get("pageMapping", DEFAULT_PAGE_MAPPING)
    result = _base_result(source, page_texts, mapping)
    issues = list(preflight_issues or [])
    try:
        parsed = parse_curriculum_content(page_texts, source, mapping)
        issues.extend(_validate_hierarchy(parsed, fixture))
    except (KeyError, TypeError, ValueError, StructureExtractionError) as exc:
        parsed = {"primary_themes": [], "secondary_themes": [], "requirements": []}
        issues.append(str(exc))
    if issues:
        result["extraction"].update(
            {
                "status": "manual_takeover_required",
                "manual_takeover_required": True,
                "issues": issues,
            }
        )
        return result
    result["hierarchy"] = _build_hierarchy(
        parsed["primary_themes"],
        parsed["secondary_themes"],
        parsed["requirements"],
    )
    result["curriculum_requirements"] = parsed["requirements"]
    return result


def load_fixture(path: Path) -> dict[str, Any]:
    try:
        fixture = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise StructureExtractionError(f"cannot read golden fixture {path}: {exc}") from exc
    if fixture.get("schemaVersion") != FIXTURE_SCHEMA_VERSION:
        raise StructureExtractionError(
            f"unsupported fixture schema: {fixture.get('schemaVersion')}"
        )
    try:
        source = fixture["source"]
        expected = fixture["expected"]
        extractor = fixture["extractor"]
        fixture["pageMapping"]
        fixture["representativePages"]
    except (KeyError, TypeError) as exc:
        raise StructureExtractionError(
            f"golden fixture is missing a required contract field: {exc}"
        ) from exc
    if source.get("sharingAllowed") is not False:
        raise StructureExtractionError(
            "golden fixture must keep the real curriculum source sharingAllowed=false"
        )
    if extractor.get("name") != "pypdf" or not extractor.get("version"):
        raise StructureExtractionError("golden fixture must pin the pypdf extractor")
    if not all(
        int(expected.get(key, 0)) > 0
        for key in (
            "primaryThemeCount",
            "secondaryThemeCount",
            "officialRequirementCount",
        )
    ):
        raise StructureExtractionError("golden fixture structure counts must be positive")
    return fixture


def inspect_pdf(path: Path) -> tuple[dict[str, Any], list[str]]:
    if not path.is_file():
        raise StructureExtractionError(f"source PDF does not exist: {path}")
    with path.open("rb") as stream:
        if stream.read(5) != b"%PDF-":
            raise StructureExtractionError(f"invalid PDF magic: {path}")
    try:
        reader = PdfReader(str(path))
        page_texts = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:
        raise StructureExtractionError(f"cannot extract PDF text: {exc}") from exc
    facts = {
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "sizeBytes": path.stat().st_size,
        "pageCount": len(page_texts),
        "textCharacterCount": sum(len(text) for text in page_texts),
        "nonEmptyPageCount": sum(bool(text.strip()) for text in page_texts),
        "extractor": f"pypdf=={importlib.metadata.version('pypdf')}",
    }
    return facts, page_texts


def validate_source_fixture(
    facts: dict[str, Any],
    page_texts: list[str],
    fixture: dict[str, Any],
) -> tuple[list[str], list[dict[str, Any]]]:
    source = fixture["source"]
    expected_facts = {
        "sha256": source["sourceDocumentSha256"],
        "pageCount": source["pageCount"],
        "textCharacterCount": source["textCharacterCount"],
        "nonEmptyPageCount": source["nonEmptyPageCount"],
        "extractor": f"{fixture['extractor']['name']}=={fixture['extractor']['version']}",
    }
    issues = [
        f"source {key} drift: expected {expected}, actual {facts.get(key)}"
        for key, expected in expected_facts.items()
        if facts.get(key) != expected
    ]
    mapping = fixture["pageMapping"]
    representative_results: list[dict[str, Any]] = []
    for expected_page in fixture["representativePages"]:
        page_number = int(expected_page["pdfPageNumber"])
        page_issues: list[str] = []
        if page_number < 1 or page_number > len(page_texts):
            page_issues.append("page is outside the source PDF")
            text = ""
        else:
            text = page_texts[page_number - 1]
        compact = compact_text(text)
        actual_hash = sha256_text(text)
        if len(text) != int(expected_page["textCharacterCount"]):
            page_issues.append("text character count drift")
        if actual_hash != expected_page["normalizedTextSha256"]:
            page_issues.append("normalized text hash drift")
        actual_printed = printed_page_number(page_number, mapping)
        if actual_printed != expected_page["printedPageNumber"]:
            page_issues.append("printed page mapping drift")
        missing_markers = [
            marker
            for marker in expected_page["requiredMarkers"]
            if compact_text(marker) not in compact
        ]
        if missing_markers:
            page_issues.append(f"missing markers: {', '.join(missing_markers)}")
        if page_issues:
            issues.append(
                f"representative page {page_number} ({expected_page['role']}): "
                + "; ".join(page_issues)
            )
        representative_results.append(
            {
                "role": expected_page["role"],
                "pdfPageNumber": page_number,
                "printedPageNumber": actual_printed,
                "textCharacterCount": len(text),
                "normalizedTextSha256": actual_hash,
                "markerPass": not missing_markers,
                "status": "pass" if not page_issues else "drift",
            }
        )
    return issues, representative_results


def write_json_atomic(value: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def build_report(
    result: dict[str, Any],
    facts: dict[str, Any],
    representative_pages: list[dict[str, Any]],
    candidate_output_path: Path,
) -> dict[str, Any]:
    requirements = result["curriculum_requirements"]
    hierarchy = result["hierarchy"]
    secondary_count = sum(len(theme["children"]) for theme in hierarchy)
    multi_page = [
        item["official_item_code"]
        for item in requirements
        if len(item["evidence_anchors"]) > 1
    ]
    return {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "status": (
            "pass"
            if result["extraction"]["status"] == "pass"
            else "manual_takeover_required"
        ),
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "source": facts,
        "extractor": result["extraction"]["extractor"],
        "goldenFixture": {
            "schemaVersion": FIXTURE_SCHEMA_VERSION,
            "representativePages": representative_pages,
        },
        "structure": {
            "primaryThemeCount": len(hierarchy),
            "secondaryThemeCount": secondary_count,
            "officialRequirementCount": len(requirements),
            "uniqueOfficialItemCodeCount": len(
                {item["official_item_code"] for item in requirements}
            ),
            "requirementSetSha256": requirement_set_digest(requirements),
            "multiPageRequirementCodes": multi_page,
            "primaryThemes": [
                {
                    "code": theme["official_item_code"],
                    "title": theme["title"],
                    "pdfPageNumber": theme["evidence_anchor"]["pdf_page_number"],
                    "secondaryThemeCount": len(theme["children"]),
                    "officialRequirementCount": sum(
                        len(child["requirement_stable_ids"])
                        for child in theme["children"]
                    ),
                }
                for theme in hierarchy
            ],
        },
        "extraction": result["extraction"],
        "candidateOutput": {
            "path": str(candidate_output_path.resolve()),
            "containsVerbatimSourceText": True,
            "mustRemainLocalAndGitIgnored": True,
            "sha256": (
                sha256_file(candidate_output_path)
                if candidate_output_path.is_file()
                else None
            ),
        },
        "governance": result["governance"],
        "verification": {
            "goldenSourceAndHierarchy": (
                "pass"
                if result["extraction"]["status"] == "pass"
                else "manual_takeover_required"
            ),
            "curriculumRequirementSchema": "pending_wrapper_validation",
            "visualReview": "pending_operator_assertion",
        },
        "fullGate": {
            "status": "gate_na",
            "reason": (
                "tools/run-gates.ps1 may affect PostgreSQL and API processes and is "
                "reserved for the separately authorized CEK-34 gate"
            ),
            "alternative_verification": (
                "unit tests, CEK-05 JSON schema validation, golden source/hash/page checks, "
                "roadmap guard, and static hotspot review"
            ),
            "evidence_link": "docs/evidence/cek006-curriculum-standard-structure.json",
            "expires_at": "CEK-34",
            "recovery_condition": (
                "obtain current-task confirmation for PostgreSQL/API process impact and run "
                "tools/run-verification.ps1 -Profile Release -AuthorizeStateful"
            ),
        },
        "rollback": (
            "Delete the ignored local candidate/cache and revert only the CEK-06 "
            "parser, fixture, tests, wrapper, documentation, and evidence files. "
            "The source PDF, SourceDocument, database, and C002 active remain unchanged."
        ),
        "completionBoundary": (
            "CEK-06 proves deterministic structure and EvidenceAnchor candidates only. "
            "It does not create requirement facets or knowledge mappings, write SourceRegion "
            "or domain assets, apply CEK-04, switch C002 active, close REAL005, or establish "
            "teacher/live acceptance."
        ),
    }


def run_extraction(
    source_pdf_path: Path,
    fixture_path: Path,
    candidate_output_path: Path,
    report_path: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    fixture = load_fixture(fixture_path)
    source_fixture = fixture["source"]
    source = {
        "material_id": source_fixture["materialId"],
        "source_document_id": source_fixture["sourceDocumentId"],
        "source_document_version": source_fixture["sourceDocumentVersion"],
        "source_document_sha256": source_fixture["sourceDocumentSha256"],
    }
    facts, page_texts = inspect_pdf(source_pdf_path)
    preflight_issues, representative_pages = validate_source_fixture(
        facts, page_texts, fixture
    )
    result = extract_structure_from_pages(
        page_texts,
        source,
        fixture,
        preflight_issues=preflight_issues,
    )
    write_json_atomic(result, candidate_output_path)
    report = build_report(result, facts, representative_pages, candidate_output_path)
    write_json_atomic(report, report_path)
    return result, report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract the fixed junior-physics curriculum hierarchy candidate"
    )
    parser.add_argument("--source-pdf", required=True)
    parser.add_argument("--fixture", required=True)
    parser.add_argument("--candidate-output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    try:
        result, report = run_extraction(
            Path(args.source_pdf),
            Path(args.fixture),
            Path(args.candidate_output),
            Path(args.report),
        )
    except StructureExtractionError as exc:
        print(
            json.dumps(
                {
                    "status": "manual_takeover_required",
                    "manual_takeover_required": True,
                    "error": str(exc),
                },
                ensure_ascii=False,
            )
        )
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if result["extraction"]["status"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())
