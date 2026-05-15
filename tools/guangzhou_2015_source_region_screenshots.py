from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

import psycopg
from PIL import Image
from psycopg.rows import dict_row


WORKFLOW_KEY = "guangzhou_2015_real_ingest_v1"
VISUAL_WORKFLOW_KEY = "guangzhou_2015_visual_region_v1"

BBoxPercent = tuple[int, float, float, float, float]


QUESTION_BBOX_PERCENT: dict[int, BBoxPercent] = {
    1: (1, 12, 58, 76, 10),
    2: (1, 12, 67, 76, 24),
    3: (2, 12, 7, 76, 16),
    4: (2, 12, 25, 76, 26),
    5: (2, 12, 53, 76, 17),
    6: (2, 12, 71, 76, 18),
    7: (3, 12, 7, 76, 20),
    8: (3, 12, 28, 76, 21),
    9: (3, 12, 50, 76, 27),
    10: (3, 12, 78, 76, 13),
    11: (4, 12, 7, 76, 21),
    12: (4, 12, 29, 76, 18),
    13: (4, 12, 48, 76, 21),
    14: (4, 12, 69, 76, 21),
    15: (4, 12, 76, 76, 16),
    16: (5, 12, 7, 76, 35),
    17: (5, 12, 42, 76, 16),
    18: (5, 12, 59, 76, 22),
    19: (5, 4, 82, 92, 10),
    20: (6, 10, 13, 80, 31),
    21: (6, 10, 45, 80, 38),
    22: (7, 10, 8, 80, 40),
    23: (7, 10, 48, 80, 43),
    24: (8, 10, 38, 78, 28),
}

QUESTION_ASSET_BBOX_PERCENT: dict[int, BBoxPercent] = {
    2: (1, 28, 78, 58, 15),
    3: (2, 52, 12, 36, 15),
    4: (2, 24, 31, 58, 20),
    5: (2, 40, 60, 46, 12),
    6: (2, 64, 76, 18, 20),
    7: (3, 48, 13, 34, 23),
    8: (3, 55, 35, 34, 25),
    9: (3, 10, 55, 80, 22),
    10: (3, 50, 79, 35, 17),
    11: (4, 48, 13, 34, 20),
    12: (4, 48, 32, 34, 22),
    13: (4, 52, 49, 28, 14),
    14: (4, 9, 79, 45, 13),
    15: (4, 43, 78, 42, 14),
    20: (6, 10, 13, 80, 31),
    21: (6, 10, 45, 80, 38),
    22: (7, 10, 8, 80, 40),
    23: (7, 10, 48, 80, 43),
    24: (8, 10, 38, 78, 28),
}

