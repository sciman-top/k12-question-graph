from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import uuid
from collections import Counter
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Iterable, Mapping

import psycopg
from psycopg.rows import dict_row
from pypdf import PdfReader


IMPORT_KEY = "cek012a_guangzhou_report_question_anchors_v1"
ID_NAMESPACE = uuid.UUID("6b89cbd6-5adc-4c3c-bb5e-65cf7ce0f890")
WORKFLOW_KEY = "guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1"
MATERIAL_BATCH_KEY = "guangzhou_physics_2015_2025_20260726_v2"


def stable_id(*parts: object) -> uuid.UUID:
    return uuid.uuid5(ID_NAMESPACE, ":".join(str(part) for part in parts))


def parse_report_page(value: str) -> int | None:
    match = re.search(r"(?:年报|报告)?\s*[pP]\s*(\d+)", value or "")
    return int(match.group(1)) if match else None


def compact(value: str) -> str:
    return re.sub(r"\s+", "", value or "")


def locate_heading_page(pages: list[str], question_number: int, stem: str, minimum_page: int = 1) -> tuple[int, float]:
    heading = re.compile(rf"(?:^|\n)\s*{question_number}\s*[.．、]\s*")
    compact_stem = compact(stem)[:240]
    candidates: list[tuple[int, int, int]] = []
    for page_number, page in enumerate(pages, start=1):
        if page_number < minimum_page or not heading.search(page):
            continue
        compact_page = compact(page)
        match_size = SequenceMatcher(None, compact_stem, compact_page, autojunk=False).find_longest_match().size
        candidates.append((match_size, -page_number, page_number))
    if not candidates:
        raise ValueError(f"report_question_heading_missing:{question_number}")
    match_size, _, page_number = max(candidates)
    confidence = round(min(0.99, 0.55 + match_size / max(1, len(compact_stem)) * 0.4), 4)
    return page_number, confidence


def build_page_plan(
    questions: Iterable[Mapping[str, Any]],
    observations: Iterable[Mapping[str, str]],
    report_pages_2015: list[str],
) -> list[dict[str, Any]]:
    observation_pages: dict[tuple[int, int], int] = {}
    for row in observations:
        key = (int(row["year"]), int(row["question_number"]))
        if key in observation_pages:
            raise ValueError(f"duplicate_report_observation:{key[0]}:{key[1]}")
        page = parse_report_page(row.get("evidence_locations", ""))
        if page is None:
            raise ValueError(f"report_observation_page_missing:{key[0]}:{key[1]}")
        observation_pages[key] = page

    result: list[dict[str, Any]] = []
    last_2015_page = 1
    for question in sorted(questions, key=lambda row: (int(row["year"]), int(row["question_number"]))):
        year = int(question["year"])
        number = int(question["question_number"])
        if year == 2015:
            page, confidence = locate_heading_page(report_pages_2015, number, str(question.get("stem") or ""), last_2015_page)
            last_2015_page = page
            method = "heading_and_stem_similarity"
        else:
            page = observation_pages.get((year, number))
            if page is None:
                raise ValueError(f"report_observation_missing:{year}:{number}")
            confidence = 0.95
            method = "c003_page_verified_observation"
        result.append({
            "questionItemId": str(question["question_item_id"]),
            "year": year,
            "questionNumber": number,
            "pageNumber": page,
            "localizationMethod": method,
            "confidence": confidence,
        })
    return result


def build_extra_evidence_plan(evidence_package: Mapping[str, Any], base_plan: list[dict[str, Any]]) -> list[dict[str, Any]]:
    question_facts = {row["questionItemId"]: row for row in base_plan}
    result: dict[tuple[str, int], dict[str, Any]] = {}
    for evidence in evidence_package.get("observed_performance", []):
        question_id = str(evidence["question_scope"]["question_item_id"])
        base = question_facts.get(question_id)
        if not base:
            continue
        for value in (evidence.get("difficulty_observed"), evidence.get("discrimination"), evidence.get("option_distribution")):
            anchor = (value or {}).get("anchor") if value else None
            if not anchor or anchor.get("source_region_id") or not anchor.get("pdf_page_number"):
                continue
            page_number = int(anchor["pdf_page_number"])
            if page_number == int(base["pageNumber"]):
                continue
            result[(question_id, page_number)] = {
                **base,
                "pageNumber": page_number,
                "localizationMethod": "cek018_metric_page_candidate",
                "confidence": 0.9,
                "anchorKind": "metric_page",
            }
    return list(result.values())


