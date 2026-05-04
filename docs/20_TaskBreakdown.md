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
- C002I 来源资料工作台 MVP。已完成 API/UI/gate 合同：同一上传链路按教材、课程标准、当地真题、考情年报、校本资料和教师原创分组，记录必需/强烈建议/可选状态、`region/year/gradeOrScope/editionOrVersion/materialBatchKey`、三类用途许可、hash 和列表；ChatGPT Web 初提炼结果只作为 `candidate`，必须与本项目上传 PDF 的来源证据交叉核验后才可进入 `reviewed/active`。
- C002J 广州中考真实来源资料导入证据层。已完成：33 个原始 PDF 已迁入统一 Git 外目录 `D:\KQG_Data\source_materials\imported\guangzhou_physics_2016_2025`，并在备份预检查后通过 `tools/import-c002-source-materials.ps1 -Apply -StartApi` 导入 `SourceDocument/FileAsset`。验收证据是 `material_batch_key=guangzhou_physics_2016_2025` 下课程标准 1、教材 3、广州中考年报 10、广州中考真题/答案/解析 19，全部关联非空 sha256；本任务未激活正式知识点，也未导入候选资产。
- C002K C002 cleaned candidate 自动导入 candidate DB。已完成：质量复核完成包通过 `tools/merge-c003-quality-review-package.ps1` 叠加到完整 C003 CSV 包后，`tools/prepare-c002-candidate-csvs.ps1` 已生成新的 cleaned candidate 输入；`tools/import-c002-candidate-assets.ps1` 经 dry-run、source hash 对齐和备份 manifest `D:\KQG_Backups\20260504-013307\manifest.json` 后执行 candidate apply。该批次导入 452 个动态资产、400 条映射、1 个 migration 计划和 1 个审核队列项，初始保持 `candidate/pending_review/productionEligible=false`，不允许直接 active。
- C002L 候选审核与激活前检查合同。已完成：`tools/run-c002l-candidate-review-readiness.ps1` 从真实 DB 读取 C002K 批次，报告 `candidate/reviewed/active` 三阶段状态、待审映射、migration、审核队列、来源 hash、rollback snapshot 和 active guard 阻断原因。该合同明确 C002 完成是“可治理的 v1 active 当前默认版本”，不是永久冻结；后续修改必须新建候选版本并通过映射、影响报告、审核、回滚和 active 切换。
- C002M 候选审核 apply/rollback 合同。已完成：`tools/generate-c002-review-decisions.ps1` 基于 source hash 完整、未 active、待审批次生成审核决策；`tools/run-c002m-candidate-review-apply-contract.ps1 -DecisionFile ... -Apply` 已将 452 个资产推进到 `reviewed`、400 条映射推进到 `approved`、migration 推进到 `dry_run`，并关闭审核队列。该合同仍不直接激活正式知识体系。
- C002N0 本地优先 AI 消耗削减审查。已完成：`docs/67_LocalFirstAIConsumptionReductionReview.md` 明确文件 hash、来源 metadata、CSV/JSON/YAML/schema、SQL、导入幂等、active guard、chunk/cache、token 预算和中文显示 guard 都应本地 100% 覆盖；外部 AI 只处理语义提炼、复杂映射和高风险仲裁。`tools/run-local-first-ai-guard.ps1` 已纳入 full gate。
- C002N 来源 chunk/extraction cache。已完成：`tools/run-c002n-source-chunk-cache.ps1` 对 33 个来源 PDF 做本地页级文本抽取、source hash、page hash、chunk hash、块类型、去重缓存和中文报告；证据为 `docs/evidence/c002n-source-chunk-cache-report.json`，共覆盖 33 份来源、1478 页级 chunk，第二次运行缓存命中 33/33，外部 AI 调用为 0。该任务只建立 C002O/C002P/C002Q 的本地证据层，不激活正式 C002。
- C002O 大模型提炼 schema + eval golden sample。已完成：`schemas/ai/c002_candidate_extraction.schema.json` 定义候选知识点、课标条目、教材章节、考点、趋势摘要和映射建议六类结构化输出；`tools/run-c002o-candidate-extraction-eval.ps1` 用 C002N chunk hash 锚点验证 golden fixture 字段、边界和 `pending_review/productionEligible=false/allowRealModelCalls=false` 口径，不接真实模型。
- C002P 分层模型路由预算门禁。已完成：`tools/run-c002p-model-budget-guard.ps1` 固化 L0-L4 默认模型、reasoning、升级目标、dry-run token 上限、L4 数量上限、cache key 和 full extraction 人工预算确认；该 guard 读取 C002N chunk/cache 与 C002O schema/eval 报告，确认 33 份来源的 `estimatedInputTokens=520612` 和 `chunkCount=1478` 超出 C002Q dry-run 上限，full extraction 必须 fail-closed 到显式预算报告和人工确认。
- C002Q0 真实模型调用与 outer subagent 编排 readiness。已完成：`tools/run-c002q0-outer-ai-readiness.ps1` 读取 C002N/C002O/C002P 证据和 `configs/model_routing.defaults.yaml`，验证 `configs/ai-evals/c002q0-outer-ai-readiness.sample.json` 的批次 manifest、模型角色、reasoning、预算、sample rate、输入/输出 artifact、evidence anchor、cache hit、no active write、人工审核和 subagent 外层编排边界；报告为 `docs/evidence/c002q0-outer-ai-readiness-report.json`。本任务外部 AI 调用为 0，项目运行时真实模型调用仍禁用，subagent 不成为运行时依赖。
- C002Q 小批量 AI extract dry-run。已完成：`tools/run-c002q-ai-extract-dry-run.ps1` 在 C002Q0 通过后执行 contract dry-run，抽样课程标准、教材、年报、真题 4 类来源共 12 个 cache-hit chunks，生成 `candidate/pending_review/production_eligible=false` 候选输出、模型层级 trace、token/cost/cache 证据；报告为 `docs/evidence/c002q-ai-extract-dry-run-report.json`。本轮 `allowRealModelCalls=false/externalAiCalls=0/noActiveWrite=true`，不写数据库，不覆盖 C002K。
- C002S 广州物理正式化前审查闭环。已完成质量阻断清零：`tools/run-c002s-formalization-precheck.ps1` 会自动 overlay `quality-review-complete-csv-package`，抽样核对 2016-2025 每年 3 道题的原卷、答案、年报页码、考点、知识点、教材/课标映射；报告为 `docs/evidence/c002s-formalization-precheck-report.json`，当前 `sampleFailures=0`、`qualityIssuesOpenForProduction=0`、`productionActivationAllowed=true`。C002S 表示质量阻断已清零，正式 active 由 C002M/C002T 的审核和受控切换完成。
- C002T reviewed -> active 受控切换。已完成：`tools/run-c002t-active-switch.ps1` 默认 dry-run，`-Apply` 必须提供 backup manifest。已在 `D:\KQG_Backups\20260504-015358\manifest.json` 备份并校验后执行 active switch：452 个 `reviewed` 资产切换为 `active`，migration 切换为 `applied`，报告为 `docs/evidence/c002t-active-switch-report.json`。该入口可复跑，已激活后返回 `alreadyActive=true`。
- C002U 学科激活工作台 v0。已完成教师侧 UI 简化层：Web 页面包含 `data-flow="subject-activation-workbench"`，把资料批次、候选结果、教师复核、激活前检查和正式启用呈现为可理解流程；教师侧只提供复核、确认表、证据和回滚查看入口，明确“不在教师端直接激活”，正式激活只给管理员。验证入口为 `tools/run-subject-activation-workbench-ui-contract.ps1`，已纳入 `tools/run-gates.ps1`；说明见 `docs/80_SubjectActivationWorkbenchV0.md`。
- C002 正式知识点初始化。已完成：初中物理 L1-L3 知识体系 v1 已通过来源证据、审核决策、映射影响、回滚快照和 active switch guard，成为当前生产默认版本。完成不表示永久冻结；旧版本保留用于历史题目、旧卷、学情解释和回滚，后续修改走 C002R。
- C002R 知识体系版本治理与便捷修订闭环。已完成合同层：`tools/run-c002r-versioned-revision-contract.ps1` 验证 C002 v1 active 后的修订不直接改旧 active；教师只提交修订原因、来源证据、影响范围和紧急程度；系统生成 `candidate/productionEligible=false` 版本，覆盖 `equivalent/split/merge/broader/narrower/renamed/deprecated` 映射、影响报告、审核理由、rollback snapshot、历史学情冻结和管理员 active 切换边界。说明见 `docs/81_C002R_VersionedRevision.md`。
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
- E003 一键换题与撤销。已完成 draft/test 合同：`POST /paper-requests/replace-question` 和 UI `data-flow="paper-question-replacement"` 按同知识点、同题型、相近难度、同分值、当前卷不重复、近期未用生成替换题，并返回 `undo` 快照；保持 `draft_test`、`productionEligible=false`、`allowRealModelCalls=false`，不等待正式 C002，不写生产试卷语义。
- E004 Word/PDF 导出 MVP。已完成 draft/test 合同：本地生成 synthetic/draft DOCX/PDF 工件、manifest 和 evidence report，校验公式文本、题图 media、表格内容、PDF header/EOF 与前端导出控件；保持 `productionEligible=false`，不等待正式 C002，不写正式试卷语义。

