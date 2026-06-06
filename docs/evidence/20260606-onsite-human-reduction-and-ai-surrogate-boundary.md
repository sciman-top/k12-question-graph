# 2026-06-06 · 现场人工压缩与 AI 视觉代理边界

## Goal

把 `P001-P006` 从“泛化的人工作业”收束为“非现场自动化预检 + 少量不可替代的人类签字与真实环境事实”。

## Changes

- 更新 `docs/101_NonSiteCapabilityImplementationRoadmap.md`，新增“先机验、后到场”原则和三类边界：
  - `可完全替代`
  - `可部分替代 / 显著降负`
  - `不可替代`
- 更新 `docs/104_OpenQuestionsAndAssumptions.md`，明确教师代理 + AI 视觉代理只能关闭客观项，不能替代真实教师理解。
- 更新 `docs/107_AITrustAndReviewContract.md`，明确视觉代理可关闭截图、工件、route smoke、可访问性等客观证据，但不得伪装成人类确认。
- 更新 `docs/109_ReleaseGoNoGoCard.md`，把 `automation / visual surrogate preflight` 明确纳入当前发布判断。
- 更新 `docs/templates/p001/p002/p003/p004/p006` 清单，要求到场前先完成非现场客观检查，现场只处理真实环境事实与签字。
- 更新 `tasks/backlog.csv` 的 `P001-P004/P006` 验收与验证文本，不新增任务，只重写验收边界。

## Decision

本轮不新增 CSV 任务。

理由：现有 `NS906`、`NS904`、`NS1306-NS1308`、`P001-P006` 已覆盖这条治理链。本轮缺的是“验收表达不够清楚”，不是“任务数量不够多”。

## External Basis

以下外部依据只用于校准边界，不直接变成项目指令：

- Playwright `Visual comparisons`
  - 官方文档：<https://playwright.dev/docs/test-snapshots>
  - 用途：支持截图基线比对，适合关闭 route/版面/工件的客观差异。
  - 边界：官方明确截图基线应在稳定环境维护，说明它适合做“前置机验”，不适合把不同现场机器的偶发差异混入同一结论。
- Playwright `Accessibility testing`
  - 官方文档：<https://playwright.dev/docs/accessibility-testing>
  - 用途：自动扫描可提前发现标签、ARIA 等共性问题。
  - 边界：官方明确自动化只能发现一部分问题，仍需 manual accessibility assessments 和 inclusive user testing，因此不能替代真实教师理解。
- Playwright `Emulation`
  - 官方文档：<https://playwright.dev/docs/emulation>
  - 用途：支持设备、viewport、locale、timezone、permissions、colorScheme 等模拟，适合把多环境差异尽量前置到非现场。
- PaddleOCR `General OCR Pipeline Usage Tutorial`
  - 官方文档：<https://www.paddleocr.ai/latest/en/version3.x/pipeline_usage/OCR.html>
  - 用途：支持本地推理、服务部署、并行推理、模型参数化和结果增量返回，适合作为 OCR profile、golden set 和本地/服务化准入依据。
- OCRmyPDF `Introduction`
  - 官方文档：<https://ocrmypdf.readthedocs.io/en/latest/introduction.html>
  - 用途：适合作为扫描 PDF 的前置自动化 OCR 与文本层补全工具。
  - 边界：官方明确其演示性 Web front-end 不适合直接公开部署，也不以恶意 PDF 安全为目标，更说明它应被包在受控 worker/profile/runbook 里，而不是现场临时人工兜底。

## Verification

建议执行以下校验：

```powershell
Import-Csv tasks/backlog.csv | Where-Object { $_.id -in @('P001','P002','P003','P004','P005','P006') } | Select-Object id,acceptance,verification
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
rg -n "先机验|visual surrogate|代签|非现场客观检查|现场只" docs tasks
```

## Gate

- `build`: `gate_na`
- `test`: `gate_na`
- `contract/invariant`: 以 `tools/run-roadmap-guard.ps1` 和 CSV/Markdown 解析替代
- `hotspot`: 文档层热点已在本文件和 `docs/109` 留痕

## Risks

- 若未来把“视觉代理通过”误解为“教师已确认”，会重新放大对外口径风险。
- 若截图基线、artifact probe 和 route smoke 不持续刷新，会把旧证据误当成当前证据。
- 若现场链路没有严格保留数据授权、support owner 和 release sign-off，人类责任边界仍会失真。

## Rollback

```powershell
git restore -- docs/101_NonSiteCapabilityImplementationRoadmap.md docs/104_OpenQuestionsAndAssumptions.md docs/107_AITrustAndReviewContract.md docs/109_ReleaseGoNoGoCard.md docs/templates/p001-live-pilot-release-checklist.md docs/templates/p002-teacher-proxy-pilot-checklist.md docs/templates/p003-onsite-pilot-admission-checklist.md docs/templates/p004-onsite-pilot-round1-checklist.md docs/templates/p006-release-decision-checklist.md tasks/backlog.csv
Remove-Item -LiteralPath docs/evidence/20260606-onsite-human-reduction-and-ai-surrogate-boundary.md -Force
```
