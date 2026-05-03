# 20 · 任务拆解

本文件给出人工可读任务拆解；机器可导入版见 `tasks/backlog.csv`。任务拆解遵循“小步闭环”：每个任务必须有验收标准和验证方式，不允许只写“建立某模块”。

动态元素不停工口径：知识点、标签、题型、难度、能力维度、评分规则、组卷规则、导出模板、Excel 字段映射、AI prompt/schema/model routing、分析指标、组织权限和隐私策略都可能变化，但这不能阻断系统搭建。相关任务应先完成 `draft/test` 系统能力和 gate，使用 synthetic fixture、draft bootstrap、sample config 或少量临时资料；正式资料录入后再通过映射、替换、迁移影响报告、人工审核和回滚快照更新。只有生产 `active` 激活、正式统计口径、真实学生数据和真实外部 AI 自动写入必须等待正式资料和人工确认。

## A · P0 工程骨架与最小上传纵切

### A000 P0 准入预检与决策锁定

验收：

- 记录 .NET SDK/runtime、Node、Python、PostgreSQL 版本与安装来源。
- 确认程序目录、数据目录、备份目录、日志目录不混用。
- 确认 Windows Service 发布时不依赖当前工作目录。
- 确认 BackgroundService job table 必含 lease/retry/idempotency 字段。
- 文档/schema/config/CSV 解析门禁可执行或按 `gate_na` 留痕。

验证：

- `dotnet --info`
- `node --version`
- `python --version`
- PostgreSQL version query
- 文档门禁命令

### A000A P0 编码前契约收口

验收：

- API P0 DTO、错误码、幂等、分页和 OpenAPI snapshot 规则已写入文档。
- 数据库 P0 constraints、indexes、status transition、soft delete 和 seed 策略已写入文档。
- P0/P1 threat model、备份 RPO/RTO、UX 状态清单和黄金样本目录规则已写入文档。
- 学生数据/合规辖区、外部 AI 数据传输边界、fixture 合成/匿名化策略和题库来源版权记录规则已写入文档。
- `locked_by`/`locked_until` 命名在架构、ADR 和数据库文档中一致。

验证：

- 文档一致性检索。
- 敏感信息边界检索。
- CSV/JSON/YAML 解析门禁。

### A001 创建 monorepo 目录结构

验收：

- `apps/api`、`apps/web`、`workers/document`、`tools`、`tests` 存在。
- README 指向真实启动入口。

验证：

- `rg --files`

### A002 建立 ASP.NET Core API 项目

验收：

- API 可启动。
- `/health` 返回正常。
- 配置区分程序目录和数据目录。

验证：

- `dotnet build`
- API 健康检查请求。

### A003 建立 React + TypeScript + Vite + Ant Design 前端

验收：

- Web UI 可启动。
- 首页只显示普通教师 4 个入口。
- 高级入口折叠或隐藏。

验证：

- `npm run build`
- 浏览器打开本机页面。

### A004 建立 PostgreSQL 与 EF Core migrations

验收：

- 能连接 PostgreSQL。
- 初始 migration 包含 User、TeacherPreference、FileAsset、ImportJob、AIJob、ReviewQueueItem、BackupJob。

验证：

- `dotnet ef database update`
- migration smoke test。

### A005 实现 FileStore 与 FileAsset 模型

验收：