- J004 公式/表格/题图保真回归。已完成 draft/test 合同：synthetic OpenXML 导入样本经 worker 解析出 `formula/table/image`，组装成 draft question 后保留 sourceRegion 和题图 asset，再导出 Word/PDF 并验证 DOCX 公式文本、表格 XML 和 media 未丢失；不写数据库、不使用真实学生数据、不调用外部 AI。验证入口为 `tools/run-j004-fidelity-regression-contract.ps1`，说明见 `docs/89_J004_FidelityRegression.md`。

- J005 Adapter 版本诊断和工具供应链门禁。已完成 draft/test 合同：抽样运行 OpenXML DOCX、文本 PDF、扫描 PDF、无效图片和 raw 文档 adapter，要求每次解析记录 `adapterName/adapterVersion/toolName/toolVersion/commandArgs/durationMs/inputSha256/outputSha256/warnings/errors`；供应链边界保持本地 Python synthetic gate，不调用外部 OCR、Docling、网络或真实 AI。验证入口为 `tools/run-j005-adapter-diagnostic-supply-chain-contract.ps1`，说明见 `docs/90_J005_AdapterDiagnosticSupplyChain.md`。

- J006 导入准确率基线与人工工作量报告。已完成 draft/test 代理基线：读取 golden import 样本和 J001-J005 证据，记录 source region 与 block 保存 100%、人工确认项 6 个、失败接管步骤 6 个、代理估算 8 分钟；`automatedCutCaseCount=0` 且 `autoCutAccuracy=N/A`，明确当前未启用真实 OCR/AI 自动切题，不虚报 AI 自动化。验证入口为 `tools/run-j006-import-accuracy-workload-contract.ps1`，说明见 `docs/91_J006_ImportAccuracyWorkload.md`。

