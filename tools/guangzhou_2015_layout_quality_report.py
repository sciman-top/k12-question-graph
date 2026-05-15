from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


WORKFLOW_KEYS = ("guangzhou_2015_real_ingest_v1", "guangzhou_2015_visual_region_v1")
REQUIRED_FIGURE_QUESTION_NOS = set(range(2, 16)) | set(range(20, 25))

NOISE_REGIONS: dict[str, list[dict[str, Any]]] = {
    "paper": [
        {"kind": "top_margin", "page": "all", "x": 0.0, "y": 0.0, "width": 100.0, "height": 5.0},
        {"kind": "footer_page_number", "page": "all", "x": 0.0, "y": 94.0, "width": 100.0, "height": 6.0},
        {"kind": "binding_line", "page": 1, "x": 0.0, "y": 0.0, "width": 10.0, "height": 100.0},
        {"kind": "exam_instructions", "page": 1, "x": 10.0, "y": 0.0, "width": 82.0, "height": 55.0},
    ],
    "answer": [
        {"kind": "top_margin", "page": "all", "x": 0.0, "y": 0.0, "width": 100.0, "height": 5.0},
        {"kind": "footer_page_number", "page": "all", "x": 0.0, "y": 94.0, "width": 100.0, "height": 6.0},
    ],
}


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def rect(row: dict[str, Any]) -> tuple[float, float, float, float]:
    x = float(row["x"])
    y = float(row["y"])
    return (x, y, x + float(row["width"]), y + float(row["height"]))


def area(bounds: tuple[float, float, float, float]) -> float:
    left, top, right, bottom = bounds
    return max(0.0, right - left) * max(0.0, bottom - top)


def overlap_ratio(region: dict[str, Any], noise: dict[str, Any]) -> float:
    left, top, right, bottom = rect(region)
    noise_right = float(noise["x"]) + float(noise["width"])
    noise_bottom = float(noise["y"]) + float(noise["height"])
    overlap = (
        max(left, float(noise["x"])),
        max(top, float(noise["y"])),
        min(right, noise_right),
        min(bottom, noise_bottom),
    )
    region_area = area((left, top, right, bottom))
    if region_area <= 0:
        return 0.0
    return area(overlap) / region_area


def applies_to_page(noise: dict[str, Any], page_number: int) -> bool:
    return noise["page"] == "all" or int(noise["page"]) == page_number


