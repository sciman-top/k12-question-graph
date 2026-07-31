from __future__ import annotations

import argparse
import hashlib
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping

import psycopg
from psycopg.rows import dict_row

from curriculum_candidate_import import active_fingerprint, stable_json


IMPORT_KEY = "cek019a_guangzhou_observed_exam_evidence_v1"
ID_NAMESPACE = uuid.UUID("ee74a35a-265c-418c-93ba-cec9a75f85bd")
PERFORMANCE_FIELDS = (
    "maximum_score",
    "average_score",
    "score_rate",
    "difficulty_observed",
    "discrimination",
    "option_distribution",
)


class ObservedExamEvidenceImportError(RuntimeError):
    pass


def deterministic_id(value: str) -> str:
    return str(uuid.uuid5(ID_NAMESPACE, value))


def _candidate_only(row: Mapping[str, Any]) -> bool:
    return (
        row.get("status") == "candidate"
        and row.get("review_status") == "pending_review"
        and row.get("production_eligible") is False
    )


def _require_anchor(anchor: Mapping[str, Any] | None, row_key: str) -> None:
    if not anchor or not anchor.get("source_document_id") or not anchor.get("source_region_id"):
        raise ObservedExamEvidenceImportError(f"source region missing:{row_key}")


def performance_metrics(row: Mapping[str, Any]) -> Iterable[tuple[str, Mapping[str, Any]]]:
    for field in PERFORMANCE_FIELDS:
        metric = row.get(field)
        if metric is not None:
            yield field, metric


def performance_anchor(row: Mapping[str, Any]) -> Mapping[str, Any]:
    for _, metric in performance_metrics(row):
        return metric["anchor"]
    raise ObservedExamEvidenceImportError(f"performance row has no metric:{row.get('evidence_id')}")


def metric_ratio(metric: Mapping[str, Any] | None) -> float | None:
    if metric is None:
        return None
    value = float(metric["parsed_value"])
    return value / 100 if metric.get("unit") == "percent" else value


def validate_package(package: Mapping[str, Any]) -> None:
    governance = package.get("governance", {})
    if (
        governance.get("status") != "candidate"
        or governance.get("review_status") != "pending_review"
        or governance.get("production_eligible") is not False
        or governance.get("active_write") is not False
    ):
        raise ObservedExamEvidenceImportError("unsafe observed evidence package")

    collections = (
        ("observed_performance", "evidence_id"),
        ("observed_errors", "evidence_id"),
        ("teaching_recommendations", "recommendation_id"),
    )
    for collection, id_field in collections:
        rows = list(package.get(collection, []))
        ids = [row.get(id_field) for row in rows]
        if any(not value for value in ids) or len(ids) != len(set(ids)):
            raise ObservedExamEvidenceImportError(f"missing or duplicate ids:{collection}")
        for row in rows:
            if not _candidate_only(row):
                raise ObservedExamEvidenceImportError(f"unsafe candidate row:{row.get(id_field)}")
            if not row.get("assessment_target_id") or not row.get("question_scope", {}).get("scope_key"):
                raise ObservedExamEvidenceImportError(f"target scope missing:{row.get(id_field)}")

    for row in package.get("observed_performance", []):
        metrics = list(performance_metrics(row))
        if not metrics:
            raise ObservedExamEvidenceImportError(f"performance row has no metric:{row['evidence_id']}")
        for _, metric in metrics:
            _require_anchor(metric.get("anchor"), row["evidence_id"])
    for row in package.get("observed_errors", []):
        _require_anchor(row.get("anchor"), row["evidence_id"])
    for row in package.get("teaching_recommendations", []):
        _require_anchor(row.get("anchor"), row["recommendation_id"])

    review_rows = list(package.get("review_queue", []))
    review_keys = [row.get("scope_key") for row in review_rows]
    if any(not value for value in review_keys) or len(review_keys) != len(set(review_keys)):
        raise ObservedExamEvidenceImportError("missing or duplicate review scope keys")
    if any(row.get("status") != "pending_review" for row in review_rows):
        raise ObservedExamEvidenceImportError("unsafe review queue row")