- K001 C002 active 生产查询接入。已完成只读数据库合同：验证 C002 默认批次全部为 active、无 candidate/reviewed 残留、无 pending mappings、migration 已 applied、来源资料 33 份；题库检索、组卷约束和学情分析三个查询 surface 均默认引用 `junior-physics-guangzhou-source-derived-v1`。本任务不修改 active 资产、不写真实学生学情、不调用外部 AI。验证入口为 `tools/run-k001-active-c002-production-query-contract.ps1`，说明见 `docs/92_K001_ActiveC002ProductionQuery.md`。

- K002 C002R 教师修订 UX。已完成教师侧低负担入口合同：讲评分析页提供 `data-flow="c002r-teacher-revision-ux"`，教师只提交修订原因、来源证据、影响范围和紧急程度；系统侧生成 candidate 版本、映射建议、影响报告和回滚快照。UI 明确普通教师不能直接切换 active，不暴露 importKey/migration/rollback snapshot/active switch 为可执行操作；验证入口为 `tools/run-k002-c002r-teacher-revision-ux-contract.ps1`，说明见 `docs/93_K002_C002RTeacherRevisionUX.md`。

- K003 映射审核工作台 UI 实现。已完成 C002H 前端承接合同：讲评分析页提供 `data-flow="c002h-mapping-review-workbench-ui"`，默认聚焦待审核、低置信度、高影响和复杂基数映射；split、merge、deprecated 样例以旧对象/新对象/映射边/来源证据/影响预览/回滚预览并排呈现，支持确认、改目标、拆分、合并和撤销动作。UI 明确批量确认只允许低风险一对一，不直接应用到 active；验证入口为 `tools/run-k003-mapping-review-workbench-ui-contract.ps1`，说明见 `docs/94_K003_MappingReviewWorkbenchUI.md`。
- E005 导出前审校。
- E006 导出回归测试。

## F · P5 成绩学情

- F001 学生/班级/考试模型。已完成 draft/test 合同：新增 `students`、`class_groups`、`assessments`、`assessment_enrollments` 基础表和 EF migration，用 synthetic 学生、班级、考试和报名关系做事务回滚验证；保持 `productionEligible=false`，不使用真实学生数据，不暴露学生端。
- F002 Excel 导入。已完成 draft/test 合同：生成并解析 synthetic `.xlsx` 成绩模板，保存字段映射 JSON，2 行导入成功、1 行异常集中提示；新增 `score_import_templates`、`score_import_batches`、`score_records`、`item_scores` 表并用事务回滚验证；保持 `productionEligible=false`，不使用真实学生数据，不写正式学情口径。
- F003 得分率知识点分析。已完成 draft/test 合同：`tools/run-f003-knowledge-mastery-analysis-contract.ps1` 用 synthetic 小题分和 active 知识版本引用输出班级总分得分率、知识点得分率、区分度、薄弱知识点和学生掌握摘要；保持 `productionEligible=false/realStudentDataUsed=false/noProductionHistoryWrite=true`，不使用真实学生数据、不暴露学生端、不改写正式历史学情。说明见 `docs/82_F003_KnowledgeMasteryAnalysis.md`。
- F004 小题分匹配。
- F005 得分率/区分度。正式知识点未激活前只生成 draft/test 分析口径。
- F006 知识点掌握。
- F007 学生/班级报告。
- F008 A/B/C 分层练习。

