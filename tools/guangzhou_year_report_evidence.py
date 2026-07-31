from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping


TARGET_ID_NAMESPACE = uuid.UUID("2a295d7e-0f66-45a5-8ce1-7b5739cd34bf")
EVIDENCE_ID_NAMESPACE = uuid.UUID("80e54edf-6058-4c06-a299-d6b05df7902b")
MISSING_TEXT_MARKERS = ("未检索到明确", "已核验为缺项", "无明确教学建议")


def deterministic_uuid(namespace: uuid.UUID, value: str) -> str:
    return str(uuid.uuid5(namespace, value))


def parse_page_number(location: str) -> int | None:
    match = re.search(r"(?:年报|报告)?\s*[pP]\s*(\d+)", location or "")
    return int(match.group(1)) if match else None


def normalized_text(value: str) -> str:
    return re.sub(r"\s+", "", value or "").replace("…", "").replace("...", "")


def page_supports_summary(page_text: str, summary: str) -> bool:
    page = normalized_text(page_text)
    candidate = normalized_text(summary)
    if not candidate or any(marker in summary for marker in MISSING_TEXT_MARKERS):
        return False
    chunks = [candidate[index:index + 16] for index in range(0, max(1, len(candidate) - 15), 8)]
    return any(len(chunk) >= 12 and chunk in page for chunk in chunks)


def page_contains_number(page_text: str, raw_value: str) -> bool:
    raw = (raw_value or "").strip()
    return bool(raw and re.search(rf"(?<![0-9.]){re.escape(raw)}(?![0-9.])", page_text))


def parse_optional_float(raw: str) -> float | None:
    value = (raw or "").strip()
    return float(value) if value else None


def parse_option_distribution(raw: str) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    for part in re.split(r"[;；]", raw or ""):
        if not part.strip():
            continue
        match = re.fullmatch(r"\s*([^:：]+)\s*[:：]\s*([0-9.]+)\s*(%?)\s*[。.]?\s*", part)
        if not match:
            raise ValueError(f"invalid_option_distribution_part:{part.strip()}")
        values.append({
            "label": match.group(1).strip(),
            "raw_value": match.group(2),
            "parsed_value": float(match.group(2)),
            "unit": "percent" if match.group(3) else "ratio",
        })
    return values


def _anchor(
    source_document_id: str,
    source_sha256: str,
    year: int,
    question_number: int,
    page_number: int,
    page_text: str,
    role: str,
    source_region_id: str | None,
) -> dict[str, Any]:
    return {
        "source_document_id": source_document_id,
        "source_region_id": source_region_id,
        "source_document_version": f"sha256:{source_sha256[:12]}",
        "source_document_sha256": source_sha256,
        "pdf_page_number": page_number,
        "printed_page_number": None,
        "section_path": ["试题分析", f"第{question_number}题"],
        "official_item_code": f"QPHY-C003-{year}-{question_number:02d}",
        "text_block_sha256": hashlib.sha256(page_text.encode("utf-8")).hexdigest(),
        "evidence_role": role,
    }


def metric_page_number(
    row: Mapping[str, str],
    metric_label: str,
    raw_value: str,
    primary_page: int,
    pages: list[str],
) -> int | None:
    if primary_page <= len(pages) and page_contains_number(pages[primary_page - 1], raw_value):
        return primary_page
    notes = row.get("notes", "")
    match = re.search(rf"{re.escape(metric_label)}来自[^;；]*?[pP](\d+)", notes)
    if match:
        candidate = int(match.group(1))
        if candidate <= len(pages) and page_contains_number(pages[candidate - 1], raw_value):
            return candidate
    return None


def _scope(target: Mapping[str, Any]) -> dict[str, Any]:
    return dict(target["question_scope"])


def _metric(raw: str, unit: str, direction: str, anchor: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "raw_value": raw.strip(),
        "parsed_value": float(raw),
        "unit": unit,
        "scale_direction": direction,
        "sample_scope": "report-defined examination cohort",
        "sample_size": None,
        "anchor": dict(anchor),
    }


