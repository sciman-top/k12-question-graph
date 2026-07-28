from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "curriculum-requirement-extraction.v1"
ENGINE_VERSION = "curriculum-requirement-facets.v1"
PROMPT_VERSION = "curriculum-requirement-extraction.rules.v1"
REVIEW_THRESHOLD = 0.85
OUTPUT_HASH_SCOPE = "requirements+review_queue+warnings"

CONDITION_PREFIX_RE = re.compile(
    r"^(?P<condition>(?:通过|结合|根据|利用|在|从)[^，]{1,40})，(?P<body>.+)$"
)
SHARED_OBJECT_RE = re.compile(r"^会(?P<first>看|识读)、会(?P<second>画|绘制)(?P<object>.+)$")
MODAL_TOOL_RE = re.compile(
    r"^能用(?P<means>.+?)(?P<action>描述|说明|解释|分析|表示|表达)(?P<object>.+)$"
)
DIRECT_TOOL_RE = re.compile(
    r"^用(?P<means>.+?)(?P<action>测量|说明|解释|描述|分析)(?P<object>.+)$"
)
MODAL_APPLY_RE = re.compile(
    r"^能运用(?P<means>.+?)(?P<action>说明|解释|分析|解决|判断)(?P<object>.+)$"
)
MODAL_ACTION_RE = re.compile(
    r"^能(?P<action>发现|说出|描述|列举|解释|说明|分析|提出|设计|评估|运用|应用)(?P<object>.+)$"
)
MODAL_PERFORM_RE = re.compile(r"^能进行(?P<object>.+)$")
LEARNED_ACTION_RE = re.compile(
    r"^会(?P<action>测量|使用|连接|计算|识别|看|画|设计)(?P<object>.*)$"
)

DIRECT_BEHAVIORS = (
    ("探究并了解", "探究并了解", 0.82, True),
    ("举例说明", "说明", 0.92, False),
    ("经历", "经历", 0.90, False),
    ("测量", "测量", 0.94, False),
    ("观察", "观察", 0.92, False),
    ("探究", "探究", 0.92, False),
    ("调查", "调查", 0.90, False),
    ("查阅", "查阅", 0.90, False),
    ("制作", "制作", 0.90, False),
    ("设计", "设计", 0.92, False),
    ("评估", "评估", 0.92, False),
    ("理解", "理解", 0.94, False),
    ("认识", "认识", 0.94, False),
    ("知道", "知道", 0.95, False),
    ("了解", "了解", 0.94, False),
    ("描述", "描述", 0.93, False),
    ("列举", "列举", 0.93, False),
    ("说明", "说明", 0.93, False),
    ("解释", "解释", 0.93, False),
    ("分析", "分析", 0.92, False),
    ("提出", "提出", 0.90, False),
    ("践行", "践行", 0.88, False),
    ("体会", "体会", 0.88, False),
    ("关注", "关注", 0.86, False),
    ("尝试", "尝试", 0.82, False),
    ("有", "有", 0.78, False),
)
BEHAVIOR_STARTS = tuple(item[0] for item in DIRECT_BEHAVIORS) + (
    "能运用",
    "能用",
    "能",
    "会",
)
BEHAVIOR_BOUNDARY_RE = re.compile(
    r"，(?=(?:(?:并)?(?:"
    + "|".join(map(re.escape, BEHAVIOR_STARTS))
    + r")|用[^，。]{1,20}(?:测量|说明|解释|描述|分析)))"
)

COGNITIVE_LEVELS = {
    "知道": "RECOGNIZE",
    "了解": "RECOGNIZE",
    "认识": "RECOGNIZE",
    "说出": "RECOGNIZE",
    "列举": "RECOGNIZE",
    "观察": "RECOGNIZE",
    "发现": "RECOGNIZE",
    "理解": "UNDERSTAND",
    "说明": "UNDERSTAND",
    "描述": "UNDERSTAND",
    "解释": "UNDERSTAND",
    "体会": "UNDERSTAND",
    "运用": "APPLY",
    "应用": "APPLY",
    "测量": "APPLY",
    "连接": "APPLY",
    "识读": "APPLY",
    "绘制": "APPLY",
    "计算": "APPLY",
    "践行": "APPLY",
    "分析": "ANALYZE",
    "探究": "INQUIRY",
    "探究并了解": "INQUIRY",
    "经历": "INQUIRY",
    "调查": "INQUIRY",
    "设计": "CREATE",
    "制作": "CREATE",
    "提出": "CREATE",
    "评估": "EVALUATE",
}
ACTION_ALIASES = {
    "看": "识读",
    "画": "绘制",
    "表达": "描述",
    "表示": "描述",
}


