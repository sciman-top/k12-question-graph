# 2026-05-05 L003 AI Cut Candidate Pilot

## Scope
- L003 仅验证“AI 切题只产候选”边界，不做 active 写入。

## Boundary Checks
- 只产候选：所有切题结果保持 `candidate/pending_review`。
- 低置信度进入确认队列：不自动通过。
- 原文件可接管：失败或低置信度时可回到人工框选、拆分、合并路径。
- 未进入 active：不修改正式知识资产与生产口径。

## Evidence Anchor
- `docs/evidence/j006-import-accuracy-workload-report.json`
- `docs/evidence/20260505-l001-real-model-admission-card.md`

## Result
- 人工复核通过，允许进入下一步 L004/L005 试点约束验证。
