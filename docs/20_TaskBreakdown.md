# 20 · 任务拆解

本文件给出人工可读任务拆解；机器可导入版见 `tasks/backlog.csv`。任务拆解遵循“小步闭环”：每个任务必须有验收标准和验证方式，不允许只写“建立某模块”。

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
- C002 初中物理 L1-L3 知识点初始化。暂缓：正式知识点必须在教师录入各版本教材、学科课程标准、近年当地中考/高考真题等资料后，从来源提炼并审核；当前只保留非权威 draft bootstrap guard。
- C003 公式、实验、方法、易错点。
- C004 教材章节映射。
- C005 地区考点映射。
- C006 AI 映射建议。
- C007 审核与版本快照。

P2 任务在 P1 验收前不得实现，只能保留模型预留和文档准备。

## D · P3 AI 流水线

- D001 AI Provider 抽象。
- D002 Model Router。
- D003 Structured Output Schema。
- D004 AI 切题。
- D005 知识点标注。
- D006 自然语言组卷意图解析。
- D007 答案校验。
- D008 成本统计与缓存。
- D009 FeedbackEvent。
- D010 AI Evals。

P3 任务在 P1 验收前不得实现真实模型调用，可先保留 schema 和接口。

## E · P4 组卷导出

- E001 题库检索。
- E002 题目卡片。
- E003 自然语言组卷。
- E004 细目表草稿。
- E005 一键换题。
- E006 试卷预览。
- E007 Word/PDF 导出。
- E008 导出审校。
- E009 导出回归测试。

## F · P5 成绩学情

- F001 学生/班级模型。
- F002 Excel 导入。
- F003 字段映射。
- F004 小题分匹配。
- F005 得分率/区分度。
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