class FacetExtractionError(RuntimeError):
    pass


@dataclass(frozen=True)
class ParsedFacet:
    source_text: str
    behavior_verb: str
    content_object: str
    condition_or_performance: str | None
    confidence: float
    rule_id: str
    compound_behavior: bool = False


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


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


def output_payload(envelope: dict[str, Any]) -> dict[str, Any]:
    return {
        "requirements": envelope["requirements"],
        "review_queue": envelope["review_queue"],
        "warnings": envelope["warnings"],
    }


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


def _sentences(source_text: str) -> list[str]:
    return [match.group(0).strip() for match in re.finditer(r"[^。！？]+[。！？]?", source_text) if match.group(0).strip()]


def _clauses(source_text: str) -> list[str]:
    clauses: list[str] = []
    for sentence in _sentences(source_text):
        parts = [part.strip() for part in BEHAVIOR_BOUNDARY_RE.split(sentence) if part.strip()]
        if (
            len(parts) > 1
            and parts[0].startswith(("通过", "结合", "根据", "利用", "在", "从"))
        ):
            parts[0] = f"{parts[0]}，{parts.pop(1)}"
        clauses.extend(parts)
    return clauses


def _clean_body(value: str) -> str:
    return value.strip().strip("，,；;。！？ ")


def _parsed(
    source_text: str,
    behavior_verb: str,
    content_object: str,
    condition: str | None,
    confidence: float,
    rule_id: str,
    *,
    compound: bool = False,
) -> tuple[list[ParsedFacet], str | None]:
    content = _clean_body(content_object)
    if not content:
        return [], "missing_content_object"
    return [
        ParsedFacet(
            source_text=source_text,
            behavior_verb=ACTION_ALIASES.get(behavior_verb, behavior_verb),
            content_object=content,
            condition_or_performance=_clean_body(condition) if condition else None,
            confidence=confidence,
            rule_id=rule_id,
            compound_behavior=compound,
        )
    ], None


