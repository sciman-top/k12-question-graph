from __future__ import annotations

import argparse
import csv
import hashlib
import json
import uuid
from collections import Counter, defaultdict
from collections.abc import Iterable, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCOPE_TYPES = frozenset({"whole_question", "subquestion", "scoring_point"})
PENDING_REVIEW = "pending_review"


def build_scope_key(question_id: str, scope_type: str, block_stable_key: str | None = None) -> str:
    question_key = str(question_id).strip()
    normalized_type = str(scope_type).strip()
    stable_key = str(block_stable_key or "").strip()
    if not question_key:
        raise ValueError("question_id_required")
    if normalized_type not in SCOPE_TYPES:
        raise ValueError(f"invalid_question_scope_type:{normalized_type}")
    if normalized_type == "whole_question":
        if stable_key:
            raise ValueError("whole_question_block_reference_forbidden")
        return f"question-scope:v1:{question_key}:whole_question"
    if not stable_key:
        raise ValueError(f"question_block_stable_key_required:{normalized_type}")
    return f"question-scope:v1:{question_key}:{normalized_type}:{stable_key}"


def _scope(
    question_id: str,
    scope_type: str,
    block_stable_key: str | None = None,
) -> dict[str, Any]:
    block_ref = None
    if block_stable_key is not None:
        scope_key = build_scope_key(question_id, scope_type, block_stable_key)
        block_ref = {
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, scope_key)),
            "blockType": scope_type,
            "stableKey": block_stable_key,
        }
    return {
        "scopeKey": build_scope_key(question_id, scope_type, block_stable_key),
        "scopeType": scope_type,
        "questionId": question_id,
        "questionBlockRef": block_ref,
        "reviewStatus": PENDING_REVIEW,
        "productionEligible": False,
    }


def _block_candidate(
    question_id: str,
    block_type: str,
    stable_key: str,
    label: str,
    text: str,
) -> dict[str, Any]:
    scope_key = build_scope_key(question_id, block_type, stable_key)
    return {
        "type": block_type,
        "stableKey": stable_key,
        "scopeKey": scope_key,
        "questionBlockId": str(uuid.uuid5(uuid.NAMESPACE_URL, scope_key)),
        "label": label,
        "text": text,
        "reviewStatus": PENDING_REVIEW,
        "productionEligible": False,
    }


def normalize_question_scopes(
    question_id: str,
    subquestions: Iterable[Mapping[str, Any]],
    scoring_points: Iterable[Mapping[str, Any]],
) -> dict[str, Any]:
    question_key = str(question_id).strip()
    scopes = [_scope(question_key, "whole_question")]
    block_candidates: list[dict[str, Any]] = []
    stable_keys: set[str] = set()
    whole_marker_rows = 0
    whole_scoring_rows = 0

    for row in subquestions:
        number = str(row.get("subquestion_number") or "").strip()
        if number.casefold() == "whole":
            whole_marker_rows += 1
            continue
        stable_key = str(row.get("subquestion_id") or "").strip()
        if not stable_key:
            raise ValueError("explicit_subquestion_id_required")
        if stable_key in stable_keys:
            raise ValueError(f"duplicate_question_block_stable_key:{stable_key}")
        stable_keys.add(stable_key)
        candidate = _block_candidate(
            question_key,
            "subquestion",
            stable_key,
            number,
            str(row.get("stem_summary") or "").strip(),
        )
        block_candidates.append(candidate)
        scopes.append(_scope(question_key, "subquestion", stable_key))

    for row in scoring_points:
        stable_key = str(row.get("scoring_point_id") or "").strip()
        if not stable_key:
            if str(row.get("scoring_point_summary") or "").strip():
                whole_scoring_rows += 1
            continue
        if stable_key in stable_keys:
            raise ValueError(f"duplicate_question_block_stable_key:{stable_key}")
        stable_keys.add(stable_key)
        candidate = _block_candidate(
            question_key,
            "scoring_point",
            stable_key,
            str(row.get("scoring_point_number") or "").strip(),
            str(row.get("scoring_point_summary") or "").strip(),
        )
        block_candidates.append(candidate)
        scopes.append(_scope(question_key, "scoring_point", stable_key))

    return {
        "questionId": question_key,
        "scopes": scopes,
        "blockCandidates": block_candidates,
        "wholeMarkerRows": whole_marker_rows,
        "wholeQuestionScoringSummaryRows": whole_scoring_rows,
    }