def _question_section(
    pages: list[str], question_number: int, start_page: int, next_question_number: int | None, next_page: int | None
) -> str:
    final_page = next_page if next_page is not None else min(len(pages), start_page + 3)
    combined = "\n\f\n".join(pages[start_page - 1:final_page])
    start_match = re.search(rf"(?:^|\n)\s*{question_number}\s*[.．、]\s*", combined)
    start = start_match.start() if start_match else 0
    end = len(combined)
    if next_question_number is not None:
        next_match = re.search(rf"(?:^|\n)\s*{next_question_number}\s*[.．、]\s*", combined[start + 1:])
        if next_match:
            end = start + 1 + next_match.start()
    return combined[start:end]


def _metric_from_section(section: str, label: str) -> str:
    match = re.search(rf"{re.escape(label)}\s*[:：]\s*([0-9]+(?:\.[0-9]+)?)", section)
    return match.group(1) if match else ""


def _metric_page(pages: list[str], label: str, raw_value: str, start_page: int, final_page: int | None) -> int | None:
    if not raw_value:
        return None
    end = final_page if final_page is not None else min(len(pages), start_page + 3)
    for page_number in range(start_page, end + 1):
        page = pages[page_number - 1]
        if label in page and page_contains_number(page, raw_value):
            return page_number
    return None


def derive_missing_observations(
    observations: Iterable[Mapping[str, str]],
    alignment_package: Mapping[str, Any],
    report_pages: Mapping[int, Mapping[str, Any]],
) -> list[dict[str, str]]:
    rows = [dict(row) for row in observations]
    existing = {(int(row["year"]), int(row["question_number"])) for row in rows}
    bundles = sorted(
        alignment_package["bundles"], key=lambda row: (int(row["year"]), int(row["questionNumber"]))
    )
    for index, bundle in enumerate(bundles):
        year = int(bundle["year"])
        number = int(bundle["questionNumber"])
        if (year, number) in existing:
            continue
        anchors = list(bundle.get("reportAnchors") or [])
        if not anchors or anchors[0].get("pageNumber") is None:
            continue
        start_page = int(anchors[0]["pageNumber"])
        next_bundle = bundles[index + 1] if index + 1 < len(bundles) and int(bundles[index + 1]["year"]) == year else None
        next_anchors = list(next_bundle.get("reportAnchors") or []) if next_bundle else []
        next_page = int(next_anchors[0]["pageNumber"]) if next_anchors and next_anchors[0].get("pageNumber") else None
        pages = list(report_pages[year]["pages"])
        section = _question_section(
            pages,
            number,
            start_page,
            int(next_bundle["questionNumber"]) if next_bundle else None,
            next_page,
        )
        difficulty = _metric_from_section(section, "难度")
        discrimination = _metric_from_section(section, "区分度")
        difficulty_page = _metric_page(pages, "难度", difficulty, start_page, next_page)
        discrimination_page = _metric_page(pages, "区分度", discrimination, start_page, next_page)
        summary_match = re.search(r"考查的科学内容\s*[:：]\s*([^\n。]+主题)", section)
        rows.append({
            "year": str(year),
            "question_number": str(number),
            "evidence_locations": f"年报p{start_page};题级SourceRegion候选",
            "official_exam_point_summary": summary_match.group(1).strip() if summary_match else "",
            "difficulty_value": difficulty,
            "discrimination_value": discrimination,
            "option_distribution_summary": "",
            "common_errors_summary": "",
            "teaching_suggestion_summary": "",
            "confidence": "0.72",
            "review_status": "pending_review",
            "production_eligible": "false",
            "generation_method": "report_heading_rule_candidate",
            "notes": ";".join(filter(None, (
                f"难度来自年报p{difficulty_page}" if difficulty_page else "",
                f"区分度来自年报p{discrimination_page}" if discrimination_page else "",
                f"rule_candidate_section_start=p{start_page}",
            ))),
        })
        existing.add((year, number))
    return rows


def _source_region_for_page(bundle: Mapping[str, Any], page_number: int) -> str | None:
    for anchor in bundle.get("reportAnchors") or []:
        if int(anchor.get("pageNumber") or 0) == page_number:
            return str(anchor["sourceRegionId"])
    return None


