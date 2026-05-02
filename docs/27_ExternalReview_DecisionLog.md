# 27 · 外部审查与决策记录

本文件记录 2026-05-02 对本项目最高原则、技术栈、架构、路线图和任务清单的外部资料审查结论。它不替代 PRD、架构或任务清单，只记录“为什么这样选”。

复核来源类型：Microsoft Learn、OpenAI 官方文档、PostgreSQL/React/Vite/Ant Design/TanStack/React Router 官方文档、1EdTech/OWASP/NIST/WCAG 标准说明、FERPA/COPPA/PIPL 官方或主管机构资料、Moodle/Open edX/TAO/Paperless-ngx 等社区项目。

## 1. 审查结论

AI 推荐：保留“教师工作流效率最大化”作为最高原则，并把它落实为可度量的产品与工程验收，而不是停留在口号。

理由：社区题库 Demo、通用 LMS、在线考试平台和标准互操作方案通常先追求功能覆盖或标准兼容；本项目的真实起点是替代教师的 Word/Excel 低效流程。v0.1 如果先做完整标准、复杂 AI 或多端协同，会直接拖慢教师可用闭环。

## 2. 技术栈决策

| 主题 | AI 推荐 | 主要依据 | 后置条件 |
| --- | --- | --- | --- |
| 后端 | ASP.NET Core / .NET 10 LTS | Windows-first、长期支持、Windows Service 部署路径清晰 | 目标学校机器若无法安装 .NET 10 runtime，再评估 self-contained publish |
| ORM | EF Core 10 + Npgsql | 与 .NET 10 生命周期一致，减少版本错配 | 大版本升级必须跑 migration/gate |
| 前端 | React + TypeScript + Vite + Ant Design | 教师后台偏数据密集，AntD 的表格、表单、上传、布局能减少自研 UI 成本 | 若后续需要高度品牌化或弱网极轻量 UI，再局部换组件 |
| 数据库 | PostgreSQL + JSONB + FTS + pg_trgm + pgvector | 一个数据库覆盖结构化、半结构化、全文、模糊和向量检索，降低运维复杂度 | 图数据库、独立搜索引擎和对象存储后置 |
| 任务系统 | P0/P1 先用 PostgreSQL job table + ASP.NET Core BackgroundService | 初期任务量低，状态可审计，部署简单 | 出现复杂定时、仪表盘、跨进程调度时引入 Hangfire；跨机高吞吐再评估 RabbitMQ |
| 文档/OCR | Python Worker Adapter + Docling/OpenXML/PaddleOCR | 文档解析生态在 Python 更成熟，Adapter 可以隔离工具波动 | 任何工具输出都必须转为内部稳定 JSON |
| AI | Provider abstraction + Structured Outputs + Evals + prompt caching | AI 输出要可校验、可审计、可回归、可控成本 | 普通教师界面不得暴露模型路由细节 |
| 学生数据与合规 | A000A 锁定辖区、数据责任方、外部 AI 传输边界和 fixture 脱敏策略 | K-12 场景天然包含学生身份、成绩和教育记录；外部模型、日志和备份会放大风险 | 未锁定前 P0/P1 使用合成或匿名化样本，真实学生数据不得进入外部 AI |

## 3. 架构决策

AI 推荐：采用模块化单体，不采用微服务、图数据库优先或云 SaaS 优先。

原因：

- 学校部署和维护成本是核心约束，P0/P1 不需要多服务复杂度。
- PostgreSQL 已能覆盖初期事务、JSONB、全文、模糊和向量检索。
- 文件仓库与数据库分离比把大文件塞进数据库更容易备份、恢复和迁移。
- Python Worker 作为工具适配层足够，不应把工具供应商的输出格式泄漏到领域模型。

## 4. 路线图决策

AI 推荐：从 P0/P1 最小纵切开始，而不是先铺完整平台能力。

当前编码焦点：

```text
P0: 打开应用 -> 登录占位 -> 上传文件 -> 创建 ImportJob -> 写数据库 -> 文件入仓 -> 备份 manifest
P1: 上传试卷 -> 文档解析/OCR 占位 -> 页面预览 -> 异常确认队列 -> 单题入库 -> 来源回看
```

P2-P6 只保留规划，不在 P1 验收前实现真实功能。

## 5. 标准与社区项目取舍

| 来源类型 | 适合吸收 | 不建议 v0.1 直接实现 |
| --- | --- | --- |
| Moodle / Open edX / TAO 等成熟教育平台 | 权限、题库、测验、导入导出边界的参考 | 整个平台范式、在线学习/考试优先路线 |
| 1EdTech QTI/CASE/OneRoster/Caliper | 数据模型预留字段、导出/导入扩展点 | 完整标准认证与双向互操作 |
| Docling / PaddleOCR | 文档解析、OCR、版面/表格/公式能力 | 把工具输出直接当领域模型 |
| OpenAI Structured Outputs / Evals | 结构化输出、回归评测、成本日志 | 无人工复核的全自动入库 |

## 6. 本轮已落地到文档的改动方向

- 把最高原则补成可度量指标。
- 增加教师效率准入卡，防止功能膨胀。
- 把技术栈从“可选清单”收敛为默认栈和后置触发条件。
- 补充 .NET/EF Core/PostgreSQL 版本锁、Windows Service content root、BackgroundService lease/retry/idempotency 约束。
- 补充学生数据/合规辖区、外部 AI 数据传输、黄金样本脱敏和题库来源版权边界。
- 把路线图改成 P0/P1 纵切优先。
- 给 P0 增加准入预检 `A000`，给 P0 收尾增加证据包 `A011`。
- 把任务清单补上验收标准、依赖和验证命令。
- 增加文档一致性门禁，避免 README、路线图、任务 CSV、交接提示词继续漂移。