def _read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def load_materialized_question_index(connection_string: str) -> list[dict[str, Any]]:
    import psycopg
    from psycopg.rows import dict_row

    with psycopg.connect(connection_string, row_factory=dict_row) as connection:
        with connection.transaction():
            connection.execute("set transaction read only")
            rows = connection.execute(
                """
                select id::text as question_id,
                       (custom_fields->>'year')::integer as year,
                       (custom_fields->>'questionNo')::integer as question_number,
                       custom_fields->>'legacyQuestionId' as legacy_question_id
                from question_items
                where custom_fields->>'sourceWorkflowKey' = %s
                order by year, question_number
                """,
                ("guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1",),
            ).fetchall()
            blocks = connection.execute(
                """
                select qb.id::text as id, qb.question_item_id::text as question_id,
                       qb.block_type, qb.sort_order, qb.content
                from question_blocks qb
                join question_items qi on qi.id = qb.question_item_id
                where qi.custom_fields->>'sourceWorkflowKey' = %s
                  and qb.block_type in ('subquestion','scoring_point')
                order by qb.question_item_id, qb.block_type, qb.sort_order, qb.id
                """,
                ("guangzhou_physics_2015_2025_20260726_v2_candidate_materialize_v1",),
            ).fetchall()
    blocks_by_question: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for block in blocks:
        blocks_by_question[str(block["question_id"])].append(dict(block))
    result = []
    for row in rows:
        item = dict(row)
        item["materialized_blocks"] = blocks_by_question.get(str(row["question_id"]), [])
        result.append(item)
    return result


def bind_materialized_block_ids(
    normalized: dict[str, Any],
    materialized_blocks: Iterable[Mapping[str, Any]],
) -> None:
    existing_by_type: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for block in materialized_blocks:
        existing_by_type[str(block["block_type"])].append(block)
    for block_type in ("subquestion", "scoring_point"):
        candidates = [row for row in normalized["blockCandidates"] if row["type"] == block_type]
        if not candidates:
            continue
        existing = sorted(existing_by_type.get(block_type, []), key=lambda row: (int(row["sort_order"]), str(row["id"])))
        if len(existing) != len(candidates):
            raise ValueError(
                f"materialized_question_block_count_mismatch:{normalized['questionId']}:{block_type}:"
                f"expected={len(candidates)}:actual={len(existing)}"
            )
        scope_by_key = {scope["scopeKey"]: scope for scope in normalized["scopes"]}
        for candidate, block in zip(candidates, existing, strict=True):
            materialized_id = str(block["id"])
            candidate["questionBlockId"] = materialized_id
            candidate["materialized"] = True
            scope_by_key[candidate["scopeKey"]]["questionBlockRef"]["id"] = materialized_id
            scope_by_key[candidate["scopeKey"]]["questionBlockRef"]["materialized"] = True


def build_scope_manifest(question_index: Iterable[Mapping[str, Any]], csv_root: Path) -> dict[str, Any]:
    subquestions_by_question: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in _read_csv(csv_root / "c003-subquestion-item-full.csv"):
        subquestions_by_question[row["question_id"]].append(row)
    scoring_by_question: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in _read_csv(csv_root / "c003-answer-scoring-point.csv"):
        scoring_by_question[row["question_id"]].append(row)

    questions: list[dict[str, Any]] = []
    seen_question_ids: set[str] = set()
    for item in question_index:
        question_id = str(item.get("question_id") or "").strip()
        if not question_id or question_id in seen_question_ids:
            raise ValueError(f"invalid_or_duplicate_materialized_question_id:{question_id}")
        seen_question_ids.add(question_id)
        legacy_id = str(item.get("legacy_question_id") or "").strip()
        normalized = normalize_question_scopes(
            question_id,
            subquestions_by_question.get(legacy_id, []),
            scoring_by_question.get(legacy_id, []),
        )
        bind_materialized_block_ids(normalized, item.get("materialized_blocks") or [])
        normalized["year"] = int(item["year"])
        normalized["questionNumber"] = int(item["question_number"])
        normalized["legacyQuestionId"] = legacy_id
        questions.append(normalized)

    questions.sort(key=lambda item: (item["year"], item["questionNumber"]))
    return {"schemaVersion": "cek010-question-scope-manifest.v1", "questions": questions}