## G · P6 运维安全

- G001 自动备份到本机与共享目录。已完成 draft/test 合同：`tools/run-g001-backup-share-contract.ps1` 复用 `tools/backup.ps1` 和 `tools/verify-backup.ps1`，验证本机备份与可配置共享目录副本均通过 manifest/hash 校验；脚本不启动 Web/API 主程序，`backup_policy.defaults.yaml` 保留 `network_share` 配置位和 `no_mirror_delete_to_network_share=true`。说明见 `docs/83_G001_BackupShareDrill.md`。
- G002 缓存清理与存储看板。已完成 draft/test 合同：API 提供 `GET /api/admin/storage/summary` 和 `POST /api/admin/cache/cleanup`，Web 提供管理员存储看板标记，`tools/run-g002-storage-cleanup-contract.ps1` 会启动 API 验证配置化 cache root、dry-run 预览、实际清理、fresh cache 保留和 file store 保护；报告为 `docs/evidence/g002-storage-cleanup-report.json`。本任务不删除文件仓库、备份包、学生成绩或正式资产。
- G003 WinPE 应急拷贝脚本生成。已完成 draft/test 合同：`configs/recovery_media.defaults.yaml` 提供数据目录、备份目录、目标介质和 copy-only 安全策略；`tools/run-g003-winpe-emergency-copy-contract.ps1` 生成 `KQG_EmergencyCopy.cmd`、`KQG_EmergencyCopy.ps1`、WinPE 说明和 manifest，并验证不使用镜像删除、支持目标参数、包含 `verify-backup.ps1` 后续校验说明；报告为 `docs/evidence/g003-winpe-emergency-copy-report.json`。本任务只生成离线恢复材料，不执行真实拷贝。
- G004 安装器数据库凭据初始化与 pgpass 验证。已完成 draft/test 合同：`configs/installer_credentials.defaults.yaml` 固化 pgpass、ACL、清空进程级 `PGPASSWORD`、临时 `APPDATA` dry-run 和不记录密码的边界；`tools/run-g004-pgpass-installer-dry-run.ps1` 使用临时 `%APPDATA%\postgresql\pgpass.conf` 写入凭据、收紧 ACL、清空当前进程 `PGPASSWORD` 后执行 `psql -w`，验证完成后删除临时目录；报告为 `docs/evidence/g004-pgpass-installer-dry-run-report.json`。本任务不修改真实用户 pgpass，不依赖 Codex 或桌面进程自然继承 User 环境变量。

## H-R · 阶段收口后的长期任务主线

旧 A000-G004 已全部完成。下一轮任务不继续塞回 P0-P6，而是进入 H-R 主线；完整判断、阶段边界、退出条件和任务顺序见 `docs/87_PhaseCloseoutAndFullRoadmap.md`，机器可读清单见 `tasks/backlog.csv`。

近期执行范围：

- H001-H006：阶段收口、fresh gate、教师效率基线、发布候选、main/远端同步和新看板初始化。
- I001-I006：普通教师四入口、导入向导、人工确认、找题组卷、成绩导入分析和新手默认值产品化。
- J001-J006：真实 docx/PDF/扫描件 Adapter、公式/表格/题图保真、工具诊断、导入准确率与人工工作量报告。

中期执行范围：

- K001-K006：C002 active 生产使用、C002R 教师修订、映射审核、历史版本解释和知识资产健康面板。
- L001-L006：真实 AI 合规准入、小批量 AI extract、AI 切题/标注/答案校验试点和成本缓存看板。
- M001-M006：题篮、自然语言组卷、换题、导出前审校、Word/PDF 回归和 10 分钟组卷验收。
- N001-N006：真实学生数据准入、Excel 模板复用、小题分映射、讲评报告、分层练习和隐私审计。
- O001-O006：Windows Service 发布、安装初始化、恢复演练、权限审计、健康面板和离线应急演练。

远期执行范围：

- P001-P006：试点部署、教师代理试点、现场教师试点和 v0.1 发布裁决。
- Q001-Q005：第二学科候选资料、教师复核、active 演练、跨学科差异和多学科 UI 简化。
- R001-R007：搜索、队列、标准互操作、高级分析、多校部署、长期技术债节奏评估和标准互操作 profile map。

新增外部复核补强项见 `docs/88_EngineeringEndStateExternalReview_20260504.md`：H007 external benchmark drift guard、I007 server-state 与 typed API boundary、L007 LLM security red-team gate、O007 EF migration bundle 与升级演练、R007 interoperability profile map。
