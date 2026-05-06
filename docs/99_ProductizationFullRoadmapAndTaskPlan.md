# 99 · 产品化全程路线图、实施计划与任务清单

日期：2026-05-05。更新：2026-05-06，纳入 S001 完成态看板和 S0 子任务执行计划。

## 1. 结论

当前技术栈和工程终态不推翻。正确终态仍是：

```text
Windows/LAN first teacher workstation
-> ASP.NET Core modular monolith
-> PostgreSQL fact store + local file store
-> Python document/OCR/AI adapters through stable ports
-> React/Vite/Ant Design teacher workbench
-> versioned domain assets and review workflow
-> structured AI candidate outputs with cost/cache/eval/security gates
-> backup/restore/upgrade/install evidence before release
```

需要修正的是完成态口径和任务顺序。旧 A-R 路线已经建立了大量 schema、API、UI 合同、dry-run、synthetic fixture 和 preflight，但教师关心的真实闭环仍要通过新的 `S0 产品化闭环` 承接：

```text
真实导入 -> 解析/切题 -> 人工确认 -> AI 标注建议 -> 题目入库
-> 题库检索 -> 组卷 -> 导出 -> 成绩导入 -> 讲评分析 -> 备份恢复 -> 试点发布
```

## 2. 完成态分级

后续路线图和任务清单必须区分以下状态，不能再把 contract 完成直接写成生产可用：

| 状态 | 含义 | 可否支撑发布 |
|---|---|---|
| `contract_done` | schema、脚本、样例或 guard 通过 | 否 |
| `synthetic_done` | synthetic fixture 或 draft/test 数据可跑 | 否 |
| `db_backed_done` | 能真实读写 PostgreSQL/FileStore | 部分 |
| `ui_productized` | 教师 UI 接真实 API 并覆盖加载、空、错误、回退状态 | 部分 |
| `teacher_validated` | 教师或代理按真实材料完成验收并记录耗时、误差和接管点 | 是 |
| `release_ready` | 门禁、备份、恢复、隐私、权限、教师效率均通过 | 是 |

## 3. 全程路线图

| 阶段 | 目标 | 退出条件 |
|---|---|---|
| A-G 基础能力 | 工程骨架、上传、题目模型、动态资产、AI/组卷/成绩/备份合同 | 已完成，保留为底座 |
| H-O 强化能力 | 教师 shell、真实 adapter、C002 active、AI/组卷/成绩/部署合同 | 已完成大部分，但按 S001 只能视为底座，不能视为教师闭环 |
| S0 产品化闭环 | 把现有合同能力接成真实教师工作流 | S001-S012 全部完成，`P001` 才可进入 |
| P0-live 试点发布 | 真实隔离机、教师代理、现场试点、反馈回流、v0.1 裁决 | P001-P006 完成 |
| Q0 多学科扩展 | 第二学科资料、复核、active、差异和 UI 简化 | Q001-Q005 完成且不破坏四入口 |
| R0 长期平台演进 | 搜索、队列、互操作、高级分析、多校部署和技术债 | 以真实瓶颈和 ADR 触发 |

## 4. S0 实施计划

S0 是当前最重要的工程阶段。它不新增花哨功能，只把已经存在的合同、静态样例和 API 变成教师可连续使用的产品链路。

| ID | 任务 | 验收重点 |
|---|---|---|
| S001 | 完成态分级与看板 | backlog 和证据能区分 contract、synthetic、DB、UI、教师验证和 release |
| S002 | 教师工作流应用服务层 | 导入、切题、审核、标注、组卷、导出、成绩、分析有稳定 application service 或 workflow aggregate |
| S003 | 真实导入工作台 API/UI 接通 | 教师上传真实授权或脱敏材料后可看到任务、页、区块、异常和来源 |
| S004 | 文档解析质量基线 | docx、文本 PDF、扫描件、公式、表格、题图按 golden set 输出准确率、耗时和人工接管点 |
| S005 | 自动/半自动切题候选管线 | 生成切题候选、置信度、失败原因和 SourceRegion，不宣称全自动 |
| S006 | 人工确认与接管工作台产品化 | 合并、拆分、跳过、重跑、题图关联、撤销和保存题目形成闭环 |
| S007 | AI 标注建议审核队列 | AI 只生成候选知识点、题型、难度、答案校验建议，教师确认后才写入题目 |
| S008 | 题库生产检索与题卡 | 题库检索默认使用 C002 active，展示来源、版本、题图/公式/表格状态和授权边界 |
| S009 | 组卷持久化与题篮 | 自然语言理解、细目表、题篮、换题、撤销和版本引用可保存和复现 |
| S010 | 导出前审校与 Word/PDF 产品化 | 学生版、教师版、答案版导出前可审校，公式/题图/表格和来源授权不丢 |
| S011 | 成绩导入到讲评报告闭环 | Excel 模板复用、小题分映射、异常行、讲评报告和分层练习建议接真实 UI/API |
| S012 | 非现场端到端发布演练 | 使用授权或脱敏材料完成完整链路，记录耗时、失败、回滚和教师效率证据 |

