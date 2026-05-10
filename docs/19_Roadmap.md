# 19 · 路线图

路线图原则：先交付能跑、能验证、能恢复的教师最小纵切，再逐步扩展 AI、知识本体、组卷、导出和学情。不要按“先建完所有底层，再补所有界面”的横向方式推进；也不要因为知识点、标签、题型、难度、模板、评分规则、组织权限、隐私策略等动态元素尚未正式确定而停工。

## 总体判断

AI 推荐保留当前 P0-P6 大方向，但调整顺序和验收口径：

- P0/P1 已完成后，P2-P6 可以继续按 backlog 小步推进，先完成 draft/test 系统能力。
- 动态元素的正式数据、正式映射和生产激活可以后置；系统骨架、API/UI、schema、测试、门禁、导入/导出/分析流程不得因此搁置。
- 每个阶段必须形成用户可验证闭环，不以“模型已建好”或“页面已画好”作为完成。
- 功能范围裁决以 `docs/28_FunctionScopeReview.md` 为准；新功能未通过准入卡前不得插入当前阶段。
- 所有阶段执行 automation-first：先用规则、脚本、schema、SQL、hash/cache、Adapter、专用 API/UI、typed client、模板和 contract 覆盖确定性部分；AI/agent 只能作为语义候选、复杂映射、异常复核或外层编排，不得替代业务规则、来源证据、人工审核、回滚和正式写入守卫。

截至 2026-05-04，旧 A000-G004 backlog 已全部进入 `已完成`。下一步不再继续扩写旧 P0-P6，而是按 `docs/87_PhaseCloseoutAndFullRoadmap.md` 做 H0 阶段收口，并把 H001-R007 作为下一轮长期主线。近期执行范围只到 H/I/J：阶段证据刷新、教师工作流产品化、真实文档解析。K 以后必须等待前置证据通过后再进入。`docs/88_EngineeringEndStateExternalReview_20260504.md` 已把官方文档、成熟项目和最佳实践复核后的补强项纳入 backlog。

截至 2026-05-05，路线图执行顺序追加减法阻断：进入 L0 真实 AI、M0 生产组卷、N0 真实成绩、O0/P0-live 发布试点前，必须先完成并持续保持 `I010` 教师 shell 后台边界收口；进入 P0-live 前还必须完成 `O004B` 角色权限与审计日志剩余闭环。`O004` 仅表示 admin/internal 裸接口 fail-closed guard 已完成，不代表角色、审计和 UI 权限体系完成。

截至 2026-05-08，路线图新增横向 automation-first 阻断：所有未完成 backlog 任务和 S0 子任务必须在 `tasks/automation-first-contract.csv` 中声明确定性预检、专用功能面、AI/agent 允许范围、例外策略和 evidence 命令，并通过 `tools/run-automation-first-feature-contract-guard.ps1`。缺少该合同的任务不得继续推进到实现或发布试点。

截至 2026-05-10，路线图新增 `O008` 技术情报刷新与候选准入目录。新硬件、新 OCR/公式识别引擎、新本地推理 runtime 和新模型只能先进入可信来源清单、capability taxonomy、model/OCR candidate catalog 和 `report_only` evidence；AI API 只允许摘要公开资料、生成候选和 eval checklist，不得安装依赖、下载模型、切换默认路由、处理真实未脱敏材料或自动写入生产。

## 动态元素不停工原则

知识点只是动态元素之一。凡是允许未来变化的对象，包括题型、标签、难度/能力维度、rubric、组卷规则、导出模板、AI prompt/schema/model routing、文档解析 pipeline、分析指标、Excel 字段映射、隐私策略、学校组织和权限，都必须先抽象为可版本化、可映射、可迁移、可回滚资产。

这些对象没有正式版本时，任务仍按 `draft/test` 推进：

- 用 synthetic fixture、sample config、draft bootstrap 或少量临时原始资料完成 API/UI/worker/gate。
- 结果标记为 `draft`、`candidate`、`pending_review` 或 `productionEligible=false`。
- 验收写清楚“完成系统能力”，不写成“正式数据/正式口径已完成”。
- 正式资料录入后，通过 mapping、impact report、review workbench、rollback snapshot 更新已有系统。

