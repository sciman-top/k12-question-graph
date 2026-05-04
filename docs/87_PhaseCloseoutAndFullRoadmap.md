# 87 · 阶段收口与全程路线图

日期：2026-05-04。

## 1. 判断

AI 推荐：现在应当做阶段收口，然后重建下一轮任务清单。

理由：旧 `tasks/backlog.csv` 从 A000 到 G004 已全部标记为 `已完成`，README、路线图和任务拆解也已经把 P0-P6 描述为可运行实现、draft/test 合同或受控 active 合同。继续在旧 P0-P6 框架里追加零散项，会让“已完成的合同层”和“下一轮产品化/试点层”混在一起，后续很难判断到底是 v0.1 系统能力、生产可用性，还是长期平台能力。

阶段收口不等于项目完成。当前完成的是：

- P0-P6 系统骨架、合同门禁和 draft/test 闭环。
- C002 初中物理 v1 source-derived active 当前默认版本。
- AI、导出、学情、备份、恢复、安装等关键能力的合同或 synthetic/draft 验证。

尚未完成的是：

- 真实教师日常使用的产品级顺滑体验。
- 真实 Word/PDF/扫描件解析质量基线。
- 真实外部 AI 小批量试点和人工审核闭环。
- 真实学生成绩数据进入系统前的合规、授权、保留和删除边界。
- Windows Service/安装器/恢复演练的准生产发布包。
- 教师现场试点、反馈回流和 v0.1 发布裁决。

## 2. 完成态分层

| 层级 | 当前状态 | 裁决 |
|---|---|---|
| 规划与范围 | 已建立 teacher-first、v0.1 范围、功能准入和动态资产原则 | 可收口 |
| P0/P1 可运行纵切 | 上传、文件、ImportJob、人工确认、来源回看、备份和 gate 已有实现与合同 | 可收口但需 fresh gate |
| P2 知识资产 | C002 v1 已 active，C002R 修订合同已建立 | 可收口，后续按版本修订 |
| P3 AI | 目前是 stub/draft/test 与成本日志、schema/eval、预算门禁 | 不可标记生产完成 |
| P4 组卷导出 | 检索、组卷理解、换题、导出已有 draft/test 合同 | 需产品化和真实题库场景 |
| P5 学情 | synthetic fixture 已打通成绩导入和基础分析 | 真实学生数据前必须过隐私准入 |
| P6 运维恢复 | 备份、共享、缓存、WinPE、pgpass dry-run 已合同化 | 需安装包和恢复演练 |
| v0.1 发布 | 未完成 | 下一轮主目标 |
| 长期平台 | 未完成 | v0.1 稳定后分阶段进入 |

## 3. 推进原则

1. 先做 H0 阶段收口，刷新证据、门禁、回滚和主分支状态。
2. 再做 I0-J0，把教师四个入口和真实文档解析打磨成可用产品，而不是继续堆后台合同。
3. K0-L0 只在 C002 active 和教师审核链稳定后，进入知识资产生产应用与真实 AI 小批量试点。
4. M0-N0 把组卷导出和成绩学情从 synthetic/draft 变成教师能跑的闭环。
5. O0-P0-live 做安装、恢复、权限、试点和 v0.1 发布裁决。
6. Q0-R0 才进入多学科、标准互操作、复杂分析、队列扩展和多校部署等长期能力。

## 4. 全程路线图

| 阶段 | 目标 | 退出条件 |
|---|---|---|
| H0 阶段收口 | 把 A-G 旧 backlog 收成可追溯基线 | fresh gate 或明确 gate_na、证据包、回滚包、主分支状态、下一轮 backlog 均完成 |
| I0 教师工作流产品化 | 四个教师入口形成顺滑页面闭环 | 导入、组卷、成绩导入、分析均能代理完成，普通教师不接触脚本和证据术语 |
| J0 真实文档解析 | docx、PDF、扫描件进入稳定 Adapter | 黄金样本可复跑，输出 DocumentModel、SourceRegion、diagnostics 和人工接管报告 |
| K0 C002 生产使用 | active C002 真正服务检索、组卷、分析和修订 | 版本引用、映射审核、历史解释和 C002R 修订演练通过 |
| L0 真实 AI 受控试点 | 小批量真实模型只产候选，不写 active | 数据边界、预算、缓存、人工审核、no active write 和成本证据齐备 |
| M0 组卷导出生产闭环 | 教师 10 分钟内获得可打印试卷 | 自然语言、细目表、题篮、换题、审校、Word/PDF 导出通过场景验收 |
| N0 成绩学情试点 | Excel 成绩导入和讲评分析可被教师复用 | 隐私准入、字段映射复用、异常行集中提示和报告导出通过 |
| O0 部署运维准生产 | Windows/LAN 安装、备份、恢复、权限可演练 | 发布包、pgpass、恢复演练、权限审计和健康面板通过 |
| P0-live 试点与发布裁决 | 用真实或授权脱敏材料完成教师试点 | 试点证据、反馈转 backlog、v0.1 release decision 完成 |
| Q0 多学科扩展 | 通过统一激活工作台接入第二学科 | 新学科 candidate、review、active、rollback 走同一治理链 |
| R0 长期平台演进 | 根据真实瓶颈引入高级能力 | 搜索、队列、标准、复杂分析、多校部署均有数据支撑和 ADR |

