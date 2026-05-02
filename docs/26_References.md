# 26 · 官方文档、社区项目与最佳实践参考

本文件只记录会影响本项目架构、路线图和实现顺序的资料。可复制的 URL 清单见 `sources/references.md`。最近一次外部复核：2026-05-02。

复核口径：优先使用官方文档或项目一手资料。社区文章只作为发现候选，不作为本仓规则依据。

## 1. AI 与 API

- OpenAI Structured Outputs：AI 输出必须用 JSON Schema 或等价 schema 约束，不只靠 prompt 描述字段。
- OpenAI Prompt Caching：稳定系统上下文、题型说明、schema 和 rubric 应放在请求前缀，动态题目内容放后面。
- OpenAI Batch/Flex/Evals：离线批量导入、回归样本和成本优化应进入 P3，而不是 P0/P1。
- 决策影响：P0/P1 只做 schema/adapter/stub，真实 AI 调用推迟到 P3；普通教师界面不暴露 provider/model 选择。

## 2. 后端与数据库

- .NET 10 LTS 与 EF Core 10：适合作为 v0.1 的默认主线；Microsoft 当前支持矩阵显示 .NET 10 为 LTS，支持到 2028 年 11 月，但本仓仍必须在 A000 锁定本机 SDK/runtime 与目标学校运行环境。
- ASP.NET Core BackgroundService / Windows Service：支持先用单体后台服务跑 P0/P1 job，后续再按证据引入 Hangfire/RabbitMQ。
- PostgreSQL JSONB/Full Text Search/pg_trgm/pgvector：用一个数据库覆盖半结构化字段、全文、模糊和向量检索。PostgreSQL 当前文档主线已经到 18；本仓不直接追最新主版本，A000 必须锁定一个受支持主版本并验证扩展、备份和迁移。
- PostgreSQL pg_dump/WAL/PITR：备份恢复必须同时覆盖数据库、文件仓库和配置；P0 先做 manifest 与逻辑备份占位，P6 再做完整演练。
- 决策影响：PostgreSQL 是事实源；独立搜索引擎、图数据库、对象存储均后置。

## 3. 前端与教师工作流

- React + TypeScript + Vite：适合快速建立浏览器 Web app 与类型化前端边界。
- Ant Design：适合教师后台的数据表、表单、上传、步骤条、抽屉和批量操作；默认比从零拼 UI 更省工。
- TanStack Query / React Router：适合 API 状态、缓存、重试和页面路由。
- 决策影响：v0.1 不做营销式首页，不做学生端；首页默认普通教师高频入口，高级设置隐藏。

## 4. 文档、OCR、公式与导出

- Docling：适合 PDF/DOCX 等文档转换、版面、表格、OCR 相关实验。
- PaddleOCR / PP-Structure：适合 OCR、版面分析、表格和公式识别能力评估。
- Open XML SDK / OfficeMath：Word 导入导出、OMML 公式处理的主要 .NET 路径。
- Pandoc、KaTeX、MathJax、OCRmyPDF 等作为工具候选，不直接成为领域模型。
- 决策影响：所有外部工具必须经 Adapter 转为内部稳定 JSON，记录工具版本、输入 hash、输出 hash 和 diagnostics。

## 5. 教育技术标准

- 1EdTech QTI：题目和测试互操作。
- 1EdTech CASE：课程标准、能力框架和知识映射。
- 1EdTech OneRoster：学生、课程、成绩交换。
- 1EdTech Caliper：学习活动数据。
- 决策影响：v0.1 只预留映射字段和导入导出扩展点，不追求完整标准认证。

## 6. 安全、隐私、恢复

- OWASP ASVS：Web 应用安全验证要求。
- OWASP AISVS：AI 系统安全验证要求。
- NIST AI RMF：AI 风险管理。
- WCAG 2.2：可访问性与可理解、可操作界面。
- FERPA/COPPA/PIPL 等教育与个人信息规则：不是本仓直接给法律结论，而是要求 A000A 锁定实际部署辖区、学生数据责任方、告知/授权、外部模型传输边界和 fixture 脱敏策略。
- Windows PE、Robocopy、Task Scheduler：学校 Windows 运维与应急恢复路径。
- 决策影响：任何 AI 结果必须可审计、可人工接管；任何备份恢复不得只依赖主程序 UI。

## 7. 社区/开源项目参考原则

Moodle、Open edX、TAO 等成熟教育平台可参考权限、题库、测试和标准边界；Paperless-ngx 可参考本地文档归档、OCR、搜索、备份和“本地服务 + 数据目录”思路；题库生成类 GitHub 项目可参考“按知识点、题型、难度选题”的基本思路。但这些项目通常不以中国学校教师的 Word/Excel 流程效率为最高约束，也往往缺少 Word/PDF 入库、公式题图处理、成绩分析、低成本 AI 流水线和离线备份恢复闭环。

AI 推荐：吸收社区项目的局部模型和交互思路，不复刻完整平台路线。