def load_database_snapshot(conn: psycopg.Connection[Any]) -> tuple[list[dict[str, Any]], dict[int, dict[str, Any]]]:
    questions = list(conn.execute(
        """select qi.id::text as question_item_id,(qi.custom_fields->>'year')::int as year,
        (qi.custom_fields->>'questionNo')::int as question_number,qb.content->>'text' as stem
        from question_items qi join question_blocks qb on qb.question_item_id=qi.id and qb.block_type='stem'
        where qi.custom_fields->>'sourceWorkflowKey'=%s order by year,question_number""",
        (WORKFLOW_KEY,),
    ).fetchall())
    documents = list(conn.execute(
        """select sd.year,sd.id::text as source_document_id,fa.relative_path,fa.sha256
        from source_documents sd join file_assets fa on fa.id=sd.file_asset_id
        where sd.material_batch_key=%s and sd.source_type='exam_analysis_report' and sd.year between 2015 and 2025
        order by sd.year""",
        (MATERIAL_BATCH_KEY,),
    ).fetchall())
    return [dict(row) for row in questions], {int(row["year"]): dict(row) for row in documents}


def validate_plan(plan: list[dict[str, Any]], documents: Mapping[int, Mapping[str, Any]], file_store_root: Path) -> None:
    expected = {year: 24 if year <= 2020 else 18 for year in range(2015, 2026)}
    counts = Counter(int(row["year"]) for row in plan)
    if counts != Counter(expected):
        raise ValueError(f"report_plan_year_counts_mismatch:{dict(counts)}")
    if set(documents) != set(expected):
        raise ValueError(f"report_document_years_mismatch:{sorted(documents)}")
    for year, document in documents.items():
        path = file_store_root / Path(str(document["relative_path"]))
        if not path.is_file():
            raise FileNotFoundError(f"report_file_missing:{year}:{path}")
        page_count = len(PdfReader(str(path)).pages)
        invalid = [row["pageNumber"] for row in plan if row["year"] == year and not 1 <= int(row["pageNumber"]) <= page_count]
        if invalid:
            raise ValueError(f"report_page_out_of_range:{year}:{invalid}")


def materialize(conn: psycopg.Connection[Any], plan: list[dict[str, Any]], documents: Mapping[int, Mapping[str, Any]]) -> None:
    for row in plan:
        document = documents[int(row["year"])]
        region_id = stable_id("report-region", row["questionItemId"], row["pageNumber"])
        anchor_kind = str(row.get("anchorKind") or "question_start")
        block_id = (
            stable_id("report-block", row["questionItemId"])
            if anchor_kind == "question_start"
            else stable_id("report-metric-block", row["questionItemId"], row["pageNumber"])
        )
        metadata = {
            "importKey": IMPORT_KEY,
            "year": row["year"],
            "questionNumber": row["questionNumber"],
            "localizationMethod": row["localizationMethod"],
            "confidence": row["confidence"],
            "reviewStatus": "pending_review",
            "productionEligible": False,
            "anchorKind": anchor_kind,
        }
        content = {
            **metadata,
            "scopeKey": f"question-scope:v1:{row['questionItemId']}:whole_question",
            "pageNumber": row["pageNumber"],
            "sourceDocumentSha256": document["sha256"],
        }
        conn.execute(
            """insert into source_regions
            (id,source_document_id,page_number,x,y,width,height,coordinate_unit,screenshot_relative_path,region_type,metadata,created_at)
            values (%s,%s,%s,0,0,100,100,'percent',null,'guangzhou_year_report_question_page_candidate',%s::jsonb,now())
            on conflict (id) do update set source_document_id=excluded.source_document_id,page_number=excluded.page_number,
            x=excluded.x,y=excluded.y,width=excluded.width,height=excluded.height,coordinate_unit=excluded.coordinate_unit,
            region_type=excluded.region_type,metadata=excluded.metadata""",
            (region_id, document["source_document_id"], row["pageNumber"], json.dumps(metadata, ensure_ascii=False)),
        )
        conn.execute(
            """insert into question_blocks (id,question_item_id,block_type,sort_order,content,source_region_id,created_at)
            values (%s,%s,'year_report_evidence',%s,%s::jsonb,%s,now())
            on conflict (id) do update set block_type=excluded.block_type,sort_order=excluded.sort_order,
            content=excluded.content,source_region_id=excluded.source_region_id""",
            (block_id, row["questionItemId"], 900 if anchor_kind == "question_start" else 910 + int(row["pageNumber"]), json.dumps(content, ensure_ascii=False), region_id),
        )


