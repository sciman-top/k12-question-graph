# 2026-05-28 非现场工作流闭环实跑报告

## 1. 结论

当前判断：非现场代理链路已经可以在本机用 synthetic/proxy 材料跑通录入、切题、人工接管、AI 标注候选写回与撤销、选题/组卷、导出、成绩导入、小题映射、讲评分析和备份恢复。它可以作为继续写代码和前置验收的主线，不应再因“现场人工未到位”而停住。

边界判断：本次仍不是现场教师验收，也不是授权校本材料的最终 `non_site_validated`。它证明的是 `runtime_verified` 级别的非现场代理闭环：真实 API、数据库、文件仓库、导出工件、成绩/分析服务和恢复脚本都被跑过，且不使用真实学生 PII。

## A. 执行摘要

| 项 | 结果 |
|---|---|
| 总控脚本 | `tools/run-s012b-non-site-e2e-rehearsal.ps1` |
| 本轮报告 | `docs/evidence/20260528-non-site-e2e-rehearsal-report.json` |
| 状态 | `pass` |
| 耗时 | `2.80` minutes |
| 生产资格 | `false` |
| 真实学生数据 | `false` |
| 预运行备份 | `tmp/s012b/pre-run-backup/20260528-222526/manifest.json` |
| 回滚入口 | `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/restore-backup.ps1 -ManifestPath 'tmp\s012b\pre-run-backup\20260528-222526\manifest.json'` |

## B. 流程覆盖

| 工作流 | 实跑步骤 | 状态 | 证据 |
|---|---|---|---|
| 场景包准入 | S012A fixture pack admission | pass | `docs/evidence/20260508-s012a-e2e-proxy-fixture-pack-report.json` |
| 试题录入/导入 | P1 import cut review save source proxy | pass | `docs/evidence/20260528-non-site-e2e-rehearsal-report.json` |
| 切题与来源回看 | P1 import cut review save source proxy | pass | `docs/evidence/20260528-non-site-e2e-rehearsal-report.json` |
| 人工接管 | S006B manual takeover workbench | pass | `docs/evidence/20260506-s006b-manual-takeover-smoke-report.json` |
| AI 标注候选与撤销 | S007C tagging writeback undo | pass | `docs/evidence/20260506-s007c-teacher-confirm-writeback-smoke-report.json` |
| 选题/组卷 | S009B blueprint review | pass | `docs/evidence/20260507-s009b-blueprint-review-workflow-smoke-report.json` |
| Word/PDF 导出 | S010B word pdf artifact chain | pass | `docs/evidence/20260508-s010b-word-pdf-artifact-chain-report.json` |
| 成绩导入 | S011A score import | pass | `docs/evidence/20260508-s011a-score-import-api-smoke-report.json` |
| 小题分映射 | S011B item score mapping preview | pass | `docs/evidence/20260508-s011b-item-score-mapping-ui-api-report.json` |
| 学情/讲评分析 | S011C commentary export | pass | `docs/evidence/20260508-s011c-commentary-report-export-report.json` |
| 备份恢复 | O003 backup restore drill | pass | `docs/evidence/20260509-s012b-o003-recovery-drill-report.json` |
| 视觉代理审查 | NS906 deterministic visual surrogate review | pass | `docs/evidence/20260528-ns906-visual-surrogate-review-report.json` |

## C. 数据变化

本轮实跑产生了 synthetic/proxy 数据增量，证明链路不是纯静态检查。

| 表 | before | after | delta |
|---|---:|---:|---:|
| `source_documents` | 1603 | 1604 | 1 |
| `question_items` | 4746 | 4764 | 18 |
| `knowledge_mappings` | 437 | 440 | 3 |
| `paper_baskets` | 410 | 412 | 2 |
| `paper_basket_items` | 1611 | 1620 | 9 |
| `assessments` | 460 | 463 | 3 |
| `score_records` | 920 | 926 | 6 |
| `item_scores` | 1884 | 1896 | 12 |

## D. 接管与回滚点

- 导入失败后保留原始上传和 adapter diagnostic。
- 切题异常可人工框选 SourceRegion、合并、拆分、跳过坏页并重跑 adapter。
- AI 标注只进入候选和审核链，教师确认后可撤销。
- 组卷由 blueprint review 先审查，再取题生成草稿题篮。
- 导出前 preflight 会阻断缺公式、题图、来源资产的风险。
- 成绩导入异常行集中提示，不接受真实学生 PII smoke。
- 讲评报告在小题映射不清时阻断，不静默生成正式学情。
- 数据层回滚可使用 pre-run backup manifest；临时 artifact 可清理 `tmp/s012b`、`tmp/o003`、`tmp/s010b-paper-artifacts`。

## E. AI 视觉替代现场的执行口径

用户判断是正确的：大量“人工现场”应前置为机器/AI 代理验证，而不是等待真实教师到场。本轮已经把人工目视环节拆成了可执行检查：

- 来源视觉：NS906 抽样读取 8 个广州 2015 SourceRegion screenshot，检查图片存在、尺寸、非空像素比例、bbox、题号和页码。
- 版面视觉：NS906 复用 REAL007，确认 `linkedSourceRegionCount=67`、第 1-24 题覆盖、缺图数 0、placeholder 截图数 0、版面噪声重叠数 0。
- 导出视觉：NS906 复核学生版、教师版、答案版 DOCX/PDF，检查 DOCX `word/document.xml`、题图媒体数量、PDF header/EOF 和既有 artifact manifest。
- 分析视觉：NS906 复核 REAL012 学情报告状态、知识点弱项数量、`allowAiDraftText=false`、`writesProductionHistory=false`，并保持 `real005ClosureStatus=not_closed`。

这些检查可以替代大部分“人工现场看一眼”的早期验证；只有真实教师偏好、学校隔离机、打印机、权限域、真实网络和最终发布裁决仍属于现场或授权环境问题。

## F. 状态推进

- `NS901` 推进到 `repo_landed`：场景包/代理路径已经在仓库中存在并可被 S012A/S012B 消费，但还不是授权材料最终包。
- `NS902` 推进到 `runtime_verified`：完整非现场代理链路已本机实跑通过。
- `NS906` 推进到 `runtime_verified`：视觉代理审查已实跑通过，可替代早期人工目检，但不替代现场教师验收。
- 不推进到 `non_site_validated`：缺授权/脱敏校本材料替换、真实教师代理记录和可选多模态 AI 样本审查准入。

## G. Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-s012b-non-site-e2e-rehearsal.ps1 -ReportPath docs/evidence/20260528-non-site-e2e-rehearsal-report.json
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-ns906-visual-surrogate-review.ps1
dotnet build apps/api/K12QuestionGraph.Api.csproj
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-non-site-implementation-plan-guard.ps1
```

注：`tools/run-gates.ps1` 会再次运行默认 S012B 报告路径 `docs/evidence/20260509-s012b-non-site-e2e-rehearsal-report.json`，用于证明 full gate 内的同链路可复跑；本报告引用的 `20260528` 路径保留为本轮非现场闭环专项证据。
