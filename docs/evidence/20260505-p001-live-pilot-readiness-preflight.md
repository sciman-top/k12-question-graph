# 20260505 P001 live pilot readiness preflight

## 目标
- 在不伪造现场实跑的前提下，为 `P001` 建立可执行 preflight 合同与 release checklist。

## 结论
- `P001` 仍保持 `待办`，本轮不改完成态。
- `O004B`、`O006`、`O007` 前置项已在 backlog 标记为 `已完成`，可作为现场预演的依赖。
- 已新增 `tools/run-p001-live-pilot-readiness-preflight-contract.ps1` 与 `docs/templates/p001-live-pilot-release-checklist.md`。

## 本轮边界
- 本轮仅做 preflight，不在当前主机执行隔离机器部署预演。
- 本轮不触发真实试点数据导入，不执行现场教师验收。

## N/A 记录
- `platform_na`:
  - reason: 当前会话主机不是目标隔离机器，无法形成 P001 现场部署证据。
  - alternative_verification: 运行 preflight contract，确认依赖、清单和证据入口完备。
  - evidence_link: `docs/evidence/20260505-p001-live-pilot-readiness-preflight.md`
  - expires_at: `2026-05-20`
- `gate_na`:
  - reason: P001 验收要求包含隔离机器安装向导与现场入口 smoke，不属于本机 dry-run 可替代范围。
  - alternative_verification: 先完成 preflight checklist 与 contract，待隔离机执行后回填正式 evidence。
  - evidence_link: `docs/templates/p001-live-pilot-release-checklist.md`
  - expires_at: `2026-05-20`

## 下一步
1. 在隔离机器按 checklist 执行安装向导、备份、恢复、权限审计和四入口 smoke。
2. 回填现场 evidence 后再将 `P001` 从 `待办` 切到 `已完成`。
