from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "curriculum-knowledge-crosswalk.v1"
ENGINE_VERSION = "curriculum-knowledge-crosswalk.v1"
ALLOWED_MAPPING_TYPES = frozenset({"equivalent", "broader", "narrower"})
REVIEW_THRESHOLD = 0.85
OUTPUT_HASH_SCOPE = "mappings+knowledge_candidates+review_queue+warnings"
PUNCTUATION_RE = re.compile(r"[\s，。；：、,.!?！？;:（）()《》\[\]【】“”‘’\-—_]+")


class CrosswalkError(RuntimeError):
    pass


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_json(value: Any) -> str:
    return sha256_text(canonical_json(value))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_atomic(value: Any, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def write_compatibility_csv(envelope: dict[str, Any], path: Path) -> None:
    fields = [
        "mapping_id",
        "source_asset_type",
        "source_stable_id",
        "target_asset_type",
        "target_stable_id",
        "mapping_type",
        "confidence",
        "source_material_ids",
        "evidence_locations",
        "impact_scope",
        "review_status",
        "auto_apply_allowed",
        "rollback_required",
        "notes",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            for item in envelope["mappings"]:
                writer.writerow(
                    {
                        "mapping_id": item["mapping_id"],
                        "source_asset_type": "curriculum_standard_item",
                        "source_stable_id": item["source_stable_id"],
                        "target_asset_type": "knowledge_point",
                        "target_stable_id": item["target_knowledge_code"],
                        "mapping_type": item["mapping_type"],
                        "confidence": f'{item["confidence"]:.2f}',
                        "source_material_ids": item["source_material_id"],
                        "evidence_locations": item["evidence_anchor_sha256"],
                        "impact_scope": ";".join(item["impact_scope"]),
                        "review_status": item["review_status"],
                        "auto_apply_allowed": str(item["auto_apply_allowed"]).lower(),
                        "rollback_required": str(item["rollback_required"]).lower(),
                        "notes": ";".join(item["review_reasons"]),
                    }
                )
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def normalize(value: str) -> str:
    return PUNCTUATION_RE.sub("", value).casefold()


def output_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    return {
        "mappings": envelope["mappings"],
        "knowledge_candidates": envelope["knowledge_candidates"],
        "review_queue": envelope["review_queue"],
        "warnings": envelope["warnings"],
    }


def _safe_source(source: dict[str, Any]) -> None:
    governance = source.get("governance", {})
    if (
        governance.get("status") != "candidate"
        or governance.get("review_status") != "pending_review"
        or governance.get("production_eligible") is not False
        or governance.get("knowledge_asset_write") is not False
        or governance.get("c002_active_write") is not False
    ):
        raise CrosswalkError("source is not a safe candidate envelope")


def _facets(source: dict[str, Any]) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    seen: set[str] = set()
    for requirement in source.get("requirements", []):
        for wrapper in requirement.get("facets", []):
            facet = wrapper.get("facet", {})
            stable_id = facet.get("stable_id")
            if not stable_id:
                raise CrosswalkError("facet stable_id is required")
            if stable_id in seen:
                raise CrosswalkError(f"duplicate facet stable_id: {stable_id}")
            seen.add(stable_id)
            if (
                facet.get("status") != "candidate"
                or facet.get("review_status") != "pending_review"
                or facet.get("production_eligible") is not False
            ):
                raise CrosswalkError(f"facet is not a safe candidate: {stable_id}")
            found.append(facet)
    return found


def _nodes(knowledge: dict[str, Any]) -> list[dict[str, Any]]:
    nodes = knowledge.get("nodes")
    if not isinstance(nodes, list) or not knowledge.get("seedId"):
        raise CrosswalkError("knowledge snapshot requires seedId and nodes")
    seen: set[str] = set()
    for node in nodes:
        code = node.get("code")
        if not code or code in seen:
            raise CrosswalkError(f"duplicate or missing knowledge code: {code}")
        seen.add(code)
    return nodes


def _terms(node: dict[str, Any]) -> list[tuple[str, str]]:
    terms = [(str(node["title"]), "title")]
    terms.extend((str(alias), "alias") for alias in node.get("aliases", []))
    unique: dict[str, tuple[str, str]] = {}
    for text, kind in terms:
        normalized = normalize(text)
        if normalized and normalized not in unique:
            unique[normalized] = (text, kind)
    return list(unique.values())


def _match(content: str, node: dict[str, Any]) -> dict[str, Any] | None:
    normalized_content = normalize(content)
    choices: list[tuple[int, int, str, str, str, float]] = []
    for term, kind in _terms(node):
        normalized_term = normalize(term)
        if normalized_content == normalized_term:
            basis = f"{kind}_exact"
            choices.append((3, len(normalized_term), basis, term, "equivalent", 0.96))
        elif len(normalized_term) >= 2 and normalized_term in normalized_content:
            basis = f"{kind}_contained_by_source"
            choices.append((2, len(normalized_term), basis, term, "broader", 0.88))
        elif len(normalized_content) >= 2 and normalized_content in normalized_term:
            basis = f"source_contained_by_{kind}"
            choices.append((1, len(normalized_content), basis, term, "narrower", 0.84))
    if not choices:
        return None
    _, _, basis, term, mapping_type, confidence = max(choices)
    return {
        "match_basis": basis,
        "matched_term": term,
        "mapping_type": mapping_type,
        "match_confidence": confidence,
    }


def _candidate(facet: dict[str, Any]) -> dict[str, Any]:
    stable_id = f'KCAN-{sha256_text(facet["stable_id"] + "|" + facet["content_object"])[:16].upper()}'
    anchors = facet.get("evidence_anchors", [])
    return {
        "candidate_stable_id": stable_id,
        "source_facet_stable_id": facet["stable_id"],
        "parent_requirement_stable_id": facet["parent_requirement_stable_id"],
        "proposed_title": facet["content_object"],
        "proposed_node_type": "concept",
        "evidence_anchor_sha256s": [item["text_block_sha256"] for item in anchors],
        "confidence": round(min(float(facet["confidence"]), 0.80), 2),
        "status": "candidate",
        "review_status": "pending_review",
        "production_eligible": False,
        "knowledge_node_write": False,
        "rollback_requirement": "discard_candidate_record",
        "reasons": ["no_deterministic_title_or_alias_match"],
    }


def build_crosswalk(
    source: dict[str, Any],
    knowledge: dict[str, Any],
    *,
    source_material_id: str = "curriculum-standard-2022-2025-revision",
    source_sha256: str | None = None,
    knowledge_sha256: str | None = None,
) -> dict[str, Any]:
    _safe_source(source)
    facets = _facets(source)
    nodes = _nodes(knowledge)
    mappings: list[dict[str, Any]] = []
    candidates: list[dict[str, Any]] = []

    for facet in facets:
        matches = [(node, _match(facet["content_object"], node)) for node in nodes]
        matched = [(node, match) for node, match in matches if match is not None]
        if not matched:
            candidates.append(_candidate(facet))
            continue
        anchor = facet.get("evidence_anchors", [{}])[0].get("text_block_sha256", "")
        for node, match in matched:
            assert match is not None
            confidence = round(min(float(facet["confidence"]), match["match_confidence"]), 2)
            mapping_id = "MAP-CEK08-" + sha256_text(
                f'{facet["stable_id"]}|{node["code"]}|{match["mapping_type"]}'
            )[:16].upper()
            mappings.append(
                {
                    "mapping_id": mapping_id,
                    "source_asset_type": "requirement_facet",
                    "source_stable_id": facet["stable_id"],
                    "parent_requirement_stable_id": facet["parent_requirement_stable_id"],
                    "target_asset_type": "knowledge_point",
                    "target_knowledge_code": node["code"],
                    "mapping_type": match["mapping_type"],
                    "match_basis": match["match_basis"],
                    "matched_term": match["matched_term"],
                    "confidence": confidence,
                    "source_material_id": source_material_id,
                    "evidence_anchor_sha256": anchor,
                    "impact_scope": ["question_binding", "search_index", "analysis_metric"],
                    "review_status": "pending_review",
                    "auto_apply_allowed": False,
                    "rollback_required": True,
                    "rollback_requirement": "discard_mapping_candidate",
                    "review_reasons": [],
                }
            )

    source_counts = Counter(item["source_stable_id"] for item in mappings)
    target_counts = Counter(item["target_knowledge_code"] for item in mappings)
    review_queue: list[dict[str, Any]] = []
    for item in mappings:
        reasons: list[str] = []
        if source_counts[item["source_stable_id"]] > 1:
            reasons.append("one_to_many")
        if target_counts[item["target_knowledge_code"]] > 1:
            reasons.append("many_to_one")
        if item["confidence"] < REVIEW_THRESHOLD:
            reasons.append("low_confidence")
        if item["mapping_type"] != "equivalent":
            reasons.append("scope_direction_review")
        reasons.append("high_impact_asset_mapping")
        item["review_reasons"] = reasons
        review_queue.append(
            {
                "item_type": "asset_mapping",
                "item_id": item["mapping_id"],
                "priority": "high" if len(reasons) > 1 else "normal",
                "reasons": reasons,
                "rollback_required": True,
            }
        )
    for item in candidates:
        review_queue.append(
            {
                "item_type": "knowledge_candidate",
                "item_id": item["candidate_stable_id"],
                "priority": "high",
                "reasons": item["reasons"],
                "rollback_required": True,
            }
        )

    input_source_hash = source_sha256 or sha256_json(source)
    input_knowledge_hash = knowledge_sha256 or sha256_json(knowledge)
    envelope: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "run_id": f"cek008-rules-{input_source_hash[:8]}-{input_knowledge_hash[:8]}",
        "mode": "draft_test",
        "generation": {
            "method": "rules",
            "engine_name": "curriculum_knowledge_crosswalk.py",
            "engine_version": ENGINE_VERSION,
            "external_model_calls": 0,
            "input_source_sha256": input_source_hash,
            "input_knowledge_snapshot_sha256": input_knowledge_hash,
            "output_sha256": "",
            "output_hash_scope": OUTPUT_HASH_SCOPE,
        },
        "knowledge_snapshot": {
            "seed_id": knowledge["seedId"],
            "node_count": len(nodes),
            "source": "repo_snapshot",
        },
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "human_review_required": True,
            "database_read": False,
            "database_write": False,
            "knowledge_node_write": False,
            "domain_asset_mapping_write": False,
            "c002_active_write": False,
        },
        "mappings": mappings,
        "knowledge_candidates": candidates,
        "review_queue": review_queue,
        "warnings": [
            "Only deterministic normalized title/alias equality and containment are used.",
            "Containment direction is a review candidate, not an approved semantic assertion.",
        ],
    }
    envelope["generation"]["output_sha256"] = sha256_json(output_payload(envelope))
    validate_crosswalk(envelope)
    return envelope


