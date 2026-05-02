# 19 · 路线图

路线图原则：先交付能跑、能验证、能恢复的教师最小纵切，再逐步扩展 AI、知识本体、组卷、导出和学情。不要按“先建完所有底层，再补所有界面”的横向方式推进。

## 总体判断

AI 推荐保留当前 P0-P6 大方向，但调整顺序和验收口径：

- P0/P1 是当前唯一编码焦点。
- P2-P6 只作为 v0.1 后续路线，不得提前实现。
- 每个阶段必须形成用户可验证闭环，不以“模型已建好”或“页面已画好”作为完成。
- 功能范围裁决以 `docs/28_FunctionScopeReview.md` 为准；新功能未通过准入卡前不得插入当前阶段。

## 阶段准入与退出

| 阶段 | 准入条件 | 退出条件 |
|---|---|---|
| P0 | `A000` 完成：版本、数据目录、Windows Service 约束、任务 lease/retry、文档门禁已锁定 | 上传 -> ImportJob -> FileAsset -> backup manifest 纵切通过 |
| P1 | P0 gate 全通过，至少有一份导入黄金样本 | 样例试卷进入确认队列，人工修正后保存题目并回看来源 |
| P2 | P1 题目来源链稳定 | 初中物理知识点可绑定题目，映射变更不破坏历史来源 |
| P3 | P1/P2 黄金样本、schema 和动态领域资产迁移契约稳定；正式生产标注仍需 C002 来源提炼与审核 | AI 输出结构化、可评测、可追踪成本、可人工接管；draft/test 模式不冒充生产事实 |
| P4 | 题库和 AI 标注质量足够支撑组卷 | 10 分钟内生成可打印 Word/PDF 初稿 |
| P5 | 试卷题号、知识点和导出结果稳定 | Excel 成绩导入后生成可讲评分析 |
| P6 | 数据、文件、配置、角色和备份路径稳定 | 管理员可低成本维护、恢复演练通过 |

## P0 · 工程骨架与最小上传纵切

目标：证明技术栈、数据路径、任务路径、文件路径和备份路径能在 Windows 本机/LAN 场景跑通。

交付：

- P0 准入预检：.NET/Node/Python/PostgreSQL 版本、数据目录、Windows Service/content root、BackgroundService job 约束、文档门禁。
- A000A 编码前契约收口：API/DB/状态机/威胁模型/备份 RPO-RTO/UX 状态、学生数据合规边界、外部 AI 传输边界和黄金样本脱敏策略。
- Monorepo 结构：`apps/api`、`apps/web`、`workers/document`、`tools`、`tests`。
- ASP.NET Core / .NET 10 API，可启动、健康检查、基础配置。
- React + TypeScript + Vite + Ant Design 前端，可打开教师首页骨架。
- PostgreSQL 连接、EF Core migrations、基础表：User、TeacherPreference、FileAsset、ImportJob、AIJob、ReviewQueueItem、BackupJob。
- FileStore：原始文件保存、hash、大小、mime、状态。
- Job Store：创建 ImportJob，状态流转，错误记录。
- Python Worker 占位：接收 job_id/file path，返回稳定 JSON。
- 基础备份脚本：pg_dump 占位、文件仓库 manifest、sha256。
- 初始 build/test/contract/hotspot gate。
- P0 证据包：命令、退出码、关键输出、manifest、gate_na 和回滚入口。

验收：

- 本机能打开 Web UI。
- 能上传一个测试文件并写入 `file_assets` 与 `import_jobs`。
- 能从 API 查询任务状态。
- 能生成包含数据库、文件仓库、配置占位的 backup manifest。
- `tasks/backlog.csv`、JSON schema、配置文件可被解析。

## P1 · 多模态试题入库最小闭环

目标：把 Word/PDF/图片试卷变成可人工确认、可保存、可回看来源的结构化题目。

交付：