def _parse_clause(clause: str) -> tuple[list[ParsedFacet], str | None]:
    source_text = clause.strip()
    body = _clean_body(source_text)
    if not body:
        return [], "missing_content_object"
    if body.startswith("并"):
        body = body[1:]

    condition: str | None = None
    condition_match = CONDITION_PREFIX_RE.match(body)
    if condition_match:
        condition = condition_match.group("condition")
        body = condition_match.group("body")

    shared = SHARED_OBJECT_RE.match(body)
    if shared:
        content = _clean_body(shared.group("object"))
        if not content:
            return [], "missing_content_object"
        return [
            ParsedFacet(
                source_text=source_text,
                behavior_verb=ACTION_ALIASES.get(shared.group(name), shared.group(name)),
                content_object=content,
                condition_or_performance=condition,
                confidence=0.82,
                rule_id="rule.shared-object-learned-actions.v1",
                compound_behavior=True,
            )
            for name in ("first", "second")
        ], None

    for pattern, rule_id in (
        (MODAL_TOOL_RE, "rule.modal-tool-action.v1"),
        (DIRECT_TOOL_RE, "rule.direct-tool-action.v1"),
        (MODAL_APPLY_RE, "rule.modal-apply-action.v1"),
    ):
        match = pattern.match(body)
        if match:
            means = _clean_body(match.group("means"))
            combined_condition = "；".join(item for item in (condition, f"使用{means}") if item)
            return _parsed(
                source_text,
                match.group("action"),
                match.group("object"),
                combined_condition,
                0.90,
                rule_id,
            )

    perform = MODAL_PERFORM_RE.match(body)
    if perform:
        content = _clean_body(perform.group("object"))
        behavior = "计算" if content.endswith("计算") else "进行"
        return _parsed(
            source_text,
            behavior,
            content,
            condition,
            0.84,
            "rule.modal-perform-action.v1",
            compound=True,
        )

    modal = MODAL_ACTION_RE.match(body)
    if modal:
        return _parsed(
            source_text,
            modal.group("action"),
            modal.group("object"),
            condition,
            0.92,
            "rule.modal-explicit-action.v1",
        )

    learned = LEARNED_ACTION_RE.match(body)
    if learned:
        return _parsed(
            source_text,
            learned.group("action"),
            learned.group("object"),
            condition,
            0.90,
            "rule.learned-explicit-action.v1",
        )

    if body.startswith("能运用"):
        return _parsed(
            source_text,
            "运用",
            body[len("能运用") :],
            condition,
            0.88,
            "rule.modal-apply.v1",
        )
    if body.startswith("能用"):
        return _parsed(
            source_text,
            "应用",
            body[len("能用") :],
            condition,
            0.86,
            "rule.modal-use.v1",
        )
    if body.startswith("会"):
        return _parsed(
            source_text,
            "会",
            body[1:],
            condition,
            0.80,
            "rule.learned-action-unresolved.v1",
            compound=True,
        )

    stripped_conjunction = body[1:] if body.startswith("并") else body
    for phrase, canonical, confidence, compound in DIRECT_BEHAVIORS:
        if stripped_conjunction.startswith(phrase):
            content = stripped_conjunction[len(phrase) :]
            if phrase == "探究并了解":
                parsed: list[ParsedFacet] = []
                for behavior in ("探究", "了解"):
                    item, issue = _parsed(
                        source_text,
                        behavior,
                        content,
                        condition,
                        confidence,
                        "rule.compound-inquiry-understand.v1",
                        compound=True,
                    )
                    if issue:
                        return [], issue
                    parsed.extend(item)
                return parsed, None
            return _parsed(
                source_text,
                canonical,
                content,
                condition,
                confidence,
                f"rule.direct-{canonical}.v1",
                compound=compound,
            )

    for phrase, canonical, confidence, compound in DIRECT_BEHAVIORS:
        index = body.find(phrase)
        if 0 < index <= 20 and body.startswith(("通过", "结合", "根据", "利用", "在", "从")):
            return _parsed(
                source_text,
                canonical,
                body[index + len(phrase) :],
                body[:index],
                min(confidence, 0.88),
                f"rule.prefixed-{canonical}.v1",
                compound=compound,
            )
    return [], "missing_behavior_verb"


def _anchor_hashes(requirement: dict[str, Any]) -> list[str]:
    anchors = requirement.get("evidence_anchors")
    if not isinstance(anchors, list) or not anchors:
        raise FacetExtractionError(
            f"requirement {requirement.get('stable_id')} has no evidence anchors"
        )
    hashes: list[str] = []
    for anchor in anchors:
        value = anchor.get("text_block_sha256")
        if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", value):
            raise FacetExtractionError(
                f"requirement {requirement.get('stable_id')} has an invalid anchor hash"
            )
        if value not in hashes:
            hashes.append(value)
    return hashes


def _facet_anchors(requirement: dict[str, Any]) -> list[dict[str, Any]]:
    anchors = copy.deepcopy(requirement["evidence_anchors"])
    for anchor in anchors:
        anchor["evidence_role"] = "curriculum_facet_source"
    return anchors


def _cognitive_demands(behavior_verb: str, standard_version: str) -> list[str]:
    level = COGNITIVE_LEVELS.get(behavior_verb)
    if not level:
        return []
    version = re.sub(r"[^A-Za-z0-9]+", "-", standard_version).strip("-").upper()
    return [f"CAND-CD-PHY-JM-{version}-{level}"]