def _resolve_target_scope(conn: psycopg.Connection, row: Mapping[str, Any]) -> None:
    scope = row["question_scope"]
    target = conn.execute(
        """select question_item_id::text,question_block_id::text,scope_type
        from assessment_targets where id=%s and batch_key='cek016_guangzhou_assessment_targets_v1'""",
        (row["assessment_target_id"],),
    ).fetchone()
    if not target:
        raise ObservedExamEvidenceImportError(f"assessment target missing:{row['assessment_target_id']}")
    if (
        target["question_item_id"] != scope["question_item_id"]
        or target["question_block_id"] != scope.get("question_block_id")
        or target["scope_type"] != scope["scope_type"]
    ):
        raise ObservedExamEvidenceImportError(f"assessment target scope mismatch:{scope['scope_key']}")


def _resolve_anchor(conn: psycopg.Connection, anchor: Mapping[str, Any]) -> None:
    region = conn.execute(
        "select source_document_id::text from source_regions where id=%s",
        (anchor["source_region_id"],),
    ).fetchone()
    if not region:
        raise ObservedExamEvidenceImportError(f"source region missing:{anchor['source_region_id']}")
    if region["source_document_id"] != anchor["source_document_id"]:
        raise ObservedExamEvidenceImportError(f"source region document mismatch:{anchor['source_region_id']}")


def _validate_references(conn: psycopg.Connection, package: Mapping[str, Any]) -> None:
    checked_targets: set[str] = set()
    checked_regions: set[str] = set()
    for collection in ("observed_performance", "observed_errors", "teaching_recommendations"):
        for row in package.get(collection, []):
            target_id = row["assessment_target_id"]
            if target_id not in checked_targets:
                _resolve_target_scope(conn, row)
                checked_targets.add(target_id)
            anchors = (
                [metric["anchor"] for _, metric in performance_metrics(row)]
                if collection == "observed_performance"
                else [row["anchor"]]
            )
            for anchor in anchors:
                region_id = anchor["source_region_id"]
                if region_id not in checked_regions:
                    _resolve_anchor(conn, anchor)
                    checked_regions.add(region_id)
    _reject_reviewed_overwrites(conn, package)


def _reject_reviewed_overwrites(conn: psycopg.Connection, package: Mapping[str, Any]) -> None:
    table_keys = (
        ("observed_performance_evidence", [f"observed-performance:{row['evidence_id']}" for row in package.get("observed_performance", [])]),
        ("observed_error_evidence", [f"observed-error:{row['evidence_id']}" for row in package.get("observed_errors", [])]),
        ("teaching_recommendations", [f"teaching-recommendation:{row['recommendation_id']}" for row in package.get("teaching_recommendations", [])]),
    )
    for table, stable_keys in table_keys:
        if not stable_keys:
            continue
        rows = conn.execute(
            f"""select stable_key from {table}
            where stable_key = any(%s)
              and (status <> 'candidate' or review_status <> 'pending_review' or production_eligible)""",
            (stable_keys,),
        ).fetchall()
        if rows:
            raise ObservedExamEvidenceImportError(f"reviewed evidence overwrite blocked:{table}:{rows[0]['stable_key']}")

    review_ids = [deterministic_id(f"review:{row['scope_key']}") for row in package.get("review_queue", [])]
    if review_ids:
        rows = conn.execute(
            """select id::text from review_queue_items
            where id::text = any(%s) and status <> 'open'""",
            (review_ids,),
        ).fetchall()
        if rows:
            raise ObservedExamEvidenceImportError(f"resolved review overwrite blocked:{rows[0]['id']}")


def _metric_value(metric: Mapping[str, Any] | None) -> float | None:
    return None if metric is None else float(metric["parsed_value"])


def _performance_sample(row: Mapping[str, Any]) -> tuple[str, int | None]:
    metrics = [metric for _, metric in performance_metrics(row)]
    sample_scope = next((metric.get("sample_scope") for metric in metrics if metric.get("sample_scope")), None)
    sample_size = next((metric.get("sample_size") for metric in metrics if metric.get("sample_size") is not None), None)
    if not sample_scope:
        raise ObservedExamEvidenceImportError(f"performance sample scope missing:{row['evidence_id']}")
    return str(sample_scope), sample_size