def build_package(
    observations: Iterable[Mapping[str, str]],
    alignment_package: Mapping[str, Any],
    target_package: Mapping[str, Any],
    report_pages: Mapping[int, Mapping[str, Any]],
) -> dict[str, Any]:
    bundles = {
        (int(row["year"]), int(row["questionNumber"])): row
        for row in alignment_package["bundles"]
    }
    whole_targets = {
        str(row["question_scope"]["question_item_id"]): row
        for row in target_package["targets"]
        if row["question_scope"]["scope_type"] == "whole_question"
    }
    observed_keys: set[tuple[int, int]] = set()
    performance: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    recommendations: list[dict[str, Any]] = []
    reviews: list[dict[str, Any]] = []
    missing_fields: Counter[str] = Counter()

    for source_row in observations:
        row = dict(source_row)
        year = int(row["year"])
        question_number = int(row["question_number"])
        key = (year, question_number)
        if key in observed_keys:
            raise ValueError(f"duplicate_observation:{year}:{question_number}")
        observed_keys.add(key)
        bundle = bundles.get(key)
        if not bundle:
            raise ValueError(f"alignment_bundle_missing:{year}:{question_number}")
        target = whole_targets.get(str(bundle["questionItemId"]))
        if not target:
            raise ValueError(f"whole_question_target_missing:{year}:{question_number}")
        target_id = deterministic_uuid(TARGET_ID_NAMESPACE, str(target["target_id"]))
        report_document = bundle.get("reportDocument") or {}
        source_document_id = str(report_document.get("sourceDocumentId") or "")
        if not source_document_id:
            raise ValueError(f"report_document_missing:{year}:{question_number}")

        report_anchors = list(bundle.get("reportAnchors") or [])
        reasons = ["candidate_only"]
        if not report_anchors:
            reasons.append("report_source_region_not_materialized")
        page_number = parse_page_number(row.get("evidence_locations", ""))
        year_pages = report_pages.get(year, {}).get("pages", [])
        source_sha256 = str(report_pages.get(year, {}).get("sha256") or "")
        page_text = year_pages[page_number - 1] if page_number and page_number <= len(year_pages) else ""
        if not page_text:
            reasons.append("report_page_missing")
            reviews.append(_review(target_id, target, year, question_number, reasons, "blocked"))
            missing_fields["report_page"] += 1
            continue

        difficulty_raw = row.get("difficulty_value", "").strip()
        discrimination_raw = row.get("discrimination_value", "").strip()
        difficulty = None
        discrimination = None
        difficulty_page = metric_page_number(row, "难度", difficulty_raw, page_number, year_pages) if difficulty_raw else None
        if difficulty_raw and difficulty_page:
            parsed = parse_optional_float(difficulty_raw)
            if parsed is not None and 0 <= parsed <= 1:
                performance_anchor = _anchor(source_document_id, source_sha256, year, question_number, difficulty_page, year_pages[difficulty_page - 1], "performance_statistic_source", _source_region_for_page(bundle, difficulty_page))
                difficulty = _metric(difficulty_raw, "ratio", "higher_is_easier", performance_anchor)
            else:
                reasons.append("difficulty_out_of_range")
        elif difficulty_raw:
            reasons.append("difficulty_value_not_found_on_page")
        else:
            missing_fields["difficulty_observed"] += 1

        discrimination_page = metric_page_number(row, "区分度", discrimination_raw, page_number, year_pages) if discrimination_raw else None
        if discrimination_raw and discrimination_page:
            parsed = parse_optional_float(discrimination_raw)
            if parsed is not None and -1 <= parsed <= 1:
                performance_anchor = _anchor(source_document_id, source_sha256, year, question_number, discrimination_page, year_pages[discrimination_page - 1], "performance_statistic_source", _source_region_for_page(bundle, discrimination_page))
                discrimination = _metric(discrimination_raw, "ratio", "higher_is_easier", performance_anchor)
            else:
                reasons.append("discrimination_out_of_range")
        elif discrimination_raw:
            reasons.append("discrimination_value_not_found_on_page")
        else:
            missing_fields["discrimination"] += 1

        option_distribution = None
        option_raw = row.get("option_distribution_summary", "").strip()
        if option_raw and any(marker in option_raw for marker in MISSING_TEXT_MARKERS):
            missing_fields["option_distribution"] += 1
        elif option_raw:
            try:
                option_values = parse_option_distribution(option_raw)
                unit_set = {value["unit"] for value in option_values}
                page_verified = all(page_contains_number(page_text, value["raw_value"]) for value in option_values)
                values_in_range = all(
                    value["parsed_value"] >= 0
                    and (value["unit"] == "count" or value["parsed_value"] <= (1 if value["unit"] == "ratio" else 100))
                    for value in option_values
                )
                if len(unit_set) != 1:
                    reasons.append("option_distribution_mixed_units")
                elif not values_in_range:
                    reasons.append("option_distribution_value_out_of_range")
                elif not page_verified:
                    reasons.append("option_distribution_value_not_found_on_page")
                else:
                    total = sum(value["parsed_value"] for value in option_values)
                    expected = 100.0 if unit_set == {"percent"} else 1.0
                    tolerance = 1.5 if expected == 100 else 0.015
                    if abs(total - expected) > tolerance:
                        reasons.append("option_distribution_sum_anomaly")
                    performance_anchor = _anchor(source_document_id, source_sha256, year, question_number, page_number, page_text, "performance_statistic_source", _source_region_for_page(bundle, page_number))
                    option_distribution = {
                        "values": option_values,
                        "sample_scope": "report-defined examination cohort",
                        "sample_size": None,
                        "anchor": performance_anchor,
                    }
            except ValueError:
                reasons.append("option_distribution_parse_error")
        else:
            missing_fields["option_distribution"] += 1

        if any(value is not None for value in (difficulty, discrimination, option_distribution)):
            evidence_key = f"performance:{year}:{question_number}"
            performance.append({
                "schema_version": "observed-performance-evidence.v1",
                "evidence_id": deterministic_uuid(EVIDENCE_ID_NAMESPACE, evidence_key),
                "assessment_target_id": target_id,
                "question_scope": _scope(target),
                "maximum_score": None,
                "average_score": None,
                "score_rate": None,
                "difficulty_observed": difficulty,
                "discrimination": discrimination,
                "option_distribution": option_distribution,
                "status": "candidate",
                "review_status": "pending_review",
                "production_eligible": False,
            })
        else:
            reasons.append("no_page_verified_performance_metric")

        error_summary = row.get("common_errors_summary", "").strip()
        if error_summary and page_supports_summary(page_text, error_summary):
            error_anchor = _anchor(source_document_id, source_sha256, year, question_number, page_number, page_text, "error_observation_source", _source_region_for_page(bundle, page_number))
            errors.append({
                "schema_version": "observed-error-evidence.v1",
                "evidence_id": deterministic_uuid(EVIDENCE_ID_NAMESPACE, f"error:{year}:{question_number}"),
                "assessment_target_id": target_id,
                "question_scope": _scope(target),
                "record_kind": "summary_candidate",
                "content": error_summary,
                "generation_method": "rules",
                "confidence": min(float(row.get("confidence") or 0.5), 0.95),
                "anchor": error_anchor,
                "status": "candidate",
                "review_status": "pending_review",
                "production_eligible": False,
            })
        elif error_summary:
            reasons.append("error_summary_not_supported_on_page")
        else:
            missing_fields["error_summary"] += 1

        suggestion = row.get("teaching_suggestion_summary", "").strip()
        if suggestion and page_supports_summary(page_text, suggestion):
            recommendation_anchor = _anchor(source_document_id, source_sha256, year, question_number, page_number, page_text, "teaching_recommendation_source", _source_region_for_page(bundle, page_number))
            recommendations.append({
                "schema_version": "teaching-recommendation.v1",
                "recommendation_id": deterministic_uuid(EVIDENCE_ID_NAMESPACE, f"recommendation:{year}:{question_number}"),
                "assessment_target_id": target_id,
                "question_scope": _scope(target),
                "content": suggestion,
                "author_kind": "legacy_candidate",
                "generation_method": "rules",
                "confidence": min(float(row.get("confidence") or 0.5), 0.9),
                "anchor": recommendation_anchor,
                "status": "candidate",
                "review_status": "pending_review",
                "production_eligible": False,
            })
        elif suggestion and not any(marker in suggestion for marker in MISSING_TEXT_MARKERS):
            reasons.append("teaching_suggestion_not_supported_on_page")
        else:
            missing_fields["teaching_recommendation"] += 1

        priority = "blocked" if any(reason.endswith("missing") or "not_found" in reason for reason in reasons) else "high"
        reviews.append(_review(target_id, target, year, question_number, reasons, priority))

    for key, bundle in sorted(bundles.items()):
        if key in observed_keys:
            continue
        target = whole_targets.get(str(bundle["questionItemId"]))
        if not target:
            continue
        target_id = deterministic_uuid(TARGET_ID_NAMESPACE, str(target["target_id"]))
        reviews.append(_review(
            target_id, target, key[0], key[1],
            ["candidate_only", "c003_observation_missing", "report_question_anchor_missing"],
            "blocked",
        ))
        missing_fields["observation"] += 1

    return {
        "schema_version": "guangzhou-year-report-evidence.v1",
        "mode": "draft_test",
        "generation": {
            "method": "deterministic_pdf_page_verification",
            "external_model_calls": 0,
        },
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "database_write": False,
            "active_write": False,
        },
        "observed_performance": performance,
        "observed_errors": errors,
        "teaching_recommendations": recommendations,
        "review_queue": reviews,
        "missing_fields": dict(sorted(missing_fields.items())),
        "invariants": {
            "numbers_require_page_literal": True,
            "missing_values_not_imputed": True,
            "observed_difficulty_higher_is_easier": True,
            "all_candidates_pending_review": True,
            "source_regions_materialized": all(
                anchor.get("source_region_id")
                for row in [*performance, *errors, *recommendations]
                for anchor in (
                    [value["anchor"] for value in (row.get("difficulty_observed"), row.get("discrimination")) if value]
                    if "difficulty_observed" in row
                    else [row["anchor"]]
                )
            ),
        },
    }