def count_materialized(conn: psycopg.Connection[Any]) -> tuple[int, int]:
    regions = conn.execute(
        "select count(*) as value from source_regions where metadata->>'importKey'=%s", (IMPORT_KEY,)
    ).fetchone()["value"]
    blocks = conn.execute(
        "select count(*) as value from question_blocks where content->>'importKey'=%s", (IMPORT_KEY,)
    ).fetchone()["value"]
    return int(regions), int(blocks)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--file-store-root", type=Path, required=True)
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--backup-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--evidence-package", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not args.backup_manifest.is_file():
        raise FileNotFoundError(f"backup_manifest_missing:{args.backup_manifest}")
    with args.observations.open(encoding="utf-8-sig", newline="") as stream:
        observations = list(csv.DictReader(stream))
    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        questions, documents = load_database_snapshot(conn)
        report_2015 = args.file_store_root / Path(str(documents[2015]["relative_path"]))
        report_pages_2015 = [(page.extract_text() or "").replace("\x00", " ") for page in PdfReader(str(report_2015)).pages]
        plan = build_page_plan(questions, observations, report_pages_2015)
        validate_plan(plan, documents, args.file_store_root)
        extra_plan: list[dict[str, Any]] = []
        if args.evidence_package and args.evidence_package.is_file():
            extra_plan = build_extra_evidence_plan(
                json.loads(args.evidence_package.read_text(encoding="utf-8")), plan
            )
            validate_plan(plan, documents, args.file_store_root)
        full_plan = [*plan, *extra_plan]
        before = count_materialized(conn)
        if args.apply:
            with conn.transaction():
                materialize(conn, full_plan, documents)
        after = count_materialized(conn)
    payload = {
        "schemaVersion": "cek012a-guangzhou-report-anchor-materialization.v1",
        "status": "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "apply" if args.apply else "dry_run",
        "importKey": IMPORT_KEY,
        "questions": len(plan),
        "anchors": len(full_plan),
        "extraMetricPageAnchors": len(extra_plan),
        "years": dict(sorted(Counter(row["year"] for row in plan).items())),
        "localizationMethods": dict(sorted(Counter(row["localizationMethod"] for row in plan).items())),
        "database": {"regionsBefore": before[0], "blocksBefore": before[1], "regionsAfter": after[0], "blocksAfter": after[1]},
        "backupManifest": str(args.backup_manifest.resolve()),
        "activeWrite": False,
        "productionEligible": False,
        "rollback": f"delete question_blocks/source_regions where JSON importKey = {IMPORT_KEY}, or restore {args.backup_manifest.resolve()}",
        "planSha256": hashlib.sha256(json.dumps(full_plan, sort_keys=True).encode()).hexdigest(),
        "completionBoundary": "Candidate report-page anchors only; full-page regions and 2015 heuristic localization require teacher review.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
