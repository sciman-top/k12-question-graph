param(
    [string] $ManifestPath = 'configs\ai-evals\c002q0-outer-ai-readiness.sample.json',
    [string] $Output = 'docs\evidence\c002q0-outer-ai-readiness-report.json'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    $env:C002Q0_MANIFEST_PATH = $ManifestPath
    $env:C002Q0_OUTPUT_PATH = $Output
    @'
from __future__ import annotations

import json
import os
from pathlib import Path

import yaml


CONFIG_PATH = Path("configs/model_routing.defaults.yaml")
MANIFEST_PATH = Path(os.environ["C002Q0_MANIFEST_PATH"])
OUTPUT_PATH = Path(os.environ["C002Q0_OUTPUT_PATH"])


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


config = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
manifest = load_json(MANIFEST_PATH)
c002n = load_json(Path(manifest["sourceReports"]["chunkCacheReport"]))
c002o = load_json(Path(manifest["sourceReports"]["schemaEvalReport"]))
c002p = load_json(Path(manifest["sourceReports"]["budgetGuardReport"]))

boundary = config["p0_p1_boundary"]
local = config["local_first_contract"]
defaults = local["c002_layer_model_defaults"]
budgets = local["c002_budget_controls"]
dry_run_limits = budgets["dry_run_limits"]

require(manifest["manifestVersion"] == "c002q0.outer-ai-readiness.v0.1", "unexpected manifestVersion")
require(manifest["mode"] == "draft_test", "C002Q0 must stay in draft_test mode")
require(manifest["allowProjectRuntimeRealModelCalls"] is False, "project runtime real model calls must remain disabled")
require(manifest["externalAiCallsInReadiness"] == 0, "C002Q0 readiness must not call external AI")
require(manifest["orchestrationOnly"] is True, "outer AI orchestration must be orchestration-only")
require(manifest["subagentRuntimeDependency"] is False, "subagent must not become a project runtime dependency")
require(manifest["noActiveWrite"] is True, "C002Q0 must require noActiveWrite")
require(manifest["humanReviewRequired"] is True, "C002Q0 must require human review")
require(manifest["cacheHitRequired"] is True, "C002Q0 must require cache hit evidence")
require(manifest["productionEligible"] is False, "C002Q0 outputs must not be production eligible")
require(manifest["reviewStatus"] == "pending_review", "C002Q0 outputs must remain pending_review")

require(boundary["allow_real_model_calls"] is False, "repository boundary must keep real model calls disabled")
require("stub_llm" in boundary["allowed_handlers"], "stub_llm must remain the project draft/test LLM handler")

require(c002n["status"] == "pass", "C002N report must pass before C002Q0")
require(c002n["externalAiCalls"] == 0, "C002N must have zero external AI calls")
require(c002n["cacheIdempotency"]["cacheHitSourceCount"] >= c002n["sourceCount"], "C002N cache must be warm before C002Q0")
require(c002o["status"] == "pass", "C002O report must pass before C002Q0")
require(c002o["allowRealModelCalls"] is False, "C002O must keep real model calls disabled")
require(c002o["productionEligible"] is False, "C002O must not be production eligible")
require(c002p["status"] == "pass", "C002P report must pass before C002Q0")
require(c002p["fullSourceExceedsDryRunLimits"] is True, "C002P must prove full source exceeds dry-run limits")
require(c002p["fullExtractionRequiresHumanBudgetApproval"] is True, "C002P must require human budget approval for full extraction")
require(c002p["realModelCallsDefault"] is False, "C002P must keep real model calls disabled by default")

sample = manifest["sampleRate"]
require(sample["sourceDocuments"] <= dry_run_limits["max_source_documents"], "sample source document count exceeds C002P dry-run limit")
require(sample["chunksTotal"] <= dry_run_limits["max_chunks_total"], "sample chunk count exceeds C002P dry-run limit")
require(sample["chunksPerSourceDocument"] <= dry_run_limits["max_chunks_per_source_document"], "sample chunks per source exceeds C002P dry-run limit")
require(sample["estimatedInputTokens"] <= dry_run_limits["max_estimated_input_tokens"], "sample input tokens exceed C002P dry-run limit")
require(sample["estimatedOutputTokens"] <= dry_run_limits["max_estimated_output_tokens"], "sample output tokens exceed C002P dry-run limit")
require(sample["l4Items"] <= dry_run_limits["max_l4_items"], "sample L4 items exceed C002P dry-run limit")

required_anchors = {
    "source_hash",
    "source_document_id",
    "page_number",
    "chunk_hash",
    "schema_version",
    "prompt_version",
    "model_role",
    "model",
    "reasoning_effort",
    "estimated_input_tokens",
    "estimated_output_tokens",
    "cached_tokens",
    "cost_estimate",
    "cache_hit",
    "no_active_write",
    "review_status",
}
anchors = set(manifest["evidenceAnchorFields"])
missing = sorted(required_anchors - anchors)
require(not missing, f"missing evidence anchor fields: {missing}")

required_input_artifacts = {
    "docs/evidence/c002n-source-chunk-cache-report.json",
    "docs/evidence/c002o-candidate-extraction-eval-report.json",
    "docs/evidence/c002p-model-budget-guard-report.json",
    "configs/model_routing.defaults.yaml",
    "schemas/ai/c002_candidate_extraction.schema.json",
}
require(required_input_artifacts.issubset(set(manifest["inputArtifacts"])), "manifest missing required input artifacts")
require(str(OUTPUT_PATH).replace("\\", "/") in manifest["outputArtifacts"], "manifest missing C002Q0 report output artifact")
require("docs/evidence/c002q-ai-extract-dry-run-report.json" in manifest["outputArtifacts"], "manifest must reserve C002Q dry-run output artifact")

roles_by_layer = {item["layer"]: item for item in manifest["modelRoles"]}
for layer in ["L0", "L1", "L2", "L3", "L4"]:
    require(layer in roles_by_layer, f"missing model role layer: {layer}")
    role = roles_by_layer[layer]
    expected = defaults[layer]
    require(role["modelRole"] == expected["model_role"], f"{layer} modelRole mismatch")
    require(role["model"] == expected["model"], f"{layer} model mismatch")
    require(role["reasoningEffort"] == expected["reasoning_effort"], f"{layer} reasoning mismatch")
    if layer == "L0":
        require(role["externalAiAllowed"] is False, "L0 must not allow external AI")
    else:
        require(role["externalAiAllowed"] is True, f"{layer} should be an external AI dry-run layer only after explicit C002Q execution")

require(roles_by_layer["L4"]["escalateTo"] == defaults["L4"]["escalate_to"], "L4 escalation model mismatch")
require(roles_by_layer["L4"]["escalateReasoningEffort"] == defaults["L4"]["escalate_reasoning_effort"], "L4 escalation reasoning mismatch")

review = manifest["humanReviewBoundary"]
require(review["allOutputsEnterReviewQueue"] is True, "all outputs must enter review queue")
require(review["autoActivate"] is False, "C002Q0/C002Q must not auto activate")
require("active" in review["blockedStatuses"], "active status must be blocked")

runtime = manifest["runtimeBoundary"]
require(runtime["projectRuntimeDependency"] is False, "outer subagent must not be project runtime dependency")
require(runtime["teacherFacingRuntimeDependency"] is False, "teacher runtime must not depend on subagent")
require(runtime["subagentUse"] == "outer_parallel_execution_and_review_only", "subagent use must stay outer-only")

report = {
    "status": "pass",
    "task": "C002Q0",
    "guard": "c002q0-outer-ai-readiness",
    "manifest": str(MANIFEST_PATH).replace("\\", "/"),
    "batchId": manifest["batchId"],
    "mode": manifest["mode"],
    "allowProjectRuntimeRealModelCalls": manifest["allowProjectRuntimeRealModelCalls"],
    "externalAiCallsInReadiness": manifest["externalAiCallsInReadiness"],
    "subagentRuntimeDependency": manifest["subagentRuntimeDependency"],
    "orchestrationOnly": manifest["orchestrationOnly"],
    "noActiveWrite": manifest["noActiveWrite"],
    "humanReviewRequired": manifest["humanReviewRequired"],
    "cacheHitRequired": manifest["cacheHitRequired"],
    "productionEligible": manifest["productionEligible"],
    "reviewStatus": manifest["reviewStatus"],
    "sourceEvidence": {
        "sourceCount": c002n["sourceCount"],
        "chunkCount": c002n["totals"]["chunkCount"],
        "estimatedInputTokens": c002n["totals"]["estimatedInputTokens"],
        "cacheHitSourceCount": c002n["cacheIdempotency"]["cacheHitSourceCount"],
    },
    "schemaEvalEvidence": {
        "suiteId": c002o["suiteId"],
        "checkedAnchorCount": c002o["checkedAnchorCount"],
        "productionEligible": c002o["productionEligible"],
    },
    "budgetEvidence": {
        "dryRunLimits": c002p["dryRunLimits"],
        "fullSourceExceedsDryRunLimits": c002p["fullSourceExceedsDryRunLimits"],
        "fullExtractionRequiresHumanBudgetApproval": c002p["fullExtractionRequiresHumanBudgetApproval"],
    },
    "sampleRate": sample,
    "modelLayersChecked": sorted(roles_by_layer),
    "evidenceAnchorFieldsChecked": sorted(required_anchors),
    "outputArtifacts": manifest["outputArtifacts"],
    "summaryChinese": {
        "title": "C002Q0 真实模型调用与 outer subagent 编排 readiness 报告",
        "result": "通过",
        "boundary": "本任务只验证外层 AI runner/subagent 编排合同；不调用真实模型，不写 active，不成为项目运行时依赖。",
        "next": "下一步可进入 C002Q 小批量 AI extract dry-run，输出仍必须保持 candidate/pending_review/production_eligible=false。",
    },
}
OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
OUTPUT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
'@ | python -
    if ($LASTEXITCODE -ne 0) {
        throw "C002Q0 outer AI readiness guard failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:C002Q0_MANIFEST_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:C002Q0_OUTPUT_PATH -ErrorAction SilentlyContinue
    Pop-Location
}