ANSWER_BBOX_PERCENT: dict[int, BBoxPercent] = {
    **{question_no: (1, 12, 20, 76, 8) for question_no in range(1, 13)},
    13: (1, 12, 33, 76, 22),
    14: (1, 12, 56, 76, 22),
    15: (1, 12, 77, 76, 6),
    16: (1, 12, 81, 76, 8),
    17: (1, 12, 86, 76, 5),
    18: (1, 12, 90, 76, 5),
    19: (2, 12, 8, 76, 5),
    20: (2, 12, 13, 76, 42),
    21: (2, 12, 55, 76, 38),
    22: (3, 12, 20, 76, 10),
    23: (3, 12, 31, 76, 54),
    24: (4, 12, 8, 76, 26),
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def json_dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def union_bbox(primary: BBoxPercent, secondary: BBoxPercent | None) -> BBoxPercent:
    if secondary is None or primary[0] != secondary[0]:
        return primary

    page = primary[0]
    left = min(primary[1], secondary[1])
    top = min(primary[2], secondary[2])
    right = max(primary[1] + primary[3], secondary[1] + secondary[3])
    bottom = max(primary[2] + primary[4], secondary[2] + secondary[4])
    return (page, left, top, right - left, bottom - top)


def profile_for_region(region_type: str, question_no: int, fallback: BBoxPercent) -> BBoxPercent:
    if region_type.endswith("_answer"):
        return ANSWER_BBOX_PERCENT.get(question_no, fallback)
    if region_type == "guangzhou_2015_visual_asset":
        return QUESTION_ASSET_BBOX_PERCENT.get(question_no, fallback)

    question_profile = QUESTION_BBOX_PERCENT.get(question_no, fallback)
    return union_bbox(question_profile, QUESTION_ASSET_BBOX_PERCENT.get(question_no))


def render_page(pdftoppm: str, pdf_path: Path, page_number: int, output_dir: Path) -> Path:
    prefix = output_dir / f"{pdf_path.stem[:16]}-page-{page_number:03d}"
    completed = subprocess.run(
        [
            pdftoppm,
            "-png",
            "-r",
            "180",
            "-f",
            str(page_number),
            "-l",
            str(page_number),
            "-singlefile",
            str(pdf_path),
            str(prefix),
        ],
        text=True,
        capture_output=True,
        timeout=60,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"pdftoppm failed for {pdf_path} page {page_number}: {completed.stderr.strip()}")
    rendered = prefix.with_suffix(".png")
    if not rendered.exists():
        raise RuntimeError(f"pdftoppm did not create {rendered}")
    return rendered


def crop_percent(source: Path, target: Path, x: float, y: float, width: float, height: float) -> None:
    with Image.open(source) as image:
        image_width, image_height = image.size
        pad_x = max(12, int(image_width * 0.015))
        pad_y = max(12, int(image_height * 0.012))
        left = int(image_width * x / 100) - pad_x
        top = int(image_height * y / 100) - pad_y
        right = int(image_width * (x + width) / 100) + pad_x
        bottom = int(image_height * (y + height) / 100) + pad_y
        box = (
            max(0, left),
            max(0, top),
            min(image_width, right),
            min(image_height, bottom),
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        image.crop(box).save(target, format="PNG", optimize=True)


def backfill_real_question_assets(conn: psycopg.Connection[Any]) -> list[dict[str, Any]]:
    candidates = rows(
        conn,
        """
        select distinct on ((qi.custom_fields->>'questionNo')::int)
            qi.id as question_item_id,
            (qi.custom_fields->>'questionNo')::int as question_no,
            sr.source_document_id,
            sd.file_asset_id
        from question_items qi
        join question_blocks qb on qb.question_item_id = qi.id
        join source_regions sr on sr.id = qb.source_region_id
        join source_documents sd on sd.id = sr.source_document_id
        where qi.custom_fields->>'sourceWorkflowKey' = %s
          and sr.region_type = 'guangzhou_2015_question'
          and (qi.custom_fields->>'questionNo')::int = any(%s::int[])
        order by (qi.custom_fields->>'questionNo')::int, qb.sort_order
        """,
        (WORKFLOW_KEY, list(QUESTION_ASSET_BBOX_PERCENT.keys())),
    )
    inserted: list[dict[str, Any]] = []
    now = utc_now()
    with conn.cursor(row_factory=dict_row) as cur:
        for candidate in candidates:
            question_no = int(candidate["question_no"])
            existing = rows(
                conn,
                """
                select qa.id
                from question_assets qa
                join source_regions sr on sr.id = qa.source_region_id
                where qa.question_item_id = %s
                  and qa.purpose = 'question_visual_region'
                  and sr.region_type = 'guangzhou_2015_visual_asset'
                limit 1
                """,
                (candidate["question_item_id"],),
            )
            if existing:
                continue

            page_number, x, y, width, height = QUESTION_ASSET_BBOX_PERCENT[question_no]
            region_id = uuid.uuid4()
            relative = f"generated/guangzhou-2015/source-regions/{region_id}.png"
            cur.execute(
                """
                insert into source_regions (
                    id, source_document_id, page_number, x, y, width, height,
                    coordinate_unit, screenshot_relative_path, region_type, created_at
                )
                values (%s, %s, %s, %s, %s, %s, %s, 'percent', %s, 'guangzhou_2015_visual_asset', %s)
                """,
                (
                    region_id,
                    candidate["source_document_id"],
                    page_number,
                    Decimal(str(x)),
                    Decimal(str(y)),
                    Decimal(str(width)),
                    Decimal(str(height)),
                    relative,
                    now,
                ),
            )
            cur.execute(
                """
                insert into question_assets (
                    id, question_item_id, file_asset_id, source_region_id,
                    asset_type, purpose, metadata, created_at
                )
                values (%s, %s, %s, %s, 'image', 'question_visual_region', %s::jsonb, %s)
                """,
                (
                    uuid.uuid4(),
                    candidate["question_item_id"],
                    candidate["file_asset_id"],
                    region_id,
                    json_dump(
                        {
                            "sourceWorkflowKey": WORKFLOW_KEY,
                            "questionNo": question_no,
                            "screenshotRelativePath": relative,
                            "generationMode": "text_asset_union_bbox",
                            "teacherValidationRequired": True,
                        }
                    ),
                    now,
                ),
            )
            inserted.append(
                {
                    "questionNo": question_no,
                    "sourceRegionId": str(region_id),
                    "screenshotRelativePath": relative,
                }
            )
    return inserted


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate PNG screenshots for 2015 Guangzhou source regions.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", required=True)
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--pdftoppm", default="pdftoppm")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    file_root = Path(args.file_root)
    connection = (
        f"host={args.host} port={args.port} dbname={args.database} "
        f"user={args.user} password={args.password}"
    )
    generated: list[dict[str, Any]] = []
    updated_regions: list[dict[str, Any]] = []

    with psycopg.connect(connection) as conn:
        inserted_assets = backfill_real_question_assets(conn) if args.apply else []
        source_rows = rows(
            conn,
            """
            with linked_regions as (
                select
                    sr.id,
                    sr.source_document_id,
                    sr.page_number,
                    sr.x,
                    sr.y,
                    sr.width,
                    sr.height,
                    sr.region_type,
                    sr.screenshot_relative_path,
                    sd.source_title,
                    fa.relative_path,
                    (qi.custom_fields->>'questionNo')::int as question_no
                from source_regions sr
                join source_documents sd on sd.id = sr.source_document_id
                join file_assets fa on fa.id = sd.file_asset_id
                join question_blocks qb on qb.source_region_id = sr.id
                join question_items qi on qi.id = qb.question_item_id
                where sr.region_type in (
                    'guangzhou_2015_question',
                    'guangzhou_2015_answer',
                    'guangzhou_2015_visual_question',
                    'guangzhou_2015_visual_answer'
                )
                  and qi.custom_fields->>'sourceWorkflowKey' in (%s, %s)
                union
                select
                    sr.id,
                    sr.source_document_id,
                    sr.page_number,
                    sr.x,
                    sr.y,
                    sr.width,
                    sr.height,
                    sr.region_type,
                    sr.screenshot_relative_path,
                    sd.source_title,
                    fa.relative_path,
                    (qi.custom_fields->>'questionNo')::int as question_no
                from source_regions sr
                join source_documents sd on sd.id = sr.source_document_id
                join file_assets fa on fa.id = sd.file_asset_id
                join question_assets qa on qa.source_region_id = sr.id
                join question_items qi on qi.id = qa.question_item_id
                where sr.region_type = 'guangzhou_2015_visual_asset'
                  and qi.custom_fields->>'sourceWorkflowKey' in (%s, %s)
            )
            select distinct on (id)
                id,
                source_document_id,
                page_number,
                x,
                y,
                width,
                height,
                region_type,
                screenshot_relative_path,
                source_title,
                relative_path,
                question_no
            from linked_regions
            order by id, question_no
            """,
            (WORKFLOW_KEY, VISUAL_WORKFLOW_KEY, WORKFLOW_KEY, VISUAL_WORKFLOW_KEY),
        )

        with tempfile.TemporaryDirectory(prefix="kqg-region-pages-") as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            rendered_pages: dict[tuple[str, int], Path] = {}
            for row in source_rows:
                pdf_path = file_root / str(row["relative_path"])
                if not pdf_path.exists():
                    raise RuntimeError(f"source PDF missing: {pdf_path}")
                question_no = int(row["question_no"])
                fallback = (
                    int(row["page_number"]),
                    float(row["x"]),
                    float(row["y"]),
                    float(row["width"]),
                    float(row["height"]),
                )
                page_number, x, y, width, height = profile_for_region(
                    str(row["region_type"]),
                    question_no,
                    fallback,
                )
                key = (str(pdf_path), page_number)
                if key not in rendered_pages:
                    rendered_pages[key] = render_page(args.pdftoppm, pdf_path, page_number, temp_dir)
                    page_relative = (
                        f"generated/guangzhou-2015/pages/"
                        f"{row['source_document_id']}-page-{page_number:03d}.png"
                    )
                    page_target = file_root / page_relative
                    page_target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(rendered_pages[key], page_target)

                relative = f"generated/guangzhou-2015/source-regions/{row['id']}.png"
                target = file_root / relative
                crop_percent(
                    rendered_pages[key],
                    target,
                    x,
                    y,
                    width,
                    height,
                )
                generated.append(
                    {
                        "regionId": str(row["id"]),
                        "sourceTitle": row["source_title"],
                        "pageNumber": page_number,
                        "regionType": row["region_type"],
                        "screenshotRelativePath": relative,
                    }
                )

                if args.apply:
                    with conn.cursor() as cur:
                        before = {
                            "pageNumber": int(row["page_number"]),
                            "x": float(row["x"]),
                            "y": float(row["y"]),
                            "width": float(row["width"]),
                            "height": float(row["height"]),
                            "screenshotRelativePath": row["screenshot_relative_path"],
                        }
                        after = {
                            "pageNumber": page_number,
                            "x": x,
                            "y": y,
                            "width": width,
                            "height": height,
                            "screenshotRelativePath": relative,
                        }
                        cur.execute(
                            """
                            update source_regions
                            set page_number = %s,
                                x = %s,
                                y = %s,
                                width = %s,
                                height = %s,
                                coordinate_unit = 'percent',
                                screenshot_relative_path = %s
                            where id = %s
                            """,
                            (page_number, x, y, width, height, relative, row["id"]),
                        )
                        if before != after:
                            updated_regions.append(
                                {
                                    "regionId": str(row["id"]),
                                    "questionNo": question_no,
                                    "regionType": row["region_type"],
                                    "before": before,
                                    "after": after,
                                }
                            )

        if args.apply:
            now = utc_now()
            with conn.cursor() as cur:
                cur.execute(
                    """
                    insert into review_queue_items (id, review_type, status, payload, created_at, resolved_at)
                    values (%s, 'source_region_revision_batch', 'resolved', %s::jsonb, %s, %s)
                    """,
                    (
                        uuid.uuid4(),
                        json_dump(
                            {
                                "sourceWorkflowKey": WORKFLOW_KEY,
                                "decision": "source_region_screenshot_backfill_applied",
                                "reviewedBy": "guangzhou_2015_source_region_screenshots.py",
                                "reason": "regenerated source screenshots, question visual assets, and text/asset union crop boxes",
                                "generatedSourceRegionScreenshotCount": len(generated),
                                "insertedQuestionAssets": inserted_assets,
                                "updatedSourceRegions": updated_regions,
                                "updatedSourceRegionCount": len(updated_regions),
                                "insertedQuestionAssetCount": len(inserted_assets),
                                "idempotentRerun": not inserted_assets and not updated_regions,
                                "reviewedAt": now.isoformat(),
                            }
                        ),
                        now,
                        now,
                    ),
                )
            conn.commit()

    print(
        json.dumps(
            {
                "status": "applied" if args.apply else "dry_run",
                "workflowKey": WORKFLOW_KEY,
                "generatedCount": len(generated),
                "insertedQuestionAssetCount": len(inserted_assets),
                "insertedQuestionAssets": inserted_assets,
                "items": generated[:8],
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
