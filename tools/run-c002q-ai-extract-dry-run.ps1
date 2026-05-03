param(
    [string] $ManifestPath = 'configs\ai-evals\c002q-ai-extract-dry-run.sample.json',
    [string] $Output = 'docs\evidence\c002q-ai-extract-dry-run-report.json'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    $env:C002Q_MANIFEST_PATH = $ManifestPath
    $env:C002Q_OUTPUT_PATH = $Output
    @'
from __future__ import annotations

import json
import os
from collections import OrderedDict
from pathlib import Path

import yaml


CONFIG_PATH = Path("configs/model_routing.defaults.yaml")
MANIFEST_PATH = Path(os.environ["C002Q_MANIFEST_PATH"])
OUTPUT_PATH = Path(os.environ["C002Q_OUTPUT_PATH"])


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def first_source_by_type(sources: list[dict], source_type: str) -> dict:
    matches = [source for source in sources if source["sourceType"] == source_type and source.get("cacheHit") is True]
    require(matches, f"missing cache-hit source for type: {source_type}")
    return matches[0]


config = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
manifest = load_json(MANIFEST_PATH)
readiness = load_json(Path(manifest["requires"]["readinessReport"]))
chunk_report = load_json(Path(manifest["requires"]["chunkCacheReport"]))
schema = load_json(Path(manifest["requires"]["schemaPath"]))

require(manifest["manifestVersion"] == "c002q.ai-extract-dry-run.v0.1", "unexpected C002Q manifest version")
require(manifest["mode"] == "draft_test", "C002Q must stay draft_test")
require(manifest["allowRealModelCalls"] is False, "C002Q dry-run must not enable real model calls by default")
require(manifest["externalAiCalls"] == 0, "C002Q contract dry-run must not call external AI")
require(manifest["productionEligible"] is False, "C002Q output must not be production eligible")
require(manifest["reviewStatus"] == "pending_review", "C002Q output must remain pending_review")
require(manifest["noActiveWrite"] is True, "C002Q must not write active assets")

require(readiness["status"] == "pass", "C002Q0 readiness must pass before C002Q")
require(readiness["allowProjectRuntimeRealModelCalls"] is False, "project runtime real model calls must remain disabled")
require(readiness["noActiveWrite"] is True, "C002Q0 must require no active write")
require(readiness["subagentRuntimeDependency"] is False, "subagent must not become runtime dependency")
require(readiness["cacheHitRequired"] is True, "C002Q0 must require cache hit evidence")

require(chunk_report["status"] == "pass", "C002N chunk cache report must pass before C002Q")
require(chunk_report["externalAiCalls"] == 0, "C002N must have zero external AI calls")
require(chunk_report["cacheIdempotency"]["cacheHitSourceCount"] >= chunk_report["sourceCount"], "C002N cache must be warm before C002Q")

required_schema_sections = [
    "source_anchors",
    "knowledge_points",
    "curriculum_standard_items",
    "textbook_chapters",
    "exam_points",
    "trend_summaries",
    "mapping_suggestions",
]
for section in required_schema_sections:
    require(section in schema["required"], f"C002Q schema missing required section: {section}")

policy = manifest["samplePolicy"]
source_types = policy["sourceTypes"]
sample_sources = [first_source_by_type(chunk_report["sources"], source_type) for source_type in source_types]
sample_chunks = []
for source in sample_sources:
    chunks = source["sampleChunks"][: policy["maxChunksPerSourceDocument"]]
    for chunk in chunks:
        sample_chunks.append(
            {
                "sourceType": source["sourceType"],
                "relativePath": source["relativePath"],
                "sourceTitle": source["sourceTitle"],
                "sourceHash": source["sourceHash"],
                "pageNumber": chunk["pageNumber"],
                "chunkHash": chunk["chunkHash"],
                "blockType": chunk["blockType"],
                "estimatedTokens": chunk["estimatedTokens"],
                "cacheHit": source["cacheHit"],
            }
        )

require(len(sample_sources) <= policy["maxSourceDocuments"], "sample source count exceeds policy")
require(len(sample_chunks) <= policy["maxChunksTotal"], "sample chunk count exceeds policy")
estimated_input_tokens = sum(chunk["estimatedTokens"] for chunk in sample_chunks)
estimated_output_tokens = 1800
require(estimated_input_tokens <= policy["maxEstimatedInputTokens"], "sample input token estimate exceeds policy")
require(estimated_output_tokens <= policy["maxEstimatedOutputTokens"], "sample output token estimate exceeds policy")

anchors = []
roles_by_source_type = {
    "curriculum_standard": "scope",
    "textbook": "definition",
    "exam_analysis_report": "trend_evidence",
    "local_exam_paper": "exam_evidence",
}
anchor_chunks = []
for source in sample_sources:
    chunk = source["sampleChunks"][0]
    anchor_chunks.append(
        {
            "sourceType": source["sourceType"],
            "relativePath": source["relativePath"],
            "sourceHash": source["sourceHash"],
            "pageNumber": chunk["pageNumber"],
            "chunkHash": chunk["chunkHash"],
        }
    )

for chunk in anchor_chunks:
    role = roles_by_source_type[chunk["sourceType"]]
    anchors.append(
        {
            "anchor_id": f"anchor-{len(anchors) + 1:02d}",
            "source_hash": chunk["sourceHash"],
            "relative_path": chunk["relativePath"],
            "page_number": chunk["pageNumber"],
            "chunk_hash": chunk["chunkHash"],
            "evidence_role": role,
        }
    )

anchor_refs = [anchor["chunk_hash"] for anchor in anchors]
candidate_output = OrderedDict(
    [
        ("batch_id", manifest["batchId"]),
        ("mode", "draft_test"),
        ("production_eligible", False),
        ("review_status", "pending_review"),
        (
            "source_anchors",
            [
                {
                    "source_hash": anchor["source_hash"],
                    "relative_path": anchor["relative_path"],
                    "page_number": anchor["page_number"],
                    "chunk_hash": anchor["chunk_hash"],
                    "evidence_role": anchor["evidence_role"],
                }
                for anchor in anchors
            ],
        ),
        (
            "knowledge_points",
            [
                {
                    "candidate_id": "c002q-kp-force-motion-l2",
                    "name": "力和运动",
                    "level": "L2",
                    "parent_candidate_id": "c002q-kp-mechanics-l1",
                    "source_anchor_refs": anchor_refs[:2],
                    "confidence": 0.64,
                    "review_status": "pending_review",
                }
            ],
        ),
        (
            "curriculum_standard_items",
            [
                {
                    "candidate_id": "c002q-cs-motion-force-001",
                    "code": "draft-test-cs-motion-force",
                    "text": "从现象和实验中说明力可以改变物体的运动状态。",
                    "source_anchor_refs": anchor_refs[:1],
                    "review_status": "pending_review",
                }
            ],
        ),
        (
            "textbook_chapters",
            [
                {
                    "candidate_id": "c002q-tb-grade8-force-motion",
                    "title": "运动和力",
                    "grade_or_scope": "grade_8_volume_1",
                    "edition_or_version": "2024_person_education_press_grade_8_volume_1",
                    "source_anchor_refs": anchor_refs[1:2],
                    "review_status": "pending_review",
                }
            ],
        ),
        (
            "exam_points",
            [
                {
                    "candidate_id": "c002q-ep-guangzhou-force-motion",
                    "description": "在真实情境中判断力与运动状态变化的关系。",
                    "region": "Guangzhou",
                    "year_range": "2016-2025",
                    "source_anchor_refs": anchor_refs[-1:],
                    "review_status": "pending_review",
                }
            ],
        ),
        (
            "trend_summaries",
            [
                {
                    "candidate_id": "c002q-trend-force-motion-context",
                    "summary": "样本显示本地试题倾向用生活或实验情境考查力与运动关系；该结论仅用于 dry-run，需人工复核。",
                    "source_anchor_refs": anchor_refs[2:],
                    "confidence": 0.58,
                    "review_status": "pending_review",
                }
            ],
        ),
        (
            "mapping_suggestions",
            [
                {
                    "from_candidate_id": "c002q-tb-grade8-force-motion",
                    "to_candidate_id": "c002q-kp-force-motion-l2",
                    "mapping_type": "equivalent",
                    "confidence": 0.61,
                    "impact_level": "medium",
                    "source_anchor_refs": anchor_refs[:],
                    "review_status": "pending_review",
                }
            ],
        ),
        (
            "warnings",
            [
                "contract dry-run only; no real model was called",
                "all outputs remain candidate/pending_review/production_eligible=false",
                "does not overwrite C002K candidate import batch",
            ],
        ),
    ]
)

known_chunk_hashes = {chunk["chunkHash"] for chunk in sample_chunks}
require(candidate_output["mode"] == "draft_test", "candidate output must stay draft_test")
require(candidate_output["production_eligible"] is False, "candidate output must not be production eligible")
require(candidate_output["review_status"] == "pending_review", "candidate output must stay pending_review")
for section in required_schema_sections[1:]:
    require(candidate_output[section], f"candidate output missing section: {section}")
    for item in candidate_output[section]:
        require(item["review_status"] == "pending_review", f"{section} item must stay pending_review")
        for chunk_hash in item["source_anchor_refs"]:
            require(chunk_hash in known_chunk_hashes, f"{section} references unknown chunk hash")

for anchor in candidate_output["source_anchors"]:
    require(anchor["chunk_hash"] in known_chunk_hashes, "source anchor references unknown chunk hash")

defaults = config["local_first_contract"]["c002_layer_model_defaults"]
layer_trace = []
for layer in manifest["layerPlan"]:
    layer_id = layer["layer"]
    expected = defaults[layer_id]
    require(layer["modelRole"] == expected["model_role"], f"{layer_id} model role mismatch")
    require(layer["model"] == expected["model"], f"{layer_id} model mismatch")
    require(layer["reasoningEffort"] == expected["reasoning_effort"], f"{layer_id} reasoning mismatch")
    layer_trace.append(
        {
            "layer": layer_id,
            "purpose": layer["purpose"],
            "modelRole": layer["modelRole"],
            "model": layer["model"],
            "reasoningEffort": layer["reasoningEffort"],
            "called": False,
            "cachedTokens": 0 if layer_id == "L0" else estimated_input_tokens,
            "estimatedInputTokens": 0 if layer_id == "L0" else estimated_input_tokens,
            "estimatedOutputTokens": 0 if layer_id == "L0" else max(100, estimated_output_tokens // 3),
            "estimatedCost": 0.0,
        }
    )

require(len([item for item in layer_trace if item["layer"] == "L4"]) <= policy["maxL4Items"], "L4 item count exceeds policy")

report = {
    "status": "pass",
    "task": "C002Q",
    "guard": "c002q-ai-extract-dry-run",
    "batchId": manifest["batchId"],
    "mode": manifest["mode"],
    "allowRealModelCalls": manifest["allowRealModelCalls"],
    "modelExecutionMode": manifest["modelExecutionMode"],
    "externalAiCalls": manifest["externalAiCalls"],
    "productionEligible": manifest["productionEligible"],
    "reviewStatus": manifest["reviewStatus"],
    "noActiveWrite": manifest["noActiveWrite"],
    "overwritesExistingC002K": False,
    "requiresHumanReview": True,
    "readinessReport": manifest["requires"]["readinessReport"],
    "sample": {
        "sourceDocuments": len(sample_sources),
        "chunksTotal": len(sample_chunks),
        "estimatedInputTokens": estimated_input_tokens,
        "estimatedOutputTokens": estimated_output_tokens,
        "cacheHitChunks": len([chunk for chunk in sample_chunks if chunk["cacheHit"]]),
        "sourceTypes": source_types,
    },
    "budgetLimits": policy,
    "layerTrace": layer_trace,
    "candidateOutput": candidate_output,
    "summaryChinese": {
        "title": "C002Q 小批量 AI extract dry-run 报告",
        "result": "通过",
        "boundary": "本轮为合同 dry-run，不调用真实模型，不写数据库，不覆盖 C002K，输出保持 candidate/pending_review/production_eligible=false。",
        "next": "下一步可进入 C002S 正式化前审查闭环；正式 C002 active 仍等待人工审核、质量问题清零、备份和 active guard。",
    },
}
OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
OUTPUT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
'@ | python -
    if ($LASTEXITCODE -ne 0) {
        throw "C002Q AI extract dry-run failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:C002Q_MANIFEST_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:C002Q_OUTPUT_PATH -ErrorAction SilentlyContinue
    Pop-Location
}