def _field_provenance(
    parsed: ParsedFacet,
    anchor_hashes: list[str],
    cognitive_demands: list[str],
) -> list[dict[str, Any]]:
    def item(
        field: str,
        source_kind: str,
        confidence: float,
        rule_id: str,
    ) -> dict[str, Any]:
        return {
            "field": field,
            "generation_method": "rules",
            "source_kind": source_kind,
            "confidence": confidence,
            "anchor_sha256s": anchor_hashes,
            "rule_id": rule_id,
            "model_output_path": None,
        }

    return [
        item("facet_statement", "derived_candidate", parsed.confidence, parsed.rule_id),
        item("behavior_verb", "explicit_text", parsed.confidence, parsed.rule_id),
        item("content_object", "explicit_text", parsed.confidence, parsed.rule_id),
        item(
            "condition_or_performance",
            "explicit_text" if parsed.condition_or_performance else "not_inferred",
            parsed.confidence if parsed.condition_or_performance else 1.0,
            parsed.rule_id,
        ),
        item(
            "cognitive_demands",
            "derived_candidate" if cognitive_demands else "not_inferred",
            max(0.0, parsed.confidence - 0.05) if cognitive_demands else 1.0,
            "rule.behavior-to-cognitive-candidate.v1",
        ),
        item(
            "ability_dimensions",
            "not_inferred",
            1.0,
            "rule.ability-deferred-to-semantic-review.v1",
        ),
    ]


def _priority(reasons: list[str]) -> str:
    if any(reason.startswith("missing_") for reason in reasons):
        return "blocked"
    if set(reasons) - {"candidate_only"}:
        return "high"
    return "normal"


def _validate_source_requirement(requirement: dict[str, Any]) -> None:
    required = (
        "stable_id",
        "standard_version",
        "official_item_code",
        "requirement_type",
        "source_text",
        "evidence_anchors",
    )
    missing = [field for field in required if not requirement.get(field)]
    if missing:
        raise FacetExtractionError(
            f"source requirement is missing fields: {', '.join(missing)}"
        )
    if (
        requirement.get("status") != "candidate"
        or requirement.get("review_status") != "pending_review"
        or requirement.get("production_eligible") is not False
    ):
        raise FacetExtractionError(
            f"source requirement {requirement['stable_id']} is not a safe candidate"
        )
    _anchor_hashes(requirement)


def extract_requirement(requirement: dict[str, Any]) -> dict[str, Any]:
    _validate_source_requirement(requirement)
    anchor_hashes = _anchor_hashes(requirement)
    parsed_facets: list[ParsedFacet] = []
    unresolved: list[str] = []
    for clause in _clauses(requirement["source_text"]):
        parsed, issue = _parse_clause(clause)
        parsed_facets.extend(parsed)
        if issue and issue not in unresolved:
            unresolved.append(issue)

    composite = len(parsed_facets) > 1 or any(item.compound_behavior for item in parsed_facets)
    facets: list[dict[str, Any]] = []
    for index, parsed in enumerate(parsed_facets, 1):
        cognitive_demands = _cognitive_demands(
            parsed.behavior_verb, requirement["standard_version"]
        )
        reasons = ["candidate_only"]
        if parsed.confidence < REVIEW_THRESHOLD:
            reasons.append("low_confidence")
        if parsed.compound_behavior:
            reasons.append("compound_behavior")
        if composite:
            reasons.append("multiple_facets")
        facet_statement = (
            f"{parsed.condition_or_performance}，" if parsed.condition_or_performance else ""
        ) + f"{parsed.behavior_verb}{parsed.content_object}"
        facet = {
            "record_type": "requirement_facet",
            "stable_id": f"{requirement['stable_id']}-F{index:02d}",
            "parent_requirement_stable_id": requirement["stable_id"],
            "standard_version": requirement["standard_version"],
            "official_item_code": requirement["official_item_code"],
            "requirement_type": requirement["requirement_type"],
            "source_text": parsed.source_text,
            "facet_statement": facet_statement,
            "behavior_verb": parsed.behavior_verb,
            "content_object": parsed.content_object,
            "condition_or_performance": parsed.condition_or_performance,
            "cognitive_demands": cognitive_demands,
            "ability_dimensions": [],
            "knowledge_stable_ids": [],
            "evidence_anchors": _facet_anchors(requirement),
            "confidence": parsed.confidence,
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
        }
        facets.append(
            {
                "facet": facet,
                "field_provenance": _field_provenance(
                    parsed, anchor_hashes, cognitive_demands
                ),
                "review": {
                    "required": True,
                    "status": "pending_review",
                    "priority": _priority(reasons),
                    "reasons": reasons,
                },
            }
        )

    return {
        "parent_requirement_stable_id": requirement["stable_id"],
        "official_item_code": requirement["official_item_code"],
        "source_text_sha256": sha256_text(requirement["source_text"]),
        "source_anchor_sha256s": anchor_hashes,
        "composite": composite,
        "facets": facets,
        "unresolved_reasons": unresolved,
    }


