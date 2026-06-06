# 2026-06-06 外部参考库 core/optional 分层与增补证据

## Goal

按当前项目真实技术主线，补齐缺失的高优先级参考仓库，并把 `D:\CODE\external\k12-question-graph-references` 的更新策略从“默认全量 pull”收紧为 `core / optional / all` 三档，降低长期维护噪音。

## Changes

- 新增外部参考仓库：
  - `document-ocr-ai/PaddleOCR`
  - `document-ocr-ai/OCRmyPDF`
  - `official-docs/Open-XML-SDK`
- 更新外部参考库：
  - `D:\CODE\external\k12-question-graph-references\update-references.ps1`
  - `D:\CODE\external\k12-question-graph-references\README.md`
- 更新项目入口：
  - `docs/26_References.md`
  - `sources/references.md`

## Verification

- `Get-ChildItem D:\CODE\external\k12-question-graph-references\document-ocr-ai | Select-Object -ExpandProperty Name`
- `Get-ChildItem D:\CODE\external\k12-question-graph-references\official-docs | Select-Object -ExpandProperty Name`
- `git -C D:\CODE\external\k12-question-graph-references\document-ocr-ai\OCRmyPDF rev-parse --short HEAD`
- `git -C D:\CODE\external\k12-question-graph-references\document-ocr-ai\PaddleOCR rev-parse --short HEAD`
- `git -C D:\CODE\external\k12-question-graph-references\official-docs\Open-XML-SDK rev-parse --short HEAD`
- `rg -n "Open-XML-SDK|PaddleOCR|OCRmyPDF|Mode core|Mode optional|Mode all" docs/26_References.md sources/references.md D:\CODE\external\k12-question-graph-references\README.md D:\CODE\external\k12-question-graph-references\update-references.ps1`

## Gate / N/A

- build：`gate_na`。reason：本轮只改仓库外参考资料和文档入口，不改应用代码、依赖、配置、schema 或运行行为。alternative_verification：目录检查、git rev-parse 和文档检索。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- test：`gate_na`。reason：同上。alternative_verification：不运行应用测试，改用参考仓完整性和入口检索确认。evidence_link：本文件。expires_at：下一次代码、依赖、配置或门禁脚本改动。
- contract/invariant：`gate_na`。reason：本轮未改变业务 contract，只调整外部参考分层和索引。alternative_verification：`docs/26_References.md` 与外部 README 关键入口一致。evidence_link：本文件。expires_at：下一次 roadmap/backlog/schema 合同改动。
- hotspot：`gate_na`。reason：本轮无 API/UI/worker/data/AI/export/analysis 行为变化。alternative_verification：人工复核仅补外部参考仓与更新策略，不改变产品实现。evidence_link：本文件。expires_at：下一次行为改动。

## Rollback

```powershell
git restore -- docs/26_References.md sources/references.md
git clean -f -- docs/evidence/20260606-external-reference-core-optional-refresh.md
Remove-Item -LiteralPath 'D:\CODE\external\k12-question-graph-references\document-ocr-ai\PaddleOCR' -Recurse -Force
Remove-Item -LiteralPath 'D:\CODE\external\k12-question-graph-references\document-ocr-ai\OCRmyPDF' -Recurse -Force
Remove-Item -LiteralPath 'D:\CODE\external\k12-question-graph-references\official-docs\Open-XML-SDK' -Recurse -Force
```