只有这些动作必须等待正式资料或人工确认：`active` 生产激活、正式统计口径改写、真实学生数据处理、真实外部 AI 自动写入、影响历史学情或校级共享权限的批量迁移、下载本地模型权重、安装未知系统依赖、切换默认 OCR/AI 路由。

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

截至 2026-05-04，33 份广州物理原始 PDF 已迁入统一 Git 外目录 `D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025`，并已完成 C002J 真实来源资料导入：课程标准 1 份、教材 3 份、广州中考年报 10 份、广州中考真题/答案/解析 19 份，已进入 `SourceDocument/FileAsset` 证据层，真实 `material_batch_key` 为 `guangzhou_physics_2016_2025`。C002K 已从质量复核完成后的 C003 合并包导入候选 DB：452 个动态资产、400 条映射、1 个 migration 计划和 1 个审核队列项；source hash 对齐为 33/33，候选导入备份 manifest 为 `D:\KQG_Backups\20260504-013307\manifest.json`。C002M 已用生成决策将该批次推进到 `reviewed/approved/dry_run` 并关闭审核队列；C002T 已在激活前备份 `D:\KQG_Backups\20260504-015358\manifest.json` 校验后切换为 452 个 `active` 动态资产和 1 个 `applied` migration。正式 C002 已完成为当前生产默认 v1，但后续修改仍必须走新候选版本、映射、影响、审核、回滚和 active 切换。

C002 的“正式完成”定义为：初中物理 L1-L3 知识体系 v1 已通过来源证据、人工审核、映射影响、回滚快照和 active guard，成为当前生产默认版本。它不表示永久冻结。后续教材、课标、考情或教师修正都应进入新的 `candidate` 版本，通过 `equivalent/split/merge/broader/narrower/renamed/deprecated` 映射、影响报告、审核和回滚快照后，再切换 active；旧 active 版本继续保留用于历史题目、旧卷复现、学情解释和回滚。

C002R 已把上述“active 后仍可修订”落成 dry-run 合同：`configs/domain-assets/c002r-versioned-revision.sample.json` 和 `tools/run-c002r-versioned-revision-contract.ps1` 验证教师侧只提交简化修订信息，系统侧生成 candidate 版本、映射、影响报告、审核理由、rollback snapshot 和管理员 active 切换边界。当前完成的是合同和 gate，不表示已经发生新的生产修订。

为了降低教师使用门槛，C002U 已把后续新学科激活流程产品化为 Web 侧“学科激活工作台 v0”。该工作台只暴露资料批次、候选结果、教师复核、激活前检查、正式启用、证据和回滚摘要；普通教师不直接执行激活脚本，正式激活仍由管理员在备份、阻断项、复核结论和回滚说明齐备后执行。UI 合同由 `tools/run-subject-activation-workbench-ui-contract.ps1` 验证，并纳入 full gate。

C002 active 前必须先完成 C002S 正式化前审查闭环：抽样核对 2016-2025 每年 2-3 道题的原卷、答案、年报页码、考点、知识点、教材/课标映射；把 C003 研究包中 210 条年报页码/指标质量问题清零；再通过 candidate DB dry-run、备份 manifest、审核队列 readiness 和 active guard。当前 `tools/run-c002s-formalization-precheck.ps1` 已自动 overlay `quality-review-complete-csv-package` 并通过审查，报告为 `docs/evidence/c002s-formalization-precheck-report.json`，`sampleFailures=0`、`qualityIssuesOpenForProduction=0`、`productionActivationAllowed=true`。`docs/evidence/c002l-candidate-review-readiness-report.json` 当前显示 `formalActivationComplete=true`、hard blockers 为空；`docs/evidence/c002t-active-switch-report.json` 显示 active switch 已应用。