def _review_queue(requirements: list[dict[str, Any]]) -> list[dict[str, Any]]:
    queue: list[dict[str, Any]] = []
    for requirement in requirements:
        code_id = requirement["official_item_code"].replace(".", "-")
        for index, candidate in enumerate(requirement["facets"], 1):
            facet = candidate["facet"]
            review = candidate["review"]
            queue.append(
                {
                    "review_item_id": f"CEK007-{code_id}-F{index:02d}",
                    "parent_requirement_stable_id": requirement[
                        "parent_requirement_stable_id"
                    ],
                    "facet_stable_id": facet["stable_id"],
                    "official_item_code": requirement["official_item_code"],
                    "priority": review["priority"],
                    "reasons": review["reasons"],
                    "evidence_anchor_sha256s": requirement["source_anchor_sha256s"],
                    "status": "pending_review",
                }
            )
        if requirement["unresolved_reasons"]:
            queue.append(
                {
                    "review_item_id": f"CEK007-{code_id}-UNRESOLVED",
                    "parent_requirement_stable_id": requirement[
                        "parent_requirement_stable_id"
                    ],
                    "facet_stable_id": None,
                    "official_item_code": requirement["official_item_code"],
                    "priority": "blocked",
                    "reasons": requirement["unresolved_reasons"],
                    "evidence_anchor_sha256s": requirement["source_anchor_sha256s"],
                    "status": "pending_review",
                }
            )
    return queue


def build_rule_envelope(
    candidate: dict[str, Any], *, input_sha256: str | None = None
) -> dict[str, Any]:
    extraction = candidate.get("extraction")
    if extraction and extraction.get("status") != "pass":
        raise FacetExtractionError("CEK-06 source candidate is not in pass state")
    source_requirements = candidate.get("curriculum_requirements")
    if not isinstance(source_requirements, list) or not source_requirements:
        raise FacetExtractionError("CEK-06 source candidate has no curriculum requirements")

    requirements = [extract_requirement(item) for item in source_requirements]
    review_queue = _review_queue(requirements)
    warnings = [
        "rule output is a review candidate; ability dimensions and knowledge mappings are not inferred"
    ]
    resolved_input_sha256 = input_sha256 or sha256_json(candidate)
    envelope: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "run_id": f"cek007-rules-{resolved_input_sha256[:16]}",
        "mode": "draft_test",
        "generation": {
            "method": "rules",
            "engine_role": "deterministic_rule_parser",
            "engine_name": "curriculum_requirement_facets.py",
            "engine_version": ENGINE_VERSION,
            "model": None,
            "prompt_version": PROMPT_VERSION,
            "output_schema_version": SCHEMA_VERSION,
            "input_sha256": resolved_input_sha256,
            "output_sha256": "",
            "output_hash_scope": OUTPUT_HASH_SCOPE,
            "cost": {
                "input_tokens": 0,
                "output_tokens": 0,
                "estimated_usd": 0,
                "currency": "USD",
            },
            "external_model_calls": 0,
        },
        "governance": {
            "status": "candidate",
            "review_status": "pending_review",
            "production_eligible": False,
            "human_review_required": True,
            "database_write": False,
            "source_region_write": False,
            "knowledge_asset_write": False,
            "c002_active_write": False,
        },
        "requirements": requirements,
        "review_queue": review_queue,
        "warnings": warnings,
    }
    envelope["generation"]["output_sha256"] = sha256_json(output_payload(envelope))
    validate_envelope_trace(envelope, expected_input_sha256=resolved_input_sha256)
    return envelope


