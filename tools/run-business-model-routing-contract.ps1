$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    @'
from __future__ import annotations

import json
from pathlib import Path

import yaml


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


root = Path.cwd()
config = yaml.safe_load((root / "configs/model_routing.defaults.yaml").read_text(encoding="utf-8"))
app = json.loads((root / "apps/api/appsettings.json").read_text(encoding="utf-8"))

expected_roles = {
    "general_structuring": ("gpt-5.6-sol", "medium"),
    "visual_document": ("gpt-5.6-luna", "xhigh"),
    "semantic_decision": ("gpt-5.6-sol", "xhigh"),
}
catalog = config["model_catalog"]
for role, (model, reasoning) in expected_roles.items():
    require(role in catalog, f"missing business model role: {role}")
    require(catalog[role]["model"] == model, f"model catalog mismatch: {role}")
    require(catalog[role]["reasoning_effort"] == reasoning, f"reasoning catalog mismatch: {role}")

expected_tasks = {
    "source_material_ingest": ("ingest", "local_deterministic", "none", "none"),
    "question_extraction": ("structuring", "general_structuring", "gpt-5.6-sol", "medium"),
    "crop_candidate_generation": ("cutting", "visual_document", "gpt-5.6-luna", "xhigh"),
    "knowledge_tagging": ("tagging", "general_structuring", "gpt-5.6-sol", "medium"),
    "knowledge_mapping_review": ("tagging", "semantic_decision", "gpt-5.6-sol", "xhigh"),
    "natural_language_paper_request": ("paper_request", "general_structuring", "gpt-5.6-sol", "medium"),
    "paper_composition": ("assembly", "semantic_decision", "gpt-5.6-sol", "xhigh"),
    "visual_asset_review": ("review", "visual_document", "gpt-5.6-luna", "xhigh"),
    "answer_verification": ("verification", "semantic_decision", "gpt-5.6-sol", "xhigh"),
}

policy_routes = config["routes"]
runtime_routes = app["AiRouting"]["Routes"]
for task, (stage, role, model, reasoning) in expected_tasks.items():
    require(task in policy_routes, f"policy route missing: {task}")
    require(task in runtime_routes, f"runtime route missing: {task}")
    policy = policy_routes[task]
    runtime = runtime_routes[task]
    require(policy["stage"] == stage, f"policy stage mismatch: {task}")
    require(policy["model_role"] == role, f"policy role mismatch: {task}")
    require(policy["model"] == model, f"policy model mismatch: {task}")
    require(policy["reasoning_effort"] == reasoning, f"policy reasoning mismatch: {task}")
    require(runtime["Stage"] == stage, f"runtime stage mismatch: {task}")
    require(runtime["ModelRole"] == role, f"runtime role mismatch: {task}")
    require(runtime["ModelName"] == model, f"runtime model mismatch: {task}")
    require(runtime["ReasoningEffort"] == reasoning, f"runtime reasoning mismatch: {task}")

for task in ["crop_candidate_generation", "visual_asset_review", "paper_composition"]:
    schema = runtime_routes[task].get("StructuredOutputSchema")
    require(schema and (root / schema).is_file(), f"missing structured output schema: {task}")

require(config["route_contract"]["task_scoped"] is True, "business routing must be task scoped")
require(config["route_contract"]["local_execution_before_model"] is True, "local-first execution contract missing")
require(config["route_contract"]["model_output_status"] == "pending_review", "model output must stay pending_review")
require(config["route_contract"]["production_eligible_default"] is False, "business AI output must not be production eligible")
require(config["route_contract"]["crop_model_proposes_regions_only"] is True, "crop model must not own crop execution")
require(config["route_contract"]["paper_model_reviews_candidates_only"] is True, "paper model must not replace hard constraints")
require(app["AiRouting"]["AllowRealModelCalls"] is False, "runtime real model calls must stay disabled")

report = {
    "status": "pass",
    "task": "business-model-routing",
    "routingVersion": app["AiRouting"]["Version"],
    "rolesChecked": sorted(expected_roles),
    "tasksChecked": sorted(expected_tasks),
    "runtimeRealModelCalls": app["AiRouting"]["AllowRealModelCalls"],
    "reviewStatus": config["route_contract"]["model_output_status"],
    "productionEligibleDefault": config["route_contract"]["production_eligible_default"],
    "boundary": "业务模型路由已投影到配置和运行时合同；真实 provider、active 写入和 live acceptance 仍未启用。",
}
print(json.dumps(report, ensure_ascii=False, indent=2))
'@ | python -X utf8 -
    if ($LASTEXITCODE -ne 0) {
        throw "business model routing contract failed"
    }
}
finally {
    Pop-Location
}
