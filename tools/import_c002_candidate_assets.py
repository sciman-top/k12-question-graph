from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
from collections import Counter, OrderedDict
from datetime import datetime, timezone
from typing import Any

import psycopg
from psycopg.rows import dict_row


ASSET_FILES = OrderedDict(
    [
        ("knowledge_point", "c002-formal-knowledge.csv"),
        ("curriculum_standard_item", "c002-curriculum-standard.csv"),
        ("exam_point", "c002-exam-point.csv"),
        ("textbook_chapter", "c002-textbook-chapter.csv"),
        ("trend_summary", "c002-trend-summary.csv"),
    ]
)

IMPORT_KEY = "c002_candidate_import_guangzhou_physics_2016_2025_v1"
VERSION = 1


def read_csv(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def split_ids(value: str) -> list[str]:
    if not value:
        return []
    return [item.strip() for item in re.split(r"[;|]", value) if item.strip()]


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"true", "1", "yes", "y"}


def parse_decimal(value: str, default: float = 0.0) -> float:
    if not value.strip():
        return default
    return float(value)


def normalize_filename(name: str) -> str:
    path = pathlib.PureWindowsPath(name)
    stem = re.sub(r"\(\d+\)$", "", path.stem)
    stem = stem.replace("_参考答案", "答案").replace("-参考答案", "答案")
    return f"{stem}{path.suffix}"


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_manifest(input_root: pathlib.Path) -> dict[str, dict[str, Any]]:
    data = json.loads((input_root / "source-material-manifest.candidate.json").read_text(encoding="utf-8-sig"))
    materials = data.get("materials", [])
    return {item["materialId"]: item for item in materials}


def fetch_source_documents(conn: psycopg.Connection, material_batch_key: str) -> dict[str, dict[str, Any]]:
    rows = conn.execute(
        """
        select
            sd.id as source_document_id,
            sd.source_type,
            sd.source_title,
            sd.year,
            sd.material_batch_key,
            fa.id as file_asset_id,
            fa.original_file_name,
            fa.sha256
        from source_documents sd
        join file_assets fa on fa.id = sd.file_asset_id
        where sd.material_batch_key = %s
        """,
        (material_batch_key,),
    ).fetchall()

    by_name: dict[str, dict[str, Any]] = {}
    for row in rows:
        by_name[row["original_file_name"]] = row
        by_name.setdefault(normalize_filename(row["original_file_name"]), row)
    return by_name