## 5. 下一轮任务清单

机器可读清单已追加到 `tasks/backlog.csv`，从 H001 到 R007。执行顺序固定为：

```text
H001-H006
→ H007
→ I001-I007
→ J001-J006
→ K001-K006
→ L001-L007
→ M001-M006
→ N001-N006
→ O001-O007
→ P001-P006
→ Q001-Q005
→ R001-R007
```

近期只应执行 H/I/J 三组。K 以后必须等前置证据通过，不要因为任务已写入长期路线图就提前扩大功能面。

外部复核详见 `docs/88_EngineeringEndStateExternalReview_20260504.md`。该文档确认现有栈和架构大方向保留，并把新增补强项落到 H007、I007、L007、O007、R007。

## 5.1 当前执行看板

更新时间：2026-05-04。

| 层级 | 状态 | 当前动作 |
|---|---|---|
| H0 阶段收口 | H001-H007 已完成 | 下一轮按 I/J/K/L/M/N/O/P/Q/R 长线推进 |
| I0 教师工作流产品化 | I001-I007 已完成 | 下一轮进入 J0 管理员/系统操作面收口 |
| J0 真实文档解析 | 待办 | I002 后从 J001 OpenXML docx adapter 开始 |
| K0 以后 | 待办 | 仅保留长期路线，不提前扩大功能面 |

近期执行项只看 H/I/J：H0 负责收口和漂移守卫，I0 负责教师默认入口和工作台产品化，J0 负责真实 docx/PDF/OCR adapter 与导入准确率基线。K0 以后必须等前置证据通过后再进入。

## 6. H0 阶段收口任务

| ID | 任务 | 验收 |
|---|---|---|
| H001 | 旧 backlog 完成态核验 | A000-G004 状态、证据、门禁、README 口径一致，不把 draft/test 写成生产完成 |
| H002 | full gate 与 quick gate 基线刷新 | 有数据库时运行 full gate，无数据库时运行 quick gate 并按 gate_na 留痕 |
| H003 | 教师效率基线复测 | 记录导入、组卷、导出、成绩导入步骤数、耗时和异常接管点 |
| H004 | 发布候选和回滚包收口 | release candidate notes、backup manifest、回滚命令和已知缺口齐备 |
| H005 | main 合并与远端同步检查 | 当前分支、main、origin/main 和未合并分支状态清楚 |
| H006 | 下一轮任务看板初始化 | H-R 阶段任务成为新主线，H/I/J 标为近期执行项 |
| H007 | 外部复核漂移守卫 | 复核官方文档、成熟项目和最佳实践，并把差异落到文档或 backlog |

## 6.1 外部复核补强项

| ID | 阶段 | 作用 |
|---|---|---|
| H007 | H0 | 防止工程终态和路线图随官方文档、社区成熟项目和最佳实践变化而漂移 |
| I007 | I0 | 明确 server-state、教师草稿、撤销快照和 typed API 边界 |
| L007 | L0 | 真实 AI 调用前补 LLM security red-team gate |
| O007 | O0 | 发布前补 EF migration bundle、升级、回滚和 restore drill |
| R007 | R0 | 标准互操作先做 profile map，不直接做完整 QTI/CASE/OneRoster/Caliper |

## 7. 执行门禁

每个阶段仍遵守 `build -> test -> contract/invariant -> hotspot`。若当前阶段是纯文档或缺少数据库凭据，必须按 `gate_na` 写：

```text
reason:
alternative_verification:
evidence_link:
expires_at:
```

下一轮的默认验证组合：

- 规划和 backlog：CSV/JSON/YAML parse、`tools/run-roadmap-guard.ps1`、文档一致性检索。
- 代码和合同：`tools/run-gates.ps1`。
- 无数据库快速反馈：`tools/run-c002-dry-run-suite.ps1` 与相关单项 contract。
- 教师效率热点：代理 walkthrough、步骤数、耗时、异常接管点和截图/报告证据。
- 中高风险动作：备份 manifest、restore drill、回滚命令和人工确认表。

## 8. 不提前做的事

- 不在 H0-I0 期间引入学生端、家长端、在线考试或监考。
- 不把真实学生成绩、身份信息或含隐私的 prompt 放入 Git、fixture 或外部模型。
- 不把真实 AI 输出直接写入 `active`。
- 不在没有真实瓶颈前引入 RabbitMQ、微服务、Kubernetes、独立搜索引擎或图数据库。
- 不把多学科支持变成一次性全学科上线；第二学科必须复用动态资产激活链。

## 9. 回滚

本文件和新 backlog 属规划层变更，默认 Git 回滚即可。若后续阶段执行数据库、文件仓库、备份、active switch 或真实 AI 调用，必须额外记录：

- backup manifest 或 restore point。
- 数据库迁移/回滚命令。
- 文件仓库 snapshot 或 hash manifest。
- active/candidate/reviewed 状态切换报告。
- 人工确认记录和恢复责任人。
