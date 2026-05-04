# Codex CLI 交接提示词

你正在实现“校本题谱：AI 原生校本题库与学情诊断平台”。请先阅读本文件包的 README.md 与 docs/00_ProjectConstitution.md。

## 最高约束

教师工作流效率最大化。任何实现选择都必须降低教师工作量和认知负担。

## v0.1 实现范围

完整 v0.1 只实现初中物理核心闭环：

```text
文件上传 → 文档解析/AI 入库 → 人工异常确认 → 题库检索 → 自然语言组卷 → 一键换题 → Word/PDF 导出 → Excel 成绩导入 → 基础学情分析 → 备份恢复
```

明确不做：在线考试、学生端、自动主观题阅卷、全学科、复杂 IRT、完整 QTI/CASE/OneRoster 实现。

旧 A000-G004 已全部完成。当前 v0.1 主线已从 P0/P1 工程纵切推进到阶段收口和产品化：

```text
H0: 阶段收口 -> fresh gate -> 教师效率基线 -> 发布候选 -> 回滚包
I0: 四个教师入口 -> 导入向导 -> 人工确认 -> 找题组卷 -> 成绩导入分析
J0: 真实 docx/PDF/扫描件 Adapter -> 黄金样本 -> 人工工作量报告
```

功能范围以 `docs/28_FunctionScopeReview.md` 为准。任何新功能必须先通过 `docs/25_FeatureAdmissionCriteria.md` 的准入卡，明确阶段归属和失败接管路径。

## 技术栈

- Frontend: React + TypeScript + Vite + Ant Design。
- Backend: ASP.NET Core / .NET 10 LTS。
- ORM: EF Core 10 + Npgsql。
- Database: PostgreSQL + JSONB + FTS + pg_trgm + pgvector。
- Job: PostgreSQL job table + ASP.NET Core BackgroundService first；Hangfire/RabbitMQ 后置。
- Worker: Python Adapter for Docling/OpenXML/PaddleOCR/AI tasks。
- File store: local directory first。
- AI output: JSON Schema Structured Outputs + prompt/schema/model/cost/confidence trace。
- Deployment: Windows-first。

## 当前编码顺序

旧 A000-G004 已全部完成，当前不要再按“只允许先做 P0/P1”的旧口径执行。新的主线见 `docs/87_PhaseCloseoutAndFullRoadmap.md` 与 `tasks/backlog.csv`：

1. 先执行 H001-H006：阶段收口、fresh gate、教师效率基线、发布候选、main/远端同步和新看板初始化。
2. 再执行 I001-I006：普通教师四入口、导入向导、人工确认队列、找题组卷、成绩导入分析和新手默认值产品化。
3. 再执行 J001-J006：真实 docx/PDF/扫描件 Adapter、公式/表格/题图保真、工具诊断、导入准确率与人工工作量报告。
4. K 以后必须等前置证据通过再进入，不因长期路线图已写出就提前扩大功能面。

不要先做学生端、在线考试、监考、全学科一次上线、真实学生数据、真实 AI 自动写入 active、微服务、RabbitMQ、Kubernetes、图数据库或公网 SaaS。

## 质量要求

- 所有大文件不进数据库。
- 所有删除都先软删除或进回收站。
- 所有 AI 任务记录成本、置信度、prompt 版本、schema 版本。
- 任何阶段都不把真实学生姓名、学号、班级、成绩表或含学生身份的 prompt 放入 fixture、日志或外部 AI 调用。
- 真实外部 AI 调用必须等合规辖区、数据责任方、脱敏策略和人工确认契约锁定后再评估。
- 所有复杂流程必须可回滚。
- 所有核心操作写入操作日志。