大模型提炼候选体系不得直接全量读取 33 个 PDF 后生成正式知识体系。执行顺序必须是 C002N0-C002Q：先完成本地优先 AI 消耗削减审查，再做本地 chunk/hash/cache，然后定义结构化 schema 和 eval，再配置分层模型路由预算门禁，再通过 C002Q0 检查真实模型调用 readiness 和 outer subagent 编排合同，最后只做小批量 AI extract dry-run。C002N 已完成本地证据层：`docs/evidence/c002n-source-chunk-cache-report.json` 覆盖 33 份来源 PDF、1478 页级 chunk、缓存复跑命中 33/33、外部 AI 调用 0。C002O 已完成结构化输出边界：`schemas/ai/c002_candidate_extraction.schema.json` 与 `docs/evidence/c002o-candidate-extraction-eval-report.json` 覆盖知识点、课标条目、教材章节、考点、趋势摘要和映射建议，全部保持 `pending_review/productionEligible=false`。C002P 已完成预算门禁：33 份来源 `estimatedInputTokens=520612`、`chunkCount=1478` 超过 C002Q dry-run 上限，full extraction 必须有显式预算报告和人工预算确认。C002Q0 已完成 readiness：`configs/ai-evals/c002q0-outer-ai-readiness.sample.json` 与 `docs/evidence/c002q0-outer-ai-readiness-report.json` 固化批次 manifest、模型角色、reasoning、预算、sample rate、输入/输出 artifact、evidence anchor、cache hit、no active write、人工审核和 subagent 外层编排边界，且证明 readiness 本身外部 AI 调用为 0、项目运行时真实模型调用仍禁用、subagent 不成为运行时依赖。C002Q 已完成 contract dry-run：`configs/ai-evals/c002q-ai-extract-dry-run.sample.json` 与 `docs/evidence/c002q-ai-extract-dry-run-report.json` 抽样课程标准、教材、年报、真题 4 类来源共 12 个 cache-hit chunks，生成候选输出、模型层级 trace、token/cost/cache 证据，保持 `allowRealModelCalls=false/externalAiCalls=0/noActiveWrite=true`，不覆盖 C002K。分层策略为 L0 本地抽取不调用模型，L1 低成本筛查用低 reasoning，L2 结构化初提炼用 medium reasoning，L3 体系合并/冲突判断用 medium/high reasoning，L4 高风险仲裁才允许强模型 high/extra high。所有输出必须保持 `candidate/pending_review/production_eligible=false`，并记录模型、reasoning、token、成本、缓存和来源证据。subagent 只作为外层并行执行和复核编排，不成为项目运行时依赖。教师可见界面、报告摘要、导入/导出结果和失败原因默认中文；内部枚举、schema 字段和 API contract 可以保留英文但不得直接暴露给普通教师。

真实导入是中风险持久化动作，执行顺序固定为：确认 `git status`、设置正确 `PGPASSWORD/KQG_CONNECTION_STRING`、先运行 dry-run、执行备份或至少生成可恢复 manifest、再运行 `tools/import-c002-source-materials.ps1 -Apply`。若数据库密码缺失或不匹配，导入必须停在 dry-run 和任务更新层，不得绕过来源证据链直接导入候选知识点。

P5 已在 draft/test 模式完成 F001-F003：学生/班级/考试模型、synthetic Excel 字段映射导入、得分率、区分度和知识点掌握摘要均已通过合同门禁。当前 F003 只写 `docs/evidence/f003-knowledge-mastery-analysis-report.json` 和临时 summary，不写正式历史学情，不使用真实学生数据。

P6 已开始进入运维闭环。G001 已完成 draft/test 备份共享演练：`tools/run-g001-backup-share-contract.ps1` 在不启动 Web/API 主程序的情况下生成本机备份、复制到可配置共享目录，并分别通过 manifest/hash 校验；当前共享目录用 `tmp/g001-backups/shared` 模拟，真实 LAN 共享路径由配置和管理员部署时提供。

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

- Docling/OpenXML/PaddleOCR Adapter 契约和占位实现；后续真实质量基线按 OpenXML/OMML、PDF text/layout、Docling、PaddleOCR PP-OCRv5/PP-StructureV3、PaddleOCR FormulaRecognition/PP-FormulaNet、云端可选兜底的顺序推进。
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
- 黄金样本至少覆盖共用题图、跨页题、公式密集、扫描版和答案解析分离，并分别记录 docx 原生公式、文本 PDF、扫描 OCR、图片公式和云端兜底是否触发。

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

