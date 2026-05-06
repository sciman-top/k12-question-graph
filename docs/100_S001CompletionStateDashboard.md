# 100 · S001 完成态看板与残缺面审计

日期：2026-05-06。

## 1. 结论

你的判断成立：当前项目不能按“多数板块已经闭环可正常使用”汇报。更准确的工程事实是：

- 已有大量 `contract_done`、`synthetic_done`、`db_backed_done` 的底座和门禁。
- 普通教师可直接连续使用的 `teacher_validated` 板块目前为 0。
- `release_ready` 板块目前为 0。
- 最接近真实可用的是管理员/系统底座：PostgreSQL/FileStore、C002 active 资产、备份恢复、部分权限审计。
- 教师核心业务仍必须按 `S002-S012` 从 application service 到 E2E 产品化重做闭环。

## 2. 完成态裁决规则

| 状态 | 裁决条件 | 用户口径 |
|---|---|---|
| `contract_done` | schema、脚本、静态 UI 标记或 preflight 通过 | 只能说“合同已建立” |
| `synthetic_done` | synthetic fixture、draft/test、stub 或示例数据可跑 | 只能说“样例可跑” |
| `db_backed_done` | 真实 PostgreSQL/FileStore 读写存在并有 contract | 只能说“后端部分可用” |
| `ui_productized` | 教师 UI 接真实 API 且覆盖 loading/empty/error/retry/fallback | 可说“可试用” |
| `teacher_validated` | 授权或脱敏材料跑完并记录耗时、误差、接管点 | 可进入代理试点 |
| `release_ready` | full gate、备份恢复、权限隐私、教师效率和回滚均通过 | 可做发布裁决 |

## 3. 当前板块总表

机器可读源：`tasks/completion-state-dashboard.csv`。

| 板块 | 当前状态 | 今天是否可正常使用 | 下一任务 | 主要阻断 |
|---|---|---|---|---|
| 本机运行骨架 | `db_backed_done` | 部分可用 | S002 | 只是运行底座 |
| 教师四入口外壳 | `ui_productized` | 部分可用 | S003 | 仍大量静态示例 |
| 来源资料与 C002 active | `db_backed_done` | 管理员可用 | S008 | 未接普通教师题库闭环 |
| 试题文件上传与 ImportJob | `db_backed_done` | 后端可用 | S003 | UI 未接真实上传状态 |
| 文档解析与 OCR | `synthetic_done` | 不可正常使用 | S004 | 真实质量基线未闭环 |
| 自动半自动切题 | `synthetic_done` | 不可正常使用 | S005 | `automatedCutCaseCount=0` |
| 人工确认与接管 | `synthetic_done` | 不可正常使用 | S006 | 静态 UI contract 多于真实操作 |
| 题目保存与来源回看 | `db_backed_done` | 后端部分可用 | S006 | 缺真实教师端编辑回看闭环 |
| AI 提炼与抽取 | `synthetic_done` | 不可生产使用 | S007 | no active write 且缺生产工作流 |
| AI 知识点标注建议 | `synthetic_done` | 不可正常使用 | S007 | 缺 DB-backed review queue |
| 审核队列 | `contract_done` | 不可正常使用 | S006 | 缺统一状态流和批量处理 |
| 题库检索与题卡 | `db_backed_done` | 后端部分可用 | S008 | UI 未完整接真实 API |
| 智能组卷和题篮 | `synthetic_done` | 不可正常使用 | S009 | 缺持久化组卷 workflow |
| Word/PDF 导出 | `synthetic_done` | 不可正常使用 | S010 | 示例预览多于真实产物链 |
| 成绩 Excel 导入 | `synthetic_done` | 不可正常使用 | S011 | 真实成绩导入未闭环 |
| 学情分析与讲评报告 | `synthetic_done` | 不可正常使用 | S011 | 真实讲评导出未闭环 |
| 备份恢复与升级 | `db_backed_done` | 管理员部分可用 | S012 | 未进入教师端 E2E 演练 |
| 安装部署与 Windows Service | `contract_done` | 不可发布使用 | P001 | 隔离机器真实安装未执行 |
| 权限角色审计 | `contract_done` | 部分可用 | S012 | 需随真实流程复验 |
| 教师代理和现场试点 | `contract_done` | 不可使用 | P001 | S012 未完成 |
| 多学科扩展 | `contract_done` | 不可使用 | Q001 | v0.1 未产品化 |
| 搜索队列互操作高级分析 | `contract_done` | 不可使用 | R001 | 需真实瓶颈触发 |

## 4. 直接影响

- `tasks/backlog.csv` 的 `已完成` 只能解释为“对应任务验收口径已完成”，不能自动解释为“板块可正常使用”。
- 任何对外汇报必须优先引用 `tasks/completion-state-dashboard.csv` 的当前状态。
- `S002-S012` 不应再被视为锦上添花，而是 v0.1 可用性的主线补课。
- `P001` 仍必须等待 `S012`，否则就是把残缺产品拿去试点。

## 5. 下一步执行顺序

1. `S002`：抽出教师工作流 application service，先把业务编排从 endpoint 和静态前端中收束出来。
2. `S003`：真实导入工作台 API/UI 接通，优先解决“上传后教师看不到连续任务状态”的第一断点。
3. `S004-S006`：解析质量、切题候选、人工接管闭环，解决录题链路最核心缺口。
4. `S007-S011`：标注、检索、组卷、导出、成绩分析逐个产品化。
5. `S012`：非现场 E2E 演练后，才允许进入 `P001`。

## 6. 回滚

本次是治理和证据层变更，无业务数据迁移。回滚命令：

```powershell
git restore -- tasks/backlog.csv tasks/productization-roadmap.csv tools/run-gates.ps1
Remove-Item -LiteralPath tasks/completion-state-dashboard.csv,tools/run-s001-completion-state-dashboard.ps1,docs/100_S001CompletionStateDashboard.md,docs/evidence/20260506-s001-completion-state-dashboard.json,docs/evidence/20260506-s001-completion-state-dashboard.md -ErrorAction SilentlyContinue
```