def validate_envelope_trace(
    envelope: dict[str, Any], *, expected_input_sha256: str | None = None
) -> None:
    generation = envelope.get("generation", {})
    governance = envelope.get("governance", {})
    if generation.get("output_hash_scope") != OUTPUT_HASH_SCOPE:
        raise FacetExtractionError("unsupported output hash scope")
    expected_output = sha256_json(output_payload(envelope))
    if generation.get("output_sha256") != expected_output:
        raise FacetExtractionError("output payload hash mismatch")
    if expected_input_sha256 and generation.get("input_sha256") != expected_input_sha256:
        raise FacetExtractionError("input hash mismatch")
    if generation.get("external_model_calls") != 0:
        raise FacetExtractionError("CEK-07 eval must not call an external model")
    if generation.get("method") == "rules":
        if generation.get("model") is not None or any(
            generation.get("cost", {}).get(field) != 0
            for field in ("input_tokens", "output_tokens", "estimated_usd")
        ):
            raise FacetExtractionError("rule generation must have null model and zero cost")
    elif generation.get("method") == "ai":
        model = generation.get("model")
        if not isinstance(model, dict) or not all(model.get(key) for key in ("role", "name", "version")):
            raise FacetExtractionError("AI generation is missing model role/name/version")
    else:
        raise FacetExtractionError("unsupported generation method")
    if (
        governance.get("status") != "candidate"
        or governance.get("review_status") != "pending_review"
        or governance.get("production_eligible") is not False
        or governance.get("human_review_required") is not True
    ):
        raise FacetExtractionError("unsafe envelope governance")
    for field in (
        "database_write",
        "source_region_write",
        "knowledge_asset_write",
        "c002_active_write",
    ):
        if governance.get(field) is not False:
            raise FacetExtractionError(f"unsafe governance field: {field}")
    _validate_parent_and_review_invariants(envelope)


def _validate_parent_and_review_invariants(envelope: dict[str, Any]) -> None:
    queue_by_facet = {
        item["facet_stable_id"]: item
        for item in envelope.get("review_queue", [])
        if item.get("facet_stable_id")
    }
    method = envelope.get("generation", {}).get("method")
    for requirement in envelope.get("requirements", []):
        parent = requirement.get("parent_requirement_stable_id")
        code = requirement.get("official_item_code")
        anchor_hashes = set(requirement.get("source_anchor_sha256s", []))
        if requirement.get("unresolved_reasons"):
            unresolved = [
                item
                for item in envelope.get("review_queue", [])
                if item.get("parent_requirement_stable_id") == parent
                and item.get("facet_stable_id") is None
            ]
            if not unresolved or unresolved[0].get("priority") != "blocked":
                raise FacetExtractionError("unresolved clause is not routed as blocked review")
        for candidate in requirement.get("facets", []):
            facet = candidate.get("facet", {})
            if (
                facet.get("parent_requirement_stable_id") != parent
                or facet.get("official_item_code") != code
            ):
                raise FacetExtractionError("facet is detached from its parent requirement")
            if (
                facet.get("status") != "candidate"
                or facet.get("review_status") != "pending_review"
                or facet.get("production_eligible") is not False
            ):
                raise FacetExtractionError("facet violates candidate-only governance")
            facet_anchor_hashes = {
                anchor.get("text_block_sha256")
                for anchor in facet.get("evidence_anchors", [])
            }
            if not facet_anchor_hashes or not facet_anchor_hashes.issubset(anchor_hashes):
                raise FacetExtractionError("facet does not retain parent evidence anchors")
            fields = {item.get("field") for item in candidate.get("field_provenance", [])}
            if fields != {
                "facet_statement",
                "behavior_verb",
                "content_object",
                "condition_or_performance",
                "cognitive_demands",
                "ability_dimensions",
            }:
                raise FacetExtractionError("facet field provenance is incomplete")
            for provenance in candidate.get("field_provenance", []):
                if provenance.get("generation_method") != method:
                    raise FacetExtractionError(
                        "field provenance generation method differs from envelope"
                    )
                provenance_hashes = set(provenance.get("anchor_sha256s", []))
                if not provenance_hashes or not provenance_hashes.issubset(anchor_hashes):
                    raise FacetExtractionError("field provenance lost its source anchor")
                if method == "rules" and (
                    not provenance.get("rule_id")
                    or provenance.get("model_output_path") is not None
                ):
                    raise FacetExtractionError("rule provenance has invalid rule/model trace")
                if method == "ai" and (
                    provenance.get("rule_id") is not None
                    or not provenance.get("model_output_path")
                ):
                    raise FacetExtractionError("AI provenance has invalid rule/model trace")
            review = candidate.get("review", {})
            reasons = set(review.get("reasons", []))
            if review.get("required") is not True or review.get("status") != "pending_review":
                raise FacetExtractionError("facet is not routed to pending review")
            if float(facet.get("confidence", 0)) < REVIEW_THRESHOLD and "low_confidence" not in reasons:
                raise FacetExtractionError("low-confidence facet lacks review reason")
            if requirement.get("composite") and len(requirement.get("facets", [])) > 1 and "multiple_facets" not in reasons:
                raise FacetExtractionError("multi-facet requirement lacks review reason")
            if method == "ai" and "ai_generated" not in reasons:
                raise FacetExtractionError("AI facet lacks ai_generated review reason")
            queue_item = queue_by_facet.get(facet.get("stable_id"))
            if not queue_item or set(queue_item.get("reasons", [])) != reasons:
                raise FacetExtractionError("facet review queue entry is missing or inconsistent")


