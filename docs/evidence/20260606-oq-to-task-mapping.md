# 2026-06-06 OQ 到任务清单映射证据

## Goal

把 `docs/104_OpenQuestionsAndAssumptions.md` 中的 `OQ01-OQ08` 逐条映射到现有机器任务清单，明确哪些事项需要回写 CSV、哪些不应新增任务，只沿现有任务和治理入口关闭。

## Result

- 已更新 `docs/104_OpenQuestionsAndAssumptions.md`
- 新增 `2.1 CSV 处理结论` 和 `2.2 当前结论`
- 当前结论：`OQ01-OQ08` **均不新增 CSV 任务**

## Mapping Summary

| OQ | 映射任务 | 结论 |
|---|---|---|
| `OQ01` | `P006` | 不新增任务 |
| `OQ02` | `O004B` + `P001` + `P006` | 不新增任务 |
| `OQ03` | `NS1303` + `NS1305` + `P001` | 不新增任务 |
| `OQ04` | `P002` + `P003` + `P004` | 不新增任务 |
| `OQ05` | `I008` + `I009` + `I010` + `NS1301` | 不新增任务 |
| `OQ06` | `R007` + `NS1203` + `P006` | 不新增任务 |
| `OQ07` | `NS1305` + `O008` + `P001` | 不新增任务 |
| `OQ08` | `P003` | 不新增任务 |

## Why No CSV Changes

本轮没有修改 `tasks/backlog.csv` 或 `tasks/non-site-implementation-plan.csv`，原因是所有关键未决事项已经被现有任务链覆盖。当前缺的是：

- 发布前置证据
- 现场数据授权
- 现场试点反馈
- 运行形态收束

而不是机器任务项缺失。

## Verification

- `rg -n "## 2.1 CSV 处理结论|## 2.2 当前结论|OQ01|OQ08|不新增任务" docs/104_OpenQuestionsAndAssumptions.md`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1`

## Gate / N/A

- build：`gate_na`。reason：本轮只更新治理文档与证据，不改应用代码、依赖、配置、schema 或运行行为。alternative_verification：文档检索和 roadmap guard。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：引用既有 full gate 基线并运行 roadmap guard。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- contract/invariant：`gate_na`。reason：本轮未改变 backlog/non-site/productization CSV 内容，只补 OQ 与任务映射说明。alternative_verification：人工复核映射任务在现有 CSV 中均存在。evidence_link：本文件。expires_at：下一次 roadmap/backlog/schema 合同改动。
- hotspot：`gate_na`。reason：本轮无 API/UI/worker/data/AI/export/analysis 行为变化。alternative_verification：人工复核本轮只补治理映射说明。evidence_link：本文件。expires_at：下一次行为改动。

## Rollback

```powershell
git restore -- docs/104_OpenQuestionsAndAssumptions.md
git clean -f -- docs/evidence/20260606-oq-to-task-mapping.md
```
