from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import psycopg
from psycopg.rows import dict_row


IMPORT_KEY = "cek009_curriculum_requirements_2022_2025_v1"
ALLOWED_MAPPING_TYPES = {"equivalent", "broader", "narrower"}


class CurriculumImportError(RuntimeError):
    pass


def validate_apply_authority(database_name: str, allow_main_candidate_write: bool) -> None:
    normalized = database_name.casefold()
    if "cek009" in normalized:
        return
    if normalized == "k12_question_graph" and allow_main_candidate_write:
        return
    raise CurriculumImportError("apply requires an isolated CEK009 database or explicit main candidate-write authority")


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _safe(envelope: dict[str, Any], name: str) -> None:
    governance = envelope.get("governance", {})
    if (
        governance.get("status") != "candidate"
        or governance.get("review_status") != "pending_review"
        or governance.get("production_eligible") is not False
        or governance.get("c002_active_write") is not False
    ):
        raise CurriculumImportError(f"{name} is not a safe candidate envelope")


def _normalize_anchor(anchor: dict[str, Any]) -> dict[str, Any]:
    return {
        "sourceDocumentId": anchor.get("source_document_id"),
        "sourceRegionId": anchor.get("source_region_id"),
        "sourceDocumentVersion": anchor.get("source_document_version"),
        "sourceDocumentSha256": anchor.get("source_document_sha256"),
        "pdfPageNumber": anchor.get("pdf_page_number"),
        "printedPageNumber": anchor.get("printed_page_number"),
        "sectionPath": list(anchor.get("section_path", [])),
        "officialItemCode": anchor.get("official_item_code"),
        "textBlockSha256": anchor.get("text_block_sha256"),
        "evidenceRole": anchor.get("evidence_role"),
    }


