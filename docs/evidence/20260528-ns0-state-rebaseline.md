# 20260528 NS0 非现场能力状态重基线

## Goal

把旧 `tasks/completion-state-dashboard.csv` 的完成态映射到新的非现场落地状态，避免继续用历史 `teacher_validated` 或 `已完成` 直接宣称当前模块已经真正落地。

## Policy

本次是保守重基线：

- 旧 `contract_done` / `synthetic_done` 不升格，按 `contract_only` 继续处理。
- 旧 `db_backed_done` / `ui_productized` / `teacher_validated` 只说明曾有实现或代理证据；若本轮没有重新跑 live/runtime/E2E，则前向执行状态降为 `repo_landed`。
- 只有本轮或后续任务提供当前运行证据，才升到 `runtime_verified`。
- 只有授权或脱敏材料完成非现场端到端演练，才升到 `non_site_validated`。
- 真实教师、隔离机、打印机、学校网络、权限域和发布裁决保留为 `blocked_by_onsite`。

## Rebaseline Table

| area_id | 旧状态 | 新前向状态 | 当前判断 | 下一步 |
|---|---|---|---|---|
| core-runtime | db_backed_done | repo_landed | 运行底座已有代码和历史 DB 证据，但不是教师业务闭环 | NS101-NS106 |
| teacher-shell | teacher_validated | repo_landed | 四入口有历史代理证据；需刷新当前 UI/runtime 证据 | NS105 / NS902 |
| source-materials | db_backed_done | repo_landed | C002 active 管理员可用；教师题库链路需重新串到 runtime evidence | NS501 / NS601 |
| question-upload | teacher_validated | repo_landed | 上传与 ImportJob 有历史证据；需重新跑当前 API/UI smoke | NS301 / NS302 |
| document-parsing | teacher_validated | repo_landed | adapter 有历史证据；需按 worker profile 和 golden set 重跑 | NS303-NS308 |
| question-cutting | teacher_validated | repo_landed | 切题候选有历史证据；需当前 API/worker/UI runtime 验证 | NS401 |
| human-review | teacher_validated | repo_landed | 人工确认链有历史证据；需刷新 ReviewQueue 和 UI 接管证据 | NS402 / NS403 |
| question-save | teacher_validated | repo_landed | 题目保存和来源回看有历史证据；需刷新编辑、重裁、audit 证据 | NS404-NS406 |
| real-guangzhou-2015 | ui_productized | repo_landed | 2015 1-24 题有 DB/UI smoke；仍需教师现场验收，不可说课堂可用 | REAL005 / NS902 |
| real-guangzhou-2015-2025 | contract_done | contract_only | REAL005 当前仍是 `not_closed`；不得宣称全流程完成 | REAL005 / NS308 |
| ai-extraction | synthetic_done | contract_only | AI 提炼仍只能作候选；没有生产写入资格 | NS502 / NS503 |
| ai-tagging | teacher_validated | repo_landed | AI 标注建议有历史审核证据；需刷新 no-active-write 和人工确认证据 | NS504 / NS505 |
| review-queue | teacher_validated | repo_landed | 审核队列有历史证据；需当前并发、审计和权限 smoke | NS402 / NS201 |
| question-search | teacher_validated | repo_landed | 检索题卡有历史证据；需刷新 active C002 查询和 UI 证据 | NS601 / NS602 |
| paper-assembly | teacher_validated | repo_landed | 组卷和题篮有历史证据；需刷新持久化、换题、撤销证据 | NS603-NS605 |
| paper-export | teacher_validated | repo_landed | Word/PDF 导出有历史证据；需刷新当前 artifact regression | NS606 / NS607 |
| score-import | teacher_validated | repo_landed | 成绩导入有历史证据；需刷新 Excel 模板和异常行证据 | NS701 / NS702 |
| analysis-report | teacher_validated | repo_landed | 学情分析有历史证据；需刷新指标、报告和隐私审计 | NS703-NS705 |
| backup-restore | teacher_validated | repo_landed | 备份恢复有历史演练；需刷新当前 manifest/restore/upgrade | NS801 / NS802 / NS806 |
| deployment-install | contract_done | contract_only | 安装部署仍未隔离机执行，不能发布使用 | NS803 / NS804 |
| auth-audit | contract_done | contract_only | 权限审计有合同，需随真实工作流逐项刷新 | NS201 / NS202 |
| live-pilot | contract_done | blocked_by_onsite | 现场与发布不能由本机会话替代 | NS1001-NS1005 |
| multi-subject | contract_done | planned | v0.1 主链稳定前不扩科 | NS1101-NS1104 |
| advanced-platform | contract_done | planned | 只在真实瓶颈或发布后 evidence 出现时触发 | NS1201-NS1206 |

## Counts

| 新前向状态 | 数量 |
|---|---:|
| planned | 2 |
| contract_only | 5 |
| repo_landed | 16 |
| runtime_verified | 0 |
| non_site_validated | 0 |
| blocked_by_onsite | 1 |

## Decision

本次重基线后，前向执行不再把旧 `teacher_validated` 当作当前可用结论。下一步应从 `NS101-NS106` 和 `NS201-NS204` 开始刷新运行底座、安全守卫和模块归属，再逐步把 `repo_landed` 模块推进到 `runtime_verified` / `non_site_validated`。

## Verification

```powershell
@'
import csv, json
from pathlib import Path
rows = list(csv.DictReader(Path('tasks/completion-state-dashboard.csv').open(encoding='utf-8-sig')))
print(json.dumps([{k: r[k] for k in ['area_id','area','user_visible','current_state','usable_today','blocking_gap','next_task','risk_level']} for r in rows], ensure_ascii=False, indent=2))
'@ | python -
```

结果：读取到 24 个 area；本文件按上述保守规则完成映射。

## Gate N/A

- `build`: gate_na
  - reason: 本轮只生成状态重基线报告，不修改业务代码。
  - alternative_verification: CSV 读取、人工映射、后续 roadmap guard。
  - evidence_link: `docs/evidence/20260528-ns0-state-rebaseline.md`
  - expires_at: 进入 NS101 运行底座刷新时。
- `test`: gate_na
  - reason: 本轮不改变 API/UI/worker 行为。
  - alternative_verification: `tasks/completion-state-dashboard.csv` 读取和映射复核。
  - evidence_link: `docs/evidence/20260528-ns0-state-rebaseline.md`
  - expires_at: 进入 NS101 或 NS201 实现/验证任务时。
- `hotspot`: gate_na
  - reason: 本轮不做教师 workflow runtime 测试。
  - alternative_verification: 前向计划要求每个模块重新取得 runtime 或 E2E 证据。
  - evidence_link: `docs/evidence/20260528-ns0-state-rebaseline.md`
  - expires_at: 进入 NS902 非现场端到端演练前。

## Rollback

```powershell
git restore -- docs/evidence/20260528-ns0-state-rebaseline.md tasks/non-site-implementation-plan.csv
```