def _upsert_performance(
    conn: psycopg.Connection,
    row: Mapping[str, Any],
    backup_manifest: str,
) -> None:
    primary_anchor = performance_anchor(row)
    sample_scope, sample_size = _performance_sample(row)
    raw_statistics = {field: row.get(field) for field in PERFORMANCE_FIELDS}
    evidence = {
        "importKey": IMPORT_KEY,
        "backupManifest": backup_manifest,
        "anchors": [metric["anchor"] for _, metric in performance_metrics(row)],
        "confidenceSource": "page_verified_numeric_candidate_default",
        "candidateOnly": True,
    }
    conn.execute(
        """insert into observed_performance_evidence
        (id,stable_key,batch_key,assessment_target_id,source_region_id,maximum_score,average_score,
         score_rate,difficulty_observed,discrimination,difficulty_direction,sample_scope,sample_size,
         option_distribution,raw_statistics,confidence,status,review_status,production_eligible,evidence,created_at)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'higher_is_easier',%s,%s,%s::jsonb,%s::jsonb,
                0.9,'candidate','pending_review',false,%s::jsonb,now())
        on conflict (stable_key) do update set
          batch_key=excluded.batch_key,assessment_target_id=excluded.assessment_target_id,
          source_region_id=excluded.source_region_id,maximum_score=excluded.maximum_score,
          average_score=excluded.average_score,score_rate=excluded.score_rate,
          difficulty_observed=excluded.difficulty_observed,discrimination=excluded.discrimination,
          difficulty_direction='higher_is_easier',sample_scope=excluded.sample_scope,
          sample_size=excluded.sample_size,option_distribution=excluded.option_distribution,
          raw_statistics=excluded.raw_statistics,confidence=excluded.confidence,status='candidate',
          review_status='pending_review',production_eligible=false,evidence=excluded.evidence""",
        (
            row["evidence_id"], f"observed-performance:{row['evidence_id']}", IMPORT_KEY,
            row["assessment_target_id"], primary_anchor["source_region_id"],
            _metric_value(row.get("maximum_score")), _metric_value(row.get("average_score")),
            metric_ratio(row.get("score_rate")), metric_ratio(row.get("difficulty_observed")),
            _metric_value(row.get("discrimination")), sample_scope, sample_size,
            stable_json(row.get("option_distribution")), stable_json(raw_statistics), stable_json(evidence),
        ),
    )


def _upsert_error(conn: psycopg.Connection, row: Mapping[str, Any], backup_manifest: str) -> None:
    evidence = {"importKey": IMPORT_KEY, "backupManifest": backup_manifest, "anchor": row["anchor"], "candidateOnly": True}
    conn.execute(
        """insert into observed_error_evidence
        (id,stable_key,batch_key,assessment_target_id,source_region_id,record_kind,content,generation_method,
         confidence,status,review_status,production_eligible,evidence,created_at)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,'candidate','pending_review',false,%s::jsonb,now())
        on conflict (stable_key) do update set
          batch_key=excluded.batch_key,assessment_target_id=excluded.assessment_target_id,
          source_region_id=excluded.source_region_id,record_kind=excluded.record_kind,content=excluded.content,
          generation_method=excluded.generation_method,confidence=excluded.confidence,status='candidate',
          review_status='pending_review',production_eligible=false,evidence=excluded.evidence""",
        (
            row["evidence_id"], f"observed-error:{row['evidence_id']}", IMPORT_KEY,
            row["assessment_target_id"], row["anchor"]["source_region_id"], row["record_kind"],
            row["content"], row["generation_method"], row["confidence"], stable_json(evidence),
        ),
    )


def _upsert_recommendation(conn: psycopg.Connection, row: Mapping[str, Any], backup_manifest: str) -> None:
    evidence = {"importKey": IMPORT_KEY, "backupManifest": backup_manifest, "anchor": row["anchor"], "candidateOnly": True}
    conn.execute(
        """insert into teaching_recommendations
        (id,stable_key,batch_key,assessment_target_id,source_region_id,content,author_kind,generation_method,
         confidence,status,review_status,production_eligible,evidence,created_at)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,'candidate','pending_review',false,%s::jsonb,now())
        on conflict (stable_key) do update set
          batch_key=excluded.batch_key,assessment_target_id=excluded.assessment_target_id,
          source_region_id=excluded.source_region_id,content=excluded.content,author_kind=excluded.author_kind,
          generation_method=excluded.generation_method,confidence=excluded.confidence,status='candidate',
          review_status='pending_review',production_eligible=false,evidence=excluded.evidence""",
        (
            row["recommendation_id"], f"teaching-recommendation:{row['recommendation_id']}", IMPORT_KEY,
            row["assessment_target_id"], row["anchor"]["source_region_id"], row["content"],
            row["author_kind"], row["generation_method"], row["confidence"], stable_json(evidence),
        ),
    )