def _deduplicate_anchors(anchors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for anchor in anchors:
        normalized = _normalize_anchor(anchor)
        key = stable_json(normalized)
        if key not in seen:
            result.append(normalized)
            seen.add(key)
    return result


def build_package(requirements: dict[str, Any], crosswalk: dict[str, Any]) -> dict[str, Any]:
    _safe(requirements, "requirements")
    _safe(crosswalk, "crosswalk")
    assets: list[dict[str, Any]] = []
    facet_ids: set[str] = set()
    for item in requirements.get("requirements", []):
        parent_id = item["parent_requirement_stable_id"]
        anchors = list(item.get("source_anchor_sha256s", []))
        if not anchors:
            raise CurriculumImportError(f"requirement lacks anchors: {parent_id}")
        parent_evidence_anchors = _deduplicate_anchors([
            anchor
            for wrapper in item.get("facets", [])
            for anchor in wrapper.get("facet", {}).get("evidence_anchors", [])
        ])
        if not parent_evidence_anchors:
            raise CurriculumImportError(f"requirement lacks full evidence anchors: {parent_id}")
        assets.append(
            {
                "asset_type": "curriculum_requirement",
                "stable_id": parent_id,
                "version": 1,
                "display_name": f'课程要求 {item["official_item_code"]}',
                "status": "candidate",
                "authority": "source_derived",
                "effective_scope": {"subject": "physics", "stage": "junior_middle_school"},
                "source_evidence": {
                    "importKey": IMPORT_KEY,
                    "anchorSha256s": anchors,
                    "evidenceAnchors": parent_evidence_anchors,
                    "sourceTextSha256": item["source_text_sha256"],
                    "reviewStatus": "pending_review",
                    "productionEligible": False,
                },
                "metadata": {
                    "officialItemCode": item["official_item_code"],
                    "legacyAssetType": "curriculum_standard_item",
                    "candidateOnly": True,
                },
            }
        )
        for wrapper in item.get("facets", []):
            facet = wrapper["facet"]
            facet_id = facet["stable_id"]
            if facet_id in facet_ids:
                raise CurriculumImportError(f"duplicate facet: {facet_id}")
            facet_ids.add(facet_id)
            facet_anchors = [a["text_block_sha256"] for a in facet.get("evidence_anchors", [])]
            if not facet_anchors:
                raise CurriculumImportError(f"facet lacks anchors: {facet_id}")
            facet_evidence_anchors = _deduplicate_anchors(facet.get("evidence_anchors", []))
            assets.append(
                {
                    "asset_type": "requirement_facet",
                    "stable_id": facet_id,
                    "version": 1,
                    "display_name": facet["facet_statement"],
                    "status": "candidate",
                    "authority": "source_derived",
                    "effective_scope": {"subject": "physics", "stage": "junior_middle_school"},
                    "source_evidence": {
                        "importKey": IMPORT_KEY,
                        "anchorSha256s": facet_anchors,
                        "evidenceAnchors": facet_evidence_anchors,
                        "reviewStatus": "pending_review",
                        "productionEligible": False,
                    },
                    "metadata": {
                        "parentRequirementStableId": parent_id,
                        "officialItemCode": item["official_item_code"],
                        "legacyAssetType": "curriculum_standard_item",
                        "candidateOnly": True,
                        "confidence": facet["confidence"],
                    },
                }
            )

    mappings: list[dict[str, Any]] = []
    for item in crosswalk.get("mappings", []):
        if item["source_stable_id"] not in facet_ids:
            raise CurriculumImportError(f'mapping references unknown facet: {item["source_stable_id"]}')
        if item["mapping_type"] not in ALLOWED_MAPPING_TYPES:
            raise CurriculumImportError(f'forbidden mapping type: {item["mapping_type"]}')
        if (
            item.get("review_status") != "pending_review"
            or item.get("auto_apply_allowed") is not False
            or item.get("rollback_required") is not True
        ):
            raise CurriculumImportError(f'unsafe mapping: {item["mapping_id"]}')
        mappings.append(
            {
                "mapping_id": item["mapping_id"],
                "source_key": ("requirement_facet", item["source_stable_id"]),
                "target_key": ("knowledge_point", item["target_knowledge_code"]),
                "mapping_type": item["mapping_type"],
                "confidence": item["confidence"],
                "review_status": "pending_review",
                "rollback_required": True,
                "evidence": {
                    "importKey": IMPORT_KEY,
                    "mappingId": item["mapping_id"],
                    "anchorSha256": item["evidence_anchor_sha256"],
                    "rollbackRequired": True,
                },
            }
        )
    return {"import_key": IMPORT_KEY, "assets": assets, "mappings": mappings}


def active_fingerprint(conn: psycopg.Connection) -> dict[str, Any]:
    rows = conn.execute(
        """
        select 'domain_asset_version' as kind, asset_type as type, stable_id, version
        from domain_asset_versions where status='active'
        union all
        select 'knowledge_node', node_type, code, version
        from knowledge_nodes where status='active'
        order by 1,2,3,4
        """
    ).fetchall()
    payload = [[row["kind"], row["type"], row["stable_id"], row["version"]] for row in rows]
    return {"count": len(payload), "sha256": sha256_text(stable_json(payload))}


def resolve_target_ids(conn: psycopg.Connection, package: dict[str, Any]) -> dict[tuple[str, str], str]:
    codes = sorted({mapping["target_key"][1] for mapping in package["mappings"]})
    rows = conn.execute(
        """select id, stable_id from domain_asset_versions
        where asset_type='knowledge_point' and status='active' and stable_id = any(%s)""",
        (codes,),
    ).fetchall()
    found = {row["stable_id"]: str(row["id"]) for row in rows}
    missing = sorted(set(codes) - set(found))
    if missing:
        raise CurriculumImportError(f"active knowledge targets missing: {','.join(missing[:10])}")
    return {("knowledge_point", code): found[code] for code in codes}


def apply_package(conn: psycopg.Connection, package: dict[str, Any], backup_manifest: str) -> dict[str, int]:
    ids: dict[tuple[str, str], str] = {}
    for asset in package["assets"]:
        existing = conn.execute(
            """select id,status from domain_asset_versions
            where asset_type=%s and stable_id=%s and version=%s""",
            (asset["asset_type"], asset["stable_id"], asset["version"]),
        ).fetchone()
        if existing and existing["status"] != "candidate":
            raise CurriculumImportError(f'protected asset exists: {asset["asset_type"]}:{asset["stable_id"]}')
        row = conn.execute(
            """insert into domain_asset_versions
            (asset_type,stable_id,version,display_name,status,authority,effective_scope,source_evidence,metadata,created_at,updated_at)
            values (%s,%s,%s,%s,'candidate','source_derived',%s::jsonb,%s::jsonb,%s::jsonb,now(),now())
            on conflict (asset_type,stable_id,version) do update set
              display_name=excluded.display_name,source_evidence=excluded.source_evidence,
              metadata=excluded.metadata,updated_at=now()
            returning id""",
            (
                asset["asset_type"], asset["stable_id"], asset["version"], asset["display_name"],
                stable_json(asset["effective_scope"]), stable_json(asset["source_evidence"]),
                stable_json(asset["metadata"]),
            ),
        ).fetchone()
        ids[(asset["asset_type"], asset["stable_id"])] = str(row["id"])
    ids.update(resolve_target_ids(conn, package))
    migration = conn.execute(
        """insert into domain_asset_migrations
        (migration_key,status,impact_report,rollback_snapshot,created_by,created_at)
        values (%s,'pending_review',%s::jsonb,%s::jsonb,'cek009_curriculum_import',now())
        on conflict (migration_key) do update set impact_report=excluded.impact_report,
          rollback_snapshot=excluded.rollback_snapshot,status='pending_review'
        returning id""",
        (
            IMPORT_KEY,
            stable_json({"candidateOnly": True, "assetCount": len(package["assets"]), "mappingCount": len(package["mappings"])}),
            stable_json({"backupManifest": backup_manifest, "importKey": IMPORT_KEY}),
        ),
    ).fetchone()
    for mapping in package["mappings"]:
        conn.execute(
            """insert into domain_asset_mappings
            (source_asset_version_id,target_asset_version_id,mapping_type,confidence,review_status,auto_applied,evidence,migration_id,created_at)
            values (%s,%s,%s,%s,'pending_review',false,%s::jsonb,%s,now())
            on conflict (source_asset_version_id,target_asset_version_id,mapping_type) do update set
              confidence=excluded.confidence,review_status='pending_review',auto_applied=false,
              evidence=excluded.evidence,migration_id=excluded.migration_id,reviewed_at=null""",
            (ids[mapping["source_key"]], ids[mapping["target_key"]], mapping["mapping_type"],
             mapping["confidence"], stable_json(mapping["evidence"]), migration["id"]),
        )
    return {"assets": len(package["assets"]), "mappings": len(package["mappings"])}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", type=Path, required=True)
    parser.add_argument("--crosswalk", type=Path, required=True)
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--database-name", required=True)
    parser.add_argument("--backup-manifest", default="")
    parser.add_argument("--backup-verified", action="store_true")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--allow-main-candidate-write", action="store_true")
    args = parser.parse_args()
    requirements = json.loads(args.requirements.read_text(encoding="utf-8"))
    crosswalk = json.loads(args.crosswalk.read_text(encoding="utf-8"))
    package = build_package(requirements, crosswalk)
    if args.apply:
        validate_apply_authority(args.database_name, args.allow_main_candidate_write)
    if args.apply and (not args.backup_manifest or not Path(args.backup_manifest).is_file()):
        raise CurriculumImportError("apply requires an existing verified backup manifest")
    if args.apply and not args.backup_verified:
        raise CurriculumImportError("apply requires backup verification in the current run")
    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        before = active_fingerprint(conn)
        resolve_target_ids(conn, package)
        counts = {"assets": len(package["assets"]), "mappings": len(package["mappings"])}
        status = "dry_run"
        if args.apply:
            with conn.transaction():
                counts = apply_package(conn, package, args.backup_manifest)
            status = "applied"
        after = active_fingerprint(conn)
        if before != after:
            raise CurriculumImportError("active fingerprint changed")
        report = {
            "schemaVersion": "cek009-curriculum-candidate-import.v1",
            "status": status,
            "checkedAt": datetime.now(timezone.utc).isoformat(),
            "importKey": IMPORT_KEY,
            "databaseName": args.database_name,
            "isolatedDatabase": "cek009" in args.database_name.casefold(),
            "backupManifest": args.backup_manifest or None,
            "counts": counts,
            "activeBefore": before,
            "activeAfter": after,
            "activeUnchanged": True,
            "candidateOnly": True,
            "productionEligible": False,
        }
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