def main() -> int:
    parser = argparse.ArgumentParser(description="Report Guangzhou 2015 source region layout and crop quality.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", required=True)
    parser.add_argument("--file-root", default=r"D:\KQG_Data\file_store")
    parser.add_argument("--json-report", default="docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.json")
    parser.add_argument("--markdown-report", default="docs/evidence/20260516-real007-guangzhou-2015-layout-quality-report.md")
    args = parser.parse_args()

    file_root = Path(args.file_root)
    connection = (
        f"host={args.host} port={args.port} dbname={args.database} "
        f"user={args.user} password={args.password}"
    )

    with psycopg.connect(connection) as conn:
        region_rows = rows(
            conn,
            """
            with linked_regions as (
                select
                    sr.id,
                    sr.source_document_id,
                    sd.source_title,
                    sd.source_type,
                    sr.page_number,
                    sr.x,
                    sr.y,
                    sr.width,
                    sr.height,
                    sr.region_type,
                    sr.screenshot_relative_path,
                    (qi.custom_fields->>'questionNo')::int as question_no,
                    'block' as link_kind
                from source_regions sr
                join source_documents sd on sd.id = sr.source_document_id
                join question_blocks qb on qb.source_region_id = sr.id
                join question_items qi on qi.id = qb.question_item_id
                where qi.custom_fields->>'sourceWorkflowKey' = any(%s)
                union
                select
                    sr.id,
                    sr.source_document_id,
                    sd.source_title,
                    sd.source_type,
                    sr.page_number,
                    sr.x,
                    sr.y,
                    sr.width,
                    sr.height,
                    sr.region_type,
                    sr.screenshot_relative_path,
                    (qi.custom_fields->>'questionNo')::int as question_no,
                    'asset' as link_kind
                from source_regions sr
                join source_documents sd on sd.id = sr.source_document_id
                join question_assets qa on qa.source_region_id = sr.id
                join question_items qi on qi.id = qa.question_item_id
                where qi.custom_fields->>'sourceWorkflowKey' = any(%s)
            )
            select distinct on (id, question_no, link_kind)
                id,
                source_document_id,
                source_title,
                source_type,
                page_number,
                x,
                y,
                width,
                height,
                region_type,
                screenshot_relative_path,
                question_no,
                link_kind
            from linked_regions
            order by id, question_no, link_kind
            """,
            (list(WORKFLOW_KEYS), list(WORKFLOW_KEYS)),
        )
        audit_rows = rows(
            conn,
            """
            select id, created_at, resolved_at, payload
            from review_queue_items
            where review_type = 'source_region_revision_batch'
              and payload->>'sourceWorkflowKey' = 'guangzhou_2015_real_ingest_v1'
            order by created_at desc
            limit 5
            """,
        )

    missing_screenshots: list[dict[str, Any]] = []
    noise_overlaps: list[dict[str, Any]] = []
    placeholder_like: list[dict[str, Any]] = []
    page_summary: dict[str, dict[str, Any]] = {}
    asset_question_nos: set[int] = set()

    for row in region_rows:
        question_no = int(row["question_no"])
        source_group = "answer" if "答案" in str(row["source_title"]) else "paper"
        page_key = f"{source_group}:{row['page_number']}"
        page_summary.setdefault(
            page_key,
            {
                "sourceGroup": source_group,
                "pageNumber": int(row["page_number"]),
                "retainedRegionCount": 0,
                "noiseRegionKinds": [
                    noise["kind"]
                    for noise in NOISE_REGIONS[source_group]
                    if applies_to_page(noise, int(row["page_number"]))
                ],
            },
        )
        page_summary[page_key]["retainedRegionCount"] += 1

        relative_path = str(row["screenshot_relative_path"] or "")
        if not relative_path or not (file_root / relative_path).exists():
            missing_screenshots.append(
                {
                    "questionNo": question_no,
                    "regionId": str(row["id"]),
                    "regionType": row["region_type"],
                    "screenshotRelativePath": relative_path,
                }
            )
        if relative_path.lower().endswith(".json"):
            placeholder_like.append(
                {
                    "questionNo": question_no,
                    "regionId": str(row["id"]),
                    "regionType": row["region_type"],
                    "screenshotRelativePath": relative_path,
                }
            )
        if str(row["region_type"]).endswith("asset"):
            asset_question_nos.add(question_no)

        for noise in NOISE_REGIONS[source_group]:
            if not applies_to_page(noise, int(row["page_number"])):
                continue
            ratio = overlap_ratio(row, noise)
            if ratio >= 0.35:
                noise_overlaps.append(
                    {
                        "questionNo": question_no,
                        "regionId": str(row["id"]),
                        "regionType": row["region_type"],
                        "sourceTitle": row["source_title"],
                        "pageNumber": int(row["page_number"]),
                        "noiseKind": noise["kind"],
                        "overlapRatio": round(ratio, 3),
                    }
                )

    missing_required_asset_question_nos = sorted(REQUIRED_FIGURE_QUESTION_NOS - asset_question_nos)
    latest_audit = audit_rows[0] if audit_rows else None
    blockers = []
    if missing_screenshots:
        blockers.append("missing_source_region_screenshots")
    if placeholder_like:
        blockers.append("placeholder_manifest_screenshots")
    if noise_overlaps:
        blockers.append("retained_region_overlaps_noise")
    if missing_required_asset_question_nos:
        blockers.append("missing_required_question_assets")
    if latest_audit is None:
        blockers.append("missing_source_region_revision_batch_audit")

    report = {
        "status": "pass" if not blockers else "fail",
        "task": "REAL007",
        "scope": "2015 Guangzhou physics paper and answer source regions",
        "workflowKeys": list(WORKFLOW_KEYS),
        "linkedSourceRegionCount": len(region_rows),
        "questionNosCovered": sorted({int(row["question_no"]) for row in region_rows}),
        "figureQuestionNosWithAssets": sorted(asset_question_nos),
        "missingRequiredAssetQuestionNos": missing_required_asset_question_nos,
        "missingScreenshotCount": len(missing_screenshots),
        "placeholderLikeScreenshotCount": len(placeholder_like),
        "noiseOverlapCount": len(noise_overlaps),
        "pageSummary": list(page_summary.values()),
        "noiseRegions": NOISE_REGIONS,
        "latestRecropAudit": None
        if latest_audit is None
        else {
            "id": str(latest_audit["id"]),
            "createdAt": latest_audit["created_at"].isoformat(),
            "resolvedAt": latest_audit["resolved_at"].isoformat() if latest_audit["resolved_at"] else None,
        },
        "blockers": blockers,
        "samples": {
            "missingScreenshots": missing_screenshots[:10],
            "placeholderLike": placeholder_like[:10],
            "noiseOverlaps": noise_overlaps[:10],
        },
        "rollback": "rerun tools/run-guangzhou-2015-real-ingest-slice.ps1 -Apply and tools/run-guangzhou-2015-visual-region-slice.ps1 -Apply, then rerun source screenshot backfill",
        "summaryChinese": "2015 广州真卷来源区域已排除主要版面噪声，题图题具备 question_assets，重裁回填有 batch audit。"
        if not blockers
        else "2015 广州真卷来源区域仍存在版面噪声、截图或重裁审计缺口。",
    }

    json_path = Path(args.json_report)
    markdown_path = Path(args.markdown_report)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    lines = [
        "# REAL007 广州 2015 版面噪声与裁图质量报告",
        "",
        f"- status: {report['status']}",
        f"- linked_source_regions: {report['linkedSourceRegionCount']}",
        f"- missing_screenshots: {report['missingScreenshotCount']}",
        f"- placeholder_like_screenshots: {report['placeholderLikeScreenshotCount']}",
        f"- noise_overlaps: {report['noiseOverlapCount']}",
        f"- latest_recrop_audit: {report['latestRecropAudit']['id'] if report['latestRecropAudit'] else 'missing'}",
        "",
        "## 结论",
        report["summaryChinese"],
        "",
        "## 阻断项",
    ]
    lines.extend([f"- {blocker}" for blocker in blockers] or ["- 无"])
    markdown_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
