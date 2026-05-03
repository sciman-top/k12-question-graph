# 19 · 路线图

路线图原则：先交付能跑、能验证、能恢复的教师最小纵切，再逐步扩展 AI、知识本体、组卷、导出和学情。不要按“先建完所有底层，再补所有界面”的横向方式推进；也不要因为知识点、标签、题型、难度、模板、评分规则、组织权限、隐私策略等动态元素尚未正式确定而停工。

## 总体判断

AI 推荐保留当前 P0-P6 大方向，但调整顺序和验收口径：

- P0/P1 已完成后，P2-P6 可以继续按 backlog 小步推进，先完成 draft/test 系统能力。
- 动态元素的正式数据、正式映射和生产激活可以后置；系统骨架、API/UI、schema、测试、门禁、导入/导出/分析流程不得因此搁置。
- 每个阶段必须形成用户可验证闭环，不以“模型已建好”或“页面已画好”作为完成。
- 功能范围裁决以 `docs/28_FunctionScopeReview.md` 为准；新功能未通过准入卡前不得插入当前阶段。

## 动态元素不停工原则

知识点只是动态元素之一。凡是允许未来变化的对象，包括题型、标签、难度/能力维度、rubric、组卷规则、导出模板、AI prompt/schema/model routing、文档解析 pipeline、分析指标、Excel 字段映射、隐私策略、学校组织和权限，都必须先抽象为可版本化、可映射、可迁移、可回滚资产。

这些对象没有正式版本时，任务仍按 `draft/test` 推进：

- 用 synthetic fixture、sample config、draft bootstrap 或少量临时原始资料完成 API/UI/worker/gate。
- 结果标记为 `draft`、`candidate`、`pending_review` 或 `productionEligible=false`。
- 验收写清楚“完成系统能力”，不写成“正式数据/正式口径已完成”。
- 正式资料录入后，通过 mapping、impact report、review workbench、rollback snapshot 更新已有系统。

只有这些动作必须等待正式资料或人工确认：`active` 生产激活、正式统计口径改写、真实学生数据处理、真实外部 AI 自动写入、影响历史学情或校级共享权限的批量迁移。

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

阶段准入不要求所有动态资产已正式 `active`。当正式资产缺失时，准入条件解释为“已有足够 draft/test fixture、sample config、schema 和 guard 支撑本阶段系统能力验证”；退出条件解释为“draft/test 系统能力通过 gate，生产激活仍由单独任务控制”。

来源资料采用双证据链：ChatGPT Web 或其他外部 AI 可以先把 PDF 提炼成结构化候选表，但这些结果只能导入为 `candidate/pending_review/productionEligible=false`；本项目必须同时通过来源资料工作台上传原始 PDF/docx/image，保存 `sha256/sourceType/region/year/page/question evidence` 后，才能核验、映射、影响评估并进入 `reviewed/active`。

截至 2026-05-03，`D:\CODE\k12-question-graph\广州中考` 已完成 C002J 真实来源资料导入：课程标准 1 份、教材 3 份、广州中考年报 10 份、广州中考真题/答案/解析 19 份，共 33 个 PDF，已进入 `SourceDocument/FileAsset` 证据层，真实 `material_batch_key` 为 `guangzhou_physics_2016_2025`。C002K 也已把 `c002-k12-question-graph-candidate-csvs\cleaned` 中的候选资产写入候选 DB：92 个 `candidate` 动态资产、55 条 `pending_review` 映射、1 个 `pending_review` migration 计划和 1 个审核队列项。正式 C002 仍不得标记为完成或 active，必须等人工审核、影响确认、回滚快照和 active guard 全部通过。

C002 的“正式完成”定义为：初中物理 L1-L3 知识体系 v1 已通过来源证据、人工审核、映射影响、回滚快照和 active guard，成为当前生产默认版本。它不表示永久冻结。后续教材、课标、考情或教师修正都应进入新的 `candidate` 版本，通过 `equivalent/split/merge/broader/narrower/renamed/deprecated` 映射、影响报告、审核和回滚快照后，再切换 active；旧 active 版本继续保留用于历史题目、旧卷复现、学情解释和回滚。

大模型提炼候选体系不得直接全量读取 33 个 PDF 后生成正式知识体系。执行顺序必须是 C002N0-C002Q：先完成本地优先 AI 消耗削减审查，再做本地 chunk/hash/cache，然后定义结构化 schema 和 eval，再配置分层模型路由预算门禁，最后只做小批量 AI extract dry-run。分层策略为 L0 本地抽取不调用模型，L1 低成本筛查用低 reasoning，L2 结构化初提炼用 medium reasoning，L3 体系合并/冲突判断用 medium/high reasoning，L4 高风险仲裁才允许强模型 high/extra high。所有输出必须保持 `candidate/pending_review/production_eligible=false`，并记录模型、reasoning、token、成本、缓存和来源证据。教师可见界面、报告摘要、导入/导出结果和失败原因默认中文；内部枚举、schema 字段和 API contract 可以保留英文但不得直接暴露给普通教师。

真实导入是中风险持久化动作，执行顺序固定为：确认 `git status`、设置正确 `PGPASSWORD/KQG_CONNECTION_STRING`、先运行 dry-run、执行备份或至少生成可恢复 manifest、再运行 `tools/import-c002-source-materials.ps1 -Apply`。若数据库密码缺失或不匹配，导入必须停在 dry-run 和任务更新层，不得绕过来源证据链直接导入候选知识点。

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
- 动态变化对象清单和映射基数合同，覆盖一对一、一对多、多对一、多对多。
- 真实来源资料导入证据层：教材、课程标准、当地真题、考情年报先进入 `SourceDocument/FileAsset`，候选表只能引用这些 hash 后继续。
- 候选数据自动导入：只写入 candidate/review queue/mapping/impact report，不写 active，不改变生产统计口径。

验收：

- 题目可绑定主/副知识点。
- 映射和知识点版本变更不破坏历史题目来源、旧卷复现和学情解释。
- 一对多、多对一、多对多映射必须生成迁移影响报告并进入人工审核，不能被静默当作普通一对一替换。
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

P3 不得用 draft bootstrap 知识点或其他 draft 动态资产作为生产正式输入。若 C002 或其他动态资产仍为 `暂缓`，D001-D010 仍可以在 draft/test 模式下实现 schema、接口、Evals、成本日志、prompt/schema 版本记录、人工审核和迁移建议；不得把真实模型输出标记为生产完成，不得自动写入正式 `active` 资产体系。

## P4 · 找题、组卷与导出闭环

目标：让教师 10 分钟内得到可打印试卷。

交付：

- 题库检索、筛选、题目卡片。
- 自然语言组卷解析，展示系统理解和细目表草稿。
- 题篮、试卷结构、一键换题、撤销。
- Word/PDF 导出 MVP。
- 导出前审校和导出黄金样本回归。

验收：

- 教师能从自然语言需求生成试卷初稿；正式知识点未激活时以 draft/test 约束验证流程。
- 一键换题保持知识点、题型、难度、分值约束；动态元素以后变更时通过映射和影响报告更新约束。
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
- 分析结果能导出并用于讲评；正式知识点/标签/能力维度未激活前只作为 draft/test 口径，不改写正式历史学情。

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
