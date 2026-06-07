# 109 · 发布 Go / No-Go 卡

日期：2026-06-07。

## 1. 当前默认结论

截至当前版本，当前裁决为 `No-Go`。

当前未关闭的关键原因：

- `P003` 现场数据授权、支持负责人和回滚记录未闭合。
- `P005` 反馈分流未闭合。
- `P006` 正式发布裁决未留痕。

## 2. 用途

本卡是 `P006` 的单页裁决入口。它不替代证据包，但要求把分散证据压缩成可签字的发布判断。

## 3. 当前裁决卡

### 发布身份

| 字段 | 必填说明 |
|---|---|
| release candidate | `未创建`。当前仅形成 No-Go 裁决底稿，不创建 tag candidate。 |
| target milestone | `P001 readiness -> P003/P005/P006 closeout -> v0.1 live pilot release decision` |
| deployment mode | 当前默认假设为 `离线优先`；云 API 增强和本地增强都不是首个试点默认值。 |
| hardware baseline | `未锁定最终现场基线`。当前只有 host capability / worker profile 只读诊断证据，缺隔离机实跑、打印、网络和权限域记录。 |
| data boundary | 真实学生数据外部模型传输默认 `禁止`；现场试点前继续使用 synthetic/anonymized 路径，直到数据授权记录完成。 |

### 硬门禁快照

| 项目 | 通过标准 | 当前状态 |
|---|---|---|
| build / test / contract / hotspot | 全通过或有效 N/A | `开发机通过，但不足以构成发布结论`。已有 `docs/evidence/20260504-h0-full-gate-evidence.md` 与 `docs/evidence/20260509-p0-live-auto-progress.md`；仍缺现场链路证据。 |
| automation / visual surrogate preflight | 非现场客观检查尽量闭合 | `非现场通过`。`NS906`、`NS904`、`NS801-NS806` 已覆盖 route smoke、artifact、source screenshot、backup/restore、visual surrogate；但它们不能替代隔离机、打印、权限域、真实网络和签字。 |
| backup | manifest 可验证 | `非现场通过`。`G001-G004`、`O003` 和 `NS801-NS806` 证据存在，但隔离机实跑未完成。 |
| restore | restore drill 通过 | `非现场通过 / 现场未验证`。`docs/evidence/20260505-o003-recovery-drill-upgrade.md` 已证明隔离恢复演练，现场恢复窗口和操作者签收未完成。 |
| teacher efficiency | 达标或有已批准例外 | `未通过发布口径`。已有 `M006` 十分钟组卷与 `S012B` 非现场链路证据，但缺现场教师观察和已批准例外。 |
| privacy / authorization | 已锁定边界且证据完备 | `部分通过 / 仍阻断`。`N001` 已锁定默认边界，但 `P003` 明确缺数据授权记录、支持负责人和反馈模板。 |
| auth / audit | 高风险动作 fail-closed | `非现场通过 / 现场未验证`。`O004B` 已完成 fail-closed 与结构化审计，隔离机角色审计和现场高风险动作记录未完成。 |
| onsite blockers | 仅剩现场事实阻断 | `未通过`。`P001`、`P003`、`P005`、`P006` 仍为 `待办`，且 `REAL005` 仍为 `not_closed`。 |

当前发布判断应尽量把剩余阻断收口为“真实现场事实和责任签字”，而不是把本可由自动化闭合的客观检查继续留给人工现场。

### 关键证据锚点

