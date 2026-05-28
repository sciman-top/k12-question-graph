# NS005 · 授权/脱敏材料 fixture 政策证据

日期：2026-05-28。

## Goal

为非现场落地路线图建立数据边界：明确 synthetic fixture、授权脱敏材料、真实来源资料、真实学生数据和公开材料的用途、禁止边界、AI 使用限制和完成态判定。

## Changes

- 新增 `docs/102_NonSiteFixturePrivacyPolicy.md`，作为 NS005、NS203、NS705、NS901、NS902 的共同政策入口。
- 更新 `tests/golden-import/privacy_and_license.md`，把 B007 golden import 样例明确收口到 `synthetic_fixture`。
- 新增 `sources/raw/.gitignore`，把 `sources/raw/` 定义为本机暂存区并默认禁止原始资料入 Git。
- 更新 `tasks/non-site-implementation-plan.csv`，将 NS005 标记为 `repo_landed` 并指向本证据。

## Verification

- `rg -n "102_NonSiteFixturePrivacyPolicy|synthetic_fixture|authorized_anonymized_material|sources/raw" docs tests sources tasks`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-non-site-implementation-plan-guard.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/run-gate-group.ps1 -Group roadmap`

## Gate NA

- `build`: `gate_na`，原因：本轮只新增文档、CSV 状态和 `.gitignore`，不修改 .NET/前端/worker 代码；替代验证为 roadmap group 和非现场计划 guard；过期条件：进入 NS101/NS102 或任意代码 slice 时恢复真实 build。
- `test`: `gate_na`，原因同上；替代验证为 CSV/guard 解析和 roadmap group；过期条件：进入运行底座或功能代码 slice 时恢复 full gate。
- `hotspot`: `gate_na`，原因：本轮热点是政策边界，不存在独立性能热点命令；替代验证为隐私/授权检查清单和后续 NS203 扫描；过期条件：进入真实资料、外部 AI、成绩数据或文件导入实现时恢复专项扫描。

## Risk

风险等级：低。没有真实资料、学生数据、数据库、外部 AI、active switch、备份或权限变更。

## Rollback

```powershell
git restore -- docs/102_NonSiteFixturePrivacyPolicy.md tests/golden-import/privacy_and_license.md tasks/non-site-implementation-plan.csv
git clean -f -- docs/evidence/20260528-ns005-fixture-policy.md sources/raw/.gitignore
```

