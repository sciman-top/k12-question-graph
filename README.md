# 校本题谱：AI 原生校本题库与学情诊断平台 · 编码前文档包

本文件包用于交给本地 Codex CLI / AI Coding Agent 继续编码实现。当前包的目的不是“把所有未来功能一次做完”，而是把**最高约束、MVP 范围、架构、数据模型、AI 流程、UX 原则、备份灾备、测试策略、实施任务**固定下来。

## 当前仓库状态

本仓当前是**编码前设计包**：已有产品、架构、schema、配置、runbook、任务清单与 Mermaid 图；尚未创建实际 ASP.NET Core、React、PostgreSQL migration 或 Python Worker 代码。

2026-05-02 外部资料复核后的判断：最高原则、默认技术栈、模块化单体架构和 P0/P1 纵切路线保持正确；需要在进入编码前先完成 P0 准入预检，锁定 SDK/runtime、PostgreSQL 版本、数据目录、Windows Service/content root 约束、BackgroundService job lease/retry 规则、学生数据/合规辖区边界和文档门禁。

下一步最小可执行里程碑是 P0 的工程骨架与第一个“上传文件 -> 创建 ImportJob -> 持久化元数据 -> 生成备份 manifest”纵切闭环。

## 最高硬约束

> **教师工作流效率最大化。**

所有功能、界面、AI 设计、数据模型、工程取舍，均必须服从该原则。当功能完整性与教师使用效率冲突时，优先教师使用效率；当字段丰富性与录入负担冲突时，优先降低录入负担；当 AI 自动化与成本/可靠性冲突时，优先成本可控和结果可靠。

该原则必须可度量，至少用以下指标验收：

- 常规组卷从需求输入到可打印导出，目标不超过 10 分钟。
- 导入试卷时教师只处理异常项，不逐题确认全部结果。
- 高频流程默认值来自教师偏好、模板和历史映射，不要求重复配置。
- 每个新字段都能证明会用于检索、组卷、分析、导出或治理。
- 所有 AI 结果结构化、可审计、可人工接管、可回滚。
- P0/P1 默认不使用真实学生个人信息作为样本、fixture 或 prompt 内容；真实外部 AI 调用必须等数据边界和人工确认契约锁定后再评估。

## v0.1 冻结范围

v0.1 聚焦：

1. 初中物理。
2. Windows-first，本机开发，终态校本局域网部署。
3. 浏览器 Web 页面。
4. Word/PDF/图片试卷导入。
5. AI + 人工异常确认的试题入库。
6. 题图、公式、表格、多模态内容保留。
7. 稳定的物理知识点本体，课标/教材/地区考点为映射层。
8. 题库检索、自然语言组卷、一键换题、Word/PDF 导出。
9. Excel 成绩导入、小题分映射、基础学情分析。
10. 自动备份、缓存清理、恢复包、WinPE 应急恢复方案。

明确不做：在线考试、在线监考、防作弊、全学科一次上线、自动主观题阅卷、复杂 IRT、完整 QTI/CASE 实现、学生端/家长端。

## 推荐实现顺序

先按 `docs/19_Roadmap.md` 与 `tasks/backlog.csv` 执行。不要先实现高级功能。先完成 `A000 P0 准入预检`，再打通 P0/P1 的最小纵切闭环：

```text
P0: 打开应用 → 登录占位 → 上传文件 → 创建 ImportJob → 写数据库 → 文件入仓 → 备份 manifest
P1: 上传试卷 → 文档解析/OCR 占位 → 页面预览 → 异常确认队列 → 单题入库 → 来源回看
```

完整 v0.1 闭环仍是：

```text
上传文件 → AI/人工切题 → 入库 → 检索 → 组卷 → 导出 → Excel 成绩导入 → 基础分析 → 备份恢复
```

但编码必须从 P0/P1 开始，后续阶段不得倒插高级功能。

## 文件结构

```text
docs/       需求、架构、UX、数据、AI、备份、安全、测试、路线图
schemas/    AI 结构化输出 JSON Schema 草案
configs/    默认配置草案：模型路由、标签、保留策略、备份策略等
diagrams/   Mermaid 架构图、ER 图、工作流图
runbooks/   运维与应急恢复指南
tasks/      任务拆解 CSV
prompts/    Codex CLI 交接提示词、AI 任务提示词模板
sources/    官方文档/最佳实践参考来源
```

关键范围文件：

- `docs/02_MVP_Scope_and_ScopeControl.md`：v0.1 范围与后置边界。
- `docs/25_FeatureAdmissionCriteria.md`：新功能准入卡。
- `docs/28_FunctionScopeReview.md`：功能保留、修改、增加、后置与不进 v0.1 的裁决。

## 编码原则

1. 先模块化单体，不做复杂微服务。
2. 前端默认：React + TypeScript + Vite + Ant Design；shadcn/ui 仅作为需要高度定制时的备选。
3. 后端默认：ASP.NET Core / .NET 10 LTS，Windows Service 部署预留。
4. 数据库默认：PostgreSQL；自定义字段用 JSONB；全文检索先用 PostgreSQL FTS；向量检索先用 pgvector；图数据库后置。
5. 任务默认：P0 先用数据库持久化 job 表 + ASP.NET Core BackgroundService；需要仪表盘、复杂重试和定时任务后再引入 Hangfire；RabbitMQ 后置。
6. Worker：Python，用于 Docling、PaddleOCR、文档/OCR/AI 任务；通过 Adapter 与稳定 JSON 契约隔离。
7. 大文件不进数据库，进入文件仓库；数据库只保存元数据、路径、hash、引用关系。
8. 模型路由是内置模块，不是 README 建议。
9. 普通教师界面默认极简；高级能力隐藏在高级模式。
10. 所有 AI 结果都要有置信度、来源、prompt 版本、schema 版本、成本记录。
11. 所有备份恢复能力都不能只依赖主程序 UI，必须有独立脚本/恢复包。
12. 学生成绩、学生身份信息、题库原始资料和备份包按高风险资产处理；进入真实部署前必须锁定适用辖区、告知/授权、外部模型传输边界、数据保留和删除策略。