- Docling/OpenXML/PaddleOCR Adapter 契约和占位实现。
- 页面预览与 `SourceRegion` 坐标模型。
- 题号锚点、题目边界、题干/选项/答案/解析的候选结构。
- 人工确认队列：合并、拆分、题图关联、标记答案/解析开始、跳过页、重跑。
- 人工接管路径：AI/OCR 失败后仍可框选、拆分、合并、跳过、重跑。
- `QuestionItem`、`QuestionBlock`、`QuestionAsset`、`SharedMaterial` 保存。
- 原始来源回看：文件、页码、区域截图、Adapter 诊断。
- 导入黄金样本目录和最小回归测试。

验收：

- 至少一份样例试卷可从上传进入确认队列。
- 教师可以修正候选切题结果并保存为题目。
- 保存后的题目能回看原始页码和区域。
- 失败路径不会丢原始文件，可转人工框选继续。
- 黄金样本至少覆盖共用题图、跨页题、公式密集、扫描版和答案解析分离。

## P2 · 初中物理知识本体闭环

目标：建立可版本化、可替换、可追溯的初中物理 L1-L3 知识体系，并把教材、课标、地区考点作为映射层。

交付：

- `KnowledgeNode`、`KnowledgeEdge`、`KnowledgeMapping` 模型。
- 初中物理 L1-L3 初始知识点。
- 公式、实验、方法、易错点字段。
- 教材章节、课标、地区考点映射。
- 版本快照与影响分析。
- draft -> formal 替换映射、自动迁移建议、人工审核和回滚报告。

验收：

- 题目可绑定主/副知识点。
- 映射和知识点版本变更不破坏历史题目来源、旧卷复现和学情解释。
- 组卷可基于 L2/L3 过滤。

## P3 · AI 入库与反馈闭环

目标：让 AI 承担批量结构化工作，让教师只处理异常。

交付：

- AI Provider 抽象与 Model Router。
- Structured Outputs schema 调用。
- 切题、题型识别、知识点标注、难度预估、答案校验。
- 成本日志、缓存、批处理。
- FeedbackEvent、Evals、prompt/schema 版本管理。

验收：

- 每个 AI 结果都有 prompt/schema/model/cost/confidence。
- 低置信度结果进入 ReviewQueue。
- 教师修改自动生成 FeedbackEvent。
- 黄金样本 eval 可复跑。

P3 不得用 draft bootstrap 知识点作为生产正式输入。若 C002 仍为 `暂缓`，D001-D003 可以在 draft/test 模式下实现 schema、接口、Evals、成本日志、prompt/schema 版本记录和人工审核链路；不得把真实模型输出标记为生产完成，不得自动写入正式 `active` 知识体系。

## P4 · 找题、组卷与导出闭环

目标：让教师 10 分钟内得到可打印试卷。

交付：

- 题库检索、筛选、题目卡片。
- 自然语言组卷解析，展示系统理解和细目表草稿。
- 题篮、试卷结构、一键换题、撤销。
- Word/PDF 导出 MVP。
- 导出前审校和导出黄金样本回归。

验收：

- 教师能从自然语言需求生成试卷初稿。
- 一键换题保持知识点、题型、难度、分值约束。
- Word/WPS 可打开，公式、题图、表格不丢失。

## P5 · 成绩导入与基础学情闭环

目标：把 Excel 成绩表转成可讲评、可补弱、可分层的分析结果。

交付：

- Student、ClassGroup、Exam、ScoreRecord、ItemScore。
- Excel 字段映射、预览、异常行提示、模板保存。
- 得分率、区分度、空白率、知识点掌握。
- 班级 Excel 分析、Word/PDF 摘要、A/B/C 分层练习建议。

验收：

- 常见 Excel 模板首次确认后可复用。
- 异常数据集中提示，不静默丢弃。
- 分析结果能导出并用于讲评。

## P6 · 校本协同、运维与恢复闭环

目标：让题库能被备课组和学校低成本长期维护。

交付：

- 教师账号、角色权限、操作审计。
- 个人/备课组/校本题库边界。
- 审核流、版本管理、标签治理。
- 自动备份、网络共享备份、缓存清理、存储看板。
- 恢复包、恢复演练、WinPE 应急脚本。

验收：

- 管理员能看到备份、存储、AI 成本和高风险操作。
- 备份包通过 manifest/hash 校验。
- 主程序不可用时仍能运行独立备份/恢复脚本。
