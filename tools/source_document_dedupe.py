from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


PAPER_2015_SHA256 = "534d8eee3b99446d514af736aaf4cd8e36f2803154f7778c0f656f1832b7510c"
ANSWER_2015_SHA256 = "065a6293b5c1019ed2da199736df44c6d0304797d0a986a750449197ca9ba88d"
PAPER_2015_FILE_NAME = "2015广州中考.pdf"
ANSWER_2015_FILE_NAME = "2015广州中考答案.pdf"

DEDUP_PARTITION_COLUMNS = [
    "file_asset_id",
    "source_type",
    "source_title",
    "region",
    "year",
    "grade_or_scope",
    "edition_or_version",
    "material_batch_key",
    "owner_scope",
    "license_or_permission",
    "sharing_allowed",
    "contains_student_pii",
    "anonymization_status",
    "external_ai_allowed",
    "may_use_for_knowledge_extraction",
    "may_use_for_exam_point_extraction",
    "may_use_for_trend_analysis",
]


def scalar(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> int:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        value = cur.fetchone()[0]
        return int(value or 0)


def rows(conn: psycopg.Connection[Any], sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def update_refs(conn: psycopg.Connection[Any], table: str, column: str, duplicate_id: str, canonical_id: str) -> int:
    with conn.cursor() as cur:
        cur.execute(
            f"update {table} set {column} = %s where {column} = %s",
            (canonical_id, duplicate_id),
        )
        return int(cur.rowcount or 0)


def has_column(conn: psycopg.Connection[Any], table: str, column: str) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            select exists (
                select 1
                from information_schema.columns
                where table_schema = 'public'
                  and table_name = %s
                  and column_name = %s
            )
            """,
            (table, column),
        )
        return bool(cur.fetchone()[0])


def reclassify_2015_guangzhou(conn: psycopg.Connection[Any]) -> list[dict[str, Any]]:
    sql = """
        update source_documents sd
        set source_type = 'local_exam_paper',
            source_title = case
                when lower(fa.sha256) = %s then '2015广州中考'
                when lower(fa.sha256) = %s then '2015广州中考答案'
                else sd.source_title
            end,
            region = 'guangzhou',
            year = 2015,
            grade_or_scope = 'grade_9',
            edition_or_version = 'guangzhou_physics_zhongkao',
            material_batch_key = 'guangzhou_physics_zhongkao',
            owner_scope = 'school',
            license_or_permission = 'pending_source_workbench_review',
            sharing_allowed = false,
            contains_student_pii = false,
            anonymization_status = 'not_applicable',
            external_ai_allowed = false,
            may_use_for_knowledge_extraction = true,
            may_use_for_exam_point_extraction = true,
            may_use_for_trend_analysis = true
        from file_assets fa
        where sd.file_asset_id = fa.id
          and (
            lower(fa.sha256) in (%s, %s)
            or fa.original_file_name in (%s, %s)
          )
        returning sd.id, sd.file_asset_id, sd.source_title, sd.material_batch_key
    """
    return rows(
        conn,
        sql,
        (
            PAPER_2015_SHA256,
            ANSWER_2015_SHA256,
            PAPER_2015_SHA256,
            ANSWER_2015_SHA256,
            PAPER_2015_FILE_NAME,
            ANSWER_2015_FILE_NAME,
        ),
    )


def duplicate_mappings(conn: psycopg.Connection[Any]) -> list[dict[str, Any]]:
    partition = ", ".join(DEDUP_PARTITION_COLUMNS)
    sql = f"""
        with ranked as (
            select
                id,
                first_value(id) over (partition by {partition} order by created_at, id) as canonical_id,
                row_number() over (partition by {partition} order by created_at, id) as row_no,
                count(*) over (partition by {partition}) as duplicate_count
            from source_documents
        )
        select id as duplicate_id, canonical_id, duplicate_count
        from ranked
        where row_no > 1
        order by canonical_id, id
    """
    return rows(conn, sql)


def exact_duplicate_group_count(conn: psycopg.Connection[Any]) -> int:
    partition = ", ".join(DEDUP_PARTITION_COLUMNS)
    return scalar(
        conn,
        f"""
        select count(*) from (
            select {partition}, count(*) as duplicate_count
            from source_documents
            group by {partition}
            having count(*) > 1
        ) duplicate_groups
        """,
    )


def merge_duplicates(conn: psycopg.Connection[Any], mappings: list[dict[str, Any]]) -> dict[str, int]:
    affected = {
        "sourceRegionsUpdated": 0,
        "cutCandidatesUpdated": 0,
        "importJobsUpdated": 0,
        "sourceDocumentsDeleted": 0,
    }
    reference_columns = [
        ("source_regions", "source_document_id", "sourceRegionsUpdated"),
        ("cut_candidates", "source_document_id", "cutCandidatesUpdated"),
        ("import_jobs", "source_document_id", "importJobsUpdated"),
    ]
    available_reference_columns = [
        (table, column, key)
        for table, column, key in reference_columns
        if has_column(conn, table, column)
    ]
    with conn.cursor() as cur:
        for mapping in mappings:
            duplicate_id = str(mapping["duplicate_id"])
            canonical_id = str(mapping["canonical_id"])
            for table, column, key in available_reference_columns:
                affected[key] += update_refs(conn, table, column, duplicate_id, canonical_id)
            cur.execute("delete from source_documents where id = %s", (duplicate_id,))
            affected["sourceDocumentsDeleted"] += int(cur.rowcount or 0)
    return affected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="k12_question_graph")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--password", default="")
    parser.add_argument("--output", default="docs/evidence/source-document-dedupe-report.json")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    conninfo = {
        "host": args.host,
        "port": args.port,
        "dbname": args.database,
        "user": args.user,
        "password": args.password,
    }

    report: dict[str, Any] = {
        "schemaVersion": "source-document-dedupe.v0.1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "apply" if args.apply else "dry_run",
        "status": "started",
        "scope": {
            "reclassifiedSha256": [PAPER_2015_SHA256, ANSWER_2015_SHA256],
            "reclassifiedOriginalFileNames": [PAPER_2015_FILE_NAME, ANSWER_2015_FILE_NAME],
            "dedupePartitionColumns": DEDUP_PARTITION_COLUMNS,
        },
    }

    with psycopg.connect(**conninfo) as conn:
        conn.execute("begin")
        try:
            report["before"] = {
                "sourceDocuments": scalar(conn, "select count(*) from source_documents"),
                "exactDuplicateGroups": exact_duplicate_group_count(conn),
                "guangzhou2015SourceDocuments": scalar(
                    conn,
                    """
                    select count(*)
                    from source_documents sd
                    join file_assets fa on fa.id = sd.file_asset_id
                    where lower(fa.sha256) in (%s, %s)
                       or fa.original_file_name in (%s, %s)
                    """,
                    (PAPER_2015_SHA256, ANSWER_2015_SHA256, PAPER_2015_FILE_NAME, ANSWER_2015_FILE_NAME),
                ),
            }

            reclassified = reclassify_2015_guangzhou(conn)
            mappings = duplicate_mappings(conn)
            affected = merge_duplicates(conn, mappings)

            report["actions"] = {
                "reclassified2015GuangzhouDocuments": len(reclassified),
                "duplicateSourceDocumentsMapped": len(mappings),
                **affected,
            }
            report["after"] = {
                "sourceDocuments": scalar(conn, "select count(*) from source_documents"),
                "exactDuplicateGroups": exact_duplicate_group_count(conn),
                "guangzhou2015SourceDocuments": scalar(
                    conn,
                    """
                    select count(*)
                    from source_documents sd
                    join file_assets fa on fa.id = sd.file_asset_id
                    where lower(fa.sha256) in (%s, %s)
                       or fa.original_file_name in (%s, %s)
                    """,
                    (PAPER_2015_SHA256, ANSWER_2015_SHA256, PAPER_2015_FILE_NAME, ANSWER_2015_FILE_NAME),
                ),
                "guangzhou2015ByTitle": rows(
                    conn,
                    """
                    select sd.source_title, count(*) as count
                    from source_documents sd
                    join file_assets fa on fa.id = sd.file_asset_id
                    where lower(fa.sha256) in (%s, %s)
                       or fa.original_file_name in (%s, %s)
                    group by sd.source_title
                    order by sd.source_title
                    """,
                    (PAPER_2015_SHA256, ANSWER_2015_SHA256, PAPER_2015_FILE_NAME, ANSWER_2015_FILE_NAME),
                ),
            }

            if args.apply:
                conn.commit()
                report["status"] = "applied"
            else:
                conn.rollback()
                report["status"] = "dry_run"
        except Exception:
            conn.rollback()
            raise

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
