# 69 · C002O 候选提炼 schema/eval 证据

## 目标

C002O 定义大模型语义提炼的结构化输出边界，但本任务只做 schema 和 golden eval，不调用真实模型。它承接 C002N 的本地 chunk/hash/cache 证据，用小样本 fixture 验证后续模型输出必须保留来源锚点、人工审核边界和非生产状态。

## 入口

```powershell
.\tools\run-c002o-candidate-extraction-eval.ps1
```

该入口验证：

- `schemas/ai/c002_candidate_extraction.schema.json` 覆盖六类输出：`knowledge_points`、`curriculum_standard_items`、`textbook_chapters`、`exam_points`、`trend_summaries`、`mapping_suggestions`。
- `configs/ai-evals/c002o-candidate-extraction-evals.sample.json` 保持 `draft_test`、`allowRealModelCalls=false`、`productionEligible=false`。
- fixture 的每个候选对象都保持 `review_status=pending_review`。
- 所有 `source_anchor_refs` 都能回指 C002N 报告中的 `chunkHash`。

报告写入 `docs/evidence/c002o-candidate-extraction-eval-report.json`。

## 边界

- 不调用真实模型。
- 不导入候选 DB。
- 不激活正式 C002。
- 不把 C002N chunk 原文提交进 Git。
- C002P 负责预算、模型层级、reasoning 和 fail-closed；C002O 只负责结构化输出与 eval 边界。
