# 20260710 Agent Rule Contract v2 - k12-question-graph

- `issue_id`: `agent-rule-coordination-v2`
- 风险等级：低（项目规则、wrapper 与证据；未改运行时代码/配置/凭据）。
- 依据：控制仓 `docs/specs/agent-rule-coordination-v2-spec.md` 与 2026-07-10 官方/社区实践研究。
- 变更：项目 `AGENTS.md` 升级为宿主中立 `2.0` 契约；`CLAUDE.md` 收敛为无 BOM 单行 `@AGENTS.md`；未删除历史兼容文件。

## Verification
- `python D:\CODE\governed-ai-coding-runtime\scripts\verify-target-project-rules.py --targets k12-question-graph --require-all`
- 关键结果：`status=pass`、`blocking_findings=[]`、`project_contract_version=2.0`、`reviewed_global_release=9.55`。
- 补充检查：`git diff --check -- AGENTS.md CLAUDE.md docs/evidence/20260710-agent-rule-contract-v2.md`。

## Gate Applicability
- build：`gate_na`; `reason=纯 Markdown 项目规则切片，未触及可执行产物`; `alternative_verification=项目契约 verifier + git diff --check`; `evidence_link=docs/evidence/20260710-agent-rule-contract-v2.md`; `expires_at=task_end`。
- test：`gate_na`; `reason=未改变运行时行为，产品测试不会增加本切片证明力`; `alternative_verification=首行/BOM/锚点/预算/宿主中立回归测试`; `evidence_link=docs/evidence/20260710-agent-rule-contract-v2.md`; `expires_at=task_end`。
- contract/invariant：通过控制仓目标契约 verifier；产品合同门禁在下一次 executable change 恢复。
- hotspot：静态复核 wrapper 仅 1 行、项目规则低于预算、无受管平台残留；产品 hotspot 在下一次 executable change 恢复。

## Compatibility And Rollback
- 兼容性：未改公开 API、数据格式、provider/auth、MCP、依赖、CI 或产品运行时；项目合同版本变化只影响 agent instruction integration。
- 工作树边界：本轮前工作树无无关改动；未运行会影响 PostgreSQL/API 进程的 full gate。
- 回滚：只撤销本仓 `AGENTS.md`、`CLAUDE.md` 与本文件；不得对整个工作树执行 reset/restore，不得覆盖其他任务改动。