def validate_crosswalk(envelope: dict[str, Any]) -> None:
    governance = envelope.get("governance", {})
    if any(
        governance.get(field) is not False
        for field in (
            "production_eligible",
            "database_read",
            "database_write",
            "knowledge_node_write",
            "domain_asset_mapping_write",
            "c002_active_write",
        )
    ):
        raise CrosswalkError("crosswalk governance permits a forbidden read or write")
    for mapping in envelope.get("mappings", []):
        if mapping.get("mapping_type") not in ALLOWED_MAPPING_TYPES:
            raise CrosswalkError(f'forbidden mapping type: {mapping.get("mapping_type")}')
        if (
            mapping.get("review_status") != "pending_review"
            or mapping.get("auto_apply_allowed") is not False
            or mapping.get("rollback_required") is not True
        ):
            raise CrosswalkError("mapping bypasses review or rollback")
    for candidate in envelope.get("knowledge_candidates", []):
        if (
            candidate.get("status") != "candidate"
            or candidate.get("review_status") != "pending_review"
            or candidate.get("production_eligible") is not False
            or candidate.get("knowledge_node_write") is not False
        ):
            raise CrosswalkError("knowledge candidate is production eligible")
    expected = sha256_json(output_payload(envelope))
    actual = envelope.get("generation", {}).get("output_sha256")
    if actual != expected:
        raise CrosswalkError(f"output hash mismatch: expected {expected}, got {actual}")


