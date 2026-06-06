# 108 · 标准互操作边界与最小 Profile Map

日期：2026-06-06。

## 1. 判断

AI 推荐：v0.1 继续坚持“只做 profile map，不做完整互操作实现”。标准名词只用于防止未来模型污染，不用于提前扩功能面。

## 2. v0.1 最小承诺

| 内部实体 | 对应标准 | v0.1 承诺 | 明确不承诺 |
|---|---|---|---|
| `QuestionItem` / `QuestionBlock` / `QuestionAsset` | QTI | 建立字段映射草表和导出占位边界 | 不做完整 QTI item/package 导入导出 |
| `Paper` / `PaperBasket` / `Blueprint` | QTI | 记录 test/section/item 级最小 profile map | 不做正式 QTI test assembly |
| `KnowledgeNode` / `KnowledgeMapping` | CASE | 记录 competency / association 级映射 | 不做完整 CASE framework 发布或同步 |
| `Student` / `ClassGroup` / `Assessment` / `ScoreRecord` | OneRoster | 记录 roster/result 级字段映射 | 不做 SIS 双向同步 |
| `AnalysisEvent` / 关键用户行为 | Caliper | 记录事件类型候选映射 | 不做完整事件流或实时上报 |

## 3. v0.1 非目标

- 不申请标准认证
- 不承诺第三方系统即插即用
- 不为标准兼容重构内部主模型
- 不在无真实需求时建立导入导出适配器
- 不处理真实校务系统同步

## 4. 允许启动真实 spike 的条件

只有同时满足以下条件，才允许从 profile map 进入真实互操作 spike：

1. `P006` 发布裁决已关闭。
2. 已有真实对接对象和授权样本。
3. 已指定 adapter owner。
4. 已有 dry-run preview。
5. 已完成隐私审查。
6. 已有 disable switch 和 rollback plan。

## 5. 对外表述规则

可以说：

- 系统已为 QTI / CASE / OneRoster / Caliper 预留最小映射边界。
- 后续可按真实需求扩展。

不能说：

- 已支持 QTI / CASE / OneRoster / Caliper。
- 可直接对接任意 LMS / SIS / 区域平台。

## 6. 与路线图的关系

- `R007` 和 `NS1203` 负责把这份边界变成 evidence。
- 没有真实需求前，任何互操作任务都只能停留在 profile map 或 ADR。
