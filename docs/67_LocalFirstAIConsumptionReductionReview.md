# 67 · 本地优先 AI 消耗削减审查

## 1. 结论

在 C002N-C002Q 之前，必须先执行本地优先链路。真正需要外部 AI 的部分只应是少量语义判断、体系合并和高风险仲裁；格式、hash、抽取缓存、枚举、来源完整性、导入幂等、active guard、回滚证据、中文显示检查等都应由本地工具 100% 覆盖。

推荐分层：

```text
L0 本地确定性处理，不调用外部 AI
-> L1 低成本模型筛查，只处理异常和低置信度样本
-> L2 中等模型结构化提炼，只喂必要 chunk
-> L3 中强模型做体系合并、冲突判断和映射复核
-> L4 高风险强模型仲裁，只处理少量正式口径争议
-> 人工审核与 active guard
```

## 2. 可不用外部 AI 且应做好的环节

| 环节 | 本地方法 | 验收证据 |
| --- | --- | --- |
| 文件去重与来源稳定性 | sha256、文件大小、路径、`materialBatchKey`、SourceDocument 查询 | 33 个来源文件 hash 覆盖率 100% |
| 来源资料分类初筛 | 文件名规则、目录规则、年份正则、手工 metadata 修正 | `sourceType/region/year/materialBatchKey` 可复跑一致 |
| CSV/Excel 结构校验 | CSV parser、枚举表、必填字段、重复 ID、外键引用检查 | parser 100% 通过，失败行给中文原因 |
| JSON/YAML/schema 校验 | JSON parser、YAML parser、JSON Schema、fixture eval | `tools/run-gates.ps1` 文档配置门禁 |
| C002 candidate 导入幂等 | SQL upsert、import key、source hash、pending_review guard | 二次导入不新增重复资产 |
| active 禁止与激活前检查 | SQL count、状态机、review queue、migration pending 检查 | active=0，blocker 报告中文可读 |
| C002N chunk/cache | 本地文本抽取、页码、chunk hash、去重、cache idempotency | 同一输入 hash 不变时复用缓存 |
| 题号、页码、分值初检 | 正则、连续性检查、范围检查、人工快速修正 | 异常项进入确认队列 |
| UI 与输出中文化 | 中文 label map、中文错误原因、内部枚举不直接展示 | 本地 guard 检查关键可见英文枚举 |
| 成本预算 | token 估算、chunk 数、模型层级、fail closed 上限 | C002P budget guard |

这些环节如果先交给外部 AI，会增加成本且降低可复现性；应先用本地工具收敛输入，只把本地无法判定的语义冲突交给模型。

## 3. 仍适合外部 AI 的环节

| 环节 | 默认层级 | 输入约束 |
| --- | --- | --- |
| 候选知识点语义提炼 | L2 | 只发送必要 chunk、来源锚点和目标 schema |
| 课标/教材/考点之间的复杂映射 | L3 | 必须带 `source_id/page/evidence_excerpt/hash` |
| 一拆多、多合一、多对多映射判断 | L3 | 必须带迁移影响和回滚计划 |
| 正式激活前争议项复核 | L4 | 只处理少量高风险争议，不批量处理 |
| 长期学情口径或跨学科资产模型裁决 | L4 | 必须有 ADR、备选方案和 rollback |

外部 AI 输出只能进入 `candidate/pending_review/production_eligible=false`。模型不得直接写入 `active`，不得绕过人工审核、来源证据、迁移影响和回滚快照。

## 4. 中文输出要求

面向教师和普通操作者的界面、错误、报告摘要、导入结果和导出文件名应默认使用中文。内部字段、数据库枚举、API contract、`data-*` marker 和 schema 字段可以保留英文，但展示层必须映射为中文。

最低要求：

- UI 不直接展示 `queued/running/failed/retry_waiting`、`draft_test`、`single_choice`、`synthetic` 等内部枚举。
- 导入报告、候选审核报告和门禁失败原因应给中文摘要，同时保留英文机器字段。
- 文件输出优先使用中文标题或中文说明，例如“候选审核报告”“来源 chunk 缓存报告”。
- 外部 AI prompt 或 schema 可以用英文机器字段，但教师可见解释必须中文。

## 5. 对 C002N-C002Q 的约束

- C002N 只做 L0：本地抽取、hash、页码、块类型、去重、缓存和中文报告，不调用外部 AI。
- C002O 仍可不调用外部 AI：先做 schema、golden fixture、中文错误信息和 eval。
- C002P 不调用外部 AI：只检查模型路由配置、预算、reasoning 层级、cache 和 fail closed。
- C002Q 才允许小批量外部 AI dry-run，且必须先证明 C002N/O/P 通过。

`configs/model_routing.defaults.yaml` 必须显式声明 L0-L4 的默认模型、`reasoning_effort`、升级目标、dry-run token 上限、L4 数量上限、cache key 字段和 full extraction 的人工预算确认要求。该合同由 `tools/run-c002p-model-budget-guard.ps1` 检查，并纳入 `tools/run-gates.ps1`。

## 6. 当前建议

下一步直接做 C002N。不要等整个项目完全搭建完再做，因为 C002N 是降低 token 消耗的前置工程；但也不要越过 C002N/O/P 直接做 33 份 PDF 的全量模型提炼。
