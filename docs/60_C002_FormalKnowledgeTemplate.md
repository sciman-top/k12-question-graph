# 60 · C002 Formal Knowledge Template

## 1. 目的

`configs/knowledge/c002-formal-knowledge-template.csv` 是正式 C002 来源提炼的录入模板。它不是正式知识点结果，也不会把任何候选节点标记为 `active`。

模板用于教师或备课组把教材、课程标准、近年当地考试资料中的候选 L1-L3 知识点整理为 `source-derived candidate`，再交给映射 dry-run、影响报告和人工审核工作台处理。

## 2. 文件位置

可提交的空模板：

```text
configs/knowledge/c002-formal-knowledge-template.csv
```

真实填写版应另存到数据目录或本地忽略文件，例如：

```text
D:\KQG_Data\source_materials\staging\c002-formal-knowledge.local.csv
```

不要把真实教材原文、真题原件、未授权内容或学生信息提交到 Git。

## 3. 字段口径

- `stable_id`: 来源提炼候选节点的稳定 ID，不随标题小改而变化。
- `parent_stable_id`: 上级候选节点 ID；L1 留空，L2 指向 L1，L3 指向 L2。
- `level`: 只允许 `1`、`2`、`3`。
- `title`: 候选知识点标题。
- `node_type`: `module`、`topic`、`concept`、`method`、`experiment` 或后续扩展类型。
- `source_material_ids`: 对应 `source-material-manifest.local.json` 中的资料 ID，可用分号分隔多个来源。
- `evidence_locations`: 页码、章节、题号或条目编号；不复制长篇原文。
- `draft_mapping_code`: 当前 draft bootstrap 节点 code；未知可留空进入人工审核。
- `mapping_type`: `equivalent`、`renamed`、`split`、`merge`、`broader`、`narrower` 或 `deprecated`。
- `mapping_confidence`: `0.00-1.00`；低置信度必须人工审核。
- `review_status`: 初始为 `pending_review`。
- `production_eligible`: 初始必须为 `false`。

## 4. 审核边界

一对一、高置信度、低影响且可回滚的映射可以由规则或 AI 自动建议，但正式激活仍需要通过 C002D/C002E guard。以下情况必须人工确认：

- 一拆多、多合一或多对多映射。
- 影响题目绑定、组卷约束、导出模板或历史学情口径。
- 来源证据不足、授权状态不清或含未脱敏 PII。
- `mapping_confidence < 0.85`。

## 5. 后续归宿

模板填写后进入以下链路：

```text
source material manifest
-> formal knowledge local CSV
-> source-derived candidate dry-run
-> draft/formal mapping plan
-> migration impact report
-> mapping review workbench
-> activation guard
```

C002 正式完成前，系统继续使用 draft/test 动态资产推进 API、UI、组卷、导出和学情链路。