def resolve_materials(
    material_ids: list[str],
    manifest: dict[str, dict[str, Any]],
    source_documents_by_name: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    resolved: list[dict[str, Any]] = []
    missing: list[str] = []
    for material_id in material_ids:
        material = manifest.get(material_id)
        if material is None:
            missing.append(material_id)
            continue
        original_name = material["originalFileName"]
        doc = source_documents_by_name.get(original_name) or source_documents_by_name.get(normalize_filename(original_name))
        if doc is None:
            missing.append(material_id)
            continue
        resolved.append(
            {
                "materialId": material_id,
                "manifestOriginalFileName": original_name,
                "uploadedOriginalFileName": doc["original_file_name"],
                "sourceDocumentId": str(doc["source_document_id"]),
                "fileAssetId": str(doc["file_asset_id"]),
                "sourceType": doc["source_type"],
                "year": doc["year"],
                "sha256": doc["sha256"],
            }
        )
    return resolved, missing


def build_assets(
    input_root: pathlib.Path,
    manifest: dict[str, dict[str, Any]],
    source_documents_by_name: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    assets: list[dict[str, Any]] = []
    missing_materials: list[str] = []
    seen: set[tuple[str, str]] = set()

    for asset_type, file_name in ASSET_FILES.items():
        for row in read_csv(input_root / file_name):
            stable_id = row["stable_id"].strip()
            key = (asset_type, stable_id)
            if key in seen:
                raise ValueError(f"duplicate asset key: {asset_type}:{stable_id}")
            seen.add(key)

            material_ids = split_ids(row.get("source_material_ids", ""))
            resolved, missing = resolve_materials(material_ids, manifest, source_documents_by_name)
            missing_materials.extend(missing)

            production_eligible = parse_bool(row.get("production_eligible", "false"))
            review_status = row.get("review_status", "").strip() or "pending_review"
            if production_eligible:
                raise ValueError(f"production_eligible=true is forbidden for candidate import: {asset_type}:{stable_id}")
            if review_status != "pending_review":
                raise ValueError(f"review_status must stay pending_review for candidate import: {asset_type}:{stable_id}")

            effective_scope = {
                "subject": row.get("subject", "physics"),
                "stage": row.get("stage", "junior_middle_school"),
                "region": row.get("region", ""),
                "gradeOrScope": row.get("grade_or_scope", row.get("grade_or_volume", "")),
                "yearRange": row.get("year_range", ""),
            }
            source_evidence = {
                "importKey": IMPORT_KEY,
                "sourceMaterialIds": material_ids,
                "resolvedSources": resolved,
                "evidenceLocations": split_ids(row.get("evidence_locations", "")),
                "productionEligible": False,
                "reviewStatus": review_status,
            }
            metadata = dict(row)
            metadata.update(
                {
                    "csvFile": file_name,
                    "candidateImportKey": IMPORT_KEY,
                    "candidateOnly": True,
                    "externalAiWriteAllowed": False,
                }
            )

            assets.append(
                {
                    "asset_type": asset_type,
                    "stable_id": stable_id,
                    "version": VERSION,
                    "display_name": row.get("title", stable_id).strip() or stable_id,
                    "status": "candidate",
                    "authority": "source_derived",
                    "effective_scope": effective_scope,
                    "source_evidence": source_evidence,
                    "metadata": metadata,
                }
            )

    return assets, missing_materials


def build_external_candidates(input_root: pathlib.Path, manifest: dict[str, dict[str, Any]], source_documents_by_name: dict[str, dict[str, Any]]) -> tuple[list[dict[str, Any]], list[str]]:
    rows = read_csv(input_root / "c002-external-ai-candidate.csv")
    missing_materials: list[str] = []
    candidates: list[dict[str, Any]] = []
    for row in rows:
        if parse_bool(row.get("production_eligible", "false")):
            raise ValueError(f"external candidate production_eligible=true is forbidden: {row.get('candidate_id')}")
        material_ids = split_ids(row.get("source_files", ""))
        resolved, missing = resolve_materials(material_ids, manifest, source_documents_by_name)
        missing_materials.extend(missing)
        candidates.append({**row, "resolvedSources": resolved})
    return candidates, missing_materials


def build_mappings(input_root: pathlib.Path, asset_keys: set[tuple[str, str]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    mappings: list[dict[str, Any]] = []
    skipped_external_source_mappings: list[dict[str, Any]] = []
    for row in read_csv(input_root / "c002-asset-mapping.csv"):
        source_type = row["source_asset_type"].strip()
        target_type = row["target_asset_type"].strip()
        source_key = (source_type, row["source_stable_id"].strip())
        target_key = (target_type, row["target_stable_id"].strip())
        if target_key not in asset_keys:
            raise ValueError(f"mapping target asset missing: {row['mapping_id']} -> {target_type}:{target_key[1]}")
        if source_key not in asset_keys:
            if source_type not in ASSET_FILES:
                skipped_external_source_mappings.append(
                    {
                        "mappingId": row["mapping_id"],
                        "sourceAssetType": source_type,
                        "sourceStableId": source_key[1],
                        "targetAssetType": target_type,
                        "targetStableId": target_key[1],
                        "impactScope": row.get("impact_scope", ""),
                    }
                )
                continue
            raise ValueError(f"mapping source asset missing: {row['mapping_id']} -> {source_type}:{source_key[1]}")
        if row.get("review_status", "").strip() != "pending_review":
            raise ValueError(f"mapping must stay pending_review: {row['mapping_id']}")
        if parse_bool(row.get("auto_apply_allowed", "false")):
            raise ValueError(f"auto_apply_allowed=true is forbidden for candidate import: {row['mapping_id']}")
        mappings.append(
            {
                "mapping_id": row["mapping_id"].strip(),
                "source_key": source_key,
                "target_key": target_key,
                "mapping_type": row["mapping_type"].strip(),
                "confidence": parse_decimal(row.get("confidence", "0")),
                "review_status": "pending_review",
                "auto_applied": False,
                "evidence": {
                    "importKey": IMPORT_KEY,
                    "csvRow": row,
                    "sourceMaterialIds": split_ids(row.get("source_material_ids", "")),
                    "evidenceLocations": split_ids(row.get("evidence_locations", "")),
                    "impactScope": row.get("impact_scope", ""),
                    "rollbackRequired": parse_bool(row.get("rollback_required", "true")),
                },
            }
        )
    return mappings, skipped_external_source_mappings


def get_existing_assets(conn: psycopg.Connection, assets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not assets:
        return []
    values = [(a["asset_type"], a["stable_id"], a["version"]) for a in assets]
    return conn.execute(
        """
        select asset_type, stable_id, version, status
        from domain_asset_versions
        where (asset_type, stable_id, version) in (
            select * from unnest(%s::text[], %s::text[], %s::int[])
        )
        """,
        ([v[0] for v in values], [v[1] for v in values], [v[2] for v in values]),
    ).fetchall()


def upsert_assets(conn: psycopg.Connection, assets: list[dict[str, Any]]) -> dict[tuple[str, str], str]:
    ids: dict[tuple[str, str], str] = {}
    for asset in assets:
        row = conn.execute(
            """
            insert into domain_asset_versions (
                asset_type, stable_id, version, display_name, status, authority,
                effective_scope, source_evidence, metadata, created_at, updated_at
            )
            values (%s, %s, %s, %s, %s, %s, %s::jsonb, %s::jsonb, %s::jsonb, now(), now())
            on conflict (asset_type, stable_id, version) do update set
                display_name = excluded.display_name,
                status = excluded.status,
                authority = excluded.authority,
                effective_scope = excluded.effective_scope,
                source_evidence = excluded.source_evidence,
                metadata = excluded.metadata,
                updated_at = now()
            returning id
            """,
            (
                asset["asset_type"],
                asset["stable_id"],
                asset["version"],
                asset["display_name"],
                asset["status"],
                asset["authority"],
                stable_json(asset["effective_scope"]),
                stable_json(asset["source_evidence"]),
                stable_json(asset["metadata"]),
            ),
        ).fetchone()
        ids[(asset["asset_type"], asset["stable_id"])] = str(row["id"])
    return ids


def upsert_migration(conn: psycopg.Connection, summary: dict[str, Any], backup_manifest: str) -> str:
    impact_report = {
        "importKey": IMPORT_KEY,
        "mode": "candidate_import",
        "productionActivationAllowed": False,
        "counts": summary,
        "reviewRequired": True,
    }
    rollback_snapshot = {
        "importKey": IMPORT_KEY,
        "backupManifest": backup_manifest,
        "rollbackMode": "delete_imported_candidate_batch_before_review",
        "deleteCriteria": {
            "domainAssetVersions": {"source_evidence.importKey": IMPORT_KEY, "status": "candidate"},
            "domainAssetMappings": {"evidence.importKey": IMPORT_KEY, "reviewStatus": "pending_review"},
            "reviewQueueItems": {"payload.importKey": IMPORT_KEY},
        },
    }
    row = conn.execute(
        """
        insert into domain_asset_migrations (
            migration_key, status, impact_report, rollback_snapshot, created_by, created_at
        )
        values (%s, 'pending_review', %s::jsonb, %s::jsonb, 'c002_candidate_import', now())
        on conflict (migration_key) do update set
            status = 'pending_review',
            impact_report = excluded.impact_report,
            rollback_snapshot = excluded.rollback_snapshot
        returning id
        """,
        (IMPORT_KEY, stable_json(impact_report), stable_json(rollback_snapshot)),
    ).fetchone()
    return str(row["id"])


def upsert_mappings(conn: psycopg.Connection, mappings: list[dict[str, Any]], asset_ids: dict[tuple[str, str], str], migration_id: str) -> None:
    for mapping in mappings:
        conn.execute(
            """
            insert into domain_asset_mappings (
                source_asset_version_id, target_asset_version_id, mapping_type, confidence,
                review_status, auto_applied, evidence, migration_id, created_at
            )
            values (%s, %s, %s, %s, 'pending_review', false, %s::jsonb, %s, now())
            on conflict (source_asset_version_id, target_asset_version_id, mapping_type) do update set
                confidence = excluded.confidence,
                review_status = 'pending_review',
                auto_applied = false,
                evidence = excluded.evidence,
                migration_id = excluded.migration_id,
                reviewed_at = null
            """,
            (
                asset_ids[mapping["source_key"]],
                asset_ids[mapping["target_key"]],
                mapping["mapping_type"],
                mapping["confidence"],
                stable_json(mapping["evidence"]),
                migration_id,
            ),
        )


def upsert_review_item(conn: psycopg.Connection, payload: dict[str, Any]) -> str:
    existing = conn.execute(
        """
        select id from review_queue_items
        where review_type = 'c002_candidate_import'
          and payload->>'importKey' = %s
        order by created_at desc
        limit 1
        """,
        (IMPORT_KEY,),
    ).fetchone()
    if existing:
        conn.execute(
            """
            update review_queue_items
            set status = 'open', payload = %s::jsonb, resolved_at = null
            where id = %s
            """,
            (stable_json(payload), existing["id"]),
        )
        return str(existing["id"])

    row = conn.execute(
        """
        insert into review_queue_items (review_type, status, payload, created_at)
        values ('c002_candidate_import', 'open', %s::jsonb, now())
        returning id
        """,
        (stable_json(payload),),
    ).fetchone()
    return str(row["id"])


def current_counts(conn: psycopg.Connection) -> dict[str, int]:
    return {
        "domainAssetVersions": conn.execute("select count(*) as c from domain_asset_versions").fetchone()["c"],
        "domainAssetMappings": conn.execute("select count(*) as c from domain_asset_mappings").fetchone()["c"],
        "domainAssetMigrations": conn.execute("select count(*) as c from domain_asset_migrations").fetchone()["c"],
        "reviewQueueItems": conn.execute("select count(*) as c from review_queue_items where review_type='c002_candidate_import'").fetchone()["c"],
        "activeDomainAssetVersions": conn.execute("select count(*) as c from domain_asset_versions where status='active'").fetchone()["c"],
    }


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-root", default="c002-k12-question-graph-candidate-csvs/cleaned")
    parser.add_argument("--material-batch-key", default="guangzhou_physics_2016_2025")
    parser.add_argument("--report-path", default="docs/evidence/c002-candidate-import-report.json")
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    input_root = pathlib.Path(args.input_root)
    report_path = pathlib.Path(args.report_path)
    manifest = load_manifest(input_root)

    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        source_documents_by_name = fetch_source_documents(conn, args.material_batch_key)
        assets, missing_asset_materials = build_assets(input_root, manifest, source_documents_by_name)
        external_candidates, missing_external_materials = build_external_candidates(input_root, manifest, source_documents_by_name)
        asset_keys = {(asset["asset_type"], asset["stable_id"]) for asset in assets}
        mappings, skipped_external_source_mappings = build_mappings(input_root, asset_keys)

        missing_materials = sorted(set(missing_asset_materials + missing_external_materials))
        existing_assets = get_existing_assets(conn, assets)
        protected_existing = [row for row in existing_assets if row["status"] in {"active", "reviewed"}]
        summary = {
            "assets": len(assets),
            "mappings": len(mappings),
            "externalAiCandidates": len(external_candidates),
            "sourceManifestMaterials": len(manifest),
            "resolvedSourceDocuments": len({str(row["source_document_id"]) for row in source_documents_by_name.values()}),
            "missingSourceMaterialIds": len(missing_materials),
            "assetTypes": dict(Counter(asset["asset_type"] for asset in assets)),
            "mappingTypes": dict(Counter(mapping["mapping_type"] for mapping in mappings)),
            "skippedExternalSourceMappings": len(skipped_external_source_mappings),
            "skippedExternalSourceMappingTypes": dict(Counter(item["sourceAssetType"] for item in skipped_external_source_mappings)),
            "skippedExternalSourceImpactScopes": dict(Counter(item["impactScope"] for item in skipped_external_source_mappings)),
        }
        before = current_counts(conn)

        report: dict[str, Any] = {
            "status": "dry_run",
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "task": "C002K",
            "importKey": IMPORT_KEY,
            "materialBatchKey": args.material_batch_key,
            "inputRoot": str(input_root),
            "apply": args.apply,
            "backupManifest": args.backup_manifest,
            "summary": summary,
            "before": before,
            "after": before,
            "missingSourceMaterialIds": missing_materials,
            "skippedExternalSourceMappings": skipped_external_source_mappings[:50],
            "protectedExistingAssets": protected_existing,
            "productionActivationAllowed": False,
            "candidateOnly": True,
            "reportHash": "",
        }

        if missing_materials:
            report["status"] = "blocked"
            report["error"] = "source_material_alignment_failed"
            write_report(report_path, report)
            raise SystemExit(2)
        if protected_existing:
            report["status"] = "blocked"
            report["error"] = "would_overwrite_reviewed_or_active_assets"
            write_report(report_path, report)
            raise SystemExit(3)

        if args.apply:
            if not args.backup_manifest:
                report["status"] = "blocked"
                report["error"] = "backup_manifest_required_for_apply"
                write_report(report_path, report)
                raise SystemExit(4)
            with conn.transaction():
                asset_ids = upsert_assets(conn, assets)
                migration_id = upsert_migration(conn, summary, args.backup_manifest)
                upsert_mappings(conn, mappings, asset_ids, migration_id)
                review_payload = {
                    "importKey": IMPORT_KEY,
                    "task": "C002K",
                    "status": "pending_review",
                    "productionEligible": False,
                    "materialBatchKey": args.material_batch_key,
                    "summary": summary,
                    "externalAiCandidates": external_candidates,
                    "migrationId": migration_id,
                    "backupManifest": args.backup_manifest,
                }
                review_item_id = upsert_review_item(conn, review_payload)
            after = current_counts(conn)
            report.update(
                {
                    "status": "applied",
                    "after": after,
                    "migrationId": migration_id,
                    "reviewQueueItemId": review_item_id,
                }
            )

        report["reportHash"] = sha256_text(stable_json({k: v for k, v in report.items() if k != "reportHash"}))
        write_report(report_path, report)
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