def summary(envelope: dict[str, Any]) -> dict[str, Any]:
    mappings = envelope["mappings"]
    return {
        "facetCount": len({item["source_stable_id"] for item in mappings})
        + len(envelope["knowledge_candidates"]),
        "mappingCount": len(mappings),
        "mappingTypes": dict(sorted(Counter(item["mapping_type"] for item in mappings).items())),
        "knowledgeCandidateCount": len(envelope["knowledge_candidates"]),
        "reviewQueueCount": len(envelope["review_queue"]),
        "highPriorityReviewCount": sum(
            item["priority"] == "high" for item in envelope["review_queue"]
        ),
        "databaseReads": 0,
        "databaseWrites": 0,
        "activeWrites": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a draft curriculum-to-C002 crosswalk")
    parser.add_argument("--requirements", type=Path, required=True)
    parser.add_argument("--knowledge", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compat-csv", type=Path, required=True)
    args = parser.parse_args()

    source = json.loads(args.requirements.read_text(encoding="utf-8"))
    knowledge = json.loads(args.knowledge.read_text(encoding="utf-8-sig"))
    result = build_crosswalk(
        source,
        knowledge,
        source_sha256=sha256_file(args.requirements),
        knowledge_sha256=sha256_file(args.knowledge),
    )
    write_json_atomic(result, args.output)
    write_compatibility_csv(result, args.compat_csv)
    print(json.dumps(summary(result), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