P3 不得用 draft bootstrap 知识点或其他 draft 动态资产作为生产正式输入。旧 `D004-D010` 不再作为独立路线图任务推进；相关能力已拆到 `D001-D003` 的合同层和 `L001-L007` 的真实 AI 准入/试点层。不得把真实模型输出标记为生产完成，不得自动写入正式 `active` 资产体系。

## P4 · 找题、组卷与导出闭环

目标：让教师 10 分钟内得到可打印试卷。

交付：

- 题库检索、筛选、题目卡片。
- 自然语言组卷解析，展示系统理解和细目表草稿。
- 题篮、试卷结构、一键换题、撤销；当前 E003 已完成 draft/test 换题与 undo 合同。
- Word/PDF 导出 MVP；当前 E004 已完成 draft/test 导出工件和公式/题图/表格校验合同。
- 导出前审校和导出黄金样本回归。

验收：

- 教师能从自然语言需求生成试卷初稿；正式知识点未激活时以 draft/test 约束验证流程。
- 一键换题保持知识点、题型、难度、分值约束；动态元素以后变更时通过映射和影响报告更新约束。
- Word/PDF 工件可生成并校验，公式、题图、表格不丢失；正式试卷语义仍等待 C002 active。

## P5 · 成绩导入与基础学情闭环

目标：把 Excel 成绩表转成可讲评、可补弱、可分层的分析结果。

交付：

- Student、ClassGroup、Assessment、ScoreRecord、ItemScore；当前 F001 已完成 draft/test 学生、班级、考试和报名基础模型。
- Excel 字段映射、预览、异常行提示、模板保存；当前 F002 已完成 synthetic Excel 字段映射导入合同。
- 得分率、区分度、空白率、知识点掌握。
- 班级 Excel 分析、Word/PDF 摘要、A/B/C 分层练习建议。

验收：

- 常见 Excel 模板首次确认后可复用。
- 异常数据集中提示，不静默丢弃。
- 分析结果能导出并用于讲评；正式知识点/标签/能力维度未激活前只作为 draft/test 口径，不改写正式历史学情。
- F001 基础模型只使用 synthetic fixture，不使用真实学生数据，不暴露学生端。
- F002 只导入 synthetic Excel fixture，异常行集中提示，字段映射模板可复用且可迁移。

## P6 · 校本协同、运维与恢复闭环

目标：让题库能被备课组和学校低成本长期维护。

交付：

- 教师账号、角色权限、操作审计。
- 个人/备课组/校本题库边界。
- 审核流、版本管理、标签治理。
- 自动备份、网络共享备份、缓存清理、存储看板。
- 恢复包、恢复演练、WinPE 应急脚本。
- 安装器或初始化向导必须配置 PostgreSQL 非交互凭据存储，优先使用 `%APPDATA%\postgresql\pgpass.conf` 或等价安全凭据机制；不得依赖 Codex、安装器或桌面进程自然继承 User 级 `PGPASSWORD`。

验收：

- 管理员能看到备份、存储、AI 成本和高风险操作。
- 备份包通过 manifest/hash 校验。
- 主程序不可用时仍能运行独立备份/恢复脚本。
- 新电脑安装 dry-run 必须在清除当前进程 `PGPASSWORD` 后通过 `psql -w` 连接验证，并检查凭据文件 ACL、回滚和修复报告。
- 当前 G001-G004 已完成 draft/test 合同：备份到本机/共享目录、管理员存储看板/缓存清理、WinPE 应急拷贝脚本生成和 PostgreSQL pgpass 非交互凭据 dry-run 均已纳入 unified gate；缓存清理只作用于配置化 cache root，WinPE 脚本只做 copy-only 拷贝，G004 只使用临时 `APPDATA` 验证 `psql -w`，不删除文件仓库、备份包、学生成绩、正式资产或目标介质既有内容，也不修改真实用户 pgpass。
