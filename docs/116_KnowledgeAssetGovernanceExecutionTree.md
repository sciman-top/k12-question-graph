# 116 · 知识资产治理细化执行树

日期：2026-06-15。

## 1. 用途

本文件只做人类执行导航，不新增新的顶层 CSV 主线。

它的目标是把已有任务之间的关系讲清楚：

- `C002B / C002C / C002D`
- `C002S / C002T`
- `K001 / K006`
- `R007`

重点不是“再造一条知识资产主线”，而是把现有主线按治理动作分层，避免后续执行时把来源准入、迁移影响、审核激活、查询接入、健康巡检和互操作承诺混在一起。

## 2. 六类治理动作

### A. 来源变更准入

对应任务：

- `C002D`
- 相关来源资料导入与证据层任务，如 `C002J`

它回答：

- 教材 / 课标 / 真题 / 年报等来源更新后，什么条件下只能进 `candidate`
- 什么来源证据、hash、页码和授权边界是最低要求
- 哪些来源更新绝不能直接写 `active`

这层产物是：

- `candidate` 资产
- `source_evidence`
- admission report

### B. 替换映射与迁移计划

对应任务：

- `C002B`

它回答：

- 一对一、一对多、多对一、多对多映射如何表达
- 哪些变更可以自动应用
- 哪些变更必须保留 `pending_review`

这层产物是：

- replacement mapping
- mapping cardinality
- confidence / review status

### C. 影响报告

对应任务：

- `C002C`

它回答：

- 映射变化会影响哪些面：题库检索、组卷约束、导出模板、学情分析、fixture、历史冻结结果
- 哪些影响可自动回写
- 哪些影响必须人工确认

这层产物是：

- migration report
- auto-applied set
- pending-review set
- rollback snapshot requirement

### D. 审核清零与 `reviewed -> active`

对应任务：

- `C002S`
- `C002T`

它回答：

- 哪些 blocker 必须先清零才能 formalize
- 哪些 candidate/import/review blocker 会阻止 active switch
- `reviewed -> active` 需要哪些 backup、snapshot、guard 和 rollback

这层产物是：

- formalization precheck
- active switch report
- reviewed/active version transition

### E. 查询接入与历史稳定性

对应任务：

- `K001`

它回答：

- 检索、组卷、学情默认读取哪一个 active 版本
- 如何保留版本引用，避免历史题单、导出和分析被新版本静默污染
- 为什么查询接入不是 active 切换本身

这层产物是：

- active query contract
- version reference stability

### F. 健康巡检与日常治理

对应任务：

- `K006`

它回答：

- 管理员日常应该看哪些字段：active、candidate、pending mappings、pending migrations、blockers、evidence 摘要
- 哪些异常意味着“不能继续 formalize”
- 哪些异常只是“待处理但不影响当前 active”

这层产物是：

- governance dashboard
- operator triage surface

## 3. 推荐执行顺序

### 变更来自新来源时

1. 先做来源准入：`C002D`
2. 再做替换映射：`C002B`
3. 再做影响报告：`C002C`
4. 再做 formalization precheck：`C002S`
5. 最后才允许 active switch：`C002T`
6. active 生效后验证查询接入：`K001`
7. 日常持续看健康：`K006`

### 变更来自治理规则或人工审查时

1. 如果不改来源，只更新映射和影响报告：从 `C002B / C002C` 开始
2. 如果改 active 边界：必须回到 `C002S / C002T`
3. 如果只是查询或解释口径漂移：先看 `K001 / K006`

### 变更来自互操作诉求时

1. 先确认不改变内部 canonical model
2. 先看 [docs/108_InteroperabilityProfileBoundary.md](/D:/CODE/k12-question-graph/docs/108_InteroperabilityProfileBoundary.md:1)
3. 再进入 `R007`
4. `R007` 只做 profile map，不反向改写知识资产主模型

## 4. 常见误区

### 误区 1：来源导入完成 = 可切 active

不是。来源导入只解决“能否进入 candidate”，不解决“是否已 formalize、reviewed、可切 active”。

### 误区 2：映射做完 = 历史稳定

不是。映射只是计划，历史稳定要看 `C002C` 的影响报告、`C002T` 的受控切换和 `K001` 的查询引用验证。

### 误区 3：健康面板 = 可以代替治理流程

不是。`K006` 只是巡检与 triage 入口，不能替代 `C002B/C/C/D/S/T` 的治理链。

### 误区 4：互操作 profile map 可以倒逼内部主模型

不允许。`R007` 只表达外部标准映射，不允许为了标准方便而反向污染内部 canonical model。

## 5. 与现有文档的关系

- 稳定模型定义：看 [docs/05_DomainModel.md](/D:/CODE/k12-question-graph/docs/05_DomainModel.md:1)
- 互操作承诺边界：看 [docs/108_InteroperabilityProfileBoundary.md](/D:/CODE/k12-question-graph/docs/108_InteroperabilityProfileBoundary.md:1)
- 任务真源：看 `tasks/backlog.csv`
- 当前执行主线：看 [docs/103_ExecutionControlBoard.md](/D:/CODE/k12-question-graph/docs/103_ExecutionControlBoard.md:1)

本文件只负责把知识资产治理动作拆得更像“可执行工作流”，不新增新的顶层里程碑。
