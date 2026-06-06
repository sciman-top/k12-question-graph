# 2026-06-06 外部参考库索引登记证据

## Goal

把已拉取到 `D:\CODE\external\k12-question-graph-references` 的外部参考仓库登记到本项目文档，方便后续工程师和 agent 在仓内发现并按边界查阅。

## Changes

- `docs/26_References.md`：新增“本地浅克隆参考库”章节，记录外部目录、更新命令、15 个已落地仓库和 OpenAI Cookbook 的 Windows checkout 限制。
- `sources/references.md`：补充对应上游 URL，并把 Open edX 主仓更新为 `openedx/openedx-platform`。
- `README.md`：在文件结构说明中补充外部浅克隆参考库入口。

## Verification

- `rg -n "k12-question-graph-references|openedx/openedx-platform|OpenAI Cookbook" README.md docs/26_References.md sources/references.md`
- `git status --short --branch`

## Gate / N/A

- build：`gate_na`。reason：本轮只改 Markdown 文档和仓库外参考索引，不改代码、依赖、配置、schema 或运行路径。alternative_verification：`rg` 检索确认入口一致。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：`rg` 检索确认 `docs/26_References.md` 与 `sources/references.md` 关键来源一致。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- contract/invariant：`gate_na`。reason：本轮未改变 roadmap/backlog/schema 合同，仅登记外部参考资料入口。alternative_verification：`rg` 检索确认 README、docs、sources 三处入口一致。evidence_link：本文件。expires_at：下一次 roadmap/backlog/schema 合同改动。
- hotspot：`gate_na`。reason：本轮无 API/UI/worker/data/AI/export/analysis 行为变化。alternative_verification：人工复核文档边界明确“只作参考、不照搬、不提交”。evidence_link：本文件。expires_at：下一次外部参考影响实现决策时。

## Rollback

```powershell
git restore -- README.md docs/26_References.md sources/references.md
git clean -f -- docs/evidence/20260606-external-reference-index.md
```