def hydrate_eval_case(case: dict[str, Any]) -> dict[str, Any]:
    hydrated = copy.deepcopy(case["expectedOutput"])
    input_value = case["input"]
    input_sha256 = sha256_json(input_value)
    source_text_sha256 = sha256_text(input_value["sourceText"])
    hydrated["generation"]["input_sha256"] = input_sha256
    for requirement in hydrated["requirements"]:
        if requirement["source_text_sha256"] == "SOURCE_TEXT_SHA256_FROM_CASE":
            requirement["source_text_sha256"] = source_text_sha256
    hydrated["generation"]["output_sha256"] = sha256_json(output_payload(hydrated))
    validate_envelope_trace(hydrated, expected_input_sha256=input_sha256)
    return hydrated


def hydrate_eval_suite(suite: dict[str, Any]) -> dict[str, Any]:
    if suite.get("mode") != "draft_test":
        raise FacetExtractionError("CEK-07 eval suite must stay draft_test")
    if suite.get("allowRealModelCalls") is not False:
        raise FacetExtractionError("CEK-07 eval suite must disable real model calls")
    if suite.get("productionEligible") is not False:
        raise FacetExtractionError("CEK-07 eval suite must not be production eligible")
    cases = suite.get("cases")
    if not isinstance(cases, list) or not cases:
        raise FacetExtractionError("CEK-07 eval suite has no cases")
    return {
        "schema_version": "curriculum-requirement-extraction-eval-hydrated.v1",
        "suite_id": suite["suiteId"],
        "allow_real_model_calls": False,
        "production_eligible": False,
        "cases": [
            {
                "case_id": case["caseId"],
                "schema_path": case["schemaPath"],
                "prompt_version": case["promptVersion"],
                "output": hydrate_eval_case(case),
            }
            for case in cases
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build deterministic RequirementFacet candidates or hydrate CEK-07 eval fixtures"
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--input")
    mode.add_argument("--eval-suite")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        if args.eval_suite:
            source_path = Path(args.eval_suite)
            suite = json.loads(source_path.read_text(encoding="utf-8"))
            output = hydrate_eval_suite(suite)
            summary = {
                "status": "pass",
                "mode": "eval_fixture",
                "cases": len(output["cases"]),
                "external_model_calls": 0,
            }
        else:
            source_path = Path(args.input)
            candidate = json.loads(source_path.read_text(encoding="utf-8"))
            output = build_rule_envelope(candidate, input_sha256=sha256_file(source_path))
            summary = {
                "status": "pass",
                "mode": "rules",
                "requirements": len(output["requirements"]),
                "facets": sum(len(item["facets"]) for item in output["requirements"]),
                "review_queue": len(output["review_queue"]),
                "external_model_calls": 0,
            }
        write_json_atomic(output, Path(args.output))
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError, FacetExtractionError) as exc:
        print(json.dumps({"status": "manual_takeover_required", "error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