def _review(
    target_id: str,
    target: Mapping[str, Any],
    year: int,
    question_number: int,
    reasons: Iterable[str],
    priority: str,
) -> dict[str, Any]:
    return {
        "assessment_target_id": target_id,
        "scope_key": target["question_scope"]["scope_key"],
        "year": year,
        "question_number": question_number,
        "priority": priority,
        "reasons": list(dict.fromkeys(reasons)),
        "status": "pending_review",
    }


def load_report_pages(inventory_path: Path, file_store_root: Path, years: set[int]) -> dict[int, dict[str, Any]]:
    import pdfplumber

    result: dict[int, dict[str, Any]] = {}
    with inventory_path.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            year = int(row["year"])
            if year not in years or "year_report" not in row["logicalRoles"]:
                continue
            source_path = Path(row["destinationPath"])
            if not source_path.exists():
                sha = row["sha256"]
                source_path = file_store_root / "original" / sha[:2] / sha[2:4] / f"{sha}.pdf"
            if not source_path.exists():
                raise FileNotFoundError(f"year_report_pdf_missing:{year}:{source_path}")
            with pdfplumber.open(source_path) as pdf:
                pages = [(page.extract_text() or "").replace("\x00", " ") for page in pdf.pages]
            result[year] = {"sha256": row["sha256"], "path": str(source_path), "pages": pages}
    missing = years - set(result)
    if missing:
        raise ValueError(f"year_report_inventory_missing:{','.join(map(str, sorted(missing)))}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--alignment", type=Path, required=True)
    parser.add_argument("--targets", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--file-store-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    with args.observations.open(encoding="utf-8-sig", newline="") as stream:
        source_observations = list(csv.DictReader(stream))
    alignment = json.loads(args.alignment.read_text(encoding="utf-8"))
    targets = json.loads(args.targets.read_text(encoding="utf-8"))
    years = {int(row["year"]) for row in alignment["bundles"]}
    report_pages = load_report_pages(args.inventory, args.file_store_root, years)
    observations = derive_missing_observations(source_observations, alignment, report_pages)
    package = build_package(observations, alignment, targets, report_pages)
    content = json.dumps(package, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    report = {
        "schemaVersion": "cek018-guangzhou-year-report-evidence.v1",
        "status": "generated",
        "schemaValidated": False,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "taskId": "CEK-18",
        "sourceYears": sorted(years),
        "sourcePdfCount": len(report_pages),
        "sourceObservationRows": len(source_observations),
        "derivedObservationRows": len(observations) - len(source_observations),
        "performanceCandidates": len(package["observed_performance"]),
        "errorCandidates": len(package["observed_errors"]),
        "teachingRecommendationCandidates": len(package["teaching_recommendations"]),
        "reviewItems": len(package["review_queue"]),
        "blockedReviewItems": sum(row["priority"] == "blocked" for row in package["review_queue"]),
        "missingFields": package["missing_fields"],
        "manifestSha256": hashlib.sha256(content.encode()).hexdigest(),
        "databaseWrite": False,
        "activeWrite": False,
        "externalModelCalls": 0,
        "completionBoundary": "CEK-18 produces page-verified candidates only. 2015 report-heading derivations and all semantic summaries remain pending teacher review; no candidate is production eligible.",
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
