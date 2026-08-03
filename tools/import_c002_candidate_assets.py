from __future__ import annotations

import argparse
import csv
import hashlib
import json
import pathlib
import re
import subprocess
import uuid
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
REGIONAL_PROFILE_IMPORT_KEY = "cek023_regional_exam_profile_candidate_v1"
REGIONAL_PROFILE_REVIEW_TYPE = "regional_exam_profile"
GUANGZHOU_V2_WORKFLOW_KEY = "guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1"
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


def verify_backup_manifest(manifest_path: pathlib.Path) -> dict[str, Any]:
    if not manifest_path.is_file():
        raise ValueError(f"backup manifest missing:{manifest_path}")
    repo_root = pathlib.Path(__file__).resolve().parents[1]
    verifier = repo_root / "tools" / "verify-backup.ps1"
    completed = subprocess.run(
        [
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(verifier),
            "-ManifestPath",
            str(manifest_path),
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise ValueError(f"backup verification failed:{detail}")
    for line in reversed(completed.stdout.splitlines()):
        try:
            result = json.loads(line)
        except json.JSONDecodeError:
            continue
        if result.get("status") != "ok":
            break
        return result
    raise ValueError("backup verification failed:missing ok result")


def build_regional_profile_assets(package: dict[str, Any]) -> list[dict[str, Any]]:
    if package.get("status") != "pass" or package.get("taskId") != "CEK-22":
        raise ValueError("CEK-22 passing profile package required")

    assets: list[dict[str, Any]] = []
    stable_ids: set[str] = set()
    for item in package.get("profiles", []):
        profile = dict(item.get("profile") or {})
        diagnostics = dict(item.get("diagnostics") or {})
        traceability = dict(item.get("traceability") or {})
        stable_id = str(profile.get("stable_id", "")).strip()
        if not stable_id or stable_id in stable_ids:
            raise ValueError(f"regional profile stable_id missing or duplicated:{stable_id}")
        stable_ids.add(stable_id)
        if (
            profile.get("semantic_type") != "RegionalExamPointProfile"
            or profile.get("storage_asset_type") != "exam_point"
            or profile.get("status") != "candidate"
            or profile.get("review_status") != "pending_review"
            or profile.get("production_eligible") is not False
        ):
            raise ValueError(f"regional profile must remain candidate-safe:{stable_id}")

        anchor_roles = sorted({str(value) for value in traceability.get("anchorRoles", [])})
        if not {"paper", "answer", "report"}.issubset(anchor_roles):
            raise ValueError(f"regional profile traceability incomplete:{stable_id}")
        actual_anchor_roles = {
            str(anchor.get("role"))
            for anchor in traceability.get("anchors", [])
            if isinstance(anchor, dict)
        }
        if not {"paper", "answer", "report"}.issubset(actual_anchor_roles):
            raise ValueError(f"regional profile traceability anchors incomplete:{stable_id}")
        occurrence_years = sorted({int(value) for value in diagnostics.get("occurrenceYears", [])})
        trend = dict(profile.get("trend") or {})
        minimum_years = int(trend.get("minimum_comparable_years", 3))
        if len(occurrence_years) < minimum_years and trend.get("status") != "insufficient_evidence":
            raise ValueError(f"regional profile trend requires at least three occurrence years:{stable_id}")

        evidence_target_ids = sorted({
            str(value) for value in traceability.get("assessmentTargetIds", []) if str(value)
        })
        try:
            if not evidence_target_ids:
                raise ValueError
            evidence_target_ids = sorted(str(uuid.UUID(value)) for value in evidence_target_ids)
        except (ValueError, AttributeError) as exc:
            raise ValueError(f"regional profile evidence target ids invalid:{stable_id}") from exc
        metadata = {
            **profile,
            "diagnostics": diagnostics,
            "candidateImportKey": REGIONAL_PROFILE_IMPORT_KEY,
            "candidateOnly": True,
            "externalAiWriteAllowed": False,
        }
        source_evidence = {
            "importKey": REGIONAL_PROFILE_IMPORT_KEY,
            "sourceTaskId": "CEK-22",
            "sourceCheckedAt": package.get("checkedAt"),
            "evidenceTargetIds": evidence_target_ids,
            "traceability": traceability,
            "candidateOnly": True,
            "reviewStatus": "pending_review",
            "productionEligible": False,
        }
        year_range = dict(profile.get("year_range") or {})
        knowledge_ids = [str(value) for value in profile.get("knowledge_stable_ids", []) if str(value)]
        display_subject = knowledge_ids[0] if knowledge_ids else stable_id
        assets.append({
            "asset_type": "exam_point",
            "stable_id": stable_id,
            "version": int(profile.get("version", VERSION)),
            "display_name": (
                f"Guangzhou physics regional profile {display_subject} "
                f"({year_range.get('start_year')}-{year_range.get('end_year')})"
            ),
            "status": "candidate",
            "authority": "source_derived",
            "effective_scope": {
                "subject": profile.get("subject"),
                "stage": profile.get("stage"),
                "region": profile.get("region"),
                "yearRange": year_range,
                "standardRegime": profile.get("standard_regime"),
            },
            "source_evidence": source_evidence,
            "metadata": metadata,
        })

    if not assets:
        raise ValueError("CEK-22 profile package contains no importable profiles")
    return assets


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
        select asset_type, stable_id, version, status, source_evidence
        from domain_asset_versions
        where (asset_type, stable_id, version) in (
            select * from unnest(%s::text[], %s::text[], %s::int[])
        )
        """,
        ([v[0] for v in values], [v[1] for v in values], [v[2] for v in values]),
    ).fetchall()


def upsert_assets(
    conn: psycopg.Connection,
    assets: list[dict[str, Any]],
    *,
    conflict_import_key: str | None = None,
) -> dict[tuple[str, str], str]:
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
            where %s::text is null or (
                domain_asset_versions.status = 'candidate'
                and domain_asset_versions.source_evidence->>'importKey' = %s
            )
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
                conflict_import_key,
                conflict_import_key,
            ),
        ).fetchone()
        if row is None:
            raise RuntimeError(
                "asset conflict guard rejected overwrite:"
                f"{asset['asset_type']}:{asset['stable_id']}:{asset['version']}"
            )
        ids[(asset["asset_type"], asset["stable_id"])] = str(row["id"])
    return ids


def upsert_migration(
    conn: psycopg.Connection,
    summary: dict[str, Any],
    backup_manifest: str,
    import_key: str = IMPORT_KEY,
    created_by: str = "c002_candidate_import",
    mode: str = "candidate_import",
    impact_fields: dict[str, Any] | None = None,
    rollback_mode: str = "delete_imported_candidate_batch_before_review",
    delete_criteria: dict[str, Any] | None = None,
) -> str:
    impact_report = {
        "importKey": import_key,
        "mode": mode,
        "productionActivationAllowed": False,
        "counts": summary,
        "reviewRequired": True,
    }
    impact_report.update(impact_fields or {})
    rollback_snapshot = {
        "importKey": import_key,
        "backupManifest": backup_manifest,
        "rollbackMode": rollback_mode,
        "deleteCriteria": delete_criteria or {
            "domainAssetVersions": {"source_evidence.importKey": import_key, "status": "candidate"},
            "domainAssetMappings": {"evidence.importKey": import_key, "reviewStatus": "pending_review"},
            "reviewQueueItems": {"payload.importKey": import_key},
        },
    }
    row = conn.execute(
        """
        insert into domain_asset_migrations (
            migration_key, status, impact_report, rollback_snapshot, created_by, created_at
        )
        values (%s, 'pending_review', %s::jsonb, %s::jsonb, %s, now())
        on conflict (migration_key) do update set
            status = 'pending_review',
            impact_report = excluded.impact_report,
            rollback_snapshot = excluded.rollback_snapshot
        returning id
        """,
        (import_key, stable_json(impact_report), stable_json(rollback_snapshot), created_by),
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


def upsert_review_item(
    conn: psycopg.Connection,
    payload: dict[str, Any],
    import_key: str = IMPORT_KEY,
    review_type: str = "c002_candidate_import",
) -> str:
    existing = conn.execute(
        """
        select id from review_queue_items
        where review_type = %s
          and payload->>'importKey' = %s
        order by created_at desc
        limit 1
        """,
        (review_type, import_key),
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
        values (%s, 'open', %s::jsonb, now())
        returning id
        """,
        (review_type, stable_json(payload)),
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


def get_existing_regional_profile_assets(
    conn: psycopg.Connection,
    assets: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    if not assets:
        return []
    values = [(asset["stable_id"], asset["version"]) for asset in assets]
    return conn.execute(
        """
        select stable_id, version, status, source_evidence->>'importKey' as import_key
        from domain_asset_versions
        where asset_type = 'exam_point'
          and (stable_id, version) in (
              select * from unnest(%s::text[], %s::int[])
          )
        order by stable_id, version
        """,
        ([value[0] for value in values], [value[1] for value in values]),
    ).fetchall()


def regional_profile_state(conn: psycopg.Connection) -> dict[str, Any]:
    return conn.execute(
        """
        select json_build_object(
          'activeAssets', (select count(*) from domain_asset_versions where status = 'active'),
          'activeAssetFingerprint', (
            select md5(string_agg(concat_ws('|', id::text, asset_type, stable_id, version::text,
              display_name, status, authority, effective_scope::text, source_evidence::text, metadata::text),
              E'\n' order by id))
            from domain_asset_versions where status = 'active'
          ),
          'profileCandidates', (
            select count(*) from domain_asset_versions
            where asset_type = 'exam_point'
              and source_evidence->>'importKey' = %s
          ),
          'unsafeProfiles', (
            select count(*) from domain_asset_versions
            where asset_type = 'exam_point'
              and source_evidence->>'importKey' = %s
              and (status <> 'candidate'
                or metadata->>'review_status' <> 'pending_review'
                or coalesce((metadata->>'production_eligible')::boolean, true))
          ),
          'profileFingerprint', (
            select md5(string_agg(concat_ws('|', id::text, stable_id, version::text,
              status, effective_scope::text, source_evidence::text, metadata::text),
              E'\n' order by stable_id, version))
            from domain_asset_versions
            where asset_type = 'exam_point'
              and source_evidence->>'importKey' = %s
          ),
          'reviewItems', (
            select count(*) from review_queue_items
            where review_type = %s and payload->>'importKey' = %s
          ),
          'migrations', (
            select count(*) from domain_asset_migrations where migration_key = %s
          ),
          'questionCount', (
            select count(*) from question_items
            where custom_fields->>'sourceWorkflowKey' = %s
          ),
          'questionFingerprint', (
            select md5(string_agg(to_jsonb(q)::text, E'\n' order by id))
            from question_items q
            where q.custom_fields->>'sourceWorkflowKey' = %s
          )
        ) as value
        """,
        (
            REGIONAL_PROFILE_IMPORT_KEY,
            REGIONAL_PROFILE_IMPORT_KEY,
            REGIONAL_PROFILE_IMPORT_KEY,
            REGIONAL_PROFILE_REVIEW_TYPE,
            REGIONAL_PROFILE_IMPORT_KEY,
            REGIONAL_PROFILE_IMPORT_KEY,
            GUANGZHOU_V2_WORKFLOW_KEY,
            GUANGZHOU_V2_WORKFLOW_KEY,
        ),
    ).fetchone()["value"]


def write_report(path: pathlib.Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


def run_regional_profile_import(
    conn: psycopg.Connection,
    package_path: pathlib.Path,
    report_path: pathlib.Path,
    backup_manifest: str,
    apply: bool,
) -> None:
    if not package_path.is_file():
        raise ValueError(f"regional profile package missing:{package_path}")
    package_bytes = package_path.read_bytes()
    package = json.loads(package_bytes.decode("utf-8-sig"))
    assets = build_regional_profile_assets(package)
    package_sha256 = hashlib.sha256(package_bytes).hexdigest()
    backup_verification = None
    if apply:
        if not backup_manifest:
            raise ValueError("verified backup manifest required for apply")
        backup_verification = verify_backup_manifest(pathlib.Path(backup_manifest))
    existing = get_existing_regional_profile_assets(conn, assets)
    protected_existing = [
        row for row in existing
        if row["status"] != "candidate" or row["import_key"] != REGIONAL_PROFILE_IMPORT_KEY
    ]
    before = regional_profile_state(conn)
    if before["questionCount"] != 234:
        raise ValueError("regional profile import requires the complete 234-question corpus")
    summary = {
        "profiles": len(assets),
        "assetTypes": dict(Counter(asset["asset_type"] for asset in assets)),
        "candidateAssets": sum(asset["status"] == "candidate" for asset in assets),
        "productionEligibleAssets": sum(bool(asset["metadata"].get("production_eligible")) for asset in assets),
        "windows": dict(Counter(
            asset["metadata"]["diagnostics"].get("windowId", "unknown") for asset in assets
        )),
        "evidenceTargetIds": len({
            target_id
            for asset in assets
            for target_id in asset["source_evidence"]["evidenceTargetIds"]
        }),
        "stableIds": [asset["stable_id"] for asset in assets],
    }
    report: dict[str, Any] = {
        "schemaVersion": "cek023-regional-exam-profile-import.v1",
        "status": "dry_run",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "taskId": "CEK-23",
        "importKey": REGIONAL_PROFILE_IMPORT_KEY,
        "packagePath": str(package_path),
        "packageSha256": package_sha256,
        "apply": apply,
        "backupManifest": backup_manifest,
        "backupVerified": backup_verification is not None,
        "backupVerification": backup_verification,
        "summary": summary,
        "before": before,
        "after": before,
        "protectedExistingAssets": protected_existing,
        "candidateOnly": True,
        "productionActivationAllowed": False,
        "activeQuestionRewriteAllowed": False,
        "reportHash": "",
    }
    if protected_existing:
        report.update(status="blocked", error="would_overwrite_foreign_reviewed_or_active_profile")
        write_report(report_path, report)
        raise SystemExit(5)

    if apply:
        with conn.transaction():
            upsert_assets(
                conn,
                assets,
                conflict_import_key=REGIONAL_PROFILE_IMPORT_KEY,
            )
            migration_id = upsert_migration(
                conn,
                summary,
                backup_manifest,
                import_key=REGIONAL_PROFILE_IMPORT_KEY,
                created_by="cek023_profile_import",
                mode="regional_exam_profile_candidate_import",
                impact_fields={
                    "packageSha256": package_sha256,
                    "activeQuestionRewriteAllowed": False,
                },
                rollback_mode="delete_profile_candidates_before_review_or_restore_backup",
                delete_criteria={
                    "domainAssetVersions": {
                        "assetType": "exam_point",
                        "sourceEvidence.importKey": REGIONAL_PROFILE_IMPORT_KEY,
                        "status": "candidate",
                    },
                    "reviewQueueItems": {
                        "reviewType": REGIONAL_PROFILE_REVIEW_TYPE,
                        "payload.importKey": REGIONAL_PROFILE_IMPORT_KEY,
                    },
                    "domainAssetMigrations": {
                        "migrationKey": REGIONAL_PROFILE_IMPORT_KEY,
                    },
                },
            )
            review_item_id = upsert_review_item(conn, {
                "importKey": REGIONAL_PROFILE_IMPORT_KEY,
                "taskId": "CEK-23",
                "status": "pending_review",
                "productionEligible": False,
                "profileStableIds": summary["stableIds"],
                "packageSha256": package_sha256,
                "migrationId": migration_id,
                "backupManifest": backup_manifest,
            }, import_key=REGIONAL_PROFILE_IMPORT_KEY, review_type=REGIONAL_PROFILE_REVIEW_TYPE)
            after = regional_profile_state(conn)
            if (
                after["activeAssets"] != before["activeAssets"]
                or after["activeAssetFingerprint"] != before["activeAssetFingerprint"]
                or after["questionCount"] != before["questionCount"]
                or after["questionFingerprint"] != before["questionFingerprint"]
            ):
                raise RuntimeError("regional profile import changed active assets or historical questions")
            if (
                after["profileCandidates"] != len(assets)
                or after["unsafeProfiles"] != 0
                or after["reviewItems"] != 1
                or after["migrations"] != 1
            ):
                raise RuntimeError("regional profile import postconditions failed")
        report.update(status="applied", after=after, migrationId=migration_id, reviewQueueItemId=review_item_id)

    report["reportHash"] = sha256_text(stable_json({k: v for k, v in report.items() if k != "reportHash"}))
    write_report(report_path, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-root", default="c002-k12-question-graph-candidate-csvs/cleaned")
    parser.add_argument("--material-batch-key", default="guangzhou_physics_2016_2025")
    parser.add_argument("--report-path", default="docs/evidence/c002-candidate-import-report.json")
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument("--regional-profile-package", type=pathlib.Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    input_root = pathlib.Path(args.input_root)
    report_path = pathlib.Path(args.report_path)
    if args.regional_profile_package:
        with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
            run_regional_profile_import(
                conn,
                args.regional_profile_package,
                report_path,
                args.backup_manifest,
                args.apply,
            )
        return 0

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