def summarize_manifest(manifest: Mapping[str, Any], sha256: str) -> dict[str, Any]:
    questions = list(manifest.get("questions") or [])
    scopes = [scope for question in questions for scope in question["scopes"]]
    blocks = [block for question in questions for block in question["blockCandidates"]]
    scope_counts = Counter(scope["scopeType"] for scope in scopes)
    block_counts = Counter(block["type"] for block in blocks)
    return {
        "schemaVersion": "cek010-question-scope-normalization.v1",
        "status": "pass",
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "taskId": "CEK-10",
        "manifest": {"sha256": sha256, "questions": len(questions)},
        "scopeCounts": {scope_type: scope_counts[scope_type] for scope_type in sorted(SCOPE_TYPES)},
        "blockCandidateCounts": {
            block_type: block_counts[block_type] for block_type in ("scoring_point", "subquestion")
        },
        "sourceRows": {
            "wholeMarkers": sum(question["wholeMarkerRows"] for question in questions),
            "wholeQuestionScoringSummaries": sum(
                question["wholeQuestionScoringSummaryRows"] for question in questions
            ),
        },
        "invariants": {
            "nonWholeScopesReferenceQuestionBlock": all(
                scope["questionBlockRef"] is not None and bool(scope["questionBlockRef"].get("id"))
                for scope in scopes
                if scope["scopeType"] != "whole_question"
            ),
            "wholeScopesHaveNoQuestionBlockReference": all(
                scope["questionBlockRef"] is None
                for scope in scopes
                if scope["scopeType"] == "whole_question"
            ),
            "allNewScopesPendingReview": all(scope["reviewStatus"] == PENDING_REVIEW for scope in scopes),
            "allNewBlocksPendingReview": all(block["reviewStatus"] == PENDING_REVIEW for block in blocks),
            "productionEligible": False,
            "punctuationSplitUsed": False,
        },
        "governance": {
            "databaseAccess": "single read-only transaction",
            "databaseWrite": False,
            "activeWrite": False,
            "externalAiCalls": 0,
            "realStudentDataUsed": False,
            "fullGate": {
                "status": "gate_na",
                "reason": "CEK-10 uses targeted read-only checks; run-gates.ps1 is deferred to CEK-34 because it can use PostgreSQL and pause or resume the API process.",
                "alternativeVerification": "API build and tests, scope contract, schema compatibility, roadmap/reference guards, Ruff, compile/AST, and REAL005B diagnostics",
                "evidenceLink": "docs/evidence/cek010-question-scope-normalization.json",
                "expiresAt": "CEK-34",
                "recoveryCondition": "obtain current-task authorization and run tools/run-verification.ps1 -Profile Release -AuthorizeStateful at CEK-34",
            },
        },
        "completionBoundary": (
            "CEK-10 proves repo-side scope normalization candidates only; it does not approve question content, "
            "create AssessmentTarget records, close REAL005, permit release, or establish teacher/live acceptance."
        ),
    }


def write_json(path: Path, payload: Mapping[str, Any]) -> str:
    content = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="Build stable question scope candidates from materialized questions.")
    parser.add_argument("--csv-root", type=Path, required=True)
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    index = load_materialized_question_index(args.connection_string)
    manifest = build_scope_manifest(index, args.csv_root)
    manifest_hash = write_json(args.manifest, manifest)
    write_json(args.evidence, summarize_manifest(manifest, manifest_hash))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