| 主题 | 证据 |
|---|---|
| P001 readiness pack | `docs/evidence/20260607-ns904-p001-readiness.json` |
| P001 preflight report | `docs/evidence/20260607-p001-live-pilot-readiness-preflight-report.json` |
| P001 isolated-machine evidence template | `docs/templates/p001-isolated-machine-evidence-template.md` |
| NS906 visual surrogate | `docs/evidence/20260528-ns906-visual-surrogate-review-report.json` |
| NS1308 release evidence pack | `docs/evidence/20260607-ns1308-release-evidence-pack.json` |
| P003 admission preflight | `docs/evidence/20260607-p003-onsite-pilot-admission-report.json` |
| P005 feedback triage preflight | `docs/evidence/20260607-p005-pilot-feedback-backlog-admission-report.json` |
| P005 feedback triage template | `docs/templates/p005-pilot-feedback-triage-template.json` |
| P005 feedback triage record | `docs/templates/p005-pilot-feedback-triage-record.md` |
| P006 release decision preflight | `docs/evidence/20260607-p006-release-decision-admission-report.json` |
| P006 release decision template | `docs/templates/p006-release-decision-record-template.json` |
| P006 release decision record | `docs/templates/p006-release-decision-record.md` |
| REAL005 closure standard | `docs/evidence/20260512-real005-guangzhou-2015-2025-closure-standard-report.json` |
| 角色与审计 | `docs/evidence/20260505-o004b-role-audit-closure.md` |
| 隐私边界 | `docs/evidence/20260505-n001-real-privacy-boundary-admission.md` |
| 恢复演练 | `docs/evidence/20260505-o003-recovery-drill-upgrade.md` |
| 全量 gate 基线 | `docs/evidence/20260504-h0-full-gate-evidence.md` |

### 残余风险

| 风险 | 影响 | 可接受条件 | owner |
|---|---|---|---|
| 隔离机实跑未执行 | 无法证明已由非现场证据之外的现场事实，例如安装、打印、网络和权限域，在目标环境可用 | 完成 `P001` 现场前置包 | 试点支持负责人 |
| 现场数据授权与支持负责人缺失 | 现场试点与真实数据处理无责任闭环 | 关闭 `P003` | 数据责任方代表 + 试点支持负责人 |
| 试点反馈未分流 | 无法把真实反馈转成 keep/modify/defer/do_not_do 决策 | 关闭 `P005` | 产品负责人 |
| 发布裁决记录未形成 | 无法合法创建 tag candidate 或对外宣称 release-ready | 关闭 `P006` | 发布负责人 |
| `REAL005 = not_closed` | 不能宣称 2015-2025 真卷全流程已闭环 | 保持如实披露，或补齐逐年逐题证据后再改口径 | 题库/导入负责人 |

### 发布裁决

| 字段 | 说明 |
|---|---|
| decision | `No-Go` |
| rationale | 当前证据只证明“非现场能力和 preflight 包已较完整”，不能证明“现场可发布”。`NS13` 已完成并把仓内前置包收口到可执行状态，但 `P001/P003/P005/P006` 均未关闭，且 `REAL005` 明确保持 `not_closed`。 |
| rollback window | 当前不进入发布执行，因此不进入现场回滚窗口；继续沿用既有 backup manifest、restore drill 和 disable-switch 证据作为预案。 |
| tag candidate plan | `不创建`。只有在 `P005` 反馈分流完成、`P006` 裁决记录签字、并满足 release-ready 证据后才创建。 |
| disable switch | 若现场前置演练中出现异常，优先禁用云 API/profile 切换、高风险 admin 写入、active switch 与真实数据链路，回退到离线优先和人工接管路径。 |

### 最低签字角色

- 发布负责人
- 管理员负责人
- 数据责任方代表
- 试点支持负责人

## 4. Go with Exceptions 规则

只有满足以下条件时，才允许 `Go with named exceptions`：

1. 例外不涉及真实学生数据外发。
2. 例外不涉及无法回滚的生产写入。
3. 例外有明确 owner、expires_at 和 recovery plan。
4. 普通教师可继续完成主链路。

## 5. 与现有清单的关系

- 证据来源仍来自 `docs/evidence/`、`tasks/completion-state-dashboard.csv` 和 `P001-P006`。
- `docs/templates/p006-release-decision-checklist.md` 负责逐项核对。
- 本卡负责最终一页式裁决，不再只靠分散 preflight 结论。

## 6. 解锁条件

只有同时满足以下条件，当前裁决才允许从 `No-Go` 进入下一轮复核：

1. `P001` 只剩隔离机安装、打印、网络、权限域和操作者签收等现场事实，并已完成对应签收。
2. `P003` 数据授权、支持负责人、回滚方案和反馈模板完成。
3. `P005` 反馈完成 keep / modify / defer / do_not_do 分流。
4. `P006` 形成正式 release decision record，并明确 tag candidate 与 rollback window。