## 5. 任务清单归宿

机器可读主清单仍是 `tasks/backlog.csv`。本轮新增 `S001-S012`，并让 `P001` 依赖 `S012`，避免在真实产品化闭环未完成时进入现场试点。

补充清单分三层：

- `tasks/productization-roadmap.csv`：S001-S012 主线产品化任务，记录目标完成态、依赖和触达模块。
- `tasks/productization-s0-execution-plan.csv`：S002-S012 的小步执行子任务，避免单个 S 任务过大而再次停留在合同层。
- `tasks/completion-state-dashboard.csv`：当前板块真实完成态，以它作为对外状态汇报和下一步排序依据。

`tasks/backlog.csv` 决定主线顺序；`tasks/productization-s0-execution-plan.csv` 决定每个 S 任务内部的实现顺序；`tasks/completion-state-dashboard.csv` 决定是否允许宣称某个板块可用。

## 6. 路线图持续优化机制

路线图不是一次性文件，后续每轮必须按以下机制更新：

1. 先运行或刷新完成态看板，确认哪些板块仍停留在 `contract_done`、`synthetic_done` 或 `db_backed_done`。
2. 每完成一个子任务，更新对应证据和必要的 `tasks/productization-s0-execution-plan.csv` 状态；只有父任务验收全部满足，才更新 `tasks/productization-roadmap.csv` 和 `tasks/backlog.csv`。
3. 如果发现某个任务仍过大，先拆分到 `tasks/productization-s0-execution-plan.csv`，不要直接扩大实现范围。
4. 如果真实实现发现路线顺序错误，先更新依赖和 guard，再编码；不要让聊天里的临时判断覆盖机器可读计划。
5. 对外汇报默认引用 `tasks/completion-state-dashboard.csv`，禁止只引用 backlog 的 `已完成`。

## 7. 当前执行波次

S0 当前采用 11 个执行波次：

| 波次 | 范围 | 目标 |
|---|---|---|
| W1 | S002A-S002F | 收束教师工作流 application service 边界 |
| W2 | S003A-S003D | 真实导入工作台 API/UI 接通 |
| W3 | S004A-S004C | 文档解析质量基线和代理验收 |
| W4 | S005A-S005C | 切题候选模型、服务和 UI |
| W5 | S006A-S006C | 审核队列、人工接管、题目保存闭环 |
| W6 | S007A-S007C | AI 标注建议从 schema 到教师确认写入 |
| W7 | S008A-S008B | 题库生产检索和题卡 UI |
| W8 | S009A-S009C | 题篮、细目表和组卷 UI 产品化 |
| W9 | S010A-S010B | 导出前审校和真实 artifact chain |
| W10 | S011A-S011C | 成绩导入、小题映射和讲评报告闭环 |
| W11 | S012A-S012C | 非现场 E2E、S0 release gate、P001 前置锁 |

## 8. 技术与架构优化边界

保留：

- ASP.NET Core modular monolith。
- PostgreSQL + EF Core migrations + local file store。
- Python adapter 通过稳定 JSON contract 隔离 Docling、PaddleOCR、OCRmyPDF、OpenXML 和后续模型工具。
- React + Vite + Ant Design 教师工作台。
- OpenAI structured outputs、evals、prompt caching、cost/cache logs、human-in-the-loop 和 no active write guard。

优化：

- 从 `Program.cs` 中逐步抽出 application services，endpoint 只做协议转换。
- 前端静态样例逐步替换为 typed API + TanStack Query server state。
- Adapter 从“能输出结构”升级为“质量可度量、失败可接管”。
- 组卷和成绩分析从 synthetic contract 升级为 DB-backed workflow。
- 标准互操作只做 profile map，不提前做完整 QTI/CASE/OneRoster/Caliper。

后置：

- 微服务、RabbitMQ/Kafka、Kubernetes、独立搜索引擎、图数据库、多校 SaaS。
- 完整 LMS、在线考试、在线监考、学生端、家长端。
- 自动主观题阅卷和复杂 IRT。

## 9. 验证策略

S0 每个任务都必须至少有：

- API 或 UI 的真实执行证据。
- `tools/run-gates.ps1` 或任务级 contract。
- `tools/run-roadmap-guard.ps1` 中的主线一致性检查。
- 证据文件，包含命令、关键输出、风险、回滚。
- 教师效率说明：减少哪一步，失败后如何继续，是否增加配置负担。

S0 结束时必须通过：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gates.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-roadmap-guard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-s001-completion-state-dashboard.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-s0-execution-plan-guard.ps1
```

## 10. 回滚

- 文档和任务清单回滚：`git restore -- docs/99_ProductizationFullRoadmapAndTaskPlan.md tasks/productization-roadmap.csv tasks/backlog.csv README.md`
- 代码实现阶段回滚：按每个 S 任务独立提交回滚。
- 数据与运行时回滚：继续使用 `D:\KQG_Backups` manifest、`tools/restore.ps1` 和对应 evidence 中的 restore 命令。