- 上传文件进入 `D:\KQG_Data\file_store\original\` 或配置的数据目录。
- 数据库只保存路径、hash、大小、mime、状态，不保存大文件内容。

验证：

- 上传测试文件。
- 查询 `file_assets`。

### A006 实现 ImportJob 状态机

验收：

- 上传后自动创建 ImportJob。
- 状态至少支持 queued/running/succeeded/failed/cancelled/retry_waiting。
- 错误、attempt_count、idempotency_key 可记录。

验证：

- API 创建并查询 ImportJob。
- 单元测试覆盖合法/非法状态转换。

### A007 建立 Python Worker 调用协议

验收：

- API 能用 job_id 和 file path 调用 worker 占位。
- Worker 返回稳定 JSON，含 diagnostics。
- Worker 失败不会丢失 ImportJob 和 FileAsset。

验证：

- worker 占位命令 smoke test。
- API 集成测试。

### A008 建立日志、配置、健康检查

验收：

- 配置能指定数据目录、数据库连接、文件仓库、日志目录。
- 健康检查覆盖 API、数据库、文件仓库、worker 占位。

验证：

- `/health`。
- 配置缺失/目录不可写测试。

### A009 建立基础备份脚本与 manifest

验收：

- 能生成 backup manifest。
- manifest 包含数据库备份占位、文件仓库清单、配置、sha256。
- 校验失败不得报告成功。

验证：

- `tools/backup.ps1`
- `tools/verify-backup.ps1`

### A010 建立测试框架与门禁入口

验收：

- 后端、前端、worker 至少各有 smoke test。
- 建立统一 gate 命令。
- 文档/schema/config CSV 可解析检查纳入门禁。

验证：

- `tools/run-gates.ps1`

### A011 建立 P0 证据包与回滚入口

验收：

- `docs/evidence/` 或等价证据目录记录 P0 gate 命令、退出码、关键输出和 gate_na。
- README 指向真实启动、门禁和回滚入口。
- P0 任一失败可定位到配置、数据库、文件仓库、worker 或备份脚本。

验证：

- `tools/run-gates.ps1`
- 证据目录检查

## B · P1 多模态试题入库最小闭环

### B001 文件上传、hash 去重、文件元数据入库

验收：

- 相同文件重复上传可识别。
- 重复上传不复制大文件。
- SourceDocument 记录来源类型、授权/传播限制、是否含学生 PII 和脱敏状态。

验证：

- 上传同一文件两次。
- 查询 SourceDocument 来源与隐私字段。

### B002 Docling/OpenXML/PaddleOCR Adapter 草案

验收：

- Adapter 接口返回 DocumentModel、PageModel、LayoutBlock、AdapterDiagnostic。
- 工具版本、输入 hash、输出 hash、耗时和警告可记录。

验证：

- Adapter contract test。

### B003 页面预览与 SourceRegion 坐标模型

验收：

- 页面预览能显示页码。
- SourceRegion 保存页码、bbox、截图路径、坐标单位。

验证：

- 样例文档预览。

### B004 人工切题/合并/拆分/题图关联界面

验收：

- 教师可合并跨页题、拆分误切题、关联共用题图。
- 所有操作可撤销或生成修订记录。

验证：

- UI 流程测试。

### B004A 人工接管失败路径

验收：

- AI/OCR/Adapter 失败后，教师仍可进入人工框选/拆分/合并/跳过/重跑路径。
- 原始文件、失败原因、stderr/stdout 摘要、AdapterDiagnostic 不丢失。
- 人工接管后的题目仍能回看 SourceRegion。

验证：

- 失败样本导入测试。
- 人工接管 UI 流程测试。

### B005 QuestionItem/QuestionBlock/Asset 保存

验收：

- 题干、选项、小问、答案、解析、图片、公式、表格可结构化保存。
- 题目可回看 SourceRegion。

验证：

- 保存题目后查询 API。

### B006 原始来源回看

验收：

- 题目详情能打开来源文件页码和区域截图。
- 原始文件丢失或截图缺失时有明确错误。

验证：

- 页面级手动验收和 API 测试。

### B007 导入黄金样本与回归测试

验收：

- 至少包含共用题图、跨页题、公式密集、扫描版、答案解析分离样本。
- 修改导入流程后可复跑。

验证：

- `tools/run-import-golden.ps1`

### B008 P1 非现场流程验收

验收：

- 代理场景能完成“上传 -> 预览 -> 修正异常 -> 保存题目 -> 回看来源”。
- 记录确认项数量、失败接管步骤和估算总耗时。
- 验收报告明确哪些仍是 stub，哪些是真实可运行能力。
- 不要求真实教师现场验收。

验证：

- P1 proxy scenario walkthrough。
- `tools/run-import-golden.ps1`

## C · P2 知识本体

- C001 KnowledgeNode/Edge/Mapping 模型。已完成：核心表、版本字段、QuestionItem 主知识点 FK、schema contract gate。
- C002 初中物理 L1-L3 知识点初始化。分为 draft/test 与 formal/production 两层：当前非权威 draft bootstrap 可用于测试绑定、筛选、组卷约束和映射历史验证；正式知识点必须在教师录入各版本教材、学科课程标准、近年当地中考/高考真题等资料后，从来源提炼并审核。来源资料准入见 `docs/50_C002_SourceMaterialAdmission.md`。
- C002A 动态领域资产契约。已完成：`DomainAssetVersion`、`DomainAssetMapping`、`DomainAssetMigration` 已落库，支持 version/status/source/mapping/migration/rollback、dry-run 自动建议与人工审核状态，并纳入 `tools/run-c002a-domain-asset-contract.ps1`。
- C002B draft -> formal 替换映射。已完成 dry-run contract：支持等价、拆分、合并、上位、下位、废弃、重命名；高置信度、低影响、可回滚的一对一映射进入 `auto_applied`，其余进入 `pending_review`，由 `tools/run-c002b-replacement-mapping-contract.ps1` 验证。
- C002C 标签/标注/索引迁移。已完成 dry-run contract：题目主知识点、副知识点、标签、搜索索引、组卷约束、学情指标和回归 fixture 可生成迁移影响报告；自动更新、人工审核和历史学情冻结由 `tools/run-c002c-migration-impact-contract.ps1` 验证。
- C002D source-derived candidate admission。已完成 dry-run contract：候选正式知识资产必须引用已准入教材、课程标准、当地考试资料，保持 `candidate/pending_review`，禁止直接 `active`，并接入 C002B/C002C 替换和影响计划。
- C002E source-derived active activation guard。已完成 dry-run contract：候选资产进入 `active` 前必须无待审候选、无 `pending_review` 映射、无待审影响项、历史学情冻结已确认且有回滚快照。
- C002 dry-run suite。已完成：`tools/run-c002-dry-run-suite.ps1` 可在无数据库密码时一键验证 source admission、replacement mapping、migration impact、candidate admission 和 activation guard；full gate 仍保留数据库 contract。
- C002G 动态变化对象清单与映射基数。已完成文档合同：明确知识点、教材/课标/考点、题型、标签、rubric、组卷规则、AI prompt/schema/model routing、解析 pipeline、分析指标、导出模板、Excel 映射、组织权限和隐私策略都必须动态化；映射必须兼容一对一、一对多、多对一和多对多，多对多用同一 migration/plan 下的多条 mapping 边表达并进入人工审核。
- C002H 映射审核工作台预处理。已完成 dry-run contract：定义 pending review 队列、筛选、排序、旧/新对象并排视图、映射边、来源证据、影响预览、回滚预览、审核历史、快捷操作、批量确认边界、迁移组和 audit snapshot，后续 UI/API 必须按该合同实现。
- C003 公式、实验、方法、易错点。
- C004 教材章节映射。
- C005 地区考点映射。
- C006 AI 映射建议。
- C007 审核与版本快照。

P2 任务在 P1 验收前不得实现，只能保留模型预留和文档准备。

## D · P3 AI 流水线

- D001 AI Provider 抽象与 ModelRouter。已完成 draft/test 合同：依赖 C002H 动态资产审核边界，而不是依赖正式 C002 active；`AllowRealModelCalls=false`，LLM 任务只路由到 `stub_llm`，保留 prompt/schema/model routing 版本、成本档位、人工审核和 production guard，不把 draft 知识点或真实模型输出标记为生产完成。
- D002 AIJob/AIResult 成本日志。已完成 draft/test 合同：`AIJob` 记录 provider、model、routing version、prompt version、schema version、input hash、tokens、cached tokens、cost、latency、confidence、review status 和 teacher modified；stub LLM 写入 `pending_review`，不调用真实模型。
- D003 Structured Outputs 与 Evals。已完成 draft/test 合同：`tools/run-d003-structured-output-eval.ps1` 用 golden smoke fixture 校验知识点映射、切题、答案校验和自然语言组卷意图解析 schema；所有 fixture 保持 `pending_review`、不接真实模型、不具备生产资格。
- D004 AI 切题。
- D005 知识点标注。
- D006 自然语言组卷意图解析。
- D007 答案校验。
- D008 成本统计与缓存。
- D009 FeedbackEvent。
- D010 AI Evals。

P3 任务在 P1 验收前不得实现真实模型调用，可先保留 schema 和接口。
若 C002 或其他动态资产仍为暂缓，P3 不再被完全阻断，但只能进入 draft/test 模式：允许实现 provider 抽象、schema、prompt/schema/model routing 版本记录、Evals、成本日志、人工审核和迁移建议；不得把 draft bootstrap 知识点或其他 draft 动态资产作为生产正式输入，不得把真实模型输出自动写入正式 `active` 资产体系。D001-D003 当前只证明路由、成本、schema/eval 和禁用真实模型调用的合同成立，不代表可进行生产 AI 标注。

## E · P4 组卷导出

- E001 题库检索和题目卡片。已完成 draft/test 合同：`GET /questions` 支持按知识点、题型、难度区间、来源、年级、状态筛选，返回题卡 preview、主知识点、来源摘要和 block/asset 计数；正式生产筛题仍等待 C002 source-derived active。
- E002 自然语言组卷系统理解页面。已完成 draft/test 合同：教师输入 synthetic 组卷需求后，系统展示系统理解、细目表草稿和待确认问题；API/UI 均保持 `draft_test`、`productionEligible=false`、`allowRealModelCalls=false`，不等待正式 C002，不写生产组卷口径。
- E003 一键换题与撤销。可先用 draft/test 知识点、题型、难度、分值约束验证换题与 undo，不等待正式 C002。
- E004 Word/PDF 导出 MVP。可先导出 synthetic/draft 试卷并验证 Word/WPS 打开、公式题图表格不丢失。
- E005 导出前审校。
- E006 导出回归测试。

## F · P5 成绩学情

- F001 学生/班级/考试模型。先用 synthetic 学生和班级 fixture，不使用真实学生数据。
- F002 Excel 导入。先用 synthetic Excel fixture 和字段映射模板验证流程。
- F003 字段映射。字段名、模板和小题分列都按动态资产处理，可一对一/一对多/多对一映射。
- F004 小题分匹配。
- F005 得分率/区分度。正式知识点未激活前只生成 draft/test 分析口径。
- F006 知识点掌握。
- F007 学生/班级报告。
- F008 A/B/C 分层练习。

## G · P6 运维安全

- G001 权限角色。
- G002 操作审计。
- G003 缓存清理。
- G004 自动备份。
- G005 网络共享备份。
- G006 恢复包。
- G007 WinPE 应急脚本。
- G008 存储看板。
- G009 安全基线。