def _upsert_review_queue(conn: psycopg.Connection, package: Mapping[str, Any]) -> int:
    evidence_by_target: dict[str, dict[str, list[str]]] = {}
    for collection, id_field in (
        ("observed_performance", "evidence_id"),
        ("observed_errors", "evidence_id"),
        ("teaching_recommendations", "recommendation_id"),
    ):
        for row in package.get(collection, []):
            bucket = evidence_by_target.setdefault(row["assessment_target_id"], {})
            bucket.setdefault(collection, []).append(row[id_field])

    for review in package.get("review_queue", []):
        payload = {
            "importKey": IMPORT_KEY,
            "assessmentTargetId": review["assessment_target_id"],
            "scopeKey": review["scope_key"],
            "year": review.get("year"),
            "questionNumber": review.get("question_number"),
            "riskLevel": review.get("priority"),
            "reasons": review.get("reasons", []),
            "evidenceIds": evidence_by_target.get(review["assessment_target_id"], {}),
            "productionEligible": False,
        }
        conn.execute(
            """insert into review_queue_items(id,review_type,status,payload,created_at,resolved_at)
            values (%s,'observed_exam_evidence','open',%s::jsonb,now(),null)
            on conflict (id) do update set review_type='observed_exam_evidence',status='open',
              payload=excluded.payload,resolved_at=null""",
            (deterministic_id(f"review:{review['scope_key']}"), stable_json(payload)),
        )
    return len(package.get("review_queue", []))


def import_package(
    conn: psycopg.Connection,
    package: Mapping[str, Any],
    backup_manifest: str,
) -> dict[str, int]:
    validate_package(package)
    _validate_references(conn, package)
    for row in package.get("observed_performance", []):
        _upsert_performance(conn, row, backup_manifest)
    for row in package.get("observed_errors", []):
        _upsert_error(conn, row, backup_manifest)
    for row in package.get("teaching_recommendations", []):
        _upsert_recommendation(conn, row, backup_manifest)
    return {
        "observedPerformance": len(package.get("observed_performance", [])),
        "observedErrors": len(package.get("observed_errors", [])),
        "teachingRecommendations": len(package.get("teaching_recommendations", [])),
        "reviewItems": _upsert_review_queue(conn, package),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--backup-manifest", type=Path, required=True)
    parser.add_argument("--backup-verified", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.apply and (not args.backup_verified or not args.backup_manifest.is_file()):
        raise ObservedExamEvidenceImportError("apply requires a backup verified in the current run")

    package = json.loads(args.package.read_text(encoding="utf-8"))
    validate_package(package)
    counts = {
        "observedPerformance": len(package.get("observed_performance", [])),
        "observedErrors": len(package.get("observed_errors", [])),
        "teachingRecommendations": len(package.get("teaching_recommendations", [])),
        "reviewItems": len(package.get("review_queue", [])),
    }
    with psycopg.connect(args.connection_string, row_factory=dict_row) as conn:
        before = active_fingerprint(conn)
        _validate_references(conn, package)
        status = "dry_run"
        if args.apply:
            with conn.transaction():
                counts = import_package(conn, package, str(args.backup_manifest))
            status = "applied"
        after = active_fingerprint(conn)
        if before != after:
            raise ObservedExamEvidenceImportError("active fingerprint changed")

    report = {
        "schemaVersion": "cek019a-observed-exam-evidence-import.v1",
        "status": status,
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "importKey": IMPORT_KEY,
        "counts": counts,
        "packageSha256": hashlib.sha256(args.package.read_bytes()).hexdigest(),
        "backupManifest": str(args.backup_manifest),
        "activeFingerprintBefore": before,
        "activeFingerprintAfter": after,
        "activeWrite": False,
        "productionEligible": False,
        "completionBoundary": "Candidate evidence import only; every row remains pending review and REAL005 remains not_closed.",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
