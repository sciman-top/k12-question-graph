# 2026-06-06 外部参考库 manifest 化证据

## Goal

把 `D:\CODE\external\k12-question-graph-references` 的仓库列表、分组、上游 URL、用途说明、最近一次验证提交号和补充说明收敛到单一机器可读 manifest，避免 `update-references.ps1`、外部 README 和项目内文档各自维护一份名单。

## Changes

- 新增外部 manifest：
  - `D:\CODE\external\k12-question-graph-references\references.manifest.json`
- 更新：
  - `D:\CODE\external\k12-question-graph-references\update-references.ps1`
  - `D:\CODE\external\k12-question-graph-references\README.md`
  - `docs/26_References.md`
  - `sources/references.md`

## Verification

- `Get-Content D:\CODE\external\k12-question-graph-references\references.manifest.json -TotalCount 120`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File D:\CODE\external\k12-question-graph-references\update-references.ps1 -Mode core`
- `rg -n "lastVerifiedCommit|notes|references.manifest.json|Mode core|Mode optional|Mode all" docs/26_References.md D:\CODE\external\k12-question-graph-references\README.md D:\CODE\external\k12-question-graph-references\update-references.ps1`

## Gate / N/A

- build：`gate_na`。reason：本轮只改仓库外参考资料与文档入口，不改应用代码、依赖、配置、schema 或运行行为。alternative_verification：manifest 读取、脚本运行和文档检索。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：执行参考库更新脚本 `-Mode core` 验证 manifest 驱动路径有效。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- contract/invariant：`gate_na`。reason：本轮未改变业务 contract，只调整参考库维护方式。alternative_verification：项目内外入口都指向同一 manifest。evidence_link：本文件。expires_at：下一次 roadmap/backlog/schema 合同改动。
- hotspot：`gate_na`。reason：本轮无 API/UI/worker/data/AI/export/analysis 行为变化。alternative_verification：人工复核仅收敛外部参考库维护入口。evidence_link：本文件。expires_at：下一次行为改动。

## Rollback

```powershell
git restore -- docs/26_References.md sources/references.md
git clean -f -- docs/evidence/20260606-external-reference-manifest.md
Remove-Item -LiteralPath 'D:\CODE\external\k12-question-graph-references\references.manifest.json' -Force
```
