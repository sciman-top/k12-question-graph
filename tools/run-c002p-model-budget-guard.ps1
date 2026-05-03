param(
    [string] $Output = 'docs\evidence\c002p-model-budget-guard-report.json'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    @'
from __future__ import annotations

import json
from pathlib import Path

import yaml


CONFIG_PATH = Path("configs/model_routing.defaults.yaml")
C002N_REPORT_PATH = Path("docs/evidence/c002n-source-chunk-cache-report.json")
C002O_REPORT_PATH = Path("docs/evidence/c002o-candidate-extraction-eval-report.json")
C002P_REPORT_PATH = Path("docs/evidence/c002p-model-budget-guard-report.json")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


config = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
c002n = json.loads(C002N_REPORT_PATH.read_text(encoding="utf-8"))
c002o = json.loads(C002O_REPORT_PATH.read_text(encoding="utf-8"))
outer = config["outer_ai_validation"]
roles = outer["role_to_model"]
local = config["local_first_contract"]
layers = local["c002_extraction_layers"]
defaults = local["c002_layer_model_defaults"]
budgets = local["c002_budget_controls"]

expected_roles = {
    "bulk_prefilter_model": "gpt-5.4-mini",
    "mechanical_cleanup_model": "gpt-5.3-codex-spark",
    "engineering_review_model": "gpt-5.3-codex",
    "high_risk_review_model": "gpt-5.4",
    "highest_risk_decision_model": "gpt-5.5",
}
for role, model in expected_roles.items():
    require(roles.get(role) == model, f"role_to_model mismatch: {role}")

expected_layers = {
    "L0": {"external_ai_allowed": False, "reasoning_effort": "none", "model": "none"},
    "L1": {"external_ai_allowed": True, "reasoning_effort": "low", "model": "gpt-5.4-mini"},
    "L2": {"external_ai_allowed": True, "reasoning_effort": "medium", "model": "gpt-5.4-mini"},
    "L3": {"external_ai_allowed": True, "reasoning_effort": "medium_or_high", "model": "gpt-5.3-codex"},
    "L4": {"external_ai_allowed": True, "reasoning_effort": "high_or_extra_high", "model": "gpt-5.4"},
}
for layer, expected in expected_layers.items():
    require(layer in layers, f"missing extraction layer: {layer}")
    require(layer in defaults, f"missing layer model default: {layer}")
    require(layers[layer]["external_ai_allowed"] is expected["external_ai_allowed"], f"{layer} external_ai_allowed mismatch")
    require(layers[layer]["reasoning_effort"] == expected["reasoning_effort"], f"{layer} reasoning_effort mismatch")
    require(defaults[layer]["model"] == expected["model"], f"{layer} model default mismatch")

require(defaults["L4"]["escalate_to"] == "gpt-5.5", "L4 must escalate to gpt-5.5 only for highest-risk decisions")
require(defaults["L4"]["reasoning_effort"] == "high", "L4 default reasoning must stay high before explicit extra-high escalation")
require(defaults["L4"]["escalate_reasoning_effort"] == "xhigh", "L4 highest-risk escalation must use xhigh reasoning")

for item in [
    "file_hash_dedup",
    "source_material_metadata_parse",
    "csv_excel_schema_validation",
    "json_yaml_schema_validation",
    "candidate_import_idempotency",
    "active_activation_guard",
    "c002_chunk_hash_cache",
    "token_budget_estimation",
    "chinese_user_output_guard",
]:
    require(item in local["no_external_ai"], f"missing no_external_ai item: {item}")

for flag in [
    "forbid_full_source_bulk_submission",
    "fail_closed_on_missing_token_estimate",
    "fail_closed_on_budget_overrun",
    "require_chunk_cache_before_external_ai",
    "require_schema_eval_before_external_ai",
    "require_budget_guard_before_external_ai",
]:
    require(budgets.get(flag) is True, f"budget control must be true: {flag}")

dry_run = budgets["dry_run_limits"]
require(dry_run["max_source_documents"] <= 4, "C002Q dry-run must stay small-batch")
require(dry_run["max_chunks_total"] <= 32, "C002Q dry-run chunk cap is too high")
require(dry_run["max_estimated_input_tokens"] <= 120000, "C002Q dry-run input token cap is too high")
require(dry_run["max_l4_items"] <= 3, "L4 dry-run item cap is too high")

full_limits = budgets["full_extraction_limits"]
require(full_limits["require_explicit_budget_report"] is True, "full extraction requires explicit budget report")
require(full_limits["require_human_budget_approval"] is True, "full extraction requires human budget approval")
require(full_limits["require_cache_hit_report"] is True, "full extraction requires cache hit report")
require(float(full_limits["max_l4_ratio"]) <= 0.05, "L4 full extraction ratio must stay low")

boundary = config["p0_p1_boundary"]
require(boundary["allow_real_model_calls"] is False, "real model calls must remain disabled by default")
require("stub_llm" in boundary["allowed_handlers"], "stub_llm must remain an allowed draft/test handler")

require(c002n["status"] == "pass", "C002N chunk cache report must pass before C002P")
require(c002n["externalAiCalls"] == 0, "C002N must have zero external AI calls")
require(c002n["sourceHashCoverage"]["coveragePass"] is True, "C002N source hash coverage must pass")
require(c002n["cacheIdempotency"]["cacheHitSourceCount"] >= c002n["sourceCount"], "C002N cache must be warm before C002P")
require(c002n["totals"]["estimatedInputTokens"] > dry_run["max_estimated_input_tokens"], "full C002 source tokens should exceed dry-run cap and require budget controls")
require(c002n["totals"]["chunkCount"] > dry_run["max_chunks_total"], "full C002 chunk count should exceed dry-run cap")

require(c002o["status"] == "pass", "C002O schema/eval report must pass before C002P")
require(c002o["allowRealModelCalls"] is False, "C002O must keep real model calls disabled")
require(c002o["productionEligible"] is False, "C002O must not be production eligible")
require(c002o["checkedAnchorCount"] >= 1, "C002O must validate source anchors from C002N")

report = {
    "status": "pass",
    "task": "C002P",
    "guard": "c002p-model-budget",
    "rolesChecked": sorted(expected_roles),
    "layersChecked": sorted(expected_layers),
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
    "dryRunLimits": dry_run,
    "fullSourceExceedsDryRunLimits": True,
    "highestRiskEscalation": {
        "model": defaults["L4"]["escalate_to"],
        "reasoningEffort": defaults["L4"]["escalate_reasoning_effort"],
    },
    "fullExtractionRequiresHumanBudgetApproval": full_limits["require_human_budget_approval"],
    "realModelCallsDefault": boundary["allow_real_model_calls"],
    "summaryChinese": {
        "title": "C002P 分层模型路由预算门禁报告",
        "result": "通过",
        "boundary": "C002Q 只能小批量 dry-run；33 份来源的 full extraction 超出 dry-run 上限，必须有人工作预算确认。",
        "next": "下一步可进入 C002Q0 真实模型调用与 outer subagent 编排 readiness。",
    },
}
C002P_REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
C002P_REPORT_PATH.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
'@ | python -
    if ($LASTEXITCODE -ne 0) {
        throw "c002p model budget guard failed"
    }
}
finally {
    Pop-Location
}
